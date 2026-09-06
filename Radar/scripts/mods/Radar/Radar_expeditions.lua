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
    local math_sqrt = math.sqrt
    local string_find = string.find
    local string_format = string.format
    local string_lower = string.lower
    local string_match = string.match
    local table_sort = table.sort
    local table_concat = table.concat
    local getmetatable = getmetatable
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

    local MARTYR_SKULL_RIDDLE_POSITION_MATCH_DISTANCE_SQ = 0.01
    local MARTYR_SKULL_RIDDLE_SOLVE_DOOR_POSITION_MATCH_DISTANCE_SQ = 0.25
    local MARTYR_SKULL_RIDDLE_COORDINATE_FALLBACK_LIVE_UNIT_DISTANCE_SQ = 0.25

    local MARTYR_SKULL_RIDDLE_SIGNATURES_BY_MISSION = {
        cm_habs = {
            ["default|default|loc_interactable_button_01"] = {
                fallback = true,
                { x = 143.653, y = -157.591, z = -13.257 },
            },
            ["default|default|loc_interactable_button_02"] = {
                fallback = true,
                { x = 144.131, y = -157.116, z = -13.258 },
            },
            ["default|default|loc_interactable_button_03"] = {
                fallback = true,
                { x = 144.565, y = -156.677, z = -13.258 },
            },
            ["default|default|loc_interactable_prison_cells"] = {
                { x = 142.250, y = -170.223, z = -12.543 },
                { x = 140.248, y = -170.223, z = -12.543 },
            },
            ["default|default|loc_interactable_security_switch"] = {
                { x = 142.749, y = -161.852, z = -12.526 },
            },
        },
        cm_archives = {
            ["default|default|loc_interaction_chandelier"] = {
                { x = -65.260, y = 102.926, z = 2.356 },
                { x = -65.950, y = 77.582, z = 2.396 },
                { x = -82.659, y = 103.048, z = 4.354 },
                { x = -83.250, y = 77.526, z = 4.400 },
                { x = -99.303, y = 103.019, z = 4.371 },
            },
        },
        cm_raid = {
            ["default|puzzle|loc_interactable_gate"] = {
                { x = -288.418, y = -276.372, z = -24.939 },
                { x = -294.552, y = -289.393, z = -27.135 },
            },
            ["default|puzzle|loc_interactable_key"] = {
                { x = -292.131, y = -290.854, z = -21.719 },
                { x = -313.701, y = -239.565, z = -24.006 },
            },
            ["default|default|loc_interactable_gate|#id[0cdc9d780a3425c5]"] = {
                { x = -287.903, y = -278.082, z = -26.492 },
                { x = -296.225, y = -289.884, z = -28.430 },
            },
            ["setup_breach_charge|default|loc_action_interaction_setup_breach_charge"] = {
                { x = -290.934, y = -298.562, z = -21.312 },
            },
        },
        dm_propaganda = {
            ["default|default|loc_interactable_skull_weight"] = {
                { x = 22.907, y = 32.243, z = 2.204 },
            },
            ["default|default|loc_interactable_trash_bin"] = {
                { x = 22.737, y = 32.175, z = 2.949 },
            },
            ["default|puzzle|loc_interactable_skull_weight"] = {
                { x = 2.261, y = -2.895, z = 4.014 },
            },
        },
        dm_stockpile = {
            ["default|puzzle|loc_interactable_crane"] = {
                { x = -121.067, y = 155.778, z = 13.462 },
                { x = -121.566, y = 156.419, z = 13.462 },
                { x = -122.064, y = 157.061, z = 13.462 },
                { x = -122.563, y = 157.702, z = 13.462 },
            },
        },
        dm_forge = {
            ["default|default|loc_interactable_button"] = {
                { x = -8.578, y = 37.113, z = 5.007 },
            },
            ["default|default|loc_interactable_button|#id[e9b4edfaf3e74a23]"] = {
                { x = 60.767, y = -5.137, z = -11.409 },
            },
        },
        dm_rise = {
            ["default|default|loc_interactable_power"] = {
                { x = -120.004, y = -79.463, z = -21.270 },
                { x = -125.952, y = -85.401, z = -21.270 },
            },
            ["moveable_platform|default|loc_interactable_elevator_controls"] = {
                { x = -120.148, y = -73.951, z = -23.000 },
                { x = -120.148, y = -73.951, z = -11.000 },
                { x = -131.461, y = -85.265, z = -11.000 },
            },
        },
        fm_armoury = {
            ["default|default|loc_interactable_gate|#id[97214c4425c8caf6]"] = {
                { x = -264.935, y = -117.707, z = -11.452 },
            },
            ["default|default|loc_interactable_power"] = {
                { x = -268.635, y = -114.754, z = -11.867 },
            },
            ["default|default|loc_interactable_valve"] = {
                { x = -257.823, y = -119.245, z = -11.690 },
            },
        },
        fm_cargo = {
            ["default|puzzle|loc_interactable_shower"] = {
                { x = -91.864, y = -40.848, z = 1.044 },
                { x = -97.586, y = -35.261, z = 1.044 },
                { x = -102.470, y = -37.313, z = 1.044 },
                { x = -114.491, y = -33.777, z = 1.044 },
            },
        },
        fm_resurgence = {
            ["default|puzzle|loc_interactable_valve"] = {
                { x = 143.984, y = 119.827, z = -2.750 },
                { x = 144.515, y = 119.297, z = -2.750 },
                { x = 145.045, y = 118.766, z = -2.750 },
                { x = 145.575, y = 118.236, z = -2.750 },
            },
        },
        hm_complex = {
            ["default|default|loc_interactable_candle"] = {
                { x = -250.027, y = 103.021, z = -22.079 },
                { x = -249.219, y = 105.886, z = -22.147 },
                { x = -246.302, y = 106.784, z = -22.077 },
                { x = -243.328, y = 105.864, z = -22.029 },
                { x = -242.171, y = 103.021, z = -22.085 },
                { x = -243.358, y = 100.062, z = -22.057 },
                { x = -246.182, y = 99.176, z = -22.067 },
                { x = -248.785, y = 100.552, z = -22.067 },
            },
        },
        hm_strain = {
            ["default|default|loc_interactable_button"] = {
                { x = 16.000, y = 91.000, z = -48.046 },
            },
            ["default|puzzle|loc_interactable_projector"] = {
                { x = 7.496, y = 88.728, z = -48.768 },
                { x = 7.496, y = 96.885, z = -48.768 },
            },
        },
        km_enforcer = {
            ["default|default|loc_interactable_prison_cells"] = {
                { x = -391.067, y = -57.326, z = 18.635 },
            },
            ["default|puzzle|loc_interactable_lever_small"] = {
                { x = -340.266, y = -57.970, z = 19.202 },
            },
            ["default|default|loc_interactable_signal"] = {
                { x = -365.904, y = -34.790, z = 18.626 },
            },
            ["default|puzzle|loc_interactable_security_gate"] = {
                { x = -394.273, y = -65.442, z = 18.559 },
                { x = -392.187, y = -63.042, z = 18.559 },
                { x = -392.708, y = -63.642, z = 18.559 },
                { x = -393.700, y = -64.783, z = 18.559 },
            },
            ["default|default|loc_interactable_button|#id[97214c4425c8caf6]"] = {
                { x = -374.960, y = -26.918, z = 18.626 },
            },
            ["default|default|loc_interactable_button|#id[dfbf44eee4048cb3]"] = {
                { x = -404.777, y = -48.632, z = 19.460 },
            },
        },
        km_station = {
            ["default|puzzle|loc_interactable_valve"] = {
                { x = -1.340, y = -176.501, z = -8.621 },
                { x = -6.098, y = -204.798, z = -10.511 },
                { x = 9.483, y = -229.324, z = -5.663 },
                { x = 44.075, y = -214.487, z = 2.128 },
                { x = 51.270, y = -219.523, z = -1.389 },
            },
        },
        lm_cooling = {
            ["default|puzzle|loc_interactable_key"] = {
                { x = -39.311, y = -181.093, z = -18.938 },
            },
            ["default|puzzle|loc_interactable_locker"] = {
                { x = -40.480, y = -215.426, z = -21.998 },
                { x = -41.298, y = -215.202, z = -22.997 },
            },
        },
    }

    local MARTYR_SKULL_RIDDLE_FALLBACK_POSITIONS_BY_MISSION = {}

    for mission_name, mission_signatures in pairs(MARTYR_SKULL_RIDDLE_SIGNATURES_BY_MISSION) do
        local fallback_positions = nil

        for _, entry in pairs(mission_signatures) do
            if type(entry) == "table" and entry.fallback == true then
                fallback_positions = fallback_positions or {}

                for i = 1, #entry do
                    fallback_positions[#fallback_positions + 1] = entry[i]
                end
            end
        end

        if fallback_positions then
            MARTYR_SKULL_RIDDLE_FALLBACK_POSITIONS_BY_MISSION[mission_name] = fallback_positions
        end
    end

    function _martyr_skull_riddle_fallback_mission_name()
        local mission_name = _safe_mission_name()

        if mission_name and MARTYR_SKULL_RIDDLE_FALLBACK_POSITIONS_BY_MISSION[mission_name] then
            return mission_name
        end

        return nil
    end

    local MARTYR_SKULL_RIDDLE_SOLVE_DOORS_BY_MISSION = {
        cm_habs = {
            require_all = true,
            { x = 142.246, y = -170.633, z = -14.345, label = "prison_cell_door_a" },
            { x = 136.254, y = -170.615, z = -14.345, label = "prison_cell_door_b" },
        },
        dm_rise = {
            require_all = true,
            { x = -130.224, y = -89.331, z = -23.000, label = "skull_path_door_a" },
            { x = -132.732, y = -81.211, z = -23.000, label = "skull_path_door_b" },
        },
        fm_cargo = {
            { x = -103.178, y = -52.162, z = 1.044, label = "skull_door" },
        },
        km_enforcer = {
            { x = -405.051, y = -49.056, z = 17.710, label = "skull_room_door" },
        },
    }

    local MARTYR_SKULL_RIDDLE_DOOR_DEBUG_POINTS_BY_MISSION = {
        dm_forge = {
            { x = -8.578, y = 37.113, z = 5.007, label = "riddle_button" },
        },
        fm_cargo = {
            { x = -97.7419, y = -51.6034, z = 1.7982, label = "skull_marker" },
        },
    }

    local function _martyr_skull_riddle_signature(interaction_type, ui_interaction_type, description)
        return tostring(interaction_type or "") .. "|"
            .. tostring(ui_interaction_type or "") .. "|"
            .. tostring(description or "")
    end

    local function _martyr_skull_riddle_unit_signature(interaction_type, ui_interaction_type, description, unit_name)
        return _martyr_skull_riddle_signature(interaction_type, ui_interaction_type, description) .. "|"
            .. tostring(unit_name or "")
    end

    local function _matches_martyr_skull_riddle_entry(entry, unit)
        if entry == true then
            return true
        end

        if not entry or not unit then
            return false
        end

        local position = _safe_unit_position(unit)

        if not position then
            return false
        end

        for i = 1, #entry do
            if _distance_squared(position, entry[i]) <= MARTYR_SKULL_RIDDLE_POSITION_MATCH_DISTANCE_SQ then
                return true
            end
        end

        return false
    end

    local function _has_mission_martyr_skull_riddle_signature(interaction_type, ui_interaction_type, description,
                                                              unit_name, unit)
        if not description then
            return false
        end

        local mission_name = _safe_mission_name()
        local mission_signatures = mission_name and MARTYR_SKULL_RIDDLE_SIGNATURES_BY_MISSION[mission_name] or nil

        if not mission_signatures then
            return false
        end

        local signature = _martyr_skull_riddle_signature(interaction_type, ui_interaction_type, description)
        if _matches_martyr_skull_riddle_entry(mission_signatures[signature], unit) then
            return true
        end

        return _matches_martyr_skull_riddle_entry(mission_signatures[_martyr_skull_riddle_unit_signature(
            interaction_type, ui_interaction_type, description, unit_name)], unit)
    end

    local function _is_current_mission_martyr_skull_riddle_solved()
        local solved_by_mission = mod._martyr_skull_riddle_solved_by_mission
        local mission_name = solved_by_mission and _safe_mission_name() or nil

        return mission_name ~= nil and solved_by_mission[mission_name] == true
    end

    function _should_scan_hidden_martyr_skull_riddle_interactables()
        if _is_current_mission_martyr_skull_riddle_solved() then
            return false
        end

        local mission_name = _safe_mission_name()

        return mission_name ~= nil and MARTYR_SKULL_RIDDLE_SIGNATURES_BY_MISSION[mission_name] ~= nil
    end

    local function _mark_martyr_skull_riddle_solved(mission_name, reason, unit)
        if not mission_name then
            return
        end

        local solved_by_mission = mod._martyr_skull_riddle_solved_by_mission

        if not solved_by_mission then
            solved_by_mission = {}
            mod._martyr_skull_riddle_solved_by_mission = solved_by_mission
        end

        if solved_by_mission[mission_name] == true then
            return
        end

        solved_by_mission[mission_name] = true

        if mod:get("debug_mode") == true then
            local position = _safe_unit_position(unit)
            local x, y, z = _vector3_components(position)
            local position_text = "nil"

            if _is_finite_number(x) and _is_finite_number(y) and _is_finite_number(z) then
                position_text = string_format("%.3f,%.3f,%.3f", x, y, z)
            end

            _log_once("martyr_skull_riddle_solved:" .. tostring(mission_name), string_format(
                "Martyr's Skull riddle solved: mission=%s reason=%s unit_name=%s position=%s",
                tostring(mission_name),
                tostring(reason),
                tostring(_safe_lower_string(_safe_unit_name(unit))),
                position_text
            ))
        end
    end

    local function _is_martyr_skull_riddle_solve_door_open_state(state)
        return state == "open" or state == "open_fwd" or state == "open_bwd"
    end

    local function _is_matching_open_martyr_skull_riddle_solve_door(unit, extension, solve_door)
        if not _safe_unit_alive(unit) or not extension then
            return false
        end

        local position = _safe_unit_position(unit)

        if not position or _distance_squared(position, solve_door) >
            MARTYR_SKULL_RIDDLE_SOLVE_DOOR_POSITION_MATCH_DISTANCE_SQ then
            return false
        end

        if _is_martyr_skull_riddle_solve_door_open_state(rawget(extension, "_current_state")) then
            return true
        end

        if solve_door.solved_when_can_open == true then
            local can_open = extension.can_open

            if can_open then
                local ok, value = pcall(can_open, extension)

                return ok and value == true or false
            end
        end

        return false
    end

    function _sync_martyr_skull_riddle_solve_state()
        local mission_name = _safe_mission_name()
        local solve_doors = mission_name and MARTYR_SKULL_RIDDLE_SOLVE_DOORS_BY_MISSION[mission_name] or nil

        if not solve_doors or _is_current_mission_martyr_skull_riddle_solved() then
            return
        end

        local door_map = _safe_unit_to_extension_map("door_system")

        if not door_map then
            return
        end

        if solve_doors.require_all == true then
            local last_open_unit = nil

            for i = 1, #solve_doors do
                local solve_door = solve_doors[i]
                local is_open = false

                for unit, extension in pairs(door_map) do
                    if _is_matching_open_martyr_skull_riddle_solve_door(unit, extension, solve_door) then
                        is_open = true
                        last_open_unit = unit
                        break
                    end
                end

                if not is_open then
                    return
                end
            end

            _mark_martyr_skull_riddle_solved(mission_name, "doors_open", last_open_unit)
            return
        end

        for unit, extension in pairs(door_map) do
            for i = 1, #solve_doors do
                if _is_matching_open_martyr_skull_riddle_solve_door(unit, extension, solve_doors[i]) then
                    _mark_martyr_skull_riddle_solved(mission_name, "door_open", unit)
                    return
                end
            end
        end
    end

    local function _is_martyr_skull_riddle_interactable(interaction_type, ui_interaction_type, description, unit_name,
                                                        unit)
        if _is_current_mission_martyr_skull_riddle_solved() then
            return false
        end

        return _has_mission_martyr_skull_riddle_signature(interaction_type, ui_interaction_type, description, unit_name,
            unit)
    end

    local function _debug_position_text(position)
        local x, y, z = _vector3_components(position)

        if not _is_finite_number(x) or not _is_finite_number(y) or not _is_finite_number(z) then
            return "nil"
        end

        return string_format("%.3f,%.3f,%.3f", x, y, z)
    end

    local function _debug_unit_position_text(unit)
        return _debug_position_text(_safe_unit_position(unit))
    end

    local function _debug_log_classified_martyr_skull_riddle_interactable(interaction_type, ui_interaction_type, icon,
                                                                          description, unit_name, pickup_name,
                                                                          pickup_group, unit)
        if mod:get("debug_mode") ~= true then
            return
        end

        local position_text = _debug_unit_position_text(unit)
        local signature = _martyr_skull_riddle_signature(interaction_type, ui_interaction_type, description)
        local unit_signature = _martyr_skull_riddle_unit_signature(interaction_type, ui_interaction_type, description,
            unit_name)
        local key = string_lower("classified_martyr_skull_riddle_interactable:"
            .. tostring(_safe_mission_name()) .. "|"
            .. signature .. "|"
            .. unit_signature .. "|"
            .. position_text .. "|"
            .. tostring(pickup_name) .. "|"
            .. tostring(icon) .. "|"
            .. tostring(pickup_group))

        _log_once(key, string_format(
            "Classified Martyr's Skull riddle interactable: mission=%s kind=martyr_skull_riddle_interactable signature=%s unit_signature=%s position=%s interaction_type=%s ui_interaction_type=%s pickup_name=%s icon=%s description=%s unit_name=%s pickup_group=%s",
            tostring(_safe_mission_name()),
            signature,
            unit_signature,
            position_text,
            tostring(interaction_type),
            tostring(ui_interaction_type),
            tostring(pickup_name),
            tostring(icon),
            tostring(description),
            tostring(unit_name),
            tostring(pickup_group)
        ))
    end

    local function _debug_extension_call(extension, method_name)
        local method = extension and extension[method_name]

        if not method then
            return nil
        end

        local ok, value = pcall(method, extension)

        if ok then
            return value
        end

        return nil
    end

    local function _debug_number_text(value)
        if _is_finite_number(value) then
            return string_format("%.2f", value)
        end

        return tostring(value)
    end

    local function _nearest_martyr_skull_riddle_door_debug_point(mission_name, position)
        local points = MARTYR_SKULL_RIDDLE_DOOR_DEBUG_POINTS_BY_MISSION[mission_name]

        if not points or not position then
            return nil, nil
        end

        local best_label = nil
        local best_distance_sq = nil

        for i = 1, #points do
            local point = points[i]
            local distance_sq = _distance_squared(position, point)

            if not best_distance_sq or distance_sq < best_distance_sq then
                best_label = point.label
                best_distance_sq = distance_sq
            end
        end

        return best_label, best_distance_sq
    end

    function _debug_log_martyr_skull_door_candidates()
        if mod:get("debug_mode") ~= true then
            return
        end

        local mission_name = _safe_mission_name()

        if not mission_name or not MARTYR_SKULL_RIDDLE_SIGNATURES_BY_MISSION[mission_name] then
            return
        end

        local door_map = _safe_unit_to_extension_map("door_system")

        if not door_map then
            _log_once("martyr_skull_door_debug:no_door_map:" .. tostring(mission_name),
                "Door candidate scan unavailable: mission=" .. tostring(mission_name) .. " reason=no_door_system_map")
            return
        end

        for unit, extension in pairs(door_map) do
            if _safe_unit_alive(unit) and extension then
                local position = _safe_unit_position(unit)
                local position_text = _debug_unit_position_text(unit)
                local unit_name = _safe_lower_string(_safe_unit_name(unit))
                local current_state = rawget(extension, "_current_state")
                local start_state = rawget(extension, "_start_state")
                local door_type = rawget(extension, "_type")
                local open_type = rawget(extension, "_open_type")
                local allow_closing = rawget(extension, "_allow_closing")
                local self_closing_time = rawget(extension, "_self_closing_time")
                local control_panel_units = rawget(extension, "_control_panel_units")
                local control_panel_count = type(control_panel_units) == "table" and #control_panel_units or 0
                local can_open = _debug_extension_call(extension, "can_open")
                local can_close = _debug_extension_call(extension, "can_close")
                local nav_blocked = _debug_extension_call(extension, "nav_blocked")
                local last_state_change = _debug_extension_call(extension, "get_last_state_change_time")
                local nearest_label, nearest_distance_sq =
                    _nearest_martyr_skull_riddle_door_debug_point(mission_name, position)
                local nearest_distance = nearest_distance_sq and math_sqrt(nearest_distance_sq) or nil
                local key = string_format("martyr_skull_door_debug:%s|%s|%s|%s|%s",
                    tostring(mission_name),
                    tostring(unit_name),
                    position_text,
                    tostring(current_state),
                    _debug_number_text(last_state_change)
                )

                _log_once(key, string_format(
                    "Door candidate: mission=%s position=%s unit_name=%s state=%s start_state=%s type=%s open_type=%s allow_closing=%s self_closing_time=%s can_open=%s can_close=%s nav_blocked=%s last_state_change=%s control_panels=%s nearest_riddle_point=%s nearest_riddle_distance=%s",
                    tostring(mission_name),
                    position_text,
                    tostring(unit_name),
                    tostring(current_state),
                    tostring(start_state),
                    tostring(door_type),
                    tostring(open_type),
                    tostring(allow_closing),
                    _debug_number_text(self_closing_time),
                    tostring(can_open),
                    tostring(can_close),
                    tostring(nav_blocked),
                    _debug_number_text(last_state_change),
                    tostring(control_panel_count),
                    tostring(nearest_label),
                    _debug_number_text(nearest_distance)
                ))
            end
        end
    end

    -- Mission objective interactables come from the game's own objective
    -- extension systems, not from the HUD world marker list. The marker list was
    -- tried first and rejected: it only contains what the HUD is drawing right
    -- now, so objectives appeared late or not at all.
    --
    -- MissionObjectiveTargetExtension carries `_objective_name`, which ties each
    -- unit to a named objective, and MissionObjectiveSystem reports which
    -- objectives are active. That pairing is what keeps the ~105 objective units
    -- in a level down to the handful that currently matter.
    local MISSION_OBJECTIVE_TARGET_SYSTEM = "mission_objective_target_system"
    local MISSION_OBJECTIVE_ZONE_SYSTEM = "mission_objective_zone_system"
    -- Per-target scanned state lives here: each scannable unit carries _is_active,
    -- which the zone clears as the target is scanned. This is the only per-target
    -- completion signal that exists; the interactee reports active=true for the
    -- whole mission and the zone selection array carries no flags.
    local MISSION_OBJECTIVE_SCANNABLE_SYSTEM = "mission_objective_zone_scannable_system"
    local MISSION_OBJECTIVE_SOURCE = "mission_objective_system"

    -- Systems whose every unit is objective-specific by definition, so they need
    -- no active-objective confirmation. Counts are small (3 decoders, 16 zones in
    -- a Hab Dreyko run), which is why they can be shown wholesale.
    local MISSION_OBJECTIVE_DEDICATED_SOURCES = {
        { system = "decoder_device_system", kind = "mission_objective_hacking" },
        { system = "scanning_event_system", kind = "mission_objective_scanner" },
    }

    local MISSION_OBJECTIVE_DEDICATED_SOURCE_COUNT = #MISSION_OBJECTIVE_DEDICATED_SOURCES

    local MISSION_OBJECTIVE_MARKER_KINDS = {
        mission_objective_scanner = true,
        mission_objective_hacking = true,
        mission_objective_console = true,
        mission_objective_servo_skull = true,
        mission_objective_other = true,
    }

    -- Interaction types that name the device directly. `scanning` and
    -- `servo_skull_activator` are both confirmed from live mission logs.
    local MISSION_OBJECTIVE_KIND_BY_INTERACTION_TYPE = {
        servo_skull_activator = "mission_objective_servo_skull",
        servo_skull = "mission_objective_servo_skull",
        decoder_device = "mission_objective_hacking",
        decoding = "mission_objective_hacking",
    }

    -- Objective units that already classify as something else keep that kind, so
    -- the objective scan never relabels a luggable or its socket.
    local _mission_objective_kind_by_unit = {}
    local _scratch_mission_objective_kind_enabled = {}
    local _scratch_active_objective_names = {}
    local _scratch_seen_mission_objective_units = {}
    local _scratch_mission_objective_zone_units = {}

    -- Scan targets and similar objective steps never report themselves used;
    -- they simply stop being active once completed. Mirrors the Martyr's Skull
    -- fallback lifecycle: a unit observed active and later inactive is finished,
    -- while one that was never seen active is treated as still upcoming.
    local _mission_objective_lifecycle_by_unit = {}

    function _update_mission_objective_lifecycle(unit, active_state, used_state)
        local state = _mission_objective_lifecycle_by_unit[unit]

        if used_state == true then
            if not state then
                state = {}
                _mission_objective_lifecycle_by_unit[unit] = state
            end

            state.retired = true

            return
        end

        if active_state == true then
            if not state then
                state = {}
                _mission_objective_lifecycle_by_unit[unit] = state
            end

            state.seen_active = true
            state.retired = false
        elseif active_state == false and state and state.seen_active then
            state.retired = true
        end
    end

    function _is_mission_objective_unit_retired(unit)
        local state = _mission_objective_lifecycle_by_unit[unit]

        return state ~= nil and state.retired == true
    end

    function _reset_mission_objective_lifecycle()
        table_clear(_mission_objective_lifecycle_by_unit)
    end

    function _is_mission_objective_marker_kind(kind)
        return MISSION_OBJECTIVE_MARKER_KINDS[kind] == true
    end

    function _mission_objective_kind_for_interaction_type(interaction_type)
        return MISSION_OBJECTIVE_KIND_BY_INTERACTION_TYPE[interaction_type]
    end

    local function _any_mission_objective_kind_enabled()
        local enabled_by_kind = _scratch_mission_objective_kind_enabled
        local any_enabled = false

        for kind in pairs(MISSION_OBJECTIVE_MARKER_KINDS) do
            local enabled = _kind_enabled(kind)
            enabled_by_kind[kind] = enabled
            any_enabled = any_enabled or enabled
        end

        return any_enabled
    end

    -- MissionObjective exposes no accessor for its units, so the objective name
    -- is read straight off the instance and matched against the name each
    -- target unit stores.
    local function _refresh_active_objective_names()
        local names = _scratch_active_objective_names
        table_clear(names)

        local objective_system = _safe_extension_system(MISSION_OBJECTIVE_SOURCE)

        if type(objective_system) ~= "table" then
            return nil
        end

        -- Field read, never a call: see the note on _safe_zone_field. The
        -- objective system is server-authoritative and its methods drive live
        -- mission state.
        local active_objectives = rawget(objective_system, "_active_objectives")

        if type(active_objectives) ~= "table" then
            return nil
        end

        local found = false

        for key, value in pairs(active_objectives) do
            local objective = type(key) == "table" and key or (type(value) == "table" and value or nil)
            local name = objective and rawget(objective, "_name") or nil

            if type(name) == "string" then
                names[name] = true
                found = true

                _debug_log_active_objective_fields(name, objective)
            end
        end

        return found and names or nil
    end

    local function _safe_objective_target_name(extension)
        if type(extension) ~= "table" then
            return nil
        end

        local name = rawget(extension, "_objective_name")

        return type(name) == "string" and name or nil
    end

    -- Field reads only, for the same reason as the zone extension below.
    local function _safe_objective_target_field(extension, field_name)
        if type(extension) ~= "table" then
            return nil
        end

        return rawget(extension, field_name)
    end

    -- Read-only by design. MissionObjectiveZoneExtension owns
    -- _equip_auspex_to_players, _unequip_auspex_from_players, _deactivate_zone
    -- and _inform_skull_of_completion, and names like zone_finished are
    -- completion routines rather than queries. Calling into this class from a
    -- client mod changes live objective state, so only fields are ever read.
    local function _safe_zone_field(extension, field_name)
        if type(extension) ~= "table" then
            return nil
        end

        return rawget(extension, field_name)
    end

    -- Zone collections are sometimes arrays and sometimes unit-keyed sets, so
    -- both shapes are read the same way.
    local function _collection_unit(key, value)
        if value ~= nil and type(value) ~= "boolean" then
            return value
        end

        return key
    end

    -- A hacking device keeps its interactee active and unused for the whole
    -- mission, so the puzzle's own state is the only thing that says it is done.
    -- `_active` is not that signal: it only means a player currently has the
    -- puzzle open, so hiding on it made markers disappear while idle and appear
    -- while somebody was already solving them.
    local MISSION_OBJECTIVE_MINIGAME_SYSTEM = "minigame_system"
    local MISSION_OBJECTIVE_MINIGAME_COMPLETE_STATE = "complete"
    local MISSION_OBJECTIVE_MINIGAME_GAMEPLAY_STATE = "gameplay"
    local MISSION_OBJECTIVE_MINIGAME_WAITING = "waiting"
    local MISSION_OBJECTIVE_MINIGAME_ACTIVE = "active"

    -- Which of the two live states a running puzzle is in, so the marker can say
    -- whether it still needs somebody or already has one. A device that has not
    -- been started gets no state at all and keeps its category's colour, which
    -- is what the game itself shows before the puzzle is placed.
    local _minigame_state_by_unit = {}
    -- One meta table per unit, reused across scans: the state changes, the table
    -- does not, so a device being solved does not allocate on every pass.
    local _minigame_meta_by_unit = {}

    -- Walks the whole minigame map rather than looking units up one at a time:
    -- a mission carries a handful of these (2 in Core Research, 5 on the train),
    -- so one pass per scan is cheaper than a lookup per objective unit.
    local function _refresh_minigame_states()
        table_clear(_minigame_state_by_unit)

        local minigame_map = _safe_unit_to_extension_map(MISSION_OBJECTIVE_MINIGAME_SYSTEM)

        if type(minigame_map) ~= "table" then
            return
        end

        for unit, extension in pairs(minigame_map) do
            if type(extension) == "table" then
                local minigame = rawget(extension, "_minigame")
                local state = type(minigame) == "table" and rawget(minigame, "_current_state") or nil

                if state == MISSION_OBJECTIVE_MINIGAME_COMPLETE_STATE then
                    _minigame_state_by_unit[unit] = MISSION_OBJECTIVE_MINIGAME_COMPLETE_STATE
                elseif state == MISSION_OBJECTIVE_MINIGAME_GAMEPLAY_STATE then
                    -- Only a running puzzle has a colour of its own: `_active`
                    -- is the one field that says a player is at the device right
                    -- now, so a running puzzle without one is asking for
                    -- somebody rather than being worked on.
                    if rawget(extension, "_active") == true then
                        _minigame_state_by_unit[unit] = MISSION_OBJECTIVE_MINIGAME_ACTIVE
                    else
                        _minigame_state_by_unit[unit] = MISSION_OBJECTIVE_MINIGAME_WAITING
                    end
                end
            end
        end
    end

    -- Only units that actually carry a puzzle get a state, so every other
    -- objective marker keeps the shared objective tint. A solved puzzle keeps
    -- its marker too and falls back to that same tint: the devices stay part of
    -- the objective until it ends, and one blinking out and returning in red
    -- when it re-arms reads as something having gone wrong.
    function _minigame_marker_meta(unit, meta)
        local state = _minigame_state_by_unit[unit]

        if state == MISSION_OBJECTIVE_MINIGAME_COMPLETE_STATE then
            state = nil
        end

        if state == nil then
            -- A unit that had a state and lost it has to be told so. The tracked
            -- entry keeps its previous meta when none is supplied, which would
            -- otherwise leave a solved puzzle wearing the colour it had while
            -- running. The cached table is the one the entry holds, so clearing
            -- the field here clears it there.
            local cached = _minigame_meta_by_unit[unit]

            if cached ~= nil then
                cached.minigame_state = nil
            end

            return meta
        end

        if meta == nil then
            meta = _minigame_meta_by_unit[unit]

            if meta == nil then
                meta = {}
                _minigame_meta_by_unit[unit] = meta
            end
        end

        meta.minigame_state = state

        return meta
    end

    function _refresh_mission_objective_markers()
        table_clear(_mission_objective_kind_by_unit)

        local enabled = _any_mission_objective_kind_enabled()

        if enabled then
            _refresh_minigame_states()
        end

        return enabled
    end

    function _mission_objective_kind_for_unit(unit)
        return _mission_objective_kind_by_unit[unit]
    end

    -- Cheap test for the hidden-interactee path: a single extension call, so
    -- scanning every hidden interactee each tick stays affordable.
    function _hidden_mission_objective_kind(extension, unit)
        local kind = _mission_objective_kind_by_unit[unit]

        if kind then
            return kind
        end

        local interaction_type_fn = extension and extension.interaction_type

        if type(interaction_type_fn) ~= "function" then
            return nil
        end

        local ok_type, value = pcall(interaction_type_fn, extension)

        if not ok_type then
            return nil
        end

        return MISSION_OBJECTIVE_KIND_BY_INTERACTION_TYPE[_safe_lower_string(value)]
    end

    -- Interaction types owned exclusively by a more specific pass. A scan target
    -- is only ever a scanner marker while its zone selects it; once scanned it
    -- must disappear rather than fall through to the generic category. Luggable
    -- sockets have had their own marker kind since long before this scan, and a
    -- second marker on the same socket is pure duplication.
    local MISSION_OBJECTIVE_EXCLUSIVE_INTERACTION_TYPES = {
        scanning = true,
        luggable_socket = true,
    }

    local function _mission_objective_unit_kind(unit, interactee_map, default_kind)
        local interactee_extension = interactee_map and interactee_map[unit] or nil
        local interaction_type = nil

        if type(interactee_extension) == "table" then
            -- State first, kind second. A completed step reports itself used,
            -- and missions place several copies of the same device with only one
            -- armed at a time, so an inactive interactee is not the one the
            -- current step wants. Resolving the kind before these checks let
            -- every copy through.
            local used_fn = interactee_extension.used

            if type(used_fn) == "function" then
                local ok_used, used = pcall(used_fn, interactee_extension)

                if not ok_used or used == true then
                    return nil
                end
            end

            local active_fn = interactee_extension.active

            if type(active_fn) == "function" then
                local ok_active, active = pcall(active_fn, interactee_extension)

                if not ok_active or active ~= true then
                    return nil
                end
            end

            local interaction_type_fn = interactee_extension.interaction_type

            if type(interaction_type_fn) == "function" then
                local ok_type, value = pcall(interaction_type_fn, interactee_extension)
                interaction_type = ok_type and _safe_lower_string(value) or nil
            end
        end

        if _is_mission_objective_unit_retired(unit) then
            return nil
        end

        if interaction_type then
            local kind = MISSION_OBJECTIVE_KIND_BY_INTERACTION_TYPE[interaction_type]

            if kind then
                return kind
            end

            -- Owned by a more specific pass; never falls through to the generic
            -- category.
            if MISSION_OBJECTIVE_EXCLUSIVE_INTERACTION_TYPES[interaction_type] then
                return nil
            end
        end

        return default_kind or "mission_objective_other"
    end

    -- `objective_confirmed` says the caller has already established that this
    -- unit belongs to a live objective. The scan zone pass has: it checks its
    -- zone's own objective before selecting any target. Its targets must not
    -- then be re-judged by the objective the target system files them under,
    -- which is not always the one whose zone selected them.
    local function _claim_mission_objective_unit(unit, kind, enabled_by_kind, seen_units, objective_confirmed)
        if not kind or not enabled_by_kind[kind] or seen_units[unit] then
            return
        end

        -- Single choke point for retirement, so a step that has been completed
        -- cannot be re-claimed by any source.
        if _is_mission_objective_unit_retired(unit) then
            _debug_log_unclaimed_mission_objective_unit(kind, "retired", unit)

            return
        end

        if not objective_confirmed and _is_unit_of_inactive_objective(unit) then
            _debug_log_unclaimed_mission_objective_unit(kind, "inactive_objective", unit)

            return
        end

        local owned = mod._tracked_units[unit]

        -- Units another scan claimed keep their own classification, so luggables
        -- and their sockets are never relabelled. Units this scan already owns
        -- must still be re-confirmed every pass, otherwise the prune below drops
        -- them and they flicker.
        if owned ~= nil and owned.source ~= MISSION_OBJECTIVE_SOURCE then
            return
        end

        if not _is_trackable_unit_alive(unit, kind) then
            return
        end

        -- Destructible steps -- the ice over the gears, and the like -- report
        -- nothing at all through the objective system once they are broken: the
        -- objective only ends when the last of them is gone. Their health
        -- extension is the one per-unit completion signal they carry. Units
        -- without one read nil here and are unaffected.
        if _safe_health_alive(unit) == false then
            return
        end

        seen_units[unit] = true
        _mission_objective_kind_by_unit[unit] = kind
        _track_unit(unit, kind, MISSION_OBJECTIVE_SOURCE, _minigame_marker_meta(unit, nil))
    end

    -- The zone selection table is the only place a per-target scanned flag can
    -- live, so its exact shape is logged: key type, value type and value for
    -- each entry, alongside the zone's own progression counters. Keyed by the
    -- whole shape, so each distinct state during a scan is reported once and the
    -- table can be watched changing as targets are scanned.
    -- Scan targets carry no completion signal of their own: every scanning
    -- interactee reports active=true, used=false for the whole mission. The only
    -- per-target signal is inside the zone's own selection table, so it is read
    -- here rather than inferred from interactee state.
    --
    -- The table is trusted to mark scanned targets only when its own numbers
    -- agree with the zone's progression counter. If the shapes disagree the
    -- interpretation is dropped and every selected target stays visible, which
    -- is the previous behaviour rather than a guess that could hide live targets.
    local function _scanned_units_from_selection(scannables, progression)
        if progression == nil then
            return nil
        end

        local entry_count = 0
        local flagged_count = 0

        for _, value in pairs(scannables) do
            entry_count = entry_count + 1

            if type(value) ~= "boolean" then
                return nil
            end

            if value == true then
                flagged_count = flagged_count + 1
            end
        end

        if entry_count == 0 or flagged_count ~= progression then
            return nil
        end

        return true
    end

    -- Missing data never hides a target: an absent extension or field means the
    -- scannable stays visible, so a changed engine layout degrades to the old
    -- behaviour instead of blanking live objectives.
    local function _is_scannable_still_active(scannable_map, unit)
        local extension = scannable_map and scannable_map[unit] or nil

        if type(extension) ~= "table" then
            return true
        end

        local is_active = rawget(extension, "_is_active")

        if is_active == nil then
            return true
        end

        return is_active == true
    end

    -- Clients never receive the zone's selection: _select_scannable_units_for_event
    -- runs on the server, so a joining player sees _num_scannables_in_zone but an
    -- empty _selected_scannable_units. The scannable extensions themselves are
    -- replicated, so the selection is recovered from their _is_active flags.
    --
    -- Self-validating: the recovered set is only used when its size matches the
    -- zone's own outstanding count. A mismatch marks nothing and says so in the
    -- log, which keeps a misread flag from putting every scannable in the level
    -- on the radar.
    local function _track_active_scannables(scannable_map, expected, enabled_by_kind, seen_units)
        if type(scannable_map) ~= "table" or expected == nil or expected <= 0 then
            return
        end

        local active_count = 0

        for _, extension in pairs(scannable_map) do
            if type(extension) == "table" and rawget(extension, "_is_active") == true then
                active_count = active_count + 1
            end
        end

        -- Fewer active scannables than the zone reports outstanding is normal:
        -- the flag clears the moment a target is scanned, while the zone's
        -- progression counter catches up a tick later. Only a count larger than
        -- the zone expects means the flag is not understood, so equality would
        -- blank every marker for a frame after each scan.
        local trusted = active_count <= expected

        if trusted then
            for unit, extension in pairs(scannable_map) do
                if type(extension) == "table" and rawget(extension, "_is_active") == true then
                    _claim_mission_objective_unit(unit, "mission_objective_scanner", enabled_by_kind,
                        seen_units, true)
                end
            end
        end
    end

    local function _track_mission_objective_scan_zones(enabled_by_kind, active_names, seen_units, zone_units)
        local extension_map = _safe_unit_to_extension_map(MISSION_OBJECTIVE_ZONE_SYSTEM)

        if type(extension_map) ~= "table" then
            return
        end

        local scanner_enabled = enabled_by_kind.mission_objective_scanner == true
        local scannable_map = scanner_enabled and _safe_unit_to_extension_map(MISSION_OBJECTIVE_SCANNABLE_SYSTEM)
            or nil
        local expected_outstanding = 0
        local marked_from_selection = 0
        local has_active_zone = false
        -- Hoisted: the loop runs over every zone in the level on every scan.
        local log_zones = mod:get("debug_mode") == true

        for zone_unit, extension in pairs(extension_map) do
            zone_units[zone_unit] = true

            if scanner_enabled and active_names ~= nil then
                local selection_entries = -1
                local claimed_here = marked_from_selection
                local objective_name = _safe_objective_target_name(extension)
                local is_active_objective = type(objective_name) == "string"
                    and active_names[objective_name] == true
                local activated = _safe_zone_field(extension, "_activated") == true
                local progression = tonumber(_safe_zone_field(extension, "_current_progression"))
                local total = tonumber(_safe_zone_field(extension, "_num_scannables_in_zone"))
                local finished = progression ~= nil and total ~= nil and total > 0 and progression >= total

                if is_active_objective and activated and not finished then
                    has_active_zone = true

                    local outstanding = (total or 0) - (progression or 0)

                    if outstanding > 0 then
                        expected_outstanding = expected_outstanding + outstanding
                    end

                    -- Never the zone's full scannable list: that holds every
                    -- scannable in the level, not the ones selected for this run.
                    local scannables = _safe_zone_field(extension, "_selected_scannable_units")

                    if type(scannables) == "table" then
                        local scanned_is_true = _scanned_units_from_selection(scannables, progression)
                        local still_active = 0
                        selection_entries = 0

                        for _ in pairs(scannables) do
                            selection_entries = selection_entries + 1
                        end

                        for key, value in pairs(scannables) do
                            local unit = _collection_unit(key, value)
                            local scanned = scanned_is_true == true and value == true

                            if unit ~= nil and not scanned and _is_scannable_still_active(scannable_map, unit) then
                                still_active = still_active + 1
                                marked_from_selection = marked_from_selection + 1

                                _claim_mission_objective_unit(unit, "mission_objective_scanner", enabled_by_kind,
                                    seen_units, true)
                            end
                        end

                    end
                end

                if log_zones then
                    _debug_log_scan_zone_state(objective_name, is_active_objective, activated, progression, total,
                        finished, selection_entries, marked_from_selection - claimed_here, zone_unit)
                end
            end
        end

        if log_zones then
            _debug_log_scan_zone_summary(has_active_zone, marked_from_selection, expected_outstanding)
        end

        if has_active_zone and marked_from_selection == 0 then
            _track_active_scannables(scannable_map, expected_outstanding, enabled_by_kind, seen_units)
        end
    end

    -- The objective target system also holds pure position hints: luggable spawn
    -- points, socket placements and waypoints the game never makes reachable.
    -- They carry no state of their own and there is nothing to do at them, which
    -- is exactly what tells them apart -- a real step is either an interactee (a
    -- device, a console, a luggable) or a destructible with health (ice, a
    -- barricade). Applied only to the broad target system; the dedicated systems
    -- hold nothing but real devices.
    local function _is_actionable_objective_target(unit, interactee_map)
        if interactee_map ~= nil and interactee_map[unit] ~= nil then
            return true
        end

        -- nil means no health extension at all, false means destroyed; the claim
        -- itself drops the destroyed ones.
        return _safe_health_alive(unit) ~= nil
    end

    -- Whether an objective is one that mixes real steps with position hints.
    -- A luggable objective holds the cells and their sockets, which you can act
    -- on, alongside spawn points and waypoints, which you cannot -- so its bare
    -- units are hints. An objective made of nothing but bare units is different:
    -- there the bare units are the step, as with the train controls you destroy
    -- to stop the train, and filtering them would leave the objective unmarked.
    --
    -- Decided per objective rather than per pass, because missions run more than
    -- one at a time -- the train runs "stop the train" and "defuse the bombs"
    -- together.
    local _scratch_objective_has_actionable = {}
    local _scratch_objective_actionable_by_unit = {}
    -- `_add_marker_on_objective_start` is the level's own statement that it will
    -- mark this unit when the objective begins. Chasm Logistratum files nine
    -- possible cargo containers and the one that actually holds the cargo under
    -- one objective, identical in every other field, and only the real one has
    -- it set. Read per objective: when none of an objective's units claims a
    -- start marker the flag says nothing, and nothing is hidden.
    local _scratch_objective_has_start_marker = {}
    local _scratch_start_marker_by_unit = {}
    -- Objective-bound units whose objective is not live. The system pass already
    -- skips them, but the interactee pass reaches the same units by interaction
    -- type alone and used to mark them whatever the objective was doing, which
    -- left an unused hacking device drawn for the rest of the mission once its
    -- event had finished.
    local _scratch_inactive_objective_units = {}
    -- Bare objective steps -- the train controls destroyed to stop the train --
    -- carry no completion state anywhere: not an interactee, no health, in no
    -- system at all, and their own target extension never changes a field. The
    -- game's own world marker is the only thing that goes away when one is
    -- finished, so it stands in for the signal the unit does not have.
    local _scratch_world_marker_units = {}
    -- Latched for the mission rather than rebuilt each scan. "No unit of this
    -- objective has a marker" is ambiguous: it means either that the list does
    -- not describe this objective, or that every one of its units is finished.
    -- Rebuilt per scan it read the second case as the first, so the last unit's
    -- marker going away switched the filter off instead of retiring the marker.
    -- Once an objective has been seen in the list it stays trusted.
    local _objective_world_marker_seen = {}
    local _world_marker_units_available = false

    function _is_unit_of_inactive_objective(unit)
        return _scratch_inactive_objective_units[unit] == true
    end

    -- Actionability is evaluated once per unit here and read back below, so the
    -- health-extension lookup runs once per active objective unit per scan
    -- rather than twice.
    local function _refresh_objective_actionable_targets(extension_map, interactee_map, active_names)
        local has_actionable = _scratch_objective_has_actionable
        local actionable_by_unit = _scratch_objective_actionable_by_unit

        table_clear(has_actionable)
        table_clear(actionable_by_unit)
        table_clear(_scratch_objective_has_start_marker)
        table_clear(_scratch_start_marker_by_unit)

        table_clear(_scratch_world_marker_units)

        -- Guarded rather than called outright: a scan must not fail outright
        -- because one helper is missing, and without the list the filter simply
        -- does not run.
        _world_marker_units_available = _refresh_world_marker_units ~= nil
            and _refresh_world_marker_units(_scratch_world_marker_units) == true

        if type(extension_map) ~= "table" then
            return
        end

        for unit, extension in pairs(extension_map) do
            local objective_name = _safe_objective_target_name(extension)

            if objective_name ~= nil then
                if active_names ~= nil and active_names[objective_name] == true then
                    local actionable = _is_actionable_objective_target(unit, interactee_map)

                    actionable_by_unit[unit] = actionable

                    if actionable then
                        has_actionable[objective_name] = true
                    end

                    if _scratch_world_marker_units[unit] then
                        _objective_world_marker_seen[objective_name] = true
                    end

                    if _safe_objective_target_field(extension, "_add_marker_on_objective_start") == true then
                        _scratch_start_marker_by_unit[unit] = true
                        _scratch_objective_has_start_marker[objective_name] = true
                    end
                else
                    _scratch_inactive_objective_units[unit] = true
                end
            end
        end
    end

    local function _track_mission_objective_units(system_name, interactee_map, enabled_by_kind, active_names,
                                                  require_active_objective, seen_units, default_kind, skip_units)
        local extension_map = _safe_unit_to_extension_map(system_name)

        if type(extension_map) ~= "table" then
            return
        end

        local has_actionable = nil
        local actionable_by_unit = nil
        -- Hoisted: this runs for every unit in the target system on every scan.
        local log_filtered_hints = false

        if require_active_objective then
            has_actionable = _scratch_objective_has_actionable
            actionable_by_unit = _scratch_objective_actionable_by_unit
            log_filtered_hints = mod:get("debug_mode") == true
        end

        for unit, extension in pairs(extension_map) do
            local keep = not require_active_objective

            if require_active_objective then
                local objective_name = _safe_objective_target_name(extension)

                keep = objective_name ~= nil and active_names ~= nil and active_names[objective_name] == true

                if keep and _scratch_objective_has_start_marker[objective_name] == true
                    and _scratch_start_marker_by_unit[unit] ~= true then
                    -- An alternative the mission chose not to use.
                    keep = false

                    if log_filtered_hints then
                        _debug_log_filtered_objective_hint(objective_name, unit)
                    end
                end

                if keep then
                    if has_actionable[objective_name] == true then
                        keep = actionable_by_unit[unit] == true

                        if not keep and log_filtered_hints then
                            _debug_log_filtered_objective_hint(objective_name, unit)
                        end
                    elseif _world_marker_units_available
                        and _objective_world_marker_seen[objective_name] == true then
                        -- Only trusted for an objective the marker list demonstrably
                        -- covers: if not one of its units has a marker the list does
                        -- not describe this objective, and dropping them all would
                        -- hide the step rather than retire it.
                        keep = _scratch_world_marker_units[unit] == true
                    end
                end
            end

            if keep and not (skip_units and skip_units[unit]) then
                _claim_mission_objective_unit(unit, _mission_objective_unit_kind(unit, interactee_map, default_kind),
                    enabled_by_kind, seen_units)
            end
        end
    end

    -- Objective zones and targets are frequently not interactees at all, so they
    -- can never be reached through the interactee scan. This walks the objective
    -- systems directly and is the only path that can surface them.
    function _scan_mission_objective_targets(interactee_map)
        local tracked_units = mod._tracked_units
        local seen_units = _scratch_seen_mission_objective_units
        local zone_units = _scratch_mission_objective_zone_units
        table_clear(seen_units)
        table_clear(zone_units)
        table_clear(_scratch_inactive_objective_units)

        if _any_mission_objective_kind_enabled() then
            local enabled_by_kind = _scratch_mission_objective_kind_enabled
            local active_names = _refresh_active_objective_names()

            _refresh_objective_actionable_targets(_safe_unit_to_extension_map(MISSION_OBJECTIVE_TARGET_SYSTEM),
                interactee_map, active_names)

            _track_mission_objective_scan_zones(enabled_by_kind, active_names, seen_units, zone_units)

            for i = 1, MISSION_OBJECTIVE_DEDICATED_SOURCE_COUNT do
                local source = MISSION_OBJECTIVE_DEDICATED_SOURCES[i]

                _track_mission_objective_units(source.system, interactee_map, enabled_by_kind, nil, false, seen_units,
                    source.kind, nil)
            end

            -- Zone units also appear here; skipping them keeps the invisible
            -- trigger volumes off the radar.
            _track_mission_objective_units(MISSION_OBJECTIVE_TARGET_SYSTEM, interactee_map, enabled_by_kind,
                active_names, true, seen_units, nil, zone_units)
        end

        for unit, data in pairs(tracked_units) do
            if data and data.source == MISSION_OBJECTIVE_SOURCE and not seen_units[unit] then
                tracked_units[unit] = nil
            end
        end

        _debug_probe_marked_objective_markers(_scratch_active_objective_names)
        _debug_probe_objective_world_markers()
        _debug_probe_objective_target_fields()
    end

    -- Dropping the unit map keeps stale unit references out of the next mission.
    function _reset_mission_objective_marker_state()
        _reset_objective_state_probe()
        _reset_marked_objective_probe()
        _reset_world_marker_probe()
        _reset_target_field_probe()
        _reset_active_objective_probe()
        _reset_mission_objective_lifecycle()
        table_clear(_minigame_state_by_unit)
        table_clear(_minigame_meta_by_unit)
        table_clear(_mission_objective_kind_by_unit)
        table_clear(_scratch_active_objective_names)
        table_clear(_scratch_seen_mission_objective_units)
        table_clear(_scratch_mission_objective_zone_units)
        table_clear(_scratch_inactive_objective_units)
        table_clear(_scratch_world_marker_units)
        table_clear(_objective_world_marker_seen)
        table_clear(_scratch_objective_has_start_marker)
        table_clear(_scratch_start_marker_by_unit)
        _world_marker_units_available = false
    end


    -- A marker that outlives its objective gives no other trace: the kind says
    -- nothing about which pass claimed it, and the tracked entry is the only
    -- place the objective it belongs to and whether that objective is still live
    -- can be seen together. Read through the field helpers only; no method on an
    -- objective extension is ever called.
    local MISSION_OBJECTIVE_STATE_PROBE_INTERVAL = 2
    local _objective_state_probe_next_t = 0
    local _objective_state_probe_window_t = nil
    local _objective_state_probe_window_due = false

    -- Declared here rather than assigned from the reset above, which runs before
    -- these locals exist and would have written globals instead.
    function _reset_objective_state_probe()
        _objective_state_probe_next_t = 0
        _objective_state_probe_window_t = nil
        _objective_state_probe_window_due = false
    end

    -- One decision per scan, so the probe never walks its extension maps at the
    -- scan rate.
    function _objective_state_probe_due()
        if mod:get("debug_mode") ~= true then
            return false
        end

        local now = _safe_gameplay_time() or 0

        if now ~= _objective_state_probe_window_t then
            _objective_state_probe_window_t = now
            _objective_state_probe_window_due = now >= _objective_state_probe_next_t

            if _objective_state_probe_window_due then
                _objective_state_probe_next_t = now + MISSION_OBJECTIVE_STATE_PROBE_INTERVAL
            end
        end

        return _objective_state_probe_window_due
    end

    -- Every marker the objective scan is currently drawing, with the state that
    -- ought to retire it. A marker that outlives its step shows up as a line
    -- whose signature stops changing while the step itself is gone.
    local MISSION_OBJECTIVE_MARKER_PROBE_SYSTEMS = {
        "destructible_system",
        "health_system",
        "minigame_system",
        "interactee_system",
    }

    local MISSION_OBJECTIVE_MARKER_PROBE_SYSTEM_COUNT = #MISSION_OBJECTIVE_MARKER_PROBE_SYSTEMS
    local MISSION_OBJECTIVE_MARKER_PROBE_BUDGET = 80
    local _marker_probe_logs_left = MISSION_OBJECTIVE_MARKER_PROBE_BUDGET
    local _scratch_marker_probe_owners = {}
    -- `_log_once` reports nothing back, so the budget needs its own record of
    -- which states have already been logged.
    local _marker_probe_seen = {}

    function _reset_marked_objective_probe()
        _marker_probe_logs_left = MISSION_OBJECTIVE_MARKER_PROBE_BUDGET
        table_clear(_marker_probe_seen)
    end

    -- The game draws its own world marker for objective units, and its frame is
    -- an asset of the game's, not one this mod references. The marker widgets
    -- come back through `request_world_markers_list`, so the materials it is
    -- built from can be read off the live widget rather than guessed at.
    local MISSION_OBJECTIVE_WORLD_MARKER_SAMPLE_LIMIT = 3
    local MISSION_OBJECTIVE_WORLD_MARKER_FIELD_LIMIT = 24
    local MISSION_OBJECTIVE_WORLD_MARKER_DEPTH = 4
    local MISSION_OBJECTIVE_WORLD_MARKER_BUDGET = 24
    local MATERIAL_PREFIX = "content/ui/materials/"
    local _world_marker_probe_logs_left = MISSION_OBJECTIVE_WORLD_MARKER_BUDGET
    local _world_marker_probe_seen = {}
    local _scratch_world_marker_materials = {}

    function _reset_world_marker_probe()
        _world_marker_probe_logs_left = MISSION_OBJECTIVE_WORLD_MARKER_BUDGET
        table_clear(_world_marker_probe_seen)
    end

    -- Only strings that name a material, wherever they sit in the widget: the
    -- frame, the icon and the backplate are separate entries and none of them is
    -- at a predictable key.
    local function _debug_collect_materials(container, prefix, out, count, depth)
        for key, value in pairs(container) do
            if count >= MISSION_OBJECTIVE_WORLD_MARKER_FIELD_LIMIT then
                break
            end

            if type(value) == "string" then
                if value:sub(1, #MATERIAL_PREFIX) == MATERIAL_PREFIX then
                    count = count + 1
                    out[count] = prefix .. tostring(key) .. "=" .. value
                end
            elseif type(value) == "table" and depth > 1 then
                count = _debug_collect_materials(value, prefix .. tostring(key) .. ".", out, count, depth - 1)
            end
        end

        return count
    end

    -- An objective can file several alternatives under one name, one per stage,
    -- and run them one at a time -- the Daemonic Growth sites are stages 2, 4, 6,
    -- 8 and 10 of a single objective. Which stage is live is known only to the
    -- objective itself, so its own fields are reported here to find the one that
    -- says so. Field reads only: this is the class whose methods drive live
    -- mission state.
    local MISSION_OBJECTIVE_ACTIVE_FIELD_LIMIT = 24
    local MISSION_OBJECTIVE_ACTIVE_FIELD_BUDGET = 40
    local _active_objective_probe_logs_left = MISSION_OBJECTIVE_ACTIVE_FIELD_BUDGET
    local _active_objective_probe_seen = {}
    local _scratch_active_objective_fields = {}

    function _reset_active_objective_probe()
        _active_objective_probe_logs_left = MISSION_OBJECTIVE_ACTIVE_FIELD_BUDGET
        table_clear(_active_objective_probe_seen)
    end

    function _debug_log_active_objective_fields(name, objective)
        if _active_objective_probe_logs_left <= 0 or mod:get("debug_mode") ~= true then
            return
        end

        local fields = _scratch_active_objective_fields
        local count = 0

        table_clear(fields)

        for key, value in pairs(objective) do
            if count >= MISSION_OBJECTIVE_ACTIVE_FIELD_LIMIT then
                break
            end

            if type(key) == "string" then
                local value_type = type(value)
                local text = nil

                if value_type == "boolean" then
                    text = tostring(value)
                elseif value_type == "number" then
                    text = string_format("%g", value)
                elseif value_type == "string" then
                    text = value
                end

                if text ~= nil then
                    count = count + 1
                    fields[count] = key .. "=" .. text
                end
            end
        end

        local field_text = table_concat(fields, " ", 1, count)
        local key = "active_objective:" .. name .. "|" .. field_text

        if not _active_objective_probe_seen[key] then
            _active_objective_probe_seen[key] = true
            _active_objective_probe_logs_left = _active_objective_probe_logs_left - 1

            _log_once(key, string_format(
                "Active objective fields: mission=%s objective=%s %s",
                tostring(_safe_mission_name()),
                name,
                field_text
            ))
        end
    end

    -- What a marked objective unit's own target extension holds. `_ui_target_type`
    -- and the like are the level designer's description of the step, and are the
    -- most likely place a distinction the mod cannot otherwise see is recorded --
    -- which of a row of identical containers holds the cargo, or which target of
    -- an event is armed before the others.
    local MISSION_OBJECTIVE_TARGET_FIELD_SAMPLE = 6
    local MISSION_OBJECTIVE_TARGET_FIELD_LIMIT = 20
    local MISSION_OBJECTIVE_TARGET_FIELD_BUDGET = 40
    local _target_field_probe_logs_left = MISSION_OBJECTIVE_TARGET_FIELD_BUDGET
    local _target_field_probe_seen = {}
    local _scratch_target_fields = {}

    function _reset_target_field_probe()
        _target_field_probe_logs_left = MISSION_OBJECTIVE_TARGET_FIELD_BUDGET
        table_clear(_target_field_probe_seen)
    end

    -- One level only: the nested tables here are the owning system, which the
    -- marker report already names.
    local function _debug_collect_scalars(container, out, count)
        for key, value in pairs(container) do
            if count >= MISSION_OBJECTIVE_TARGET_FIELD_LIMIT then
                break
            end

            if type(key) == "string" then
                local value_type = type(value)
                local text = nil

                if value_type == "boolean" then
                    text = tostring(value)
                elseif value_type == "number" then
                    text = string_format("%g", value)
                elseif value_type == "string" then
                    text = value
                end

                if text ~= nil then
                    count = count + 1
                    out[count] = key .. "=" .. text
                end
            end
        end

        return count
    end

    function _debug_probe_objective_target_fields()
        if _target_field_probe_logs_left <= 0 or not _objective_state_probe_due() then
            return
        end

        local target_map = _safe_unit_to_extension_map(MISSION_OBJECTIVE_TARGET_SYSTEM)

        if type(target_map) ~= "table" then
            return
        end

        local mission_text = tostring(_safe_mission_name())
        local fields = _scratch_target_fields
        local sampled = 0

        for unit, data in pairs(mod._tracked_units) do
            if sampled >= MISSION_OBJECTIVE_TARGET_FIELD_SAMPLE or _target_field_probe_logs_left <= 0 then
                break
            end

            local kind = data and data.kind or nil
            local extension = kind ~= nil and _is_mission_objective_marker_kind(kind) and target_map[unit] or nil

            if type(extension) == "table" then
                sampled = sampled + 1

                table_clear(fields)

                local count = _debug_collect_scalars(extension, fields, 0)
                local position_text = _debug_unit_position_text(unit)
                local key = "objective_target_fields:" .. position_text

                if not _target_field_probe_seen[key] then
                    _target_field_probe_seen[key] = true
                    _target_field_probe_logs_left = _target_field_probe_logs_left - 1

                    _log_once(key, string_format(
                        "Objective target fields: mission=%s kind=%s position=%s %s",
                        mission_text,
                        tostring(kind),
                        position_text,
                        table_concat(fields, " ", 1, count)
                    ))
                end
            end
        end
    end

    function _debug_probe_objective_world_markers()
        if _world_marker_probe_logs_left <= 0 or not _objective_state_probe_due() then
            return
        end

        -- Guarded rather than called outright, like every other cross-module
        -- helper here: a missing one must not fail a scan.
        local world_markers_list = _safe_world_markers_list
        local markers = world_markers_list ~= nil and world_markers_list() or nil

        if type(markers) ~= "table" then
            return
        end

        local tracked_units = mod._tracked_units
        local mission_text = tostring(_safe_mission_name())
        local materials = _scratch_world_marker_materials
        local sampled = 0

        for i = 1, #markers do
            if sampled >= MISSION_OBJECTIVE_WORLD_MARKER_SAMPLE_LIMIT then
                break
            end

            local marker = markers[i]
            local unit = marker and marker.unit or nil
            local data = unit ~= nil and tracked_units[unit] or nil
            local kind = data and data.kind or nil

            -- Only markers on units this mod already treats as objectives, so
            -- the level's other markers are never walked.
            if kind ~= nil and _is_mission_objective_marker_kind(kind) then
                sampled = sampled + 1

                local widget = marker.widget

                table_clear(materials)

                local count = 0

                if type(widget) == "table" then
                    count = _debug_collect_materials(widget, "", materials, 0,
                        MISSION_OBJECTIVE_WORLD_MARKER_DEPTH)
                end

                local material_text = table_concat(materials, " ", 1, count)
                local key = "world_marker_materials:" .. tostring(marker.type) .. "|" .. material_text

                if not _world_marker_probe_seen[key] then
                    _world_marker_probe_seen[key] = true
                    _world_marker_probe_logs_left = _world_marker_probe_logs_left - 1

                    _log_once(key, string_format(
                        "World marker materials: mission=%s kind=%s type=%s position=%s %s",
                        mission_text,
                        tostring(kind),
                        tostring(marker.type),
                        _debug_unit_position_text(unit),
                        material_text
                    ))
                end
            end
        end
    end

    function _debug_probe_marked_objective_markers(active_names)
        if _marker_probe_logs_left <= 0 or not _objective_state_probe_due() then
            return
        end

        local target_map = _safe_unit_to_extension_map(MISSION_OBJECTIVE_TARGET_SYSTEM)
        local destructible_map = _safe_unit_to_extension_map("destructible_system")
        local mission_text = tostring(_safe_mission_name())
        local owners = _scratch_marker_probe_owners

        for unit, data in pairs(mod._tracked_units) do
            if _marker_probe_logs_left <= 0 then
                break
            end

            local kind = data and data.kind or nil

            if kind ~= nil and _is_mission_objective_marker_kind(kind) then
                local target_extension = type(target_map) == "table" and target_map[unit] or nil
                local objective_name = target_extension and _safe_objective_target_name(target_extension) or nil
                local objective_active = objective_name ~= nil and active_names ~= nil
                    and active_names[objective_name] == true
                local owner_count = 0

                table_clear(owners)

                for i = 1, MISSION_OBJECTIVE_MARKER_PROBE_SYSTEM_COUNT do
                    local system_map = _safe_unit_to_extension_map(MISSION_OBJECTIVE_MARKER_PROBE_SYSTEMS[i])

                    if type(system_map) == "table" and system_map[unit] ~= nil then
                        owner_count = owner_count + 1
                        owners[owner_count] = MISSION_OBJECTIVE_MARKER_PROBE_SYSTEMS[i]
                    end
                end

                local destructible = type(destructible_map) == "table" and destructible_map[unit] or nil
                local destructible_visible = destructible and _safe_destructible_visible(destructible) or nil
                local minigame_state = data.meta and data.meta.minigame_state or nil
                -- A bare step is retired by the game's own world marker going
                -- away. Whether this unit has one, and whether the list is
                -- trusted for its objective at all, is the whole of that gate.
                local world_marker = _scratch_world_marker_units[unit] == true
                local objective_covered = objective_name ~= nil
                    and _objective_world_marker_seen[objective_name] == true
                local position_text = _debug_unit_position_text(unit)
                local key = "objective_marker:" .. position_text
                    .. "|" .. tostring(kind)
                    .. "|" .. tostring(objective_name)
                    .. "|" .. tostring(objective_active)
                    .. "|" .. tostring(_safe_unit_alive(unit))
                    .. "|" .. tostring(_safe_health_alive(unit))
                    .. "|" .. tostring(destructible_visible)
                    .. "|" .. tostring(minigame_state)
                    .. "|" .. tostring(world_marker) .. "|" .. tostring(objective_covered)
                    .. "|" .. tostring(_world_marker_units_available)
                    .. "|" .. table_concat(owners, ",", 1, owner_count)

                if not _marker_probe_seen[key] then
                    _marker_probe_seen[key] = true
                    _marker_probe_logs_left = _marker_probe_logs_left - 1

                    _log_once(key, string_format(
                        "Objective marker state: mission=%s kind=%s objective=%s objective_active=%s source=%s alive=%s health_alive=%s destructible_visible=%s minigame_state=%s world_marker=%s objective_covered=%s marker_list=%s owners=%s position=%s",
                        mission_text,
                        tostring(kind),
                        tostring(objective_name),
                        tostring(objective_active),
                        tostring(data.source),
                        tostring(_safe_unit_alive(unit)),
                        tostring(_safe_health_alive(unit)),
                        tostring(destructible_visible),
                        tostring(minigame_state),
                        tostring(world_marker),
                        tostring(objective_covered),
                        tostring(_world_marker_units_available),
                        table_concat(owners, ",", 1, owner_count),
                        position_text
                    ))
                end
            end
        end
    end

    -- The scan zone pass is the only path that can surface scan targets, and it
    -- can produce nothing for several different reasons -- a dormant objective, a
    -- zone that never reports itself activated, a selection table that is empty
    -- because it is server-only data. Each is reported so a run with no scan
    -- markers says which gate closed rather than leaving it to be guessed at.
    function _debug_log_scan_zone_state(objective_name, is_active_objective, activated, progression, total, finished,
                                        selection_entries, claimed, zone_unit)
        local position_text = _debug_unit_position_text(zone_unit)
        local signature = tostring(objective_name) .. "|" .. tostring(is_active_objective)
            .. "|" .. tostring(activated) .. "|" .. tostring(progression) .. "|" .. tostring(total)
            .. "|" .. tostring(finished) .. "|" .. tostring(selection_entries) .. "|" .. tostring(claimed)

        _log_once("scan_zone:" .. position_text .. "|" .. signature, string_format(
            "Scan zone state: mission=%s objective=%s objective_active=%s activated=%s progression=%s total=%s finished=%s selection_entries=%s claimed=%s position=%s",
            tostring(_safe_mission_name()),
            tostring(objective_name),
            tostring(is_active_objective),
            tostring(activated),
            tostring(progression),
            tostring(total),
            tostring(finished),
            tostring(selection_entries),
            tostring(claimed),
            position_text
        ))
    end

    function _debug_log_scan_zone_summary(has_active_zone, marked_from_selection, expected_outstanding)
        _log_once("scan_zone_summary:" .. tostring(has_active_zone) .. "|" .. tostring(marked_from_selection)
            .. "|" .. tostring(expected_outstanding), string_format(
            "Scan zone summary: mission=%s has_active_zone=%s marked_from_selection=%s expected_outstanding=%s fallback=%s",
            tostring(_safe_mission_name()),
            tostring(has_active_zone),
            tostring(marked_from_selection),
            tostring(expected_outstanding),
            tostring(has_active_zone and marked_from_selection == 0)
        ))
    end

    -- Claims dropped at the choke point, which is where a marker disappears with
    -- no other trace. Only reached by units that already passed their pass's own
    -- filters, so this stays rare rather than firing for every dormant unit.
    function _debug_log_unclaimed_mission_objective_unit(kind, reason, unit)
        if mod:get("debug_mode") ~= true then
            return
        end

        local position_text = _debug_unit_position_text(unit)

        _log_once("mission_objective_unclaimed:" .. kind .. "|" .. reason .. "|" .. position_text, string_format(
            "Mission objective marker not claimed: mission=%s kind=%s reason=%s position=%s",
            tostring(_safe_mission_name()),
            kind,
            reason,
            position_text
        ))
    end

    -- Names any objective whose bare units were treated as position hints, so a
    -- step that stops being marked can be identified from a debug run instead of
    -- another round of probing. Callers hoist the debug-mode check.
    function _debug_log_filtered_objective_hint(objective_name, unit)
        _log_once("mission_objective_hint_filtered:" .. objective_name, string_format(
            "Mission objective position hint filtered: mission=%s objective=%s position=%s",
            tostring(_safe_mission_name()),
            objective_name,
            _debug_unit_position_text(unit)
        ))
    end

    -- Records objective units that never reached classification, so a debug run
    -- shows which gate is filtering objectives that should be shown.
    -- The kind map is rebuilt after the interactee pass, so the kind is resolved
    -- from the interactee itself rather than read from a map that is empty at
    -- this point. Callers gate on debug mode, so the lookup only runs then.
    function _debug_log_rejected_mission_objective_marker(unit, extension, reason)
        local kind = _hidden_mission_objective_kind(extension, unit)

        if not kind then
            return
        end

        local position_text = _debug_unit_position_text(unit)

        _log_once("mission_objective_marker_rejected:" .. kind .. "|" .. reason .. "|" .. position_text, string_format(
            "Mission objective marker not shown: mission=%s kind=%s reason=%s position=%s unit_name=%s",
            tostring(_safe_mission_name()),
            kind,
            reason,
            position_text,
            tostring(_safe_unit_name(unit))
        ))
    end


    local function _classify_pickup_like(interaction_type, ui_interaction_type, icon, description, unit_name, pickup_name,
                                         pickup_data, marked_by_player_slot, unit, suppress_debug)
        local pickup_group = pickup_data and pickup_data.group or nil
        local meta = _pickup_meta(pickup_name, interaction_type, ui_interaction_type, icon, description,
            marked_by_player_slot)

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

        if _is_martyr_skull_riddle_interactable(interaction_type, ui_interaction_type, description, unit_name,
            unit) then
            _debug_log_classified_martyr_skull_riddle_interactable(interaction_type, ui_interaction_type, icon,
                description, unit_name, pickup_name, pickup_group, unit)

            return "martyr_skull_riddle_interactable", meta
        end

        -- Runs after every pickup classifier so units that already resolve to a
        -- known kind keep it; only otherwise-unclassified interactables can
        -- become mission objective markers. The interaction type is checked
        -- first because it names the device directly, while the unit map only
        -- says which objective system owns it.
        local mission_objective_kind = _mission_objective_kind_for_interaction_type(interaction_type)
            or _mission_objective_kind_for_unit(unit)

        if mission_objective_kind
            and not _is_mission_objective_unit_retired(unit)
            and not _is_unit_of_inactive_objective(unit) then
            return mission_objective_kind, _minigame_marker_meta(unit, meta)
        end

        local key = tostring(pickup_name or "") .. "|"
            .. tostring(interaction_type or "") .. "|"
            .. tostring(ui_interaction_type or "") .. "|"
            .. tostring(icon or "") .. "|"
            .. tostring(description or "") .. "|"
            .. tostring(unit_name or "") .. "|"
            .. tostring(pickup_group or "")
        key = string_lower(key)

        if not suppress_debug and mod:get("debug_mode") == true then
            local position_text = _debug_unit_position_text(unit)
            local signature = _martyr_skull_riddle_signature(interaction_type, ui_interaction_type, description)
            local unit_signature = _martyr_skull_riddle_unit_signature(interaction_type, ui_interaction_type,
                description, unit_name)

            _log_once("unclassified_interactable:" .. key .. "|" .. position_text, string_format(
                "Unclassified interactable: mission=%s signature=%s unit_signature=%s position=%s interaction_type=%s ui_interaction_type=%s pickup_name=%s icon=%s description=%s unit_name=%s pickup_group=%s",
                tostring(_safe_mission_name()),
                signature,
                unit_signature,
                position_text,
                tostring(interaction_type),
                tostring(ui_interaction_type),
                tostring(pickup_name),
                tostring(icon),
                tostring(description),
                tostring(unit_name),
                tostring(pickup_group)
            ))
        end

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
            if not suppress_debug then
                _log_once(key, "Unknown pickup: " .. key)
            end

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

    function _classify_interactee(extension, unit, suppress_debug, skip_marked_by_player_slot)
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
        local marked_by_player_slot = skip_marked_by_player_slot and nil or _marked_by_player_slot_for_unit(unit)

        local kind, meta = _classify_pickup_like(interaction_type, ui_interaction_type, icon, description, unit_name,
            pickup_name, pickup_data, marked_by_player_slot, unit, suppress_debug)

        if kind == "material_expeditions_loot" then
            meta.remnant_value = _expedition_loot_value_for_pickup_name(pickup_name)
            meta.is_player_drop = false
        elseif kind == "material_expeditions_loot_player_drop" then
            meta.remnant_value = _safe_expedition_player_drop_amount(unit)
            meta.is_player_drop = true
        end

        return kind, meta
    end

    local function _martyr_skull_riddle_fallback_position_for_unit(mission_name, unit)
        local fallback_positions = MARTYR_SKULL_RIDDLE_FALLBACK_POSITIONS_BY_MISSION[mission_name]

        if not fallback_positions then
            return nil, false
        end

        local fallback_state_by_position = mod._martyr_skull_riddle_fallback_state_by_position

        if fallback_state_by_position then
            for i = 1, #fallback_positions do
                local position = fallback_positions[i]
                local state = fallback_state_by_position[position]

                if state and state.unit == unit then
                    return position, true
                end
            end
        end

        local unit_position = _safe_unit_position(unit)

        if not unit_position then
            return nil, false
        end

        for i = 1, #fallback_positions do
            local position = fallback_positions[i]

            if _distance_squared(unit_position, position) <= MARTYR_SKULL_RIDDLE_POSITION_MATCH_DISTANCE_SQ then
                return position, false
            end
        end

        return nil, false
    end

    function _update_martyr_skull_riddle_fallback_state(extension, unit, active_state, used_state, show_marker_state,
                                                         is_verified_riddle, mission_name)
        local position = nil
        local is_associated = false

        position, is_associated = _martyr_skull_riddle_fallback_position_for_unit(mission_name, unit)

        if not position then
            return
        end

        local fallback_state_by_position = mod._martyr_skull_riddle_fallback_state_by_position

        if not fallback_state_by_position then
            fallback_state_by_position = {}
            mod._martyr_skull_riddle_fallback_state_by_position = fallback_state_by_position
        end

        local state = fallback_state_by_position[position]

        if not is_associated then
            if is_verified_riddle ~= true then
                local kind = _classify_interactee(extension, unit, true, true)

                if kind ~= "martyr_skull_riddle_interactable" then
                    return
                end
            end

            local preserve_retirement = state and state.retired == true

            state = state or {}
            fallback_state_by_position[position] = state
            state.unit = unit
            state.seen_active = false
            state.retired = preserve_retirement
        elseif not state then
            return
        end

        local was_seen_active = state.seen_active == true
        local was_retired = state.retired == true
        local was_active_state = state.active_state
        local was_used_state = state.used_state
        local was_show_marker_state = state.show_marker_state

        if used_state == true then
            state.retired = true
        elseif active_state == true then
            state.seen_active = true
            state.retired = false
        elseif active_state == false and state.seen_active == true then
            state.retired = true
        end

        state.active_state = active_state
        state.used_state = used_state
        state.show_marker_state = show_marker_state

        if mod:get("debug_mode") == true
            and (not is_associated
                or was_seen_active ~= (state.seen_active == true)
                or was_retired ~= (state.retired == true)
                or was_active_state ~= active_state
                or was_used_state ~= used_state
                or was_show_marker_state ~= show_marker_state) then
            local position_text = _debug_position_text(position)
            local key = string_format("martyr_skull_riddle_fallback_state:%s|%s|%s|%s|%s|%s|%s",
                tostring(mission_name),
                position_text,
                tostring(active_state),
                tostring(used_state),
                tostring(show_marker_state),
                tostring(state.seen_active == true),
                tostring(state.retired == true)
            )

            _log_once(key, string_format(
                "Martyr's Skull fallback state: mission=%s position=%s active=%s used=%s show_marker=%s seen_active=%s retired=%s",
                tostring(mission_name),
                position_text,
                tostring(active_state),
                tostring(used_state),
                tostring(show_marker_state),
                tostring(state.seen_active == true),
                tostring(state.retired == true)
            ))
        end
    end

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

    local function _is_martyr_skull_riddle_fallback_retired(position)
        local fallback_state_by_position = mod._martyr_skull_riddle_fallback_state_by_position
        local state = fallback_state_by_position and fallback_state_by_position[position]

        return state and state.retired == true or false
    end

    local function _has_live_martyr_skull_riddle_interactable_near_position(position)
        local tracked_units = mod._tracked_units

        if not tracked_units then
            return false
        end

        for unit, data in pairs(tracked_units) do
            if data
                and data.kind == "martyr_skull_riddle_interactable"
                and data.source == "interactee_system" then
                local tracked_position = data.position or _safe_unit_position(unit)

                if _distance_squared(tracked_position, position) <=
                    MARTYR_SKULL_RIDDLE_COORDINATE_FALLBACK_LIVE_UNIT_DISTANCE_SQ then
                    return true
                end
            end
        end

        return false
    end

    local function _martyr_skull_riddle_signature_parts(signature)
        local interaction_type, ui_interaction_type, description = string_match(signature, "^([^|]*)|([^|]*)|([^|]*)")

        return interaction_type, ui_interaction_type, description
    end

    function _scan_martyr_skull_riddle_coordinate_fallbacks()
        if not _kind_enabled("martyr_skull_riddle_interactable")
            or _is_current_mission_martyr_skull_riddle_solved() then
            return
        end

        local mission_name = _safe_mission_name()
        local mission_signatures = mission_name and MARTYR_SKULL_RIDDLE_SIGNATURES_BY_MISSION[mission_name] or nil

        if not mission_signatures then
            return
        end

        for signature, entry in pairs(mission_signatures) do
            if type(entry) == "table" and entry.fallback == true then
                local interaction_type, ui_interaction_type, description =
                    _martyr_skull_riddle_signature_parts(signature)

                for i = 1, #entry do
                    local position = entry[i]

                    if position
                        and not _is_martyr_skull_riddle_fallback_retired(position)
                        and not _has_live_martyr_skull_riddle_interactable_near_position(position) then
                        _track_point(
                            string_format("martyr_skull_riddle_fallback:%s:%s:%s", tostring(mission_name),
                                tostring(signature), tostring(i)),
                            "martyr_skull_riddle_interactable",
                            position,
                            "martyr_skull_riddle_coordinate_fallback",
                            {
                                interaction_type = interaction_type,
                                ui_interaction_type = ui_interaction_type,
                                interaction_icon = "content/ui/materials/hud/interactions/icons/default",
                                description = description,
                            }
                        )
                    end
                end
            end
        end
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
