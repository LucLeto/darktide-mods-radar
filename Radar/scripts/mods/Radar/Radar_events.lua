return function(env)
    setfenv(1, env)

    local mod = mod
    local pcall = pcall

    -- ----------------------------------------------------------------------------
    -- Constants
    -- ----------------------------------------------------------------------------

    local DARK_RITES_CIRCUMSTANCE_PREFIX = "skulls_guns"
    local LEGACY_SKULLS_CIRCUMSTANCE_PREFIX = "skulls_event_01"
    local DARK_RITES_CIRCUMSTANCE_VARIANT_PREFIX = DARK_RITES_CIRCUMSTANCE_PREFIX .. "_"
    local LEGACY_SKULLS_CIRCUMSTANCE_VARIANT_PREFIX = LEGACY_SKULLS_CIRCUMSTANCE_PREFIX .. "_"
    local PSYKHANIUM_MISSION_NAME = "tg_shooting_range"

    local LIVE_EVENT_ITEM_KIND_BY_PICKUP_NAME = {
        skulls_01_pickup = "pickup_tainted_skull",
        communications_hack_device = "pocketable_corrupted_auspex_scanner",
        live_event_leftover_01_pickup_small = "pickup_leftover",
        live_event_leftover_01_pickup_medium = "pickup_leftover",
        live_event_leftover_01_pickup_large = "pickup_leftover",
        stolen_rations_01_pickup_small = "pickup_stolen_rations",
        stolen_rations_01_pickup_medium = "pickup_stolen_rations",
    }

    local SAINTS_PICKUP_NAMES = {
        live_event_saints_01_pickup_small = true,
        live_event_saints_01_pickup_medium = true,
        live_event_saints_01_pickup_large = true,
        consumable = true,
    }

    -- ----------------------------------------------------------------------------
    -- Mutable runtime state
    -- ----------------------------------------------------------------------------

    mod._dark_rites_marker_scan_cache_valid = false
    mod._dark_rites_marker_scan_allowed = true
    mod._dark_rites_marker_cached_circumstance_name = nil
    mod._dark_rites_marker_cached_mission_name = nil

    -- ----------------------------------------------------------------------------
    -- Circumstance detection
    -- ----------------------------------------------------------------------------

    local function _safe_circumstance_value(value)
        if value ~= nil and value ~= "" then
            return _safe_lower_string(value)
        end

        return nil
    end

    local function _safe_circumstance_name()
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

    -- ----------------------------------------------------------------------------
    -- Event marker classification
    -- ----------------------------------------------------------------------------

    -- Tainted Skulls only exist while the skulls event runs; outside it the
    -- pickup is left unclassified, exactly as before it had a module of its own.
    function _is_live_event_pickup_kind_allowed(kind)
        return kind ~= "pickup_tainted_skull" or _is_dark_rites_marker_scan_allowed()
    end

    function _live_event_item_kind_for_pickup_name(pickup_name)
        local kind = LIVE_EVENT_ITEM_KIND_BY_PICKUP_NAME[pickup_name]

        if kind then
            return kind
        end

        if SAINTS_PICKUP_NAMES[pickup_name] then
            return "pickup_saints"
        end

        return nil
    end

    function _live_event_interactable_kind(description)
        if description == "loc_skulls_guns_servo_skull_interact_description"
            and _is_dark_rites_marker_scan_allowed() then
            return "dark_rites_servo_skull"
        end

        return nil
    end

    function _is_live_event_skulls_totem_unit(collectible_type, unit_data_breed_name, prop_data_name)
        return collectible_type == "nurgle_totem"
            or unit_data_breed_name == "nurgle_totem"
            or prop_data_name == "nurgle_totem"
    end

end
