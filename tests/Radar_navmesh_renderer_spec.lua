-- Dropping navmesh triangles before projection must never change what the radar draws.
-- Installs the real navmesh renderer and triangle clipper against a fake GUI and a generated
-- mesh, and compares every draw with the clipper run directly on all selected triangles.

local RENDERER_PATH = "Radar/scripts/mods/Radar/ui/Radar_navmesh_renderer.lua"
local CLIPPER_PATH = "Radar/scripts/mods/Radar/ui/Radar_triangle_clipper.lua"
local CENTER_X, CENTER_Y = 110, 310
local UI_SCALE = 4 / 3
local PROJECTION_RADIUS = 142
local LAYER = 103
local TOLERANCE = 1e-6

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

--- Geometry in the shape `Radar_navmesh.lua` builds, with one bucket per 16 m cell.
local function new_geometry(triangles)
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
        revision = 1,
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

        local key = math.floor(mid_x / 16) .. ":" .. math.floor(mid_y / 16)
        local bucket = geometry.buckets[key]

        if not bucket then
            bucket = {}
            geometry.buckets[key] = bucket
        end

        bucket[#bucket + 1] = i
    end

    return geometry
end

--- Loads a fresh renderer and clipper against the given geometry and style.
local function new_harness(geometry, style)
    local harness = { emitted = {}, values = {}, geometry = geometry }
    local mod = {}
    local previous_get_mod = rawget(_G, "get_mod")
    local previous = { Gui = rawget(_G, "Gui"), Vector3 = rawget(_G, "Vector3"), Color = rawget(_G, "Color"),
        Quaternion = rawget(_G, "Quaternion") }
    local forward = { x = 0, y = 1 }

    harness.forward = forward

    function mod:get(id)
        if id == "radar_style" then
            return style
        end

        return nil
    end

    function mod:info()
    end

    function mod:is_overview_mode_active()
        return false
    end

    function mod:get_map_geometry_source()
        return "live"
    end

    function mod:get_radar_color(_, fallback)
        return fallback
    end

    function mod:ensure_navmesh_geometry()
        return harness.geometry
    end

    function mod:radar_profiler_value(name, value)
        harness.values[name] = value
    end

    function mod:get_navmesh_nearby_buckets(_, _, _, out_buckets)
        local n = 0

        for _, bucket in pairs(harness.geometry.buckets) do
            n = n + 1
            out_buckets[n] = bucket
        end

        return n
    end

    function mod:io_dofile(path)
        return assert(loadfile(path .. ".lua"))()
    end

    rawset(_G, "get_mod", function()
        return mod
    end)
    rawset(_G, "Vector3", function(x, _, z)
        return { x, z }
    end)
    rawset(_G, "Color", function(a, r, g, b)
        return a * 16777216 + r * 65536 + g * 256 + b
    end)
    rawset(_G, "Quaternion", {
        forward = function()
            return forward
        end,
    })
    rawset(_G, "Gui", {
        triangle = function(_, a, b, c, layer, color)
            harness.emitted[#harness.emitted + 1] = { a[1], a[2], b[1], b[2], c[1], c[2], layer, color }
        end,
    })

    harness.renderer = assert(loadfile(RENDERER_PATH))()
    harness.clip_and_emit = assert(loadfile(CLIPPER_PATH))()

    for name, value in pairs(previous) do
        rawset(_G, name, value)
    end

    rawset(_G, "get_mod", previous_get_mod)

    function harness.draw(t, player, range)
        harness.emitted = {}
        harness.renderer.draw({ gui = {}, scale = UI_SCALE, render_settings = { start_layer = 100 } }, t, player, {},
            CENTER_X, CENTER_Y, PROJECTION_RADIUS, range, 3)

        return harness.emitted
    end

    return harness
end

--- What the renderer drew before it dropped anything: every selected triangle clipped, by band.
local function expected_emission(harness, player, range, is_circle, select_range)
    local geometry = harness.geometry
    local forward_x, forward_y = harness.forward.x, harness.forward.y
    local scale = PROJECTION_RADIUS / range
    local bands = { {}, {}, {} }

    for _, bucket in pairs(geometry.buckets) do
        for j = 1, #bucket do
            local i = bucket[j]
            local dx, dy = geometry.mid_x[i] - player.x, geometry.mid_y[i] - player.y
            local dz = geometry.mid_z[i] - player.z
            local reach = select_range + geometry.radius[i]

            if dz <= 7 and dz >= -7 and dx * dx + dy * dy <= reach * reach then
                local band = dz > 2.5 and 3 or (dz < -2.5 and 1 or 2)

                bands[band][#bands[band] + 1] = i
            end
        end
    end

    local colors = {
        55 * 16777216 + 120 * 65536 + 98 * 256 + 76,
        80 * 16777216 + 101 * 65536 + 133 * 256 + 96,
        32 * 16777216 + 120 * 65536 + 150 * 256 + 185,
    }
    local expected = {}
    local saved = harness.emitted

    harness.emitted = expected

    for band = 1, 3 do
        for k = 1, #bands[band] do
            local i = bands[band][k]
            local vertices = {
                { geometry.ax[i], geometry.ay[i] },
                { geometry.bx[i], geometry.by[i] },
                { geometry.cx[i], geometry.cy[i] },
            }
            local projected = {}

            for v = 1, 3 do
                local dx, dy = vertices[v][1] - player.x, vertices[v][2] - player.y

                projected[#projected + 1] = (dx * forward_y - dy * forward_x) * scale
                projected[#projected + 1] = -(dx * forward_x + dy * forward_y) * scale
            end

            harness.clip_and_emit({}, LAYER, colors[band], is_circle, PROJECTION_RADIUS,
                PROJECTION_RADIUS * PROJECTION_RADIUS, UI_SCALE, CENTER_X, CENTER_Y, projected[1], projected[2],
                projected[3], projected[4], projected[5], projected[6])
        end
    end

    harness.emitted = saved

    return expected
end

local function assert_same_emission(expected, actual, label)
    assert_equal(#expected, #actual, label .. " triangle count")

    for i = 1, #expected do
        for j = 1, 8 do
            if math.abs(expected[i][j] - actual[i][j]) > TOLERANCE then
                error(string.format("%s triangle %d field %d: expected %.9f, got %.9f", label, i, j, expected[i][j],
                    actual[i][j]), 2)
            end
        end
    end
end

--- A deterministic mesh with small, long and huge triangles around the origin on three floors.
local function random_triangles(seed)
    math.randomseed(seed)

    local triangles = {}

    for i = 1, 900 do
        local size = i % 40 == 0 and 60 or (i % 7 == 0 and 12 or 3)
        local x = (math.random() - 0.5) * 120
        local y = (math.random() - 0.5) * 120
        local z = (math.random(1, 3) - 2) * 5

        triangles[i] = {
            x, y, z,
            x + (math.random() - 0.5) * size, y + (math.random() - 0.5) * size, z,
            x + (math.random() - 0.5) * size, y + (math.random() - 0.5) * size, z,
        }
    end

    return triangles
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local STYLES = {
    { style = "circle", is_circle = true },
    { style = "square", is_circle = false },
    { style = "auspex", is_circle = false },
}
local HEADINGS = { { 0, 1 }, { 1, 0 }, { 0.6, 0.8 }, { -0.28, -0.96 } }

for s = 1, #STYLES do
    local entry = STYLES[s]

    test(entry.style .. " draws exactly what clipping every selected triangle draws", function()
        local dropped = 0

        for seed = 1, 3 do
            for h = 1, #HEADINGS do
                for _, range in ipairs({ 15, 25, 40 }) do
                    local harness = new_harness(new_geometry(random_triangles(seed)), entry.style)
                    local player = { x = 3.5, y = -2.25, z = 0.5 }

                    harness.forward.x, harness.forward.y = HEADINGS[h][1], HEADINGS[h][2]

                    local actual = harness.draw(1, player, range)
                    local select_range = (entry.is_circle and range or range * 1.4143) + 4
                    local expected = expected_emission(harness, player, range, entry.is_circle, select_range)

                    assert_same_emission(expected, actual, entry.style)
                    assert_true(#actual > 0, "the mesh must reach the radar")

                    dropped = dropped + harness.values.draw_geometry_selected - harness.values.draw_geometry_in_shape
                end
            end
        end

        assert_true(dropped > 0, "the comparison must cover dropped triangles")
    end)
end

test("a triangle beyond the circle is dropped, one crossing it is not", function()
    local harness = new_harness(new_geometry({
        { 28, 0, 0, 29, 0, 0, 28, 1, 0 },
        { 24, 0, 0, 40, -2, 0, 40, 2, 0 },
    }), "circle")

    harness.draw(1, { x = 0, y = 0, z = 0 }, 25)

    assert_equal(2, harness.values.draw_geometry_selected, "both are selected")
    assert_equal(1, harness.values.draw_geometry_in_shape, "only the crossing one is left")
    assert_true(harness.values.draw_geometry_triangles >= 1, "and it is drawn")
end)

test("a triangle covering the whole radar is kept and fills it, on every style", function()
    for s = 1, #STYLES do
        local harness = new_harness(new_geometry({
            { -400, -400, 0, 400, -400, 0, 0, 500, 0 },
        }), STYLES[s].style)

        harness.draw(1, { x = 0, y = 0, z = 0 }, 25)

        assert_equal(1, harness.values.draw_geometry_in_shape, STYLES[s].style)
        assert_true(harness.values.draw_geometry_triangles >= 2, STYLES[s].style .. " draws the clipped fan")
    end
end)

test("the rotated square keeps its corners and drops what lies past its sides", function()
    local harness = new_harness(new_geometry({
        { 23, 23, 0, 24, 23, 0, 23, 24, 0 },
        { 30, 1, 0, 31, 1, 0, 30, 2, 0 },
    }), "square")

    harness.draw(1, { x = 0, y = 0, z = 0 }, 25)

    assert_equal(2, harness.values.draw_geometry_selected, "both are selected")
    assert_equal(1, harness.values.draw_geometry_in_shape, "only the corner one is left")
    assert_equal(1, harness.values.draw_geometry_triangles, "and it is drawn")

    harness.forward.x = math.sqrt(0.5)
    harness.forward.y = math.sqrt(0.5)
    harness.draw(2, { x = 0, y = 0, z = 0 }, 25)

    assert_equal(1, harness.values.draw_geometry_in_shape, "turned 45 degrees, the other one is left")
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
