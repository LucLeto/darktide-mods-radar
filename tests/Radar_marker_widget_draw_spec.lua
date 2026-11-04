-- A marker widget must draw exactly what `UIWidget.draw` would draw for it.
-- Loads the real widget module against a fake UI stack whose `UIWidget.create_definition` and
-- `UIWidget.init` build widgets as the game does, and compares each draw with a model of the
-- game's widget draw: the visible passes in definition order, a plain texture pass ending in
-- `UIRenderer.script_draw_bitmap` at the scenegraph position plus the widget and style offsets,
-- with both vectors scaled by `Gui.scale_vector3`. A visible pass of any other kind needs the
-- game's own draw.

local WIDGETS_PATH = "Radar/scripts/mods/Radar/ui/Radar_hud_widgets.lua"
local UI_SCALE = 4 / 3

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

--- Loads the widget module against a fake UI stack, with the HUD element's marker pool created.
local function new_harness()
    local harness = { bitmaps = {}, widget_draws = {} }
    local mod = {}

    function mod:get()
        return nil
    end

    function mod:info()
    end

    local UIWidget = {}

    function UIWidget.create_definition(passes, scenegraph_id)
        local definition = { passes = {}, content = {}, style = {}, scenegraph_id = scenegraph_id }

        for i = 1, #passes do
            local pass = passes[i]

            definition.passes[i] = pass
            definition.content[pass.value_id] = pass.value
            definition.style[pass.style_id] = pass.style
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

    function UIWidget.draw(widget)
        harness.widget_draws[#harness.widget_draws + 1] = widget
    end

    local UIRenderer = {}

    function UIRenderer.script_draw_bitmap(ui_renderer, material, position, size, color, retained_id)
        local render_settings = ui_renderer.render_settings

        harness.bitmaps[#harness.bitmaps + 1] = {
            material = material,
            position = position,
            size = size,
            color = color,
            retained_id = retained_id,
            alpha_multiplier = render_settings.alpha_multiplier,
            color_intensity_multiplier = render_settings.color_intensity_multiplier,
            material_flags = render_settings.material_flags,
        }
    end

    local modules = {
        ["scripts/managers/ui/ui_font_settings"] = { hud_body = { font_type = "hud_body" } },
        ["scripts/managers/ui/ui_renderer"] = UIRenderer,
        ["scripts/managers/ui/ui_scenegraph"] = {
            world_position = function(scenegraph, id)
                return scenegraph[id].world_position
            end,
        },
        ["scripts/managers/ui/ui_widget"] = UIWidget,
    }
    local globals = {
        get_mod = function()
            return mod
        end,
        require = function(name)
            return assert(modules[name], "unexpected require of " .. name)
        end,
        Gui = {
            scale_vector3 = function(vector, scale)
                return { scaled = vector, scale = scale }
            end,
        },
        Vector2 = function(x, y)
            return { "Vector2", x, y }
        end,
        Vector3 = function(x, y, z)
            return { "Vector3", x, y, z }
        end,
    }
    local previous = {}

    for name, value in pairs(globals) do
        previous[name] = rawget(_G, name)
        rawset(_G, name, value)
    end

    harness.widgets = assert(loadfile(WIDGETS_PATH))()

    for name in pairs(globals) do
        rawset(_G, name, previous[name])
    end

    local hud = {}

    harness.widgets.ensure_marker_widgets(hud)
    harness.widget = hud._marker_widgets[1]
    harness.widgets.clear_marker_widget(harness.widget)
    harness.render_settings = {}
    harness.ui_renderer = {
        scale = UI_SCALE,
        render_settings = harness.render_settings,
        ui_scenegraph = { screen = { world_position = { 3, 5, 7 } } },
    }

    function harness.draw(widget)
        harness.bitmaps = {}
        harness.widget_draws = {}
        harness.widgets.draw_marker_widget(widget or harness.widget, harness.ui_renderer)
    end

    return harness
end

--- Whether the game's texture pass draws a pass as a plain bitmap.
local function is_plain_texture(widget, pass)
    return pass.pass_type == "texture" and widget.style[pass.style_id].material_values == nil
end

--- The bitmaps the game's widget draw makes for a widget, or nil when a visible pass is not a
-- plain texture.
local function expected_bitmaps(widget, ui_renderer)
    local world_position = ui_renderer.ui_scenegraph[widget.scenegraph_id].world_position
    local expected = {}

    for i = 1, #widget.passes do
        local pass = widget.passes[i]
        local style = widget.style[pass.style_id]
        local visibility_function = pass.visibility_function

        if visibility_function == nil or visibility_function(widget.content, style) then
            if not is_plain_texture(widget, pass) then
                return nil
            end

            local offset = style.offset

            expected[#expected + 1] = {
                material = widget.content[pass.value_id],
                position = {
                    world_position[1] + widget.offset[1] + offset[1],
                    world_position[2] + widget.offset[2] + offset[2],
                    world_position[3] + widget.offset[3] + offset[3],
                },
                size = { style.size[1], style.size[2] },
                color = style.color,
            }
        end
    end

    return expected
end

local function assert_same_bitmaps(expected, actual, label)
    assert_equal(#expected, #actual, label .. " bitmap count")

    for i = 1, #expected do
        local want, got = expected[i], actual[i]
        local position, size = got.position, got.size
        local where = label .. " bitmap " .. i

        assert_equal(want.material, got.material, where .. " material")
        assert_equal(UI_SCALE, position.scale, where .. " position scale")
        assert_equal("Vector3", position.scaled[1], where .. " position type")

        for axis = 1, 3 do
            assert_equal(want.position[axis], position.scaled[axis + 1], where .. " position axis " .. axis)
        end

        assert_equal(UI_SCALE, size.scale, where .. " size scale")
        assert_equal("Vector2", size.scaled[1], where .. " size type")
        assert_equal(want.size[1], size.scaled[2], where .. " width")
        assert_equal(want.size[2], size.scaled[3], where .. " height")
        assert_true(rawequal(want.color, got.color), where .. " is not drawn with its style colour")
        assert_equal(nil, got.retained_id, where .. " retained id")
    end
end

local seed = 7

local function random_int(low, high)
    seed = (seed * 1103515245 + 12345) % 2147483648

    return low + seed % (high - low + 1)
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("draws every mix of texture layers as the game's widget draw would", function()
    local harness = new_harness()
    local widget = harness.widget
    local layers = {}

    for i = 1, #widget.passes do
        local pass = widget.passes[i]

        if is_plain_texture(widget, pass) then
            layers[#layers + 1] = pass.value_id
        end
    end

    assert_true(#layers >= 6, "the marker definition lost its texture layers")
    widget.offset = { 2, -4, 1 }
    widget.content.glyph_icon = ""
    widget.content.marked_ring = nil

    for mask = 0, 2 ^ #layers - 1 do
        for j = 1, #layers do
            local layer = layers[j]
            local style = widget.style[layer]
            local shown = math.floor(mask / 2 ^ (j - 1)) % 2 == 1

            widget.content[layer] = shown and ("material/" .. layer .. "/" .. mask) or (j % 2 == 0 and "" or nil)
            style.offset = { random_int(-40, 400), random_int(-40, 400), random_int(0, 30) }
            style.size = { random_int(1, 64), random_int(1, 64) }
            style.color = { random_int(0, 255), random_int(0, 255), random_int(0, 255), random_int(0, 255) }
        end

        local expected = expected_bitmaps(widget, harness.ui_renderer)

        harness.draw()

        assert_equal(0, #harness.widget_draws, "mask " .. mask .. " fell back to UIWidget.draw")
        assert_same_bitmaps(expected, harness.bitmaps, "mask " .. mask)
    end
end)

test("leaves a shown marked ring or glyph to UIWidget.draw", function()
    local harness = new_harness()
    local widget = harness.widget
    local others = 0

    widget.content.icon = "material/icon"

    for i = 1, #widget.passes do
        local pass = widget.passes[i]

        if not is_plain_texture(widget, pass) then
            local id = pass.value_id

            others = others + 1
            widget.content[id] = "value/" .. id
            assert_equal(nil, expected_bitmaps(widget, harness.ui_renderer), id .. " needs the game's draw")
            harness.draw()
            assert_equal(1, #harness.widget_draws, id .. " is not drawn by UIWidget.draw")
            assert_true(harness.widget_draws[1] == widget, id .. " handed UIWidget.draw another widget")
            assert_equal(0, #harness.bitmaps, id .. " drew bitmaps of its own as well")

            widget.content[id] = ""
            harness.draw()
            assert_equal(0, #harness.widget_draws, id .. " left empty still falls back")
            assert_same_bitmaps(expected_bitmaps(widget, harness.ui_renderer), harness.bitmaps, id .. " left empty")

            widget.content[id] = nil
        end
    end

    assert_equal(2, others, "layers that need the game's draw")
end)

test("applies the renderer's multipliers only while the widget draws", function()
    local harness = new_harness()
    local render_settings = harness.render_settings

    harness.widget.content.icon = "material/icon"
    render_settings.alpha_multiplier = 0.5
    harness.ui_renderer.alpha_multiplier = 0.8
    harness.ui_renderer.color_intensity_multiplier = 0.9
    harness.draw()

    local bitmap = harness.bitmaps[1]

    assert_equal(0.5 * 0.8, bitmap.alpha_multiplier, "alpha multiplier while drawing")
    assert_equal(0.9, bitmap.color_intensity_multiplier, "colour intensity multiplier while drawing")
    assert_equal(0, bitmap.material_flags, "material flags while drawing")
    assert_equal(0.5, render_settings.alpha_multiplier, "alpha multiplier after the draw")
    assert_equal(nil, render_settings.color_intensity_multiplier, "colour intensity multiplier after the draw")
    assert_equal(0, render_settings.material_flags, "the draw leaves material flags set, as UIWidget.draw does")

    harness.ui_renderer.alpha_multiplier = nil
    harness.ui_renderer.color_intensity_multiplier = nil
    render_settings.alpha_multiplier = nil
    render_settings.material_flags = 4
    harness.draw()
    bitmap = harness.bitmaps[1]

    assert_equal(1, bitmap.alpha_multiplier, "alpha multiplier without multipliers")
    assert_equal(1, bitmap.color_intensity_multiplier, "colour intensity multiplier without multipliers")
    assert_equal(4, bitmap.material_flags, "existing material flags")
    assert_equal(nil, render_settings.alpha_multiplier, "alpha multiplier restored to nil")
    assert_equal(4, render_settings.material_flags, "existing material flags kept")
end)

test("uses UIWidget.draw without render settings or in forced retained mode", function()
    local harness = new_harness()

    harness.widget.content.icon = "material/icon"
    harness.render_settings.force_retained_mode = true
    harness.draw()
    assert_equal(1, #harness.widget_draws, "forced retained mode")
    assert_equal(0, #harness.bitmaps, "forced retained mode drew bitmaps of its own")

    harness.ui_renderer.render_settings = nil
    harness.draw()
    assert_equal(1, #harness.widget_draws, "no render settings")
    assert_equal(0, #harness.bitmaps, "no render settings drew bitmaps of its own")
end)

test("clears the widget's dirty flag, as UIWidget.draw does", function()
    local harness = new_harness()

    harness.widget.content.icon = "material/icon"
    harness.widget.dirty = true
    harness.draw()
    assert_equal(nil, harness.widget.dirty, "dirty flag after the draw")
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
