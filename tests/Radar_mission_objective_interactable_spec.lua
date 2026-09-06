local EXPEDITIONS_PATH = "Radar/scripts/mods/Radar/Radar_expeditions.lua"
local TRACKING_PATH = "Radar/scripts/mods/Radar/Radar_tracking.lua"

local MISSION_OBJECTIVE_SETTING_BY_KIND = {
    mission_objective_scanner = "show_mission_objective_scanner",
    mission_objective_hacking = "show_mission_objective_hacking",
    mission_objective_console = "show_mission_objective_console",
    mission_objective_servo_skull = "show_mission_objective_servo_skull",
    mission_objective_other = "show_mission_objective_other",
}

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
        show_mission_objective_scanner = "icon_only",
        show_mission_objective_hacking = "icon_only",
        show_mission_objective_console = "icon_only",
        show_mission_objective_servo_skull = "icon_only",
        show_mission_objective_other = "icon_only",
    }
    -- A mission with no Martyr's Skull riddle data, so nothing else writes
    -- tracked units or points during these scans.
    local mission_name = "test_mission"
    local gameplay_t = 0
    local player_unit = {}
    local interactee_map = {}
    local extension_systems = {}
    local active_objective_names = nil
    local objective_system_available = true
    local log_entries = {}
    local probe_calls = 0
    local next_unit_index = 0
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

    -- Mirrors the real cascade: mission objective kinds resolve through the
    -- icon/icon+distance/off dropdown, so "off" must disable them.
    function mod:get_icon_distance_marker_display_mode(kind)
        local setting_id = MISSION_OBJECTIVE_SETTING_BY_KIND[kind]

        return setting_id and settings[setting_id] or nil
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
        KIND_TO_SETTING = {},
        SCAN_INTERVAL = 0.25,
        CompanionServoSkullSettings = { STATES = {} },
        GameSession = {},
        CLASS = { InputService = {} },
    }

    setmetatable(env, { __index = _G })

    -- The owner probe enumerates systems from the extension manager registry,
    -- so the fake manager points at the same table the map stub serves.
    env.Managers = {
        state = {
            extension = {
                _systems = extension_systems,
            },
        },
    }

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

        return extension_systems[system_name]
    end

    env._safe_extension_system = function(system_name)
        if system_name ~= "mission_objective_system" or not objective_system_available then
            return nil
        end

        local active_objectives = nil

        if active_objective_names then
            active_objectives = {}

            for i = 1, #active_objective_names do
                active_objectives[{ _name = active_objective_names[i] }] = true
            end
        end

        return {
            _active_objectives = active_objectives,
            active_objectives = function()
                error("mod called MissionObjectiveSystem:active_objectives() - must read fields only", 2)
            end,
        }
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

    env._safe_unit_pickup_name = function(unit)
        return unit and unit.pickup_name or nil
    end

    env._safe_lower_string = function(value)
        return type(value) == "string" and string.lower(value) or nil
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

    env._log_once = function(_, message)
        probe_calls = probe_calls + 1
        log_entries[#log_entries + 1] = tostring(message)
    end

    env._vector3_components = function(value)
        if type(value) ~= "table" then
            return nil, nil, nil
        end

        return value.x, value.y, value.z
    end

    env._safe_unit_main_visible = function(unit)
        return unit and unit.visible
    end

    env._safe_health_alive = function(unit)
        return unit and unit.health_alive
    end

    env._safe_destructible_visible = function(extension)
        return extension and extension.visible
    end

    -- Defaults to "the game's marker list cannot be read", which is the state in
    -- which the objective scan does no world-marker filtering at all.
    local world_marker_units = nil
    local world_marker_list = nil

    env._safe_world_markers_list = function()
        return world_marker_list
    end

    env._refresh_world_marker_units = function(out)
        for key in pairs(out) do
            out[key] = nil
        end

        if world_marker_units == nil then
            return false
        end

        for i = 1, #world_marker_units do
            out[world_marker_units[i]] = true
        end

        return true
    end

    env._is_finite_number = function(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
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

    -- Adds an interactee that no existing classifier recognizes, so it can only
    -- be picked up by the mission objective path.
    function harness:add_interactee(options)
        options = options or {}
        next_unit_index = next_unit_index + 1

        local state = {
            active = options.active ~= false,
            used = options.used == true,
            show_marker = options.show_marker ~= false,
        }
        local unit = {
            name = options.unit_name or ("objective_unit_" .. tostring(next_unit_index)),
            position = options.position or { x = next_unit_index, y = 0, z = 0 },
            pickup_name = options.pickup_name,
        }
        local extension = {}

        function extension:active()
            return state.active
        end

        function extension:used()
            return state.used
        end

        function extension:show_marker()
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
            return options.description or "loc_objective_interaction"
        end

        interactee_map[unit] = extension

        return unit, state
    end

    -- Registers a unit in one of the game's objective extension systems.
    function harness:add_to_system(system_name, unit, fields)
        local map = extension_systems[system_name]

        if not map then
            map = {}
            extension_systems[system_name] = map
        end

        map[unit] = fields or {}

        return unit
    end

    function harness:remove_from_system(system_name, unit)
        local map = extension_systems[system_name]

        if map then
            map[unit] = nil
        end
    end

    -- Mirrors MissionObjectiveZoneExtension: the zone owns its scannables and
    -- reports which of them this run selected.
    function harness:add_scan_zone(options)
        options = options or {}
        next_unit_index = next_unit_index + 1

        local zone_unit = { name = "zone_unit_" .. tostring(next_unit_index), position = { x = 0, y = 0, z = 0 } }
        local scannables = options.scannables or {}
        local total = options.total or #scannables
        local extension = {
            _objective_name = options.objective_name or "objective_a",
            _activated = options.activated ~= false,
            _selected_scannable_units = options.selection or scannables,
            _scannable_units = scannables,
            _num_scannables_in_zone = total,
            _current_progression = options.progression or (options.finished and total or 0),
        }

        -- Calling into this class equips and unequips the auspex, deactivates
        -- zones and signals the skull. Any call at all is a defect, so every
        -- method on the fixture fails the test loudly.
        local function forbidden(name)
            return function()
                error("mod called MissionObjectiveZoneExtension:" .. name .. "() - must read fields only", 2)
            end
        end

        extension.objective_name = forbidden("objective_name")
        extension.zone_finished = forbidden("zone_finished")
        extension.selected_scannable_units = forbidden("selected_scannable_units")
        extension.scannable_units = forbidden("scannable_units")
        extension.set_active = forbidden("set_active")
        extension.set_scanned = forbidden("set_scanned")
        extension.reset = forbidden("reset")

        local map = extension_systems["mission_objective_zone_system"]

        if not map then
            map = {}
            extension_systems["mission_objective_zone_system"] = map
        end

        map[zone_unit] = extension

        return zone_unit
    end

    function harness:set_active_objective_names(names)
        active_objective_names = names
    end

    function harness:set_objective_system_available(value)
        objective_system_available = value
    end

    function harness:remove_interactee(unit)
        interactee_map[unit] = nil
    end

    function harness:scan()
        gameplay_t = gameplay_t + 0.25
        scan_interactees()
    end

    function harness:scan_with_active_objective()
        active_objective_names = active_objective_names or { "objective_a" }
        self:scan()
    end

    function harness:tracked_kind(unit)
        local tracked = self.mod._tracked_units[unit]

        return tracked and tracked.kind or nil
    end

    function harness:tracked_minigame_state(unit)
        local tracked = self.mod._tracked_units[unit]

        return tracked and tracked.meta and tracked.meta.minigame_state or nil
    end

    -- nil means the list is unreadable; a table means these units, and only
    -- these, currently have one of the game's own world markers.
    function harness:set_world_marker_units(units)
        world_marker_units = units
    end

    -- The game's own marker widgets, as `request_world_markers_list` returns them.
    function harness:set_world_marker_list(markers)
        world_marker_list = markers
    end

    function harness:log_text()
        return table.concat(log_entries, "\n")
    end

    function harness:probe_calls()
        return probe_calls
    end

    return harness
end

local function assert_contains(haystack, needle, message)
    if not string.find(haystack, needle, 1, true) then
        error((message or "missing text") .. ": expected to find `" .. needle .. "`", 2)
    end
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("decoder devices are tracked as hacking terminals", function()
    local harness = new_harness()
    local unit = harness:add_interactee()

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "unexpected kind")
    assert_equal("mission_objective_system", harness.mod._tracked_units[unit].source, "unexpected source")
end)

test("scanning event units are tracked as scanner targets", function()
    local harness = new_harness()
    local unit = harness:add_interactee()

    harness:add_to_system("scanning_event_system", unit)
    harness:scan()

    assert_equal("mission_objective_scanner", harness:tracked_kind(unit), "unexpected kind")
end)

test("an active scan zone marks its selected scannable units", function()
    local harness = new_harness()
    local scannable = harness:add_interactee()

    harness:add_scan_zone({ scannables = { scannable } })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_equal("mission_objective_scanner", harness:tracked_kind(scannable), "scannable not marked")
end)

-- The zone unit is an invisible trigger volume. Marking it produced the ghost
-- markers that matched nothing in the world.
test("the scan zone volume itself is never marked", function()
    local harness = new_harness()
    local scannable = harness:add_interactee()
    local zone_unit = harness:add_scan_zone({ scannables = { scannable } })

    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_nil(harness:tracked_kind(zone_unit), "the zone volume must never be marked")
end)

test("a zone that is not activated marks nothing", function()
    local harness = new_harness()
    local scannable = harness:add_interactee()

    harness:add_scan_zone({ scannables = { scannable }, activated = false })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_nil(harness:tracked_kind(scannable), "only zones you can scan right now should mark")
end)

test("a finished zone stops marking its scannables", function()
    local harness = new_harness()
    local scannable = harness:add_interactee()

    harness:add_scan_zone({ scannables = { scannable }, finished = true })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_nil(harness:tracked_kind(scannable), "a completed zone must not keep its markers")
end)

-- A scanned target drops out of the zone selection but stays in the broad
-- objective target system, where it used to reappear as a generic objective.
test("a scan target never falls through to the generic category", function()
    local harness = new_harness()
    local scannable = harness:add_interactee({ interaction_type = "scanning" })

    harness:add_to_system("mission_objective_target_system", scannable,
        { _objective_name = "objective_a" })
    harness:add_scan_zone({ scannables = {} })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_nil(harness:tracked_kind(scannable), "a scan target outside its zone selection must not be marked")
end)

test("a scanned target is not re-claimed by its zone", function()
    local harness = new_harness()
    local scannable, state = harness:add_interactee({ interaction_type = "scanning" })

    harness:add_scan_zone({ scannables = { scannable } })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()
    assert_equal("mission_objective_scanner", harness:tracked_kind(scannable), "expected an initial marker")

    -- Scanning a point takes it out of the active state.
    state.active = false
    harness:scan()

    assert_nil(harness:tracked_kind(scannable), "a scanned target must retire even while its zone stays active")
end)

test("a zone belonging to an inactive objective marks nothing", function()
    local harness = new_harness()
    local scannable = harness:add_interactee()

    harness:add_scan_zone({ scannables = { scannable }, objective_name = "objective_b" })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_nil(harness:tracked_kind(scannable), "only the active objective zone should mark")
end)

test("servo skull activators are tracked from their interaction type alone", function()
    local harness = new_harness()
    local unit = harness:add_interactee({
        interaction_type = "servo_skull_activator",
        description = "loc_interactable_servo_skull_scanner",
    })

    harness:scan()

    assert_equal("mission_objective_servo_skull", harness:tracked_kind(unit),
        "servo skull must not depend on any objective system")
end)

-- The reported bug: markers only appeared once the game drew the interaction
-- prompt. Objective markers must survive show_marker being false.
test("objective markers appear before the game draws the interaction prompt", function()
    local harness = new_harness()
    local system_unit = harness:add_interactee({ show_marker = false })
    local servo_unit = harness:add_interactee({
        show_marker = false,
        interaction_type = "servo_skull_activator",
    })

    harness:add_to_system("decoder_device_system", system_unit)
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(system_unit),
        "system-sourced objective must show while show_marker is false")
    assert_equal("mission_objective_servo_skull", harness:tracked_kind(servo_unit),
        "servo skull must show while show_marker is false")
end)

test("objective targets stay hidden without active objective confirmation", function()
    local harness = new_harness()
    local unit = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", unit, { _objective_name = "objective_a" })
    harness:set_active_objective_names(nil)
    harness:scan()

    assert_nil(harness:tracked_kind(unit), "the broad target system must not mark units on its own")
end)

test("objective targets appear once tied to an active objective", function()
    local harness = new_harness()
    local active_unit = harness:add_interactee()
    local idle_unit = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", active_unit, { _objective_name = "objective_a" })
    harness:add_to_system("mission_objective_target_system", idle_unit, { _objective_name = "objective_b" })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(active_unit), "active objective unit not marked")
    assert_nil(harness:tracked_kind(idle_unit), "inactive objective unit must stay hidden")
end)

test("objective targets stay hidden when the objective system is unavailable", function()
    local harness = new_harness()
    local unit = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", unit, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_objective_system_available(false)
    harness:scan()

    assert_nil(harness:tracked_kind(unit), "no objective system means no broad-system markers")
end)

test("dedicated systems win over the broad target system", function()
    local harness = new_harness()
    local unit = harness:add_interactee()

    harness:add_to_system("decoder_device_system", unit)
    harness:add_to_system("mission_objective_target_system", unit, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "specific category must win")
end)

test("used interactable is dropped", function()
    local harness = new_harness()
    local unit, state = harness:add_interactee()

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()
    assert_not_nil(harness:tracked_kind(unit), "expected an initial marker")

    state.used = true
    harness:scan()

    assert_nil(harness:tracked_kind(unit), "used interactable should clear")
end)

test("inactive interactable is dropped", function()
    local harness = new_harness()
    local unit, state = harness:add_interactee()

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()
    assert_not_nil(harness:tracked_kind(unit), "expected an initial marker")

    state.active = false
    harness:scan()

    assert_nil(harness:tracked_kind(unit), "inactive interactable should clear")
end)

test("leaving the objective system drops the marker", function()
    local harness = new_harness()
    local unit = harness:add_interactee()

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()
    assert_not_nil(harness:tracked_kind(unit), "expected an initial marker")

    harness:remove_from_system("decoder_device_system", unit)
    harness:scan()

    assert_nil(harness:tracked_kind(unit), "marker should clear once the objective system drops the unit")
end)

test("interactee that belongs to no objective system is ignored", function()
    local harness = new_harness()
    local unit = harness:add_interactee()

    harness:scan()

    assert_nil(harness:tracked_kind(unit), "plain interactee should not be tracked")
end)

test("existing classifications are not overridden", function()
    local harness = new_harness()
    local unit = harness:add_interactee({ interaction_type = "health_station" })

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()

    assert_equal("medicae_station", harness:tracked_kind(unit), "known kinds must win over the objective fallback")
end)

test("disabled category produces no marker", function()
    local harness = new_harness()
    local unit = harness:add_interactee()

    harness.settings.show_mission_objective_hacking = "off"
    harness:add_to_system("decoder_device_system", unit)
    harness:scan()

    assert_nil(harness:tracked_kind(unit), "disabled category should not track")
end)

test("disabling one category leaves the others working", function()
    local harness = new_harness()
    local hacking_unit = harness:add_interactee()
    local scanner_unit = harness:add_interactee()

    harness.settings.show_mission_objective_hacking = "off"
    harness:add_to_system("decoder_device_system", hacking_unit)
    harness:add_to_system("scanning_event_system", scanner_unit)
    harness:scan()

    assert_nil(harness:tracked_kind(hacking_unit), "disabled category should not track")
    assert_equal("mission_objective_scanner", harness:tracked_kind(scanner_unit), "other categories must still work")
end)

test("re-enabling a category restores the marker", function()
    local harness = new_harness()
    local unit = harness:add_interactee()

    harness.settings.show_mission_objective_hacking = "off"
    harness:add_to_system("decoder_device_system", unit)
    harness:scan()
    assert_nil(harness:tracked_kind(unit), "disabled category should not track")

    harness.settings.show_mission_objective_hacking = "icon_distance"
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "re-enabled category should track again")
end)

test("all categories disabled skips the objective scan entirely", function()
    local harness = new_harness()
    local unit = harness:add_interactee()

    for _, setting_id in pairs(MISSION_OBJECTIVE_SETTING_BY_KIND) do
        harness.settings[setting_id] = "off"
    end

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()

    assert_nil(harness:tracked_kind(unit), "no category should track when all are off")
end)

test("objective system membership keeps a marker alive without an interactee", function()
    local harness = new_harness()
    local unit = harness:add_interactee()

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()
    assert_not_nil(harness:tracked_kind(unit), "expected an initial marker")

    -- Objective zones are never interactees, so losing the interactee alone
    -- must not retire a marker the objective system still holds.
    harness:remove_interactee(unit)
    harness:scan()
    assert_equal("mission_objective_hacking", harness:tracked_kind(unit),
        "objective system should still hold the unit")

    harness:remove_from_system("decoder_device_system", unit)
    harness:scan()

    assert_nil(harness:tracked_kind(unit), "dropping both sources should clear")
end)

-- The zone selection table is the only per-target scanned signal that exists.
test("targets flagged scanned in the zone selection are hidden", function()
    local harness = new_harness()
    local scanned = harness:add_interactee()
    local pending = harness:add_interactee()

    harness:add_scan_zone({
        selection = { [scanned] = true, [pending] = false },
        total = 2,
        progression = 1,
    })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_nil(harness:tracked_kind(scanned), "a scanned target must be dropped")
    assert_equal("mission_objective_scanner", harness:tracked_kind(pending), "an unscanned target must stay")
end)

-- Safety valve: the flag is only trusted when the table agrees with the zone's
-- own counter, so a different layout can never hide live targets.
test("a selection that disagrees with the progression counter hides nothing", function()
    local harness = new_harness()
    local first = harness:add_interactee()
    local second = harness:add_interactee()

    harness:add_scan_zone({
        selection = { [first] = true, [second] = true },
        total = 3,
        progression = 1,
    })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_equal("mission_objective_scanner", harness:tracked_kind(first), "mismatched flags must not hide targets")
    assert_equal("mission_objective_scanner", harness:tracked_kind(second), "mismatched flags must not hide targets")
end)

test("an array selection is shown in full", function()
    local harness = new_harness()
    local first = harness:add_interactee()
    local second = harness:add_interactee()

    harness:add_scan_zone({ scannables = { first, second }, progression = 1 })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_equal("mission_objective_scanner", harness:tracked_kind(first), "array selection must still mark")
    assert_equal("mission_objective_scanner", harness:tracked_kind(second), "array selection must still mark")
end)

-- The client path: the server-only selection is empty, so the selection is
-- recovered from the replicated scannable flags.
test("a client with an empty zone selection recovers targets from scannable flags", function()
    local harness = new_harness()
    local first = harness:add_interactee()
    local second = harness:add_interactee()

    harness:add_scan_zone({ scannables = {}, total = 3, progression = 1 })
    harness:add_to_system("mission_objective_zone_scannable_system", first, { _is_active = true })
    harness:add_to_system("mission_objective_zone_scannable_system", second, { _is_active = true })
    harness:add_to_system("mission_objective_zone_scannable_system", harness:add_interactee(), { _is_active = false })
    harness:scan_with_active_objective()

    assert_equal("mission_objective_scanner", harness:tracked_kind(first), "client fallback did not mark")
    assert_equal("mission_objective_scanner", harness:tracked_kind(second), "client fallback did not mark")
end)

-- Guard against a flood: if the recovered set disagrees with the zone counter
-- the flag is not understood, so nothing is marked.
-- The reported bug: the flag clears the instant a target is scanned, before the
-- zone counter catches up. Requiring exact equality blanked every marker.
test("scanning one target does not blank the rest on the fallback path", function()
    local harness = new_harness()
    local first = harness:add_interactee()
    local second = harness:add_interactee()
    local third = harness:add_interactee()

    harness:add_scan_zone({ scannables = {}, total = 3, progression = 0 })

    for _, unit in ipairs({ first, second, third }) do
        harness:add_to_system("mission_objective_zone_scannable_system", unit, { _is_active = true })
    end

    harness:scan_with_active_objective()
    assert_equal("mission_objective_scanner", harness:tracked_kind(first), "expected all three marked")

    -- One scanned: its flag clears immediately, the zone counter has not moved.
    harness.env._safe_unit_to_extension_map("mission_objective_zone_scannable_system")[first]._is_active = false
    harness:scan_with_active_objective()

    assert_nil(harness:tracked_kind(first), "the scanned target must clear")
    assert_equal("mission_objective_scanner", harness:tracked_kind(second), "the rest must survive the lag")
    assert_equal("mission_objective_scanner", harness:tracked_kind(third), "the rest must survive the lag")
end)

test("a disagreeing scannable count marks nothing", function()
    local harness = new_harness()
    local units = {}

    harness:add_scan_zone({ scannables = {}, total = 3, progression = 1 })

    for i = 1, 5 do
        units[i] = harness:add_interactee()
        harness:add_to_system("mission_objective_zone_scannable_system", units[i], { _is_active = true })
    end

    harness:scan_with_active_objective()

    for i = 1, 5 do
        assert_nil(harness:tracked_kind(units[i]), "an unvalidated flag must not put every scannable on the radar")
    end
end)

test("the selection path wins over the scannable fallback", function()
    local harness = new_harness()
    local selected = harness:add_interactee()
    local stray = harness:add_interactee()

    harness:add_scan_zone({ scannables = { selected }, total = 1, progression = 0 })
    harness:add_to_system("mission_objective_zone_scannable_system", selected, { _is_active = true })
    harness:add_to_system("mission_objective_zone_scannable_system", stray, { _is_active = true })
    harness:scan_with_active_objective()

    assert_equal("mission_objective_scanner", harness:tracked_kind(selected), "selection must still mark")
    assert_nil(harness:tracked_kind(stray), "fallback must not run when the selection worked")
end)

-- The real per-target completion signal: the scannable extension clears
-- _is_active as each target is scanned.
test("a scanned target is dropped once its scannable goes inactive", function()
    local harness = new_harness()
    local scanned = harness:add_interactee()
    local pending = harness:add_interactee()

    harness:add_scan_zone({ scannables = { scanned, pending }, total = 2, progression = 1 })
    harness:add_to_system("mission_objective_zone_scannable_system", scanned, { _is_active = false })
    harness:add_to_system("mission_objective_zone_scannable_system", pending, { _is_active = true })
    harness:scan_with_active_objective()

    assert_nil(harness:tracked_kind(scanned), "a scanned target must be dropped")
    assert_equal("mission_objective_scanner", harness:tracked_kind(pending), "an unscanned target must stay")
end)

test("targets clear one by one as each is scanned", function()
    local harness = new_harness()
    local first = harness:add_interactee()
    local second = harness:add_interactee()
    local third = harness:add_interactee()

    harness:add_scan_zone({ scannables = { first, second, third }, total = 3 })

    for _, unit in ipairs({ first, second, third }) do
        harness:add_to_system("mission_objective_zone_scannable_system", unit, { _is_active = true })
    end

    harness:scan_with_active_objective()
    assert_equal("mission_objective_scanner", harness:tracked_kind(first), "expected all three marked")

    harness.env._safe_unit_to_extension_map("mission_objective_zone_scannable_system")[first]._is_active = false
    harness:scan_with_active_objective()

    assert_nil(harness:tracked_kind(first), "the scanned target must clear")
    assert_equal("mission_objective_scanner", harness:tracked_kind(second), "the rest must remain")
    assert_equal("mission_objective_scanner", harness:tracked_kind(third), "the rest must remain")
end)

-- Missing data must never blank a live objective.
test("a scannable with no extension or no flag stays visible", function()
    local harness = new_harness()
    local unknown = harness:add_interactee()
    local flagless = harness:add_interactee()

    harness:add_scan_zone({ scannables = { unknown, flagless }, total = 2 })
    harness:add_to_system("mission_objective_zone_scannable_system", flagless, {})
    harness:scan_with_active_objective()

    assert_equal("mission_objective_scanner", harness:tracked_kind(unknown), "missing extension must not hide")
    assert_equal("mission_objective_scanner", harness:tracked_kind(flagless), "missing flag must not hide")
end)

-- A joining client may not have every server field replicated. Degrading to
-- fewer markers is acceptable; crashing or mislabelling is not.
test("unreplicated objective state degrades to no markers rather than failing", function()
    local harness = new_harness()
    local scannable = harness:add_interactee()
    local target = harness:add_interactee()

    -- Zone present but with none of its fields populated.
    harness:add_to_system("mission_objective_zone_system", harness:add_interactee(), {})
    harness:add_to_system("mission_objective_zone_scannable_system", scannable, {})
    harness:add_to_system("mission_objective_target_system", target, {})
    harness:set_objective_system_available(false)
    harness:scan()

    assert_nil(harness:tracked_kind(scannable), "no zone state means no scanner markers")
    assert_nil(harness:tracked_kind(target), "no objective state means no target markers")
end)

test("a scannable stays marked across consecutive scans", function()
    local harness = new_harness()
    local scannable = harness:add_interactee()

    harness:add_scan_zone({ scannables = { scannable } })
    harness:set_active_objective_names({ "objective_a" })

    -- Regression guard: re-confirming an owned unit each pass is what stops the
    -- track/prune cycle that made these markers flicker.
    for _ = 1, 4 do
        harness:scan()
        assert_equal("mission_objective_scanner", harness:tracked_kind(scannable), "marker flickered between scans")
    end
end)

test("an objective step retires once it goes inactive", function()
    local harness = new_harness()
    local unit, state = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:scan()
    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "expected an initial marker")

    -- Objective steps often never report themselves used; they just stop being
    -- active once completed.
    state.active = false
    harness:scan()

    assert_nil(harness:tracked_kind(unit), "a completed objective step must not linger")
end)


-- Clandestium Gloriana places several Synchronistor overrides and arms one at a
-- time. Marking inactive ones put every copy on the radar at once.
test("only the armed copy of a repeated objective device is marked", function()
    local harness = new_harness()
    local armed = harness:add_interactee({ interaction_type = "decoder_device" })
    local idle_a = harness:add_interactee({ interaction_type = "decoder_device", active = false })
    local idle_b = harness:add_interactee({ interaction_type = "decoder_device", active = false })

    harness:add_to_system("decoder_device_system", armed)
    harness:add_to_system("decoder_device_system", idle_a)
    harness:add_to_system("decoder_device_system", idle_b)
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(armed), "the armed device must be marked")
    assert_nil(harness:tracked_kind(idle_a), "an inactive copy must not be marked")
    assert_nil(harness:tracked_kind(idle_b), "an inactive copy must not be marked")
end)

-- The distinction that matters: `show_marker` is about range and line of sight,
-- `active` is about whether this device is the live one.
test("an armed device is marked before the game draws its prompt", function()
    local harness = new_harness()
    local unit = harness:add_interactee({ interaction_type = "decoder_device", show_marker = false })

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unit),
        "an armed device must show before you are close enough for the prompt")
end)

test("a device that becomes armed later starts being marked", function()
    local harness = new_harness()
    local unit, state = harness:add_interactee({ interaction_type = "decoder_device", active = false })

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()
    assert_nil(harness:tracked_kind(unit), "an unarmed device must stay hidden")

    state.active = true
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "arming the device must mark it")
end)

-- The probe scaffolding is gone; this is the one debug line that remains.
test("the rejection log stays quiet unless debug mode is on", function()
    local harness = new_harness()
    local unit, state = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()

    state.used = true
    harness:scan()
    assert_equal("", harness:log_text(), "nothing should be logged with debug mode off")

    harness.settings.debug_mode = true
    harness:scan()
    assert_contains(harness:log_text(), "Mission objective marker not shown", "the rejection log did not run")
end)

-- A finished puzzle reports `complete` and then stops changing, while its
-- interactee stays active and unused for the rest of the mission. Both devices
-- stay marked; only the colour tells them apart.
test("a completed minigame keeps its marker without a state colour", function()
    local harness = new_harness()
    local unstarted = harness:add_interactee({ interaction_type = "decoder_device" })
    local solved = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("decoder_device_system", unstarted)
    harness:add_to_system("decoder_device_system", solved)
    harness:add_to_system("minigame_system", unstarted, { _minigame = { _current_state = "none" } })
    harness:add_to_system("minigame_system", solved, { _minigame = { _current_state = "complete" } })
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unstarted), "an unstarted puzzle must stay marked")
    assert_equal("mission_objective_hacking", harness:tracked_kind(solved), "a solved puzzle must stay marked")
    assert_nil(harness:tracked_minigame_state(solved), "a solved puzzle must use the shared tint")
end)

-- `_active` means a player currently has the puzzle open, not that the device
-- wants one. Hiding on it inverted the marker: gone while idle, back while
-- somebody was already solving it.
test("an open minigame does not hide its marker", function()
    local harness = new_harness()
    local unit = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("decoder_device_system", unit)
    harness:add_to_system("minigame_system", unit, {
        _active = true,
        _minigame = { _current_state = "gameplay" },
    })
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unit),
        "a device somebody is solving must keep its marker")
end)

-- An objective can require the same device several times, and the devices stay
-- part of it once solved. A solved puzzle keeps its marker and drops back to the
-- shared objective tint, so nothing blinks out and returns in red when it
-- re-arms. What ends a device for good is its objective going inactive.
test("a solved device keeps its marker in the shared tint", function()
    local harness = new_harness()
    local unit = harness:add_interactee({ interaction_type = "decoder_device" })
    local minigame = { _minigame = { _current_state = "gameplay" } }

    harness:add_to_system("decoder_device_system", unit)
    harness:add_to_system("mission_objective_target_system", unit, { _objective_name = "repeat_objective" })
    harness:add_to_system("minigame_system", unit, minigame)
    harness:set_active_objective_names({ "repeat_objective" })
    harness:scan()
    assert_equal("waiting", harness:tracked_minigame_state(unit), "a running puzzle must ask for a player")

    minigame._minigame._current_state = "complete"
    harness:scan()
    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "a solved device must stay marked")
    assert_nil(harness:tracked_minigame_state(unit), "a solved device must fall back to the shared tint")

    -- The objective arms the same device for its second round.
    minigame._minigame._current_state = "gameplay"
    harness:scan()
    assert_equal("waiting", harness:tracked_minigame_state(unit), "an armed device must ask for a player again")

    -- The event finishes for good.
    harness:set_active_objective_names({})
    harness:scan()
    harness:scan()
    assert_nil(harness:tracked_kind(unit), "only the finished objective removes it")
end)

-- The tracked entry keeps its previous meta when none is supplied, so a solved
-- puzzle would otherwise keep wearing the colour it had while running.
test("a solved device does not keep its running colour", function()
    local harness = new_harness()
    local unit = { name = "bare_device", position = { x = 1, y = 0, z = 0 } }
    local minigame = { _active = true, _minigame = { _current_state = "gameplay" } }

    -- Claimed by the system pass, which supplies no meta of its own.
    harness:add_to_system("mission_objective_target_system", unit, { _objective_name = "objective_a" })
    harness:add_to_system("minigame_system", unit, minigame)
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()
    assert_equal("active", harness:tracked_minigame_state(unit), "a puzzle with a player must report active")

    minigame._active = false
    minigame._minigame._current_state = "complete"
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(unit), "a solved device must stay marked")
    assert_nil(harness:tracked_minigame_state(unit), "the stale running colour must be cleared")
end)

test("a minigame with no state is unaffected", function()
    local harness = new_harness()
    local no_extension = harness:add_interactee({ interaction_type = "decoder_device" })
    local no_state = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("decoder_device_system", no_extension)
    harness:add_to_system("decoder_device_system", no_state)
    harness:add_to_system("minigame_system", no_state, {})
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(no_extension), "no minigame must not hide")
    assert_equal("mission_objective_hacking", harness:tracked_kind(no_state), "a missing state must not hide")
end)

-- The marker keeps its icon and dropdown and changes only its colour key, so a
-- puzzle can say whether it still needs somebody without becoming another kind.
-- Three states, matching the device's own hologram: unstarted keeps the shared
-- objective tint, running-but-unattended asks for a player, and running with one
-- says it is being worked on.
test("a running puzzle reports whether it needs a player", function()
    local harness = new_harness()
    local unattended = harness:add_interactee({ interaction_type = "decoder_device" })
    local being_solved = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("decoder_device_system", unattended)
    harness:add_to_system("decoder_device_system", being_solved)
    harness:add_to_system("minigame_system", unattended, {
        _active = false,
        _minigame = { _current_state = "gameplay" },
    })
    harness:add_to_system("minigame_system", being_solved, {
        _active = true,
        _minigame = { _current_state = "gameplay" },
    })
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unattended), "the kind must not change with state")
    assert_equal("mission_objective_hacking", harness:tracked_kind(being_solved), "the kind must not change with state")
    assert_equal("waiting", harness:tracked_minigame_state(unattended),
        "a running puzzle with nobody at it must ask for a player")
    assert_equal("active", harness:tracked_minigame_state(being_solved),
        "a puzzle with a player at it must report active")
end)

-- The device carries a minigame extension long before the puzzle is placed, so
-- treating that as "needs a player" painted it red across the whole mission.
test("an unstarted puzzle keeps the shared objective colour", function()
    local harness = new_harness()
    local unit = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("decoder_device_system", unit)
    harness:add_to_system("minigame_system", unit, { _active = false, _minigame = { _current_state = "none" } })
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "an unstarted device must still be marked")
    assert_nil(harness:tracked_minigame_state(unit), "an unstarted puzzle must carry no state colour")
end)

test("a puzzle state follows the device through its whole life", function()
    local harness = new_harness()
    local unit = harness:add_interactee({ interaction_type = "decoder_device" })
    local minigame = { _minigame = { _current_state = "none" } }

    harness:add_to_system("decoder_device_system", unit)
    harness:add_to_system("minigame_system", unit, minigame)
    harness:scan()
    assert_nil(harness:tracked_minigame_state(unit), "an unstarted puzzle must carry no state colour")

    minigame._minigame._current_state = "gameplay"
    harness:scan()
    assert_equal("waiting", harness:tracked_minigame_state(unit), "a started puzzle must ask for a player")

    minigame._active = true
    harness:scan()
    assert_equal("active", harness:tracked_minigame_state(unit), "it must report active once somebody arrives")

    -- Somebody backed out without finishing.
    minigame._active = false
    harness:scan()
    assert_equal("waiting", harness:tracked_minigame_state(unit), "it must ask again when abandoned part-way")

    minigame._minigame._current_state = "complete"
    harness:scan()
    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "a solved puzzle keeps its marker")
    assert_nil(harness:tracked_minigame_state(unit), "and falls back to the shared tint")
end)

-- An unknown state must never be read as one of the two live ones.
test("an unrecognised puzzle state carries no colour", function()
    local harness = new_harness()
    local unit = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("decoder_device_system", unit)
    harness:add_to_system("minigame_system", unit, { _active = true, _minigame = { _current_state = "intro" } })
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "it must still be marked")
    assert_nil(harness:tracked_minigame_state(unit), "only a running puzzle may take a state colour")
end)

test("objective markers without a puzzle carry no state", function()
    local harness = new_harness()
    local unit = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "a plain terminal must still be marked")
    assert_nil(harness:tracked_minigame_state(unit), "a device with no puzzle must keep the shared objective tint")
end)

-- Ice over the gears: the objective only ends when the last chunk is broken, so
-- without a per-unit check every chunk keeps its marker until then.
test("a destroyed objective target drops its own marker", function()
    local harness = new_harness()
    local intact = { name = "ice_a", position = { x = 1, y = 0, z = 0 }, health_alive = true }
    local broken = { name = "ice_b", position = { x = 2, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("mission_objective_target_system", intact, { _objective_name = "objective_a" })
    harness:add_to_system("mission_objective_target_system", broken, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(intact), "an intact chunk must be marked")
    assert_equal("mission_objective_other", harness:tracked_kind(broken), "an intact chunk must be marked")

    broken.health_alive = false
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(intact), "the rest must stay marked")
    assert_nil(harness:tracked_kind(broken), "a broken chunk must lose its marker on its own")
end)

-- Luggable spawn points, socket placements and waypoints all sit in the target
-- system alongside the real steps, and one of them is not even reachable.
test("objective targets with nothing to act on are never marked", function()
    local harness = new_harness()
    local hint = { name = "spawn_point", position = { x = 3, y = 0, z = 0 } }
    local destructible = { name = "ice", position = { x = 4, y = 0, z = 0 }, health_alive = true }
    local interactee = harness:add_interactee({})

    harness:add_to_system("mission_objective_target_system", hint, { _objective_name = "objective_a" })
    harness:add_to_system("mission_objective_target_system", destructible, { _objective_name = "objective_a" })
    harness:add_to_system("mission_objective_target_system", interactee, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_nil(harness:tracked_kind(hint), "a bare position hint must not be marked")
    assert_equal("mission_objective_other", harness:tracked_kind(destructible), "a destructible step must be marked")
    assert_equal("mission_objective_other", harness:tracked_kind(interactee), "an interactable step must be marked")
end)

-- The train controls you destroy to stop the train are bare units too, and the
-- whole objective is made of them. Filtering those left the finale unmarked.
test("an objective made only of bare units keeps its markers", function()
    local harness = new_harness()
    local control_a = { name = "train_control_a", position = { x = 1, y = 0, z = 0 } }
    local control_b = { name = "train_control_b", position = { x = 2, y = 0, z = 0 } }

    harness:add_to_system("mission_objective_target_system", control_a, { _objective_name = "stop_train" })
    harness:add_to_system("mission_objective_target_system", control_b, { _objective_name = "stop_train" })
    harness:set_active_objective_names({ "stop_train" })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(control_a), "the step itself must stay marked")
    assert_equal("mission_objective_other", harness:tracked_kind(control_b), "the step itself must stay marked")
end)

-- Missions run more than one objective at a time, so one objective's hints must
-- not decide anything about another's.
test("hints are filtered per objective, not across the mission", function()
    local harness = new_harness()
    local cell = harness:add_interactee({})
    local spawn_point = { name = "cell_spawn", position = { x = 3, y = 0, z = 0 } }
    local control = { name = "train_control", position = { x = 4, y = 0, z = 0 } }

    harness:add_to_system("mission_objective_target_system", cell, { _objective_name = "luggables" })
    harness:add_to_system("mission_objective_target_system", spawn_point, { _objective_name = "luggables" })
    harness:add_to_system("mission_objective_target_system", control, { _objective_name = "stop_train" })
    harness:set_active_objective_names({ "luggables", "stop_train" })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(cell), "a real luggable step must be marked")
    assert_nil(harness:tracked_kind(spawn_point), "a spawn point beside a real step must stay hidden")
    assert_equal("mission_objective_other", harness:tracked_kind(control),
        "a bare-only objective must not be filtered by another objective's hints")
end)

-- A step that stops being marked has to be identifiable without another probe.
test("filtered hints are named in debug mode", function()
    local harness = new_harness()
    local cell = harness:add_interactee({})
    local spawn_point = { name = "cell_spawn", position = { x = 5, y = 0, z = 0 } }

    harness.settings.debug_mode = true
    harness:add_to_system("mission_objective_target_system", cell, { _objective_name = "luggables" })
    harness:add_to_system("mission_objective_target_system", spawn_point, { _objective_name = "luggables" })
    harness:set_active_objective_names({ "luggables" })
    harness:scan()

    assert_contains(harness:log_text(), "Mission objective position hint filtered:", "the hint filter is not reported")
    assert_contains(harness:log_text(), "objective=luggables", "the report does not name the objective")
end)

-- Hab Dreyko places three interrogators and the event can finish with one never
-- used. That one is reached by interaction type alone, which used to skip the
-- active-objective rule, so it stayed drawn for the rest of the mission.
test("an unused device is dropped when its objective ends", function()
    local harness = new_harness()
    local used = harness:add_interactee({ interaction_type = "decoder_device" })
    local unused = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("mission_objective_target_system", used, { _objective_name = "interrogators" })
    harness:add_to_system("mission_objective_target_system", unused, { _objective_name = "interrogators" })
    harness:set_active_objective_names({ "interrogators" })
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(used), "a live device must be marked")
    assert_equal("mission_objective_hacking", harness:tracked_kind(unused), "a live device must be marked")

    -- The event finishes with the second device never touched.
    harness:set_active_objective_names({})
    harness:scan()
    harness:scan()

    assert_nil(harness:tracked_kind(used), "the objective is over, so its markers must go")
    assert_nil(harness:tracked_kind(unused), "an unused device must not outlive its objective")
end)

-- The interaction-type route is the one that skipped the rule, so it is checked
-- on a kind that route resolves on its own.
test("interaction type alone does not outrank the active objective", function()
    local harness = new_harness()
    local skull = harness:add_interactee({ interaction_type = "servo_skull_activator" })

    harness:add_to_system("mission_objective_target_system", skull, { _objective_name = "follow_skull" })
    harness:set_active_objective_names({})
    harness:scan()
    harness:scan()

    assert_nil(harness:tracked_kind(skull), "a device of a dormant objective must not be marked")

    harness:set_active_objective_names({ "follow_skull" })
    harness:scan()

    assert_equal("mission_objective_servo_skull", harness:tracked_kind(skull),
        "it must come back when its objective starts")
end)

-- A device the objective system never lists is not gated: that is the only way
-- devices the mission does not attribute stay reachable.
test("a device no objective owns is unaffected", function()
    local harness = new_harness()
    local unowned = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("decoder_device_system", unowned)
    harness:set_active_objective_names({})
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unowned),
        "a dedicated-system device must not need an active objective")
end)

-- The dedicated systems claim before the broad target pass runs, so the map of
-- which objectives are live has to exist before any of them claim. Built too
-- late, a decoder device of a finished objective was marked by the dedicated
-- pass every scan and the gate never saw it.
test("a dedicated system device is dropped when its objective ends", function()
    local harness = new_harness()
    local device = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("decoder_device_system", device)
    harness:add_to_system("mission_objective_target_system", device, { _objective_name = "interrogators" })
    harness:set_active_objective_names({ "interrogators" })
    harness:scan()
    assert_equal("mission_objective_hacking", harness:tracked_kind(device), "a live device must be marked")

    -- The set of live objectives is rebuilt inside the objective scan, which runs
    -- after the interactee pass, so the interactee pass sees it one scan later.
    harness:set_active_objective_names({})
    harness:scan()
    harness:scan()

    assert_nil(harness:tracked_kind(device), "the dedicated pass must not outlive the objective either")
end)

-- The train controls carry no completion state anywhere: no interactee, no
-- health, in no system, and their own target extension never changes a field.
-- The game drops its own world marker for one when it is destroyed, and that is
-- the only thing that moves.
test("a bare step is retired when the game drops its world marker", function()
    local harness = new_harness()
    local control_a = { name = "train_control_a", position = { x = 1, y = 0, z = 0 } }
    local control_b = { name = "train_control_b", position = { x = 2, y = 0, z = 0 } }

    harness:add_to_system("mission_objective_target_system", control_a, { _objective_name = "stop_train" })
    harness:add_to_system("mission_objective_target_system", control_b, { _objective_name = "stop_train" })
    harness:set_active_objective_names({ "stop_train" })
    harness:set_world_marker_units({ control_a, control_b })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(control_a), "a live control must be marked")
    assert_equal("mission_objective_other", harness:tracked_kind(control_b), "a live control must be marked")

    -- One control is destroyed; the game drops its marker, the other keeps one.
    harness:set_world_marker_units({ control_b })
    harness:scan()

    assert_nil(harness:tracked_kind(control_a), "a destroyed control must lose its marker on its own")
    assert_equal("mission_objective_other", harness:tracked_kind(control_b), "the rest must stay marked")
end)

-- If not one unit of the objective has a marker, the list plainly does not
-- describe this objective, and dropping them all would hide the step rather
-- than retire it.
test("an objective the marker list does not cover is not filtered", function()
    local harness = new_harness()
    local control = { name = "train_control", position = { x = 3, y = 0, z = 0 } }
    local unrelated = { name = "other_thing", position = { x = 9, y = 0, z = 0 } }

    harness:add_to_system("mission_objective_target_system", control, { _objective_name = "stop_train" })
    harness:set_active_objective_names({ "stop_train" })
    harness:set_world_marker_units({ unrelated })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(control),
        "an uncovered objective must keep its markers")
end)

test("an unreadable marker list changes nothing", function()
    local harness = new_harness()
    local control = { name = "train_control", position = { x = 4, y = 0, z = 0 } }

    harness:add_to_system("mission_objective_target_system", control, { _objective_name = "stop_train" })
    harness:set_active_objective_names({ "stop_train" })
    harness:set_world_marker_units(nil)
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(control),
        "an unreadable list must not hide anything")
end)

-- Only bare steps use this. An objective that has real interactables in it is
-- decided by those, so a device out of the game's marker range is unaffected.
test("world markers do not gate objectives that have real steps", function()
    local harness = new_harness()
    local device = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("mission_objective_target_system", device, { _objective_name = "interrogators" })
    harness:set_active_objective_names({ "interrogators" })
    harness:set_world_marker_units({})
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(device),
        "an interactable step must not need a world marker")
end)

-- A zone checks its own objective before selecting any target, so its targets
-- must not then be re-judged by the objective the target system files them
-- under -- which is not always the one whose zone selected them. Getting this
-- wrong hid every scan target on Hab Dreyko.
test("scan targets survive a differing objective on the target system", function()
    local harness = new_harness()
    local scannable = { name = "scannable_a", position = { x = 1, y = 0, z = 0 } }
    local zone = { name = "scan_zone", position = { x = 0, y = 0, z = 0 } }

    harness:add_to_system("mission_objective_zone_system", zone, {
        _objective_name = "scan_hab_a",
        _activated = true,
        _num_scannables_in_zone = 1,
        _selected_scannable_units = { scannable },
    })
    -- The target system files it under a different, dormant objective.
    harness:add_to_system("mission_objective_target_system", scannable, { _objective_name = "scan_hab_b" })
    harness:set_active_objective_names({ "scan_hab_a" })
    harness:scan()

    assert_equal("mission_objective_scanner", harness:tracked_kind(scannable),
        "a target its own zone selected must be marked")
end)

-- The exemption is for zone-confirmed claims only; everything else still has to
-- belong to a live objective.
test("the zone exemption does not leak to other claims", function()
    local harness = new_harness()
    local device = harness:add_interactee({ interaction_type = "decoder_device" })

    harness:add_to_system("decoder_device_system", device)
    harness:add_to_system("mission_objective_target_system", device, { _objective_name = "finished_objective" })
    harness:set_active_objective_names({ "other_objective" })
    harness:scan()
    harness:scan()

    assert_nil(harness:tracked_kind(device), "a dedicated device of a dormant objective must stay hidden")
end)

-- A claim dropped at the choke point is where a marker vanishes with no other
-- trace, which is how the scan targets went missing unnoticed.
test("dropped claims are named in debug mode", function()
    local harness = new_harness()
    local device = harness:add_interactee({ interaction_type = "decoder_device" })

    harness.settings.debug_mode = true
    harness:add_to_system("decoder_device_system", device)
    harness:add_to_system("mission_objective_target_system", device, { _objective_name = "finished_objective" })
    harness:set_active_objective_names({ "other_objective" })
    harness:scan()
    harness:scan()

    assert_contains(harness:log_text(), "Mission objective marker not claimed:", "the dropped claim is not reported")
    assert_contains(harness:log_text(), "reason=inactive_objective", "the report does not name the gate")
end)

-- A run with no scan markers has to say which gate closed. Every debug path
-- that has ever shipped unverified here has shipped broken.
test("the scan zone pass reports why it produced nothing", function()
    local harness = new_harness()
    local zone = { name = "scan_zone", position = { x = 0, y = 0, z = 0 } }

    harness.settings.debug_mode = true
    harness:add_to_system("mission_objective_zone_system", zone, {
        _objective_name = "scan_hab_a",
        -- A client can see the zone and its objective but not that it is armed.
        _activated = false,
        _num_scannables_in_zone = 3,
        _current_progression = 0,
    })
    harness:set_active_objective_names({ "scan_hab_a" })
    harness:scan()

    local text = harness:log_text()

    assert_contains(text, "Scan zone state:", "the zone probe did not run")
    assert_contains(text, "objective_active=true", "the probe did not report the objective")
    assert_contains(text, "activated=false", "the probe did not report the armed flag")
    assert_contains(text, "Scan zone summary:", "the summary did not run")
    assert_contains(text, "has_active_zone=false", "the summary did not report the outcome")
end)

test("the scan zone pass reports a working selection", function()
    local harness = new_harness()
    local scannable = { name = "scannable_a", position = { x = 1, y = 0, z = 0 } }
    local zone = { name = "scan_zone", position = { x = 0, y = 0, z = 0 } }

    harness.settings.debug_mode = true
    harness:add_to_system("mission_objective_zone_system", zone, {
        _objective_name = "scan_hab_a",
        _activated = true,
        _num_scannables_in_zone = 1,
        _current_progression = 0,
        _selected_scannable_units = { scannable },
    })
    harness:set_active_objective_names({ "scan_hab_a" })
    harness:scan()

    local text = harness:log_text()

    assert_contains(text, "selection_entries=1", "the probe did not report the selection size")
    assert_contains(text, "claimed=1", "the probe did not report what the zone claimed")
    assert_equal("mission_objective_scanner", harness:tracked_kind(scannable), "the target must still be marked")
end)

-- A marker that outlives its objective leaves no other trace, and this probe
-- has twice shipped broken -- once calling a helper declared later in the file,
-- once reaching into the logger internals the harness does not provide.
test("the marker probe reports which pass claimed a marker", function()
    local harness = new_harness()
    local device = harness:add_interactee({ interaction_type = "decoder_device" })

    harness.settings.debug_mode = true
    harness:add_to_system("decoder_device_system", device)
    harness:add_to_system("mission_objective_target_system", device, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    local text = harness:log_text()

    assert_contains(text, "Objective marker state:", "the marker probe did not run")
    assert_contains(text, "kind=mission_objective_hacking", "the probe did not report the marker kind")
    assert_contains(text, "objective=objective_a", "the probe did not report the objective")
    assert_contains(text, "objective_active=true", "the probe did not report whether the objective is live")
    assert_contains(text, "source=", "the probe did not report which pass claimed it")
end)

-- A bare step is retired by the game's own world marker going away, so a marker
-- that outlives one has to say whether it still has a marker, and whether the
-- list is trusted for its objective at all.
test("the marker probe reports the world marker gate", function()
    local harness = new_harness()
    local waypoint = { name = "waypoint", position = { x = 1, y = 0, z = 0 } }
    local other = { name = "other_step", position = { x = 2, y = 0, z = 0 } }

    harness.settings.debug_mode = true
    harness:add_to_system("mission_objective_target_system", waypoint, { _objective_name = "extract" })
    harness:add_to_system("mission_objective_target_system", other, { _objective_name = "extract" })
    harness:set_active_objective_names({ "extract" })
    harness:set_world_marker_units({ other })
    harness:scan()

    local text = harness:log_text()

    -- The probe reports drawn markers, so the retired one is absent by design
    -- and the surviving one carries the state of the gate that kept it.
    assert_nil(harness:tracked_kind(waypoint), "a bare step with no world marker must be retired")
    assert_equal("mission_objective_other", harness:tracked_kind(other), "a step with a marker must stay")
    assert_contains(text, "world_marker=true", "the probe did not report the world marker")
    assert_contains(text, "objective_covered=true", "the probe did not report that the list covers the objective")
    assert_contains(text, "marker_list=true", "the probe did not report that the list is readable")
end)

-- The failure being chased is a marker that stays drawn, so the report has to
-- carry the gate's state for one the list does not cover.
test("the marker probe reports an uncovered objective", function()
    local harness = new_harness()
    local waypoint = { name = "waypoint", position = { x = 1, y = 0, z = 0 } }

    harness.settings.debug_mode = true
    harness:add_to_system("mission_objective_target_system", waypoint, { _objective_name = "extract" })
    harness:set_active_objective_names({ "extract" })
    harness:set_world_marker_units({})
    harness:scan()

    local text = harness:log_text()

    assert_equal("mission_objective_other", harness:tracked_kind(waypoint),
        "an uncovered objective must keep its markers")
    assert_contains(text, "world_marker=false", "the probe did not report the missing world marker")
    assert_contains(text, "objective_covered=false", "the probe did not report that the list misses the objective")
end)

-- The last unit of an objective finishing looks exactly like an objective the
-- marker list never described. Recomputing coverage per scan read it as the
-- latter and switched the filter off at the moment it was needed, leaving a
-- waypoint drawn for the rest of the mission.
test("the last bare step is retired when its marker goes", function()
    local harness = new_harness()
    local waypoint = { name = "waypoint", position = { x = 1, y = 0, z = 0 } }

    harness:add_to_system("mission_objective_target_system", waypoint, { _objective_name = "to_deck" })
    harness:set_active_objective_names({ "to_deck" })
    harness:set_world_marker_units({ waypoint })
    harness:scan()
    assert_equal("mission_objective_other", harness:tracked_kind(waypoint), "a live step must be marked")

    -- The game drops the marker for the only unit the objective has.
    harness:set_world_marker_units({})
    harness:scan()

    assert_nil(harness:tracked_kind(waypoint), "the last step must be retired, not un-filtered")
end)

-- The fallback still has to hold for an objective the list genuinely never
-- covered, which is what stops the filter hiding a step it knows nothing about.
test("an objective never seen in the marker list is still never filtered", function()
    local harness = new_harness()
    local step = { name = "step", position = { x = 2, y = 0, z = 0 } }

    harness:add_to_system("mission_objective_target_system", step, { _objective_name = "uncovered" })
    harness:set_active_objective_names({ "uncovered" })
    harness:set_world_marker_units({})
    harness:scan()
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(step),
        "an objective the list never described must keep its markers")
end)

-- The frame around the game's own objective marker is an asset of the game's,
-- readable only off the live marker widget. Materials sit at no predictable key,
-- so the probe has to find them wherever they are.
test("the world marker probe names the game's marker materials", function()
    local harness = new_harness()
    local device = harness:add_interactee({ interaction_type = "decoder_device" })

    harness.settings.debug_mode = true
    harness:add_to_system("decoder_device_system", device)
    harness:add_to_system("mission_objective_target_system", device, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_list({
        {
            type = "mission_objective",
            unit = device,
            widget = {
                content = { icon = "content/ui/materials/hud/interactions/icons/objective_main" },
                style = {
                    frame = { material = "content/ui/materials/hud/markers/objective_frame" },
                    ignored = { size = { 32, 32 } },
                },
            },
        },
        -- A marker on a unit this mod does not track must not be walked.
        { type = "unrelated", unit = { name = "elsewhere" }, widget = {} },
    })
    harness:scan()

    local text = harness:log_text()

    assert_contains(text, "World marker materials:", "the world marker probe did not run")
    assert_contains(text, "type=mission_objective", "the probe did not report the marker template")
    assert_contains(text, "content/ui/materials/hud/markers/objective_frame",
        "the probe did not find a material nested in the widget style")
    assert_contains(text, "content/ui/materials/hud/interactions/icons/objective_main",
        "the probe did not find the marker icon")
end)

-- Which of a row of identical containers holds the cargo is a distinction the
-- mod cannot see any other way, and the target extension is where the level
-- designer records what a step is.
test("the target field probe reports a marked unit's own fields", function()
    local harness = new_harness()
    local container = harness:add_interactee({})

    harness.settings.debug_mode = true
    harness:add_to_system("mission_objective_target_system", container, {
        _objective_name = "collect_cargo",
        _ui_target_type = "luggable",
        _objective_stage = 2,
        _add_marker_on_objective_start = true,
        _owner_system = { NAME = "mission_objective_system" },
    })
    harness:set_active_objective_names({ "collect_cargo" })
    harness:scan()

    local text = harness:log_text()

    assert_contains(text, "Objective target fields:", "the target field probe did not run")
    assert_contains(text, "_ui_target_type=luggable", "the probe did not report the target type")
    assert_contains(text, "_objective_stage=2", "the probe did not report numeric fields")
    assert_contains(text, "_add_marker_on_objective_start=true", "the probe did not report boolean fields")
    assert_equal(nil, text:find("_owner_system", 1, true), "the owning system must not be walked")
end)

-- Chasm Logistratum files nine possible cargo containers and the one that holds
-- the cargo under a single objective, identical in every field but this one.
test("alternatives the mission did not choose are not marked", function()
    local harness = new_harness()
    local real = harness:add_interactee({})
    local decoy_a = harness:add_interactee({})
    local decoy_b = harness:add_interactee({})

    harness:add_to_system("mission_objective_target_system", real, {
        _objective_name = "collect_cargo",
        _add_marker_on_objective_start = true,
    })
    harness:add_to_system("mission_objective_target_system", decoy_a, {
        _objective_name = "collect_cargo",
        _add_marker_on_objective_start = false,
    })
    harness:add_to_system("mission_objective_target_system", decoy_b, {
        _objective_name = "collect_cargo",
        _add_marker_on_objective_start = false,
    })
    harness:set_active_objective_names({ "collect_cargo" })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(real), "the chosen container must be marked")
    assert_nil(harness:tracked_kind(decoy_a), "an unused alternative must not be marked")
    assert_nil(harness:tracked_kind(decoy_b), "an unused alternative must not be marked")
end)

-- When no unit of an objective claims a start marker the flag says nothing about
-- that objective, and hiding on it would silence the whole step.
test("an objective where nothing claims a start marker is untouched", function()
    local harness = new_harness()
    local step_a = harness:add_interactee({})
    local step_b = harness:add_interactee({})

    harness:add_to_system("mission_objective_target_system", step_a, {
        _objective_name = "reach_elevator",
        _add_marker_on_objective_start = false,
    })
    harness:add_to_system("mission_objective_target_system", step_b, { _objective_name = "reach_elevator" })
    harness:set_active_objective_names({ "reach_elevator" })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(step_a), "the step must stay marked")
    assert_equal("mission_objective_other", harness:tracked_kind(step_b), "a unit with no flag must stay marked")
end)

-- Which stage of a multi-stage objective is live is known only to the objective.
test("the active objective probe reports its own fields", function()
    local harness = new_harness()
    local unit = harness:add_interactee({})

    harness.settings.debug_mode = true
    harness:add_to_system("mission_objective_target_system", unit, { _objective_name = "corruptor_event" })
    harness:set_active_objective_names({ "corruptor_event" })
    harness:scan()

    assert_contains(harness:log_text(), "Active objective fields:", "the active objective probe did not run")
    assert_contains(harness:log_text(), "objective=corruptor_event", "the probe did not name the objective")
end)

-- Sockets have had their own marker kind since long before this scan, and the
-- objective pass must leave them to it rather than adding a second one.
test("luggable sockets are left to their own marker", function()
    local harness = new_harness()
    local socket = harness:add_interactee({ interaction_type = "luggable_socket" })

    harness:add_to_system("mission_objective_target_system", socket, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_equal("luggable_socket", harness:tracked_kind(socket), "a socket must keep its own kind")
end)

local failures = {}

for i = 1, #tests do
    local current = tests[i]
    local ok, failure = xpcall(current.fn, debug.traceback)

    if ok then
        io.write("PASS ", current.name, "\n")
    else
        failures[#failures + 1] = current.name .. "\n" .. tostring(failure)
        io.write("FAIL ", current.name, "\n")
    end
end

io.write("\n")

if #failures > 0 then
    for i = 1, #failures do
        io.write(failures[i], "\n\n")
    end

    io.write(tostring(#failures), " of ", tostring(#tests), " tests failed\n")
    os.exit(1)
end

io.write(tostring(#tests), " tests passed\n")
