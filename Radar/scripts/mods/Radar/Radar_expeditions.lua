return function(env)
    setfenv(1, env)

    local mod = mod

    local pcall = pcall
    local pairs = pairs
    local tonumber = tonumber
    local tostring = tostring
    local type = type
    local rawget = rawget
    local math_floor = math.floor
    local string_find = string.find
    local string_format = string.format
    local string_lower = string.lower
    local table_sort = table.sort
    local table_clear = table.clear or function(t)
        for k in pairs(t) do
            t[k] = nil
        end
    end

    local _scratch_seen_player_tag_ids = {}
    local _scratch_expedition_registered_entries = {}

    local function _is_expedition_runtime()
        return _safe_game_mode_name() == "expedition"
    end

    function _expedition_loot_value_for_pickup_name(pickup_name)
        if not pickup_name then
            return nil
        end

        return EXPEDITION_LOOT_VALUE_BY_PICKUP_NAME[pickup_name]
    end

    local function _safe_expedition_loot_handler()
        if not _is_expedition_runtime() then
            return nil
        end

        local game_mode = _safe_game_mode()

        if not game_mode then
            return nil
        end

        local logic = rawget(game_mode, "_game_mode_logic")

        if logic and logic.loot_handler then
            local ok_handler, handler = pcall(logic.loot_handler, logic)

            if ok_handler and handler then
                return handler
            end
        end

        if logic then
            local handler = rawget(logic, "_loot_handler")

            if handler then
                return handler
            end
        end

        return nil
    end

    local function _safe_expedition_player_drop_amount(unit)
        if not unit then
            return nil
        end

        local loot_handler = _safe_expedition_loot_handler()
        local dropped_loot_by_pickup_unit = loot_handler and rawget(loot_handler, "_dropped_loot_by_pickup_unit")
        local amount = dropped_loot_by_pickup_unit and dropped_loot_by_pickup_unit[unit] or nil
        local numeric_amount = tonumber(amount)

        if numeric_amount and numeric_amount > 0 then
            return math_floor(numeric_amount + 0.5)
        end

        return nil
    end

    function _is_in_expedition_safe_zone()
        if not _is_expedition_runtime() then
            return false
        end

        local game_mode = _safe_game_mode()
        local in_safe_zone = game_mode and game_mode.in_safe_zone

        if not in_safe_zone then
            return false
        end

        local ok, value = pcall(in_safe_zone, game_mode)

        return ok and value == true or false
    end

    function _should_hide_expedition_store_product_in_open_zone(unit)
        if not unit or not _is_expedition_runtime() or _is_in_expedition_safe_zone() then
            return false
        end

        local game_mode = _safe_game_mode()
        if not game_mode then
            return false
        end

        -- Safe-zone store data marks sanctuary shop fixtures without also matching player-dropped deployables.
        local get_unit_store_data = game_mode.get_unit_store_data
        if type(get_unit_store_data) == "function" then
            local ok_store_data, store_data = pcall(get_unit_store_data, game_mode, unit)

            if ok_store_data and store_data ~= nil then
                return true
            end
        end

        local is_store_product = game_mode.is_store_product
        if type(is_store_product) == "function" then
            local ok_is_store_product, value = pcall(is_store_product, game_mode, unit)

            if ok_is_store_product and value == true then
                return true
            end
        end

        return false
    end

    local function _safe_vector3_unbox(value)
        if not value then
            return nil
        end

        if type(value) == "table" and value.x ~= nil and value.y ~= nil and value.z ~= nil then
            return _copy_vector3(value)
        end

        if value.unbox then
            local ok, vector = pcall(value.unbox, value)

            if ok and vector then
                return _copy_vector3(vector)
            end
        end

        return _copy_vector3(value)
    end

    local UNIT_LEVEL_METHOD_NAMES = {
        "level_by_unit",
        "get_level_by_unit",
        "unit_level",
        "unit_level_by_unit",
        "get_unit_level",
        "owner_level",
        "unit_owner_level",
    }

    local UNIT_LEVEL_INDEX_METHOD_NAMES = {
        "level_index_by_unit",
        "get_level_index_by_unit",
        "unit_level_index",
        "unit_level_index_by_unit",
        "get_unit_level_index",
        "unit_to_level_index",
    }

    local UNIT_LEVEL_LOOKUP_TABLE_NAMES = {
        "_unit_to_level",
        "_level_by_unit",
        "_unit_to_level_lookup",
        "_unit_to_level_map",
    }

    local UNIT_LEVEL_INDEX_LOOKUP_TABLE_NAMES = {
        "_unit_to_level_index",
        "_level_index_by_unit",
        "_unit_to_level_index_lookup",
        "_unit_to_level_index_map",
    }

    local UNIT_SECTION_DATA_FIELDS = {
        "expedition_section_index",
        "section_index",
    }

    local UNIT_LEVEL_INDEX_DATA_FIELDS = {
        "expedition_level_index",
        "level_index",
    }

    local function _safe_unit_spawner()
        return Managers and Managers.state and Managers.state.unit_spawner or nil
    end

    local function _normalized_expedition_index(index)
        return tonumber(index) or index
    end

    local function _safe_unit_data_value(unit, field_name)
        local unit_api = Unit
        local has_data = unit_api and unit_api.has_data
        local get_data = unit_api and unit_api.get_data

        if not unit or not field_name or type(has_data) ~= "function" or type(get_data) ~= "function" then
            return nil
        end

        local ok_has_data, has_value = pcall(has_data, unit, field_name)
        if not ok_has_data or not has_value then
            return nil
        end

        local ok_value, value = pcall(get_data, unit, field_name)
        if ok_value then
            return value
        end

        return nil
    end

    local function _safe_unit_data_index(unit, field_names)
        for i = 1, #field_names do
            local value = _safe_unit_data_value(unit, field_names[i])

            if value ~= nil then
                return _normalized_expedition_index(value)
            end
        end

        return nil
    end

    local function _safe_unit_spawner_method_lookup(unit_spawner, unit, method_names)
        if not unit_spawner or not unit then
            return nil
        end

        for i = 1, #method_names do
            local method = unit_spawner[method_names[i]]

            if type(method) == "function" then
                local ok, value = pcall(method, unit_spawner, unit)

                if ok and value ~= nil then
                    return value
                end
            end
        end

        return nil
    end

    local function _safe_unit_spawner_table_lookup(unit_spawner, unit, table_names)
        if type(unit_spawner) ~= "table" or not unit then
            return nil
        end

        for i = 1, #table_names do
            local lookup = rawget(unit_spawner, table_names[i])

            if type(lookup) == "table" then
                local value = lookup[unit]

                if value ~= nil then
                    return value
                end
            end
        end

        return nil
    end

    local function _safe_unit_level(unit)
        local unit_api = Unit
        local level_fn = unit_api and unit_api.level

        if unit and type(level_fn) == "function" then
            local ok, level = pcall(level_fn, unit)

            if ok and level ~= nil then
                return level
            end
        end

        local unit_spawner = _safe_unit_spawner()
        local level = _safe_unit_spawner_method_lookup(unit_spawner, unit, UNIT_LEVEL_METHOD_NAMES)

        if level ~= nil then
            return level
        end

        return _safe_unit_spawner_table_lookup(unit_spawner, unit, UNIT_LEVEL_LOOKUP_TABLE_NAMES)
    end

    local function _safe_unit_level_index(unit)
        local data_index = _safe_unit_data_index(unit, UNIT_LEVEL_INDEX_DATA_FIELDS)

        if data_index ~= nil then
            return data_index
        end

        local unit_spawner = _safe_unit_spawner()
        local level_index = _safe_unit_spawner_method_lookup(unit_spawner, unit, UNIT_LEVEL_INDEX_METHOD_NAMES)

        if level_index ~= nil then
            return _normalized_expedition_index(level_index)
        end

        level_index = _safe_unit_spawner_table_lookup(unit_spawner, unit, UNIT_LEVEL_INDEX_LOOKUP_TABLE_NAMES)

        return _normalized_expedition_index(level_index)
    end

    local function _safe_expedition_level_index(level)
        local unit_spawner = _safe_unit_spawner()

        if not level or not unit_spawner then
            return nil
        end

        if type(unit_spawner.index_by_level) ~= "function" then
            return nil
        end

        local ok, level_index = pcall(unit_spawner.index_by_level, unit_spawner, level)

        if ok then
            return _normalized_expedition_index(level_index)
        end

        return nil
    end

    local function _safe_expedition_level_by_index(level_index, sub_level_index)
        local unit_spawner = _safe_unit_spawner()

        if level_index == nil or not unit_spawner then
            return nil
        end

        if type(unit_spawner.level_by_index) ~= "function" then
            return nil
        end

        local ok, level = pcall(unit_spawner.level_by_index, unit_spawner, level_index, sub_level_index)

        if ok then
            return level
        end

        return nil
    end

    local function _safe_expedition_level_data_by_level(game_mode, level)
        if not game_mode or not level or type(game_mode.get_level_data) ~= "function" then
            return nil
        end

        local ok, level_data = pcall(game_mode.get_level_data, game_mode, level)

        if ok then
            return level_data
        end

        return nil
    end

    local function _safe_expedition_level_data_by_index(game_mode, level_index, sub_level_index)
        if not game_mode or type(game_mode.get_level_data) ~= "function" then
            return nil
        end

        local level = _safe_expedition_level_by_index(level_index, sub_level_index)
        if not level then
            return nil
        end

        return _safe_expedition_level_data_by_level(game_mode, level)
    end

    local function _safe_expedition_section_index_from_level_data(level_data)
        local section = level_data and level_data.section or nil
        local section_index = section and section.index or nil

        return _normalized_expedition_index(section_index)
    end

    local function _safe_expedition_section_index_by_level(game_mode, level)
        local level_data = _safe_expedition_level_data_by_level(game_mode, level)

        return _safe_expedition_section_index_from_level_data(level_data)
    end

    local function _safe_expedition_section_index_by_level_index(game_mode, level_index, sub_level_index)
        local level_data = _safe_expedition_level_data_by_index(game_mode, level_index, sub_level_index)

        return _safe_expedition_section_index_from_level_data(level_data)
    end

    local function _safe_unit_expedition_section_index(game_mode, unit)
        local section_index = _safe_unit_data_index(unit, UNIT_SECTION_DATA_FIELDS)

        if section_index ~= nil then
            return section_index
        end

        local level = _safe_unit_level(unit)
        section_index = _safe_expedition_section_index_by_level(game_mode, level)

        if section_index ~= nil then
            return section_index
        end

        local level_index = _safe_unit_level_index(unit)

        if level_index ~= nil then
            return _safe_expedition_section_index_by_level_index(game_mode, level_index)
        end

        return nil
    end

    local function _safe_current_safe_zone_section_index(game_mode)
        local logic = game_mode and game_mode._game_mode_logic or nil
        local index = logic and logic._current_safe_zone_section_index or nil

        return _normalized_expedition_index(index)
    end

    local function _safe_expedition_active_section_index(game_mode)
        if not game_mode then
            return nil
        end

        local in_safe_zone = false
        local in_safe_zone_fn = game_mode.in_safe_zone

        if in_safe_zone_fn then
            local ok, value = pcall(in_safe_zone_fn, game_mode)

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

        local current_location_index = game_mode.current_location_index

        if current_location_index then
            local ok, value = pcall(current_location_index, game_mode)

            if ok then
                return _normalized_expedition_index(value)
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

        return section_index == _normalized_expedition_index(active_section_index)
    end

    local function _expedition_opportunity_icon(level_index)
        local numeric_index = tonumber(level_index) or 0
        local icon_index = 1 + numeric_index % 24

        return string_format("content/ui/materials/backgrounds/scanner/scanner_map_greek_%02d", icon_index)
    end

    local function _expedition_opportunity_title_icon(location_id)
        local numeric_id = tonumber(location_id) or 0
        return string_format("content/ui/materials/backgrounds/scanner/scanner_map_%d", numeric_id % 9)
    end

    local function _safe_havoc_runtime_active()
        local state_gameplay = mod._last_state_gameplay
        local shared_state = state_gameplay and state_gameplay._shared_state
        local havoc_data = shared_state and shared_state.havoc_data

        if havoc_data ~= nil and havoc_data ~= "" then
            return true
        end

        local difficulty_manager = Managers and Managers.state and Managers.state.difficulty
        if difficulty_manager and difficulty_manager.get_parsed_havoc_data then
            local ok_parsed, parsed_havoc_data = pcall(difficulty_manager.get_parsed_havoc_data, difficulty_manager)

            if ok_parsed and parsed_havoc_data then
                return true
            end
        end

        local game_mode = _safe_game_mode()
        if game_mode and game_mode.extension then
            local ok_extension, havoc_extension = pcall(game_mode.extension, game_mode, "havoc")

            if ok_extension and havoc_extension then
                return true
            end
        end

        return false
    end

    local function _classify_radar_game_mode(mission_name, mechanism_name)
        local game_mode_name = _safe_game_mode_name()

        if game_mode_name == "expedition" or mechanism_name == "expedition" then
            return "expeditions", game_mode_name
        end

        if game_mode_name == "survival" then
            return "mortis_trials", game_mode_name
        end

        if _safe_havoc_runtime_active() then
            return "havoc", game_mode_name
        end

        if game_mode_name == "coop_complete_objective"
            or game_mode_name == "training_grounds"
            or game_mode_name == "shooting_range"
            or mechanism_name == "adventure"
            or mission_name == "tg_shooting_range" then
            return "regular_missions", game_mode_name
        end

        return nil, game_mode_name
    end

    function mod:is_radar_enabled_for_game_mode(game_mode_id)
        local setting_id = RADAR_GAME_MODE_SETTING_BY_ID[game_mode_id]

        if not setting_id then
            return false
        end

        return self:get(setting_id) ~= false
    end

    local function _is_radar_enabled_for_current_mode(mission_name, mechanism_name)
        local game_mode_id = _classify_radar_game_mode(mission_name, mechanism_name)

        if not game_mode_id then
            return false
        end

        return mod:is_radar_enabled_for_game_mode(game_mode_id)
    end

    function mod:is_radar_runtime_game_mode_allowed()
        local mission_name = _safe_mission_name()
        local activity = _safe_presence_activity()
        local mechanism_name = _safe_mechanism_name()

        if activity == "loading" then
            return false
        end

        if mechanism_name == "left_session" or mechanism_name == "hub" then
            return false
        end

        if not mission_name or mission_name == "hub_ship" then
            return false
        end

        if mechanism_name == "onboarding" and mission_name ~= "tg_shooting_range" then
            return false
        end

        if _is_hub_runtime(mission_name, activity, mechanism_name) then
            return false
        end

        return _is_radar_enabled_for_current_mode(mission_name, mechanism_name)
    end

    local _runtime_state_cached_t = nil
    local _runtime_state_allowed = false
    local _runtime_state_reason = nil
    local _runtime_state_mission_name = nil
    local _runtime_state_activity = nil
    local _runtime_state_mechanism_name = nil
    local _runtime_state_player_unit = nil
    local _runtime_state_player_pos = nil

    function _invalidate_runtime_state_cache()
        _runtime_state_cached_t = nil
    end

    local function _store_runtime_state(allowed, reason, gameplay_t, mission_name, activity, mechanism_name,
                                        player_unit, player_pos)
        _runtime_state_cached_t = gameplay_t
        _runtime_state_allowed = allowed
        _runtime_state_reason = reason
        _runtime_state_mission_name = mission_name
        _runtime_state_activity = activity
        _runtime_state_mechanism_name = mechanism_name
        _runtime_state_player_unit = player_unit
        _runtime_state_player_pos = player_pos

        return allowed, reason, gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    function _get_runtime_state()
        local gameplay_t = _safe_gameplay_time()

        -- The runtime state is queried several times per frame (scan hook, DMF
        -- update and HUD draw); reuse the result computed for the current
        -- gameplay tick instead of re-deriving it from the managers each time.
        if gameplay_t ~= nil and gameplay_t == _runtime_state_cached_t then
            return _runtime_state_allowed, _runtime_state_reason, gameplay_t, _runtime_state_mission_name,
                _runtime_state_activity, _runtime_state_mechanism_name, _runtime_state_player_unit,
                _runtime_state_player_pos
        end

        local mission_name = _safe_mission_name()
        local activity = _safe_presence_activity()
        local mechanism_name = _safe_mechanism_name()
        local player_unit = _player_unit()
        local player_pos = _safe_unit_position(player_unit)

        if activity == "loading" then
            return _store_runtime_state(false, "loading", gameplay_t, mission_name, activity, mechanism_name,
                player_unit, player_pos)
        end

        if mechanism_name == "left_session" or mechanism_name == "hub" then
            return _store_runtime_state(false, "hub_mechanism", gameplay_t, mission_name, activity, mechanism_name,
                player_unit, player_pos)
        end

        if not mission_name then
            return _store_runtime_state(false, "no_mission", gameplay_t, mission_name, activity, mechanism_name,
                player_unit, player_pos)
        end

        if mission_name == "hub_ship" then
            return _store_runtime_state(false, "hub_mission", gameplay_t, mission_name, activity, mechanism_name,
                player_unit, player_pos)
        end

        if mechanism_name == "onboarding" and mission_name ~= "tg_shooting_range" then
            return _store_runtime_state(false, "onboarding_non_psykhanium", gameplay_t, mission_name, activity,
                mechanism_name, player_unit, player_pos)
        end

        if _is_hub_runtime(mission_name, activity, mechanism_name) then
            return _store_runtime_state(false, "hub_runtime", gameplay_t, mission_name, activity, mechanism_name,
                player_unit, player_pos)
        end

        if not mod:is_radar_runtime_game_mode_allowed() then
            return _store_runtime_state(false, "game_mode_disabled", gameplay_t, mission_name, activity, mechanism_name,
                player_unit, player_pos)
        end

        if _is_local_player_using_foreign_unit(player_unit) then
            return _store_runtime_state(false, "spectating_teammate", gameplay_t, mission_name, activity, mechanism_name,
                player_unit, player_pos)
        end

        if not _is_player_unit_alive(player_unit) then
            return _store_runtime_state(false, "player_not_alive", gameplay_t, mission_name, activity, mechanism_name,
                player_unit, player_pos)
        end

        if _is_player_unit_captured(player_unit) then
            return _store_runtime_state(false, "player_captured", gameplay_t, mission_name, activity, mechanism_name,
                player_unit, player_pos)
        end

        if not player_pos then
            return _store_runtime_state(false, "no_player_position", gameplay_t, mission_name, activity, mechanism_name,
                player_unit, player_pos)
        end

        return _store_runtime_state(true, "ok", gameplay_t, mission_name, activity, mechanism_name, player_unit,
            player_pos)
    end

    function _is_allowed_runtime()
        local allowed = _get_runtime_state()
        return allowed
    end

    function _is_expedition_marker_kind(kind)
        return EXPEDITION_MARKER_KINDS[kind] == true
    end

    function _is_boss_marker_kind(kind)
        return kind == "enemy_monstrosity"
            or kind == "enemy_captain"
            or kind == "enemy_karnak_twin"
    end

    function _is_player_smart_tag_kind(kind)
        return kind == "location_attention"
            or kind == "location_ping"
            or kind == "location_threat"
    end

    function _has_infinite_radar_range_for_kind(kind)
        if kind == "material_expeditions_loot_player_drop" then
            return true
        end

        if kind == "player_teammate" and mod:get_player_marker_range_mode() == "infinite" then
            return true
        end

        if _is_boss_marker_kind(kind) and mod:get_boss_marker_range_mode() == "infinite" then
            return true
        end

        return false
    end

    function _ignore_radar_range_for_kind(kind)
        if kind == "expedition_loot_converter" then
            return false
        end

        if _is_player_smart_tag_kind(kind) then
            return true
        end

        if _has_infinite_radar_range_for_kind(kind) then
            return true
        end

        return _is_expedition_marker_kind(kind) and mod:get("ignore_radar_range_for_expedition_markers") == true
    end

    function _kind_enabled(kind)
        local get_enemy_marker_mode = mod.get_enemy_marker_mode
        local get_icon_distance_marker_display_mode = mod.get_icon_distance_marker_display_mode
        local get_expedition_marker_display_mode = mod.get_expedition_marker_display_mode
        local get_marker_display_mode = mod.get_marker_display_mode
        local get_setting = mod.get
        local enemy_display_mode = get_enemy_marker_mode(mod, kind)

        if kind == "player_teammate" then
            if mod.get_show_players then
                return mod:get_show_players()
            end

            local show_players = get_setting(mod, "show_players")

            return show_players ~= false and show_players ~= "off"
        end

        if kind == "player_companion_dog" or kind == "player_companion_servo_skull" then
            local companion_setting_id = KIND_TO_SETTING[kind]
            local companion_setting = companion_setting_id and get_setting(mod, companion_setting_id)

            return companion_setting ~= false and companion_setting ~= "off"
        end

        if enemy_display_mode ~= nil then
            return enemy_display_mode ~= "off"
        end

        local icon_distance_display_mode = get_icon_distance_marker_display_mode and
            get_icon_distance_marker_display_mode(mod, kind) or nil
        if icon_distance_display_mode ~= nil then
            return icon_distance_display_mode ~= "off"
        end

        local expedition_display_mode = get_expedition_marker_display_mode and
            get_expedition_marker_display_mode(mod, kind) or nil
        if expedition_display_mode ~= nil then
            return expedition_display_mode ~= "off"
        end

        local display_mode = get_marker_display_mode(mod, kind)
        if display_mode ~= nil then
            return display_mode ~= "off"
        end

        local setting_id = KIND_TO_SETTING[kind]
        if not setting_id then
            return true
        end

        local value = get_setting(mod, setting_id)

        return value ~= false and value ~= "off"
    end

    local function _is_expedition_section_filtered_item_kind(kind)
        if not kind then
            return false
        end

        if kind == "player_teammate"
            or kind == "player_companion_dog"
            or kind == "player_companion_servo_skull" then
            return false
        end

        if _is_player_smart_tag_kind(kind) or _is_enemy_kind(kind) or _is_expedition_marker_kind(kind) then
            return false
        end

        return true
    end

    function _is_valid_expedition_item_for_current_section(kind, unit)
        if not _is_expedition_runtime() then
            return true
        end

        if not _is_expedition_section_filtered_item_kind(kind) then
            return true
        end

        -- Player-drop loot bookkeeping lives on the server; clients still identify the pickup by
        -- pickup_type, so section filtering must not require the server-only dropped-loot table.
        local game_mode = _safe_game_mode()
        local active_section_index = _safe_expedition_active_section_index(game_mode)

        if active_section_index == nil then
            return true
        end

        local unit_section_index = _safe_unit_expedition_section_index(game_mode, unit)

        if unit_section_index == nil then
            _log_once("expedition_item_section_unknown:" .. tostring(kind),
                "Unable to resolve expedition section for item kind: " .. tostring(kind))
            return true
        end

        return unit_section_index == active_section_index
    end

    local function _pickup_meta(pickup_name, interaction_type, ui_interaction_type, interaction_icon, description,
                                marked_by_player_slot)
        return {
            pickup_name = pickup_name,
            interaction_type = interaction_type,
            ui_interaction_type = ui_interaction_type,
            interaction_icon = interaction_icon,
            description = description,
            marked_by_player_slot = marked_by_player_slot,
        }
    end

    local function _classify_pickup_like(interaction_type, ui_interaction_type, icon, description, unit_name, pickup_name,
                                         pickup_data, marked_by_player_slot)
        local pickup_group = pickup_data and pickup_data.group or nil
        local meta = _pickup_meta(pickup_name, interaction_type, ui_interaction_type, icon, description,
            marked_by_player_slot)

        -- default items
        if interaction_type == "chest" then
            return "crate_unknown", meta
        end

        if interaction_type == "expedition_loot_converter"
            or (ui_interaction_type == "point_of_interest" and pickup_name == "expedition_loot_converter") then
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

        if pickup_name ~= nil then
            local exact_kind = EXACT_PICKUP_KIND_BY_NAME[pickup_name]

            if exact_kind then
                if exact_kind == "pickup_tainted_skull" and not _is_dark_rites_marker_scan_allowed() then
                    return nil, meta
                end

                return exact_kind, meta
            end

            if PAPER_PICKUP_NAMES[pickup_name] then
                return "pickup_coordinates_paper", meta
            end

            if SAINTS_PICKUP_NAMES[pickup_name] then
                return "pickup_saints", meta
            end

            if _string_starts_with(pickup_name, "expedition_currency_") then
                return "material_expeditions_currency", meta
            end

            if _string_starts_with(pickup_name, "expedition_loot_small_") then
                return "material_expeditions_loot", meta
            end
        end

        if description == "loc_skulls_guns_servo_skull_interact_description"
            and _is_dark_rites_marker_scan_allowed() then
            return "dark_rites_servo_skull", meta
        end

        local key = tostring(pickup_name or "") .. "|"
            .. tostring(interaction_type or "") .. "|"
            .. tostring(icon or "") .. "|"
            .. tostring(description or "") .. "|"
            .. tostring(unit_name or "") .. "|"
            .. tostring(pickup_group or "")
        key = string_lower(key)

        if string_find(key, "grimoire", 1, true)
            or string_find(key, "scripture", 1, true)
            or string_find(key, "side_mission", 1, true)
            or string_find(key, "objective_side", 1, true)
            or string_find(key, "objective_pickup", 1, true)
            or string_find(key, "luggable", 1, true)
            or string_find(key, "forge_material", 1, true)
            or string_find(key, "tainted_skull", 1, true)
            or string_find(key, "saints_pickup", 1, true)
            or string_find(key, "stolen_rations", 1, true)
            or string_find(key, "penance_collectible", 1, true) then
            _log_once(key, "Unknown pickup: " .. key)
            return "pickup_unknown", meta
        end

        return nil, meta
    end

    function _safe_player_slot(player)
        local slot_fn = player and player.slot

        if not slot_fn then
            return nil
        end

        local ok_slot, slot = pcall(slot_fn, player)

        if ok_slot then
            return slot
        end

        return nil
    end

    function _marked_by_player_slot_for_unit(unit)
        if not _safe_unit_alive(unit) then
            return nil
        end

        local smart_tag_system = _safe_extension_system("smart_tag_system")
        local unit_tag = smart_tag_system and smart_tag_system.unit_tag

        if not unit_tag then
            return nil
        end

        local ok_tag, tag = pcall(unit_tag, smart_tag_system, unit)
        local tagger_player = tag and tag.tagger_player

        if not ok_tag or not tagger_player then
            return nil
        end

        local ok_player, player = pcall(tagger_player, tag)

        if not ok_player or not player then
            return nil
        end

        return _safe_player_slot(player)
    end

    function _classify_interactee(extension, unit)
        if not extension then
            return nil, nil
        end

        local interaction_type = nil
        local ui_interaction_type = nil
        local icon = nil
        local description = nil
        local interaction_type_fn = extension.interaction_type
        local ui_interaction_type_fn = extension.ui_interaction_type
        local interaction_icon_fn = extension.interaction_icon
        local description_fn = extension.description

        local ok_interaction_type, interaction_type_value = pcall(interaction_type_fn, extension)
        if ok_interaction_type then
            interaction_type = _safe_lower_string(interaction_type_value)
        end

        local ok_ui_interaction_type, ui_interaction_type_value = pcall(ui_interaction_type_fn, extension)
        if ok_ui_interaction_type then
            ui_interaction_type = _safe_lower_string(ui_interaction_type_value)
        end

        local ok_icon, icon_value = pcall(interaction_icon_fn, extension)
        if ok_icon then
            icon = _safe_lower_string(icon_value)
        end

        local ok_description, description_value = pcall(description_fn, extension)
        if ok_description then
            description = _safe_lower_string(description_value)
        end

        local unit_name = _safe_lower_string(_safe_unit_name(unit))
        local pickup_name = _safe_unit_pickup_name(unit)
        local pickups_by_name = Pickups and Pickups.by_name or nil
        local pickup_data = pickup_name and pickups_by_name and pickups_by_name[pickup_name] or nil
        local marked_by_player_slot = _marked_by_player_slot_for_unit(unit)

        local kind, meta = _classify_pickup_like(interaction_type, ui_interaction_type, icon, description, unit_name,
            pickup_name, pickup_data, marked_by_player_slot)

        if kind == "material_expeditions_loot" then
            meta.remnant_value = _expedition_loot_value_for_pickup_name(pickup_name)
            meta.is_player_drop = false
        elseif kind == "material_expeditions_loot_player_drop" then
            meta.remnant_value = _safe_expedition_player_drop_amount(unit)
            meta.is_player_drop = true
        end

        return kind, meta
    end

    -- Breed classification is a pure function of static tables, so cache the
    -- result per breed name (`false` marks breeds without a radar kind) to keep
    -- the string scans out of the per-minion scan loop.
    local _enemy_kind_by_breed_cache = {}

    function _classify_enemy_from_breed(breed_name)
        local cache_key = breed_name or ""
        local cached = _enemy_kind_by_breed_cache[cache_key]

        if cached ~= nil then
            return cached or nil
        end

        local key = string_lower(cache_key)
        local kind = nil

        if key == "chaos_daemonhost" or key == "chaos_mutator_daemonhost" or string_find(key, "daemonhost", 1, true) then
            kind = "enemy_daemonhost"
        elseif TWIN_BREEDS[key] or string_find(key, "twin_captain", 1, true) then
            kind = "enemy_karnak_twin"
        elseif CAPTAIN_BREEDS[key] or string_find(key, "captain", 1, true) then
            kind = "enemy_captain"
        elseif MONSTROSITY_BREEDS[key]
            or string_find(key, "beast_of_nurgle", 1, true)
            or string_find(key, "plague_ogryn", 1, true)
            or string_find(key, "chaos_spawn", 1, true)
            or string_find(key, "houndmaster", 1, true) then
            kind = "enemy_monstrosity"
        else
            local definition = ENEMY_RADAR_DEFINITIONS_BY_BREED[key]

            if definition then
                kind = definition.kind
            end
        end

        _enemy_kind_by_breed_cache[cache_key] = kind or false

        return kind
    end

    function _track_unit(unit, kind, source, meta)
        if not kind or not _is_trackable_unit_alive(unit, kind) then
            return
        end

        local tracked_units = mod._tracked_units

        if not _is_valid_expedition_item_for_current_section(kind, unit) then
            tracked_units[unit] = nil
            return
        end

        local existing = tracked_units[unit]
        local now = _safe_gameplay_time() or 0
        local position = meta and _copy_vector3(meta.position) or nil

        position = position or _safe_unit_position(unit)

        if existing then
            existing.kind = kind
            existing.source = source or existing.source
            existing.last_seen_t = now
            existing.position = position or existing.position

            if meta ~= nil then
                existing.meta = meta
            end
        else
            tracked_units[unit] = {
                kind = kind,
                source = source,
                last_seen_t = now,
                position = position,
                meta = meta,
            }
        end
    end

    function _clear_tracked_unit_from_source(unit, source)
        local tracked_units = mod._tracked_units
        local tracked = tracked_units and tracked_units[unit]

        if tracked and tracked.source == source then
            tracked_units[unit] = nil
        end
    end

    local function _clear_invalid_expedition_item_units()
        local tracked_units = mod._tracked_units

        for unit, data in pairs(tracked_units) do
            if data and not _is_valid_expedition_item_for_current_section(data.kind, unit) then
                tracked_units[unit] = nil
            end
        end
    end

    local function _reset_expedition_player_smart_tag_state()
        mod._last_expedition_in_safe_zone = nil
        mod._player_smart_tag_generation = 0
        mod._player_smart_tag_state_by_id = {}
    end

    local function _advance_expedition_player_smart_tag_generation()
        mod._player_smart_tag_generation = (tonumber(mod._player_smart_tag_generation) or 0) + 1
    end

    function _sync_expedition_item_state()
        if not _is_expedition_runtime() then
            mod._last_safe_zone_section_index = nil
            _reset_expedition_player_smart_tag_state()
            return
        end

        local game_mode = _safe_game_mode()
        if not game_mode then
            return
        end

        local current_in_safe_zone = _is_in_expedition_safe_zone()
        local previous_in_safe_zone = mod._last_expedition_in_safe_zone
        local current_safe_zone_section_index = _safe_current_safe_zone_section_index(game_mode)
        local previous_safe_zone_section_index = mod._last_safe_zone_section_index
        local sanctuary_transition = false

        if previous_in_safe_zone ~= nil and previous_in_safe_zone ~= current_in_safe_zone then
            sanctuary_transition = true
        end

        if current_safe_zone_section_index ~= nil then
            if previous_safe_zone_section_index ~= nil
                and previous_safe_zone_section_index ~= current_safe_zone_section_index then
                sanctuary_transition = true
                _clear_invalid_expedition_item_units()
            end

            mod._last_safe_zone_section_index = current_safe_zone_section_index
        end

        if sanctuary_transition then
            _advance_expedition_player_smart_tag_generation()
        end

        mod._last_expedition_in_safe_zone = current_in_safe_zone

        _clear_invalid_expedition_item_units()
    end

    function _idol_collectible_key(section_id, id)
        if section_id == nil or id == nil then
            return nil
        end

        return tostring(section_id) .. ":" .. tostring(id)
    end

    local function _remember_destroyed_idol_collectible(section_id, id)
        local collectible_key = _idol_collectible_key(section_id, id)

        if collectible_key ~= nil then
            mod._idol_destroyed_collectible_keys[collectible_key] = _safe_gameplay_time() or 0
        end
    end

    local function _remember_destroyed_idol_unit(unit)
        if unit ~= nil then
            mod._idol_destroyed_units[unit] = _safe_gameplay_time() or 0
        end
    end

    function _is_live_event_skulls_totem_unit(collectible_type, unit_data_breed_name, prop_data_name)
        return collectible_type == "nurgle_totem"
            or unit_data_breed_name == "nurgle_totem"
            or prop_data_name == "nurgle_totem"
    end

    function _clear_tracked_idol_by_collectible(section_id, id)
        local collectible_key = _idol_collectible_key(section_id, id)

        if collectible_key == nil then
            return
        end

        local now = _safe_gameplay_time() or 0
        local tracked_units = mod._tracked_units
        local destroyed_collectible_keys = mod._idol_destroyed_collectible_keys
        local destroyed_units = mod._idol_destroyed_units

        destroyed_collectible_keys[collectible_key] = now

        for unit, data in pairs(tracked_units) do
            local meta = data and data.meta or nil

            if data and data.source == "destructible_system"
                and (data.kind == "pickup_heretic_idol" or data.kind == "dark_rites_totem")
                and meta and meta.collectible_section_id == section_id and meta.collectible_id == id then
                tracked_units[unit] = nil
                destroyed_units[unit] = now
            end
        end
    end

    function _mark_idol_unit_destroyed(unit, extension)
        if unit == nil then
            return
        end

        local collectible_type = _safe_unit_collectible_type(unit)
        local is_live_event_skulls_totem = false

        if collectible_type ~= "heretic_idol" and _is_dark_rites_marker_scan_allowed() then
            local prop_data_name = _safe_unit_prop_data_name(unit)
            local unit_data_breed_name = _safe_unit_data_breed_name(unit)
            is_live_event_skulls_totem = _is_live_event_skulls_totem_unit(collectible_type, unit_data_breed_name, prop_data_name)
        end

        if collectible_type ~= "heretic_idol" and not is_live_event_skulls_totem then
            return
        end

        local collectible_data = _safe_destructible_collectible_data(extension)

        if collectible_data then
            _remember_destroyed_idol_collectible(collectible_data.section_id, collectible_data.id)
        end

        _remember_destroyed_idol_unit(unit)
        _clear_tracked_unit_from_source(unit, "destructible_system")
    end

    function _prune_destroyed_idol_state()
        local now = _safe_gameplay_time() or 0
        local destroyed_collectible_keys = mod._idol_destroyed_collectible_keys
        local destroyed_units = mod._idol_destroyed_units

        for collectible_key, destroyed_t in pairs(destroyed_collectible_keys) do
            if now - (destroyed_t or 0) > 60 then
                destroyed_collectible_keys[collectible_key] = nil
            end
        end

        for unit, destroyed_t in pairs(destroyed_units) do
            if now - (destroyed_t or 0) > 60 or not _safe_unit_alive(unit) then
                destroyed_units[unit] = nil
            end
        end
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

    local PLAYER_SMART_TAG_KINDS = {
        location_attention = true,
        location_ping = true,
        location_threat = true,
    }

    local function _safe_smart_tag_template_name(tag)
        local template_fn = tag and tag.template

        if not template_fn then
            return nil
        end

        local ok_template, template = pcall(template_fn, tag)
        if not ok_template or not template then
            return nil
        end

        local template_name = template.name or template.marker_type or nil

        return _safe_lower_string(template_name)
    end

    local function _safe_smart_tag_target_position(tag)
        local target_unit = nil
        local target_unit_fn = tag and tag.target_unit

        if target_unit_fn then
            local ok_unit, resolved_target_unit = pcall(target_unit_fn, tag)

            if ok_unit then
                target_unit = resolved_target_unit
            end
        end

        local target_location_fn = tag and tag.target_location

        if target_location_fn then
            local ok_location, target_location = pcall(target_location_fn, tag)
            local copied_location = ok_location and _copy_vector3(target_location) or nil

            if copied_location then
                return copied_location, target_unit
            end
        end

        if target_unit then
            return _safe_unit_position(target_unit), target_unit
        end

        return nil, nil
    end

    local function _smart_tag_state_by_id()
        local state_by_id = mod._player_smart_tag_state_by_id

        if type(state_by_id) ~= "table" then
            state_by_id = {}
            mod._player_smart_tag_state_by_id = state_by_id
        end

        return state_by_id
    end

    local function _current_player_smart_tag_generation()
        return tonumber(mod._player_smart_tag_generation) or 0
    end

    local function _is_valid_expedition_player_smart_tag_for_current_section(tag_id, target_unit)
        if not _is_expedition_runtime() then
            return true
        end

        local game_mode = _safe_game_mode()
        local active_section_index = _safe_expedition_active_section_index(game_mode)
        local current_generation = _current_player_smart_tag_generation()
        local state_by_id = _smart_tag_state_by_id()
        local tag_state = state_by_id[tag_id]

        if type(tag_state) ~= "table" then
            tag_state = {
                generation = current_generation,
                section_index = active_section_index,
            }
            state_by_id[tag_id] = tag_state
        end

        if tonumber(tag_state.generation) ~= current_generation then
            return false
        end

        if target_unit then
            local target_section_index = _safe_unit_expedition_section_index(game_mode, target_unit)

            if target_section_index ~= nil then
                if active_section_index ~= nil and target_section_index ~= active_section_index then
                    return false
                end

                if tag_state.section_index == nil then
                    tag_state.section_index = target_section_index
                end
            end
        end

        if active_section_index == nil then
            return true
        end

        if tag_state.section_index == nil then
            tag_state.section_index = active_section_index
            return true
        end

        return tag_state.section_index == active_section_index
    end

    local function _prune_player_smart_tag_states(seen_tag_ids)
        local state_by_id = mod._player_smart_tag_state_by_id

        if type(state_by_id) ~= "table" then
            return
        end

        for tag_id in pairs(state_by_id) do
            if not seen_tag_ids[tag_id] then
                state_by_id[tag_id] = nil
            end
        end
    end

    local function _safe_smart_tag_tagger_player(tag)
        local tagger_player_fn = tag and tag.tagger_player

        if not tagger_player_fn then
            return nil
        end

        local ok_player, player = pcall(tagger_player_fn, tag)

        if ok_player then
            return player
        end

        return nil
    end

    function _scan_player_tag_points()
        local smart_tag_system = _safe_extension_system("smart_tag_system")
        local all_tags = type(smart_tag_system) == "table" and rawget(smart_tag_system, "_all_tags") or nil

        if type(all_tags) ~= "table" then
            mod._player_smart_tag_state_by_id = {}
            return
        end

        local seen_tag_ids = _scratch_seen_player_tag_ids
        table_clear(seen_tag_ids)

        for tag_id, tag in pairs(all_tags) do
            local template_name = _safe_smart_tag_template_name(tag)

            if template_name and PLAYER_SMART_TAG_KINDS[template_name] then
                seen_tag_ids[tag_id] = true

                local position, target_unit = _safe_smart_tag_target_position(tag)

                if position and _is_valid_expedition_player_smart_tag_for_current_section(tag_id, target_unit) then
                    local tagger_player = _safe_smart_tag_tagger_player(tag)
                    local player_slot = _safe_player_slot(tagger_player)

                    _track_point(
                        string_format("player_smart_tag:%s", tostring(tag_id)),
                        template_name,
                        position,
                        "smart_tag_location",
                        {
                            marked_by_player_slot = player_slot,
                            player_slot = player_slot,
                        }
                    )
                end
            end
        end

        _prune_player_smart_tag_states(seen_tag_ids)
    end

    local PLAYER_SLOT_MASK_BY_SLOT = {
        1,
        2,
        4,
        8,
    }

    local function _marked_player_slots_result(marked_slots, marked_level_index)
        local local_player_slot = tonumber(_safe_player_slot(_local_player()))
        local preferred_local_slot = nil
        local first_numeric_slot = nil
        local first_raw_slot = nil
        local marked_player_slots_mask = 0

        for player_slot, level_index in pairs(marked_slots) do
            if marked_level_index == nil or level_index == marked_level_index then
                first_raw_slot = first_raw_slot or player_slot

                local numeric_slot = tonumber(player_slot)

                if numeric_slot then
                    if first_numeric_slot == nil or numeric_slot < first_numeric_slot then
                        first_numeric_slot = numeric_slot
                    end

                    if numeric_slot == local_player_slot then
                        preferred_local_slot = numeric_slot
                    end

                    local slot_mask = PLAYER_SLOT_MASK_BY_SLOT[numeric_slot]

                    if slot_mask then
                        marked_player_slots_mask = marked_player_slots_mask + slot_mask
                    end
                end
            end
        end

        return preferred_local_slot or first_numeric_slot or first_raw_slot,
            marked_player_slots_mask ~= 0 and marked_player_slots_mask or nil
    end

    local function _safe_navigation_handler_marked_by_slot(navigation_handler, level_index)
        if not navigation_handler or level_index == nil then
            return nil
        end

        local player_slots_by_level_marked = navigation_handler.player_slots_by_level_marked

        if type(player_slots_by_level_marked) == "function" then
            local ok_slots, player_slots, num_player_slots = pcall(
                player_slots_by_level_marked,
                navigation_handler,
                level_index
            )
            local numeric_num_player_slots = tonumber(num_player_slots)

            if ok_slots and type(player_slots) == "table"
                and numeric_num_player_slots and numeric_num_player_slots > 0 then
                return _marked_player_slots_result(player_slots)
            end
        end

        local player_slot_by_level_marked = navigation_handler.player_slot_by_level_marked

        if type(player_slot_by_level_marked) == "function" then
            local ok_slot, player_slot = pcall(player_slot_by_level_marked, navigation_handler, level_index)

            if ok_slot then
                local numeric_slot = tonumber(player_slot)
                local slot_mask = numeric_slot and PLAYER_SLOT_MASK_BY_SLOT[numeric_slot] or nil

                return player_slot, slot_mask
            end
        end

        local get_marked_player_slots = navigation_handler.get_marked_player_slots

        if type(get_marked_player_slots) == "function" then
            local ok_marked_slots, marked_slots = pcall(get_marked_player_slots, navigation_handler)

            if ok_marked_slots and type(marked_slots) == "table" then
                return _marked_player_slots_result(marked_slots, level_index)
            end
        end

        return nil
    end

    local function _safe_navigation_handler_level_completed(navigation_handler, level_index)
        local is_level_completed = navigation_handler and navigation_handler.is_level_completed

        if not is_level_completed or level_index == nil then
            return false
        end

        local ok, completed = pcall(is_level_completed, navigation_handler, level_index)

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

        local ok_unit, level_slot_unit = pcall(Level.unit_by_id, parent_level, level_slot_id)
        if not ok_unit or not level_slot_unit or not Unit or not Unit.world_position then
            return nil
        end

        local ok_position, world_position = pcall(Unit.world_position, level_slot_unit, 1)
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

        local safe_vector3_unbox = _safe_vector3_unbox
        local is_expedition_level_in_active_section = _is_expedition_level_in_active_section
        local safe_navigation_handler_level_completed = _safe_navigation_handler_level_completed
        local safe_navigation_handler_marked_by_slot = _safe_navigation_handler_marked_by_slot
        local safe_expedition_section_index_by_level_index = _safe_expedition_section_index_by_level_index
        local track_point = _track_point

        if kind == "expedition_objective_opportunity" then
            local location_id = 1

            for level_index, boxed_position in pairs(points) do
                local position = safe_vector3_unbox(boxed_position)
                local is_active_section = is_expedition_level_in_active_section(game_mode, active_section_index,
                    level_index)
                local is_completed = safe_navigation_handler_level_completed(navigation_handler, level_index)
                local section_index = is_active_section and
                    safe_expedition_section_index_by_level_index(game_mode, level_index) or nil

                if position and is_active_section and not is_completed then
                    local marked_by_player_slot, marked_player_slots_mask =
                        safe_navigation_handler_marked_by_slot(navigation_handler, level_index)

                    track_point(
                        string_format("%s:%s", tostring(kind), tostring(level_index)),
                        kind,
                        position,
                        "expedition_navigation",
                        {
                            objective_icon = _expedition_opportunity_icon(level_index),
                            objective_title_icon = _expedition_opportunity_title_icon(location_id),
                            marked_by_player_slot = marked_by_player_slot,
                            marked_player_slots_mask = marked_player_slots_mask,
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

        local entries = _scratch_expedition_registered_entries
        local entry_count = 0

        for level_index, boxed_position in pairs(points) do
            local position = safe_vector3_unbox(boxed_position)

            if position and is_expedition_level_in_active_section(game_mode, active_section_index, level_index) then
                entry_count = entry_count + 1
                local entry = entries[entry_count]

                if not entry then
                    entry = {}
                    entries[entry_count] = entry
                end

                entry.level_index = level_index
                entry.position = position
                entry.section_index = safe_expedition_section_index_by_level_index(game_mode, level_index)
            end
        end

        for i = entry_count + 1, #entries do
            entries[i] = nil
        end

        table_sort(entries, function(a, b)
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

        for index = 1, entry_count do
            local entry = entries[index]
            local level_index = entry.level_index
            local position = entry.position
            local marked_by_player_slot, marked_player_slots_mask =
                safe_navigation_handler_marked_by_slot(navigation_handler, level_index)

            track_point(
                string_format("%s:%s", tostring(kind), tostring(level_index)),
                kind,
                position,
                "expedition_navigation",
                {
                    objective_icon = EXPEDITION_OBJECTIVE_ICON_DEFAULTS[kind],
                    marked_by_player_slot = marked_by_player_slot,
                    marked_player_slots_mask = marked_player_slots_mask,
                    expedition_level_index = level_index,
                    expedition_section_index = entry.section_index,
                    objective_location_id = index,
                    objective_tag = objective_tag,
                }
            )
        end

        for i = 1, entry_count do
            local entry = entries[i]
            entry.level_index = nil
            entry.position = nil
            entry.section_index = nil
        end
    end

    local function _track_expedition_tagged_levels(game_mode, navigation_handler, current_location_index, level_tag, kind)
        if not game_mode or not game_mode.get_all_levels_of_specified_tag or current_location_index == nil then
            return
        end

        local ok_levels, levels = pcall(game_mode.get_all_levels_of_specified_tag, game_mode, current_location_index,
            { [level_tag] = true })
        if not ok_levels or type(levels) ~= "table" then
            return
        end

        for i = 1, #levels do
            local level_data = levels[i]
            local position = _safe_expedition_level_slot_position(level_data)

            if position then
                local level_index = _safe_expedition_level_index(level_data and level_data.level or nil)
                local marked_by_player_slot, marked_player_slots_mask =
                    _safe_navigation_handler_marked_by_slot(navigation_handler, level_index)

                _track_point(
                    string_format("%s:%s:%s", tostring(kind), tostring(level_index or i),
                        tostring(level_data and level_data.reference_name or i)),
                    kind,
                    position,
                    "expedition_level_tag",
                    {
                        objective_icon = EXPEDITION_OBJECTIVE_ICON_DEFAULTS[kind],
                        marked_by_player_slot = marked_by_player_slot,
                        marked_player_slots_mask = marked_player_slots_mask,
                        expedition_level_index = level_index,
                        objective_tag = level_tag,
                        reference_name = level_data and level_data.reference_name or nil,
                        level_name = level_data and level_data.level_name or nil,
                    }
                )
            end
        end
    end

    function _scan_expedition_objectives()
        mod._tracked_points = {}

        if not _is_expedition_runtime() then
            return
        end

        local game_mode = _safe_game_mode()
        if not game_mode then
            return
        end

        local navigation_handler = nil
        local get_navigation_handler = game_mode.get_navigation_handler

        if get_navigation_handler then
            local ok_navigation, value = pcall(get_navigation_handler, game_mode)
            if ok_navigation then
                navigation_handler = value
            end
        end

        local current_location_index = nil
        local current_location_index_fn = game_mode.current_location_index

        if current_location_index_fn then
            local ok_location, value = pcall(current_location_index_fn, game_mode)
            if ok_location then
                current_location_index = value
            end
        end

        local active_section_index = _safe_expedition_active_section_index(game_mode) or current_location_index
        local track_expedition_registered_points = _track_expedition_registered_points

        if navigation_handler then
            local get_registered_opportunities = navigation_handler.get_registered_opportunities

            if get_registered_opportunities then
                local ok, opportunities = pcall(get_registered_opportunities, navigation_handler)
                if ok then
                    track_expedition_registered_points(game_mode, navigation_handler, active_section_index,
                        opportunities,
                        "expedition_objective_opportunity", "type_opportunity")
                end
            end

            local get_registered_exits = navigation_handler.get_registered_exits

            if get_registered_exits then
                local ok, exits = pcall(get_registered_exits, navigation_handler)
                if ok then
                    track_expedition_registered_points(game_mode, navigation_handler, active_section_index, exits,
                        "expedition_objective_transition", "type_transition")
                end
            end

            local get_registered_extractions = navigation_handler.get_registered_extractions

            if get_registered_extractions then
                local ok, extractions = pcall(get_registered_extractions, navigation_handler)
                if ok then
                    track_expedition_registered_points(game_mode, navigation_handler, active_section_index,
                        extractions,
                        "expedition_objective_extraction", "type_extraction")
                end
            end
        end

        _track_expedition_tagged_levels(game_mode, navigation_handler, current_location_index, "type_main_objective",
            "expedition_objective_main_objective")
        _track_expedition_tagged_levels(game_mode, navigation_handler, current_location_index, "type_arrival",
            "expedition_objective_arrival")
    end
end
