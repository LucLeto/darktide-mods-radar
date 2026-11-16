-- How much of a marker's opacity its height difference from the player keeps, from the settings to
-- the radar target.
-- Installs the real runtime helpers and tracking modules into a fake shared environment and builds
-- radar targets through `_collect_radar_targets`, reached through the upvalues of the update the
-- `StateGameplay.update` hook runs. The shared curve keeps a marker's opacity up to the fade start,
-- falls in a straight line to the minimum at the fade end and stays there, the same above and
-- below; unreadable or invalid settings fall back to their defaults and never divide by zero. Every
-- target gets its height difference, a category switched off keeps its opacity, the vertical hide
-- still drops what it dropped, exempt and infinite range targets still fade, and a pooled target
-- never keeps an earlier target's fade. The real enemy definitions map every marker kind to its
-- category's toggle, and the real settings menu ends Limits & filtering with the shared curve and
-- puts each category's toggle in that category's own section, with their text in every language.

local HELPERS_PATH = "Radar/scripts/mods/Radar/Radar_runtime_helpers.lua"
local TRACKING_PATH = "Radar/scripts/mods/Radar/Radar_tracking.lua"
local DEFINITIONS_PATH = "Radar/scripts/mods/Radar/Radar_enemy_definitions.lua"
local DATA_PATH = "Radar/scripts/mods/Radar/Radar_data.lua"
local LOCALIZATION_PATH = "Radar/scripts/mods/Radar/Radar_localization.lua"
local LANGUAGES = { "en", "fr", "de", "it", "es", "pl", "pt-br", "ru", "ja", "ko", "zh-cn", "zh-tw" }

--- The toggles, each with the section or marker setting it sits under and, for an enemy category,
-- the facing option it follows, as the vertical arrow and facing options sit in each enemy section.
local CATEGORY_TOGGLES = {
    { "elevation_fade_common_pickups", "common_pickups_group" },
    { "elevation_fade_materials", "materials_group" },
    { "elevation_fade_environment", "environment_group" },
    { "elevation_fade_deployables", "deployables_group" },
    { "elevation_fade_mission_objective", "mission_objective_group" },
    { "elevation_fade_primary_objective", "primary_objective_group" },
    { "elevation_fade_secondary_objective", "secondary_objective_group" },
    { "elevation_fade_martyr_s_skull", "martyr_s_skull_group" },
    { "elevation_fade_event", "event_group" },
    { "elevation_fade_expeditions_location", "expeditions_location_group" },
    { "elevation_fade_expeditions_specific", "expedition_items_group" },
    { "elevation_fade_enemy_boss", "enemy_bosses_group", "show_enemy_boss_facing" },
    { "elevation_fade_enemy_horde", "enemy_horde_group", "show_enemy_horde_facing" },
    { "elevation_fade_enemy_common", "enemy_common_shooters_group", "show_enemy_common_facing" },
    { "elevation_fade_enemy_shooter", "enemy_common_shooters_group", "show_enemy_shooter_facing" },
    { "elevation_fade_enemy_elite", "enemy_elites_group", "show_enemy_elite_facing" },
    { "elevation_fade_enemy_special", "enemy_specials_group", "show_enemy_special_facing" },
    { "elevation_fade_enemy_misc", "enemy_misc_group", "show_enemy_misc_facing" },
    { "elevation_fade_teammates", "show_players" },
    { "elevation_fade_player_companions", "player_companions_group" },
    { "elevation_fade_player_tags", "show_player_tags" },
    { "elevation_fade_respawn", "respawn_group" },
    { "elevation_fade_saferoute", "saferoute_group" },
}

table.clear = table.clear or function(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

local function assert_nil(value, message)
    if value ~= nil then
        error((message or "expected nil") .. ": got " .. tostring(value), 2)
    end
end

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assert_near(expected, actual, message)
    if type(actual) ~= "number" or math.abs(expected - actual) > 1e-9 then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
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

local function noop()
end

-- --------------------------------------------------------------------------------------------
-- The collection, with the real runtime helpers and tracking modules
-- --------------------------------------------------------------------------------------------

--- The toggle of each kind the collection tests track, standing in for the enemy definitions.
local TEST_FADE_SETTING_BY_KIND = {
    player_teammate = "elevation_fade_teammates",
    pickup_ammo_small = "elevation_fade_common_pickups",
    mission_objective_scanner = "elevation_fade_mission_objective",
    respawn_active = "elevation_fade_respawn",
    material_expeditions_loot = "elevation_fade_expeditions_specific",
    material_expeditions_loot_player_drop = "elevation_fade_expeditions_specific",
}

local function new_harness()
    local captured = {}
    local alive = {}
    local settings = {
        enable_radar = true,
        debug_mode = false,
        debug_profiling = false,
        radar_style = "square",
        max_radar_markers = 64,
        overview_zoom_in_key = { "wheel_down" },
        overview_zoom_out_key = { "wheel_up" },
        radar_zoom_modifier_key = {},
    }
    local mod = {
        _tracked_units = {},
        _tracked_points = {},
    }

    function mod:get(setting_id)
        return settings[setting_id]
    end

    function mod:set(setting_id, value)
        settings[setting_id] = value
    end

    function mod:get_elevation_fade_setting(kind)
        return TEST_FADE_SETTING_BY_KIND[kind]
    end

    function mod:get_player_marker_range_mode()
        return "default"
    end

    function mod:get_target_render_layer()
        return 0
    end

    function mod:get_target_selection_priority()
        return 0
    end

    function mod:hook_safe(class_or_name, method_name, callback)
        if class_or_name == "StateGameplay" and method_name == "update" then
            captured.state_gameplay_update = callback
        end
    end

    mod.hook = noop
    mod.register_hud_element = noop
    mod.info = noop
    mod.error = noop
    mod.notify = noop

    local env = {
        mod = mod,
        ALIVE = alive,
        POSITION_LOOKUP = {},
        SCAN_INTERVAL = 0.25,
        KIND_TO_SETTING = {},
        RESPAWN_MARKER_KINDS = {},
        SAFEROUTE_MARKER_KINDS = {},
        ENEMY_RADAR_DEFINITION_BY_KIND = {},
        NEARBY_HIGHLIGHT_SETTING_BY_GROUP = {},
        CLASS = { InputService = {} },
    }

    -- Shared functions from modules this harness does not install only need to exist.
    setmetatable(env, {
        __index = function(_, key)
            local value = _G[key]

            if value ~= nil then
                return value
            end

            if type(key) == "string" and key:sub(1, 1) == "_" then
                return noop
            end

            return nil
        end,
    })

    local helpers_chunk = assert(loadfile(HELPERS_PATH))
    local tracking_chunk = assert(loadfile(TRACKING_PATH))

    helpers_chunk()(env)
    tracking_chunk()(env)

    local player_unit = { position = { x = 0, y = 0, z = 0 } }
    local extra_targets = {}

    alive[player_unit] = true

    -- What the scans around the collection would decide; here every kind is enabled, every unit
    -- still alive is trackable and objective kinds are the objectives.
    env._player_unit = function()
        return player_unit
    end
    env._safe_unit_position = function(unit)
        return type(unit) == "table" and unit.position or nil
    end
    env._is_trackable_unit_alive = function(unit)
        return alive[unit] == true
    end
    env._kind_enabled = function()
        return true
    end
    env._mastiff_disabled_enemy_units = function()
        return {}
    end
    env._is_mission_objective_marker_kind = function(kind)
        return type(kind) == "string" and kind:sub(1, 18) == "mission_objective_"
    end
    -- Clustering hands back a new list, here with any cluster targets the test adds.
    env._cluster_expedition_loot_targets = function(targets)
        local result = {}

        for i = 1, #targets do
            result[i] = targets[i]
        end

        for i = 1, #extra_targets do
            result[#result + 1] = extra_targets[i]
        end

        return result
    end

    local update_internal = named_upvalue(captured.state_gameplay_update, "_update_internal")
    local collect_radar_targets = named_upvalue(update_internal, "_collect_radar_targets")
    local harness = {
        env = env,
        mod = mod,
        settings = settings,
        player_unit = player_unit,
        extra_targets = extra_targets,
        fade_alpha = named_upvalue(collect_radar_targets, "_elevation_fade_alpha"),
    }

    --- Makes a unit at a height above the player, one metre away on the floor plan.
    function harness:unit(height)
        local unit = { position = { x = 1, y = 1, z = height } }

        alive[unit] = true

        return unit
    end

    --- Tracks a unit as a radar target of a kind.
    function harness:track(unit, kind)
        mod._tracked_units[unit] = {
            kind = kind,
            source = "test",
            position = unit.position,
            meta = {},
            last_seen_t = 0,
        }
    end

    --- Builds the radar targets and returns them by unit.
    function harness:collect()
        local targets = collect_radar_targets()
        local by_unit = {}

        for i = 1, #targets do
            local unit = targets[i].unit

            if unit ~= nil then
                by_unit[unit] = targets[i]
            end
        end

        return targets, by_unit
    end

    function harness:forget()
        for unit in pairs(mod._tracked_units) do
            mod._tracked_units[unit] = nil
        end
    end

    return harness
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("the default curve keeps 100 % through 2 m, 67.5 % at 5 m and 35 % from 8 m, above and below", function()
    local harness = new_harness()
    local fade_start, fade_end, min_alpha = harness.mod:get_elevation_fade_curve()

    assert_equal(2, fade_start, "default fade start")
    assert_equal(8, fade_end, "default fade end")
    assert_near(0.35, min_alpha, "default minimum")

    local fade_alpha = harness.fade_alpha

    assert_nil(fade_alpha(0, fade_start, fade_end, min_alpha), "at the player's height")
    assert_nil(fade_alpha(2, fade_start, fade_end, min_alpha), "at the fade start")
    assert_near(1 - 0.01 / 6 * 0.65, fade_alpha(2.01, fade_start, fade_end, min_alpha), "just past the start")
    assert_near(0.675, fade_alpha(5, fade_start, fade_end, min_alpha), "halfway")
    assert_near(0.35, fade_alpha(8, fade_start, fade_end, min_alpha), "at the fade end")
    assert_near(0.35, fade_alpha(20, fade_start, fade_end, min_alpha), "beyond the fade end")

    local unit_above = harness:unit(5)
    local unit_below = harness:unit(-5)

    harness:track(unit_above, "player_teammate")
    harness:track(unit_below, "player_teammate")

    local _, by_unit = harness:collect()

    assert_near(0.675, by_unit[unit_above].elevation_alpha, "5 m above")
    assert_near(0.675, by_unit[unit_below].elevation_alpha, "5 m below")
    assert_equal(5, by_unit[unit_above].vertical_delta, "height above")
    assert_equal(-5, by_unit[unit_below].vertical_delta, "height below")
end)

test("the curve follows the shared settings and survives invalid values without dividing by zero", function()
    local harness = new_harness()
    local settings = harness.settings
    local mod = harness.mod
    local fade_alpha = harness.fade_alpha

    settings.elevation_fade_start = 4
    settings.elevation_fade_end = 14
    settings.elevation_fade_min_percent = 50

    local fade_start, fade_end, min_alpha = mod:get_elevation_fade_curve()

    assert_equal(4, fade_start, "configured start")
    assert_equal(14, fade_end, "configured end")
    assert_near(0.5, min_alpha, "configured minimum")
    assert_near(0.75, fade_alpha(9, fade_start, fade_end, min_alpha), "halfway on the configured curve")

    local cases = {
        { start = nil, finish = nil, minimum = nil, expected = { 2, 8, 0.35 } },
        { start = 0 / 0, finish = math.huge, minimum = -math.huge, expected = { 2, 8, 0.35 } },
        { start = "abc", finish = {}, minimum = true, expected = { 2, 8, 0.35 } },
        { start = "3", finish = "9", minimum = "40", expected = { 3, 9, 0.4 } },
        { start = -5, finish = -1, minimum = -20, expected = { 0, 0, 0 } },
        { start = 80, finish = 90, minimum = 250, expected = { 50, 50, 1 } },
    }

    for i = 1, #cases do
        local case = cases[i]

        settings.elevation_fade_start = case.start
        settings.elevation_fade_end = case.finish
        settings.elevation_fade_min_percent = case.minimum
        fade_start, fade_end, min_alpha = mod:get_elevation_fade_curve()

        assert_equal(case.expected[1], fade_start, "case " .. i .. " start")
        assert_equal(case.expected[2], fade_end, "case " .. i .. " end")
        assert_near(case.expected[3], min_alpha, "case " .. i .. " minimum")
    end

    -- An end at or below the start is a step at the start, never a division by zero or a negative span.
    for _, curve in ipairs({ { 5, 5 }, { 6, 3 }, { 0, 0 } }) do
        assert_nil(fade_alpha(curve[1], curve[1], curve[2], 0.35), "at a step's start")
        assert_near(0.35, fade_alpha(curve[1] + 0.001, curve[1], curve[2], 0.35), "just past a step")
        assert_near(0.35, fade_alpha(curve[1] + 30, curve[1], curve[2], 0.35), "far past a step")
    end

    -- 100 % keeps every marker's opacity, 0 % leaves the faded part invisible.
    assert_nil(fade_alpha(30, 2, 8, 1), "a 100 % minimum")
    assert_near(0, fade_alpha(30, 2, 8, 0), "a 0 % minimum")
    assert_near(0.5, fade_alpha(5, 2, 8, 0), "halfway to a 0 % minimum")
end)

test("every kind gets its height, and a category switched off keeps its opacity", function()
    local harness = new_harness()
    local settings = harness.settings
    local teammate = harness:unit(6)
    local pickup = harness:unit(-6)
    local unmapped = harness:unit(6)

    harness:track(teammate, "player_teammate")
    harness:track(pickup, "pickup_ammo_small")
    harness:track(unmapped, "location_ping")

    local _, by_unit = harness:collect()
    local expected = 1 - 4 / 6 * 0.65

    assert_equal(6, by_unit[teammate].vertical_delta, "a teammate has no vertical arrow but gets its height")
    assert_nil(by_unit[teammate].vertical_state, "a teammate still gets no vertical arrow")
    assert_near(expected, by_unit[teammate].elevation_alpha, "a teammate fades")
    assert_near(expected, by_unit[pickup].elevation_alpha, "a pickup below fades")
    assert_equal(6, by_unit[unmapped].vertical_delta, "a kind outside the test categories gets its height")
    assert_nil(by_unit[unmapped].elevation_alpha, "a kind no category covers never fades")

    settings.elevation_fade_teammates = false
    _, by_unit = harness:collect()

    assert_nil(by_unit[teammate].elevation_alpha, "a teammate faded with its category off")
    assert_near(expected, by_unit[pickup].elevation_alpha, "switching teammates off stopped pickups fading")

    settings.elevation_fade_teammates = true
    settings.elevation_fade_start = 1
    settings.elevation_fade_end = 11
    settings.elevation_fade_min_percent = 0
    _, by_unit = harness:collect()

    assert_near(0.5, by_unit[teammate].elevation_alpha, "a changed curve reached the teammate on the next scan")
    assert_near(0.5, by_unit[pickup].elevation_alpha, "a changed curve reached the pickup on the next scan")
end)

test("the vertical hide still drops what it dropped; exempt and infinite range targets still fade", function()
    local harness = new_harness()
    local settings = harness.settings
    local hidden_pickup = harness:unit(20)
    local objective = harness:unit(20)
    local respawn = harness:unit(-20)
    local dropped_remnant = harness:unit(20)
    local teammate = harness:unit(20)

    harness:track(hidden_pickup, "pickup_ammo_small")
    harness:track(objective, "mission_objective_scanner")
    harness:track(respawn, "respawn_active")
    harness:track(dropped_remnant, "material_expeditions_loot_player_drop")
    harness:track(teammate, "player_teammate")

    local _, by_unit = harness:collect()

    assert_nil(by_unit[hidden_pickup], "a pickup past the vertical hide threshold is drawn")
    assert_near(0.35, by_unit[objective].elevation_alpha, "an objective, exempt from the hide, fades")
    assert_near(0.35, by_unit[respawn].elevation_alpha, "the active respawn, exempt from the hide, fades")
    assert_near(0.35, by_unit[dropped_remnant].elevation_alpha, "a dropped Tech-Remnant, infinite range, fades")
    assert_near(0.35, by_unit[teammate].elevation_alpha, "a teammate, never hidden by height, fades")

    -- Switching fading off for every category hides nothing more and shows nothing hidden.
    for kind, setting_id in pairs(TEST_FADE_SETTING_BY_KIND) do
        settings[setting_id] = false
    end

    _, by_unit = harness:collect()

    assert_nil(by_unit[hidden_pickup], "switching fading off showed a pickup past the hide threshold")
    assert_nil(by_unit[objective].elevation_alpha, "an objective faded with fading off")
    assert_nil(by_unit[teammate].elevation_alpha, "a teammate faded with fading off")

    -- A 0 % floor fades, it does not hide: the target is still collected.
    settings.elevation_fade_teammates = true
    settings.elevation_fade_min_percent = 0
    _, by_unit = harness:collect()

    assert_near(0, by_unit[teammate].elevation_alpha, "a teammate at a 0 % floor")
end)

test("unreadable heights keep the configured opacity", function()
    local harness = new_harness()
    local no_height = harness:unit(nil)
    local not_a_number = harness:unit(0 / 0)
    local infinite = harness:unit(math.huge)

    harness:track(no_height, "player_teammate")
    harness:track(not_a_number, "player_teammate")
    harness:track(infinite, "player_teammate")

    local _, by_unit = harness:collect()

    for unit, label in pairs({ [no_height] = "no height", [not_a_number] = "NaN", [infinite] = "infinite" }) do
        assert_nil(by_unit[unit].vertical_delta, label .. " has a height difference")
        assert_nil(by_unit[unit].elevation_alpha, label .. " fades")
    end

    local teammate = harness:unit(6)

    harness:track(teammate, "player_teammate")
    harness.player_unit.position = { x = 0, y = 0, z = 0 / 0 }
    _, by_unit = harness:collect()

    assert_nil(by_unit[teammate].elevation_alpha, "a target fades while the player's height is unreadable")
end)

test("a pooled target and a later scan never keep an earlier fade", function()
    local harness = new_harness()
    local teammate = harness:unit(8)
    local pickup = harness:unit(0)

    harness:track(teammate, "player_teammate")

    local targets = harness:collect()
    local pooled = targets[1]

    assert_near(0.35, pooled.elevation_alpha, "the teammate's fade")

    harness:forget()
    harness:track(pickup, "pickup_ammo_small")
    targets = harness:collect()

    assert_equal(pooled, targets[1], "the pool did not hand out the same table")
    assert_nil(targets[1].elevation_alpha, "the pickup at the player's height kept the teammate's fade")

    -- The same target follows its height, and the player's, from scan to scan.
    pickup.position.z = 5
    targets = harness:collect()
    assert_near(0.675, targets[1].elevation_alpha, "the pickup moved up")

    harness.player_unit.position = { x = 0, y = 0, z = 5 }
    targets = harness:collect()
    assert_nil(targets[1].elevation_alpha, "the player climbed to the pickup")

    harness.player_unit.position = { x = 0, y = 0, z = 13 }
    targets = harness:collect()
    assert_near(0.35, targets[1].elevation_alpha, "the player climbed above the pickup")
end)

test("cluster targets fade, and every target the marker limit keeps gets its fade", function()
    local harness = new_harness()
    local cluster = {
        kind = "material_expeditions_loot",
        position = { x = 0.5, y = 0.5, z = -5 },
        source = "expedition_loot_cluster",
        meta = { is_tech_remnant_cluster = true },
        distance_sq = 1,
        vertical_delta = -5,
        ignore_radar_range = false,
    }

    harness.extra_targets[1] = cluster
    harness.settings.max_radar_markers = 10

    for i = 1, 12 do
        harness:track(harness:unit(5), "player_teammate")
    end

    local targets = harness:collect()

    assert_equal(10, #targets, "the marker limit")

    local found_cluster = false

    for i = 1, #targets do
        assert_near(0.675, targets[i].elevation_alpha, "target " .. i)
        found_cluster = found_cluster or targets[i] == cluster
    end

    assert_equal(true, found_cluster, "the cluster target was cut")
end)

-- --------------------------------------------------------------------------------------------
-- The category of every marker kind, with the real enemy definitions
-- --------------------------------------------------------------------------------------------

--- Installs the real enemy definitions and returns their environment and mod.
local function load_definitions()
    local store = {}
    local mod = {}

    function mod:get(setting_id)
        return store[setting_id]
    end

    function mod:set(setting_id, value)
        store[setting_id] = value
    end

    function mod:localize(key)
        return tostring(key)
    end

    function mod:io_dofile(path)
        return assert(loadfile(path .. ".lua"))()
    end

    mod.hook_safe = noop
    mod.hook = noop
    mod.info = noop
    mod.error = noop
    mod.notify = noop

    _G.get_mod = function()
        return mod
    end
    _G.Localize = function(key)
        return tostring(key)
    end

    local env = { mod = mod, Pickups = { by_name = {} } }

    setmetatable(env, { __index = _G })
    assert(loadfile(DEFINITIONS_PATH))()(env)

    return env, mod
end

--- Builds the settings menu for a fresh profile and returns its widgets.
local function load_menu()
    local store = {}
    local mod = {}

    function mod:get(setting_id)
        return store[setting_id]
    end

    function mod:set(setting_id, value)
        store[setting_id] = value
    end

    function mod:localize(key)
        return tostring(key)
    end

    function mod:io_dofile(path)
        return assert(loadfile(path .. ".lua"))()
    end

    _G.get_mod = function()
        return mod
    end

    local data = assert(loadfile(DATA_PATH))()

    return data.options.widgets, store
end

local function find_widget(list, setting_id)
    for i = 1, #(list or {}) do
        if list[i].setting_id == setting_id then
            return list[i]
        end
    end

    return nil
end

--- Returns the elevation fade group of the menu, and the Limits & filtering section it ends.
local function elevation_fade_group(widgets)
    local general = find_widget(widgets, "general_group")
    local limits = general and find_widget(general.sub_widgets, "general_limits_filtering_group") or nil
    local sub_widgets = limits and limits.sub_widgets or {}

    return sub_widgets[#sub_widgets], limits
end

--- Returns every widget of the menu by setting id, with the widget it sits under and its position there.
local function index_menu(widgets)
    local widget_by_id = {}
    local parent_by_id = {}
    local position_by_id = {}

    local function walk(list, parent)
        for i = 1, #(list or {}) do
            local widget = list[i]

            widget_by_id[widget.setting_id] = widget
            parent_by_id[widget.setting_id] = parent
            position_by_id[widget.setting_id] = i
            walk(widget.sub_widgets, widget)
        end
    end

    walk(widgets, nil)

    return widget_by_id, parent_by_id, position_by_id
end

test("every marker kind fades with its own category's toggle", function()
    local env, mod = load_definitions()
    local widget_by_id = index_menu(load_menu())
    local toggles = {}
    local used = {}

    for setting_id, widget in pairs(widget_by_id) do
        if widget.type == "checkbox" and setting_id:sub(1, 15) == "elevation_fade_" then
            toggles[setting_id] = true
        end
    end

    local kinds = {}

    for _, registry in ipairs({ env.KIND_TO_SETTING, env.NEARBY_OUTLINE_COLOR_BY_KIND, env.EXPEDITION_MARKER_KINDS,
        env.RESPAWN_MARKER_KINDS, env.SAFEROUTE_MARKER_KINDS, env.ARTWORK_MODE_KIND_TO_SETTING,
        env.ENEMY_RADAR_DEFINITION_BY_KIND }) do
        for kind in pairs(registry) do
            kinds[kind] = true
        end
    end

    -- A registry leftover that no classifier produces and no settings group holds.
    kinds.pocketable_expedition_loot_crate = nil

    local count = 0

    for kind in pairs(kinds) do
        local setting_id = mod:get_elevation_fade_setting(kind)

        count = count + 1
        assert_equal(true, setting_id ~= nil and toggles[setting_id] == true,
            kind .. " maps to " .. tostring(setting_id) .. ", which is not a toggle in the menu")
        used[setting_id] = true
    end

    assert_equal(true, count > 100, "the sweep found too few kinds")

    for i = 1, #CATEGORY_TOGGLES do
        assert_equal(true, used[CATEGORY_TOGGLES[i][1]], CATEGORY_TOGGLES[i][1] .. " is used by no kind")
    end

    local expected = {
        player_teammate = "elevation_fade_teammates",
        location_attention = "elevation_fade_player_tags",
        location_ping = "elevation_fade_player_tags",
        location_threat = "elevation_fade_player_tags",
        player_companion_dog = "elevation_fade_player_companions",
        player_companion_servo_skull = "elevation_fade_player_companions",
        enemy_daemonhost = "elevation_fade_enemy_boss",
        enemy_monstrosity = "elevation_fade_enemy_boss",
        enemy_captain = "elevation_fade_enemy_boss",
        enemy_karnak_twin = "elevation_fade_enemy_boss",
        pickup_unknown = "elevation_fade_common_pickups",
        crate_unknown = "elevation_fade_common_pickups",
        pickup_ammo = "elevation_fade_common_pickups",
        material_plasteel = "elevation_fade_materials",
        luggable_socket = "elevation_fade_environment",
        medical_crate_deployable = "elevation_fade_deployables",
        mission_objective_servo_skull = "elevation_fade_mission_objective",
        luggable_power_cell_teal = "elevation_fade_primary_objective",
        pocketable_grimoire = "elevation_fade_secondary_objective",
        martyr_skull_riddle_interactable = "elevation_fade_martyr_s_skull",
        luggable_power_cell_orange = "elevation_fade_martyr_s_skull",
        pickup_saints = "elevation_fade_event",
        expedition_objective_opportunity = "elevation_fade_expeditions_location",
        expedition_loot_converter = "elevation_fade_expeditions_location",
        material_expeditions_loot = "elevation_fade_expeditions_specific",
        material_expeditions_loot_player_drop = "elevation_fade_expeditions_specific",
        respawn_runback = "elevation_fade_respawn",
        saferoute_wrong = "elevation_fade_saferoute",
    }

    for kind, setting_id in pairs(expected) do
        assert_equal(setting_id, mod:get_elevation_fade_setting(kind), kind)
    end

    -- Every enemy with a definition follows its category; common and shooter stay apart.
    for kind, definition in pairs(env.ENEMY_RADAR_DEFINITION_BY_KIND) do
        assert_equal("elevation_fade_enemy_" .. definition.category, mod:get_elevation_fade_setting(kind), kind)
    end

    assert_equal("elevation_fade_enemy_common", mod:get_elevation_fade_setting("enemy_cultist_melee"), "common")
    assert_equal("elevation_fade_enemy_shooter", mod:get_elevation_fade_setting("enemy_renegade_rifleman"), "shooter")
    assert_nil(mod:get_elevation_fade_setting(nil), "no kind")
    assert_nil(mod:get_elevation_fade_setting("not_a_marker_kind"), "an unknown kind")
end)

-- --------------------------------------------------------------------------------------------
-- The settings menu and its text
-- --------------------------------------------------------------------------------------------

test("the shared curve ends Limits & filtering and each category's toggle sits in its own section", function()
    local widgets, store = load_menu()
    local group, limits = elevation_fade_group(widgets)

    assert_equal(true, limits ~= nil, "Limits & filtering is missing")
    assert_equal("elevation_fade_group", group and group.setting_id, "the last widget of Limits & filtering")
    assert_equal("group", group.type, "the elevation fade widget type")
    assert_equal(nil, next(store), "building the menu saved settings")

    local sub_widgets = group.sub_widgets
    local sliders = {
        { "elevation_fade_start", 2, 0, 50 },
        { "elevation_fade_end", 8, 0, 50 },
        { "elevation_fade_min_percent", 35, 0, 100 },
    }

    assert_equal(#sliders, #sub_widgets, "widgets in the elevation fade group")

    for i = 1, #sliders do
        local slider = sliders[i]
        local widget = sub_widgets[i]

        assert_equal(slider[1], widget.setting_id, "slider " .. i)
        assert_equal("numeric", widget.type, slider[1] .. " type")
        assert_equal(slider[2], widget.default_value, slider[1] .. " default")
        assert_equal(slider[3], widget.range[1], slider[1] .. " minimum")
        assert_equal(slider[4], widget.range[2], slider[1] .. " maximum")
        assert_equal(slider[1] .. "_tooltip", widget.tooltip, slider[1] .. " tooltip")
    end

    local widget_by_id, parent_by_id, position_by_id = index_menu(widgets)
    local toggle_count = 0

    for setting_id, widget in pairs(widget_by_id) do
        if widget.type == "checkbox" and setting_id:sub(1, 15) == "elevation_fade_" then
            toggle_count = toggle_count + 1
        end
    end

    assert_equal(#CATEGORY_TOGGLES, toggle_count, "elevation fade toggles in the menu")

    for i = 1, #CATEGORY_TOGGLES do
        local toggle = CATEGORY_TOGGLES[i]
        local setting_id = toggle[1]
        local widget = widget_by_id[setting_id]
        local parent = parent_by_id[setting_id]

        assert_equal(true, widget ~= nil, setting_id .. " is missing")
        assert_equal("checkbox", widget.type, setting_id .. " type")
        assert_equal(true, widget.default_value, setting_id .. " default")
        assert_equal("elevation_fade_category_tooltip", widget.tooltip, setting_id .. " tooltip")
        assert_nil(widget.title, setting_id .. " borrows another setting's title")
        assert_equal(toggle[2], parent and parent.setting_id, setting_id .. " section")

        -- An enemy category's toggle follows its vertical arrow and facing options.
        if toggle[3] ~= nil then
            assert_equal(toggle[3], parent.sub_widgets[position_by_id[setting_id] - 1].setting_id,
                setting_id .. " does not follow " .. toggle[3])
        end
    end
end)

test("every title and tooltip of the elevation fade settings is in every language", function()
    _G.Localize = function(key)
        return tostring(key)
    end

    local localization = assert(loadfile(LOCALIZATION_PATH))()
    local keys = {
        "elevation_fade_group",
        "elevation_fade_start",
        "elevation_fade_start_tooltip",
        "elevation_fade_end",
        "elevation_fade_end_tooltip",
        "elevation_fade_min_percent",
        "elevation_fade_min_percent_tooltip",
        "elevation_fade_category_tooltip",
    }

    for i = 1, #CATEGORY_TOGGLES do
        keys[#keys + 1] = CATEGORY_TOGGLES[i][1]
    end

    for i = 1, #keys do
        local entry = localization[keys[i]]

        assert_equal("table", type(entry), keys[i] .. " has no text")

        for l = 1, #LANGUAGES do
            local text = entry[LANGUAGES[l]]

            assert_equal(true, type(text) == "string" and text ~= "", keys[i] .. " has no " .. LANGUAGES[l] .. " text")
        end
    end

    assert_equal("Elevation fade start (m)", localization.elevation_fade_start.en, "English start label")
    assert_equal("Elevation fade end (m)", localization.elevation_fade_end.en, "English end label")
    assert_equal("Minimum elevation opacity (%)", string.format(localization.elevation_fade_min_percent.en),
        "English minimum label")
end)

test("every localized text survives the string.format DMF runs it through", function()
    _G.Localize = function(key)
        return tostring(key)
    end

    -- `mod:localize` formats every text, so a lone `%` such as "(%)" logs an error instead of the label.
    local localization = assert(loadfile(LOCALIZATION_PATH))()
    local count = 0

    for key, entry in pairs(localization) do
        if type(entry) == "table" then
            for language, text in pairs(entry) do
                if type(text) == "string" then
                    local ok, message = pcall(string.format, text)

                    count = count + 1
                    assert_equal(true, ok, key .. " " .. tostring(language) .. ": " .. tostring(message))
                end
            end
        end
    end

    assert_equal(true, count > 1000, "too few texts were checked")
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
