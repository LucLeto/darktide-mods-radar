return function(env)
    setfenv(1, env)

    local mod = mod

    local PhysicsWorld = PhysicsWorld
    local pcall = pcall
    local pairs = pairs
    local tonumber = tonumber
    local tostring = tostring
    local type = type
    local rawget = rawget
    local math_abs = math.abs
    local math_floor = math.floor
    local math_huge = math.huge
    local math_max = math.max
    local math_rad = math.rad
    local math_sqrt = math.sqrt
    local math_tan = math.tan
    local string_len = string.len
    local string_lower = string.lower
    local string_sub = string.sub
    local table_clear = table.clear or function(t)
        for k in pairs(t) do
            t[k] = nil
        end
    end
    local DARK_RITES_CIRCUMSTANCE_PREFIX = "skulls_guns"
    local LEGACY_SKULLS_CIRCUMSTANCE_PREFIX = "skulls_event_01"
    local DARK_RITES_CIRCUMSTANCE_VARIANT_PREFIX = DARK_RITES_CIRCUMSTANCE_PREFIX .. "_"
    local LEGACY_SKULLS_CIRCUMSTANCE_VARIANT_PREFIX = LEGACY_SKULLS_CIRCUMSTANCE_PREFIX .. "_"
    local PSYKHANIUM_MISSION_NAME = "tg_shooting_range"
    local _scratch_highlight_enabled_by_kind = {}

    local function _reuse_screen_highlight_output()
        local highlights = mod._screen_highlight_targets

        if type(highlights) == "table" then
            table_clear(highlights)
            return highlights
        end

        highlights = {}
        mod._screen_highlight_targets = highlights

        return highlights
    end

    local HUD_OCCLUSION_RAYCAST_FILTERS = {
        "filter_player_character_shooting",
        "filter_ray_projectile",
        "filter_minion_shooting",
        "filter_cover",
    }
    local HUD_OCCLUSION_EPSILON = 0.05
    local HUD_OCCLUSION_RAYCAST_MODE = "closest"
    local HUD_OCCLUSION_COLLISION_FILTER = "collision_filter"
    local HUD_OCCLUSION_RAYCAST_FILTER_COUNT = #HUD_OCCLUSION_RAYCAST_FILTERS

    function _safe_gameplay_time()
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

    function _safe_unit_alive(unit)
        return unit and ALIVE and ALIVE[unit]
    end

    function _safe_unit_name(unit)
        if not _safe_unit_alive(unit) then
            return "<dead>"
        end

        local unit_api = Unit
        local debug_name = unit_api and unit_api.debug_name

        if not debug_name then
            return tostring(unit)
        end

        local ok, result = pcall(debug_name, unit, false)
        if ok and result then
            return tostring(result)
        end

        return tostring(unit)
    end

    function _is_finite_number(v)
        return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
    end

    function _vector3_components(vec)
        if not vec then
            return nil, nil, nil
        end

        local vec_type = type(vec)

        if vec_type == "table" then
            return vec.x, vec.y, vec.z
        end

        local vector3 = Vector3
        local vector3_x = vector3 and vector3.x
        local vector3_y = vector3 and vector3.y
        local vector3_z = vector3 and vector3.z

        if not vector3_x or not vector3_y or not vector3_z then
            return nil, nil, nil
        end

        local ok_x, x = pcall(vector3_x, vec)
        local ok_y, y = pcall(vector3_y, vec)
        local ok_z, z = pcall(vector3_z, vec)

        if ok_x and ok_y and ok_z then
            return x, y, z
        end

        return nil, nil, nil
    end

    function _copy_vector3(vec)
        local x, y, z = _vector3_components(vec)

        if not _is_finite_number(x) or not _is_finite_number(y) or not _is_finite_number(z) then
            return nil
        end

        return { x = x, y = y, z = z }
    end

    function _safe_lower_string(value)
        if value == nil then
            return nil
        end

        return string_lower(tostring(value))
    end

    function _string_starts_with(value, prefix)
        if value == nil or prefix == nil then
            return false
        end

        return string_sub(value, 1, string_len(prefix)) == prefix
    end

    function _safe_unit_data_string(unit, field_name)
        local unit_api = Unit
        local has_data = unit_api and unit_api.has_data
        local get_data = unit_api and unit_api.get_data

        if not unit or not field_name or not has_data or not get_data then
            return nil
        end

        local ok_has_data, has_value = pcall(has_data, unit, field_name)
        if not ok_has_data or not has_value then
            return nil
        end

        local ok_value, value = pcall(get_data, unit, field_name)
        if ok_value and value ~= nil then
            return _safe_lower_string(value)
        end

        return nil
    end

    function _safe_unit_pickup_name(unit)
        return _safe_unit_data_string(unit, "pickup_type")
    end

    function _safe_unit_deployable_type(unit)
        return _safe_unit_data_string(unit, "deployable_type")
    end

    function _safe_unit_smart_tag_target_type(unit)
        return _safe_unit_data_string(unit, "smart_tag_target_type")
    end

    function _safe_unit_collectible_type(unit)
        return _safe_unit_data_string(unit, "collectible_type")
    end

    function _safe_unit_prop_data_name(unit)
        return _safe_unit_data_string(unit, "armor_data_name")
    end

    function _safe_unit_data_breed_name(unit)
        local script_unit = ScriptUnit
        local has_extension = script_unit and script_unit.has_extension

        if not unit or not has_extension then
            return nil
        end

        local unit_data_extension = has_extension(unit, "unit_data_system")
        local breed_name_fn = unit_data_extension and unit_data_extension.breed_name or nil

        if not breed_name_fn then
            return nil
        end

        local ok_breed_name, breed_name = pcall(breed_name_fn, unit_data_extension)

        if ok_breed_name and breed_name ~= nil then
            return _safe_lower_string(breed_name)
        end

        return nil
    end

    function _safe_destructible_collectible_data(extension)
        if not extension then
            return nil
        end

        local collectible_data = rawget(extension, "_collectible_data")
        if type(collectible_data) == "table" then
            return collectible_data
        end

        return nil
    end

    function _safe_destructible_visible(extension)
        if not extension then
            return nil
        end

        local visibility_info = rawget(extension, "_visibility_info")
        if type(visibility_info) == "table" and visibility_info.visible ~= nil then
            return visibility_info.visible == true
        end

        return nil
    end

    function _safe_unit_main_visible(unit)
        local unit_api = Unit

        if not unit or not unit_api or not unit_api.is_visible then
            return nil
        end

        local is_visible = unit_api.is_visible
        local ok_visible, visible = pcall(is_visible, unit, "main")

        if ok_visible then
            return visible == true
        end

        local ok_visible_2, visible_2 = pcall(is_visible, unit)

        if ok_visible_2 then
            return visible_2 == true
        end

        return nil
    end

    function _table_size(t)
        local n = 0
        for _, _ in pairs(t) do
            n = n + 1
        end
        return n
    end

    DEFAULT_RADAR_POS_X = 40
    DEFAULT_RADAR_POS_Y = 220
    DEFAULT_RADAR_MOVE_STEP = 10
    DEFAULT_RADAR_ANCHOR = "top_left"

    RADAR_ANCHORS = {
        top_left = true,
        top_right = true,
        bottom_left = true,
        bottom_right = true,
    }

    function _clamp(value, min_value, max_value)
        if value < min_value then
            return min_value
        end

        if value > max_value then
            return max_value
        end

        return value
    end

    function _get_ui_space_size()
        local width = 1920
        local height = 1080
        local resolution_lookup = RESOLUTION_LOOKUP

        if resolution_lookup and resolution_lookup.width and resolution_lookup.height then
            local inverse_scale = resolution_lookup.inverse_scale or 1

            width = resolution_lookup.width * inverse_scale
            height = resolution_lookup.height * inverse_scale
        end

        return width, height
    end

    function _normalize_radar_anchor(value)
        if RADAR_ANCHORS[value] then
            return value
        end

        return DEFAULT_RADAR_ANCHOR
    end

    function _get_radar_position_bounds(size)
        local radar_size = tonumber(size) or 0
        local ui_width, ui_height = _get_ui_space_size()
        local max_x = math_max(0, ui_width - radar_size)
        local max_y = math_max(0, ui_height - radar_size)

        return max_x, max_y
    end

    function _round_radar_position_value(value, default_value)
        return math_floor((tonumber(value) or default_value or 0) + 0.5)
    end

    function _resolve_radar_position_value(value, default_value, min_value, max_value, unrestricted)
        local rounded_value = _round_radar_position_value(value, default_value)

        if unrestricted == true then
            return rounded_value
        end

        return math_floor(_clamp(rounded_value, min_value, max_value) + 0.5)
    end

    function _get_radar_origin_from_offsets(anchor, offset_x, offset_y, size)
        local max_x, max_y = _get_radar_position_bounds(size)
        local x = offset_x
        local y = offset_y

        if anchor == "top_right" or anchor == "bottom_right" then
            x = max_x - offset_x
        end

        if anchor == "bottom_left" or anchor == "bottom_right" then
            y = max_y - offset_y
        end

        return x, y, max_x, max_y
    end

    function _get_radar_offsets_from_origin(anchor, x, y, size)
        local max_x, max_y = _get_radar_position_bounds(size)
        local offset_x = x
        local offset_y = y

        if anchor == "top_right" or anchor == "bottom_right" then
            offset_x = max_x - x
        end

        if anchor == "bottom_left" or anchor == "bottom_right" then
            offset_y = max_y - y
        end

        return offset_x, offset_y, max_x, max_y
    end

    function _log_once(key, text)
        if mod:get("debug_mode") ~= true then
            return
        end

        if mod._logged_units[key] then
            return
        end

        mod._logged_units[key] = true
        mod:info(text)
    end

    function _position_lookup(unit)
        local position_lookup = POSITION_LOOKUP

        if not unit or not position_lookup then
            return nil
        end

        return _copy_vector3(position_lookup[unit])
    end

    function _safe_unit_position(unit)
        if not _safe_unit_alive(unit) then
            return nil
        end

        local position = _position_lookup(unit)
        if position then
            return position
        end

        local unit_api = Unit
        local world_position = unit_api and unit_api.world_position

        if not world_position then
            return nil
        end

        local ok, result = pcall(world_position, unit, 1)
        if ok and result then
            return _copy_vector3(result)
        end

        return nil
    end

    function _safe_unit_node_position(unit, node_name)
        if not _safe_unit_alive(unit) or node_name == nil then
            return nil
        end

        local unit_api = Unit
        local has_node = unit_api and unit_api.has_node
        local node = unit_api and unit_api.node
        local world_position = unit_api and unit_api.world_position

        if not has_node or not node or not world_position then
            return nil
        end

        local ok_has_node, has_named_node = pcall(has_node, unit, node_name)

        if not ok_has_node or not has_named_node then
            return nil
        end

        local ok_node, node_index = pcall(node, unit, node_name)

        if not ok_node or node_index == nil then
            return nil
        end

        local ok_position, result = pcall(world_position, unit, node_index)

        if ok_position and result then
            return _copy_vector3(result)
        end

        return nil
    end

    function _is_enemy_kind(kind)
        return kind ~= nil and _string_starts_with(kind, "enemy_")
    end

    function _safe_health_alive(unit)
        local script_unit = ScriptUnit
        local has_extension = script_unit and script_unit.has_extension

        if not unit or not has_extension then
            return nil
        end

        local health_extension = has_extension(unit, "health_system")
        if not health_extension or not health_extension.is_alive then
            return nil
        end

        local ok_alive, is_alive = pcall(health_extension.is_alive, health_extension)

        if ok_alive then
            return is_alive
        end

        return nil
    end

    function _safe_unit_has_keyword(unit, keyword)
        local script_unit = ScriptUnit
        local has_extension = script_unit and script_unit.has_extension

        if not unit or not keyword or not has_extension then
            return false
        end

        local buff_extension = has_extension(unit, "buff_system")
        if not buff_extension or not buff_extension.has_keyword then
            return false
        end

        local ok_has_keyword, has_keyword = pcall(buff_extension.has_keyword, buff_extension, keyword)

        return ok_has_keyword and has_keyword or false
    end

    function _safe_unit_has_buff_template(unit, buff_template_name)
        local script_unit = ScriptUnit
        local has_extension = script_unit and script_unit.has_extension

        if not unit or not buff_template_name or not has_extension then
            return false
        end

        local buff_extension = has_extension(unit, "buff_system")
        if not buff_extension or not buff_extension.has_buff_using_buff_template then
            return false
        end

        local ok_has_buff, has_buff = pcall(
            buff_extension.has_buff_using_buff_template,
            buff_extension,
            buff_template_name
        )

        return ok_has_buff and has_buff or false
    end

    function _safe_unit_ability_name(unit, ability_type)
        local script_unit = ScriptUnit
        local has_extension = script_unit and script_unit.has_extension

        if not unit or not has_extension then
            return nil
        end

        local ability_extension = has_extension(unit, "ability_system")

        if not ability_extension then
            return nil
        end

        if ability_type ~= nil and ability_extension.ability_name then
            local ok_ability_name, ability_name = pcall(ability_extension.ability_name, ability_extension, ability_type)

            if ok_ability_name and ability_name ~= nil and ability_name ~= "none" and ability_name ~= "not_equipped" then
                return ability_name
            end
        end

        if (ability_type == nil or ability_type == "combat_ability")
            and ability_extension.get_current_ability_name then
            local ok_current_ability_name, current_ability_name = pcall(ability_extension.get_current_ability_name, ability_extension)

            if ok_current_ability_name
                and current_ability_name ~= nil
                and current_ability_name ~= "none"
                and current_ability_name ~= "not_equipped" then
                return current_ability_name
            end
        end

        return nil
    end

    function _is_owned_by_death_manager(unit)
        local script_unit = ScriptUnit
        local has_extension = script_unit and script_unit.has_extension

        if not unit or not has_extension then
            return false
        end

        local unit_data_extension = has_extension(unit, "unit_data_system")
        if not unit_data_extension or not unit_data_extension.is_owned_by_death_manager then
            return false
        end

        local ok_owned, owned = pcall(unit_data_extension.is_owned_by_death_manager, unit_data_extension)

        return ok_owned and owned or false
    end

    function _is_trackable_unit_alive(unit, kind)
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

        if kind == "pickup_heretic_idol" or kind == "dark_rites_totem" then
            local health_alive = _safe_health_alive(unit)
            if health_alive == false then
                return false
            end
        end

        return true
    end

    function _safe_world_rotation(unit, node)
        if not _safe_unit_alive(unit) then
            return nil
        end

        local unit_api = Unit
        local world_rotation = unit_api and unit_api.world_rotation

        if not world_rotation then
            return nil
        end

        local ok, rotation = pcall(world_rotation, unit, node or 1)
        if ok then
            return rotation
        end

        return nil
    end

    function _safe_flat_direction_xy(vector_getter, rotation)
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

        local length = math_sqrt(x * x + y * y)
        if length <= 0 then
            return nil, nil
        end

        return x / length, y / length
    end

    function _safe_forward_xy(rotation)
        local quaternion = Quaternion
        local forward = quaternion and quaternion.forward

        return _safe_flat_direction_xy(forward, rotation)
    end

    function _safe_mission_name()
        local state_gameplay = mod._last_state_gameplay
        if state_gameplay then
            local shared_state = state_gameplay._shared_state
            local mission_name = shared_state and shared_state.mission_name
            if mission_name ~= nil then
                return mission_name
            end
        end

        local state_manager = Managers and Managers.state
        local game_mode_manager = state_manager and state_manager.game_mode
        if game_mode_manager and game_mode_manager.mission_name then
            local ok, mission_name = pcall(game_mode_manager.mission_name, game_mode_manager)

            if ok and mission_name ~= nil then
                return mission_name
            end
        end

        local gameplay = state_manager and state_manager.gameplay
        local shared_state = gameplay and gameplay._shared_state
        local mission_name = shared_state and shared_state.mission_name
        if mission_name ~= nil then
            return mission_name
        end

        local package_synchronizer_client = Managers and Managers.package_synchronizer_client
        mission_name = package_synchronizer_client and package_synchronizer_client._mission_name
        if mission_name ~= nil then
            return mission_name
        end

        local mechanism_manager = Managers and Managers.mechanism
        local mechanism = mechanism_manager and mechanism_manager._mechanism
        mission_name = mechanism and mechanism._mission_name
        if mission_name ~= nil then
            return mission_name
        end

        return nil
    end

    local function _safe_circumstance_value(value)
        if value ~= nil and value ~= "" then
            return _safe_lower_string(value)
        end

        return nil
    end

    function _safe_circumstance_name()
        local state_gameplay = mod._last_state_gameplay
        if state_gameplay then
            local shared_state = state_gameplay._shared_state
            local circumstance_name = _safe_circumstance_value(shared_state and shared_state.circumstance_name)

            if circumstance_name ~= nil then
                return circumstance_name
            end
        end

        local state_manager = Managers and Managers.state
        local game_mode_manager = state_manager and state_manager.game_mode
        if game_mode_manager and game_mode_manager.circumstance_name then
            local ok, circumstance_name = pcall(game_mode_manager.circumstance_name, game_mode_manager)
            circumstance_name = ok and _safe_circumstance_value(circumstance_name) or nil

            if circumstance_name ~= nil then
                return circumstance_name
            end
        end

        local gameplay = state_manager and state_manager.gameplay
        local shared_state = gameplay and gameplay._shared_state
        local circumstance_name = _safe_circumstance_value(shared_state and shared_state.circumstance_name)
        if circumstance_name ~= nil then
            return circumstance_name
        end

        local package_synchronizer_client = Managers and Managers.package_synchronizer_client
        circumstance_name = _safe_circumstance_value(package_synchronizer_client and package_synchronizer_client._circumstance_name)
        if circumstance_name ~= nil then
            return circumstance_name
        end

        local mechanism_manager = Managers and Managers.mechanism
        if mechanism_manager and mechanism_manager.mechanism_data then
            local ok, mechanism_data = pcall(mechanism_manager.mechanism_data, mechanism_manager)
            circumstance_name = ok and _safe_circumstance_value(mechanism_data and mechanism_data.circumstance_name) or nil

            if circumstance_name ~= nil then
                return circumstance_name
            end
        end

        local mechanism = mechanism_manager and mechanism_manager._mechanism
        local mechanism_data = mechanism and mechanism._mechanism_data
        circumstance_name = _safe_circumstance_value(mechanism_data and mechanism_data.circumstance_name)
            or _safe_circumstance_value(mechanism and mechanism._circumstance_name)

        if circumstance_name ~= nil then
            return circumstance_name
        end

        return nil
    end

    local function _is_skulls_live_event_circumstance(circumstance_name)
        return circumstance_name == DARK_RITES_CIRCUMSTANCE_PREFIX
            or circumstance_name == LEGACY_SKULLS_CIRCUMSTANCE_PREFIX
            or _string_starts_with(circumstance_name, DARK_RITES_CIRCUMSTANCE_VARIANT_PREFIX)
            or _string_starts_with(circumstance_name, LEGACY_SKULLS_CIRCUMSTANCE_VARIANT_PREFIX)
    end

    local function _is_psykhanium_mission(mission_name)
        return mission_name == PSYKHANIUM_MISSION_NAME
    end

    function _reset_dark_rites_marker_scan_cache()
        mod._dark_rites_marker_scan_cache_valid = false
        mod._dark_rites_marker_scan_allowed = true
        mod._dark_rites_marker_cached_circumstance_name = nil
        mod._dark_rites_marker_cached_mission_name = nil
    end

    function _is_dark_rites_marker_scan_allowed()
        local circumstance_name = _safe_circumstance_name()
        local mission_name = _safe_lower_string(_safe_mission_name())

        if mod._dark_rites_marker_scan_cache_valid == true
            and mod._dark_rites_marker_cached_circumstance_name == circumstance_name
            and mod._dark_rites_marker_cached_mission_name == mission_name then
            return mod._dark_rites_marker_scan_allowed == true
        end

        local scan_allowed = circumstance_name == nil
            or _is_skulls_live_event_circumstance(circumstance_name)
            or _is_psykhanium_mission(mission_name)

        mod._dark_rites_marker_scan_cache_valid = true
        mod._dark_rites_marker_scan_allowed = scan_allowed
        mod._dark_rites_marker_cached_circumstance_name = circumstance_name
        mod._dark_rites_marker_cached_mission_name = mission_name

        return scan_allowed
    end

    function _safe_presence_activity()
        local presence_manager = Managers and Managers.presence
        if not presence_manager then
            return nil
        end

        if presence_manager.activity then
            local ok, value = pcall(presence_manager.activity, presence_manager)
            if ok and value ~= nil then
                return tostring(value)
            end
        end

        if presence_manager.current_activity then
            local ok, value = pcall(presence_manager.current_activity, presence_manager)
            if ok and value ~= nil then
                return tostring(value)
            end
        end

        local value = presence_manager._current_activity
        if value ~= nil then
            return tostring(value)
        end

        value = presence_manager._activity
        if value ~= nil then
            return tostring(value)
        end

        value = presence_manager._presence_name
        if value ~= nil then
            return tostring(value)
        end

        return nil
    end

    function _safe_mechanism_name()
        local mechanism_manager = Managers and Managers.mechanism
        if not mechanism_manager then
            return nil
        end

        if mechanism_manager.current_mechanism_name then
            local ok, value = pcall(mechanism_manager.current_mechanism_name, mechanism_manager)
            if ok and value ~= nil then
                return tostring(value)
            end
        end

        if mechanism_manager.mechanism_name then
            local ok, value = pcall(mechanism_manager.mechanism_name, mechanism_manager)
            if ok and value ~= nil then
                return tostring(value)
            end
        end

        local value = mechanism_manager._mechanism_name
        if value ~= nil then
            return tostring(value)
        end

        local mechanism = mechanism_manager._mechanism
        if mechanism ~= nil then
            if type(mechanism) == "table" then
                value = mechanism.name or mechanism._name
                if value ~= nil then
                    return tostring(value)
                end
            else
                return tostring(mechanism)
            end
        end

        return nil
    end

    function _is_hub_runtime(mission_name, activity, mechanism_name)
        mission_name = mission_name or _safe_mission_name()
        activity = activity or _safe_presence_activity()
        mechanism_name = mechanism_name or _safe_mechanism_name()

        return mission_name == "hub_ship"
            or activity == "hub"
            or activity == "main_menu"
            or activity == "title_screen"
            or mechanism_name == "hub"
    end

    function _player_manager()
        return Managers and Managers.player
    end

    function _local_player()
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

        local ok, player = pcall(getter, player_manager, 1)

        if ok then
            return player
        end

        return nil
    end

    function _player_unit()
        local local_player = _local_player()
        return local_player and local_player.player_unit
    end

    function _safe_player_character_state_component(player_unit)
        local script_unit = ScriptUnit
        local has_extension = script_unit and script_unit.has_extension

        if not player_unit or not has_extension then
            return nil
        end

        local unit_data_extension = has_extension(player_unit, "unit_data_system")

        if not unit_data_extension or not unit_data_extension.read_component then
            return nil
        end

        local ok_component, character_state_component = pcall(
            unit_data_extension.read_component,
            unit_data_extension,
            "character_state"
        )

        if ok_component then
            return character_state_component
        end

        return nil
    end

    function _safe_player_character_state_name(player_unit)
        local character_state_component = _safe_player_character_state_component(player_unit)
        return character_state_component and character_state_component.state_name or nil
    end

    local function _player_for_unit(player_unit)
        if not player_unit then
            return nil
        end

        local player_manager = _player_manager()
        local players_getter = player_manager and player_manager.players

        if not players_getter then
            return nil
        end

        local ok_players, players = pcall(players_getter, player_manager)

        if not ok_players or type(players) ~= "table" then
            return nil
        end

        for _, player in pairs(players) do
            if player and player.player_unit == player_unit then
                return player
            end
        end

        return nil
    end

    function _is_local_player_using_foreign_unit(player_unit)
        local local_player = _local_player()

        if not local_player or not player_unit then
            return false
        end

        -- Spectating can repoint `local_player.player_unit` to a living teammate.
        -- Treat that as unavailable for radar visibility and scan gating.
        local owning_player = _player_for_unit(player_unit)

        return owning_player ~= nil and owning_player ~= local_player
    end

    function _is_player_unit_alive(player_unit)
        return _safe_unit_alive(player_unit)
    end

    function _is_player_unit_captured(player_unit)
        if not _safe_unit_alive(player_unit) or not PlayerUnitStatus then
            return false
        end

        local character_state_component = _safe_player_character_state_component(player_unit)

        if not character_state_component then
            return false
        end

        local state_name = character_state_component.state_name

        if state_name == "hogtied" then
            return true
        end

        local is_hogtied = PlayerUnitStatus.is_hogtied
        if not is_hogtied then
            return false
        end

        local ok, captured = pcall(is_hogtied, character_state_component)

        return ok and captured == true or false
    end

    function _is_local_player_alive()
        local player_unit = _player_unit()

        if _is_local_player_using_foreign_unit(player_unit) then
            return false
        end

        return _is_player_unit_alive(player_unit)
    end

    function _is_local_player_captured()
        local player_unit = _player_unit()

        if _is_local_player_using_foreign_unit(player_unit) then
            return false
        end

        return _is_player_unit_captured(player_unit)
    end

    function _safe_camera_rotation()
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

        local has_camera = camera_manager.has_camera

        if has_camera then
            local ok_has_camera, visible_camera = pcall(has_camera, camera_manager, viewport_name)

            if ok_has_camera and not visible_camera then
                return nil
            end
        end

        local camera_rotation = camera_manager.camera_rotation
        if not camera_rotation then
            return nil
        end

        local ok_rotation, rotation = pcall(camera_rotation, camera_manager, viewport_name)

        if ok_rotation and rotation then
            return rotation
        end

        return nil
    end

    function _safe_player_rotation(player_unit)
        local camera_rotation = _safe_camera_rotation()
        if camera_rotation then
            return camera_rotation
        end

        if not _safe_unit_alive(player_unit) then
            return nil
        end

        local script_unit = ScriptUnit
        local has_extension = script_unit and script_unit.has_extension
        local unit_data_extension = has_extension and has_extension(player_unit, "unit_data_system") or nil

        if unit_data_extension and unit_data_extension.read_component then
            local ok_component, first_person_component = pcall(unit_data_extension.read_component, unit_data_extension,
                "first_person")

            if ok_component and first_person_component and first_person_component.rotation then
                return first_person_component.rotation
            end
        end

        local first_person_extension = has_extension and has_extension(player_unit, "first_person_system") or nil
        if first_person_extension and first_person_extension.extrapolated_rotation then
            local ok_rotation, rotation = pcall(first_person_extension.extrapolated_rotation, first_person_extension)

            if ok_rotation and rotation then
                return rotation
            end
        end

        return _safe_world_rotation(player_unit, 1)
    end

    function _safe_extension_system(system_name)
        local extension_manager = Managers and Managers.state and Managers.state.extension
        local system_getter = extension_manager and extension_manager.system

        if not system_getter then
            return nil
        end

        local ok, system = pcall(system_getter, extension_manager, system_name)

        if ok then
            return system
        end

        return nil
    end

    function _copy_color_array(color)
        if not color then
            return nil
        end

        return {
            color[1] or 255,
            color[2] or 255,
            color[3] or 255,
            color[4] or 255,
        }
    end

    function _darkened_color_array(color, multiplier)
        local src = color or DEFAULT_COLOR_ARRAY_WHITE
        local mul = multiplier or 1

        return {
            src[1] or 255,
            math_floor(_clamp((src[2] or 255) * mul, 0, 255) + 0.5),
            math_floor(_clamp((src[3] or 255) * mul, 0, 255) + 0.5),
            math_floor(_clamp((src[4] or 255) * mul, 0, 255) + 0.5),
        }
    end

    SCREEN_HIGHLIGHT_Z_OFFSET_BY_KIND = {
        material_diamantine = 0.1,
        material_plasteel = 0.1,
        crate_unknown = 0.08,
        pickup_ammo = 0.08,
        pickup_ammo_small = 0.08,
        pickup_ammo_big = 0.08,
        pickup_grenade = 0.08,
        pocketable_ammo_crate = 0.08,
        pocketable_medical_crate = 0.08,
        pocketable_syringe_ability = 0.08,
        pocketable_syringe_corruption = 0.08,
        pocketable_syringe_power = 0.08,
        pocketable_syringe_speed = 0.08,
        luggable_power_cell_teal = 0.18,
        luggable_cryonic_rod = 0.18,
        luggable_moebian_pox_zetaphyte_13_sample = 0.18,
        luggable_vacuum_capsule = 0.18,
        luggable_special_issue_ammo = 0.18,
        luggable_prismata_crystal_repository = 0.18,
        pickup_mortis_relic = 0.1,
        pickup_coordinates_paper = 0.08,
        pocketable_grimoire = 0.08,
        pocketable_scripture = 0.08,
        material_expeditions_currency = 0.1,
        material_expeditions_loot = 0.1,
        material_expeditions_loot_player_drop = 0.1,
        luggable_data_reliquary = 0.18,
        pickup_large_ammunition_crate = 0.1,
        luggable_promethium_barrel = 0.12,
        hazard_explosive_barrel = 0.12,
        hazard_fire_barrel = 0.12,
        pocketable_anti_rad_stimm = 0.08,
        pocketable_airstrike = 0.08,
        pocketable_artillery_strike = 0.08,
        pocketable_big_grenade = 0.08,
        pocketable_landmine_explosive = 0.08,
        pocketable_landmine_fire = 0.08,
        pocketable_landmine_shock = 0.08,
        pocketable_valkyrie_hover = 0.08,
        pocketable_void_shield = 0.08,
        pickup_martyr_skull = 0.1,
        luggable_power_cell_orange = 0.18,
        medicae_station = 0.2,
        luggable_socket = 0.18,
        pickup_heretic_idol = 0.12,
        pickup_tainted_skull = 0.1,
        dark_rites_totem = 0.12,
        dark_rites_servo_skull = 0.1,
        pocketable_corrupted_auspex_scanner = 0.08,
        pickup_saints = 0.12,
        pickup_leftover = 0.12,
        pickup_stolen_rations = 0.08,
    }

    function _screen_highlight_color_for_kind(kind)
        if mod.get_nearby_highlight_color then
            return mod:get_nearby_highlight_color(kind)
        end

        return _copy_color_array(NEARBY_OUTLINE_COLOR_BY_KIND[kind])
    end

    function _safe_interactee_ui_interaction_type(unit, interactee_extension_map)
        if not unit then
            return nil
        end

        local extension = interactee_extension_map and interactee_extension_map[unit] or nil

        if type(extension) ~= "table" then
            local script_unit = ScriptUnit
            local has_extension = script_unit and script_unit.has_extension

            extension = has_extension and has_extension(unit, "interactee_system") or nil
        end

        local ui_interaction_type = extension and extension.ui_interaction_type

        if type(ui_interaction_type) ~= "function" then
            return nil
        end

        local ok_type, value = pcall(ui_interaction_type, extension)

        if ok_type then
            return _safe_lower_string(value)
        end

        return nil
    end

    function _interaction_world_marker_cache()
        local cache = mod._interaction_world_markers_by_unit

        if type(cache) ~= "table" then
            cache = {}
            mod._interaction_world_markers_by_unit = cache
        else
            table_clear(cache)
        end

        return cache
    end

    function mod:get_interaction_world_markers_by_unit()
        local cache = _interaction_world_marker_cache()
        local managers = Managers
        local event_manager = managers and managers.event or nil
        local trigger = event_manager and event_manager.trigger or nil

        if not trigger then
            return cache
        end

        local markers = nil
        local ok = pcall(trigger, event_manager, "request_world_markers_list", function(response)
            markers = response
        end)

        if not ok or type(markers) ~= "table" then
            return cache
        end

        for i = 1, #markers do
            local marker = markers[i]
            local unit = marker and marker.unit or nil
            local widget = marker and marker.widget or nil

            if marker and marker.type == "interaction" and unit and marker.draw ~= false and widget
                and widget.visible ~= false then
                cache[unit] = marker
            end
        end

        return cache
    end

    function mod:get_interaction_world_marker_draw_data(unit)
        if not unit then
            return nil, nil, nil
        end

        local markers_by_unit = self:get_interaction_world_markers_by_unit()
        local marker = markers_by_unit and markers_by_unit[unit] or nil
        local widget = marker and marker.widget or nil
        local widget_offset = widget and widget.offset or nil
        local style = widget and widget.style or nil
        local icon_style = style and style.icon or nil
        local icon_size = icon_style and icon_style.size or nil

        local center_x = widget_offset and widget_offset[1] or nil
        local center_y = widget_offset and widget_offset[2] or nil
        local size_x = icon_size and icon_size[1] or nil
        local size_y = icon_size and icon_size[2] or nil

        if not (_is_finite_number(center_x) and _is_finite_number(center_y)) then
            return nil, nil, nil
        end

        local draw_size = nil

        if _is_finite_number(size_x) and _is_finite_number(size_y) then
            draw_size = math_max(size_x, size_y)
        end

        if not _is_finite_number(draw_size) then
            local ring_style = style and style.ring or nil
            local ring_size = ring_style and ring_style.size or nil
            local ring_x = ring_size and ring_size[1] or nil
            local ring_y = ring_size and ring_size[2] or nil

            if _is_finite_number(ring_x) and _is_finite_number(ring_y) then
                draw_size = math_max(ring_x, ring_y)
            end
        end

        if not _is_finite_number(draw_size) then
            draw_size = 0
        end

        return center_x, center_y, draw_size
    end

    function mod:get_hud_player_camera(hud_element)
        local parent = hud_element and hud_element._parent

        if not parent or not parent.player_camera then
            return nil
        end

        local ok_camera, camera = pcall(parent.player_camera, parent)

        if ok_camera and camera then
            return camera
        end

        return nil
    end

    function mod:get_hud_player_camera_position(hud_element)
        local camera = self:get_hud_player_camera(hud_element)

        if not camera or not Camera or not Camera.local_position then
            return nil
        end

        local ok_position, position = pcall(Camera.local_position, camera)

        if ok_position and position then
            return _copy_vector3(position)
        end

        return nil
    end

    function mod:get_hud_player_camera_rotation(hud_element)
        local camera = self:get_hud_player_camera(hud_element)

        if not camera or not Camera or not Camera.local_rotation then
            return nil
        end

        local ok_rotation, rotation = pcall(Camera.local_rotation, camera)

        if ok_rotation and rotation then
            return rotation
        end

        return nil
    end

    function mod:get_hud_player_vertical_fov()
        local local_player = _local_player()

        if not local_player then
            return nil
        end

        local viewport_name = local_player.viewport_name
        local camera_manager = Managers and Managers.state and Managers.state.camera

        if not viewport_name or not camera_manager or type(camera_manager.fov) ~= "function" then
            return nil
        end

        if type(camera_manager.has_camera) == "function" then
            local ok_has_camera, has_camera = pcall(camera_manager.has_camera, camera_manager, viewport_name)

            if ok_has_camera and not has_camera then
                return nil
            end
        end

        local ok_fov, vertical_fov = pcall(camera_manager.fov, camera_manager, viewport_name)

        vertical_fov = ok_fov and tonumber(vertical_fov) or nil

        if vertical_fov and vertical_fov > 0 then
            return vertical_fov
        end

        return nil
    end

    function _hud_rotation_basis(rotation)
        if not rotation then
            return nil
        end

        local quaternion = Quaternion
        local quaternion_forward = quaternion.forward
        local quaternion_right = quaternion.right
        local quaternion_up = quaternion.up

        local ok_forward, forward = pcall(quaternion_forward, rotation)
        local ok_right, right = pcall(quaternion_right, rotation)
        local ok_up, up = pcall(quaternion_up, rotation)

        if not ok_forward or not ok_right or not ok_up or not forward or not right or not up then
            return nil
        end

        local fx, fy, fz = _vector3_components(forward)
        local rx, ry, rz = _vector3_components(right)
        local ux, uy, uz = _vector3_components(up)

        if not (_is_finite_number(fx) and _is_finite_number(fy) and _is_finite_number(fz)) then
            return nil
        end

        if not (_is_finite_number(rx) and _is_finite_number(ry) and _is_finite_number(rz)) then
            return nil
        end

        if not (_is_finite_number(ux) and _is_finite_number(uy) and _is_finite_number(uz)) then
            return nil
        end

        return {
            forward = { x = fx, y = fy, z = fz },
            right = { x = rx, y = ry, z = rz },
            up = { x = ux, y = uy, z = uz },
        }
    end

    function _safe_hud_physics_world()
        local physics_manager = Managers and Managers.state and Managers.state.physics

        if physics_manager and type(physics_manager.physics_world) == "function" then
            local ok, physics_world = pcall(physics_manager.physics_world, physics_manager)

            if ok and physics_world then
                return physics_world
            end
        end

        if World and World.physics_world then
            local state_world_manager = Managers and Managers.state and Managers.state.world

            if state_world_manager and type(state_world_manager.world) == "function" then
                local ok_world, world = pcall(state_world_manager.world, state_world_manager, "level_world")

                if ok_world and world then
                    local ok_physics_world, physics_world = pcall(World.physics_world, world)

                    if ok_physics_world and physics_world then
                        return physics_world
                    end
                end
            end

            local world_manager = Managers and Managers.world

            if world_manager and type(world_manager.world) == "function" then
                local ok_world, world = pcall(world_manager.world, world_manager, "level_world")

                if ok_world and world then
                    local ok_physics_world, physics_world = pcall(World.physics_world, world)

                    if ok_physics_world and physics_world then
                        return physics_world
                    end
                end
            end
        end

        return nil
    end

    local function _extract_hud_raycast_distance_from_value(value)
        if type(value) == "number" and _is_finite_number(value) then
            return value
        end

        if type(value) == "table" then
            local distance = value.distance

            if _is_finite_number(distance) then
                return distance
            end

            local first = value[1]
            distance = type(first) == "table" and first.distance or nil

            if _is_finite_number(distance) then
                return distance
            end
        end

        return nil
    end

    function _extract_hud_raycast_distance(a, b, c, d)
        return _extract_hud_raycast_distance_from_value(a)
            or _extract_hud_raycast_distance_from_value(b)
            or _extract_hud_raycast_distance_from_value(c)
            or _extract_hud_raycast_distance_from_value(d)
    end

    function mod:is_hud_world_position_occluded(camera_position, world_position)
        local physics_world = _safe_hud_physics_world()
        local immediate_raycast = PhysicsWorld and PhysicsWorld.immediate_raycast

        if not physics_world or not immediate_raycast then
            return false
        end

        local dx = world_position.x - camera_position.x
        local dy = world_position.y - camera_position.y
        local dz = world_position.z - camera_position.z
        local distance = math_sqrt(dx * dx + dy * dy + dz * dz)

        if not _is_finite_number(distance) or distance <= HUD_OCCLUSION_EPSILON then
            return false
        end

        local origin = Vector3(camera_position.x, camera_position.y, camera_position.z)
        local direction = Vector3(dx / distance, dy / distance, dz / distance)
        local threshold = distance - HUD_OCCLUSION_EPSILON

        for i = 1, HUD_OCCLUSION_RAYCAST_FILTER_COUNT do
            local ok, a, b, c, d = pcall(
                immediate_raycast,
                physics_world,
                origin,
                direction,
                distance,
                HUD_OCCLUSION_RAYCAST_MODE,
                HUD_OCCLUSION_COLLISION_FILTER,
                HUD_OCCLUSION_RAYCAST_FILTERS[i]
            )

            if ok then
                local hit_distance = _extract_hud_raycast_distance(a, b, c, d)

                if hit_distance ~= nil then
                    return hit_distance < threshold
                end
            end
        end

        return false
    end

    function mod:get_hud_projection_context(hud_element, fallback_camera_position, fallback_rotation)
        local camera_position = self:get_hud_player_camera_position(hud_element) or fallback_camera_position
        local camera_rotation = self:get_hud_player_camera_rotation(hud_element) or fallback_rotation
        local basis = _hud_rotation_basis(camera_rotation)

        if not camera_position or not basis then
            return nil
        end

        local ui_width, ui_height = _get_ui_space_size()
        local vertical_fov = self:get_hud_player_vertical_fov() or math_rad(65)
        local tan_half_vertical = math_tan(vertical_fov * 0.5)
        local aspect_ratio = ui_width / math_max(ui_height, 1)
        local tan_half_horizontal = tan_half_vertical * aspect_ratio

        if tan_half_vertical <= 0 or tan_half_horizontal <= 0 then
            return nil
        end

        return {
            camera_position = camera_position,
            basis = basis,
            ui_width = ui_width,
            ui_height = ui_height,
            tan_half_vertical = tan_half_vertical,
            tan_half_horizontal = tan_half_horizontal,
        }
    end

    function mod:project_hud_world_to_screen_with_context(world_position, projection_context)
        if not world_position or not projection_context then
            return nil, nil, nil
        end

        local camera_position = projection_context.camera_position
        local basis = projection_context.basis

        local dx = world_position.x - camera_position.x
        local dy = world_position.y - camera_position.y
        local dz = world_position.z - camera_position.z

        local view_x = dx * basis.right.x + dy * basis.right.y + dz * basis.right.z
        local view_y = dx * basis.up.x + dy * basis.up.y + dz * basis.up.z
        local view_z = dx * basis.forward.x + dy * basis.forward.y + dz * basis.forward.z

        if not (_is_finite_number(view_x) and _is_finite_number(view_y) and _is_finite_number(view_z)) then
            return nil, nil, nil
        end

        if view_z <= 0.05 then
            return nil, nil, nil
        end

        local ndc_x = view_x / (view_z * projection_context.tan_half_horizontal)
        local ndc_y = view_y / (view_z * projection_context.tan_half_vertical)

        if not (_is_finite_number(ndc_x) and _is_finite_number(ndc_y)) then
            return nil, nil, nil
        end

        if math_abs(ndc_x) > 1 or math_abs(ndc_y) > 1 then
            return nil, nil, nil
        end

        local screen_x = (ndc_x * 0.5 + 0.5) * projection_context.ui_width
        local screen_y = (0.5 - ndc_y * 0.5) * projection_context.ui_height

        if not (_is_finite_number(screen_x) and _is_finite_number(screen_y)) then
            return nil, nil, nil
        end

        return screen_x, screen_y, camera_position
    end

    function mod:project_hud_world_to_screen(hud_element, world_position, fallback_camera_position, fallback_rotation)
        if not world_position then
            return nil, nil, nil
        end

        local projection_context = self:get_hud_projection_context(hud_element, fallback_camera_position,
            fallback_rotation)

        if not projection_context then
            return nil, nil, nil
        end

        return self:project_hud_world_to_screen_with_context(world_position, projection_context)
    end

    function mod:get_screen_highlight_bracket_size(distance_sq)
        local distance = math_sqrt(math_max(distance_sq or 0, 0))
        local min_distance = 5
        local max_distance = 20
        local near_size = 24
        local far_size = 18

        if distance <= min_distance then
            return near_size
        end

        if distance >= max_distance then
            return far_size
        end

        local t = (distance - min_distance) / (max_distance - min_distance)
        return near_size + (far_size - near_size) * t
    end

    function _screen_highlight_anchor_position(target, interactee_extension_map)
        local unit = target and target.unit or nil
        local position = target and target.position

        local anchor_position = nil

        if unit then
            anchor_position = _safe_unit_node_position(unit, "ui_interaction_marker") or _safe_unit_position(unit)
        end

        if not anchor_position and not position then
            return nil
        end

        anchor_position = anchor_position or {
            x = position.x,
            y = position.y,
            z = position.z or 0,
        }

        local z_offset = SCREEN_HIGHLIGHT_Z_OFFSET_BY_KIND[target.kind] or 0
        local ui_interaction_type = _safe_interactee_ui_interaction_type(unit, interactee_extension_map)

        if ui_interaction_type == "pickup" or ui_interaction_type == "pickup_hidden" then
            z_offset = z_offset + 0.8
        end

        return {
            x = anchor_position.x,
            y = anchor_position.y,
            z = (anchor_position.z or 0) + z_offset,
        }
    end

    function _screen_highlight_projection_fallback_position(target)
        local unit = target and target.unit or nil
        local position = nil

        if unit then
            position = _safe_unit_position(unit)
        end

        position = position or (target and target.position) or nil

        if not position then
            return nil
        end

        local z_offset = SCREEN_HIGHLIGHT_Z_OFFSET_BY_KIND[target.kind] or 0

        return {
            x = position.x,
            y = position.y,
            z = (position.z or 0) + z_offset,
        }
    end

    function _copy_target_list(targets, destination)
        local copy = destination or {}
        table_clear(copy)

        if not targets then
            return copy
        end

        for i = 1, #targets do
            copy[i] = targets[i]
        end

        return copy
    end

    function _distance_squared(a, b)
        if not a or not b then
            return math_huge
        end

        local ax, ay, az = a.x, a.y, a.z
        local bx, by, bz = b.x, b.y, b.z

        if not _is_finite_number(ax) or not _is_finite_number(ay) or not _is_finite_number(az) then
            return math_huge
        end

        if not _is_finite_number(bx) or not _is_finite_number(by) or not _is_finite_number(bz) then
            return math_huge
        end

        local dx = ax - bx
        local dy = ay - by
        local dz = az - bz

        return dx * dx + dy * dy + dz * dz
    end

    function _collect_screen_highlight_targets()
        local highlights = _reuse_screen_highlight_output()

        if not mod:has_any_nearby_highlight_enabled() then
            return highlights
        end

        local player_unit = _player_unit()

        if not _safe_unit_alive(player_unit) then
            return highlights
        end

        local player_pos = _safe_unit_position(player_unit)

        if not player_pos then
            return highlights
        end

        local get_setting = mod.get
        local get_marker_scale_group = mod.get_marker_scale_group
        local highlight_setting_by_group = NEARBY_HIGHLIGHT_SETTING_BY_GROUP
        local screen_highlight_color_for_kind = _screen_highlight_color_for_kind
        local get_occluded_highlight_color = mod.get_occluded_highlight_color
        local screen_highlight_anchor_position = _screen_highlight_anchor_position
        local screen_highlight_projection_fallback_position = _screen_highlight_projection_fallback_position
        local darkened_color_array = _darkened_color_array
        local distance_squared = _distance_squared
        local interactee_extension_map = _safe_unit_to_extension_map("interactee_system")
        local max_distance = mod:get_nearby_highlight_range()
        local max_distance_sq = max_distance * max_distance
        local highlight_count = 0

        table_clear(_scratch_highlight_enabled_by_kind)

        local highlight_enabled_by_kind = _scratch_highlight_enabled_by_kind
        local source_targets = mod._highlight_source_radar_targets or mod._unclustered_radar_targets or
            mod._radar_targets
        local source_target_count = source_targets and #source_targets or 0

        for i = 1, source_target_count do
            local target = source_targets[i]
            local kind = target and target.kind

            if kind ~= nil then
                local enabled = highlight_enabled_by_kind[kind]

                if enabled == nil then
                    local group_name = get_marker_scale_group(mod, kind)
                    local setting_id = group_name and highlight_setting_by_group[group_name] or nil

                    enabled = setting_id ~= nil and get_setting(mod, setting_id) == true or false
                    highlight_enabled_by_kind[kind] = enabled
                end

                if enabled then
                    local position = target.position
                    local distance_sq = target.distance_sq_3d

                    if distance_sq == nil and position then
                        distance_sq = distance_squared(player_pos, position)
                    end

                    if distance_sq ~= nil and distance_sq <= max_distance_sq then
                        local color = screen_highlight_color_for_kind(kind)
                        local world_position = screen_highlight_anchor_position(target, interactee_extension_map)
                        local fallback_world_position = screen_highlight_projection_fallback_position(target)

                        if color and world_position then
                            highlight_count = highlight_count + 1
                            highlights[highlight_count] = {
                                unit = target.unit,
                                kind = kind,
                                world_position = world_position,
                                fallback_world_position = fallback_world_position or world_position,
                                color = color,
                                occluded_color = get_occluded_highlight_color and
                                    get_occluded_highlight_color(mod, kind, NEARBY_OUTLINE_OCCLUDED_MULTIPLIER) or
                                    darkened_color_array(color, NEARBY_OUTLINE_OCCLUDED_MULTIPLIER),
                                distance_sq_3d = distance_sq,
                            }
                        end
                    end
                end
            end
        end

        return highlights
    end

    function _safe_unit_to_extension_map(system_name)
        local system = _safe_extension_system(system_name)
        local unit_to_extension_map = system and system.unit_to_extension_map

        if not unit_to_extension_map then
            return nil
        end

        local ok, map = pcall(unit_to_extension_map, system)

        if ok and type(map) == "table" then
            return map
        end

        return nil
    end

    function _safe_outline_extension_data_map()
        local outline_system = _safe_extension_system("outline_system")
        local unit_extension_data = outline_system and rawget(outline_system, "_unit_extension_data")

        if type(unit_extension_data) == "table" then
            return unit_extension_data
        end

        return nil
    end

    function _safe_unit_outline_extension(unit, outline_extension_map)
        if not unit then
            return nil
        end

        local unit_extension_data = outline_extension_map or _safe_outline_extension_data_map()

        if type(unit_extension_data) ~= "table" then
            return nil
        end

        local extension = unit_extension_data[unit]

        if type(extension) == "table" then
            return extension
        end

        return nil
    end

    function _safe_game_mode_manager()
        return Managers and Managers.state and Managers.state.game_mode or nil
    end

    function _safe_game_mode()
        local game_mode_manager = _safe_game_mode_manager()
        if not game_mode_manager or not game_mode_manager.game_mode then
            return nil
        end

        local ok, game_mode = pcall(game_mode_manager.game_mode, game_mode_manager)

        if ok then
            return game_mode
        end

        return nil
    end

    function _safe_game_mode_name()
        local game_mode_manager = _safe_game_mode_manager()
        if not game_mode_manager or not game_mode_manager.game_mode_name then
            return nil
        end

        local ok, game_mode_name = pcall(game_mode_manager.game_mode_name, game_mode_manager)

        if ok then
            return game_mode_name
        end

        return nil
    end
end
