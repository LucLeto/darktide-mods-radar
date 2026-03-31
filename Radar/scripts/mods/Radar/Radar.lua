local mod = get_mod("Radar")
local Pickups = require("scripts/settings/pickup/pickups")
local PlayerUnitStatus = require("scripts/utilities/attack/player_unit_status")

local SCAN_INTERVAL = 0.25

local _marked_by_player_slot_for_unit

mod._next_scan_t = 0
mod._tracked_units = {}
mod._tracked_points = {}
mod._logged_units = {}
mod._radar_targets = {}
mod._radar_snapshot = nil
mod._gameplay_run = false
mod._last_update_t = nil
mod._last_scan_signature = nil
mod._last_block_signature = nil

local MONSTROSITY_BREEDS = {
    chaos_daemonhost = true,
    chaos_beast_of_nurgle = true,
    chaos_plague_ogryn = true,
    chaos_spawn = true,
    chaos_ogryn_houndmaster = true,
}

local CAPTAIN_BREEDS = {
    renegade_captain = true,
    cultist_captain = true,
}

local TWIN_BREEDS = {
    renegade_twin_captain = true,
    renegade_twin_captain_two = true,
}

local KIND_TO_SETTING = {
    pickup_ammo = "show_ammo_small",
    pickup_ammo_small = "show_ammo_small",
    pickup_ammo_big = "show_ammo_big",
    pickup_grenade = "show_grenades",
    pickup_medkit = "show_medkits",
    pickup_stimm = "show_stimms",
    pickup_unknown = "show_unknown_pickups",
    medicae_station = "show_medicae_station",
    luggable_socket = "show_luggable_socket",
    pickup_heretic_idol = "show_heretic_idol",
    crate_unknown = "show_crates",
    enemy_daemonhost = "show_monstrosities",
    enemy_monstrosity = "show_monstrosities",
    enemy_captain = "show_captains",
    enemy_karnak_twin = "show_karnak_twins",
    player_teammate = "show_teammates",
    material_diamantine = "show_diamantine",
    material_plasteel = "show_plasteel",
    material_expeditions_currency = "show_expeditions_currency",
    material_expeditions_loot = "show_expeditions_loot",
    material_expeditions_loot_player_drop = "show_expeditions_dropped_loot",
    expedition_loot_converter = "show_expedition_loot_converter",
    expedition_objective_opportunity = "show_expedition_objective_opportunity",
    expedition_objective_transition = "show_expedition_objective_transition",
    expedition_objective_main_objective = "show_expedition_objective_main_objective",
    expedition_objective_extraction = "show_expedition_objective_extraction",
    expedition_objective_arrival = "show_expedition_objective_arrival",
    luggable_data_reliquary = "show_data_reliquaries",
    pickup_large_ammunition_crate = "show_large_ammunition_crate",
    luggable_promethium_barrel = "show_promethium_barrel",
    pocketable_anti_rad_stimm = "show_anti_rad_stimm",
    pocketable_ammo_crate = "show_pocketable_ammo_crate",
    pocketable_breach_charge = "show_pocketable_breach_charge",
    pocketable_corrupted_auspex_scanner = "show_pocketable_corrupted_auspex_scanner",
    pocketable_expedition_loot_crate = "show_pocketable_expedition_loot_crate",
    pocketable_airstrike = "show_pocketable_airstrike",
    pocketable_artillery_strike = "show_pocketable_artillery_strike",
    pocketable_big_grenade = "show_pocketable_big_grenade",
    pocketable_grimoire = "show_pocketable_grimoire",
    pocketable_landmine_explosive = "show_pocketable_landmine_explosive",
    pocketable_landmine_fire = "show_pocketable_landmine_fire",
    pocketable_landmine_shock = "show_pocketable_landmine_shock",
    pocketable_medical_crate = "show_pocketable_medical_crate",
    pocketable_scripture = "show_pocketable_scripture",
    pocketable_syringe_ability = "show_pocketable_syringe_ability",
    pocketable_syringe_corruption = "show_pocketable_syringe_corruption",
    pocketable_syringe_power = "show_pocketable_syringe_power",
    pocketable_syringe_speed = "show_pocketable_syringe_speed",
    pocketable_valkyrie_hover = "show_pocketable_valkyrie_hover",
    pocketable_void_shield = "show_pocketable_void_shield",
    pickup_ammo_cache_deployable = "show_ammo_crate_deployable",
    medical_crate_deployable = "show_medical_crate_deployable",
}

local EXPEDITION_MARKER_KINDS = {
    expedition_loot_converter = true,
    expedition_objective_opportunity = true,
    expedition_objective_transition = true,
    expedition_objective_main_objective = true,
    expedition_objective_extraction = true,
    expedition_objective_arrival = true,
}

local EXPEDITION_OBJECTIVE_ICON_DEFAULTS = {
    expedition_loot_converter = "content/ui/materials/hud/interactions/icons/expeditions",
    expedition_objective_transition = "content/ui/materials/backgrounds/scanner/scanner_map_exit",
    expedition_objective_main_objective = "content/ui/materials/hud/interactions/icons/objective_main",
    expedition_objective_extraction = "content/ui/materials/backgrounds/scanner/scanner_map_extract",
    expedition_objective_arrival = "content/ui/materials/icons/mission_types/mission_type_05",
}

local ARTWORK_MODE_KIND_TO_SETTING = {
    crate_unknown = "show_crates",
    material_diamantine = "show_diamantine",
    material_plasteel = "show_plasteel",
    material_expeditions_currency = "show_expeditions_currency",
    material_expeditions_loot = "show_expeditions_loot",
    material_expeditions_loot_player_drop = "show_expeditions_dropped_loot",
    pocketable_airstrike = "show_pocketable_airstrike",
    pocketable_artillery_strike = "show_pocketable_artillery_strike",
    pocketable_big_grenade = "show_pocketable_big_grenade",
    pocketable_valkyrie_hover = "show_pocketable_valkyrie_hover",
    pocketable_landmine_explosive = "show_pocketable_landmine_explosive",
    pocketable_landmine_fire = "show_pocketable_landmine_fire",
    pocketable_landmine_shock = "show_pocketable_landmine_shock",
    pocketable_void_shield = "show_pocketable_void_shield",
}

local ARTWORK_MODE_SETTING_IDS = {
    "show_crates",
    "show_diamantine",
    "show_plasteel",
    "show_expeditions_currency",
    "show_expeditions_loot",
    "show_expeditions_dropped_loot",
    "show_pocketable_airstrike",
    "show_pocketable_artillery_strike",
    "show_pocketable_big_grenade",
    "show_pocketable_valkyrie_hover",
    "show_pocketable_landmine_explosive",
    "show_pocketable_landmine_fire",
    "show_pocketable_landmine_shock",
    "show_pocketable_void_shield",
}

local function _normalize_marker_display_mode(value)
    if value == false or value == "off" then
        return "off"
    end

    if value == "icon" then
        return "icon"
    end

    return "artwork"
end

function mod:get_marker_display_mode(kind)
    local setting_id = ARTWORK_MODE_KIND_TO_SETTING[kind]
    if not setting_id then
        return nil
    end

    return _normalize_marker_display_mode(mod:get(setting_id))
end

local function _migrate_marker_display_mode_settings()
    for _, setting_id in ipairs(ARTWORK_MODE_SETTING_IDS) do
        local value = mod:get(setting_id)

        if value == true then
            mod:set(setting_id, "artwork")
        elseif value == false then
            mod:set(setting_id, "off")
        end
    end
end

function mod.on_all_mods_loaded()
    _migrate_marker_display_mode_settings()

    -- Preload icon packages
    local function load_package(package_name)
        local ok, err = pcall(function()
            if not Managers or not Managers.package then
                error("Managers.package unavailable")
            end

            if not Managers.package:has_loaded(package_name) then
                Managers.package:load(package_name, "Radar", nil, true)
                if mod:get("debug_mode") then
                    mod:echo(string.format("[Radar] package load requested | %s", tostring(package_name)))
                end
            else
                if mod:get("debug_mode") then
                    mod:echo(string.format("[Radar] package already loaded | %s", tostring(package_name)))
                end
            end
        end)

        if not ok then
            if mod:get("debug_mode") then
                mod:echo(string.format("[Radar] package load failed | %s | %s", tostring(package_name), tostring(err)))
            end
        end
    end

    load_package("packages/ui/views/inventory_view/inventory_view")
    load_package("packages/ui/views/inventory_weapons_view/inventory_weapons_view")
    load_package("packages/ui/hud/player_weapon/player_weapon")
    load_package("packages/ui/views/inventory_background_view/inventory_background_view")
    load_package("packages/ui/views/inventory_weapon_details_view/inventory_weapon_details_view")
    load_package("packages/ui/views/inventory_weapon_marks_view/inventory_weapon_marks_view")
    load_package("packages/ui/views/main_menu_view/main_menu_view")
    load_package("packages/ui/views/player_character_options_view/player_character_options_view")
    load_package("packages/ui/views/talent_builder_view/talent_builder_view")
    load_package("packages/ui/views/live_events_view/live_events_view")
    load_package("packages/ui/views/group_finder_view/group_finder_view")
    load_package("packages/ui/views/mission_board_view/mission_board_view")
    load_package("packages/ui/views/scanner_display_view/scanner_display_view")
    load_package("packages/ui/material_sets/circumstances")

    if mod:get("debug_mode") then
        mod:echo("Packages loaded")
    end
end

local function _safe_gameplay_time()
    local time_manager = Managers and Managers.time
    if not time_manager then
        return nil
    end

    local timers = time_manager._timers
    if not timers or not timers.gameplay then
        return nil
    end

    return time_manager:time("gameplay")
end

local function _safe_unit_alive(unit)
    return unit and ALIVE and ALIVE[unit]
end

local function _safe_unit_name(unit)
    if not _safe_unit_alive(unit) then
        return "<dead>"
    end

    local ok, result = pcall(Unit.debug_name, unit, false)
    if ok and result then
        return tostring(result)
    end

    return tostring(unit)
end

local function _is_finite_number(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function _vector3_components(vec)
    if not vec then
        return nil, nil, nil
    end

    if type(vec) == "table" then
        return vec.x, vec.y, vec.z
    end

    local ok_x, x = pcall(function()
        return Vector3.x(vec)
    end)
    local ok_y, y = pcall(function()
        return Vector3.y(vec)
    end)
    local ok_z, z = pcall(function()
        return Vector3.z(vec)
    end)

    if ok_x and ok_y and ok_z then
        return x, y, z
    end

    return nil, nil, nil
end

local function _copy_vector3(vec)
    local x, y, z = _vector3_components(vec)

    if not _is_finite_number(x) or not _is_finite_number(y) or not _is_finite_number(z) then
        return nil
    end

    return { x = x, y = y, z = z }
end

local function _safe_lower_string(value)
    if value == nil then
        return nil
    end

    return string.lower(tostring(value))
end

local function _string_starts_with(value, prefix)
    if value == nil or prefix == nil then
        return false
    end

    return string.sub(value, 1, string.len(prefix)) == prefix
end

local function _safe_unit_data_string(unit, field_name)
    if not unit or not field_name or not Unit or not Unit.has_data or not Unit.get_data then
        return nil
    end

    local ok_has_data, has_data = pcall(Unit.has_data, unit, field_name)
    if not ok_has_data or not has_data then
        return nil
    end

    local ok_value, value = pcall(Unit.get_data, unit, field_name)
    if ok_value and value ~= nil then
        return _safe_lower_string(value)
    end

    return nil
end

local function _safe_unit_pickup_name(unit)
    return _safe_unit_data_string(unit, "pickup_type")
end

local function _safe_unit_deployable_type(unit)
    return _safe_unit_data_string(unit, "deployable_type")
end

local function _safe_unit_smart_tag_target_type(unit)
    return _safe_unit_data_string(unit, "smart_tag_target_type")
end

local function _safe_unit_collectible_type(unit)
    return _safe_unit_data_string(unit, "collectible_type")
end

local function _table_size(t)
    local n = 0
    for _, _ in pairs(t) do
        n = n + 1
    end
    return n
end

local DEFAULT_RADAR_POS_X = 40
local DEFAULT_RADAR_POS_Y = 220
local DEFAULT_RADAR_MOVE_STEP = 10

local function _clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end

    if value > max_value then
        return max_value
    end

    return value
end

local function _get_ui_space_size()
    local width = 1920
    local height = 1080

    if RESOLUTION_LOOKUP and RESOLUTION_LOOKUP.width and RESOLUTION_LOOKUP.height then
        local inverse_scale = RESOLUTION_LOOKUP.inverse_scale or 1

        width = RESOLUTION_LOOKUP.width * inverse_scale
        height = RESOLUTION_LOOKUP.height * inverse_scale
    end

    return width, height
end

local function _log_once(key, text)
    if mod:get("debug_mode") ~= true then
        return
    end

    if mod._logged_units[key] then
        return
    end

    mod._logged_units[key] = true
    mod:echo(text)
end

local function _position_lookup(unit)
    if not unit or not POSITION_LOOKUP then
        return nil
    end

    return _copy_vector3(POSITION_LOOKUP[unit])
end

local function _safe_unit_position(unit)
    if not _safe_unit_alive(unit) then
        return nil
    end

    local position = _position_lookup(unit)
    if position then
        return position
    end

    local ok, world_position = pcall(Unit.world_position, unit, 1)
    if ok and world_position then
        return _copy_vector3(world_position)
    end

    return nil
end

local function _is_enemy_kind(kind)
    return kind ~= nil and _string_starts_with(kind, "enemy_")
end

local function _safe_health_alive(unit)
    if not unit or not ScriptUnit or not ScriptUnit.has_extension then
        return nil
    end

    local health_extension = ScriptUnit.has_extension(unit, "health_system")
    if not health_extension or not health_extension.is_alive then
        return nil
    end

    local ok_alive, is_alive = pcall(function()
        return health_extension:is_alive()
    end)

    if ok_alive then
        return is_alive
    end

    return nil
end

local function _is_owned_by_death_manager(unit)
    if not unit or not ScriptUnit or not ScriptUnit.has_extension then
        return false
    end

    local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
    if not unit_data_extension or not unit_data_extension.is_owned_by_death_manager then
        return false
    end

    local ok_owned, owned = pcall(function()
        return unit_data_extension:is_owned_by_death_manager()
    end)

    return ok_owned and owned or false
end

local function _is_trackable_unit_alive(unit, kind)
    if not _safe_unit_alive(unit) then
        return false
    end

    if _is_enemy_kind(kind) then
        if _is_owned_by_death_manager(unit) then
            return false
        end

        local health_alive = _safe_health_alive(unit)
        if health_alive == false then
            return false
        end
    end

    if kind == "pickup_heretic_idol" then
        local health_alive = _safe_health_alive(unit)
        if health_alive == false then
            return false
        end
    end

    return true
end

local function _safe_world_rotation(unit, node)
    if not _safe_unit_alive(unit) then
        return nil
    end

    local ok, rotation = pcall(Unit.world_rotation, unit, node or 1)
    if ok then
        return rotation
    end

    return nil
end

local function _safe_flat_direction_xy(vector_getter, rotation)
    if not rotation or not vector_getter then
        return nil, nil
    end

    local ok, direction = pcall(vector_getter, rotation)
    if not ok or not direction then
        return nil, nil
    end

    local x, y = _vector3_components(direction)
    if not _is_finite_number(x) or not _is_finite_number(y) then
        return nil, nil
    end

    local length = math.sqrt(x * x + y * y)
    if length <= 0 then
        return nil, nil
    end

    return x / length, y / length
end

local function _safe_forward_xy(rotation)
    return _safe_flat_direction_xy(Quaternion.forward, rotation)
end

local function _safe_right_xy(rotation)
    return _safe_flat_direction_xy(Quaternion.right, rotation)
end

local function _safe_mission_name()
    local state_gameplay = mod._last_state_gameplay
    if state_gameplay then
        local shared_state = state_gameplay._shared_state
        local mission_name = shared_state and shared_state.mission_name
        if mission_name ~= nil then
            return mission_name
        end
    end

    local game_mode_manager = Managers and Managers.state and Managers.state.game_mode
    if game_mode_manager and game_mode_manager.mission_name then
        local ok, mission_name = pcall(function()
            return game_mode_manager:mission_name()
        end)

        if ok and mission_name ~= nil then
            return mission_name
        end
    end

    local state_manager = Managers and Managers.state
    local candidates = {
        function()
            local gameplay = state_manager and state_manager.gameplay
            local shared_state = gameplay and gameplay._shared_state
            return shared_state and shared_state.mission_name
        end,
        function()
            local package_synchronizer_client = Managers and Managers.package_synchronizer_client
            return package_synchronizer_client and package_synchronizer_client._mission_name
        end,
        function()
            local mechanism = Managers and Managers.mechanism and Managers.mechanism._mechanism
            return mechanism and mechanism._mission_name
        end,
    }

    for _, getter in ipairs(candidates) do
        local ok, mission_name = pcall(getter)
        if ok and mission_name ~= nil then
            return mission_name
        end
    end

    return nil
end

local function _safe_presence_activity()
    local presence_manager = Managers and Managers.presence
    if not presence_manager then
        return nil
    end

    local candidates = {
        function()
            if presence_manager.activity then
                return presence_manager:activity()
            end
        end,
        function()
            if presence_manager.current_activity then
                return presence_manager:current_activity()
            end
        end,
        function()
            return presence_manager._current_activity
        end,
        function()
            return presence_manager._activity
        end,
        function()
            return presence_manager._presence_name
        end,
    }

    for _, getter in ipairs(candidates) do
        local ok, value = pcall(getter)
        if ok and value ~= nil then
            return tostring(value)
        end
    end

    return nil
end

local function _safe_mechanism_name()
    local mechanism_manager = Managers and Managers.mechanism
    if not mechanism_manager then
        return nil
    end

    local candidates = {
        function()
            if mechanism_manager.current_mechanism_name then
                return mechanism_manager:current_mechanism_name()
            end
        end,
        function()
            if mechanism_manager.mechanism_name then
                return mechanism_manager:mechanism_name()
            end
        end,
        function()
            return mechanism_manager._mechanism_name
        end,
        function()
            local mechanism = mechanism_manager._mechanism
            if type(mechanism) == "table" then
                return mechanism.name or mechanism._name
            end
            return mechanism
        end,
    }

    for _, getter in ipairs(candidates) do
        local ok, value = pcall(getter)
        if ok and value ~= nil then
            return tostring(value)
        end
    end

    return nil
end

local function _is_hub_runtime()
    local mission_name = _safe_mission_name()
    local activity = _safe_presence_activity()
    local mechanism_name = _safe_mechanism_name()

    return mission_name == "hub_ship"
        or activity == "hub"
        or activity == "main_menu"
        or activity == "title_screen"
        or mechanism_name == "hub"
end

local function _player_manager()
    return Managers and Managers.player
end

local function _local_player()
    local player_manager = _player_manager()
    if not player_manager then
        return nil
    end

    local num_players = tonumber(player_manager._num_players) or 0
    if num_players <= 0 then
        return nil
    end

    local getter = player_manager.local_player_safe or player_manager.local_player
    if not getter then
        return nil
    end

    local ok, player = pcall(function()
        return getter(player_manager, 1)
    end)

    if ok then
        return player
    end

    return nil
end

local function _player_unit()
    local local_player = _local_player()
    return local_player and local_player.player_unit
end

local function _is_local_player_alive()
    return _safe_unit_alive(_player_unit())
end

local function _is_local_player_captured()
    local player_unit = _player_unit()
    if not _safe_unit_alive(player_unit) or not PlayerUnitStatus or not PlayerUnitStatus.is_hogtied then
        return false
    end

    local ok, captured = pcall(function()
        return PlayerUnitStatus.is_hogtied(player_unit)
    end)

    return ok and captured == true or false
end

local function _safe_camera_rotation()
    local local_player = _local_player()
    if not local_player then
        return nil
    end

    local viewport_name = local_player.viewport_name
    if not viewport_name then
        return nil
    end

    local camera_manager = Managers and Managers.state and Managers.state.camera
    if not camera_manager then
        return nil
    end

    if camera_manager.has_camera then
        local ok_has_camera, has_camera = pcall(function()
            return camera_manager:has_camera(viewport_name)
        end)

        if ok_has_camera and not has_camera then
            return nil
        end
    end

    if not camera_manager.camera_rotation then
        return nil
    end

    local ok_rotation, rotation = pcall(function()
        return camera_manager:camera_rotation(viewport_name)
    end)

    if ok_rotation and rotation then
        return rotation
    end

    return nil
end

local function _safe_player_rotation(player_unit)
    local camera_rotation = _safe_camera_rotation()
    if camera_rotation then
        return camera_rotation
    end

    if not _safe_unit_alive(player_unit) then
        return nil
    end

    local unit_data_extension = ScriptUnit and ScriptUnit.has_extension and
        ScriptUnit.has_extension(player_unit, "unit_data_system")
    if unit_data_extension and unit_data_extension.read_component then
        local ok_component, first_person_component = pcall(function()
            return unit_data_extension:read_component("first_person")
        end)

        if ok_component and first_person_component and first_person_component.rotation then
            return first_person_component.rotation
        end
    end

    local first_person_extension = ScriptUnit and ScriptUnit.has_extension and
        ScriptUnit.has_extension(player_unit, "first_person_system")
    if first_person_extension and first_person_extension.extrapolated_rotation then
        local ok_rotation, rotation = pcall(function()
            return first_person_extension:extrapolated_rotation()
        end)

        if ok_rotation and rotation then
            return rotation
        end
    end

    return _safe_world_rotation(player_unit, 1)
end

local function _safe_extension_system(system_name)
    local extension_manager = Managers and Managers.state and Managers.state.extension
    if not extension_manager or not extension_manager.system then
        return nil
    end

    local ok, system = pcall(function()
        return extension_manager:system(system_name)
    end)

    if ok then
        return system
    end

    return nil
end

local function _safe_unit_to_extension_map(system_name)
    local system = _safe_extension_system(system_name)
    if not system or not system.unit_to_extension_map then
        return nil
    end

    local ok, map = pcall(function()
        return system:unit_to_extension_map()
    end)

    if ok and type(map) == "table" then
        return map
    end

    return nil
end

local function _safe_game_mode_manager()
    return Managers and Managers.state and Managers.state.game_mode or nil
end

local function _safe_game_mode()
    local game_mode_manager = _safe_game_mode_manager()
    if not game_mode_manager or not game_mode_manager.game_mode then
        return nil
    end

    local ok, game_mode = pcall(function()
        return game_mode_manager:game_mode()
    end)

    if ok then
        return game_mode
    end

    return nil
end

local function _safe_game_mode_name()
    local game_mode_manager = _safe_game_mode_manager()
    if not game_mode_manager or not game_mode_manager.game_mode_name then
        return nil
    end

    local ok, game_mode_name = pcall(function()
        return game_mode_manager:game_mode_name()
    end)

    if ok then
        return game_mode_name
    end

    return nil
end

local function _is_expedition_runtime()
    return _safe_game_mode_name() == "expedition"
end

local function _is_in_expedition_safe_zone()
    if not _is_expedition_runtime() then
        return false
    end

    local game_mode = _safe_game_mode()
    if not game_mode or not game_mode.in_safe_zone then
        return false
    end

    local ok, in_safe_zone = pcall(function()
        return game_mode:in_safe_zone()
    end)

    return ok and in_safe_zone == true or false
end

local function _safe_vector3_unbox(value)
    if not value then
        return nil
    end

    if type(value) == "table" and value.x ~= nil and value.y ~= nil and value.z ~= nil then
        return _copy_vector3(value)
    end

    if value.unbox then
        local ok, vector = pcall(function()
            return value:unbox()
        end)

        if ok and vector then
            return _copy_vector3(vector)
        end
    end

    return _copy_vector3(value)
end

local function _safe_expedition_level_index(level)
    if not level or not Managers or not Managers.state or not Managers.state.unit_spawner then
        return nil
    end

    local unit_spawner = Managers.state.unit_spawner
    if not unit_spawner.index_by_level then
        return nil
    end

    local ok, level_index = pcall(function()
        return unit_spawner:index_by_level(level)
    end)

    if ok then
        return level_index
    end

    return nil
end

local function _safe_expedition_level_by_index(level_index, sub_level_index)
    if level_index == nil or not Managers or not Managers.state or not Managers.state.unit_spawner then
        return nil
    end

    local unit_spawner = Managers.state.unit_spawner
    if not unit_spawner.level_by_index then
        return nil
    end

    local ok, level = pcall(function()
        return unit_spawner:level_by_index(level_index, sub_level_index)
    end)

    if ok then
        return level
    end

    return nil
end

local function _safe_expedition_level_data_by_index(game_mode, level_index, sub_level_index)
    if not game_mode or not game_mode.get_level_data then
        return nil
    end

    local level = _safe_expedition_level_by_index(level_index, sub_level_index)
    if not level then
        return nil
    end

    local ok, level_data = pcall(function()
        return game_mode:get_level_data(level)
    end)

    if ok then
        return level_data
    end

    return nil
end

local function _safe_expedition_section_index_by_level_index(game_mode, level_index, sub_level_index)
    local level_data = _safe_expedition_level_data_by_index(game_mode, level_index, sub_level_index)
    local section = level_data and level_data.section or nil

    return section and section.index or nil
end

local function _safe_current_safe_zone_section_index(game_mode)
    local logic = game_mode and game_mode._game_mode_logic or nil
    local index = logic and logic._current_safe_zone_section_index or nil

    return tonumber(index) or index
end

local function _safe_expedition_active_section_index(game_mode)
    if not game_mode then
        return nil
    end

    local in_safe_zone = false
    if game_mode.in_safe_zone then
        local ok, value = pcall(function()
            return game_mode:in_safe_zone()
        end)
        if ok then
            in_safe_zone = value == true
        end
    end

    if in_safe_zone then
        local safe_zone_section_index = _safe_current_safe_zone_section_index(game_mode)
        if safe_zone_section_index ~= nil then
            return safe_zone_section_index
        end
    end

    if game_mode.current_location_index then
        local ok, value = pcall(function()
            return game_mode:current_location_index()
        end)
        if ok then
            return value
        end
    end

    return nil
end

local function _is_expedition_level_in_active_section(game_mode, active_section_index, level_index, sub_level_index)
    if active_section_index == nil or level_index == nil then
        return true
    end

    local section_index = _safe_expedition_section_index_by_level_index(game_mode, level_index, sub_level_index)
    if section_index == nil then
        return true
    end

    return section_index == active_section_index
end

local function _expedition_opportunity_icon(level_index)
    local numeric_index = tonumber(level_index) or 0
    local icon_index = 1 + numeric_index % 24

    return string.format("content/ui/materials/backgrounds/scanner/scanner_map_greek_%02d", icon_index)
end

local function _expedition_opportunity_title_icon(location_id)
    local numeric_id = tonumber(location_id) or 0
    return string.format("content/ui/materials/backgrounds/scanner/scanner_map_%d", numeric_id % 9)
end

local function _get_runtime_state()
    local gameplay_t = _safe_gameplay_time()
    local mission_name = _safe_mission_name()
    local activity = _safe_presence_activity()
    local mechanism_name = _safe_mechanism_name()
    local player_unit = _player_unit()
    local player_pos = _safe_unit_position(player_unit)

    if activity == "loading" then
        return false, "loading", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if mechanism_name == "left_session" or mechanism_name == "hub" then
        return false, "hub_mechanism", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if not mission_name then
        return false, "no_mission", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if mission_name == "hub_ship" then
        return false, "hub_mission", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if mechanism_name == "onboarding" and mission_name ~= "tg_shooting_range" then
        return false, "onboarding_non_psykhanium", gameplay_t, mission_name, activity, mechanism_name, player_unit,
            player_pos
    end

    if _is_hub_runtime() then
        return false, "hub_runtime", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if not _is_local_player_alive() then
        return false, "player_not_alive", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if _is_local_player_captured() then
        return false, "player_captured", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if not player_pos then
        return false, "no_player_position", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    return true, "ok", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
end

local function _is_allowed_runtime()
    local allowed = _get_runtime_state()
    return allowed
end

local function _is_expedition_marker_kind(kind)
    return EXPEDITION_MARKER_KINDS[kind] == true
end

local function _ignore_radar_range_for_kind(kind)
    if kind == "expedition_loot_converter" then
        return false
    end

    return _is_expedition_marker_kind(kind) and mod:get("ignore_radar_range_for_expedition_markers") == true
end

local function _kind_enabled(kind)
    local display_mode = mod:get_marker_display_mode(kind)
    if display_mode ~= nil then
        return display_mode ~= "off"
    end

    local setting_id = KIND_TO_SETTING[kind]
    if not setting_id then
        return true
    end

    return mod:get(setting_id) ~= false
end

local function _pickup_meta(pickup_name, pickup_data, interaction_type, ui_interaction_type, interaction_icon,
                            description, unit_name, marked_by_player_slot)
    return {
        pickup_name = pickup_name,
        pickup_group = pickup_data and pickup_data.group or nil,
        interaction_type = interaction_type,
        ui_interaction_type = ui_interaction_type,
        interaction_icon = interaction_icon,
        description = description,
        unit_name = unit_name,
        marked_by_player_slot = marked_by_player_slot,
    }
end

local function _classify_pickup_like(interaction_type, ui_interaction_type, icon, description, unit_name, pickup_name,
                                     pickup_data, marked_by_player_slot)
    local meta = _pickup_meta(pickup_name, pickup_data, interaction_type, ui_interaction_type, icon, description,
        unit_name,
        marked_by_player_slot)

    -- default items
    if interaction_type == "chest" then
        return "crate_unknown", meta
    end

    if interaction_type == "expedition_loot_converter" or (ui_interaction_type == "point_of_interest" and pickup_name == "expedition_loot_converter") then
        meta.objective_icon = EXPEDITION_OBJECTIVE_ICON_DEFAULTS.expedition_loot_converter
        return "expedition_loot_converter", meta
    end

    if interaction_type == "health_station" or pickup_name == "health_station" then
        return "medicae_station", meta
    end

    if (interaction_type == "health" or pickup_name == "health")
        and pickup_name ~= "medical_crate_deployable"
        and icon == "content/ui/materials/hud/interactions/icons/respawn" then
        return "medicae_station", meta
    end

    if interaction_type == "luggable_socket" or pickup_name == "luggable_socket" then
        return "luggable_socket", meta
    end

    if pickup_name == "small_clip" then
        return "pickup_ammo_small", meta
    end

    if pickup_name == "large_clip" then
        return "pickup_ammo_big", meta
    end

    if pickup_name == "small_grenade" then
        return "pickup_grenade", meta
    end

    if pickup_name == "small_metal" or pickup_name == "large_metal" then
        return "material_plasteel", meta
    end

    if pickup_name == "small_platinum" or pickup_name == "large_platinum" then
        return "material_diamantine", meta
    end

    if pickup_name == "ammo_cache_pocketable" then
        return "pocketable_ammo_crate", meta
    end

    if pickup_name == "medical_crate_pocketable" then
        return "pocketable_medical_crate", meta
    end

    if pickup_name == "syringe_ability_boost_pocketable" then
        return "pocketable_syringe_ability", meta
    end

    if pickup_name == "syringe_corruption_pocketable" then
        return "pocketable_syringe_corruption", meta
    end

    if pickup_name == "syringe_power_boost_pocketable" then
        return "pocketable_syringe_power", meta
    end

    if pickup_name == "syringe_speed_boost_pocketable" then
        return "pocketable_syringe_speed", meta
    end

    -- primary objective items
    if pickup_name == "battery_01_luggable" then
        return "luggable_power_cell_teal", meta
    end

    if pickup_name == "control_rod_01_luggable" then
        return "luggable_cryonic_rod", meta
    end

    if pickup_name == "container_01_luggable" then
        return "luggable_moebian_pox_zetaphyte_13_sample", meta
    end

    if pickup_name == "container_02_luggable" then
        return "luggable_vacuum_capsule", meta
    end

    if pickup_name == "container_03_luggable" then
        return "luggable_special_issue_ammo", meta
    end

    if pickup_name == "prismata_case_01_luggable" then
        return "luggable_prismata_crystal_repository", meta
    end

    if pickup_name == "hordes_mcguffin" then
        return "pickup_mortis_relic", meta
    end

    if pickup_name == "paper_pickup" or pickup_name == "paper_pickup_02" or pickup_name == "paper_pickup_03" or pickup_name == "paper_pickup_04" then
        return "pickup_coordinates_paper", meta
    end

    -- secondary objective items
    if pickup_name == "grimoire" then
        return "pocketable_grimoire", meta
    end

    if pickup_name == "tome" then
        return "pocketable_scripture", meta
    end

    -- expeditions specific items
    if pickup_name and _string_starts_with(pickup_name, "expedition_currency_") then
        return "material_expeditions_currency", meta
    end

    if pickup_name and _string_starts_with(pickup_name, "expedition_loot_small_") then
        return "material_expeditions_loot", meta
    end

    if pickup_name == "expedition_loot_player_drop" then
        return "material_expeditions_loot_player_drop", meta
    end

    if pickup_name == "large_ammunition_crate" then
        return "pickup_large_ammunition_crate", meta
    end

    if pickup_name == "expedition_deployable_force_field_pocketable" then
        return "pocketable_void_shield", meta
    end

    if pickup_name == "expedition_grenade_airstrike_pocketable" then
        return "pocketable_airstrike", meta
    end

    if pickup_name == "expedition_grenade_artillery_strike_pocketable" then
        return "pocketable_artillery_strike", meta
    end

    if pickup_name == "expedition_grenade_big_pocketable" then
        return "pocketable_big_grenade", meta
    end

    if pickup_name == "expedition_grenade_valkyrie_hover_pocketable" then
        return "pocketable_valkyrie_hover", meta
    end

    if pickup_name == "motion_detection_mine_explosive_pocketable" then
        return "pocketable_landmine_explosive", meta
    end

    if pickup_name == "motion_detection_mine_fire_pocketable" then
        return "pocketable_landmine_fire", meta
    end

    if pickup_name == "motion_detection_mine_shock_pocketable" then
        return "pocketable_landmine_shock", meta
    end

    if pickup_name == "expedition_loot_heavy_tier_1" or pickup_name == "expedition_loot_heavy_tier_2" or pickup_name == "expedition_loot_heavy_tier_3" then
        return "luggable_data_reliquary", meta
    end

    if pickup_name == "expedition_explosive_luggable_01" then
        return "luggable_promethium_barrel", meta
    end

    if pickup_name == "expedition_time_syringe_timed" then
        return "pocketable_anti_rad_stimm", meta
    end

    -- Martyr's Skull items
    if pickup_name == "collectible_01_pickup" then
        return "pickup_martyr_skull", meta
    end

    if pickup_name == "battery_02_luggable" then
        return "luggable_power_cell_orange", meta
    end

    -- deployables
    if pickup_name == "ammo_cache_deployable" then
        return "pickup_ammo_cache_deployable", meta
    end

    if pickup_name == "medical_crate_deployable" then
        return "medical_crate_deployable", meta
    end

    -- Event items
    if pickup_name == "skulls_01_pickup" then
        return "pickup_tainted_skull", meta
    end

    if pickup_name == "communications_hack_device" then
        return "pocketable_corrupted_auspex_scanner", meta
    end

    if pickup_name == "live_event_saints_01_pickup_small" or pickup_name == "live_event_saints_01_pickup_medium" or pickup_name == "live_event_saints_01_pickup_large" or pickup_name == "consumable" then
        return "pickup_saints", meta
    end

    if pickup_name == "stolen_rations_01_pickup_small" or pickup_name == "stolen_rations_01_pickup_medium" then
        return "pickup_stolen_rations", meta
    end

    local key = string.format("%s|%s|%s|%s|%s|%s",
        tostring(pickup_name or ""),
        tostring(interaction_type or ""),
        tostring(icon or ""),
        tostring(description or ""),
        tostring(unit_name or ""),
        tostring(pickup_data and pickup_data.group or ""))
    key = string.lower(key)

    if string.find(key, "grimoire", 1, true)
        or string.find(key, "scripture", 1, true)
        or string.find(key, "side_mission", 1, true)
        or string.find(key, "objective_side", 1, true)
        or string.find(key, "objective_pickup", 1, true)
        or string.find(key, "luggable", 1, true)
        or string.find(key, "forge_material", 1, true)
        or string.find(key, "tainted_skull", 1, true)
        or string.find(key, "saints_pickup", 1, true)
        or string.find(key, "stolen_rations", 1, true)
        or string.find(key, "penance_collectible", 1, true) then
        _log_once(key, "Unknown pickup: " .. key)
        return "pickup_unknown", meta
    end

    return nil, meta
end

local function _classify_interactee(extension, unit)
    if not extension then
        return nil, nil
    end

    local interaction_type = nil
    local ui_interaction_type = nil
    local icon = nil
    local description = nil

    local ok_interaction_type, interaction_type_value = pcall(function()
        return extension:interaction_type()
    end)
    if ok_interaction_type then
        interaction_type = _safe_lower_string(interaction_type_value)
    end

    local ok_ui_interaction_type, ui_interaction_type_value = pcall(function()
        return extension:ui_interaction_type()
    end)
    if ok_ui_interaction_type then
        ui_interaction_type = _safe_lower_string(ui_interaction_type_value)
    end

    local ok_icon, icon_value = pcall(function()
        return extension:interaction_icon()
    end)
    if ok_icon then
        icon = _safe_lower_string(icon_value)
    end

    local ok_description, description_value = pcall(function()
        return extension:description()
    end)
    if ok_description then
        description = _safe_lower_string(description_value)
    end

    local unit_name = _safe_lower_string(_safe_unit_name(unit))
    local pickup_name = _safe_unit_pickup_name(unit)
    local pickup_data = pickup_name and Pickups and Pickups.by_name and Pickups.by_name[pickup_name] or nil
    local marked_by_player_slot = _marked_by_player_slot_for_unit(unit)

    return _classify_pickup_like(interaction_type, ui_interaction_type, icon, description, unit_name, pickup_name,
        pickup_data, marked_by_player_slot)
end

local function _classify_enemy_from_breed(breed_name)
    local key = string.lower(breed_name or "")

    if key == "chaos_daemonhost" or string.find(key, "daemonhost", 1, true) then
        return "enemy_daemonhost"
    end

    if TWIN_BREEDS[key] or string.find(key, "twin_captain", 1, true) then
        return "enemy_karnak_twin"
    end

    if CAPTAIN_BREEDS[key] or string.find(key, "captain", 1, true) then
        return "enemy_captain"
    end

    if MONSTROSITY_BREEDS[key]
        or string.find(key, "beast_of_nurgle", 1, true)
        or string.find(key, "plague_ogryn", 1, true)
        or string.find(key, "chaos_spawn", 1, true)
        or string.find(key, "houndmaster", 1, true) then
        return "enemy_monstrosity"
    end

    return nil
end

local function _track_unit(unit, kind, source, meta)
    if not kind or not _is_trackable_unit_alive(unit, kind) then
        return
    end

    local existing = mod._tracked_units[unit]
    local now = _safe_gameplay_time() or 0
    local position = _safe_unit_position(unit)

    if existing then
        existing.kind = kind or existing.kind
        existing.source = source or existing.source
        existing.last_seen_t = now
        existing.position = position or existing.position
        if meta ~= nil then
            existing.meta = meta
        end
    else
        mod._tracked_units[unit] = {
            kind = kind,
            source = source,
            last_seen_t = now,
            position = position,
            meta = meta,
        }
    end
end

local function _safe_player_slot(player)
    if not player or not player.slot then
        return nil
    end

    local ok_slot, slot = pcall(function()
        return player:slot()
    end)

    if ok_slot then
        return slot
    end

    return nil
end

_marked_by_player_slot_for_unit = function(unit)
    if not _safe_unit_alive(unit) then
        return nil
    end

    local smart_tag_system = _safe_extension_system("smart_tag_system")
    if not smart_tag_system or not smart_tag_system.unit_tag then
        return nil
    end

    local ok_tag, tag = pcall(function()
        return smart_tag_system:unit_tag(unit)
    end)
    if not ok_tag or not tag or not tag.tagger_player then
        return nil
    end

    local ok_player, player = pcall(function()
        return tag:tagger_player()
    end)
    if not ok_player or not player then
        return nil
    end

    return _safe_player_slot(player)
end

local function _track_point(id, kind, position, source, meta)
    if not id or not kind or not position then
        return
    end

    mod._tracked_points[id] = {
        kind = kind,
        source = source,
        position = position,
        meta = meta,
    }
end

local function _safe_navigation_handler_marked_by_slot(navigation_handler, level_index)
    if not navigation_handler or not navigation_handler.player_slot_by_level_marked or level_index == nil then
        return nil
    end

    local ok, player_slot = pcall(function()
        return navigation_handler:player_slot_by_level_marked(level_index)
    end)

    if ok then
        return player_slot
    end

    return nil
end

local function _safe_navigation_handler_level_completed(navigation_handler, level_index)
    if not navigation_handler or not navigation_handler.is_level_completed or level_index == nil then
        return false
    end

    local ok, completed = pcall(function()
        return navigation_handler:is_level_completed(level_index)
    end)

    return ok and completed == true or false
end

local function _safe_expedition_parent_level_data(section, parent_level_reference_name)
    if not section or not section.levels_data then
        return nil
    end

    local wanted_reference_name = parent_level_reference_name or "level"

    for i = 1, #section.levels_data do
        local level_data = section.levels_data[i]
        if level_data and level_data.reference_name == wanted_reference_name then
            return level_data
        end
    end

    return nil
end

local function _safe_expedition_level_slot_position(level_data)
    if not level_data then
        return nil
    end

    local section = level_data.section
    local custom_data = level_data.custom_data
    local level_slot_id = custom_data and custom_data.level_slot_id
    local parent_level_reference_name = level_data.parent_level_reference_name or "level"
    local parent_level_data = _safe_expedition_parent_level_data(section, parent_level_reference_name)
    local parent_level = parent_level_data and parent_level_data.level or nil

    if not parent_level or not level_slot_id or not Level or not Level.unit_by_id then
        return nil
    end

    local ok_unit, level_slot_unit = pcall(function()
        return Level.unit_by_id(parent_level, level_slot_id)
    end)
    if not ok_unit or not level_slot_unit or not Unit or not Unit.world_position then
        return nil
    end

    local ok_position, world_position = pcall(function()
        return Unit.world_position(level_slot_unit, 1)
    end)
    if ok_position and world_position then
        return _copy_vector3(world_position)
    end

    return nil
end

local function _track_expedition_registered_points(game_mode, navigation_handler, active_section_index, points, kind,
                                                   objective_tag)
    if type(points) ~= "table" then
        return
    end

    if kind == "expedition_objective_opportunity" then
        local location_id = 1

        for level_index, boxed_position in pairs(points) do
            local position = _safe_vector3_unbox(boxed_position)
            local is_active_section = _is_expedition_level_in_active_section(game_mode, active_section_index, level_index)
            local is_completed = _safe_navigation_handler_level_completed(navigation_handler, level_index)
            local section_index = is_active_section and
                _safe_expedition_section_index_by_level_index(game_mode, level_index) or nil

            if position and is_active_section and not is_completed then
                _track_point(
                    string.format("%s:%s", tostring(kind), tostring(level_index)),
                    kind,
                    position,
                    "expedition_navigation",
                    {
                        objective_icon = _expedition_opportunity_icon(level_index),
                        objective_title_icon = _expedition_opportunity_title_icon(location_id),
                        marked_by_player_slot = _safe_navigation_handler_marked_by_slot(navigation_handler, level_index),
                        expedition_level_index = level_index,
                        expedition_section_index = section_index,
                        objective_location_id = location_id,
                        objective_tag = objective_tag,
                    }
                )
            end

            if position and is_active_section then
                location_id = location_id + 1
            end
        end

        return
    end

    local entries = {}

    for level_index, boxed_position in pairs(points) do
        local position = _safe_vector3_unbox(boxed_position)

        if position and _is_expedition_level_in_active_section(game_mode, active_section_index, level_index) then
            entries[#entries + 1] = {
                level_index = level_index,
                position = position,
                section_index = _safe_expedition_section_index_by_level_index(game_mode, level_index),
            }
        end
    end

    table.sort(entries, function(a, b)
        local a_level_index = tonumber(a.level_index)
        local b_level_index = tonumber(b.level_index)

        if a_level_index ~= nil and b_level_index ~= nil and a_level_index ~= b_level_index then
            return a_level_index < b_level_index
        end

        if a_level_index ~= nil and b_level_index == nil then
            return true
        end

        if a_level_index == nil and b_level_index ~= nil then
            return false
        end

        return tostring(a.level_index) < tostring(b.level_index)
    end)

    for index = 1, #entries do
        local entry = entries[index]
        local level_index = entry.level_index
        local position = entry.position

        _track_point(
            string.format("%s:%s", tostring(kind), tostring(level_index)),
            kind,
            position,
            "expedition_navigation",
            {
                objective_icon = EXPEDITION_OBJECTIVE_ICON_DEFAULTS[kind],
                marked_by_player_slot = _safe_navigation_handler_marked_by_slot(navigation_handler, level_index),
                expedition_level_index = level_index,
                expedition_section_index = entry.section_index,
                objective_location_id = index,
                objective_tag = objective_tag,
            }
        )
    end
end

local function _track_expedition_tagged_levels(game_mode, navigation_handler, current_location_index, level_tag, kind)
    if not game_mode or not game_mode.get_all_levels_of_specified_tag or current_location_index == nil then
        return
    end

    local ok_levels, levels = pcall(function()
        return game_mode:get_all_levels_of_specified_tag(current_location_index, { [level_tag] = true })
    end)
    if not ok_levels or type(levels) ~= "table" then
        return
    end

    for i = 1, #levels do
        local level_data = levels[i]
        local position = _safe_expedition_level_slot_position(level_data)

        if position then
            local level_index = _safe_expedition_level_index(level_data and level_data.level or nil)

            _track_point(
                string.format("%s:%s:%s", tostring(kind), tostring(level_index or i),
                    tostring(level_data and level_data.reference_name or i)),
                kind,
                position,
                "expedition_level_tag",
                {
                    objective_icon = EXPEDITION_OBJECTIVE_ICON_DEFAULTS[kind],
                    marked_by_player_slot = _safe_navigation_handler_marked_by_slot(navigation_handler, level_index),
                    expedition_level_index = level_index,
                    objective_tag = level_tag,
                    reference_name = level_data and level_data.reference_name or nil,
                    level_name = level_data and level_data.level_name or nil,
                }
            )
        end
    end
end

local function _scan_expedition_objectives()
    mod._tracked_points = {}

    if not _is_expedition_runtime() then
        return
    end

    local game_mode = _safe_game_mode()
    if not game_mode then
        return
    end

    local navigation_handler = nil
    if game_mode.get_navigation_handler then
        local ok_navigation, value = pcall(function()
            return game_mode:get_navigation_handler()
        end)
        if ok_navigation then
            navigation_handler = value
        end
    end

    local current_location_index = nil
    if game_mode.current_location_index then
        local ok_location, value = pcall(function()
            return game_mode:current_location_index()
        end)
        if ok_location then
            current_location_index = value
        end
    end

    local active_section_index = _safe_expedition_active_section_index(game_mode) or current_location_index

    if navigation_handler and navigation_handler.get_registered_opportunities then
        local ok, opportunities = pcall(function()
            return navigation_handler:get_registered_opportunities()
        end)
        if ok then
            _track_expedition_registered_points(game_mode, navigation_handler, active_section_index, opportunities,
                "expedition_objective_opportunity", "type_opportunity")
        end
    end

    if navigation_handler and navigation_handler.get_registered_exits then
        local ok, exits = pcall(function()
            return navigation_handler:get_registered_exits()
        end)
        if ok then
            _track_expedition_registered_points(game_mode, navigation_handler, active_section_index, exits,
                "expedition_objective_transition", "type_transition")
        end
    end

    if navigation_handler and navigation_handler.get_registered_extractions then
        local ok, extractions = pcall(function()
            return navigation_handler:get_registered_extractions()
        end)
        if ok then
            _track_expedition_registered_points(game_mode, navigation_handler, active_section_index, extractions,
                "expedition_objective_extraction", "type_extraction")
        end
    end

    _track_expedition_tagged_levels(game_mode, navigation_handler, current_location_index, "type_main_objective",
        "expedition_objective_main_objective")
    _track_expedition_tagged_levels(game_mode, navigation_handler, current_location_index, "type_arrival",
        "expedition_objective_arrival")
end

local function _refresh_player_units()
    local player_manager = _player_manager()
    if not player_manager or not player_manager.players then
        return
    end

    local local_player = _local_player()

    for _, player in pairs(player_manager:players()) do
        local unit = player.player_unit
        if unit and _safe_unit_alive(unit) and player ~= local_player then
            local archetype_name = nil
            local player_name = nil
            local player_slot = _safe_player_slot(player)

            local ok_player_name, resolved_player_name = pcall(function()
                return player:name()
            end)
            if ok_player_name then
                player_name = resolved_player_name
            end

            local ok_profile, profile = pcall(function()
                return player:profile()
            end)
            if ok_profile and profile and profile.archetype and profile.archetype.name then
                archetype_name = profile.archetype.name
            end

            local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
            if unit_data_extension and unit_data_extension.archetype_name then
                local ok_archetype, value = pcall(function()
                    return unit_data_extension:archetype_name()
                end)
                if ok_archetype and value ~= nil then
                    archetype_name = value
                end
            end

            _track_unit(unit, "player_teammate", "player_manager", {
                player = player_name,
                player_slot = player_slot,
                archetype_name = archetype_name,
            })
        end
    end
end

local function _scan_interactees()
    local interactee_map = _safe_unit_to_extension_map("interactee_system")
    if not interactee_map then
        return
    end

    local player_unit = _player_unit()

    for unit, extension in pairs(interactee_map) do
        if _safe_unit_alive(unit) then
            local is_active = true
            local is_used = false
            local show_marker = true

            if extension.active then
                local ok_active, value = pcall(function()
                    return extension:active()
                end)
                if ok_active then
                    is_active = value
                end
            end

            if extension.used then
                local ok_used, value = pcall(function()
                    return extension:used()
                end)
                if ok_used then
                    is_used = value
                end
            end

            if player_unit and extension.show_marker then
                local ok_show, value = pcall(function()
                    return extension:show_marker(player_unit)
                end)
                if ok_show then
                    show_marker = value
                end
            end

            if is_active and not is_used and show_marker then
                local kind, meta = _classify_interactee(extension, unit)
                if kind then
                    if kind ~= "expedition_loot_converter" or _is_in_expedition_safe_zone() then
                        _track_unit(unit, kind, "interactee_system", meta)
                    end
                end
            end
        end
    end
end

local function _scan_chests()
    local chest_map = _safe_unit_to_extension_map("chest_system")
    if not chest_map then
        return
    end

    for unit, extension in pairs(chest_map) do
        if _safe_unit_alive(unit) and extension and extension.is_open then
            local ok_open, is_open = pcall(function()
                return extension:is_open()
            end)

            if ok_open and not is_open then
                _track_unit(unit, "crate_unknown", "chest_system")
            end
        end
    end
end

local function _scan_minions()
    local unit_data_map = _safe_unit_to_extension_map("unit_data_system")
    if not unit_data_map then
        return
    end

    for unit, extension in pairs(unit_data_map) do
        if _safe_unit_alive(unit) and extension and extension.breed_name then
            local ok_breed, breed_name = pcall(function()
                return extension:breed_name()
            end)

            if ok_breed and breed_name then
                local kind = _classify_enemy_from_breed(breed_name)
                if kind and _is_trackable_unit_alive(unit, kind) then
                    _track_unit(unit, kind, "unit_data_system", {
                        breed_name = breed_name,
                    })
                end
            end
        end
    end
end

local function _scan_destructibles()
    local destructible_map = _safe_unit_to_extension_map("destructible_system")
    if not destructible_map then
        return
    end

    for unit, extension in pairs(destructible_map) do
        if _safe_unit_alive(unit) and extension then
            local collectible_type = _safe_unit_collectible_type(unit)

            if collectible_type == "heretic_idol" then
                local health_alive = _safe_health_alive(unit)

                if health_alive ~= false then
                    _track_unit(unit, "pickup_heretic_idol", "destructible_system", {
                        collectible_type = collectible_type,
                        unit_name = _safe_lower_string(_safe_unit_name(unit)),
                    })
                end
            end
        end
    end
end

local function _scan_smart_tag_targets()
    local smart_tag_map = _safe_unit_to_extension_map("smart_tag_system")
    if not smart_tag_map then
        return
    end

    for unit, extension in pairs(smart_tag_map) do
        if _safe_unit_alive(unit) and extension then
            local smart_tag_target_type = _safe_unit_smart_tag_target_type(unit)

            if smart_tag_target_type == "medical_crate_deployable" then
                _track_unit(unit, "medical_crate_deployable", "smart_tag_system", {
                    smart_tag_target_type = smart_tag_target_type,
                    deployable_type = _safe_unit_deployable_type(unit),
                    unit_name = _safe_lower_string(_safe_unit_name(unit)),
                })
            end
        end
    end
end

local function _prune_units()
    local now = _safe_gameplay_time() or 0

    for unit, data in pairs(mod._tracked_units) do
        if not _is_trackable_unit_alive(unit, data and data.kind) then
            mod._tracked_units[unit] = nil
        elseif data.last_seen_t and now - data.last_seen_t > 2.5 then
            mod._tracked_units[unit] = nil
        else
            data.position = _safe_unit_position(unit) or data.position
            if not data.position then
                mod._tracked_units[unit] = nil
            end
        end
    end
end

local function _distance_squared(a, b)
    if not a or not b then
        return math.huge
    end

    local ax, ay, az = a.x, a.y, a.z
    local bx, by, bz = b.x, b.y, b.z

    if not _is_finite_number(ax) or not _is_finite_number(ay) or not _is_finite_number(az) then
        return math.huge
    end

    if not _is_finite_number(bx) or not _is_finite_number(by) or not _is_finite_number(bz) then
        return math.huge
    end

    local dx = ax - bx
    local dy = ay - by
    local dz = az - bz

    return dx * dx + dy * dy + dz * dz
end

local function _distance_squared_horizontal(a, b)
    if not a or not b then
        return math.huge
    end

    local ax, ay = a.x, a.y
    local bx, by = b.x, b.y

    if not _is_finite_number(ax) or not _is_finite_number(ay) then
        return math.huge
    end

    if not _is_finite_number(bx) or not _is_finite_number(by) then
        return math.huge
    end

    local dx = ax - bx
    local dy = ay - by

    return dx * dx + dy * dy
end

local function _collect_radar_targets()
    local player_unit = _player_unit()
    if not _safe_unit_alive(player_unit) then
        return {}
    end

    local player_pos = _safe_unit_position(player_unit)
    if not player_pos then
        return {}
    end

    local max_range = mod:get_radar_range()
    local max_range_sq = max_range * max_range
    local max_markers = mod:get_max_radar_markers()
    local targets = {}

    local function append_target(unit, data)
        if not data or not data.position or not data.kind or not _kind_enabled(data.kind) then
            return
        end

        local distance_sq_horizontal = _distance_squared_horizontal(player_pos, data.position)
        local ignore_range = _ignore_radar_range_for_kind(data.kind)

        if distance_sq_horizontal > max_range_sq and not ignore_range then
            return
        end

        targets[#targets + 1] = {
            unit = unit,
            kind = data.kind,
            position = data.position,
            source = data.source,
            meta = data.meta,
            distance_sq = distance_sq_horizontal,
            distance_sq_3d = _distance_squared(player_pos, data.position),
            ignore_radar_range = ignore_range,
        }
    end

    for unit, data in pairs(mod._tracked_units) do
        if _is_trackable_unit_alive(unit, data and data.kind) then
            append_target(unit, data)
        end
    end

    for id, data in pairs(mod._tracked_points) do
        append_target(id, data)
    end

    table.sort(targets, function(a, b)
        return (a.distance_sq or math.huge) < (b.distance_sq or math.huge)
    end)

    if #targets > max_markers then
        for i = #targets, max_markers + 1, -1 do
            targets[i] = nil
        end
    end

    return targets
end

local function _collect_radar_snapshot()
    local player_unit = _player_unit()
    if not _safe_unit_alive(player_unit) then
        return nil
    end

    local player_pos = _safe_unit_position(player_unit)
    if not player_pos then
        return nil
    end

    local local_player = _local_player()

    return {
        player_unit = player_unit,
        player_position = player_pos,
        player_rotation = _safe_player_rotation(player_unit),
        player_slot = _safe_player_slot(local_player),
        targets = mod._radar_targets,
    }
end

local function _count_kind(kind)
    local n = 0
    for unit, data in pairs(mod._tracked_units) do
        if _safe_unit_alive(unit) and data.kind == kind then
            n = n + 1
        end
    end
    return n
end

local function _debug_log_scan()
    if mod:get("debug_mode") ~= true then
        return
    end

    local counts = {
        enemies = 0,
        players = 0,
        ammo = 0,
        crates = 0,
        pocketables = 0,
        materials = 0,
        generic = 0,
    }

    for unit, data in pairs(mod._tracked_units) do
        if _safe_unit_alive(unit) and data.kind then
            local kind = data.kind

            if _string_starts_with(kind, "enemy_") then
                counts.enemies = counts.enemies + 1
            elseif kind == "player_teammate" then
                counts.players = counts.players + 1
            elseif kind == "crate_unknown" then
                counts.crates = counts.crates + 1
            elseif _string_starts_with(kind, "pocketable_") then
                counts.pocketables = counts.pocketables + 1
            elseif _string_starts_with(kind, "material_") then
                counts.materials = counts.materials + 1
            elseif string.find(kind, "ammo", 1, true) then
                counts.ammo = counts.ammo + 1
            else
                counts.generic = counts.generic + 1
            end
        end
    end

    local signature = table.concat({
        tostring(counts.enemies),
        tostring(counts.players),
        tostring(counts.ammo),
        tostring(counts.crates),
        tostring(counts.pocketables),
        tostring(counts.materials),
        tostring(counts.generic),
        tostring(#mod._radar_targets),
        tostring(_safe_mission_name()),
        tostring(_safe_presence_activity()),
        tostring(_safe_mechanism_name()),
    }, "|")

    if signature == mod._last_scan_signature then
        return
    end

    mod._last_scan_signature = signature

    mod:echo(string.format(
        "Radar scan | enemies=%d players=%d ammo=%d crates=%d pocketables=%d materials=%d generic=%d tracked=%d radar_targets=%d mission=%s activity=%s mechanism=%s",
        counts.enemies,
        counts.players,
        counts.ammo,
        counts.crates,
        counts.pocketables,
        counts.materials,
        counts.generic,
        _table_size(mod._tracked_units),
        #mod._radar_targets,
        tostring(_safe_mission_name()),
        tostring(_safe_presence_activity()),
        tostring(_safe_mechanism_name())
    ))
end

local function _reset_runtime_state()
    mod._next_scan_t = 0
    mod._tracked_units = {}
    mod._tracked_points = {}
    mod._logged_units = {}
    mod._radar_targets = {}
    mod._radar_snapshot = nil
    mod._last_update_t = nil
    mod._last_scan_signature = nil
    mod._last_block_signature = nil
    mod._last_state_gameplay = nil
end

local function _debug_log_block(reason, gameplay_t, mission_name, activity, mechanism_name)
    if mod:get("debug_mode") ~= true then
        return
    end

    local signature = table.concat({
        tostring(reason),
        tostring(mission_name),
        tostring(activity),
        tostring(mechanism_name),
        tostring(gameplay_t),
    }, "|")

    if signature == mod._last_block_signature then
        return
    end

    mod._last_block_signature = signature
    mod:echo(string.format(
        "Radar blocked | reason=%s mission=%s activity=%s mechanism=%s gameplay_t=%s",
        tostring(reason),
        tostring(mission_name),
        tostring(activity),
        tostring(mechanism_name),
        tostring(gameplay_t)
    ))
end

local function _update_internal(dt, t)
    if mod:get("enable_radar") == false then
        mod._tracked_points = {}
        mod._radar_targets = {}
        mod._radar_snapshot = nil
        return
    end

    local allowed, reason, gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos =
        _get_runtime_state()
    local scan_clock = gameplay_t or t or 0

    if mod._last_update_t and scan_clock and scan_clock == mod._last_update_t then
        return
    end
    mod._last_update_t = scan_clock

    if not allowed then
        if reason == "player_not_alive" or reason == "player_captured" or reason == "no_player_unit" then
            mod._tracked_units = {}
        end

        mod._tracked_points = {}
        mod._radar_targets = {}
        mod._radar_snapshot = nil
        _debug_log_block(reason, gameplay_t, mission_name, activity, mechanism_name)
        return
    end

    mod._radar_snapshot = {
        player_unit = player_unit,
        player_position = player_pos,
        player_rotation = _safe_player_rotation(player_unit),
        player_slot = _safe_player_slot(_local_player()),
        targets = mod._radar_targets,
    }

    if scan_clock < (mod._next_scan_t or 0) then
        return
    end

    mod._next_scan_t = scan_clock + SCAN_INTERVAL

    _scan_interactees()
    _scan_chests()
    _scan_minions()
    _scan_destructibles()
    _scan_smart_tag_targets()
    _refresh_player_units()
    _scan_expedition_objectives()
    _prune_units()

    mod._radar_targets = _collect_radar_targets()
    mod._radar_snapshot = _collect_radar_snapshot()

    _debug_log_scan()
end

mod.on_game_state_changed = function(status, state_name)
    if status == "enter" and state_name == "GameplayStateRun" then
        mod._gameplay_run = true
        mod._next_scan_t = 0
        mod._last_update_t = nil
        return
    end

    if status == "exit" and state_name == "GameplayStateRun" then
        mod._gameplay_run = false
        _reset_runtime_state()
        return
    end

    if status == "enter" and (
            state_name == "StateLoading" or
            state_name == "StateMainMenu" or
            state_name == "StateTitle" or
            state_name == "StateGameplay" or
            state_name == "GameplayStateInit"
        ) then
        mod._gameplay_run = false
        _reset_runtime_state()
    end
end

mod:register_hud_element({
    class_name = "HudElementRadar",
    filename = "Radar/scripts/mods/Radar/ui/hud_element_radar",
    visibility_groups = { "alive" },
    use_hud_scale = true,
})

if mod:get("debug_mode") then
    _log_once("radar_hook_reg_marker", "Radar registering HudElementWorldMarkers hook")
end
mod:hook_safe("HudElementWorldMarkers", "event_add_world_marker_unit", function(self, unit, template_name, position, ...)
    if mod:get("enable_radar") == false or not _is_allowed_runtime() then
        return
    end

    local key = _safe_lower_string(template_name)

    if key and string.find(key, "ammo", 1, true) then
        _track_unit(unit, "pickup_ammo", "world_marker", { template_name = template_name })
    elseif key and string.find(key, "grenade", 1, true) then
        _track_unit(unit, "pickup_grenade", "world_marker", { template_name = template_name })
    elseif key and (string.find(key, "medical", 1, true) or string.find(key, "medkit", 1, true) or string.find(key, "health", 1, true)) then
        _track_unit(unit, "pickup_medkit", "world_marker", { template_name = template_name })
    elseif key and (string.find(key, "stim", 1, true) or string.find(key, "syringe", 1, true)) then
        _track_unit(unit, "pickup_stimm", "world_marker", { template_name = template_name })
    end
end)

mod:hook_safe("StateGameplay", "update", function(self, dt, t, ...)
    mod._last_state_gameplay = self
    _update_internal(dt, t)
end)

mod.update = function(dt)
    if not mod._gameplay_run then
        return
    end

    _update_internal(dt, _safe_gameplay_time())
end

function mod:get_player_display_style()
    local value = tostring(self:get("player_display_style") or "marked_icon")

    if value ~= "icon_only"
        and value ~= "marked_icon"
        and value ~= "dot_only"
        and value ~= "marked_dot" then
        value = "marked_icon"
    end

    return value
end

function mod:get_radar_snapshot()
    return self._radar_snapshot
end

function mod:should_draw_radar()
    if self:get("enable_radar") == false then
        return false
    end

    if not _is_local_player_alive() then
        return false
    end

    if _is_local_player_captured() then
        return false
    end

    return _is_allowed_runtime()
end

function mod:get_radar_size()
    return self:get("radar_size") or 220
end

function mod:get_radar_range()
    local value = tonumber(self:get("radar_range")) or 40

    if value < 25 then
        value = 25
    elseif value > 100 then
        value = 100
    end

    return value
end

function mod:get_max_radar_markers()
    local value = tonumber(self:get("max_radar_markers")) or 64

    if value < 10 then
        value = 10
    elseif value > 100 then
        value = 100
    end

    return math.floor(value)
end

function mod:get_radar_style()
    local value = tostring(self:get("radar_style") or "square")

    if value ~= "circle" then
        value = "square"
    end

    return value
end

function mod:get_radar_outline()
    local value = tostring(self:get("radar_outline") or "solid")

    if value ~= "solid" and value ~= "dotted" and value ~= "off" then
        value = "solid"
    end

    return value
end

function mod:get_radar_guides()
    local value = tostring(self:get("radar_guides") or "crosshair")

    if value ~= "crosshair" and value ~= "view_guides" and value ~= "range_rings" and value ~= "off" then
        value = "crosshair"
    end

    return value
end

function mod:get_radar_move_step()
    local value = tonumber(self:get("radar_move_step")) or DEFAULT_RADAR_MOVE_STEP

    if value < 1 then
        value = 1
    elseif value > 200 then
        value = 200
    end

    return math.floor(value)
end

function mod:get_radar_pos_x(size)
    local radar_size = tonumber(size) or self:get_radar_size()
    local ui_width = _get_ui_space_size()
    local max_x = math.max(0, ui_width - radar_size)
    local value = tonumber(self:get("radar_pos_x"))

    if value == nil then
        value = DEFAULT_RADAR_POS_X
    end

    return math.floor(_clamp(value, 0, max_x) + 0.5)
end

function mod:get_radar_pos_y(size)
    local radar_size = tonumber(size) or self:get_radar_size()
    local _, ui_height = _get_ui_space_size()
    local max_y = math.max(0, ui_height - radar_size)
    local value = tonumber(self:get("radar_pos_y"))

    if value == nil then
        value = DEFAULT_RADAR_POS_Y
    end

    return math.floor(_clamp(value, 0, max_y) + 0.5)
end

function mod:set_radar_position(x, y)
    local radar_size = self:get_radar_size()
    local ui_width, ui_height = _get_ui_space_size()
    local clamped_x = self:get_radar_pos_x(radar_size)
    local clamped_y = self:get_radar_pos_y(radar_size)

    if x ~= nil then
        local max_x = math.max(0, ui_width - radar_size)

        clamped_x = math.floor(_clamp(tonumber(x) or DEFAULT_RADAR_POS_X, 0, max_x) + 0.5)
        self:set("radar_pos_x", clamped_x)
    end

    if y ~= nil then
        local max_y = math.max(0, ui_height - radar_size)

        clamped_y = math.floor(_clamp(tonumber(y) or DEFAULT_RADAR_POS_Y, 0, max_y) + 0.5)
        self:set("radar_pos_y", clamped_y)
    end

    if mod:get("debug_mode") == true then
        self:notify("Radar position: X %d | Y %d", clamped_x, clamped_y)
    end

    return clamped_x, clamped_y
end

function mod:nudge_radar(dx, dy)
    local x = self:get_radar_pos_x()
    local y = self:get_radar_pos_y()

    return self:set_radar_position(x + (tonumber(dx) or 0), y + (tonumber(dy) or 0))
end

function mod:set_radar_enabled(enabled)
    local is_enabled = enabled == true

    self:set("enable_radar", is_enabled)

    if not is_enabled then
        self._radar_targets = {}
        self._radar_snapshot = nil
    end

    if mod:get("debug_mode") == true then
        self:notify("Radar %s", is_enabled and "enabled" or "disabled")
    end

    return is_enabled
end

function mod.toggle_radar_keybind(_)
    local current_value = mod:get("enable_radar") ~= false

    return mod:set_radar_enabled(not current_value)
end

function mod.move_radar_left(_)
    return mod:nudge_radar(-mod:get_radar_move_step(), 0)
end

function mod.move_radar_right(_)
    return mod:nudge_radar(mod:get_radar_move_step(), 0)
end

function mod.move_radar_up(_)
    return mod:nudge_radar(0, -mod:get_radar_move_step())
end

function mod.move_radar_down(_)
    return mod:nudge_radar(0, mod:get_radar_move_step())
end

function mod:get_radar_origin(size)
    local radar_size = tonumber(size) or self:get_radar_size()
    local x = self:get_radar_pos_x(radar_size)
    local y = self:get_radar_pos_y(radar_size)
    local z = 200
    local radius = radar_size / 2

    return x, y, z, radius
end

function mod:project_target_to_radar(player_pos, player_rot, target_pos, max_radius, range, ignore_radar_range)
    if not player_pos or not target_pos then
        return nil, nil
    end

    range = tonumber(range) or 40
    max_radius = tonumber(max_radius) or 0
    if range <= 0 or max_radius <= 0 then
        return nil, nil
    end

    local dx = target_pos.x - player_pos.x
    local dy = target_pos.y - player_pos.y
    if not _is_finite_number(dx) or not _is_finite_number(dy) then
        return nil, nil
    end

    local distance_sq_horizontal = dx * dx + dy * dy
    if not _is_finite_number(distance_sq_horizontal) then
        return nil, nil
    end

    local outside_range = distance_sq_horizontal > range * range
    if outside_range and not ignore_radar_range then
        return nil, nil
    end

    local local_x = dx
    local local_y = dy

    local forward_x, forward_y = _safe_forward_xy(player_rot)

    if forward_x and forward_y then
        -- Derive a flattened right vector from forward instead of relying on
        -- Quaternion.right. This matches the compass math more closely and keeps
        -- the radar in the same 2D basis as the live camera facing.
        local right_x = forward_y
        local right_y = -forward_x

        local_x = dx * right_x + dy * right_y
        local_y = dx * forward_x + dy * forward_y
    end

    local radar_scale = max_radius / range
    local px = local_x * radar_scale
    local py = -local_y * radar_scale
    if not _is_finite_number(px) or not _is_finite_number(py) then
        return nil, nil
    end

    if outside_range then
        local radar_style = self.get_radar_style and self:get_radar_style() or "square"

        if radar_style == "circle" then
            local projected_distance = math.sqrt(px * px + py * py)
            if projected_distance > 0 then
                local circle_scale = max_radius / projected_distance
                px = px * circle_scale
                py = py * circle_scale
            end
        else
            local max_component = math.max(math.abs(px), math.abs(py))
            if max_component > 0 then
                local square_scale = max_radius / max_component
                px = px * square_scale
                py = py * square_scale
            end
        end
    end

    return px, py
end

return mod
