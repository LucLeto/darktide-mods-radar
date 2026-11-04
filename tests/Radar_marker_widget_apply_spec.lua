-- How a pooled marker widget is styled for a target.
-- Loads the real HUD element and widget modules against a fake UI stack, takes
-- `_apply_marker_widget` from the HUD draw's upvalues, and draws through the real
-- `draw_marker_widget`. Each layer a target shows is drawn in that target's colour, a widget the
-- pool hands from target to target draws exactly what a fresh widget draws, and a layer the
-- target does not show is left untouched.

local HUD_PATH = "Radar/scripts/mods/Radar/ui/Radar_hud_element.lua"
local UI_SCALE = 4 / 3
local WHITE = { 255, 255, 255, 255 }
local ARROW_COLOR = { 200, 10, 20, 30 }
local ENEMY_KIND = "enemy_poxwalker"
local BOSS_KIND = "enemy_captain"
local ITEM_KIND = "pickup_ammo_small"
local ARROW_UP = "content/ui/materials/icons/circumstances/more_resistance_01"
local ARROW_SIZE_RATIO = 0.34
local ARROW_CENTRE_RATIO = 0.885
local ARROW_MIN_SIZE = 6
local LAYERS = { "radius_icon", "marked_ring", "plate_icon", "icon", "glyph_icon", "overlay_icon", "title_icon",
    "arrow_icon" }

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function clone(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}

    for key, field in pairs(value) do
        copy[key] = clone(field)
    end

    return copy
end

local function named_upvalue(fn, expected_name)
    for index = 1, 255 do
        local name, value = debug.getupvalue(fn, index)

        if name == nil then
            error("missing upvalue `" .. expected_name .. "`", 2)
        elseif name == expected_name then
            return value
        end
    end
end

local function color_text(color)
    return table.concat({ tostring(color[1]), tostring(color[2]), tostring(color[3]), tostring(color[4]) }, ",")
end

local function same_values(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end

    for key, value in pairs(a) do
        if not same_values(value, b[key]) then
            return false
        end
    end

    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end

    return true
end

--- Loads the HUD element against a fake UI stack and returns what the specs need from it.
local function new_harness()
    local harness = {}
    local records = nil
    local mod = {}
    local env

    function mod:get()
        return nil
    end

    function mod:info()
    end

    function mod:get_radar_color(prefix, fallback)
        if prefix == "vertical_arrow" then
            return ARROW_COLOR
        end

        return fallback
    end

    function mod:io_dofile(path)
        local chunk = assert(loadfile(path .. ".lua"))

        setfenv(chunk, env)

        return chunk()
    end

    local UIWidget = {}

    function UIWidget.create_definition(passes, scenegraph_id)
        local definition = { passes = {}, content = {}, style = {}, scenegraph_id = scenegraph_id }

        for i = 1, #passes do
            local pass = passes[i]

            definition.passes[i] = pass

            if pass.value_id then
                definition.content[pass.value_id] = pass.value
            end

            if pass.style_id then
                definition.style[pass.style_id] = pass.style
            end
        end

        return definition
    end

    function UIWidget.init(name, definition)
        return {
            name = name,
            visible = true,
            passes = definition.passes,
            content = clone(definition.content),
            style = clone(definition.style),
            scenegraph_id = definition.scenegraph_id,
            offset = { 0, 0, 0 },
        }
    end

    -- The game's widget draw, as far as a marker needs it: every visible pass in order, with
    -- the content and style it reads.
    function UIWidget.draw(widget)
        for i = 1, #widget.passes do
            local pass = widget.passes[i]
            local style = widget.style[pass.style_id]
            local visibility_function = pass.visibility_function

            if visibility_function == nil or visibility_function(widget.content, style) then
                local parts = { pass.pass_type, tostring(widget.content[pass.value_id]),
                    "at", color_text(style.offset), "size", color_text(style.size) }

                if pass.pass_type == "text" then
                    parts[#parts + 1] = "font " .. tostring(style.font_size) .. " colour " .. color_text(style.text_color)
                else
                    parts[#parts + 1] = "colour " .. color_text(style.color)
                end

                local material_values = style.material_values

                if material_values then
                    for part = 1, 4 do
                        parts[#parts + 1] = color_text(material_values["part_" .. part .. "_color"])
                    end

                    parts[#parts + 1] = tostring(material_values.display_mode)
                end

                records[#records + 1] = table.concat(parts, " ")
            end
        end
    end

    local UIRenderer = {}

    function UIRenderer.script_draw_bitmap(_, material, position, size, color)
        records[#records + 1] = string.format("bitmap %s at %s,%s,%s size %s,%s colour %s", tostring(material),
            tostring(position[1]), tostring(position[2]), tostring(position[3]), tostring(size[1]),
            tostring(size[2]), color_text(color))
    end

    local modules = {
        ["scripts/managers/ui/ui_font_settings"] = { body_small = {}, hud_body = {} },
        ["scripts/managers/ui/ui_fonts"] = {},
        ["scripts/managers/ui/ui_renderer"] = UIRenderer,
        ["scripts/managers/ui/ui_scenegraph"] = {
            world_position = function(scenegraph, id)
                return scenegraph[id].world_position
            end,
        },
        ["scripts/managers/ui/ui_widget"] = UIWidget,
        ["scripts/settings/ui/ui_hud_settings"] = {},
        ["scripts/settings/ui/ui_settings"] = {
            player_bright_slot_colors = {
                { 255, 1, 2, 3 },
                { 255, 4, 5, 6 },
                { 255, 7, 8, 9 },
                { 255, 10, 11, 12 },
            },
        },
    }
    local game_table = setmetatable({
        clone = clone,
        merge_recursive = function(destination, source)
            for key, value in pairs(source) do
                destination[key] = value
            end

            return destination
        end,
    }, { __index = table })

    env = setmetatable({
        get_mod = function()
            return mod
        end,
        class = function(name)
            return { __class_name = name }
        end,
        require = function(name)
            return assert(modules[name], "unexpected require of " .. name)
        end,
        table = game_table,
        Color = setmetatable({}, {
            __call = function(_, a, r, g, b)
                return { a, r, g, b }
            end,
        }),
        Gui = {
            scale_vector3 = function(vector, scale)
                return { vector[1] * scale, vector[2] * scale, vector[3] }
            end,
        },
        Quaternion = {},
        Vector2 = setmetatable({}, {
            __call = function(_, x, y)
                return { x, y, 0 }
            end,
        }),
        Vector3 = setmetatable({}, {
            __call = function(_, x, y, z)
                return { x, y, z }
            end,
        }),
    }, { __index = _G })

    local chunk = assert(loadfile(HUD_PATH))

    setfenv(chunk, env)

    local HudElementRadar = chunk()
    local draw_internal = named_upvalue(HudElementRadar.draw, "_draw_internal")
    local widgets = named_upvalue(draw_internal, "RadarHudWidgets")
    local ui_renderer = {
        scale = UI_SCALE,
        render_settings = {},
        ui_scenegraph = { screen = { world_position = { 3, 5, 7 } } },
    }

    harness.apply = named_upvalue(draw_internal, "_apply_marker_widget")
    harness.new_widget = named_upvalue(widgets.ensure_marker_widgets, "_create_marker_widget")

    --- Draws a widget and returns what was drawn, one line per bitmap or pass.
    function harness.draw(widget)
        records = {}
        widgets.draw_marker_widget(widget, ui_renderer)

        return records
    end

    return harness
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

--- A visual and target showing every layer, each in a colour of its own.
local function full_case()
    return {
        visual = {
            icon = "icon",
            color = { 255, 11, 12, 13 },
            plate_icon = "plate",
            plate_color = { 254, 21, 22, 23 },
            overlay_icon = "overlay",
            overlay_color = { 253, 31, 32, 33 },
            title_icon = "title",
            radius_icon = "radius",
            radius_color = { 252, 41, 42, 43 },
        },
        target = { kind = ITEM_KIND, vertical_state = "up" },
        icon_size = 20,
        radius_icon_size = 50,
    }
end

local function apply(harness, widget, case)
    harness.apply(widget, case.visual, case.x or 100, case.y or 200, case.z or 10, case.target, case.icon_size,
        case.bracket_x, case.bracket_y, case.bracket_size, case.radius_icon_size)
end

--- The colour each layer is drawn in, by the marker's own rules.
local function expected_colors(visual, target)
    local pinned = target ~= nil and target.disabled_by_mastiff == true
    local function faded(color)
        local copy = clone(color)

        if pinned then
            copy[1] = 0
        end

        return copy
    end

    return {
        icon = faded(visual.color or WHITE),
        plate = visual.plate_color or WHITE,
        overlay = faded(visual.overlay_color or WHITE),
        title = visual.color or WHITE,
        radius = visual.radius_color or visual.color or WHITE,
        G = visual.color or WHITE,
        [ARROW_UP] = ARROW_COLOR,
        ["content/ui/materials/icons/circumstances/less_resistance_01"] = ARROW_COLOR,
    }
end

--- The colour a layer was drawn in, by its material or text, whether drawn as a bitmap or as a
-- pass of the game's widget draw.
local function drawn_color(records, material)
    for i = 1, #records do
        local record = records[i]

        if record:match("^%S+ (%S+)") == material then
            return record:match(" colour (%S+)")
        end
    end

    return nil
end

test("each layer a target shows is drawn in its own colour, in pass order", function()
    local harness = new_harness()
    local case = full_case()
    local widget = harness.new_widget(1)

    apply(harness, widget, case)

    local records = harness.draw(widget)
    local colors = expected_colors(case.visual, case.target)
    local order = { "radius", "plate", "icon", "overlay", "title", ARROW_UP }

    assert_equal(#order, #records, "bitmap count")

    for i = 1, #order do
        local material = records[i]:match("^bitmap (%S+)")

        assert_equal(order[i], material, "layer " .. i)
        assert_equal(color_text(colors[material]), drawn_color(records, material), material .. " colour")
    end

    -- A glyph is text, drawn by the game's widget draw in the marker colour.
    case.visual.glyph = "G"
    apply(harness, widget, case)
    records = harness.draw(widget)

    assert_equal("255,11,12,13", drawn_color(records, "G"), "glyph colour")
end)

test("an enemy pinned by a mastiff is drawn without fill", function()
    local harness = new_harness()
    local case = full_case()
    local widget = harness.new_widget(1)

    case.target = { kind = ENEMY_KIND, disabled_by_mastiff = true }
    apply(harness, widget, case)

    local records = harness.draw(widget)

    assert_equal("0,11,12,13", drawn_color(records, "icon"), "icon")
    assert_equal("0,31,32,33", drawn_color(records, "overlay"), "overlay")
    assert_equal("254,21,22,23", drawn_color(records, "plate"), "plate keeps its fill")
    assert_equal("255,11,12,13", drawn_color(records, "title"), "title keeps its fill")
end)

test("a layer the target does not show is left untouched", function()
    local harness = new_harness()
    local widget = harness.new_widget(1)

    apply(harness, widget, full_case())

    local before = clone(widget.style)

    apply(harness, widget, {
        visual = { icon = "icon", color = { 255, 1, 2, 3 }, plate_icon = "", overlay_icon = "", title_icon = "" },
        target = { kind = ITEM_KIND },
        icon_size = 30,
        x = 40,
        y = 60,
    })

    local untouched = { "radius_icon", "plate_icon", "glyph_icon", "overlay_icon", "title_icon", "arrow_icon" }

    for i = 1, #untouched do
        local layer = untouched[i]

        assert_equal(true, same_values(before[layer], widget.style[layer]), layer .. " was restyled")
    end

    assert_equal(false, same_values(before.icon, widget.style.icon), "the icon was not restyled")

    local records = harness.draw(widget)

    assert_equal(1, #records, "only the icon is drawn")
    assert_equal("255,1,2,3", drawn_color(records, "icon"), "icon")

    -- An enemy's vertical arrow is sized from the overlay, which stays uncoloured while hidden.
    local overlay_color = clone(widget.style.overlay_icon.color)

    apply(harness, widget, {
        visual = { icon = "icon", overlay_color = { 255, 9, 9, 9 }, overlay_base_size = 10, background_base_size = 20 },
        target = { kind = ENEMY_KIND, vertical_state = "up" },
        icon_size = 24,
        bracket_size = 40,
    })

    assert_equal(true, same_values(overlay_color, widget.style.overlay_icon.color), "the hidden overlay was coloured")
end)

--- The arrow's top left and size for a base box and size.
local function expected_arrow(base_x, base_y, base_size, arrow_base)
    local arrow_size = math.max(ARROW_MIN_SIZE, math.floor(arrow_base * ARROW_SIZE_RATIO + 0.5))
    local inset = (base_size - arrow_base) * 0.5
    local centre = arrow_base * ARROW_CENTRE_RATIO

    return math.floor(base_x + inset + centre - arrow_size * 0.5 + 0.5),
        math.floor(base_y + inset + centre - arrow_size * 0.5 + 0.5), arrow_size
end

test("an enemy's vertical arrow sits on its brackets, sized from its overlay whether shown or not", function()
    local harness = new_harness()

    for _, overlay_icon in ipairs({ "overlay", "" }) do
        local widget = harness.new_widget(1)

        apply(harness, widget, {
            visual = {
                icon = "icon",
                overlay_icon = overlay_icon,
                overlay_base_size = 10,
                background_base_size = 20,
            },
            target = { kind = ENEMY_KIND, vertical_state = "up" },
            icon_size = 24,
            bracket_x = 90,
            bracket_y = 190,
            bracket_size = 40,
        })

        local x, y, size = expected_arrow(90, 190, 40, 12)
        local arrow_style = widget.style.arrow_icon

        assert_equal(x, arrow_style.offset[1], "arrow x with overlay `" .. overlay_icon .. "`")
        assert_equal(y, arrow_style.offset[2], "arrow y with overlay `" .. overlay_icon .. "`")
        assert_equal(size, arrow_style.size[1], "arrow size with overlay `" .. overlay_icon .. "`")
    end

    -- A boss's and an item's arrow keep to the icon box instead.
    for _, kind in ipairs({ BOSS_KIND, ITEM_KIND }) do
        local widget = harness.new_widget(1)

        apply(harness, widget, {
            visual = { icon = "icon", overlay_icon = "overlay", overlay_base_size = 10, background_base_size = 20 },
            target = { kind = kind, vertical_state = "up" },
            icon_size = 24,
            bracket_x = 90,
            bracket_y = 190,
            bracket_size = 40,
        })

        local x, y, size = expected_arrow(100, 200, 24, 24)
        local arrow_style = widget.style.arrow_icon

        assert_equal(x, arrow_style.offset[1], kind .. " arrow x")
        assert_equal(y, arrow_style.offset[2], kind .. " arrow y")
        assert_equal(size, arrow_style.size[1], kind .. " arrow size")
    end
end)

test("a widget handed from target to target draws what a fresh widget draws", function()
    local harness = new_harness()
    local reused = harness.new_widget(1)
    local seed = 4242

    local function random()
        seed = (seed * 1103515245 + 12345) % 2147483648

        return seed / 2147483648
    end

    local function chance(probability)
        return random() < probability
    end

    local function random_int(low, high)
        return low + math.floor(random() * (high - low + 1))
    end

    local function random_color()
        return { random_int(0, 255), random_int(0, 255), random_int(0, 255), random_int(0, 255) }
    end

    local kinds = { ENEMY_KIND, BOSS_KIND, ITEM_KIND, false }
    local verticals = { "up", "down", false, false }

    for i = 1, 600 do
        local kind = kinds[random_int(1, #kinds)]
        local vertical = verticals[random_int(1, #verticals)]
        local visual = {
            icon = chance(0.9) and "icon" or nil,
            color = chance(0.9) and random_color() or nil,
            plate_icon = chance(0.4) and "plate" or (chance(0.2) and "" or nil),
            plate_color = chance(0.7) and random_color() or nil,
            overlay_icon = chance(0.4) and "overlay" or (chance(0.2) and "" or nil),
            overlay_color = chance(0.7) and random_color() or nil,
            overlay_base_size = chance(0.4) and random_int(4, 30) or nil,
            background_base_size = chance(0.5) and random_int(10, 40) or nil,
            overlay_size = chance(0.2) and random_int(4, 30) or nil,
            overlay_anchor = chance(0.3) and "bottom_right" or nil,
            title_icon = chance(0.3) and "title" or nil,
            radius_icon = chance(0.3) and "radius" or nil,
            radius_color = chance(0.5) and random_color() or nil,
            glyph = chance(0.15) and "G" or nil,
            marked_player_slots_mask = chance(0.15) and random_int(1, 15) or nil,
            value_text = chance(0.3) and tostring(random_int(1, 99)) or nil,
            arrow_base_size = chance(0.2) and random_int(8, 30) or nil,
        }
        local case = {
            visual = visual,
            target = kind and {
                kind = kind,
                vertical_state = vertical or nil,
                disabled_by_mastiff = chance(0.2),
            } or nil,
            x = random() * 400,
            y = random() * 400,
            z = random_int(0, 20),
            icon_size = random_int(6, 48),
            bracket_x = chance(0.7) and random() * 400 or nil,
            bracket_y = random() * 400,
            bracket_size = chance(0.8) and random_int(8, 60) or nil,
            radius_icon_size = chance(0.8) and random() * 120 or nil,
        }
        local fresh = harness.new_widget(1)

        apply(harness, reused, case)
        apply(harness, fresh, case)

        local reused_records = harness.draw(reused)
        local fresh_records = harness.draw(fresh)

        assert_equal(#fresh_records, #reused_records, "case " .. i .. " draw count")

        for j = 1, #fresh_records do
            assert_equal(fresh_records[j], reused_records[j], "case " .. i .. " draw " .. j)
        end

        local colors = expected_colors(visual, case.target)

        for material, color in pairs(colors) do
            local drawn = drawn_color(reused_records, material)

            if drawn ~= nil then
                assert_equal(color_text(color), drawn, "case " .. i .. " " .. material .. " colour")
            end
        end
    end
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
