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

local GUI_RENDER_PASS_LAYER = 16

--- Loads the renderer with a recording `Gui.rect` and `Gui2.bitmap_3d` and the given style settings.
-- Each `Gui2.bitmap_3d` call is recorded with its transform taken apart: `Rotation2D` gives the
-- angle, origin and pivot, `Rotation2D.translate` the unscaled position and the scale.
local function load_renderer(settings)
    local recorded = {}
    local textures = {}
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
        Gui2 = {
            bitmap_3d = function(gui, material, material_flags, tm, layer, args)
                local rotation = tm.rotation
                local position = tm.position
                local size = args.size

                textures[#textures + 1] = {
                    gui = gui,
                    material = material,
                    material_flags = material_flags,
                    layer = layer,
                    origin = rotation.origin,
                    angle = rotation.angle,
                    pivot = rotation.pivot,
                    x = position[1],
                    y = position[2],
                    z = position[3],
                    scale = tm.scale,
                    size = size,
                    along = size[1] / tm.scale,
                    across = size[2] / tm.scale,
                    color = args.color,
                    uv00 = args.uv00,
                    uv11 = args.uv11,
                    render_pass = args.render_pass,
                    snap_pixel_positions = args.snap_pixel_positions,
                }
            end,
        },
        GuiMaterialFlag = { GUI_RENDER_PASS_LAYER = GUI_RENDER_PASS_LAYER },
        Rotation2D = setmetatable({
            translate = function(tm, position, scale)
                return { rotation = tm, position = position, scale = scale }
            end,
        }, {
            __call = function(_, origin, angle, pivot)
                return { origin = origin, angle = angle, pivot = pivot }
            end,
        }),
        Color = make_color,
        Vector3 = setmetatable({
            zero = function()
                return { 0, 0, 0 }
            end,
        }, {
            __call = function(_, x, y, z)
                return { x, y, z }
            end,
        }),
        Vector2 = function(x, y, z)
            return { x, y, z }
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

    return chunk(), recorded, textures
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

-- ----------------------------------------------------------------------------
-- Facing chevron
-- ----------------------------------------------------------------------------

local function assert_near(expected, actual, message, tolerance)
    if type(actual) ~= "number" or math.abs(expected - actual) > (tolerance or 1e-9) then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

--- Returns the renderer's facing chevron constants, read from the draw function's upvalues.
local function facing_constants(renderer)
    local draw = renderer.draw_marker_facing_chevron

    for index = 1, 255 do
        local name, value = debug.getupvalue(draw, index)

        assert(name ~= nil, "missing upvalue `FACING_CHEVRON`")

        if name == "FACING_CHEVRON" then
            return value
        end
    end
end

local function facing_ui_renderer(scale)
    return { gui = {}, scale = scale, render_settings = { start_layer = START_LAYER } }
end

local function assert_vector(expected_x, expected_y, expected_z, actual, message)
    assert_near(expected_x, actual[1], message .. " x")
    assert_near(expected_y, actual[2], message .. " y")

    if expected_z == nil then
        assert_equal(nil, actual[3], message .. " z")
    else
        assert_near(expected_z, actual[3], message .. " z")
    end
end

--- Returns an angle in (-pi, pi].
local function wrapped_angle(angle)
    while angle <= -math.pi do
        angle = angle + math.pi * 2
    end

    while angle > math.pi do
        angle = angle - math.pi * 2
    end

    return angle
end

--- The chevron the renderer drew, and its back's distance from the centre along the heading.
local function drawn_chevron(textures, center_x, center_y, direction_x, direction_y)
    local arrow = textures[1]
    local mid_x = arrow.x + arrow.along * 0.5
    local mid_y = arrow.y + arrow.across * 0.5
    local offset = (mid_x - center_x) * direction_x + (mid_y - center_y) * direction_y

    return arrow, offset - arrow.along * 0.5
end

local FACING_COLOR = { 180, 10, 20, 30 }

--- How far the coherency frame's art reaches along a direction, as a share of the frame texture.
-- Measured from the game's `mission_top` texture every 15 degrees from 3 o'clock to 12 o'clock;
-- the side bars reach furthest at 3 and 9 o'clock, the circle from about 50 degrees on.
local FRAME_ART_REACH = { 0.3119, 0.3044, 0.2929, 0.2626, 0.2538, 0.2535, 0.25 }

test("the facing chevron sits just beyond a round marker and points along the heading", function()
    for _, size in ipairs({ 6, 13, 15, 21, 40 }) do
        for step = 0, 15 do
            local angle = step * math.pi / 8
            local direction_x, direction_y = math.cos(angle), -math.sin(angle)
            local renderer, recorded, textures = load_renderer({})
            local constants = facing_constants(renderer)
            local ui_renderer = facing_ui_renderer(1.333)
            local label = "size " .. size .. " step " .. step

            renderer.begin_facing_outline(size * 0.5)
            renderer.draw_marker_facing_chevron(ui_renderer, 200.5, 80.5, 9, size, FACING_COLOR, direction_x,
                direction_y)

            local arrow, back = drawn_chevron(textures, 200.5, 80.5, direction_x, direction_y)
            local across = math.max(constants.min_size, math.floor(size * constants.size_ratio + 0.5))
            local along = across * constants.aspect
            local mid_x = arrow.x + along * 0.5
            local mid_y = arrow.y + across * 0.5
            local side = (mid_y - 80.5) * direction_x - (mid_x - 200.5) * direction_y

            assert_equal(0, #recorded, label .. " rectangles")
            assert_equal(1, #textures, label .. " arrows")
            assert_equal(ui_renderer.gui, arrow.gui, label .. " gui")
            assert_equal(constants.material, arrow.material, label .. " material")
            assert_vector(constants.uvs[1][1], constants.uvs[1][2], nil, arrow.uv00, label .. " crop's first corner")
            assert_vector(constants.uvs[2][1], constants.uvs[2][2], nil, arrow.uv11, label .. " crop's second corner")
            assert_vector(along * 1.333, across * 1.333, 0, arrow.size, label .. " scaled size")
            assert_vector(0, 0, 0, arrow.origin, label .. " rotation origin")
            assert_vector(along * 0.5 * 1.333, across * 0.5 * 1.333, 0, arrow.pivot, label .. " scaled pivot")
            assert_equal(1.333, arrow.scale, label .. " position scale")
            assert_near(size * 0.5 + constants.gap, back, label .. " back on the marker's edge", 1e-6)
            assert_near(0, side, label .. " centred on the heading", 1e-6)
            assert_near(0, wrapped_angle(arrow.angle - angle), label .. " turned along the heading", 1e-9)
            assert_equal(9, arrow.z, label .. " position layer")
            assert_equal(START_LAYER + 9, arrow.layer, label .. " layer")
            assert_equal(tostring(make_color(180, 10, 20, 30)), tostring(arrow.color), label .. " colour")
            assert_equal(0, arrow.material_flags, label .. " material flags")
            assert_equal(nil, arrow.render_pass, label .. " render pass")
            assert_equal(false, arrow.snap_pixel_positions, label .. " pixel snapping")
            assert_equal(0, ui_renderer.render_settings.material_flags, label .. " material flags left unset")
        end
    end

    local cardinals = { { 1, 0, 0 }, { 0, -1, math.pi * 0.5 }, { -1, 0, math.pi }, { 0, 1, -math.pi * 0.5 } }

    for _, case in ipairs(cardinals) do
        local renderer, _, textures = load_renderer({})

        renderer.begin_facing_outline(7.5)
        renderer.draw_marker_facing_chevron(facing_ui_renderer(1), 100, 100, 3, 15, FACING_COLOR, case[1], case[2])

        assert_near(0, wrapped_angle(textures[1].angle - case[3]), "cardinal angle " .. case[3], 1e-9)
    end
end)

test("the facing chevron follows the coherency frame round its side bars", function()
    for _, frame_size in ipairs({ 21, 31, 47, 97 }) do
        for step = 0, 23 do
            local angle = step * math.pi / 12
            local direction_x, direction_y = math.cos(angle), -math.sin(angle)
            local renderer, _, textures = load_renderer({})
            local label = "frame " .. frame_size .. " step " .. step
            local quadrant_step = step % 12
            local reach_step = quadrant_step <= 6 and quadrant_step or 12 - quadrant_step

            renderer.begin_facing_outline(frame_size * 0.25)
            renderer.add_facing_outline_frame(frame_size)
            renderer.draw_marker_facing_chevron(facing_ui_renderer(1), 300, 120, 11, 15, FACING_COLOR, direction_x,
                direction_y)

            local _, back = drawn_chevron(textures, 300, 120, direction_x, direction_y)

            assert_true(back >= FRAME_ART_REACH[reach_step + 1] * frame_size - 1e-9,
                label .. " chevron cuts into the frame's art")
            assert_true(back <= FRAME_ART_REACH[reach_step + 1] * frame_size + 0.03 * frame_size,
                label .. " chevron strays far from the frame")
        end
    end
end)

test("the facing chevron keeps clear of the boxes within its width, and only of those", function()
    local seed = 271

    local function random()
        seed = (seed * 1103515245 + 12345) % 2147483648

        return seed / 2147483648
    end

    for round = 1, 400 do
        local renderer, _, textures = load_renderer({})
        local constants = facing_constants(renderer)
        local angle = random() * math.pi * 2
        local direction_x, direction_y = math.cos(angle), -math.sin(angle)
        local size = 10 + math.floor(random() * 30)
        local across = math.max(constants.min_size, math.floor(size * constants.size_ratio + 0.5))
        local half_width = across * 0.5
        local boxes = {}

        renderer.begin_facing_outline(size * 0.5)

        for i = 1, 1 + math.floor(random() * constants.max_boxes) do
            local left = 100 + (random() - 0.5) * size * 3
            local top = 100 + (random() - 0.5) * size * 3
            local box = { left, top, left + 2 + random() * size, top + 2 + random() * size * 0.6 }

            boxes[i] = box
            renderer.add_facing_outline_box(box[1], box[2], box[3], box[4])
        end

        renderer.draw_marker_facing_chevron(facing_ui_renderer(1), 100, 100, 5, size, FACING_COLOR, direction_x,
            direction_y)

        local _, back = drawn_chevron(textures, 100, 100, direction_x, direction_y)
        local expected = size * 0.5

        -- Every point of a box within the chevron's width, sampled finely, against the drawn back.
        for _, box in ipairs(boxes) do
            for a = 0, 60 do
                for b = 0, 60 do
                    local x = box[1] + (box[3] - box[1]) * a / 60 - 100
                    local y = box[2] + (box[4] - box[2]) * b / 60 - 100
                    local reach = x * direction_x + y * direction_y
                    local beside = y * direction_x - x * direction_y

                    if math.abs(beside) <= half_width and reach > expected then
                        expected = reach
                    end
                end
            end
        end

        assert_near(expected + constants.gap, back, "round " .. round .. " back of the chevron", 0.35)
    end

    local renderer, _, textures = load_renderer({})

    renderer.begin_facing_outline(7.5)
    renderer.add_facing_outline_box(80, 150, 120, 170)
    renderer.add_facing_outline_box(90, 90, 110, 110)
    renderer.begin_facing_outline(7.5)
    renderer.add_facing_outline_box(110, 92, 113, 108)
    renderer.draw_marker_facing_chevron(facing_ui_renderer(1), 100, 100, 5, 15, FACING_COLOR, 1, 0)

    local _, back = drawn_chevron(textures, 100, 100, 1, 0)

    assert_near(13, back, "a box from an earlier marker was kept, or the box ahead was missed", 1e-9)

    renderer.begin_facing_outline(7.5)
    renderer.add_facing_outline_box(80, 112, 120, 130)
    renderer.draw_marker_facing_chevron(facing_ui_renderer(1), 100, 100, 5, 15, FACING_COLOR, 1, 0)

    _, back = drawn_chevron({ textures[2] }, 100, 100, 1, 0)

    assert_near(7.5, back, "a text below the marker pushed out a chevron pointing right", 1e-9)

    renderer.draw_marker_facing_chevron(facing_ui_renderer(1), 100, 100, 5, 15, FACING_COLOR, 0, 1)

    _, back = drawn_chevron({ textures[3] }, 100, 100, 0, 1)

    assert_near(30, back, "a chevron pointing down does not clear the text below the marker", 1e-9)

    renderer.draw_marker_facing_chevron(facing_ui_renderer(1), 100, 100, 5, 15, FACING_COLOR, nil, nil)
    renderer.draw_marker_facing_chevron(facing_ui_renderer(1), 100, 100, 5, 15, nil, 1, 0)

    assert_equal(3, #textures, "a chevron without a heading or a colour was drawn")
end)

test("the facing chevron draws with the render settings as the game's rotated texture draw does", function()
    local renderer, _, textures = load_renderer({})
    local ui_renderer = {
        gui = {},
        scale = 0.75,
        render_settings = {
            start_layer = 40,
            alpha_multiplier = 0.5,
            color_intensity_multiplier = 0.8,
            material_flags = 3,
            snap_pixel_positions = true,
        },
    }

    renderer.begin_facing_outline(7.5)
    renderer.draw_marker_facing_chevron(ui_renderer, 100, 100, 0, 15, FACING_COLOR, 1, 0)

    local arrow = textures[1]

    assert_equal(tostring(make_color(90, 8, 16, 24)), tostring(arrow.color), "colour multipliers")
    assert_equal(41, arrow.layer, "layer below 1 on top of the start layer")
    assert_equal(0, arrow.z, "position layer")
    assert_equal(3, arrow.material_flags, "material flags from the render settings")
    assert_equal(false, arrow.snap_pixel_positions, "pixel snapping below scale 1")
    assert_equal(3, ui_renderer.render_settings.material_flags, "material flags changed")

    ui_renderer.scale = 1
    ui_renderer.render_settings.material_flags = nil
    ui_renderer.render_settings.alpha_multiplier = nil
    ui_renderer.render_settings.color_intensity_multiplier = nil
    ui_renderer.render_pass_flag = "render_pass"
    ui_renderer.base_render_pass = "hud_bloom"
    renderer.draw_marker_facing_chevron(ui_renderer, 100, 100, 6, 15, FACING_COLOR, 1, 0)
    arrow = textures[2]

    assert_equal(tostring(make_color(180, 10, 20, 30)), tostring(arrow.color), "colour without multipliers")
    assert_equal(46, arrow.layer, "layer on top of the start layer")
    assert_equal(GUI_RENDER_PASS_LAYER, arrow.material_flags, "render pass layer flag")
    assert_equal(0, ui_renderer.render_settings.material_flags, "material flags left unset")
    assert_equal("hud_bloom", arrow.render_pass, "render pass")
    assert_equal(true, arrow.snap_pixel_positions, "pixel snapping from scale 1")

    ui_renderer.render_settings.hdr = true
    renderer.draw_marker_facing_chevron(ui_renderer, 100, 100, 6, 15, FACING_COLOR, 1, 0)
    renderer.draw_marker_facing_chevron(ui_renderer, 100, 100, 6, 15, FACING_COLOR, 1, 0)

    assert_equal("hud_bloom_hdr", textures[3].render_pass, "HDR render pass")
    assert_equal("hud_bloom_hdr", textures[4].render_pass, "HDR render pass drawn again")

    ui_renderer.render_settings.hdr = nil
    ui_renderer.render_pass_flag = nil
    ui_renderer.base_render_pass = nil
    renderer.draw_marker_facing_chevron(ui_renderer, 100, 100, 6, 15, FACING_COLOR, 1, 0)

    assert_equal(nil, textures[5].render_pass, "render pass kept from an earlier draw")

    ui_renderer.render_settings = nil
    renderer.draw_marker_facing_chevron(ui_renderer, 100, 100, 0, 15, FACING_COLOR, 1, 0)
    arrow = textures[6]

    assert_equal(1, arrow.layer, "layer without render settings")
    assert_equal(nil, arrow.material_flags, "material flags without render settings")
    assert_equal(false, arrow.snap_pixel_positions, "pixel snapping without render settings")
    assert_equal(tostring(make_color(180, 10, 20, 30)), tostring(arrow.color), "colour without render settings")
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
