local EXPEDITIONS_PATH = "Radar/scripts/mods/Radar/Radar_expeditions.lua"
local TRACKING_PATH = "Radar/scripts/mods/Radar/Radar_tracking.lua"

local MISSION_OBJECTIVE_SETTING_BY_KIND = {
    mission_objective_scanner = "show_mission_objective_scanner",
    mission_objective_hacking = "show_mission_objective_hacking",
    mission_objective_servo_skull = "show_mission_objective_servo_skull",
    mission_objective_other = "show_mission_objective_other",
    mission_objective_growth = "show_mission_objective_growth",
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
        show_mission_objective_servo_skull = "icon_only",
        show_mission_objective_other = "icon_only",
        show_mission_objective_growth = "icon_only",
    }
    -- A mission with no Martyr's Skull riddle data, so nothing else writes
    -- tracked units or points during these scans.
    local mission_name = "test_mission"
    local gameplay_t = 0
    -- Positioned, so anything that measures distance from the player works.
    local player_unit = { position = { x = 0, y = 0, z = 0 } }
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

    env._safe_unit_prefab_name = function(unit)
        return unit and unit.prefab or nil
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

    -- Past the window in which a just-started objective's markers may not have
    -- been assigned yet. A scan alone advances only a quarter second.
    function harness:wait_for_marker_settle()
        gameplay_t = gameplay_t + 3
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
    -- A used device really is dropped, so it gets the drop wording.
    assert_contains(harness:log_text(), "Mission objective marker dropped", "the rejection log did not run")
    assert_contains(harness:log_text(), "reason=used", "the reason is not reported")
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
    -- Red is the game asking for a player, so the game has to be asking.
    harness:set_world_marker_units({ unit })
    harness:scan()
    assert_equal("waiting", harness:tracked_minigame_state(unit), "a running puzzle must ask for a player")

    minigame._minigame._current_state = "complete"
    harness:set_world_marker_units({})
    harness:scan()
    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "a solved device must stay marked")
    assert_nil(harness:tracked_minigame_state(unit), "a solved device must fall back to the shared tint")

    -- The objective arms the same device for its second round.
    minigame._minigame._current_state = "gameplay"
    harness:set_world_marker_units({ unit })
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
    -- The game is asking for the unattended one; the other already has somebody.
    harness:set_world_marker_units({ unattended })
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
    harness:set_world_marker_units({ unit })
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
    harness:set_world_marker_units({})
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

    assert_nil(harness:tracked_kind(control), "candidates are held back until the markers settle")

    harness:wait_for_marker_settle()
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(control),
        "an uncovered objective must keep its markers once the window has passed")
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
    harness:wait_for_marker_settle()
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
    harness:wait_for_marker_settle()
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

-- Three targets a fraction of a metre around a growth's centre eye, filed with
-- `_ui_target_type` set to `demolition`. Every growth on Silo Cluster, Rise and
-- Propaganda files them, and no other objective in 21 logs does.
local function add_demolition_targets(harness, objective_name, position)
    local targets = {}

    for i = 1, 3 do
        local target = {
            name = "growth_demolition_" .. tostring(i),
            position = { x = position.x + 0.3 * i - 0.6, y = position.y + 0.2, z = position.z + 0.1 },
        }

        harness:add_to_system("mission_objective_target_system", target, {
            _objective_name = objective_name,
            _ui_target_type = "demolition",
            _add_marker_on_objective_start = false,
        })
        targets[i] = target
    end

    return targets
end

-- A growth as every mission files it: the centre eye, which carries health and
-- claims the start marker, and its demolition targets. `centre_type` covers
-- Propaganda's first growth, whose centre eye is itself filed as a demolition
-- target. Returns the centre, then the demolition targets.
local function add_growth_site(harness, objective_name, position, centre_type)
    local centre = { name = "growth_centre", position = position, health_alive = true }

    harness:add_to_system("mission_objective_target_system", centre, {
        _objective_name = objective_name,
        _ui_target_type = centre_type or "default",
        _add_marker_on_objective_start = true,
    })

    return centre, add_demolition_targets(harness, objective_name, position)
end

-- The objective name differs on every mission running the event. Only the
-- first of these was ever in the name list the icon used to depend on.
test("a growth is recognised by its demolition targets on every mission", function()
    for _, objective_name in ipairs({
        "objective_dm_stockpile_corruptor_event",
        "objective_dm_rise_demo_floor_one",
        "objective_dm_propaganda_demolition_a",
    }) do
        local harness = new_harness()
        local centre = add_growth_site(harness, objective_name, { x = 1, y = 0, z = 0 })

        harness:set_active_objective_names({ objective_name })
        harness:scan()

        assert_equal("mission_objective_growth", harness:tracked_kind(centre),
            objective_name .. ": the growth centre was not recognised")
    end
end)

-- Name-independent the other way too: Silo Cluster's objective name without the
-- demolition targets is just an objective.
test("an objective without demolition targets is not a growth, whatever it is called", function()
    local harness = new_harness()
    local step = { name = "step", position = { x = 3, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("mission_objective_target_system", step,
        { _objective_name = "objective_dm_stockpile_corruptor_event" })
    harness:set_active_objective_names({ "objective_dm_stockpile_corruptor_event" })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(step),
        "an objective was recognised as a growth by its name")
end)

-- Which objectives were recognised must be visible in a debug run, not only in
-- the icons it silently changed.
test("recognised growth objectives are named in debug mode", function()
    local harness = new_harness()

    harness.settings.debug_mode = true
    add_growth_site(harness, "objective_dm_rise_demo_floor_one", { x = 4, y = 0, z = 0 })
    harness:set_active_objective_names({ "objective_dm_rise_demo_floor_one" })
    harness:scan()

    assert_contains(harness:log_text(), "Daemonic growth objective matched:", "the match is not reported")
    assert_contains(harness:log_text(), "objective=objective_dm_rise_demo_floor_one",
        "the report does not name the objective")
end)

-- The pass that recognises a growth is the same one collecting its targets, and
-- it meets them in the table's order. A centre met before any demolition
-- target must still be a growth on that same scan. Repeated, so both orders
-- are met.
test("a growth is recognised on its first scan whichever target comes first", function()
    for attempt = 1, 40 do
        local harness = new_harness()
        local centre = add_growth_site(harness, "objective_dm_rise_demo_floor_one", { x = 1, y = 0, z = 0 })

        harness:set_active_objective_names({ "objective_dm_rise_demo_floor_one" })
        harness:scan()

        assert_equal("mission_objective_growth", harness:tracked_kind(centre),
            "attempt " .. attempt .. ": the centre was a generic objective on the scan its growth was recognised")
    end
end)

-- The game may retire the demolition targets before the centre eye they stand
-- around, and the centre must not lose its icon when they go.
test("a growth keeps its icon once its demolition targets are gone", function()
    local harness = new_harness()
    local centre, demolition = add_growth_site(harness, "objective_dm_stockpile_corruptor_event",
        { x = 1, y = 0, z = 0 })

    harness:set_active_objective_names({ "objective_dm_stockpile_corruptor_event" })
    harness:scan()

    assert_equal("mission_objective_growth", harness:tracked_kind(centre), "the growth was not recognised")

    for i = 1, #demolition do
        harness:remove_from_system("mission_objective_target_system", demolition[i])
    end

    harness:scan()

    assert_equal("mission_objective_growth", harness:tracked_kind(centre),
        "the centre lost its icon with its demolition targets")
end)

-- Remembered by objective name, which the next mission may reuse for an
-- objective that is not a growth.
test("a recognised growth is forgotten when the mission ends", function()
    local harness = new_harness()
    local centre, demolition = add_growth_site(harness, "objective_dm_stockpile_corruptor_event",
        { x = 1, y = 0, z = 0 })

    harness:set_active_objective_names({ "objective_dm_stockpile_corruptor_event" })
    harness:scan()

    assert_equal("mission_objective_growth", harness:tracked_kind(centre), "the growth was not recognised")

    harness.env._reset_mission_objective_marker_state()

    for i = 1, #demolition do
        harness:remove_from_system("mission_objective_target_system", demolition[i])
    end

    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(centre),
        "a growth recognised in one mission carried into the next")
end)

-- Silo Cluster, from a client log: the game marks the centre eye, and from the
-- moment the tentacles spawn each of the three demolition targets as well, to
-- hang its pointers at the tentacles off them. They stand under a metre from
-- the centre, so drawing them stacked four markers on one spot of the radar.
test("a growth's demolition targets do not stack markers on its centre", function()
    local harness = new_harness()
    local centre, demolition = add_growth_site(harness, "objective_dm_stockpile_corruptor_event",
        { x = 1, y = 0, z = 0 })

    harness:set_active_objective_names({ "objective_dm_stockpile_corruptor_event" })
    harness:set_world_marker_units({ centre, demolition[1], demolition[2], demolition[3] })
    harness:scan()

    assert_equal("mission_objective_growth", harness:tracked_kind(centre), "the centre eye must be shown")

    for i = 1, #demolition do
        assert_nil(harness:tracked_kind(demolition[i]),
            "demolition target " .. i .. " was drawn on top of the centre eye")
    end
end)

-- Propaganda's first growth files its centre eye as a demolition target too.
-- It claims the start marker, so it is kept on that, and the rule that drops
-- the others must not catch it.
test("a growth centre filed as a demolition target is still shown", function()
    local harness = new_harness()
    local centre, demolition = add_growth_site(harness, "objective_dm_propaganda_demolition_first",
        { x = 1, y = 0, z = 0 }, "demolition")

    harness:set_active_objective_names({ "objective_dm_propaganda_demolition_first" })
    harness:set_world_marker_units({ centre, demolition[1], demolition[2], demolition[3] })
    harness:scan()

    assert_equal("mission_objective_growth", harness:tracked_kind(centre), "the centre eye was dropped")

    for i = 1, #demolition do
        assert_nil(harness:tracked_kind(demolition[i]),
            "demolition target " .. i .. " was drawn on top of the centre eye")
    end
end)

-- Only the icon changes. An objective that is not recognised costs a distinct
-- icon and nothing else, so the marker itself is untouched.
test("an unmatched objective keeps the default icon", function()
    local harness = new_harness()
    local step = { name = "step", position = { x = 2, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("mission_objective_target_system", step, { _objective_name = "objective_dm_rise_demo_floor_one" })
    harness:set_active_objective_names({ "objective_dm_rise_demo_floor_one" })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(step),
        "an unmatched step keeps the generic objective kind")
end)

-- The growth flag is rebuilt each scan, so a step must lose the icon if its
-- objective is no longer matched -- and one unit's override must never reach
-- another unit's marker.
test("the growth icon does not leak to other markers", function()
    local harness = new_harness()
    local growth = add_growth_site(harness, "objective_dm_stockpile_corruptor_event", { x = 3, y = 0, z = 0 })
    local plain = { name = "plain", position = { x = 4, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("mission_objective_target_system", plain,
        { _objective_name = "objective_dm_stockpile_reach_elevator" })
    harness:set_active_objective_names({
        "objective_dm_stockpile_corruptor_event",
        "objective_dm_stockpile_reach_elevator",
    })
    harness:scan()

    assert_equal("mission_objective_growth", harness:tracked_kind(growth), "the growth step lost its kind")
    assert_equal("mission_objective_other", harness:tracked_kind(plain),
        "a neighbouring step must not become a growth")
end)

-- A purge event files its dormant growth eyes and the active one under one
-- objective name, all carrying health, so nothing on the unit tells them apart.
-- The game marks exactly the one that is live.
test("only the live target of a health-bearing objective is marked", function()
    local harness = new_harness()
    local active_eye = { name = "eye_active", position = { x = 1, y = 0, z = 0 }, health_alive = true }
    local dormant_a = { name = "eye_dormant_a", position = { x = 2, y = 0, z = 0 }, health_alive = true }
    local dormant_b = { name = "eye_dormant_b", position = { x = 3, y = 0, z = 0 }, health_alive = true }

    for _, unit in ipairs({ active_eye, dormant_a, dormant_b }) do
        harness:add_to_system("mission_objective_target_system", unit,
            { _objective_name = "objective_dm_stockpile_corruptor_event" })
    end

    add_demolition_targets(harness, "objective_dm_stockpile_corruptor_event", active_eye.position)

    harness:set_active_objective_names({ "objective_dm_stockpile_corruptor_event" })
    harness:set_world_marker_units({ active_eye })
    harness:scan()

    assert_equal("mission_objective_growth", harness:tracked_kind(active_eye), "the live target must be marked")
    assert_nil(harness:tracked_kind(dormant_a), "a dormant spawn location must not be marked")
    assert_nil(harness:tracked_kind(dormant_b), "a dormant spawn location must not be marked")
end)

-- An interactee is deliberately shown before the game marks it -- that is the
-- point of the feature -- so this filter must never reach one.
test("an interactable target is still shown before the game marks it", function()
    local harness = new_harness()
    local device = harness:add_interactee({ interaction_type = "decoder_device" })
    local marked = { name = "marked_target", position = { x = 5, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("mission_objective_target_system", device, { _objective_name = "objective_a" })
    harness:add_to_system("mission_objective_target_system", marked, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    -- The list covers the objective, but not the device.
    harness:set_world_marker_units({ marked })
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(device),
        "an interactable must not need a world marker")
end)

-- At the start of an event the game has not assigned its markers yet, so for a
-- moment no candidate has one -- which looks exactly like an objective the list
-- never describes. Every candidate flashed up during that window.
test("candidates do not flash up before the markers are assigned", function()
    local harness = new_harness()
    local active_eye = { name = "eye_active", position = { x = 1, y = 0, z = 0 }, health_alive = true }
    local dormant = { name = "eye_dormant", position = { x = 2, y = 0, z = 0 }, health_alive = true }

    for _, unit in ipairs({ active_eye, dormant }) do
        harness:add_to_system("mission_objective_target_system", unit,
            { _objective_name = "objective_dm_stockpile_corruptor_event" })
    end

    add_demolition_targets(harness, "objective_dm_stockpile_corruptor_event", active_eye.position)

    harness:set_active_objective_names({ "objective_dm_stockpile_corruptor_event" })
    -- The event has begun but nothing has been marked yet.
    harness:set_world_marker_units({})
    harness:scan()

    assert_nil(harness:tracked_kind(active_eye), "nothing may be shown before the markers settle")
    assert_nil(harness:tracked_kind(dormant), "nothing may be shown before the markers settle")

    -- The game assigns the marker to the live one.
    harness:set_world_marker_units({ active_eye })
    harness:scan()

    assert_equal("mission_objective_growth", harness:tracked_kind(active_eye), "the live target must appear")
    assert_nil(harness:tracked_kind(dormant), "a dormant candidate must stay hidden")
end)

-- A tentacle's three eyes die one at a time and its own target is protected
-- until they are gone, so what matters is how one unit's state changes, not
-- which shapes exist. Debug paths that ship unverified here have shipped broken
-- four times.
test("the destructible probe follows one unit through its states", function()
    local harness = new_harness()
    local eye = { name = "eye", position = { x = 2, y = 0, z = 0 }, health_alive = true }
    local far_away = { name = "crate_far", position = { x = 500, y = 0, z = 0 }, health_alive = true }
    local wall = { name = "wall", position = { x = 3, y = 0, z = 0 }, health_alive = true }

    local growth_target = { name = "growth_eye", position = { x = 1, y = 0, z = 0 }, health_alive = true }

    harness.settings.debug_mode = true
    harness:add_to_system("mission_objective_target_system", growth_target,
        { _objective_name = "objective_dm_stockpile_corruptor_event" })
    add_demolition_targets(harness, "objective_dm_stockpile_corruptor_event", growth_target.position)
    harness:set_active_objective_names({ "objective_dm_stockpile_corruptor_event" })
    harness:add_to_system("destructible_system", eye, { _is_invulnerable = true, _health = 70, _is_dead = false })
    harness:add_to_system("destructible_system", far_away, { _is_invulnerable = false, _health = 5 })
    -- The level's monster wall volumes are numerous and never a target.
    harness:add_to_system("destructible_system", wall, { _is_nav_gate = true, _health = 5 })
    harness:scan()

    local text = harness:log_text()

    assert_contains(text, "Destructible state:", "the destructible probe did not run")
    assert_contains(text, "invulnerable=true health=70", "the probe did not report the watched state")

    -- The eye becomes destructible once the tentacle's prerequisites are gone.
    -- Past the probe's own window, which a scan alone does not clear.
    harness.env._safe_unit_to_extension_map("destructible_system")[eye]._is_invulnerable = false
    harness:wait_for_marker_settle()
    harness:scan()

    assert_contains(harness:log_text(), "invulnerable=false health=70",
        "a change of state must produce a new line")
end)

-- A budget spent walking the level at large was exhausted hundreds of metres
-- from the tentacles, so the probe anchors to the live growth targets. With no
-- growth objective running it must do nothing at all.
test("the destructible probe is silent without a growth objective", function()
    local harness = new_harness()
    local eye = { name = "eye", position = { x = 2, y = 0, z = 0 }, health_alive = true }

    harness.settings.debug_mode = true
    harness:add_to_system("destructible_system", eye, { _is_invulnerable = true, _health = 70 })
    harness:scan()

    assert_equal(nil, harness:log_text():find("Destructible state:", 1, true),
        "the probe must not walk the level when no growth objective is running")
end)

test("the destructible probe ignores scenery and distant units", function()
    local harness = new_harness()
    local far_away = { name = "crate_far", position = { x = 500, y = 0, z = 0 }, health_alive = true }
    local wall = { name = "wall", position = { x = 3, y = 0, z = 0 }, health_alive = true }

    local growth_target = { name = "growth_eye", position = { x = 1, y = 0, z = 0 }, health_alive = true }

    harness.settings.debug_mode = true
    harness:add_to_system("mission_objective_target_system", growth_target,
        { _objective_name = "objective_dm_stockpile_corruptor_event" })
    add_demolition_targets(harness, "objective_dm_stockpile_corruptor_event", growth_target.position)
    harness:set_active_objective_names({ "objective_dm_stockpile_corruptor_event" })
    harness:add_to_system("destructible_system", far_away, { _is_invulnerable = false, _health = 5 })
    harness:add_to_system("destructible_system", wall, { _is_nav_gate = true, _health = 7 })
    harness:scan()

    local text = harness:log_text()

    assert_equal(nil, text:find("health=5", 1, true), "a distant breakable must not be walked")
    assert_equal(nil, text:find("health=7", 1, true), "a nav gate must not be reported")
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

-- The three eyes of a growth tentacle are one prefab. Measured off eight
-- tentacles of a single Chasm Logistratum run, their pairwise distances were
-- 0.328, 0.347 and 0.407 metres every time, to the millimetre. These offsets
-- reproduce that triangle, so the shape test is exercised against the real one
-- rather than a convenient one.
local TENTACLE_EYE_OFFSETS = {
    { x = 0.000, y = 0.000, z = 0.000 },
    { x = 0.102, y = 0.083, z = 0.321 },
    { x = 0.302, y = 0.246, z = 0.118 },
}

-- Returns the three eyes in prefab order. `centre` is where the tentacle
-- stands; the corruptor it belongs to is placed by the caller.
local function add_tentacle(harness, centre, options)
    options = options or {}

    local eyes = {}
    -- Every eye of every tentacle is this one prefab.
    local prefab = "#ID[ab4fec216e4f3c1c]"

    -- An engine that cannot name prefabs.
    if options.no_prefab then
        prefab = nil
    end

    for i = 1, #TENTACLE_EYE_OFFSETS do
        local offset = TENTACLE_EYE_OFFSETS[i]
        local eye = {
            name = (options.name or "eye") .. "_" .. tostring(i),
            prefab = prefab,
            position = { x = centre.x + offset.x, y = centre.y + offset.y, z = centre.z + offset.z },
            health_alive = true,
        }

        harness:add_to_system("destructible_system", eye, { _is_nav_gate = options.nav_gate == true })
        eyes[i] = eye
    end

    return eyes
end

-- The corruptor the event marks, with the demolition targets that make its
-- objective a growth.
local function add_growth_objective(harness, position)
    local corruptor = add_growth_site(harness, "objective_dm_stockpile_corruptor_event", position)

    harness:set_active_objective_names({ "objective_dm_stockpile_corruptor_event" })

    return corruptor
end

local function marked_eyes(harness, eyes)
    local marked = {}

    for i = 1, #eyes do
        if harness:tracked_kind(eyes[i]) ~= nil then
            marked[#marked + 1] = eyes[i]
        end
    end

    return marked
end

-- The tentacle search is anchored on the growth's own targets, so it reaches
-- every mission the growth is recognised on. Rise and Propaganda never had a
-- tentacle marked while that depended on the objective name.
test("tentacles are marked around a growth on any mission", function()
    local harness = new_harness()

    add_growth_site(harness, "objective_dm_rise_demo_floor_one", { x = 0, y = 0, z = 0 })
    harness:set_active_objective_names({ "objective_dm_rise_demo_floor_one" })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()

    assert_equal(1, #marked_eyes(harness, eyes), "the tentacle of a growth on Rise was not marked")
end)

-- Rise runs one growth after another under two objectives. When the second is
-- recognised, the targets of the first -- ended, but still remembered as a
-- growth -- must not anchor the tentacle search again.
test("an ended growth does not anchor the search when the next is recognised", function()
    local harness = new_harness()

    add_growth_site(harness, "objective_dm_rise_demo_floor_one", { x = 0, y = 0, z = 0 })
    harness:set_active_objective_names({ "objective_dm_rise_demo_floor_one" })
    harness:scan()

    add_growth_site(harness, "objective_dm_rise_demo_floor_two", { x = 300, y = 0, z = 0 })
    harness:set_active_objective_names({ "objective_dm_rise_demo_floor_two" })

    local stale = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()

    assert_equal(0, #marked_eyes(harness, stale), "the ended growth's site was searched for tentacles")
end)

-- hm_strain: a row of decorative breakables beside a growth, three different
-- prefabs within half a metre of each other, was drawn as a tentacle. They
-- stand here in the eyes' own triangle, so only the prefab can tell them apart.
test("three different prefabs are not a tentacle, even in the eyes' triangle", function()
    local harness = new_harness()
    local decoration = {}

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    for i = 1, #TENTACLE_EYE_OFFSETS do
        local offset = TENTACLE_EYE_OFFSETS[i]

        decoration[i] = harness:add_to_system("destructible_system", {
            name = "decoration_" .. tostring(i),
            prefab = "#ID[decoration_" .. tostring(i) .. "]",
            position = { x = 12 + offset.x, y = offset.y, z = offset.z },
            health_alive = true,
        }, {})
    end

    harness:scan()

    assert_equal(0, #marked_eyes(harness, decoration), "decoration of three prefabs was drawn as a tentacle")
end)

-- A tentacle can spawn with the level's own breakables inside half a metre of
-- it. It must be made of its three eyes, and the breakable must neither join it
-- nor carry its marker, whichever of them the pass happens to meet first.
test("a tentacle beside decoration is made of its own eyes only", function()
    local harness = new_harness()

    harness.settings.debug_mode = true
    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })
    local pustule = harness:add_to_system("destructible_system", {
        name = "pustule",
        prefab = "#ID[pustule]",
        position = { x = 12.1, y = 0.1, z = 0 },
        health_alive = true,
    }, {})

    harness:scan()

    assert_equal(1, #marked_eyes(harness, eyes), "the tentacle was not marked")
    assert_nil(harness:tracked_kind(pustule), "the decoration carries the tentacle's marker")
    assert_contains(harness:log_text(), "eyes=3", "the tentacle was not registered with its three eyes")

    if string.find(harness:log_text(), "eyes=4", 1, true) then
        error("the decoration was counted as one of the tentacle's eyes")
    end
end)

-- An engine that cannot name prefabs must keep the tentacles it had, rather
-- than lose every one of them to a comparison it cannot make.
test("a tentacle is still found when prefabs cannot be read", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 }, { no_prefab = true })

    harness:scan()

    assert_equal(1, #marked_eyes(harness, eyes), "without prefab names the tentacle was lost")
end)

-- The eyes move with the tentacle. One on hm_strain measured 0.328, 0.422 and
-- 0.548 metres between its eyes a second after it spawned, against 0.328, 0.347
-- and 0.407 at rest, which is why the prefab and not the triangle identifies
-- one. These are its eyes' measured positions, relative to the middle one.
test("a tentacle is found in any pose", function()
    local harness = new_harness()
    local pose = {
        { x = 0, y = 0, z = 0 },
        { x = 0.264, y = -0.299, z = 0.137 },
        { x = -0.254, y = -0.122, z = 0.168 },
    }
    local eyes = {}

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    for i = 1, #pose do
        eyes[i] = harness:add_to_system("destructible_system", {
            name = "moving_eye_" .. tostring(i),
            prefab = "#ID[ab4fec216e4f3c1c]",
            position = { x = 12 + pose[i].x, y = pose[i].y, z = pose[i].z },
            health_alive = true,
        }, {})
    end

    harness:scan()

    assert_equal(1, #marked_eyes(harness, eyes), "a tentacle out of its resting pose was not recognised")
end)

-- The world-marker set counts a prompt the same as an objective marker, and a
-- player standing next to anything gets a prompt. This probe tells them apart
-- for every objective marker on the radar.
test("the marker type probe reports what the game marks an objective with", function()
    local harness = new_harness()
    local step = harness:add_interactee({ position = { x = 30, y = 40, z = 0 } })

    harness.settings.debug_mode = true
    harness:add_to_system("mission_objective_target_system", step, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_list({ { unit = step, type = "interaction" }, { unit = step, type = "objective" } })
    harness:scan()

    local log = harness:log_text()

    assert_contains(log, "Objective marker types:", "the marker type probe did not run")
    assert_contains(log, "objective=objective_a", "the objective is not named")
    assert_contains(log, "interactee=true", "whether it is an interactable is not reported")
    -- In a fixed order, whatever order the game lists them in.
    assert_contains(log, "types=objective+interaction", "the types are not reported in a fixed order")
    assert_contains(log, "distance=50.0", "the player's distance is not reported")
end)

-- Once per unit and set of types: the moment the game starts marking a step is
-- the line that matters, and it must not be buried under one line a scan.
test("the marker type probe reports each change once, not each scan", function()
    local harness = new_harness()
    local step = harness:add_interactee({})

    harness.settings.debug_mode = true
    harness:add_to_system("mission_objective_target_system", step, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_list({})
    harness:scan()

    assert_contains(harness:log_text(), "types=none", "an unmarked objective marker is not reported")

    harness:set_world_marker_list({ { unit = step, type = "objective" } })

    for _ = 1, 3 do
        harness:wait_for_marker_settle()
        harness:scan()
    end

    local lines = 0

    for _ in string.gmatch(harness:log_text(), "Objective marker types:") do
        lines = lines + 1
    end

    assert_contains(harness:log_text(), "types=objective", "the game's marker arriving is not reported")
    assert_equal(2, lines, "the marker type probe repeats itself")
end)

test("the marker type probe is silent outside debug mode", function()
    local harness = new_harness()
    local step = harness:add_interactee({})

    harness:add_to_system("mission_objective_target_system", step, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_list({ { unit = step, type = "objective" } })
    harness:scan()

    if string.find(harness:log_text(), "Objective marker types:", 1, true) then
        error("the marker type probe logged with debug mode off")
    end
end)

-- Scavenge alone put sixty-one lockers on the radar at once.
test("the marker type probe is bounded", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    for _ = 1, 250 do
        local locker = harness:add_interactee({})

        harness:add_to_system("mission_objective_target_system", locker, { _objective_name = "objective_a" })
    end

    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_list({})
    harness:scan()

    local lines = 0

    for _ in string.gmatch(harness:log_text(), "Objective marker types:") do
        lines = lines + 1
    end

    assert_equal(true, lines > 0, "nothing was reported")
    assert_equal(true, lines <= 200, "the marker type probe is unbounded: " .. lines .. " lines")
end)

-- The eyes reach the radar through their shape alone: they are in no objective
-- system, their unit names are hashed, and the game's own marker list never
-- carries them.
test("a growth tentacle is marked once, not three times", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()

    local marked = marked_eyes(harness, eyes)

    assert_equal(1, #marked, "a tentacle must put exactly one marker on the radar")
    assert_equal("mission_objective_growth", harness:tracked_kind(marked[1]),
        "the tentacle marker must be a growth marker")
end)

-- The level's own breakables stand alone. In the run data the closest of them
-- was 9.2 m from the corruptor, nearer than any tentacle, so distance cannot be
-- the test and the shape has to be.
test("a lone breakable near a growth event is not a tentacle", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local barrel = { name = "barrel", position = { x = 9, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("destructible_system", barrel, {})
    harness:scan()

    assert_nil(harness:tracked_kind(barrel), "a solitary breakable must not be marked")
end)

-- Two is not the prefab. Without this the pass would fire on any pair of
-- breakables that happen to sit together.
test("a pair of breakables is not a tentacle", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:remove_from_system("destructible_system", eyes[3])
    harness:scan()

    assert_equal(0, #marked_eyes(harness, eyes), "two breakables must not be read as a tentacle")
end)

-- The tentacle is what the marker belongs to, not the eye carrying it. This
-- covers an eye retired by health alone; the case that actually happens in game,
-- where the eye leaves the destructible system, is below.
test("the tentacle marker outlives its first destroyed eyes", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()

    local first = marked_eyes(harness, eyes)[1]

    first.health_alive = false
    harness:scan()

    local marked = marked_eyes(harness, eyes)

    assert_equal(1, #marked, "the tentacle must keep exactly one marker")
    assert_equal(true, marked[1].health_alive, "the marker must move to a living eye")

    marked[1].health_alive = false
    harness:scan()

    assert_equal(1, #marked_eyes(harness, eyes), "the last living eye must still be marked")
end)

test("a cleared tentacle leaves no marker", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()

    for i = 1, #eyes do
        eyes[i].health_alive = false
    end

    harness:scan()

    assert_equal(0, #marked_eyes(harness, eyes), "a cleared tentacle must leave the radar")
end)

-- The shape is only looked for while the event runs, so the level's breakables
-- are never walked outside one.
test("breakables are ignored without a live growth objective", function()
    local harness = new_harness()
    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:add_to_system("mission_objective_target_system",
        { name = "step", position = { x = 0, y = 0, z = 0 } }, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:scan()

    assert_equal(0, #marked_eyes(harness, eyes), "breakables must not be marked outside a growth event")
end)

-- The event ending empties the anchor set, and the scan's own prune drops what
-- is left. This is what retires the tentacles when the corruptor dies.
test("tentacle markers are dropped when the growth event ends", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()
    assert_equal(1, #marked_eyes(harness, eyes), "the tentacle must be marked while the event runs")

    harness:set_active_objective_names({})
    harness:scan()

    assert_equal(0, #marked_eyes(harness, eyes), "the tentacle must go when the event ends")
end)

-- Monster wall volumes come in numbers and sit in the destructible system too.
test("nav gates are never read as a tentacle", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local gates = add_tentacle(harness, { x = 12, y = 0, z = 0 }, { nav_gate = true, name = "gate" })

    harness:scan()

    assert_equal(0, #marked_eyes(harness, gates), "nav gates must not be marked")
end)

-- The range test bounds the work rather than identifying anything, but a shape
-- on the far side of the level is not this event.
test("a tentacle out of range of the event is not marked", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 200, y = 0, z = 0 })

    harness:scan()

    assert_equal(0, #marked_eyes(harness, eyes), "a distant shape must not be marked")
end)

-- Each stage puts three tentacles around its corruptor. They must not be
-- collapsed into a single marker between them.
test("three tentacles of a stage each get their own marker", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local first = add_tentacle(harness, { x = 12, y = 0, z = 0 }, { name = "first" })
    local second = add_tentacle(harness, { x = -3, y = 12, z = 1 }, { name = "second" })
    local third = add_tentacle(harness, { x = 8, y = -9, z = 2 }, { name = "third" })

    harness:scan()

    assert_equal(1, #marked_eyes(harness, first), "the first tentacle must be marked once")
    assert_equal(1, #marked_eyes(harness, second), "the second tentacle must be marked once")
    assert_equal(1, #marked_eyes(harness, third), "the third tentacle must be marked once")
end)

-- Turning the setting off must stop the work, not just the marker. The claim
-- itself refuses a disabled kind, so nothing observable would change if the
-- pass ran anyway; what the guard protects is the walk of the whole
-- destructible map, once a scan, for the length of every growth event.
test("the destructible map is not walked when growth markers are off", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })
    local inner = harness.env._safe_unit_to_extension_map
    local destructible_lookups = 0

    harness.env._safe_unit_to_extension_map = function(system_name)
        if system_name == "destructible_system" then
            destructible_lookups = destructible_lookups + 1
        end

        return inner(system_name)
    end

    harness.settings.show_mission_objective_growth = "off"
    harness:scan()

    assert_equal(0, destructible_lookups, "a disabled kind must not read the destructible system")
    assert_equal(0, #marked_eyes(harness, eyes), "a disabled kind must not mark anything")

    harness.settings.show_mission_objective_growth = "icon_only"
    harness:scan()

    assert_equal(1, #marked_eyes(harness, eyes), "turning the setting back on must restore the marker")
end)

-- A run has to be readable against the destructible probe's own list, so each
-- tentacle the shape found names itself once.
test("found tentacles are named in debug mode", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })
    add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()

    assert_contains(harness:log_text(), "Growth tentacle standing:", "the tentacle is not reported")
    assert_contains(harness:log_text(), "eyes=3", "the report does not say how many eyes are standing")
end)

-- The report is scaffolding, not part of the marker, so a normal run stays
-- silent about it.
test("tentacles are not reported outside debug mode", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()

    assert_equal(1, #marked_eyes(harness, eyes), "the tentacle must still be marked")
    assert_equal(0, harness:probe_calls(), "a normal run must log nothing")
end)

test("a tentacle is reported once, not once a scan", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })
    add_tentacle(harness, { x = 12, y = 0, z = 0 })

    -- Counted by its own lines rather than by calls: the harness counts every
    -- `_log_once` call, and the filtered-hint line for the growth's demolition
    -- targets is one the real `_log_once` prints once per objective.
    local function tentacle_lines()
        local _, count = string.gsub(harness:log_text(), "Growth tentacle", "")

        return count
    end

    harness:scan()

    local first = tentacle_lines()

    assert_equal(true, first > 0, "the tentacle was not reported at all")

    harness:scan()
    harness:scan()

    assert_equal(first, tentacle_lines(), "the tentacle report repeats every scan")
end)

-- An objective the game is itself pointing at is exempt from the radar's scan
-- range. The exemption is read off the same marker list the vanilla HUD draws
-- from, so it lasts exactly as long as that marker and there is no second
-- notion of "the game is showing this" to drift out of step.
test("an objective the game is marking is exempt from the scan range", function()
    local harness = new_harness()
    local step = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", step, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({ step })
    harness:scan()

    assert_equal(true, harness.env._objective_ignores_radar_range(step),
        "a marked objective must be exempt from the scan range")
end)

test("an objective the game is not marking is not exempt", function()
    local harness = new_harness()
    local marked = harness:add_interactee()
    local unmarked = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", marked, { _objective_name = "objective_a" })
    harness:add_to_system("mission_objective_target_system", unmarked, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({ marked })
    harness:scan()

    assert_equal(false, harness.env._objective_ignores_radar_range(unmarked),
        "an unmarked objective must obey the scan range")
end)

-- The exemption ends with the marker, not with the objective.
test("the exemption ends when the game drops its marker", function()
    local harness = new_harness()
    local step = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", step, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({ step })
    harness:scan()
    assert_equal(true, harness.env._objective_ignores_radar_range(step), "the marked step must be exempt")

    harness:set_world_marker_units({})
    harness:scan()

    assert_equal(false, harness.env._objective_ignores_radar_range(step),
        "the exemption must end with the game's own marker")
end)

-- With no readable marker list there is nothing to base an exemption on, and
-- range filtering must behave exactly as it did before.
test("an unreadable marker list exempts nothing", function()
    local harness = new_harness()
    local step = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", step, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units(nil)
    harness:scan()

    assert_equal(false, harness.env._objective_ignores_radar_range(step),
        "an unreadable marker list must not exempt anything")
end)

-- A unit that was never an objective at all reads false, so nothing outside the
-- objective family can pick the exemption up by accident.
test("a unit with no objective at all is not exempt", function()
    local harness = new_harness()
    local stranger = { name = "stranger", position = { x = 0, y = 0, z = 0 } }

    harness:set_world_marker_units({})
    harness:scan()

    assert_equal(false, harness.env._objective_ignores_radar_range(stranger),
        "an unknown unit must not be exempt")
end)

-- A tentacle has no world marker of its own: the game draws its three yellow
-- pips with something that never reaches the marker list. It inherits the
-- exemption from the corruptor it belongs to, which does carry one.
test("a tentacle inherits the exemption from the growth it belongs to", function()
    local harness = new_harness()
    local corruptor = add_growth_objective(harness, { x = 0, y = 0, z = 0 })
    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:set_world_marker_units({ corruptor })
    harness:scan()

    local marked = marked_eyes(harness, eyes)

    assert_equal(1, #marked, "the tentacle must be marked")
    assert_equal(true, harness.env._objective_ignores_radar_range(marked[1]),
        "the tentacle must be exempt while the game marks its growth")

    -- Exactly the eye carrying the marker, not every destructible of the
    -- prefab: the other two are not drawn, so exempting them would be a set
    -- that says more than it means.
    for i = 1, #eyes do
        if eyes[i] ~= marked[1] then
            assert_equal(false, harness.env._objective_ignores_radar_range(eyes[i]),
                "only the eye carrying the marker is exempt")
        end
    end
end)

-- The exemption is the game's marker, not the event. A growth the HUD is not
-- pointing at leaves its tentacles under the normal scan range.
test("a tentacle of an unmarked growth obeys the scan range", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:set_world_marker_units({})
    harness:scan()

    local marked = marked_eyes(harness, eyes)

    assert_equal(1, #marked, "the tentacle must still be marked")
    assert_equal(false, harness.env._objective_ignores_radar_range(marked[1]),
        "an unmarked growth must not exempt its tentacles")
end)

-- Only the tentacles. A breakable that failed the shape test is not part of the
-- event and keeps the normal range rules.
test("a breakable that is not a tentacle is never exempt", function()
    local harness = new_harness()
    local corruptor = add_growth_objective(harness, { x = 0, y = 0, z = 0 })
    local barrel = { name = "barrel", position = { x = 9, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("destructible_system", barrel, {})
    harness:set_world_marker_units({ corruptor })
    harness:scan()

    assert_nil(harness:tracked_kind(barrel), "a solitary breakable must not be marked")
    assert_equal(false, harness.env._objective_ignores_radar_range(barrel),
        "a breakable outside the event must not be exempt")
end)

-- The exemption ends with the event, not one scan later.
test("the tentacle exemption ends with the growth event", function()
    local harness = new_harness()
    local corruptor = add_growth_objective(harness, { x = 0, y = 0, z = 0 })
    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:set_world_marker_units({ corruptor })
    harness:scan()

    local exempt = marked_eyes(harness, eyes)[1]

    assert_equal(true, harness.env._objective_ignores_radar_range(exempt), "the tentacle must be exempt")

    harness:set_active_objective_names({})
    harness:scan()

    assert_equal(false, harness.env._objective_ignores_radar_range(exempt),
        "the exemption must end with the event")
end)

-- Turning growth markers off must not leave a stale exemption behind, since the
-- pass returns before it reaches any tentacle.
test("disabling growth markers clears the tentacle exemption", function()
    local harness = new_harness()
    local corruptor = add_growth_objective(harness, { x = 0, y = 0, z = 0 })
    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:set_world_marker_units({ corruptor })
    harness:scan()

    local exempt = marked_eyes(harness, eyes)[1]

    assert_equal(true, harness.env._objective_ignores_radar_range(exempt), "the tentacle must be exempt")

    harness.settings.show_mission_objective_growth = "off"
    harness:scan()

    assert_equal(false, harness.env._objective_ignores_radar_range(exempt),
        "a disabled kind must not leave an exemption behind")
end)

-- The way the game actually retires an eye: it leaves the destructible system.
-- That is what used to end the tentacle at the first kill, because the shape
-- test then had only two units left to match and gave up on all of them.
test("a tentacle survives its eyes leaving the destructible system", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()
    assert_equal(1, #marked_eyes(harness, eyes), "three standing eyes must show one marker")

    harness:remove_from_system("destructible_system", marked_eyes(harness, eyes)[1])
    harness:scan()
    assert_equal(1, #marked_eyes(harness, eyes), "two standing eyes must still show the marker")

    harness:remove_from_system("destructible_system", marked_eyes(harness, eyes)[1])
    harness:scan()
    assert_equal(1, #marked_eyes(harness, eyes), "the last standing eye must still show the marker")

    harness:remove_from_system("destructible_system", marked_eyes(harness, eyes)[1])
    harness:scan()
    assert_equal(0, #marked_eyes(harness, eyes), "the tentacle must leave the radar with its last eye")
end)

-- Destroying an eye that is not the one carrying the marker must change nothing
-- at all.
test("destroying a tentacle's other eyes does not move its marker", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()

    local carrier = marked_eyes(harness, eyes)[1]

    -- One at a time, so that a rule picking the last standing eye rather than
    -- the first is visible: with two eyes left, those are different units.
    for i = 1, #eyes do
        if eyes[i] ~= carrier then
            harness:remove_from_system("destructible_system", eyes[i])
            harness:scan()

            local marked = marked_eyes(harness, eyes)

            assert_equal(1, #marked, "the tentacle must keep exactly one marker")
            assert_equal(carrier, marked[1], "the marker must stay on the eye already carrying it")
        end
    end
end)

-- A worn-down tentacle can no longer be matched by shape, so a fresh one at the
-- same spawn point must not be able to adopt what is left of it.
test("a new tentacle does not adopt a cleared one's last eye", function()
    local harness = new_harness()

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local old_eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 }, { name = "old" })

    harness:scan()

    -- Two of the three gone: the survivor is still standing but its tentacle can
    -- never be re-matched.
    local survivor = marked_eyes(harness, old_eyes)[1]

    for i = 1, #old_eyes do
        if old_eyes[i] ~= survivor then
            harness:remove_from_system("destructible_system", old_eyes[i])
        end
    end

    -- A replacement lands close enough that a shape match could reach across.
    local new_eyes = add_tentacle(harness, { x = 12.2, y = 0, z = 0 }, { name = "new" })

    harness:scan()

    assert_equal(1, #marked_eyes(harness, old_eyes), "the survivor must keep its own marker")
    assert_equal(1, #marked_eyes(harness, new_eyes), "the new tentacle must get its own marker")
end)

-- The remaining eye count is what a run needs in order to show the tentacle
-- being worn down rather than only that it was found.
test("a tentacle reports its remaining eyes as they are destroyed", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()
    harness:remove_from_system("destructible_system", marked_eyes(harness, eyes)[1])
    harness:scan()

    assert_contains(harness:log_text(), "eyes=3", "the full tentacle was not reported")
    assert_contains(harness:log_text(), "eyes=2", "the worn tentacle was not reported")
end)

-- The scalar dump is blind to a reference, so it reported an extension that
-- carries nothing but numbers. Whether the eyes name a shared parent is exactly
-- the question the grouping would rather be answered by, so the probe has to be
-- able to see one.
test("the destructible probe reports references, not only numbers", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    local corruptor = add_growth_objective(harness, { x = 0, y = 0, z = 0 })
    local parent = { name = "tentacle_parent" }
    local eye = { name = "eye", position = { x = 12, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("destructible_system", eye, { _broadphase_id = 7, _parent_unit = parent })
    harness:wait_for_marker_settle()
    harness:scan()

    assert_contains(harness:log_text(), "Destructible state:", "the probe did not run")
    assert_contains(harness:log_text(), "links:", "the probe reports no references at all")
    assert_contains(harness:log_text(), "_parent_unit=table", "a reference field was not named")
end)

-- Named and rendered, so the same parent seen from two eyes can be recognised
-- as the same parent rather than merely as two fields of the same name.
test("a reference is rendered, not only typed", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local shared = {}
    local first = { name = "first", position = { x = 12, y = 0, z = 0 }, health_alive = true }
    local second = { name = "second", position = { x = 12.1, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("destructible_system", first, { _parent_unit = shared })
    harness:add_to_system("destructible_system", second, { _parent_unit = shared })
    harness:wait_for_marker_settle()
    harness:scan()

    local rendered = tostring(shared)

    assert_contains(harness:log_text(), rendered,
        "the probe does not render a reference, so two eyes cannot be told to share one")
end)

-- Scan targets never appear in the game's world marker list -- confirmed from a
-- run where all three read world_marker=false while the objective was live and
-- the list was readable -- so the direct lookup can never answer for them. The
-- zone's own selection is what the vanilla HUD draws from, and it is what
-- exempts them here.
test("a selected scan target ignores the scan range", function()
    local harness = new_harness()
    local first = harness:add_interactee()
    local second = harness:add_interactee()

    harness:add_scan_zone({ objective_name = "objective_a", scannables = { first, second }, total = 2 })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({})
    harness:scan()

    assert_equal("mission_objective_scanner", harness:tracked_kind(first), "the scan target must be marked")
    assert_equal(true, harness.env._objective_ignores_radar_range(first),
        "a selected scan target must ignore the scan range")
    assert_equal(true, harness.env._objective_ignores_radar_range(second),
        "every outstanding target of the zone must ignore the scan range")
end)

-- The exemption follows the zone, so a target that has been scanned goes back
-- under the normal range rules along with its marker.
test("a scanned target stops ignoring the scan range", function()
    local harness = new_harness()
    local first = harness:add_interactee()
    local second = harness:add_interactee()

    harness:add_scan_zone({
        objective_name = "objective_a",
        scannables = { [first] = true, [second] = false },
        total = 2,
        progression = 1,
    })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({})
    harness:scan()

    assert_equal(false, harness.env._objective_ignores_radar_range(first),
        "a scanned target must obey the scan range again")
    assert_equal(true, harness.env._objective_ignores_radar_range(second),
        "the outstanding target must still ignore the scan range")
end)

-- And with the objective, not one scan later.
test("scan targets stop ignoring the range when the objective ends", function()
    local harness = new_harness()
    local target = harness:add_interactee()

    harness:add_scan_zone({ objective_name = "objective_a", scannables = { target }, total = 1 })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({})
    harness:scan()

    assert_equal(true, harness.env._objective_ignores_radar_range(target), "the target must be exempt")

    harness:set_active_objective_names({})
    harness:scan()

    assert_equal(false, harness.env._objective_ignores_radar_range(target),
        "the exemption must end with the objective")
end)

-- A scannable the zone did not select is not part of this run and keeps the
-- normal range rules, the same way it keeps no marker.
test("an unselected scannable does not ignore the scan range", function()
    local harness = new_harness()
    local selected = harness:add_interactee()
    local spare = harness:add_interactee()

    harness:add_scan_zone({ objective_name = "objective_a", scannables = { selected }, total = 1 })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({})
    harness:scan()

    assert_nil(harness:tracked_kind(spare), "an unselected scannable must not be marked")
    assert_equal(false, harness.env._objective_ignores_radar_range(spare),
        "an unselected scannable must obey the scan range")
end)

-- Silence would otherwise be ambiguous between "no tentacles here" and "this
-- machine cannot see the destructible system at all". Only the second is a
-- defect, and it is the one a non-host client run has to rule out.
test("a growth event reports what this machine can see, tentacles or not", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local barrel = { name = "barrel", position = { x = 9, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("destructible_system", barrel, { _is_server = false })
    harness:scan()

    assert_contains(harness:log_text(), "Growth tentacle scan:", "the scan reports nothing at all")
    assert_contains(harness:log_text(), "server=false destructibles=1",
        "the report does not say which side this is, or does not count what it can see")
    assert_contains(harness:log_text(), "registered=0", "the report claims a tentacle that was never matched")
end)

test("the report follows a tentacle from registration to its last eye", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    local eyes = add_tentacle(harness, { x = 12, y = 0, z = 0 })

    harness:scan()
    assert_contains(harness:log_text(), "registered=1 standing=1", "a matched tentacle is not reported")

    for i = 1, #eyes do
        harness:remove_from_system("destructible_system", eyes[i])
    end

    harness:scan()

    assert_contains(harness:log_text(), "registered=1 standing=0",
        "a cleared tentacle is not distinguishable from one that was never there")
end)

-- The candidate cap bounds the pairwise match, not the count of what is
-- visible: a machine seeing nothing must be distinguishable from one seeing a
-- great deal, however many it can match.
test("the report counts every destructible, not just the ones it matched", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_growth_objective(harness, { x = 0, y = 0, z = 0 })

    for i = 1, 80 do
        harness:add_to_system("destructible_system",
            { name = "far_" .. i, position = { x = 400 + i, y = 0, z = 0 }, health_alive = true },
            { _is_server = true })
    end

    harness:scan()

    assert_contains(harness:log_text(), "destructibles=80", "the report undercounts what this machine can see")
    assert_contains(harness:log_text(), "near=0", "distant breakables were counted as near the event")
end)

-- Power Matrix, three Data Interrogators on one objective. A repaired one does
-- not report itself repaired: its puzzle goes back to `gameplay` with nobody
-- attached, which by state alone reads exactly like a fresh breakdown. Confirmed
-- from a run where the first interrogator sat in that state for the rest of the
-- event and turned red again the moment the second one broke.
local function add_interrogator(harness, objective_name)
    local unit = harness:add_interactee({ interaction_type = "decoder_device" })
    local minigame = { _active = false, _minigame = { _current_state = "none" } }

    harness:add_to_system("decoder_device_system", unit)
    harness:add_to_system("mission_objective_target_system", unit, { _objective_name = objective_name })
    harness:add_to_system("minigame_system", unit, minigame)

    return unit, minigame
end

test("a repaired interrogator does not turn red when the next one breaks", function()
    local harness = new_harness()
    local first, first_game = add_interrogator(harness, "decrypt")
    local second, second_game = add_interrogator(harness, "decrypt")

    harness:set_active_objective_names({ "decrypt" })
    harness:scan()

    assert_nil(harness:tracked_minigame_state(first), "a healthy interrogator carries no state colour")
    assert_nil(harness:tracked_minigame_state(second), "a healthy interrogator carries no state colour")

    -- The first breaks down: the game starts asking for a player.
    first_game._minigame._current_state = "gameplay"
    harness:set_world_marker_units({ first })
    harness:scan()

    assert_equal("waiting", harness:tracked_minigame_state(first), "a broken interrogator must ask for a player")
    assert_nil(harness:tracked_minigame_state(second), "the other interrogator must be untouched")

    -- A player repairs it. Its puzzle stays in `gameplay` afterwards, which is
    -- the whole trap; what changes is that the game stops asking.
    first_game._active = true
    harness:scan()
    assert_equal("active", harness:tracked_minigame_state(first), "a puzzle being solved must report active")

    first_game._active = false
    harness:set_world_marker_units({})
    harness:scan()
    assert_nil(harness:tracked_minigame_state(first),
        "a repaired interrogator must fall back to the shared tint")

    -- The second breaks down later. The first must not follow it into red.
    second_game._minigame._current_state = "gameplay"
    harness:set_world_marker_units({ second })
    harness:scan()

    assert_equal("waiting", harness:tracked_minigame_state(second), "the newly broken one must ask for a player")
    assert_nil(harness:tracked_minigame_state(first),
        "a repaired interrogator must not inherit the next one's red state")
end)

-- The red one and the one drawn past the radar's range are the same device by
-- construction: both are "the game is asking for this one".
test("only the interrogator the game is asking for ignores the scan range", function()
    local harness = new_harness()
    local broken, broken_game = add_interrogator(harness, "decrypt")
    local repaired, repaired_game = add_interrogator(harness, "decrypt")

    -- Repaired: still in `gameplay`, nobody attached, and unmarked.
    repaired_game._minigame._current_state = "gameplay"
    broken_game._minigame._current_state = "gameplay"

    harness:set_active_objective_names({ "decrypt" })
    harness:set_world_marker_units({ broken })
    harness:scan()

    assert_equal("waiting", harness:tracked_minigame_state(broken), "the broken one must be red")
    assert_nil(harness:tracked_minigame_state(repaired), "the repaired one must not be red")
    assert_equal(true, harness.env._objective_ignores_radar_range(broken),
        "the interrogator the game is asking for must ignore the scan range")
    assert_equal(false, harness.env._objective_ignores_radar_range(repaired),
        "a repaired interrogator must obey the scan range")
end)

-- Yellow is per device and does not need the game's marker: a player being at
-- the device is a fact about that device alone, and the game drops its marker
-- while somebody is interacting.
test("a puzzle being solved stays yellow without the game's marker", function()
    local harness = new_harness()
    local unit, minigame = add_interrogator(harness, "decrypt")

    minigame._minigame._current_state = "gameplay"
    minigame._active = true

    harness:set_active_objective_names({ "decrypt" })
    harness:set_world_marker_units({})
    harness:scan()

    assert_equal("active", harness:tracked_minigame_state(unit),
        "a puzzle with a player at it must stay yellow while the marker is away")
end)

-- The colour is read at the head of the frame, so it must not be a scan behind
-- the game's own marker.
test("a breakdown is coloured on the same scan the game marks it", function()
    local harness = new_harness()
    local unit, minigame = add_interrogator(harness, "decrypt")

    harness:set_active_objective_names({ "decrypt" })
    harness:scan()

    minigame._minigame._current_state = "gameplay"
    harness:set_world_marker_units({ unit })
    harness:scan()

    assert_equal("waiting", harness:tracked_minigame_state(unit),
        "the red state lags the game's marker by a scan")
end)

-- With no readable marker list there is nothing to base red on, and a device
-- must not be coloured on a guess.
test("an unreadable marker list leaves a puzzle in the shared tint", function()
    local harness = new_harness()
    local unit, minigame = add_interrogator(harness, "decrypt")

    minigame._minigame._current_state = "gameplay"

    harness:set_active_objective_names({ "decrypt" })
    harness:set_world_marker_units(nil)
    harness:scan()

    assert_equal("mission_objective_hacking", harness:tracked_kind(unit), "the device must still be marked")
    assert_nil(harness:tracked_minigame_state(unit), "an unreadable list must not colour a device red")
end)

-- Knowing the game marks something the radar does not is only half an answer.
-- Power Matrix had an objective-marked elevator target that Radar dropped, and
-- the probe could say it was dropped but not which of six gates did it.
test("an untracked objective marker reports the gate that dropped it", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    local unit = harness:add_interactee({ active = false })

    harness:add_to_system("mission_objective_target_system", unit, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_list({ { unit = unit, type = "objective" } })
    harness:set_world_marker_units({ unit })
    harness:wait_for_marker_settle()
    harness:scan()

    local log = harness:log_text()

    assert_contains(log, "Untracked world marker:", "the untracked marker is not reported")
    assert_contains(log, "objective=objective_a", "the report does not name the objective")
    assert_contains(log, "objective_active=true", "the report does not say whether the objective is live")
    assert_contains(log, "interactee_active=false",
        "the report does not name the interactee gate that dropped it")
end)

-- A marker on a unit that is in no objective system at all has no gates to
-- report, and the probe must not invent any.
test("an untracked marker outside the objective system reports no gates", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    local stranger = { name = "stranger", position = { x = 5, y = 0, z = 0 } }

    harness:set_world_marker_list({ { unit = stranger, type = "interaction" } })
    harness:set_world_marker_units({})
    harness:wait_for_marker_settle()
    harness:scan()

    local log = harness:log_text()

    assert_contains(log, "Untracked world marker:", "the untracked marker is not reported")

    if string.find(log, "objective_active=", 1, true) then
        error("the probe reported objective gates for a unit in no objective system")
    end
end)

-- Power Matrix files the elevator's call point and the platform it takes you to
-- under one objective. Only the call point claims
-- `_add_marker_on_objective_start`, so the platform was dropped as an
-- alternative the mission had not chosen -- while the game was drawing an
-- objective marker on it and sending the player there.
test("a marked unit survives a sibling claiming the start marker", function()
    local harness = new_harness()
    local call_point = harness:add_interactee()
    local platform = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", call_point,
        { _objective_name = "objective_a", _add_marker_on_objective_start = true })
    harness:add_to_system("mission_objective_target_system", platform, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({ platform })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(platform),
        "a unit the game is marking must not be dropped as an unused alternative")
    assert_equal("mission_objective_other", harness:tracked_kind(call_point),
        "the unit claiming the start marker must still be shown")
end)

-- The filter still does its job on everything the game is not marking. Chasm
-- Logistratum files nine possible cargo containers and one real one under a
-- single objective, and only the real one claims the flag.
test("unmarked alternatives are still dropped", function()
    local harness = new_harness()
    local chosen = harness:add_interactee()
    local spare_one = harness:add_interactee()
    local spare_two = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", chosen,
        { _objective_name = "objective_a", _add_marker_on_objective_start = true })
    harness:add_to_system("mission_objective_target_system", spare_one, { _objective_name = "objective_a" })
    harness:add_to_system("mission_objective_target_system", spare_two, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({})
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(chosen), "the chosen container must be shown")
    assert_nil(harness:tracked_kind(spare_one), "an unmarked alternative must stay hidden")
    assert_nil(harness:tracked_kind(spare_two), "an unmarked alternative must stay hidden")
end)

-- The same override on the other guess: a target with nothing to act on is
-- normally a position hint, but not while the game is pointing at it.
test("a marked unit survives the actionable filter", function()
    local harness = new_harness()
    local device = harness:add_interactee()
    local hint = { name = "hint", position = { x = 40, y = 0, z = 0 } }

    harness:add_to_system("mission_objective_target_system", device, { _objective_name = "objective_a" })
    harness:add_to_system("mission_objective_target_system", hint, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({ hint })
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(hint),
        "a unit the game is marking must not be dropped as a position hint")
end)

test("unmarked position hints are still dropped", function()
    local harness = new_harness()
    local device = harness:add_interactee()
    local hint = { name = "hint", position = { x = 40, y = 0, z = 0 } }

    harness:add_to_system("mission_objective_target_system", device, { _objective_name = "objective_a" })
    harness:add_to_system("mission_objective_target_system", hint, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({})
    harness:wait_for_marker_settle()
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(device), "the real step must be shown")
    assert_nil(harness:tracked_kind(hint), "an unmarked position hint must stay hidden")
end)

-- The override reads the game's list, so with no readable list it cannot fire
-- and the filters behave exactly as they did before.
test("an unreadable marker list overrides nothing", function()
    local harness = new_harness()
    local chosen = harness:add_interactee()
    local spare = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", chosen,
        { _objective_name = "objective_a", _add_marker_on_objective_start = true })
    harness:add_to_system("mission_objective_target_system", spare, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units(nil)
    harness:scan()

    assert_equal("mission_objective_other", harness:tracked_kind(chosen), "the chosen unit must be shown")
    assert_nil(harness:tracked_kind(spare), "without a list the alternative filter must still apply")
end)

-- And it ends with the marker: the platform goes when the game stops pointing
-- at it, rather than being latched on by having once been marked.
test("the override ends when the game drops its marker", function()
    local harness = new_harness()
    local call_point = harness:add_interactee()
    local platform = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", call_point,
        { _objective_name = "objective_a", _add_marker_on_objective_start = true })
    harness:add_to_system("mission_objective_target_system", platform, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:set_world_marker_units({ platform })
    harness:scan()
    assert_equal("mission_objective_other", harness:tracked_kind(platform), "the marked platform must be shown")

    harness:set_world_marker_units({})
    harness:scan()

    assert_nil(harness:tracked_kind(platform), "the platform must go when the game stops marking it")
end)

-- A servo skull flies, and a probe key holding its position made it a new unit
-- on every scan. One of them took 59 of the marker probe's 80 line budget in a
-- single havoc mission; the probe then went silent two minutes before the next
-- objective began, so nothing about that objective was recorded at all.
test("a moving marker reports each state once, not each step", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    local unit = harness:add_interactee({ interaction_type = "servo_skull" })

    harness:add_to_system("mission_objective_target_system", unit, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:wait_for_marker_settle()
    harness:scan()

    local after_first = harness:probe_calls()

    for step = 1, 20 do
        unit.position = { x = step, y = step, z = 0 }
        harness:wait_for_marker_settle()
        harness:scan()
    end

    assert_equal(after_first, harness:probe_calls(),
        "a marker that only moved was logged again, which is what starved the probe")
end)

-- The state still has to be reported when it actually changes, or keying on the
-- unit would have traded a spam problem for a blind one.
test("a moving marker still reports a change of state", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    local unit = harness:add_interactee({ interaction_type = "decoder_device" })
    local minigame = { _active = false, _minigame = { _current_state = "none" } }

    harness:add_to_system("decoder_device_system", unit)
    harness:add_to_system("mission_objective_target_system", unit, { _objective_name = "objective_a" })
    harness:add_to_system("minigame_system", unit, minigame)
    harness:set_active_objective_names({ "objective_a" })
    harness:wait_for_marker_settle()
    harness:scan()

    local before = harness:probe_calls()

    minigame._minigame._current_state = "gameplay"
    harness:set_world_marker_units({ unit })
    harness:wait_for_marker_settle()
    harness:scan()

    assert_equal(true, harness:probe_calls() > before, "a state change went unreported")
end)

-- Two units in the same state must not collapse into one line now that position
-- is out of the key.
test("two markers in the same state are reported separately", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    local first = harness:add_interactee()
    local second = harness:add_interactee()

    harness:add_to_system("mission_objective_target_system", first, { _objective_name = "objective_a" })
    harness:add_to_system("mission_objective_target_system", second, { _objective_name = "objective_a" })
    harness:set_active_objective_names({ "objective_a" })
    harness:wait_for_marker_settle()
    harness:scan()

    local log = harness:log_text()
    local reported = 0

    for _ in string.gmatch(log, "Objective marker state:") do
        reported = reported + 1
    end

    assert_equal(2, reported, "two markers in the same state were collapsed into one report")
end)

-- `show_marker` is deliberately bypassed for objective kinds, so that reason is
-- a note about the game rather than a drop. The line used to say the opposite,
-- 425 times in one run, for a marker that was on the radar throughout.
test("a bypassed prompt is not reported as a dropped marker", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    local unit = harness:add_interactee({ interaction_type = "decoder_device", show_marker = false })

    harness:add_to_system("decoder_device_system", unit)
    harness:scan()

    local log = harness:log_text()

    assert_contains(log, "Mission objective marked before its prompt",
        "a bypassed prompt is not reported")
    assert_equal("mission_objective_hacking", harness:tracked_kind(unit),
        "and the marker is still drawn, which is what the wording has to say")

    if string.find(log, "Mission objective marker dropped", 1, true) then
        error("a bypassed prompt was reported as a dropped marker")
    end
end)

-- Unbudgeted, this probe wrote 425 lines in one run.
test("the rejection log is bounded", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    for i = 1, 60 do
        local unit = harness:add_interactee({ interaction_type = "decoder_device", show_marker = false })

        harness:add_to_system("decoder_device_system", unit)
    end

    harness:scan()

    local reported = 0

    for _ in string.gmatch(harness:log_text(), "Mission objective marked before its prompt") do
        reported = reported + 1
    end

    assert_equal(true, reported > 0, "the rejection log reported nothing at all")
    assert_equal(true, reported <= 40, "the rejection log is unbounded, it wrote " .. reported .. " lines")
end)

-- Daemonic growth runs under a different objective name on every mission, so
-- anything anchored on the name only ever saw Stockpile. What the missions
-- share is the objective's shape: a protected centre eye with three targets
-- whose `_ui_target_type` is `demolition` around it. The probe is anchored on
-- that, and only reports; it must not classify anything.
local EYE_PREFAB = "#ID[ab4fec216e4f3c1c]"

local function add_demolition_objective(harness, objective_name, options)
    options = options or {}

    local centre = { name = "centre_eye", position = { x = 0, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("mission_objective_target_system", centre, {
        _objective_name = objective_name,
        _ui_target_type = "default",
        _add_marker_on_objective_start = true,
        _is_server = options.is_server,
    })

    for i = 1, 3 do
        harness:add_to_system("mission_objective_target_system",
            { name = "demolition_" .. i, position = { x = 0.8 * i - 1.6, y = 0.6, z = 0.2 } }, {
                _objective_name = objective_name,
                _ui_target_type = "demolition",
                _add_marker_on_objective_start = false,
                _is_server = options.is_server,
            })
    end

    harness:set_active_objective_names({ objective_name })

    return centre
end

local function add_eye_triple(harness, centre, name)
    local eyes = {}

    for i = 1, #TENTACLE_EYE_OFFSETS do
        local offset = TENTACLE_EYE_OFFSETS[i]
        local eye = {
            name = name or EYE_PREFAB,
            position = { x = centre.x + offset.x, y = centre.y + offset.y, z = centre.z + offset.z },
            health_alive = true,
        }

        harness:add_to_system("destructible_system", eye, { _is_server = false })
        eyes[i] = eye
    end

    return eyes
end

-- Rise: `objective_dm_rise_demo_floor_one`, which the growth name matcher does
-- not recognise. The probe has to report it anyway.
test("the demolition probe reports an objective of any name", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_demolition_objective(harness, "objective_dm_rise_demo_floor_one")
    add_eye_triple(harness, { x = 12, y = 0, z = 0 })
    harness:scan()

    local log = harness:log_text()

    assert_contains(log, "Demolition probe:", "an objective with demolition targets is not reported")
    assert_contains(log, "objectives=objective_dm_rise_demo_floor_one:", "the objective is not named")
    assert_contains(log, "near=3", "the eyes near the objective are not counted")
    assert_contains(log, "ids=" .. EYE_PREFAB .. "x3", "the eyes' prefab is not reported")
    assert_contains(log, "Demolition destructible:", "the eyes are not reported individually")
end)

test("the demolition probe is silent without a demolition target", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    harness:add_to_system("mission_objective_target_system",
        { name = "step", position = { x = 0, y = 0, z = 0 } },
        { _objective_name = "objective_a", _ui_target_type = "default" })
    harness:set_active_objective_names({ "objective_a" })
    add_eye_triple(harness, { x = 12, y = 0, z = 0 })
    harness:scan()

    if string.find(harness:log_text(), "Demolition probe:", 1, true) then
        error("the demolition probe reported an objective without demolition targets")
    end
end)

test("the demolition probe is silent outside debug mode", function()
    local harness = new_harness()

    add_demolition_objective(harness, "objective_dm_rise_demo_floor_one")
    add_eye_triple(harness, { x = 12, y = 0, z = 0 })
    harness:scan()

    if string.find(harness:log_text(), "Demolition", 1, true) then
        error("the demolition probe logged with debug mode off")
    end
end)

-- The client question. If a non-host's destructible system is empty, the line
-- has to say so and still say it came from a client; the flag is read off the
-- objective target, which a client carries, not off a destructible it may lack.
test("the demolition probe reports a client with no destructibles as such", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_demolition_objective(harness, "objective_dm_rise_demo_floor_one", { is_server = false })
    harness:scan()

    assert_contains(harness:log_text(), "server=false objectives=",
        "the host flag is not taken from the objective target")
    assert_contains(harness:log_text(), "destructibles=0 near=0 ids=none",
        "an empty destructible system is not distinguishable from a quiet one")
end)

-- Scenery near the event must be counted under its own id, so the eyes' prefab
-- can be told apart from it by id alone.
test("the demolition probe counts each prefab separately", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_demolition_objective(harness, "objective_dm_propaganda_demolition_first")
    add_eye_triple(harness, { x = 12, y = 0, z = 0 })
    harness:add_to_system("destructible_system",
        { name = "#ID[cab8409c3a8cf5a5]", position = { x = 9, y = 0, z = 0 }, health_alive = true }, {})
    harness:scan()

    local log = harness:log_text()

    assert_contains(log, "ids=#ID[ab4fec216e4f3c1c]x3,#ID[cab8409c3a8cf5a5]x1",
        "the eyes and the scenery are not counted under their own prefab ids")
end)

-- The extension's top-level references are all level-wide systems, so a parent,
-- if the game keeps one, would be a level down.
test("the demolition probe reports references a level down", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_demolition_objective(harness, "objective_dm_rise_demo_floor_one")

    local parent = {}
    local eye = { name = EYE_PREFAB, position = { x = 12, y = 0, z = 0 }, health_alive = true }

    harness:add_to_system("destructible_system", eye,
        { _parameters = { owner_unit = parent, stages = 3 }, _destruction_info = { stage = 1 } })
    harness:scan()

    local log = harness:log_text()

    assert_contains(log, "_parameters.owner_unit=table(" .. tostring(parent) .. ")",
        "a nested reference is not reported, or not rendered")
    assert_contains(log, "_destruction_info.stage=1", "a nested scalar is not reported")
end)

test("the demolition probe ignores nav gates and distant destructibles", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_demolition_objective(harness, "objective_dm_rise_demo_floor_one")
    harness:add_to_system("destructible_system",
        { name = "gate", position = { x = 5, y = 0, z = 0 } }, { _is_nav_gate = true })
    harness:add_to_system("destructible_system",
        { name = "far", position = { x = 500, y = 0, z = 0 } }, {})
    harness:scan()

    assert_contains(harness:log_text(), "destructibles=2 near=0 ids=none",
        "a nav gate or a distant destructible was counted as near the event")
end)

-- Stockpile put 18 destructibles inside forty metres at once; a level with many
-- more must not be able to flood the log.
test("the demolition probe is bounded", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_demolition_objective(harness, "objective_dm_rise_demo_floor_one")

    for i = 1, 150 do
        harness:add_to_system("destructible_system",
            { name = "#ID[crate]", position = { x = (i % 20) - 10, y = math.floor(i / 20), z = 0 } }, {})
    end

    harness:scan()

    local reported = 0

    for _ in string.gmatch(harness:log_text(), "Demolition destructible:") do
        reported = reported + 1
    end

    assert_equal(true, reported > 0, "nothing was reported")
    assert_equal(true, reported <= 100, "the demolition probe is unbounded: " .. reported .. " lines")
    -- The summary is the line that answers the question, so running out of
    -- budget on individual destructibles must not silence it.
    assert_contains(harness:log_text(), "Demolition probe:",
        "the individual destructibles spent the summary's budget")
end)

-- Once per unit, not once per scan.
test("the demolition probe reports a destructible once", function()
    local harness = new_harness()

    harness.settings.debug_mode = true

    add_demolition_objective(harness, "objective_dm_rise_demo_floor_one")
    add_eye_triple(harness, { x = 12, y = 0, z = 0 })

    for _ = 1, 4 do
        harness:wait_for_marker_settle()
        harness:scan()
    end

    local reported = 0

    for _ in string.gmatch(harness:log_text(), "Demolition destructible:") do
        reported = reported + 1
    end

    assert_equal(3, reported, "a destructible was reported more than once")
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
