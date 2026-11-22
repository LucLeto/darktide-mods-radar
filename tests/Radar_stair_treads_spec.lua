-- The stair marks of the live navmesh: which slopes are marked (flat facets that climb far enough and lead
-- somewhere), where their lines and bands go, how the build keeps to its budgets and starts over, and how a
-- frame draws them as lines, stripes or shading, fades them, thins them out and clips them. Loads the real
-- `ui/Radar_stair_treads.lua` and `ui/Radar_triangle_clipper.lua` against a fake GUI, `Vector3`, `Color` and
-- mod, with navmesh geometry in the shape `Radar_navmesh.lua` builds.

local MODULE_PATH = "Radar/scripts/mods/Radar/ui/Radar_stair_treads.lua"
local CENTER_X, CENTER_Y = 110, 310
local UI_SCALE = 4 / 3
local PROJECTION_RADIUS = 142
local LAYER = 103
local CURRENT_COLOR = { 80, 101, 133, 96 }
local ABOVE_COLOR = { 32, 120, 150, 185 }
local BELOW_COLOR = { 55, 140, 98, 76 }
local EPSILON = 1e-6

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assert_true(value, message)
    if value ~= true then
        error(message or "expected true", 2)
    end
end

local function assert_near(expected, actual, tolerance, message)
    if math.abs(expected - actual) > tolerance then
        error(string.format("%s: expected %.6f, got %.6f", message or "values differ", expected, actual), 2)
    end
end

local function upvalue(fn, name)
    for i = 1, 200 do
        local key, value = debug.getupvalue(fn, i)

        if key == nil then
            break
        end

        if key == name then
            return value
        end
    end

    error("no upvalue " .. name)
end

-- ----------------------------------------------------------------------------
-- Geometry
-- ----------------------------------------------------------------------------

local function bucket_key(cell_x, cell_y)
    return (cell_x + 32768) * 65536 + cell_y + 32768
end

--- Navmesh geometry from a list of triangles `{ x1, y1, z1, x2, y2, z2, x3, y3, z3 }`, with the centres,
-- radii and 16 m buckets `Radar_navmesh.lua` adds.
local function new_geometry(triangles, revision)
    local geometry = {
        ax = {}, ay = {}, az = {},
        bx = {}, by = {}, bz = {},
        cx = {}, cy = {}, cz = {},
        mid_x = {}, mid_y = {}, mid_z = {},
        radius = {},
        count = #triangles,
        max_radius = 0,
        cell_size = 16,
        buckets = {},
        revision = revision or 1,
    }

    for i = 1, #triangles do
        local t = triangles[i]
        local mid_x = (t[1] + t[4] + t[7]) / 3
        local mid_y = (t[2] + t[5] + t[8]) / 3
        local radius = 0

        geometry.ax[i], geometry.ay[i], geometry.az[i] = t[1], t[2], t[3]
        geometry.bx[i], geometry.by[i], geometry.bz[i] = t[4], t[5], t[6]
        geometry.cx[i], geometry.cy[i], geometry.cz[i] = t[7], t[8], t[9]
        geometry.mid_x[i], geometry.mid_y[i] = mid_x, mid_y
        geometry.mid_z[i] = (t[3] + t[6] + t[9]) / 3

        for v = 0, 2 do
            local dx, dy = t[v * 3 + 1] - mid_x, t[v * 3 + 2] - mid_y

            radius = math.max(radius, math.sqrt(dx * dx + dy * dy))
        end

        geometry.radius[i] = radius
        geometry.max_radius = math.max(geometry.max_radius, radius)

        local cell_x, cell_y = math.floor(mid_x / 16), math.floor(mid_y / 16)
        local key = bucket_key(cell_x, cell_y)
        local bucket = geometry.buckets[key]

        if not bucket then
            bucket = { cell_x = cell_x, cell_y = cell_y }
            geometry.buckets[key] = bucket
        end

        bucket[#bucket + 1] = i
    end

    return geometry
end

--- A rectangle climbing along +y from `z0` at `y0` to `z1` at `y1`, as two triangles.
local function ramp(out, x0, y0, x1, y1, z0, z1)
    out[#out + 1] = { x0, y0, z0, x1, y0, z0, x1, y1, z1 }
    out[#out + 1] = { x0, y0, z0, x1, y1, z1, x0, y1, z1 }
end

local function flat(out, x0, y0, x1, y1, z)
    ramp(out, x0, y0, x1, y1, z, z)
end

--- A rectangle on the plane `z = gx * x + gy * y`, as two triangles.
local function plane(out, x0, y0, x1, y1, gx, gy)
    local function z(x, y)
        return gx * x + gy * y
    end

    out[#out + 1] = { x0, y0, z(x0, y0), x1, y0, z(x1, y0), x1, y1, z(x1, y1) }
    out[#out + 1] = { x0, y0, z(x0, y0), x1, y1, z(x1, y1), x0, y1, z(x0, y1) }
end

--- A flight between two floors: a ramp with a 2 m landing below its foot and another above its head.
local function flight(out, x0, y0, x1, y1, z0, z1)
    flat(out, x0, y0 - 2, x1, y0, z0)
    ramp(out, x0, y0, x1, y1, z0, z1)
    flat(out, x0, y1, x1, y1 + 2, z1)
end

-- ----------------------------------------------------------------------------
-- Harness
-- ----------------------------------------------------------------------------

--- Loads a fresh module and clipper against fakes; `harness.emitted` records each `Gui.triangle` call.
-- Like the engine's, a fake `Color` is only valid in the frame it was made in; each colour carries the
-- frame, and `harness.stale` counts triangles drawn with a colour from another frame.
local function new_harness()
    local harness = { emitted = {}, logs = {}, settings = {}, colors_made = 0, frame = 0, stale = 0 }
    local mod = {}
    local previous = { get_mod = rawget(_G, "get_mod"), Gui = rawget(_G, "Gui"), Vector3 = rawget(_G, "Vector3"),
        Color = rawget(_G, "Color") }

    function mod:get(id)
        return harness.settings[id]
    end

    function mod:info(message)
        harness.logs[#harness.logs + 1] = message
    end

    function mod:io_dofile(path)
        return assert(loadfile(path .. ".lua"))()
    end

    --- The buckets of the geometry being built, centre cell and rings, as `Radar_navmesh.lua` returns them.
    function mod:get_navmesh_nearby_buckets(x, y, range, out)
        local geometry = harness.build.geometry
        local reach = math.floor((range or 0) / 16) + 1
        local center_x, center_y = math.floor(x / 16), math.floor(y / 16)
        local n = 0

        for cell_x = center_x - reach, center_x + reach do
            for cell_y = center_y - reach, center_y + reach do
                local bucket = geometry.buckets[bucket_key(cell_x, cell_y)]

                if bucket then
                    n = n + 1
                    out[n] = bucket
                end
            end
        end

        return n
    end

    rawset(_G, "get_mod", function()
        return mod
    end)
    rawset(_G, "Vector3", function(x, _, z)
        return { x, z }
    end)
    rawset(_G, "Color", function(a, r, g, b)
        harness.colors_made = harness.colors_made + 1

        return { a, r, g, b, frame = harness.frame }
    end)
    rawset(_G, "Gui", {
        triangle = function(_, a, b, c, layer, color)
            if type(color) ~= "table" or color.frame ~= harness.frame then
                harness.stale = harness.stale + 1
            end

            harness.emitted[#harness.emitted + 1] = { a[1], a[2], b[1], b[2], c[1], c[2], layer = layer, color = color }
        end,
    })

    harness.treads = assert(loadfile(MODULE_PATH))()

    for name, value in pairs(previous) do
        rawset(_G, name, value)
    end

    harness.build = upvalue(harness.treads.update, "_build")
    harness.lines = upvalue(harness.treads.draw, "_lines")
    harness.bands = upvalue(harness.treads.draw, "_bands")
    harness.selection = upvalue(harness.treads.draw, "_selection")

    --- Runs updates until the build is ready, returning the number of frames it took.
    function harness.build_all(geometry)
        local frames = 0

        repeat
            frames = frames + 1
            assert_true(frames < 1000, "the build never finished")
        until harness.treads.update(geometry)

        return frames
    end

    --- Draws one frame north-up around `player` and returns what was emitted.
    function harness.draw(player, options)
        options = options or {}

        local range = options.range or 25
        local scale = PROJECTION_RADIUS / range

        harness.frame = harness.frame + 1
        harness.emitted = {}
        harness.drawn = harness.treads.draw({}, LAYER, options.style, options.color or CURRENT_COLOR,
            options.above or ABOVE_COLOR, options.below or BELOW_COLOR, options.reselect == true, player.x, player.y,
            player.z, scale, 0, 0, -scale, scale, options.circle == true, PROJECTION_RADIUS, UI_SCALE, CENTER_X,
            CENTER_Y, range)
        assert_equal(0, harness.stale, "a mark was drawn with a colour made in an earlier frame")

        return harness.emitted
    end

    return harness
end

--- Builds a fresh module on a list of triangles and returns the harness.
local function built(triangles)
    local harness = new_harness()

    harness.build_all(new_geometry(triangles))

    return harness
end

--- The stored lines as `{ x1, y1, x2, y2, z }` records.
local function stored_lines(harness)
    local lines = harness.lines
    local out = {}

    for i = 1, lines.count do
        out[i] = { lines.x1[i], lines.y1[i], lines.x2[i], lines.y2[i], lines.z[i] }
    end

    return out
end

--- Heights of the stored lines, each once, in order.
local function line_heights(harness)
    local seen, list = {}, {}

    for _, line in ipairs(stored_lines(harness)) do
        if not seen[line[5]] then
            seen[line[5]] = true
            list[#list + 1] = line[5]
        end
    end

    table.sort(list)

    return list
end

local function triangle_area(x1, y1, x2, y2, x3, y3)
    return math.abs((x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)) * 0.5
end

--- Area of the stored band pieces by height step.
local function stored_band_area(harness)
    local bands = harness.bands
    local by_step = {}

    for i = 1, bands.count do
        local step = bands.step[i]

        assert_near((step + 0.5) * 0.5, bands.z[i], EPSILON, "a band piece's middle height")
        by_step[step] = (by_step[step] or 0)
            + triangle_area(bands.x1[i], bands.y1[i], bands.x2[i], bands.y2[i], bands.x3[i], bands.y3[i])
    end

    return by_step
end

--- The drawn quads back as world lines, `{ x1, y1, x2, y2, color }`, for a north-up draw around `player`.
local function drawn_lines(emitted, player, range)
    local scale = PROJECTION_RADIUS / (range or 25)
    local out = {}

    assert_equal(0, #emitted % 2, "a line is not two triangles")

    for k = 1, #emitted, 2 do
        local first, second = emitted[k], emitted[k + 1]
        local sx1 = (first[1] + second[5]) * 0.5 / UI_SCALE - CENTER_X
        local sy1 = (first[2] + second[6]) * 0.5 / UI_SCALE - CENTER_Y
        local sx2 = (first[3] + first[5]) * 0.5 / UI_SCALE - CENTER_X
        local sy2 = (first[4] + first[6]) * 0.5 / UI_SCALE - CENTER_Y
        local width = math.sqrt((first[3] - first[5]) ^ 2 + (first[4] - first[6]) ^ 2)

        assert_equal(LAYER, first.layer, "a line was drawn on another layer")
        assert_true(first.color == second.color, "the two halves of a line differ in colour")
        out[#out + 1] = { player.x + sx1 / scale, player.y - sy1 / scale, player.x + sx2 / scale,
            player.y - sy2 / scale, first.color, sx1 = sx1, sy1 = sy1, sx2 = sx2, sy2 = sy2, width = width }
    end

    return out
end

--- The drawn triangles back in world space, `{ x1, y1, x2, y2, x3, y3, color, area = ..., y = ... }`.
local function drawn_pieces(emitted, player, range)
    local scale = PROJECTION_RADIUS / (range or 25)
    local out = {}

    for k = 1, #emitted do
        local e = emitted[k]
        local piece = { color = e.color }

        assert_equal(LAYER, e.layer, "a band piece was drawn on another layer")

        for v = 0, 2 do
            piece[v * 2 + 1] = player.x + (e[v * 2 + 1] / UI_SCALE - CENTER_X) / scale
            piece[v * 2 + 2] = player.y - (e[v * 2 + 2] / UI_SCALE - CENTER_Y) / scale
        end

        piece.area = triangle_area(piece[1], piece[2], piece[3], piece[4], piece[5], piece[6])
        piece.y = (piece[2] + piece[4] + piece[6]) / 3
        out[#out + 1] = piece
    end

    return out
end

--- Drawn area by height step on the flight from 0 m at y = 0 to 4 m at y = 6, with the colour of each step.
-- Slivers the clipper leaves where a piece only touches the radar edge cover nothing and are skipped.
local function drawn_steps(emitted, player, range)
    local area, colors = {}, {}

    for _, piece in ipairs(drawn_pieces(emitted, player, range)) do
        if piece.area > 1e-9 then
            local step = math.floor(piece.y / 1.5 / 0.5)

            area[step] = (area[step] or 0) + piece.area

            if colors[step] then
                assert_true(colors[step] == piece.color, "the pieces of step " .. step .. " differ in colour")
            end

            colors[step] = piece.color
        end
    end

    return area, colors
end

local function brighten(channel, amount)
    return math.floor(channel + (255 - channel) * amount + 0.5)
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

-- ----------------------------------------------------------------------------
-- Which slopes are marked
-- ----------------------------------------------------------------------------

test("a flight between two floors gets even lines and bands across it, and floors, kerbs, short climbs and"
    .. " gentle slopes get none", function()
    local triangles = {}

    flight(triangles, 0, 0, 2, 6, 0, 4)

    -- The ramp's second triangle winds the other way, as a navmesh may.
    local t = triangles[4]

    triangles[4] = { t[1], t[2], t[3], t[7], t[8], t[9], t[4], t[5], t[6] }
    flat(triangles, -10, -10, -2, -2, 0)
    flight(triangles, 10, 0, 12, 0.4, 0, 0.3)
    flight(triangles, 20, 0, 22, 2.1, 0, 1.4)
    flight(triangles, 30, 0, 32, 23, 0, 2)

    local harness = built(triangles)
    local heights = line_heights(harness)

    assert_equal(8, #heights, "the flight's line heights")

    for k = 1, 8 do
        assert_near(k * 0.5, heights[k], EPSILON, "line height " .. k)
    end

    local covered = {}

    for _, line in ipairs(stored_lines(harness)) do
        assert_true(line[1] >= -EPSILON and line[3] <= 2 + EPSILON and line[1] <= 2 + EPSILON,
            "a line left the flight")
        assert_near(line[2], line[4], EPSILON, "a line does not run across the climb")
        assert_near(line[5] * 1.5, line[2], EPSILON, "a line is not at its height on the flight")
        covered[line[5]] = (covered[line[5]] or 0) + math.abs(line[3] - line[1])
    end

    for z, width in pairs(covered) do
        assert_near(2, width, EPSILON, "the line at " .. z .. " m does not cross the whole flight")
    end

    local area = stored_band_area(harness)

    for step = 0, 7 do
        assert_near(1.5, area[step] or 0, EPSILON, "the band of step " .. step .. " does not tile its part of the flight")
    end

    for step in pairs(area) do
        assert_true(step >= 0 and step <= 7, "a band of step " .. step .. " lies off the flight")
    end
end)

test("a slope is marked only when it leads somewhere, with floor just past its head and just below its foot",
    function()
        local function marked(build_scene)
            local triangles = {}

            build_scene(triangles)

            return built(triangles).lines.count > 0
        end

        assert_equal(true, marked(function(out)
            flight(out, 0, 0, 2, 6, 0, 4)
        end), "a flight between two floors")
        assert_equal(true, marked(function(out)
            flat(out, 0, -2, 2, 0, 0)
            out[#out + 1] = { 0, 0, 0, 2, 0, 0, 1, 6, 4 }
            flat(out, 0, 6, 2, 8, 4)
        end), "a flight of one triangle between two floors")
        assert_equal(false, marked(function(out)
            ramp(out, 0, 0, 2, 6, 0, 4)
        end), "a berm with no floor at either end")
        assert_equal(false, marked(function(out)
            flat(out, 0, -2, 2, 0, 0)
            ramp(out, 0, 0, 2, 6, 0, 4)
        end), "a slope that climbs into nothing")
        assert_equal(false, marked(function(out)
            ramp(out, 0, 0, 2, 6, 0, 4)
            flat(out, 0, 6, 2, 8, 4)
        end), "a slope that starts in the air")

        local cases = {
            { top = 0.75, bottom = 0, expected = true, name = "a floor 0.75 m above the head" },
            { top = 0.85, bottom = 0, expected = false, name = "a ledge 0.85 m above the head" },
            { top = -0.35, bottom = 0, expected = true, name = "a floor 0.35 m below the head" },
            { top = -0.45, bottom = 0, expected = false, name = "a drop 0.45 m below the head" },
            { top = 0, bottom = -0.75, expected = true, name = "a floor 0.75 m below the foot" },
            { top = 0, bottom = -0.85, expected = false, name = "a drop 0.85 m below the foot" },
            { top = 0, bottom = 0.35, expected = true, name = "a floor 0.35 m above the foot" },
            { top = 0, bottom = 0.45, expected = false, name = "a wall 0.45 m above the foot" },
        }

        for _, case in ipairs(cases) do
            assert_equal(case.expected, marked(function(out)
                flat(out, 0, -2, 2, 0, case.bottom)
                ramp(out, 0, 0, 2, 6, 0, 4)
                flat(out, 0, 6, 2, 8, 4 + case.top)
            end), case.name)
        end

        assert_equal(true, marked(function(out)
            flat(out, 0, -2, 2, 0, 0)
            ramp(out, 0, 0, 2, 6, 0, 4)
            flat(out, 0, 6.55, 2, 8.55, 4)
        end), "a floor starting 0.55 m past the head")
        assert_equal(false, marked(function(out)
            flat(out, 0, -2, 2, 0, 0)
            ramp(out, 0, 0, 2, 6, 0, 4)
            flat(out, 0, 6.65, 2, 8.65, 4)
        end), "a floor starting 0.65 m past the head")

        -- A slope 10 m wide, climbing 2.5 m, has six corners at its head; floor past two of them is enough, past
        -- one is not.
        local function wide(landing_width)
            return function(out)
                flat(out, 0, -2, 10, 0, 0)

                for k = 0, 4 do
                    ramp(out, k * 2, 0, k * 2 + 2, 6, 0, 2.5)
                end

                flat(out, 0, 6, landing_width, 8, 2.5)
            end
        end

        assert_equal(true, marked(wide(2)), "floor past two of six corners")
        assert_equal(false, marked(wide(1)), "floor past one of six corners")

        -- The same slope with a corner halfway along each 2 m of its head edge, so eight of its eleven head corners
        -- are probed against six at its foot: floor past two of the eight is too few, past three is enough.
        local function fine_head(landing_width)
            return function(out)
                flat(out, 0, -2, 10, 0, 0)

                for k = 0, 4 do
                    local x0, x1 = k * 2, k * 2 + 2

                    out[#out + 1] = { x0, 0, 0, x1, 0, 0, x1, 6, 2.5 }
                    out[#out + 1] = { x0, 0, 0, x1, 6, 2.5, x0 + 1, 6, 2.5 }
                    out[#out + 1] = { x0, 0, 0, x0 + 1, 6, 2.5, x0, 6, 2.5 }
                end

                flat(out, 0, 6, landing_width, 8, 2.5)
            end
        end

        assert_equal(false, marked(fine_head(1.5)), "floor past two of eight probed head corners")
        assert_equal(true, marked(fine_head(2.5)), "floor past three of eight probed head corners")

        -- The head's probe points lie in one bucket cell and the floor's triangles have their centres in the next.
        assert_equal(true, marked(function(out)
            flat(out, 0, 6, 2, 8, 0)
            ramp(out, 0, 8, 2, 15, 0, 4.5)
            flat(out, 0, 15, 2, 19, 4.5)
        end), "a floor whose triangles are filed in the neighbouring cell")
    end)

test("each corner at a slope's head and foot is probed once, and at most eight at either end", function()
    local triangles = {}

    flight(triangles, 0, 0, 2, 6, 0, 4)

    local harness = built(triangles)

    assert_equal(4, harness.build.probe_n, "probes of a flight's two head and two foot corners")

    triangles = {}
    flat(triangles, 0, -2, 24, 0, 0)

    for k = 0, 11 do
        ramp(triangles, k * 2, 0, k * 2 + 2, 6, 0, 4)
    end

    flat(triangles, 0, 6, 24, 8, 4)
    harness = built(triangles)
    assert_equal(16, harness.build.probe_n, "probes of a slope with 13 corners at either end")
    assert_true(harness.lines.count > 0, "the wide slope was not marked")

    -- The head edge runs at a slant, its left corner 0.4 m below the right one along the climb, and the landing
    -- lies past the left corner only. Both corners are within the 0.5 m band, so one of two probes finds it.
    local function slanted(left_y)
        local out = {}
        local function point(x, y)
            return x, y, 0.6 * y
        end
        local ax, ay, az = point(0, 0)
        local bx, by, bz = point(2, 0)
        local cx, cy, cz = point(2, 3.4)
        local dx, dy, dz = point(0, left_y)
        local ex, ey = 0.8, left_y + (3.4 - left_y) * 0.4

        flat(out, 0, -2, 2, 0, 0)
        out[#out + 1] = { ax, ay, az, bx, by, bz, cx, cy, cz }
        out[#out + 1] = { ax, ay, az, cx, cy, cz, dx, dy, dz }
        out[#out + 1] = { -1, left_y, dz, dx, dy, dz, ex, ey, dz }
        out[#out + 1] = { -1, left_y, dz, ex, ey, dz, ex, left_y + 2, dz }
        out[#out + 1] = { -1, left_y, dz, ex, left_y + 2, dz, -1, left_y + 2, dz }

        return out
    end

    harness = built(slanted(3))
    assert_equal(4, harness.build.probe_n, "probes of a slanted head edge and a straight foot")
    assert_true(harness.lines.count > 0, "a landing past part of a slanted head edge was not found")
    assert_equal(0, built(slanted(2.85)).lines.count, "a head corner 0.55 m below the top was probed")

    -- A 6 m wide flight with four head corners, whose landing lies past the left one only, as on a flight entered
    -- from the side. One of four is too few for a flight climbing 2.5 m, but enough for one climbing 3 m or more.
    local function side_landing(rise, landing)
        local out = {}

        flat(out, 0, -2, 6, 0, 0)

        for k = 0, 2 do
            ramp(out, k * 2, 0, k * 2 + 2, 6, 0, rise)
        end

        if landing then
            flat(out, -2, 6, 0.5, 8, rise)
        end

        return out
    end

    harness = built(side_landing(3, true))
    assert_equal(8, harness.build.probe_n, "probes of a flight with four corners at either end")
    assert_true(harness.lines.count > 0, "a 3 m flight with a landing past one of four head corners was not marked")
    assert_equal(0, built(side_landing(2.5, true)).lines.count, "a 2.5 m flight needed only one head corner with floor")
    assert_equal(0, built(side_landing(4, false)).lines.count, "a 4 m slope with no floor past its head was marked")
end)

test("a facet grows over triangles of one slope, so a climb split into parts counts whole, while uneven"
    .. " ground, rubble and a curved tunnel side break into facets that climb too little", function()
    local triangles = {}

    flat(triangles, 0, -2, 2, 0, 0)
    ramp(triangles, 0, 0, 2, 1.5, 0, 1)
    ramp(triangles, 0, 1.5, 2, 3, 1, 2)
    flat(triangles, 0, 3, 2, 5, 2)

    assert_equal(4, #line_heights(built(triangles)), "a 2 m climb over two 1 m parts")

    triangles = {}
    flight(triangles, 0, 0, 2, 1.5, 0, 1)
    assert_equal(0, built(triangles).lines.count, "a 1 m climb")

    -- A 1.2 m part at 0.6 m per metre, then 0.75 m twice as steep, within the ratio, or three times, beyond it.
    -- Neither part climbs 1.5 m alone.
    -- With `steep_first` the steeper part's triangles come first, so the facet starts there.
    local function bent(second_slope, steep_first)
        local out = {}
        local head = 1.2 + 0.75 * second_slope

        flat(out, 0, -2, 2, 0, 0)

        if steep_first then
            ramp(out, 0, 2, 2, 2.75, 1.2, head)
            ramp(out, 0, 0, 2, 2, 0, 1.2)
        else
            ramp(out, 0, 0, 2, 2, 0, 1.2)
            ramp(out, 0, 2, 2, 2.75, 1.2, head)
        end

        flat(out, 0, 2.75, 2, 4.75, head)

        return out
    end

    assert_equal(4, #line_heights(built(bent(1.2))), "two parts, the second twice as steep")
    assert_equal(0, built(bent(1.8)).lines.count, "two parts, the second three times as steep")
    assert_equal(4, #line_heights(built(bent(1.2, true))), "a part half as steep joining a steep one")
    assert_equal(0, built(bent(1.8, true)).lines.count, "a part a third as steep joining a steep one")

    -- Two halves of a climb side by side, as steep, whose uphill directions turn 25 or 35 degrees apart.
    local function folded(degrees)
        local out = {}
        local half = math.rad(degrees) / 2

        plane(out, -2, 0, 0, 3, -0.6 * math.sin(half), 0.6 * math.cos(half))
        plane(out, 0, 0, 2, 3, 0.6 * math.sin(half), 0.6 * math.cos(half))

        return out
    end

    assert_equal(1, built(folded(25)).build.facet_count, "two halves turning 25 degrees apart")
    assert_equal(2, built(folded(35)).build.facet_count, "two halves turning 35 degrees apart")
    assert_equal(2, built(folded(180)).build.facet_count, "two halves climbing away from each other")

    -- The facet's mean follows a slope that steepens part by part from 0.4 to 1.15 m per metre, almost three
    -- times the foot's, and the whole climb stays one facet.
    triangles = {}
    flat(triangles, 0, -2, 2, 0, 0)

    local z = 0

    for part, slope in ipairs({ 0.4, 0.55, 0.7, 0.85, 1, 1.15 }) do
        ramp(triangles, 0, part - 1, 2, part, z, z + slope)
        z = z + slope
    end

    flat(triangles, 0, 6, 2, 8, z)

    local gradual = built(triangles)

    assert_equal(1, gradual.build.facet_count, "a slope that steepens gradually broke into facets")
    assert_equal(9, #line_heights(gradual), "a slope that steepens gradually")

    triangles = {}
    flight(triangles, 10, 0, 12, 11.4, 0, 2)

    local ys, seen = {}, {}

    for _, line in ipairs(stored_lines(built(triangles))) do
        local key = string.format("%.4f", line[2])

        if not seen[key] then
            seen[key] = true
            ys[#ys + 1] = line[2]
        end
    end

    table.sort(ys)
    assert_true(#ys >= 2, "the 10 degree ramp got fewer than two lines")
    assert_near(11.4 / 4, ys[2] - ys[1], 1e-3, "the gentle ramp's lines are not 0.5 m of height apart")

    triangles = {}

    local heights = {}

    math.randomseed(7)

    for i = 0, 8 do
        heights[i] = {}

        for j = 0, 8 do
            heights[i][j] = math.random() * 1.6
        end
    end

    for i = 0, 7 do
        for j = 0, 7 do
            local x, y = 20 + i, j
            local a, b = { x, y, heights[i][j] }, { x + 1, y, heights[i + 1][j] }
            local c, d = { x + 1, y + 1, heights[i + 1][j + 1] }, { x, y + 1, heights[i][j + 1] }

            triangles[#triangles + 1] = { a[1], a[2], a[3], b[1], b[2], b[3], c[1], c[2], c[3] }
            triangles[#triangles + 1] = { a[1], a[2], a[3], c[1], c[2], c[3], d[1], d[2], d[3] }
        end
    end

    local radius = 6
    local strips = 12

    for k = 0, strips - 1 do
        local a0, a1 = k / strips * math.pi / 3, (k + 1) / strips * math.pi / 3
        local y0, z0 = radius * math.sin(a0), radius * (1 - math.cos(a0))
        local y1, z1 = radius * math.sin(a1), radius * (1 - math.cos(a1))

        for x = 40, 48, 2 do
            triangles[#triangles + 1] = { x, y0, z0, x + 2, y0, z0, x + 2, y1, z1 }
            triangles[#triangles + 1] = { x, y0, z0, x + 2, y1, z1, x, y1, z1 }
        end
    end

    flat(triangles, 40, -4, 50, 0, 0)
    flight(triangles, 0, 0, 2, 6, 0, 4)

    local harness = built(triangles)
    local stray, stair_pieces = 0, 0

    for _, line in ipairs(stored_lines(harness)) do
        if line[1] >= 19 then
            stray = stray + math.sqrt((line[3] - line[1]) ^ 2 + (line[4] - line[2]) ^ 2)
        else
            stair_pieces = stair_pieces + 1
        end
    end

    assert_equal(8, stair_pieces, "the flight beside the rubble and the tunnel lost lines")
    assert_true(stray < 3, string.format("the rubble and the tunnel side got %.1f m of lines", stray))

    for i = 1, harness.bands.count do
        assert_true(harness.bands.x1[i] < 19, "a band was made on the rubble or the tunnel side")
    end
end)

-- ----------------------------------------------------------------------------
-- Lines
-- ----------------------------------------------------------------------------

test("the pieces of one height across neighbouring triangles join into one line, stored once at a seam",
    function()
        local triangles = {}

        flat(triangles, 0, -2, 2, 0, 0)
        ramp(triangles, 0, 0, 2, 6, 0, 4)
        ramp(triangles, 0, 6, 2, 9, 4, 6)
        flat(triangles, 0, 9, 2, 11, 6)

        local harness = built(triangles)
        local lines = stored_lines(harness)

        assert_equal(8 + 4, #lines, "the lines of the flight and of its upper part")
        assert_equal(7 + 3, harness.build.joined, "pieces joined across the diagonals")

        local at_seam = 0

        for _, line in ipairs(lines) do
            assert_near(2, math.abs(line[3] - line[1]), EPSILON, "a line at " .. line[5] .. " m does not cross the flight")

            if math.abs(line[5] - 4) < EPSILON then
                at_seam = at_seam + 1
            end
        end

        assert_equal(1, at_seam, "the line on the seam between the two parts was not stored once")

        local base = {}

        flat(base, 0, -2, 2, 0, 0)
        ramp(base, 0, 0, 2, 3, 0, 2)
        ramp(base, 0, 3, 2, 6, 2, 4)
        flat(base, 0, 6, 2, 8, 4)

        for rotation = 0, 2 do
            local rotated_triangles = {}

            for i = 1, #base do
                local t = base[i]
                local rotated = {}

                for v = 0, 2 do
                    local from = (v + rotation) % 3

                    rotated[v * 3 + 1], rotated[v * 3 + 2], rotated[v * 3 + 3] =
                        t[from * 3 + 1], t[from * 3 + 2], t[from * 3 + 3]
                end

                rotated_triangles[i] = rotated
            end

            local rotated_harness = built(rotated_triangles)
            local seam = 0
            local per_height = {}

            for _, line in ipairs(stored_lines(rotated_harness)) do
                if math.abs(line[5] - 2) < EPSILON then
                    assert_near(3, line[2], EPSILON, "the line at 2 m is off the seam")
                    assert_near(3, line[4], EPSILON, "the line at 2 m is off the seam")
                    seam = seam + math.abs(line[3] - line[1])
                end

                per_height[line[5]] = (per_height[line[5]] or 0) + 1
            end

            assert_near(2, seam, EPSILON, "the seam line at 2 m with corner rotation " .. rotation)

            for z, count in pairs(per_height) do
                assert_equal(1, count, "the pieces at " .. z .. " m were not joined with corner rotation " .. rotation)
            end
        end
    end)

test("a piece lengthens a line of its height only when it carries the line on straight ahead", function()
    local harness = new_harness()
    local add_triangle_lines = upvalue(upvalue(upvalue(harness.treads.update, "_build_step"), "_output_step"),
        "_add_triangle_lines")
    local add_piece = upvalue(add_triangle_lines, "_add_piece")
    local build = { ends = {}, steps = {}, joined = 0 }

    add_piece(build, 0, 0, 1, 0, 2)
    add_piece(build, 1, 0, 2, 0, 2)
    add_piece(build, 3, 0, 2, 0, 2)
    assert_equal(1, harness.lines.count, "pieces carrying a line on in either direction")
    assert_equal(2, build.joined, "pieces joined")
    assert_near(0, harness.lines.x1[1], EPSILON, "the joined line's start")
    assert_near(3, harness.lines.x2[1], EPSILON, "the joined line's end")
    assert_near(1, harness.lines.z[1], EPSILON, "the joined line's height")

    add_piece(build, 3, 0, 4, 1, 2)
    assert_equal(2, harness.lines.count, "a piece turning by 45 degrees")
    add_piece(build, 30, 0, 31, 0, 2)
    add_piece(build, 31, 0, 30.5, 0, 2)
    assert_equal(4, harness.lines.count, "a piece folding back over the line")
    add_piece(build, 0, 0, -1, 0, 3)
    assert_equal(5, harness.lines.count, "a piece of another height")

    add_piece(build, 10, 0, 11, 0, 4)
    add_piece(build, 11, 0, 12, 0.0015, 4)
    assert_equal(6, harness.lines.count, "a piece turning by a sine of 0.0015")
    add_piece(build, 20, 0, 21, 0, 4)
    add_piece(build, 21, 0, 22, 0.0025, 4)
    assert_equal(8, harness.lines.count, "a piece turning by a sine of 0.0025")
    assert_equal(3, build.joined, "pieces joined in all")
end)

-- ----------------------------------------------------------------------------
-- Build
-- ----------------------------------------------------------------------------

test("the build keeps to its budgets, draws nothing until it is done, and starts over for new geometry", function()
    local triangles = {}

    for i = 0, 1099 do
        local x = -3000 + (i % 40) * 3
        local y = math.floor(i / 40) * 3

        triangles[#triangles + 1] = { x, y, 0, x + 1, y, 0, x, y + 1, 0.5 }
    end

    for i = 0, 9999 do
        local x = (i % 100) * 3
        local y = math.floor(i / 100) * 3

        triangles[#triangles + 1] = { x, y, 0, x + 1, y, 0, x, y + 1, 0 }
    end

    for f = 0, 599 do
        local x = 1000 + (f % 20) * 5
        local y = math.floor(f / 20) * 10

        flight(triangles, x, y, x + 2, y + 3, 0, 2)
    end

    flight(triangles, 500, 500, 502, 506, 0, 4)

    local harness = new_harness()
    local geometry = new_geometry(triangles)
    local build_step = upvalue(harness.treads.update, "_build_step")
    local budgets = {
        { step = "_scan_step", name = "SCAN_BUDGET", value = 2048, field = "cursor" },
        { step = "_facets_step", name = "FACET_BUDGET", value = 1024, field = "order_n" },
        { step = "_measure_step", name = "MEASURE_BUDGET", value = 1024, field = "cursor" },
        { step = "_probe_step", name = "PROBE_BUDGET", value = 32, field = "probe_cursor" },
        { step = "_output_step", name = "OUTPUT_BUDGET", value = 256, field = "cursor" },
        { step = "_index_step", name = "INDEX_BUDGET", value = 2048, field = "cursor" },
    }

    for phase, budget in ipairs(budgets) do
        assert_equal(budget.value, upvalue(upvalue(build_step, budget.step), budget.name), budget.name)
        budget.phase = phase
    end

    local player = { x = 501, y = 503, z = 1 }
    local frames_by_phase = {}
    local frames = 0

    repeat
        frames = frames + 1

        -- The first update starts the build and scans in the same frame.
        local phase = math.max(1, harness.build.phase)
        local ready = harness.treads.update(geometry)

        if not ready then
            assert_equal(0, #harness.draw(player, { reselect = true }), "marks were drawn before the build finished")
        end

        frames_by_phase[phase] = (frames_by_phase[phase] or 0) + 1

        if frames_by_phase[phase] == 1 then
            local budget = budgets[phase]
            local progress = budget.field == "order_n" and harness.build.order_n or harness.build.cursor

            assert_equal(phase, harness.build.phase, budget.name .. " finished its phase in one frame")
            assert_equal(budget.value, progress, "the first frame's progress under " .. budget.name)
        end
    until ready

    local lines = harness.lines.count
    local items = lines + harness.bands.count

    assert_equal(1100 + 1202, harness.build.sloped_n, "sloped triangles found")
    assert_equal(1100 + 601, harness.build.facet_count, "facets grown")
    assert_equal(601, harness.build.kept, "flights kept")
    assert_equal(601 * 4, harness.build.probe_n, "probe points")
    assert_equal(600 * 4 + 8, lines, "lines of the 600 short flights and the tall one")

    local expected = { math.ceil(#triangles / 2048), 3, 3, math.ceil(601 * 4 / 32), math.ceil(2302 / 256),
        math.ceil(items / 2048) }

    for phase = 1, 6 do
        assert_equal(expected[phase], frames_by_phase[phase], "frames of phase " .. phase)
    end

    assert_equal(frames, harness.build.frames, "frames the build counted")
    assert_equal(nil, harness.build.sloped, "the build kept its working tables")
    assert_equal(nil, harness.build.facet_state, "the build kept its facet tables")
    assert_true(#harness.draw(player, { reselect = true }) > 0, "nothing was drawn once the build finished")

    local count = harness.lines.count
    local band_count = harness.bands.count

    geometry.revision = 2
    assert_equal(false, harness.treads.update(geometry), "a new revision did not start over")
    assert_equal(0, harness.lines.count, "a new revision kept the old lines")
    assert_equal(0, harness.bands.count, "a new revision kept the old bands")
    harness.build_all(geometry)
    assert_equal(count, harness.lines.count, "a rebuilt revision has other lines")
    assert_equal(band_count, harness.bands.count, "a rebuilt revision has other bands")

    local tall = {}

    flight(tall, 500, 500, 502, 506, 0, 4)

    local other = new_geometry(tall, 2)

    harness.build_all(other)
    assert_equal(8, harness.lines.count, "the tall flight in a new table built other lines")
    assert_equal(other, harness.build.geometry, "a new geometry table did not start over")

    harness.treads.fail("broken")

    for _ = 1, 10 do
        assert_equal(false, harness.treads.update(other), "a failed build came back for the same geometry")
    end

    assert_equal(0, harness.lines.count, "a failed build kept or rebuilt its lines")
    assert_equal(0, harness.bands.count, "a failed build kept or rebuilt its bands")
    assert_equal(0, #harness.draw(player, { reselect = true }), "a failed build drew marks")
    other.revision = 3
    harness.build_all(other)
    assert_equal(8, harness.lines.count, "a new revision after a failure did not build again")

    harness.settings.debug_mode = true
    other.revision = 4
    harness.build_all(other)
    assert_true(harness.logs[#harness.logs]:find("navmesh stair marks ready", 1, true) ~= nil,
        "the finished build was not logged in debug mode")
    assert_true(harness.logs[#harness.logs]:find("kept=1 ", 1, true) ~= nil, "the log has no kept facet count")

    harness.treads.reset()
    assert_equal(nil, harness.build.geometry, "the reset kept the geometry")
    assert_equal(0, harness.lines.count, "the reset kept the lines")
    assert_equal(0, harness.bands.count, "the reset kept the bands")
    assert_equal(0, #harness.draw(player, { reselect = true }), "marks were drawn after the reset")
end)

test("a build at once stores what the frame-by-frame build stores, and starts over for the next mission's navmesh",
    function()
        local triangles = {}

        flight(triangles, 0, 0, 2, 6, 0, 4)
        flight(triangles, 20, 0, 22, 6, 0, 2.5)

        local stepped = built(triangles)
        local harness = new_harness()
        local geometry = new_geometry(triangles)

        assert_equal(true, harness.treads.build_now(geometry), "the build at once did not finish")
        assert_equal(stepped.build.frames, harness.build.frames, "the build at once took other steps")
        assert_equal(stepped.lines.count, harness.lines.count, "lines stored")
        assert_equal(stepped.bands.count, harness.bands.count, "band pieces stored")

        local expected = stored_lines(stepped)
        local actual = stored_lines(harness)

        for i = 1, #expected do
            for k = 1, 5 do
                assert_equal(expected[i][k], actual[i][k], "field " .. k .. " of line " .. i)
            end
        end

        local stepped_area = stored_band_area(stepped)
        local area = stored_band_area(harness)

        for step = 0, 7 do
            assert_near(stepped_area[step] or 0, area[step] or 0, 1e-9, "the band area of step " .. step)
        end

        -- The navmesh module rebuilds the next mission's navmesh into the same table, with a new revision.
        local tall = {}

        flight(tall, 500, 500, 502, 506, 0, 4)

        for key, value in pairs(new_geometry(tall, 2)) do
            geometry[key] = value
        end

        assert_equal(true, harness.treads.build_now(geometry), "the next mission's build did not finish")
        assert_equal(8, harness.lines.count, "the next mission kept the previous mission's lines")
        assert_true(harness.lines.y1[1] >= 500, "the next mission's lines are not on its flight")

        harness.treads.build_now(new_geometry(triangles, 2))
        assert_equal(stepped.lines.count, harness.lines.count, "a new geometry table of the same revision kept the old lines")

        harness.treads.fail("broken")
        assert_equal(false, harness.treads.build_now(harness.build.geometry), "a failed build came back")
        assert_equal(0, harness.lines.count, "a failed build kept or rebuilt its lines")
    end)

-- ----------------------------------------------------------------------------
-- Draw
-- ----------------------------------------------------------------------------

test("lines are thin, fade with height difference, hide beyond 4 m, take the floor colour and thin out at"
    .. " long range", function()
    local triangles = {}

    flight(triangles, 0, 0, 2, 6, 0, 4)

    local harness = built(triangles)
    local player = { x = 1, y = 2, z = 0 }
    local lines = drawn_lines(harness.draw(player, { reselect = true }), player)
    local alpha = math.floor(80 * 1.6 + 0.5)
    local fades = { 1, 0.8, 0.6, 0.4 }

    assert_equal(8, #lines, "lines drawn")

    for _, line in ipairs(lines) do
        local z = math.floor(line[2] / 1.5 * 2 + 0.5) / 2
        local fade = math.min(4, math.floor(z) + 1)
        local color = line[5]

        assert_equal(math.floor(alpha * fades[fade] + 0.5), color[1], "the opacity at " .. z .. " m")
        assert_equal(brighten(101, 0.3), color[2], "the red channel")
        assert_equal(brighten(133, 0.3), color[3], "the green channel")
        assert_equal(brighten(96, 0.3), color[4], "the blue channel")
        assert_near(UI_SCALE, line.width, 1e-9, "a line is not one unscaled pixel wide")
    end

    local made = harness.colors_made

    assert_equal(8, #drawn_lines(harness.draw(player), player), "lines drawn in the next frame")
    assert_equal(made + 4, harness.colors_made, "the line colours made in a frame")

    player.z = -1
    lines = drawn_lines(harness.draw(player, { reselect = true }), player)

    for _, line in ipairs(lines) do
        assert_true(line[2] / 1.5 <= 3 + EPSILON, "a line more than 4 m above the player was drawn")
    end

    assert_equal(6, #lines, "lines within 4 m of a player 1 m lower")

    player.z = 0

    local expected = { [25] = 0.5, [60] = 1, [120] = 2, [240] = 4 }

    for range, step in pairs(expected) do
        lines = drawn_lines(harness.draw(player, { range = range }), player, range)
        assert_true(#lines > 0, "nothing was drawn at " .. range .. " m")

        for _, line in ipairs(lines) do
            local z = line[2] / 1.5
            local ratio = z / step

            assert_near(math.floor(ratio + 0.5), ratio, 1e-6, "a skipped line was drawn at " .. range .. " m")
        end
    end

    assert_equal(4, #drawn_lines(harness.draw(player, { range = 60 }), player, 60), "lines at a 1 m stride")
    assert_equal(0, #harness.draw(player, { range = 400 }), "lines were drawn too close together to read")
    assert_equal(0, #harness.draw(player, { color = { 0, 101, 133, 96 } }), "a transparent floor colour drew lines")
    assert_equal(8, #drawn_lines(harness.draw(player, { style = "bogus" }), player), "an unknown style drew no lines")
end)

test("stripes fill every other band a little lighter, fade with height difference and widen at long range",
    function()
        local triangles = {}

        flight(triangles, 0, 0, 2, 6, 0, 4)

        local harness = built(triangles)
        local player = { x = 1, y = 2, z = 0 }
        local area, colors = drawn_steps(harness.draw(player, { style = "stripes", reselect = true }), player)
        local alpha = math.floor(80 * 0.7 + 0.5)
        local fades = { 1, 0.8, 0.6, 0.4 }

        for step = 0, 7 do
            if step % 2 == 0 then
                local fade = fades[math.floor((step + 0.5) * 0.5) + 1]
                local color = colors[step]

                assert_near(1.5, area[step] or 0, 1e-6, "the stripe of step " .. step)
                assert_equal(math.floor(alpha * fade + 0.5), color[1], "the opacity of step " .. step)
                assert_equal(brighten(101, 0.5), color[2], "the red channel")
                assert_equal(brighten(133, 0.5), color[3], "the green channel")
                assert_equal(brighten(96, 0.5), color[4], "the blue channel")
            else
                assert_equal(nil, area[step], "the band of step " .. step .. " was filled")
            end
        end

        area = drawn_steps(harness.draw(player, { style = "stripes", range = 60 }), player, 60)

        for step = 0, 7 do
            if math.floor(step / 2) % 2 == 0 then
                assert_near(1.5, area[step] or 0, 1e-6, "the band of step " .. step .. " in a 1 m stripe")
            else
                assert_equal(nil, area[step], "the band of step " .. step .. " was filled at a 1 m stride")
            end
        end

        assert_equal(0, #harness.draw(player, { style = "stripes", range = 400 }), "stripes too narrow to read")
        assert_equal(0, #harness.draw(player, { style = "stripes", color = { 0, 101, 133, 96 } }),
            "a transparent floor colour drew stripes")
    end)

test("shading tints every band towards the floor-above or floor-below colour by height difference, with"
    .. " alternating opacity", function()
    local triangles = {}

    flight(triangles, 0, 0, 2, 6, 0, 4)

    local harness = built(triangles)

    --- The shading colour of a band whose middle lies `dz` above the player, and of its step's parity.
    local function shade(dz, step, stride)
        local level = math.max(-3, math.min(3, math.floor(dz + 0.5)))
        local target = level < 0 and BELOW_COLOR or ABOVE_COLOR
        local weight = math.abs(level) / 3
        local alpha = math.floor(step / (stride or 1)) % 2 == 0 and math.floor(80 * 0.6 + 0.5) or 80
        local color = { alpha }

        for channel = 2, 4 do
            local current = CURRENT_COLOR[channel]

            color[channel] = brighten(current + (target[channel] - current) * weight, 0.2)
        end

        return color
    end

    for _, player in ipairs({ { x = 1, y = 2, z = 0 }, { x = 1, y = 4, z = 4 }, { x = 1, y = 3, z = 1.7 } }) do
        local area, colors = drawn_steps(harness.draw(player, { style = "shading", reselect = true }), player)

        for step = 0, 7 do
            local dz = (step + 0.5) * 0.5 - player.z
            local expected = shade(dz, step)
            local color = colors[step]

            assert_near(1.5, area[step] or 0, 1e-6, "the band of step " .. step .. " at " .. player.z .. " m")

            for channel = 1, 4 do
                assert_equal(expected[channel], color[channel],
                    "channel " .. channel .. " of step " .. step .. " seen from " .. player.z .. " m")
            end
        end
    end

    local player = { x = 1, y = 2, z = 0 }
    local _, colors = drawn_steps(harness.draw(player, { style = "shading", range = 60 }), player, 60)

    for step = 0, 7 do
        assert_equal(shade((step + 0.5) * 0.5, step, 2)[1], colors[step][1], "the opacity of step " .. step .. " at a 1 m stride")
    end

    local made = harness.colors_made

    harness.draw(player, { style = "shading" })
    assert_equal(made + 14, harness.colors_made, "the shading colours made in a frame")
    _, colors = drawn_steps(harness.draw(player, { style = "shading", above = { 32, 200, 150, 185 } }), player)
    assert_equal(brighten(200, 0.2), colors[7][2], "a new floor-above colour kept the old shading")
    assert_equal(0, #harness.draw(player, { style = "shading", color = { 0, 101, 133, 96 } }),
        "a transparent floor colour drew shading")
end)

test("lines and bands are clipped to the radar circle and square, and long ones centred far away still show",
    function()
        local triangles = {}

        flight(triangles, -60, 0, 60, 6, 0, 4)

        local harness = built(triangles)

        -- The player stands 5 m from the flight's left end, so most of its band pieces are centred far outside.
        local player = { x = -55, y = 3, z = 1 }

        for _, style in ipairs({ "lines", "stripes", "shading" }) do
            for _, circle in ipairs({ false, true }) do
                local emitted = harness.draw(player, { style = style, reselect = true, circle = circle })
                local widest = 0

                assert_true(#emitted > 0, "nothing was drawn")

                for _, triangle in ipairs(emitted) do
                    for v = 0, 2 do
                        local sx = triangle[1 + v * 2] / UI_SCALE - CENTER_X
                        local sy = triangle[2 + v * 2] / UI_SCALE - CENTER_Y
                        local reach = PROJECTION_RADIUS + (style == "lines" and 0.5 or 0) + 1e-6

                        if circle then
                            assert_true(math.sqrt(sx * sx + sy * sy) <= reach, style .. " left the circle")
                        else
                            assert_true(math.abs(sx) <= reach and math.abs(sy) <= reach, style .. " left the square")
                        end

                        widest = math.max(widest, sx)
                    end
                end

                assert_true(widest > PROJECTION_RADIUS * 0.95, style .. " were not drawn up to the radar edge")

                if style ~= "lines" and not circle then
                    local area = drawn_steps(emitted, player)

                    for step = 0, 7 do
                        if style == "shading" or step % 2 == 0 then
                            assert_near(30 * 0.75, area[step] or 0, 1e-6,
                                "the " .. style .. " of step " .. step .. " inside the square")
                        end
                    end
                end
            end
        end
    end)

test("the marks near the player are listed again only when asked, when they change or when the stride does",
    function()
        local triangles = {}

        flight(triangles, 0, 0, 2, 6, 0, 4)

        local harness = built(triangles)
        local player = { x = 1, y = 2, z = 0 }

        harness.draw(player)
        assert_equal(1, harness.selection.refreshes, "finished marks were not listed")
        harness.draw(player, { style = "shading" })
        harness.draw({ x = 30, y = 30, z = 0 })
        assert_equal(1, harness.selection.refreshes, "the marks were listed again without a reason")
        assert_equal(0, #harness.draw({ x = 300, y = 300, z = 0 }, { reselect = true }),
            "marks far away were drawn after a new listing")
        assert_equal(0, #harness.draw({ x = 300, y = 300, z = 0 }, { style = "shading" }),
            "bands far away were drawn after a new listing")
        assert_equal(2, harness.selection.refreshes, "a requested listing did not happen")
        harness.draw(player, { reselect = true, range = 60 })
        harness.draw(player, { range = 25 })
        assert_equal(4, harness.selection.refreshes, "a new stride did not list the marks again")

        -- Flights in the cells around the player are listed, one 20 m up is not.
        triangles = {}

        for x = -20, 20, 10 do
            flight(triangles, x, 0, x + 2, 6, 0, 4)
        end

        flight(triangles, 0, 0, 2, 6, 20, 24)
        harness = built(triangles)
        player = { x = 1, y = 2, z = 0 }

        local area = drawn_steps(harness.draw(player, { style = "shading", reselect = true }), player)

        assert_near(5 * 1.5, area[0], 1e-6, "the five flights' lowest bands")
        assert_equal(5 * 8, harness.selection.line_count, "lines listed around the player")

        local low_pieces = 0

        for i = 1, harness.bands.count do
            if harness.bands.z[i] < 10 then
                low_pieces = low_pieces + 1
            end
        end

        assert_equal(low_pieces, harness.selection.band_count, "band pieces listed around the player")
    end)

local failures = {}

for i = 1, #tests do
    local current = tests[i]
    local ok, failure = xpcall(current.fn, debug.traceback)

    if ok then
        io.write("PASS ", current.name, "\n")
    else
        failures[#failures + 1] = current.name .. "\n" .. failure
        io.write("FAIL ", current.name, "\n")
    end
end

if #failures > 0 then
    io.write("\n")

    for i = 1, #failures do
        io.write(failures[i], "\n")
    end

    io.write("\n", tostring(#failures), " of ", tostring(#tests), " tests failed\n")
    os.exit(1)
end

io.write("\n", tostring(#tests), " tests passed\n")
