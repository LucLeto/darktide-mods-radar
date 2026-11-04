-- Circle radar frame pixels. The renderer draws the circle fill, its soft edge, the solid outline
-- and the view guides with as few rectangles as it can; this spec draws the same shapes pixel by
-- pixel with the reference algorithms (one span per row, the midpoint circle, Bresenham's line)
-- and checks that both cover the same screen pixels with the same colours, the same number of
-- times, at several sizes, UI scales and draw phases.

local RENDERER_PATH = "Radar/scripts/mods/Radar/ui/Radar_hud_renderer.lua"
local START_LAYER = 100

local function assert_true(value, message)
    if value ~= true then
        error(message or "expected true", 2)
    end
end

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local color_meta = {
    __tostring = function(color)
        return color[1] .. "," .. color[2] .. "," .. color[3] .. "," .. color[4]
    end,
}

local function make_color(a, r, g, b)
    return setmetatable({ a, r, g, b }, color_meta)
end

--- Loads the renderer with a recording `Gui.rect` and the given style settings.
local function load_renderer(settings)
    local recorded = {}
    local mod = {}

    function mod:get(id)
        return settings[id]
    end

    function mod:get_radar_outline()
        return settings.radar_outline
    end

    function mod:get_radar_guides()
        return settings.radar_guides
    end

    function mod:get_radar_style()
        return settings.radar_style
    end

    local env = setmetatable({
        get_mod = function()
            return mod
        end,
        require = function()
            return { draw = function() end }
        end,
        Gui = {
            rect = function(_, position, size, color)
                recorded[#recorded + 1] = { position[1], position[2], position[3], size[1], size[2], tostring(color) }
            end,
        },
        Color = make_color,
        Vector3 = function(x, y, z)
            return { x, y, z }
        end,
        Vector2 = function(x, y)
            return { x, y }
        end,
        Quaternion = {
            yaw = function()
                return 0
            end,
        },
        math = setmetatable({
            clamp = function(value, low, high)
                return value < low and low or (value > high and high or value)
            end,
        }, { __index = math }),
    }, { __index = _G })
    local chunk = assert(loadfile(RENDERER_PATH))

    setfenv(chunk, env)

    return chunk(), recorded
end

--- Draws one frame phase and returns the recorded rectangles.
local function draw_frame(settings, size, scale, x, y, phase)
    local renderer, recorded = load_renderer(settings)
    local ui_renderer = { gui = {}, scale = scale, render_settings = { start_layer = START_LAYER } }

    if phase == "background" then
        renderer.draw_radar_frame_background({}, ui_renderer, x, y, 1, size, nil)
    elseif phase == "foreground" then
        renderer.draw_radar_frame_foreground({}, ui_renderer, x, y, 1, size, nil)
    else
        renderer.draw_radar_frame({}, ui_renderer, x, y, 1, size, nil)
    end

    return recorded
end

-- ----------------------------------------------------------------------------
-- Reference drawing, one pixel or row at a time
-- ----------------------------------------------------------------------------

local function ref_box(out, x, y, z, w, h, color, scale)
    out[#out + 1] = { x * scale, y * scale, START_LAYER + z, w * scale, h * scale, tostring(color) }
end

local function ref_fill(out, cx, cy, z, radius, color, scale)
    for dy = -radius, radius do
        local span = math.floor(math.sqrt(math.max(0, radius * radius - dy * dy)))

        ref_box(out, cx - span, cy + dy, z, span * 2 + 1, 1, color, scale)
    end
end

local function ref_octants(out, cx, cy, z, x, y, color, scale)
    local points

    if y == 0 then
        points = { { x, 0 }, { -x, 0 }, { 0, x }, { 0, -x } }
    elseif x == y then
        points = { { x, y }, { -x, y }, { x, -y }, { -x, -y } }
    else
        points = { { x, y }, { -x, y }, { x, -y }, { -x, -y }, { y, x }, { -y, x }, { y, -x }, { -y, -x } }
    end

    for i = 1, #points do
        ref_box(out, cx + points[i][1], cy + points[i][2], z, 1, 1, color, scale)
    end
end

local function ref_perimeter(out, cx, cy, z, radius, color, scale)
    local x, y, decision = radius, 0, 1 - radius

    while y <= x do
        ref_octants(out, cx, cy, z, x, y, color, scale)
        y = y + 1

        if decision < 0 then
            decision = decision + 2 * y + 1
        else
            x = x - 1
            decision = decision + 2 * (y - x) + 1
        end
    end
end

local function ref_line(out, x1, y1, x2, y2, z, color, scale)
    local function round(v)
        return math.floor(v + 0.5)
    end

    local sx, sy, ex, ey = round(x1 * scale), round(y1 * scale), round(x2 * scale), round(y2 * scale)
    local dx, dy = math.abs(ex - sx), math.abs(ey - sy)
    local step_x, step_y = sx < ex and 1 or -1, sy < ey and 1 or -1
    local err = dx - dy

    if sx == ex and sy == ey then
        return
    end

    while true do
        local e2 = err * 2

        if e2 > -dy then
            err = err - dy
            sx = sx + step_x
        end

        if e2 < dx then
            err = err + dx
            sy = sy + step_y
        end

        if sx == ex and sy == ey then
            break
        end

        out[#out + 1] = { sx, sy, START_LAYER + z, 1, 1, tostring(color) }
    end
end

local function alpha_scaled(color, factor)
    return make_color(math.max(0, math.min(255, math.floor(color[1] * factor + 0.5))), color[2], color[3], color[4])
end

local BACKGROUND = make_color(90, 0, 0, 0)
local OUTLINE = make_color(255, 213, 226, 206)
local GUIDES = make_color(90, 255, 255, 255)

--- The circle frame as the renderer composes it, drawn with the reference shapes.
local function reference_frame(settings, size, scale, x, y, phase)
    local out = {}
    local snapped = math.max(2, math.floor(size + 0.5))
    local cx = math.floor(x + snapped * 0.5 + 0.5)
    local cy = math.floor(y + snapped * 0.5 + 0.5)
    local radius = math.max(1, math.floor(snapped * 0.5 - 1 + 0.5))

    if phase ~= "foreground" then
        ref_fill(out, cx, cy, 1, radius - 1, BACKGROUND, scale)
        ref_perimeter(out, cx, cy, 1, radius, alpha_scaled(BACKGROUND, 0.45), scale)
    end

    if phase ~= "background" then
        if settings.radar_outline == "solid" then
            local feather = alpha_scaled(OUTLINE, 0.35)

            ref_perimeter(out, cx, cy, 2, radius, OUTLINE, scale)
            ref_perimeter(out, cx, cy, 2, radius + 1, feather, scale)
            ref_perimeter(out, cx, cy, 2, radius - 1, feather, scale)
        end

        if settings.radar_guides == "view_guides" then
            local half_angle = math.rad(45)
            local reach = radius - 1

            ref_line(out, cx, cy, cx + math.sin(-half_angle) * reach, cy - math.cos(-half_angle) * reach, 2, GUIDES, scale)
            ref_line(out, cx, cy, cx + math.sin(half_angle) * reach, cy - math.cos(half_angle) * reach, 2, GUIDES, scale)
        end
    end

    return out
end

-- ----------------------------------------------------------------------------
-- Coverage
-- ----------------------------------------------------------------------------

--- Rasterises rectangles by pixel centres into one canonical text: per layer, colour and row, the
--- covered column ranges with how many rectangles cover them.
local function coverage(rects)
    local rows = {}

    for n = 1, #rects do
        local r = rects[n]
        local i0, i1 = math.ceil(r[1] - 0.5), math.ceil(r[1] + r[4] - 0.5) - 1
        local j0, j1 = math.ceil(r[2] - 0.5), math.ceil(r[2] + r[5] - 0.5) - 1

        for j = j0, j1 do
            if i1 >= i0 then
                local key = r[3] .. "|" .. r[6] .. "@" .. j
                local list = rows[key]

                if not list then
                    list = {}
                    rows[key] = list
                end

                list[#list + 1] = { i0, 1 }
                list[#list + 1] = { i1 + 1, -1 }
            end
        end
    end

    local lines = {}

    for key, events in pairs(rows) do
        table.sort(events, function(a, b)
            return a[1] < b[1]
        end)

        local segments, count, last = {}, 0, nil

        for k = 1, #events do
            local position = events[k][1]

            if last ~= nil and position > last and count > 0 then
                local previous = segments[#segments]

                if previous and previous[2] == last - 1 and previous[3] == count then
                    previous[2] = position - 1
                else
                    segments[#segments + 1] = { last, position - 1, count }
                end
            end

            count = count + events[k][2]
            last = position
        end

        local parts = {}

        for k = 1, #segments do
            parts[k] = segments[k][1] .. "-" .. segments[k][2] .. "x" .. segments[k][3]
        end

        lines[#lines + 1] = key .. "=" .. table.concat(parts, ",")
    end

    table.sort(lines)

    return table.concat(lines, "\n")
end

-- ----------------------------------------------------------------------------
-- Tests
-- ----------------------------------------------------------------------------

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local SIZES = { 100, 101, 150, 180, 220, 299, 300, 301, 450, 600, 777, 1200 }
local SCALES = { 1, 4 / 3, 1.5, 0.75 }
local CONFIGS = {
    { radar_style = "circle", radar_outline = "off", radar_guides = "view_guides" },
    { radar_style = "circle", radar_outline = "solid", radar_guides = "off" },
    { radar_style = "circle", radar_outline = "solid", radar_guides = "view_guides" },
}

for c = 1, #CONFIGS do
    local settings = CONFIGS[c]

    test("circle frame, outline " .. settings.radar_outline .. ", guides " .. settings.radar_guides
        .. ": the same pixels as drawing it pixel by pixel", function()
        for _, size in ipairs(SIZES) do
            for _, scale in ipairs(SCALES) do
                for _, phase in ipairs({ "single", "background", "foreground" }) do
                    local label = string.format("size %d, scale %.3f, %s", size, scale, phase)
                    local drawn = coverage(draw_frame(settings, size, scale, 40, 220, phase))
                    local expected = coverage(reference_frame(settings, size, scale, 40, 220, phase))

                    assert_true(drawn == expected, "pixels differ for " .. label)
                end
            end
        end
    end)
end

test("the circle background takes far fewer rectangles than pixels or rows", function()
    local settings = { radar_style = "circle", radar_outline = "off", radar_guides = "view_guides" }
    local drawn = #draw_frame(settings, 300, 4 / 3, 40, 220, "background")
    local reference = #reference_frame(settings, 300, 4 / 3, 40, 220, "background")

    assert_equal(1141, reference, "the reference background changed")
    assert_true(drawn <= 523, "the circle background at size 300 draws " .. drawn .. " rectangles")
end)

test("a nearly horizontal guide line is drawn as runs, not pixels", function()
    local settings = { radar_style = "circle", radar_outline = "off", radar_guides = "view_guides" }
    local renderer, recorded = load_renderer(settings)
    local ui_renderer = { gui = {}, scale = 1, render_settings = { start_layer = START_LAYER } }

    -- A 160 degree field of view gives an 80 degree half angle, so both guide lines run nearly flat.
    local env = getfenv(renderer.draw_radar_frame)

    env.Managers = {
        state = {
            player = {
                local_player = function()
                    return { viewport_name = "player1" }
                end,
            },
            camera = {
                fov = function()
                    return 2 * math.atan(math.tan(math.rad(160) * 0.5) / (16 / 9))
                end,
            },
        },
    }

    renderer.draw_radar_frame_foreground({}, ui_renderer, 40, 220, 1, 300, nil)

    local pixels = 0

    for i = 1, #recorded do
        pixels = pixels + recorded[i][4] * recorded[i][5]
    end

    assert_true(#recorded > 0 and #recorded * 3 < pixels,
        #recorded .. " rectangles for " .. pixels .. " guide pixels")
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
