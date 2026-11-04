-- How big a marker and its brackets are drawn, and where.
-- Loads the real HUD element against a fake UI stack and runs its draw loop with the renderer,
-- the widget pool and the map geometry swapped out through upvalues, so each marker's size, its
-- brackets' size and both boxes' top left corners are read as the loop hands them on. A target's
-- visual is the one the test gives it; the sizes follow from the radar size, the settings group
-- and enemy category sliders, and the size limits of an item or of an enemy's category.

local HUD_PATH = "Radar/scripts/mods/Radar/ui/Radar_hud_element.lua"
local RADAR_X = 100
local RADAR_Y = 40
local RADAR_RADIUS = 150
local CENTRE_X = RADAR_X + RADAR_RADIUS
local CENTRE_Y = RADAR_Y + RADAR_RADIUS
local ENEMY_LIMITS = {
    horde = { 6, 28 },
    common = { 6, 40 },
    shooter = { 8, 56 },
}
local DEFAULT_ENEMY_LIMITS = { 10, 72 }
local GROUP_BY_KIND = {
    pickup_ammo_small = "common_pickups_group",
    medicae_station = "stations_group",
    pickup_grenade = "grenades_group",
}

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

local function upvalue_index(fn, expected_name)
    for index = 1, 255 do
        local name = debug.getupvalue(fn, index)

        if name == nil then
            error("missing upvalue `" .. expected_name .. "`", 2)
        elseif name == expected_name then
            return index
        end
    end
end

local function noop()
end

local function has_enemy_prefix(kind)
    return string.sub(tostring(kind), 1, 6) == "enemy_"
end

--- Loads the HUD element and returns a harness that draws targets through its marker loop.
-- The world holds what the settings say: the radar size, whether icons scale with it, the
-- factor of each settings group and enemy, and each enemy kind's category.
local function new_harness()
    local harness = {
        world = {
            radar_size = 300,
            scale_with_radar = true,
            group_factor = {},
            enemy_factor = {},
            category = {},
        },
    }
    local world = harness.world
    local mod = { _radar_color_cache_generation = 1 }
    local env

    function mod:get(setting_id)
        if setting_id == "scale_icons_with_radar_size" then
            return world.scale_with_radar
        end

        return nil
    end

    function mod:info()
    end

    function mod:get_radar_color(_, fallback)
        return fallback
    end

    function mod:get_configured_radar_size()
        return world.radar_size
    end

    function mod:get_marker_scale_group(kind)
        if has_enemy_prefix(kind) then
            return "enemies_group"
        end

        return GROUP_BY_KIND[kind]
    end

    function mod:get_marker_scale_factor(group_name)
        return world.group_factor[group_name] or 1
    end

    function mod:get_enemy_category_scale_factor(kind)
        return world.enemy_factor[kind] or 1
    end

    function mod:get_enemy_radar_definition(kind)
        local category = world.category[kind]

        return category and { category = category } or nil
    end

    function mod:get_enemy_marker_mode()
        return "marked_icon"
    end

    function mod:get_radar_size()
        return RADAR_RADIUS * 2
    end

    function mod:get_radar_range()
        return 25
    end

    function mod:get_radar_origin()
        return RADAR_X, RADAR_Y, 10, RADAR_RADIUS
    end

    function mod:get_max_radar_markers()
        return 200
    end

    function mod:radar_projection_forward()
        return nil, nil
    end

    -- A target's position is already its offset from the radar centre in pixels.
    function mod:project_target_to_radar(_, _, _, position)
        return position[1], position[2]
    end

    function mod:io_dofile(path)
        local chunk = assert(loadfile(path .. ".lua"))

        setfenv(chunk, env)

        return chunk()
    end

    local modules = {
        ["scripts/managers/ui/ui_font_settings"] = { body_small = {}, hud_body = {} },
        ["scripts/managers/ui/ui_fonts"] = {},
        ["scripts/managers/ui/ui_renderer"] = {},
        ["scripts/managers/ui/ui_scenegraph"] = {},
        ["scripts/managers/ui/ui_widget"] = {
            create_definition = function(passes)
                return { passes = passes, content = {}, style = {} }
            end,
            init = function(_, definition)
                return clone(definition)
            end,
        },
        ["scripts/settings/ui/ui_hud_settings"] = {},
        ["scripts/settings/ui/ui_settings"] = { player_bright_slot_colors = {} },
    }

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
        table = setmetatable({
            clone = clone,
            merge_recursive = function(destination, source)
                for key, value in pairs(source) do
                    destination[key] = value
                end

                return destination
            end,
        }, { __index = table }),
        Color = setmetatable({}, {
            __call = function(_, a, r, g, b)
                return { a, r, g, b }
            end,
        }),
        Gui = {},
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
    local draw_internal
    local records, brackets

    for index = 1, 255 do
        local name, value = debug.getupvalue(HudElementRadar.draw, index)

        assert(name ~= nil, "missing upvalue `_draw_internal`")

        if name == "_draw_internal" then
            draw_internal = value
            break
        end
    end

    local function replace(name, value)
        debug.setupvalue(draw_internal, upvalue_index(draw_internal, name), value)
    end

    replace("RadarHudWidgets", {
        ensure_overview_scale_widget = noop,
        ensure_marker_widgets = noop,
        draw_marker_widget = noop,
        clear_marker_widget = noop,
        clear_overview_scale_widget = noop,
    })
    replace("RadarHudRenderer", {
        draw_radar_frame = noop,
        draw_radar_frame_background = noop,
        draw_radar_frame_foreground = noop,
        draw_box = noop,
        draw_marker_brackets = function(_, x, y, _, size)
            brackets[#brackets + 1] = { x = x, y = y, size = size }
        end,
    })
    replace("RadarStrikemapGeometry", {
        is_active = function()
            return false
        end,
    })
    replace("RadarNavmesh", {
        is_active = function()
            return false
        end,
    })
    replace("_target_visual", function(target)
        return target.visual
    end)
    replace("_apply_marker_widget", function(_, _, x, y, _, target, icon_size, bracket_x, bracket_y, bracket_size)
        if target ~= nil then
            records[#records + 1] = {
                target = target,
                x = x,
                y = y,
                size = icon_size,
                bracket_x = bracket_x,
                bracket_y = bracket_y,
                bracket_size = bracket_size,
            }
        end
    end)
    replace("_draw_marker_value_text", noop)
    replace("_draw_overview_scale_overlay", noop)
    replace("_draw_screen_highlights", noop)

    local element = { _marker_widgets = {} }

    for i = 1, 301 do
        element._marker_widgets[i] = {}
    end

    --- Draws one radar frame at time `t` and returns, per drawn target, what the loop handed to
    -- its widget, and every bracket drawn.
    function harness.draw(targets, t)
        records, brackets = {}, {}
        draw_internal(element, {}, { player_position = { 0, 0, 0 }, targets = targets }, t, nil)

        return records, brackets
    end

    --- Makes the next draw read the settings again, as a settings change does.
    function harness.settings_changed()
        mod._radar_color_cache_generation = mod._radar_color_cache_generation + 1
    end

    return harness
end

local function target(kind, visual, x, y)
    return { kind = kind, visual = visual, position = { x or 0, y or 0, 0 }, render_layer = 0 }
end

local function scaled(base_size, scale, min_size, max_size)
    local size = math.floor(base_size * scale + 0.5)

    if size < min_size then
        size = min_size
    end

    if size > max_size then
        size = max_size
    end

    return size
end

--- The marker and bracket size of a kind and visual, by the radar's rules and the world's settings.
local function expected_sizes(world, kind, visual)
    local radar_scale = 1

    if world.scale_with_radar ~= false then
        radar_scale = math.min(3, math.max(0.5, world.radar_size / 300))
    end

    local base_size = visual.size or 14
    local bracket_base_size = visual.bracket_base_size or visual.size or 14
    local group = has_enemy_prefix(kind) and "enemies_group" or GROUP_BY_KIND[kind]
    local scale = radar_scale * (group and world.group_factor[group] or 1)

    if has_enemy_prefix(kind) then
        local limits = ENEMY_LIMITS[world.category[kind]] or DEFAULT_ENEMY_LIMITS
        local marker_size = scaled(base_size, scale * (world.enemy_factor[kind] or 1), limits[1], limits[2])
        local bracket_scale = 1 + (marker_size / math.max(1, visual.size or bracket_base_size) - 1)

        return marker_size, scaled(bracket_base_size, bracket_scale, limits[1], limits[2])
    end

    return scaled(base_size, scale, 10, 48), scaled(bracket_base_size, scale, 10, 64)
end

local function check_sizes(record, marker_size, bracket_size, label)
    assert_equal(marker_size, record.size, label .. " marker size")
    assert_equal(bracket_size, record.bracket_size, label .. " bracket size")
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("an item's marker and brackets scale with the radar and its group, within 10 to 48 and 10 to 64 pixels",
    function()
        local harness = new_harness()

        harness.world.radar_size = 450
        harness.world.group_factor.common_pickups_group = 2

        local records = harness.draw({
            target("pickup_ammo_small", { size = 14 }),
            target("pickup_ammo_small", { size = 20 }),
            target("pickup_ammo_small", { size = 30 }),
            target("pickup_ammo_small", { size = 14, bracket_base_size = 18 }),
        }, 10)

        check_sizes(records[1], 42, 42, "three times 14")
        check_sizes(records[2], 48, 60, "three times 20")
        check_sizes(records[3], 48, 64, "three times 30")
        check_sizes(records[4], 42, 54, "a bracket base of 18")

        harness = new_harness()
        harness.world.scale_with_radar = false
        harness.world.radar_size = 900
        harness.world.group_factor.common_pickups_group = 0.5
        records = harness.draw({
            target("pickup_ammo_small", { size = 14 }),
            target("pickup_ammo_small", { size = 25 }),
            target("medicae_station", { size = 14 }),
        }, 10)

        check_sizes(records[1], 10, 10, "half of 14")
        check_sizes(records[2], 13, 13, "half of 25")
        check_sizes(records[3], 14, 14, "another group")
    end)

test("an enemy's brackets follow its drawn marker, within its category's limits", function()
    local harness = new_harness()
    local world = harness.world

    world.group_factor.enemies_group = 1.5
    world.enemy_factor.enemy_renegade_gunner = 2
    world.category.enemy_poxwalker = "horde"
    world.category.enemy_renegade_gunner = "shooter"
    world.category.enemy_cultist_melee = "common"
    world.category.enemy_renegade_flamer = "special"

    local records = harness.draw({
        target("enemy_poxwalker", { size = 10, bracket_base_size = 14 }),
        target("enemy_poxwalker", { size = 20, bracket_base_size = 24 }),
        target("enemy_renegade_gunner", { size = 12, bracket_base_size = 16 }),
        target("enemy_renegade_gunner", { size = 4 }),
        target("enemy_renegade_gunner", { size = 2 }),
        target("enemy_cultist_melee", { size = 30 }),
        target("enemy_renegade_flamer", { size = 4 }),
        target("enemy_without_definition", { size = 40 }),
        target("enemy_without_definition", { size = 60 }),
    }, 10)

    check_sizes(records[1], 15, 21, "a horde enemy")
    check_sizes(records[2], 28, 28, "a horde enemy at its limit")
    check_sizes(records[3], 36, 48, "a shooter with a factor of its own")
    check_sizes(records[4], 12, 12, "a small shooter")
    check_sizes(records[5], 8, 8, "a shooter under its limit")
    check_sizes(records[6], 40, 40, "a common enemy at its limit")
    check_sizes(records[7], 10, 10, "a special under its limit")
    check_sizes(records[8], 60, 60, "an enemy without a category")
    check_sizes(records[9], 72, 72, "an enemy without a category at its limit")
end)

test("a marker box and its brackets are centred on the marker's whole-pixel position", function()
    local harness = new_harness()

    harness.world.group_factor.enemies_group = 1.5
    harness.world.category.enemy_poxwalker = "horde"

    local records, brackets = harness.draw({
        target("pickup_ammo_small", { size = 14 }, 0.5, -0.5),
        target("pickup_ammo_small", { size = 15, bracket_base_size = 20 }, -10.5, 3.49),
        target("enemy_poxwalker", { size = 10, bracket_base_size = 14, accent_color = { 255, 1, 2, 3 } }, 10.4,
            -20.6),
    }, 10)

    assert_equal(3, #records, "drawn markers")

    local expected = {
        { x = 244, y = 183, bracket_x = 244, bracket_y = 183 },
        { x = 233, y = 186, bracket_x = 230, bracket_y = 183 },
        { x = 253, y = 162, bracket_x = 250, bracket_y = 159 },
    }

    for i = 1, #expected do
        for key, value in pairs(expected[i]) do
            assert_equal(value, records[i][key], "marker " .. i .. " " .. key)
        end
    end

    assert_equal(1, #brackets, "drawn brackets")
    assert_equal(250, brackets[1].x, "bracket x")
    assert_equal(159, brackets[1].y, "bracket y")
    assert_equal(21, brackets[1].size, "bracket size")
end)

test("a changed slider reaches the markers when the settings are read again", function()
    local harness = new_harness()
    local world = harness.world
    local targets = {
        target("pickup_ammo_small", { size = 14 }),
        target("enemy_poxwalker", { size = 14 }),
    }

    world.category.enemy_poxwalker = "elite"

    local records = harness.draw(targets, 10)

    check_sizes(records[1], 14, 14, "an item before the change")
    check_sizes(records[2], 14, 14, "an enemy before the change")

    world.group_factor.common_pickups_group = 2
    world.enemy_factor.enemy_poxwalker = 3
    records = harness.draw(targets, 10.5)

    check_sizes(records[1], 14, 14, "an item until the settings are read again")
    check_sizes(records[2], 14, 14, "an enemy until the settings are read again")

    records = harness.draw(targets, 11)

    check_sizes(records[1], 28, 28, "an item a second later")
    check_sizes(records[2], 42, 42, "an enemy a second later")

    world.radar_size = 150
    harness.settings_changed()
    records = harness.draw(targets, 11.1)

    check_sizes(records[1], 14, 14, "an item right after a settings change")
    check_sizes(records[2], 21, 21, "an enemy right after a settings change")
end)

test("only kinds that start with enemy_ are drawn with an enemy's scale and limits", function()
    local harness = new_harness()

    harness.world.group_factor.enemies_group = 0.5

    local kinds = { "enemy_", "enemyless", "Enemy_poxwalker", "my_enemy_poxwalker", 5 }
    local expected = {
        { 50, 50 },
        { 48, 64 },
        { 48, 64 },
        { 48, 64 },
        { 48, 64 },
    }

    for round = 1, 2 do
        local targets = {}

        for i = 1, #kinds do
            targets[i] = target(kinds[i], { size = 100 })
        end

        local records = harness.draw(targets, 10 + round)

        for i = 1, #kinds do
            check_sizes(records[i], expected[i][1], expected[i][2], "round " .. round .. " " .. tostring(kinds[i]))
        end
    end
end)

test("random markers are drawn at the size and place the rules give them", function()
    local harness = new_harness()
    local world = harness.world
    local seed = 2718

    local function random()
        seed = (seed * 1103515245 + 12345) % 2147483648

        return seed / 2147483648
    end

    local function pick(list)
        return list[math.floor(random() * #list) + 1]
    end

    local kinds = { "pickup_ammo_small", "medicae_station", "pickup_grenade", "radar_unknown_kind", "enemy_poxwalker",
        "enemy_renegade_gunner", "enemy_cultist_melee", "enemy_renegade_flamer", "enemy_daemonhost",
        "enemy_without_definition" }
    local enemy_kinds = { "enemy_poxwalker", "enemy_renegade_gunner", "enemy_cultist_melee", "enemy_renegade_flamer",
        "enemy_daemonhost", "enemy_without_definition" }
    local groups = { "common_pickups_group", "stations_group", "grenades_group", "enemies_group" }
    local categories = { "horde", "common", "shooter", "special", "elite", "monster", false }
    local factors = { 0.5, 0.75, 1, 1.25, 1.333, 2, 3 }
    local sizes = { 4, 8, 10, 12, 13, 14, 15, 16, 18, 20, 24, 32, 13.5, 0 }
    local t = 10
    local compared = 0

    for round = 1, 40 do
        world.radar_size = pick({ 100, 220, 300, 451, 700, 1000 })
        world.scale_with_radar = pick({ true, false })

        for i = 1, #groups do
            world.group_factor[groups[i]] = pick(factors)
        end

        for i = 1, #enemy_kinds do
            local kind = enemy_kinds[i]

            world.enemy_factor[kind] = pick(factors)
            world.category[kind] = pick(categories) or nil
        end

        harness.settings_changed()

        local targets = {}

        for i = 1, 150 do
            local visual = { size = random() < 0.9 and pick(sizes) or nil, accent_color = { 255, 1, 2, 3 } }

            if random() < 0.4 then
                visual.bracket_base_size = pick({ 6, 10, 14, 17, 20, 26, 9.5 })
            end

            targets[i] = target(pick(kinds), visual, (random() - 0.5) * 280, (random() - 0.5) * 280)
        end

        t = t + 0.25

        local records, brackets = harness.draw(targets, t)
        local bracket_index = 0

        assert_equal(#targets, #records, "round " .. round .. " drawn markers")

        for i = 1, #records do
            local record = records[i]
            local drawn = record.target
            local label = "round " .. round .. " marker " .. i .. " " .. drawn.kind
            local marker_size, bracket_size = expected_sizes(world, drawn.kind, drawn.visual)
            local centre_x = math.floor(CENTRE_X + drawn.position[1] + 0.5)
            local centre_y = math.floor(CENTRE_Y + drawn.position[2] + 0.5)

            check_sizes(record, marker_size, bracket_size, label)
            assert_equal(centre_x - math.floor(marker_size / 2), record.x, label .. " x")
            assert_equal(centre_y - math.floor(marker_size / 2), record.y, label .. " y")
            assert_equal(centre_x - math.floor(bracket_size / 2), record.bracket_x, label .. " bracket x")
            assert_equal(centre_y - math.floor(bracket_size / 2), record.bracket_y, label .. " bracket y")

            if has_enemy_prefix(drawn.kind) then
                bracket_index = bracket_index + 1

                local bracket = brackets[bracket_index]

                assert_equal(record.bracket_x, bracket.x, label .. " drawn bracket x")
                assert_equal(record.bracket_y, bracket.y, label .. " drawn bracket y")
                assert_equal(record.bracket_size, bracket.size, label .. " drawn bracket size")
            end

            compared = compared + 1
        end

        assert_equal(bracket_index, #brackets, "round " .. round .. " drawn brackets")
    end

    assert_equal(6000, compared, "compared markers")
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
