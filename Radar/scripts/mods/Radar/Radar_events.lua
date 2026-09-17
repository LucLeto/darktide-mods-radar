--- Live event marker classification (Dark Rites skulls, saints, leftovers and stolen rations).
-- Maps live event pickups, interactables and totems to Radar marker kinds, and decides
-- whether the Dark Rites (skulls) event can be running from the mission's circumstance, so
-- its markers are only produced where the event exists.
--
-- Installer module, installed after the other feature modules into Radar's shared runtime
-- environment (see `Radar.lua`). Contributes the classifiers
-- `_live_event_item_kind_for_pickup_name`, `_live_event_interactable_kind`,
-- `_is_live_event_skulls_totem_unit` and `_is_live_event_pickup_kind_allowed`, and the
-- circumstance gate `_is_dark_rites_marker_scan_allowed` with its reset
-- `_reset_dark_rites_marker_scan_cache`. Relies on `_safe_lower_string`,
-- `_string_starts_with` and `_safe_mission_name` from `Radar_runtime_helpers.lua`.
-- module: Radar_events
-- author: LucLeto
return function(env)
    setfenv(1, env)

    local mod = mod
    local pcall = pcall

    -- ----------------------------------------------------------------------------
    -- Constants
    -- ----------------------------------------------------------------------------

    --- Circumstance names of the skulls live event (current and legacy, with their variants).
    -- The Psykhanium mission also allows the event's markers.
    local DARK_RITES_CIRCUMSTANCE_PREFIX = "skulls_guns"
    local LEGACY_SKULLS_CIRCUMSTANCE_PREFIX = "skulls_event_01"
    local DARK_RITES_CIRCUMSTANCE_VARIANT_PREFIX = DARK_RITES_CIRCUMSTANCE_PREFIX .. "_"
    local LEGACY_SKULLS_CIRCUMSTANCE_VARIANT_PREFIX = LEGACY_SKULLS_CIRCUMSTANCE_PREFIX .. "_"
    local PSYKHANIUM_MISSION_NAME = "tg_shooting_range"

    --- Marker kind of each live event pickup, by pickup name.
    local LIVE_EVENT_ITEM_KIND_BY_PICKUP_NAME = {
        skulls_01_pickup = "pickup_tainted_skull",
        communications_hack_device = "pocketable_corrupted_auspex_scanner",
        live_event_leftover_01_pickup_small = "pickup_leftover",
        live_event_leftover_01_pickup_medium = "pickup_leftover",
        live_event_leftover_01_pickup_large = "pickup_leftover",
        stolen_rations_01_pickup_small = "pickup_stolen_rations",
        stolen_rations_01_pickup_medium = "pickup_stolen_rations",
    }

    --- Pickup names of the saints event, all drawn as `pickup_saints`.
    local SAINTS_PICKUP_NAMES = {
        live_event_saints_01_pickup_small = true,
        live_event_saints_01_pickup_medium = true,
        live_event_saints_01_pickup_large = true,
        consumable = true,
    }

    -- ----------------------------------------------------------------------------
    -- Mutable runtime state
    -- ----------------------------------------------------------------------------

    --- Cached Dark Rites gate, valid while the circumstance and mission name are unchanged.
    mod._dark_rites_marker_scan_cache_valid = false
    mod._dark_rites_marker_scan_allowed = true
    mod._dark_rites_marker_cached_circumstance_name = nil
    mod._dark_rites_marker_cached_mission_name = nil

    -- ----------------------------------------------------------------------------
    -- Circumstance detection
    -- ----------------------------------------------------------------------------

    --- Normalises a circumstance name to lower case, treating an empty name as none.
    -- param: value circumstance name
    -- treturn: ?string
    local function _safe_circumstance_value(value)
        if value ~= nil and value ~= "" then
            return _safe_lower_string(value)
        end

        return nil
    end

    --- Returns the circumstance of the current mission, from the first source that knows it.
    -- Tries the last gameplay state's shared state, the game mode manager, the gameplay state
    -- manager, the package synchronizer and the mechanism data in turn and returns the first
    -- name found; manager calls run through `pcall`.
    -- treturn: ?string lower-case circumstance name, or nil when none can be read
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

    --- Returns whether a circumstance belongs to the skulls live event.
    -- string: circumstance_name lower-case circumstance name
    -- treturn: bool
    local function _is_skulls_live_event_circumstance(circumstance_name)
        return circumstance_name == DARK_RITES_CIRCUMSTANCE_PREFIX
            or circumstance_name == LEGACY_SKULLS_CIRCUMSTANCE_PREFIX
            or _string_starts_with(circumstance_name, DARK_RITES_CIRCUMSTANCE_VARIANT_PREFIX)
            or _string_starts_with(circumstance_name, LEGACY_SKULLS_CIRCUMSTANCE_VARIANT_PREFIX)
    end

    --- Returns whether the mission is the Psykhanium.
    -- treturn: bool
    local function _is_psykhanium_mission(mission_name)
        return mission_name == PSYKHANIUM_MISSION_NAME
    end

    --- Invalidates the cached Dark Rites gate, so the next check reads the circumstance again.
    function _reset_dark_rites_marker_scan_cache()
        mod._dark_rites_marker_scan_cache_valid = false
        mod._dark_rites_marker_scan_allowed = true
        mod._dark_rites_marker_cached_circumstance_name = nil
        mod._dark_rites_marker_cached_mission_name = nil
    end

    --- Returns whether Dark Rites markers may be produced in the current mission.
    -- True for a skulls event circumstance, the Psykhanium, or when no circumstance can be read
    -- at all, so an unreadable circumstance never hides the event. The answer is cached until
    -- the circumstance or mission name changes.
    -- treturn: bool
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

    --- Returns whether a live event pickup kind may be classified in the current mission.
    -- Tainted Skulls only exist while the skulls event runs; outside it the pickup stays
    -- unclassified. Every other kind is always allowed.
    -- ?string: kind marker kind
    -- treturn: bool
    function _is_live_event_pickup_kind_allowed(kind)
        return kind ~= "pickup_tainted_skull" or _is_dark_rites_marker_scan_allowed()
    end

    --- Returns the marker kind of a live event pickup.
    -- ?string: pickup_name pickup name
    -- treturn: ?string marker kind, or nil for pickups that belong to no live event
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

    --- Returns the marker kind of a live event interactable, identified by its interaction description.
    -- Only the Dark Rites servo skull is recognised, and only while the event is allowed.
    -- ?string: description interaction description localization id
    -- treturn: ?string marker kind
    function _live_event_interactable_kind(description)
        if description == "loc_skulls_guns_servo_skull_interact_description"
            and _is_dark_rites_marker_scan_allowed() then
            return "dark_rites_servo_skull"
        end

        return nil
    end

    --- Returns whether a unit is a Nurgle totem of the skulls event, by its breed name.
    -- The unit data extension of a totem reports its prop data entry, `nurgle_totem`, as the
    -- breed. Its prop data name and collectible type are component data that unit data reads
    -- cannot reach, and a totem's collectible type is `none` anyway.
    -- ?string: unit_data_breed_name breed name from the unit data extension
    -- treturn: bool
    function _is_live_event_skulls_totem_unit(unit_data_breed_name)
        return unit_data_breed_name == "nurgle_totem"
    end

end
