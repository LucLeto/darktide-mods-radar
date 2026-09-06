local EXPEDITIONS_PATH = "Radar/scripts/mods/Radar/Radar_expeditions.lua"
local TRACKING_PATH = "Radar/scripts/mods/Radar/Radar_tracking.lua"

local BUTTONS = {
    {
        description = "loc_interactable_button_01",
        position = { x = 143.653, y = -157.591, z = -13.257 },
    },
    {
        description = "loc_interactable_button_02",
        position = { x = 144.131, y = -157.116, z = -13.258 },
    },
    {
        description = "loc_interactable_button_03",
        position = { x = 144.565, y = -156.677, z = -13.258 },
    },
}

local function fallback_id(button_index)
    local button = BUTTONS[button_index]

    return "martyr_skull_riddle_fallback:cm_habs:default|default|" .. button.description .. ":1"
end

local function assert_true(value, message)
    if value ~= true then
        error(message or "expected true", 2)
    end
end

local function assert_nil(value, message)
    if value ~= nil then
        error(message or "expected nil", 2)
    end
end

local function assert_not_nil(value, message)
    if value == nil then
        error(message or "expected a value", 2)
    end
end

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function table_size(values)
    local count = 0

    for _ in pairs(values or {}) do
        count = count + 1
    end

    return count
end

local function named_upvalue(fn, expected_name)
    local index = 1

    while true do
        local name, value = debug.getupvalue(fn, index)

        if not name then
            error("missing upvalue `" .. expected_name .. "`", 2)
        end

        if name == expected_name then
            return value
        end

        index = index + 1
    end
end

local function install(path, env)
    local chunk, load_error = loadfile(path)

    assert(chunk, load_error)

    local installer = chunk()

    assert_equal("function", type(installer), path .. " must return an installer")
    installer(env)
end

local function new_harness()
    local captured = {}
    local settings = {
        debug_mode = false,
        enable_radar = true,
        show_martyr_skull_riddle_interactables = true,
    }
    local mission_name = "cm_habs"
    local gameplay_t = 0
    local player_unit = {}
    local interactee_map = {}
    local mod = {
        _tracked_units = {},
        _tracked_points = {},
        _martyr_skull_riddle_solved_by_mission = {},
        _overview_capture_actions = {},
    }

    function mod:get(setting_id)
        return settings[setting_id]
    end

    function mod:set(setting_id, value)
        settings[setting_id] = value
    end

    function mod:get_enemy_marker_mode()
        return nil
    end

    function mod:get_icon_distance_marker_display_mode()
        return nil
    end

    function mod:get_expedition_marker_display_mode()
        return nil
    end

    function mod:get_marker_display_mode()
        return nil
    end

    function mod:register_hud_element()
    end

    function mod:hook()
    end

    function mod:hook_safe(class_or_name, method_name, callback)
        if class_or_name == "StateGameplay" and method_name == "update" then
            captured.state_gameplay_update = callback
        end
    end

    function mod:info()
    end

    function mod:error()
    end

    function mod:notify()
    end

    local env = {
        mod = mod,
        Pickups = { by_name = {} },
        KIND_TO_SETTING = {
            martyr_skull_riddle_interactable = "show_martyr_skull_riddle_interactables",
        },
        SCAN_INTERVAL = 0.25,
        CompanionServoSkullSettings = { STATES = {} },
        GameSession = {},
        CLASS = { InputService = {} },
    }

    setmetatable(env, { __index = _G })

    env._safe_mission_name = function()
        return mission_name
    end

    env._safe_game_mode_name = function()
        return nil
    end

    env._safe_game_mode = function()
        return nil
    end

    env._safe_unit_to_extension_map = function(system_name)
        if system_name == "interactee_system" then
            return interactee_map
        end

        return nil
    end

    env._player_unit = function()
        return player_unit
    end

    env._safe_unit_alive = function(unit)
        return unit ~= nil and unit.alive ~= false
    end

    env._is_trackable_unit_alive = env._safe_unit_alive

    env._safe_unit_position = function(unit)
        return unit and unit.position or nil
    end

    env._safe_unit_name = function(unit)
        return unit and unit.name or nil
    end

    env._safe_unit_pickup_name = function()
        return nil
    end

    env._safe_lower_string = function(value)
        return type(value) == "string" and string.lower(value) or nil
    end

    env._safe_extension_system = function()
        return nil
    end

    env._safe_gameplay_time = function()
        return gameplay_t
    end

    env._copy_vector3 = function(value)
        return value and { x = value.x, y = value.y, z = value.z } or nil
    end

    env._distance_squared = function(a, b)
        if not a or not b then
            return math.huge
        end

        local dx = a.x - b.x
        local dy = a.y - b.y
        local dz = a.z - b.z

        return dx * dx + dy * dy + dz * dz
    end

    env._is_enemy_kind = function()
        return false
    end

    env._is_expedition_marker_kind = function()
        return false
    end

    env._is_player_smart_tag_kind = function()
        return false
    end

    env._invalidate_runtime_state_cache = function()
    end

    env._reset_dark_rites_marker_scan_cache = function()
    end

    install(EXPEDITIONS_PATH, env)
    install(TRACKING_PATH, env)

    local update_internal = named_upvalue(captured.state_gameplay_update, "_update_internal")
    local scan_interactees = named_upvalue(update_internal, "_scan_interactees")
    local harness = {
        env = env,
        mod = mod,
        settings = settings,
        interactee_map = interactee_map,
        scan_interactees = scan_interactees,
    }

    function harness:add_interactee(button_index, options)
        options = options or {}

        local button = BUTTONS[button_index]
        local position = options.position or button.position
        local state = {
            active = options.active,
            used = options.used,
            show_marker = options.show_marker,
            active_error = false,
            used_error = false,
            show_marker_error = false,
        }

        if state.active == nil then
            state.active = true
        end

        if state.used == nil then
            state.used = false
        end

        if state.show_marker == nil then
            state.show_marker = true
        end

        local unit = {
            name = options.unit_name or "cm_habs_test_button_" .. tostring(button_index),
            position = { x = position.x, y = position.y, z = position.z },
        }
        local extension = {}

        function extension:active()
            if state.active_error then
                error("active read failed")
            end

            return state.active
        end

        function extension:used()
            if state.used_error then
                error("used read failed")
            end

            return state.used
        end

        function extension:show_marker()
            if state.show_marker_error then
                error("show_marker read failed")
            end

            return state.show_marker
        end

        function extension:interaction_type()
            return options.interaction_type or "default"
        end

        function extension:ui_interaction_type()
            return options.ui_interaction_type or "default"
        end

        function extension:interaction_icon()
            return "content/ui/materials/hud/interactions/icons/default"
        end

        function extension:description()
            return options.description or button.description
        end

        interactee_map[unit] = extension

        return unit, state, extension
    end

    function harness:remove_interactee(unit)
        interactee_map[unit] = nil
    end

    function harness:scan()
        gameplay_t = gameplay_t + 0.25
        scan_interactees()
        env._scan_expedition_objectives()
        env._scan_martyr_skull_riddle_coordinate_fallbacks()
    end

    function harness:set_mission_name(value)
        mission_name = value
    end

    return harness
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("creates fallbacks for unobserved cm_habs buttons", function()
    local harness = new_harness()

    harness:scan()

    for i = 1, #BUTTONS do
        assert_not_nil(harness.mod._tracked_points[fallback_id(i)], "missing fallback for button " .. tostring(i))
    end

    assert_equal(3, table_size(harness.mod._tracked_points), "unexpected fallback count")
end)

test("active unit replaces only its matching fallback", function()
    local harness = new_harness()
    local unit = harness:add_interactee(1)

    harness:scan()

    assert_not_nil(harness.mod._tracked_units[unit], "active unit was not tracked")
    assert_nil(harness.mod._tracked_points[fallback_id(1)], "active unit retained a duplicate fallback")
    assert_not_nil(harness.mod._tracked_points[fallback_id(2)], "unobserved button 2 lost its fallback")
    assert_not_nil(harness.mod._tracked_points[fallback_id(3)], "unobserved button 3 lost its fallback")
end)

test("seen active to inactive transition retires matching fallback", function()
    local harness = new_harness()
    local unit, state = harness:add_interactee(1)

    harness:scan()
    state.active = false
    harness:scan()

    assert_nil(harness.mod._tracked_units[unit], "inactive unit remained live-tracked")
    assert_nil(harness.mod._tracked_points[fallback_id(1)], "inactive completed button fallback resurrected")
    assert_not_nil(harness.mod._tracked_points[fallback_id(2)], "unrelated button 2 fallback was retired")
    assert_not_nil(harness.mod._tracked_points[fallback_id(3)], "unrelated button 3 fallback was retired")
end)

test("initial used state retires fallback for hot join", function()
    local harness = new_harness()
    local unit = harness:add_interactee(1, { active = false, used = true })

    harness:scan()
    assert_nil(harness.mod._tracked_points[fallback_id(1)], "used hot-join button retained its fallback")

    harness:remove_interactee(unit)
    harness:scan()
    assert_nil(harness.mod._tracked_points[fallback_id(1)], "used hot-join fallback returned after unit removal")
end)

test("initial inactive unused state remains conservatively visible", function()
    local harness = new_harness()

    harness:add_interactee(1, { active = false, used = false })
    harness:scan()

    assert_not_nil(harness.mod._tracked_points[fallback_id(1)],
        "ambiguous initially inactive and unused button was treated as completed")
end)

test("partial input remains visible when buttons stay active and unused", function()
    local harness = new_harness()
    local units = {}

    for i = 1, #BUTTONS do
        units[i] = harness:add_interactee(i, { show_marker = i ~= 1 })
    end

    harness:scan()

    local visible_riddle_entries = 0

    for _, data in pairs(harness.mod._tracked_units) do
        if data.kind == "martyr_skull_riddle_interactable" then
            visible_riddle_entries = visible_riddle_entries + 1
        end
    end

    for _, data in pairs(harness.mod._tracked_points) do
        if data.kind == "martyr_skull_riddle_interactable" then
            visible_riddle_entries = visible_riddle_entries + 1
        end
    end

    assert_equal(3, visible_riddle_entries, "partial input did not preserve all three button markers")
    assert_not_nil(harness.mod._tracked_units[units[1]], "presentation-only show_marker=false retired button 1")
    assert_true(harness.mod._martyr_skull_riddle_solved_by_mission.cm_habs ~= true,
        "partial input set the mission completion latch")
end)

test("failed active or used read does not retire fallback", function()
    local harness = new_harness()
    local unit, state = harness:add_interactee(1)

    harness:scan()
    state.active_error = true
    harness:scan()

    assert_nil(harness.mod._tracked_units[unit], "unit with failed active read remained live-tracked")
    assert_not_nil(harness.mod._tracked_points[fallback_id(1)], "failed active read was treated as completion")

    state.active_error = false
    harness:scan()
    assert_not_nil(harness.mod._tracked_units[unit], "recovered active unit was not tracked")
    assert_nil(harness.mod._tracked_points[fallback_id(1)], "recovered active unit retained a duplicate fallback")

    state.active = nil
    harness:scan()
    assert_not_nil(harness.mod._tracked_points[fallback_id(1)], "unknown active state was treated as completion")

    state.active = true
    harness:scan()
    assert_not_nil(harness.mod._tracked_units[unit], "unit did not recover after active state resumed")

    state.used_error = true
    harness:scan()
    assert_nil(harness.mod._tracked_units[unit], "unit with failed used read remained live-tracked")
    assert_not_nil(harness.mod._tracked_points[fallback_id(1)], "failed used read was treated as completion")

    state.used_error = false
    harness:scan()
    assert_not_nil(harness.mod._tracked_units[unit], "unit did not recover after used read resumed")
    assert_nil(harness.mod._tracked_points[fallback_id(1)], "recovered unit retained a duplicate fallback")
end)

test("active recurrence clears inferred retirement", function()
    local harness = new_harness()
    local unit, state = harness:add_interactee(1)

    harness:scan()
    state.active = false
    harness:scan()
    assert_nil(harness.mod._tracked_points[fallback_id(1)], "transition did not retire fallback")

    state.active = true
    harness:scan()
    assert_not_nil(harness.mod._tracked_units[unit], "reactivated unit was not tracked")

    harness:remove_interactee(unit)
    harness:scan()
    assert_not_nil(harness.mod._tracked_points[fallback_id(1)],
        "active recurrence did not clear inferred retirement")
end)

test("retired fallback survives an inactive replacement unit", function()
    local harness = new_harness()
    local first_unit, first_state = harness:add_interactee(1)

    harness:scan()
    first_state.active = false
    harness:scan()
    harness:remove_interactee(first_unit)

    local replacement_unit, replacement_state = harness:add_interactee(1, { active = false, used = false })

    harness:scan()
    assert_nil(harness.mod._tracked_points[fallback_id(1)],
        "inactive replacement unit resurrected a retired fallback")

    replacement_state.active = true
    harness:scan()
    assert_not_nil(harness.mod._tracked_units[replacement_unit], "active replacement unit was not tracked")

    harness:remove_interactee(replacement_unit)
    harness:scan()
    assert_not_nil(harness.mod._tracked_points[fallback_id(1)],
        "active replacement unit did not clear inherited retirement")
end)

test("retirement survives point rebuild rescans and Radar toggle", function()
    local harness = new_harness()
    local unit, state = harness:add_interactee(1)

    harness:scan()
    state.active = false
    harness:scan()
    harness:remove_interactee(unit)

    harness.mod._tracked_points = {}
    harness:scan()
    harness:scan()
    assert_nil(harness.mod._tracked_points[fallback_id(1)], "retired fallback returned on a later rescan")

    harness.mod:set_radar_enabled(false)
    harness.mod._tracked_points = {}
    harness.mod:set_radar_enabled(true)
    harness:scan()
    assert_nil(harness.mod._tracked_points[fallback_id(1)], "retired fallback returned after Radar toggle")
end)

test("nonmatching inactive or used units cannot retire fallback", function()
    local harness = new_harness()
    local button = BUTTONS[1]

    harness:add_interactee(1, {
        active = false,
        used = true,
        position = { x = button.position.x + 1, y = button.position.y, z = button.position.z },
    })
    harness:add_interactee(1, {
        active = false,
        used = true,
        description = "loc_interactable_unrelated_button",
    })
    harness:scan()

    for i = 1, #BUTTONS do
        assert_not_nil(harness.mod._tracked_points[fallback_id(i)],
            "nonmatching unit retired button " .. tostring(i))
    end
end)

test("gameplay runtime reset clears fallback observations", function()
    local harness = new_harness()
    local unit, state = harness:add_interactee(1)

    harness:scan()
    state.active = false
    harness:scan()
    assert_nil(harness.mod._tracked_points[fallback_id(1)], "transition did not retire fallback")

    harness:remove_interactee(unit)
    harness.mod.on_game_state_changed("exit", "GameplayStateRun")
    harness:scan()

    assert_not_nil(harness.mod._tracked_points[fallback_id(1)], "runtime reset retained stale fallback observations")
end)

test("final mission latch suppresses every fallback", function()
    local harness = new_harness()

    harness.mod._martyr_skull_riddle_solved_by_mission.cm_habs = true
    harness:scan()

    for i = 1, #BUTTONS do
        assert_nil(harness.mod._tracked_points[fallback_id(i)],
            "final mission latch retained button " .. tostring(i))
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
