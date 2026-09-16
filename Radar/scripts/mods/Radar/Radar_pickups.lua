return function(env)
    setfenv(1, env)

    local mod = mod
    local pcall = pcall
    local pairs = pairs
    local tostring = tostring
    local type = type
    local rawget = rawget
    local string_find = string.find
    local string_format = string.format
    local string_lower = string.lower

    local table_clear = table.clear or function(t)
        for k in pairs(t) do
            t[k] = nil
        end
    end

    -- ----------------------------------------------------------------------------
    -- Constants
    -- ----------------------------------------------------------------------------

    local PICKUP_KIND_BY_NAME = {
        small_clip = "pickup_ammo_small",
        large_clip = "pickup_ammo_big",
        small_grenade = "pickup_grenade",
        small_metal = "material_plasteel",
        large_metal = "material_plasteel",
        small_platinum = "material_diamantine",
        large_platinum = "material_diamantine",
        ammo_cache_pocketable = "pocketable_ammo_crate",
        medical_crate_pocketable = "pocketable_medical_crate",
        syringe_ability_boost_pocketable = "pocketable_syringe_ability",
        syringe_corruption_pocketable = "pocketable_syringe_corruption",
        syringe_power_boost_pocketable = "pocketable_syringe_power",
        syringe_speed_boost_pocketable = "pocketable_syringe_speed",
        ammo_cache_deployable = "pickup_ammo_cache_deployable",
        medical_crate_deployable = "medical_crate_deployable",
    }

    -- ----------------------------------------------------------------------------
    -- Mutable runtime state
    -- ----------------------------------------------------------------------------

    mod._idol_destroyed_collectible_keys = {}
    mod._idol_destroyed_units = {}
    local _scratch_seen_chests = {}
    local _scratch_seen_destructibles = {}
    local _scratch_seen_hazard_props = {}

    -- ----------------------------------------------------------------------------
    -- Generic helpers
    -- ----------------------------------------------------------------------------

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

    -- ----------------------------------------------------------------------------
    -- Interactee classification
    -- ----------------------------------------------------------------------------

    local function _classify_pickup_like(interaction_type, ui_interaction_type, icon, description, unit_name, pickup_name,
                                         pickup_data, marked_by_player_slot, unit, suppress_debug)
        local pickup_group = pickup_data and pickup_data.group or nil
        local meta = _pickup_meta(pickup_name, interaction_type, ui_interaction_type, icon, description,
            marked_by_player_slot)

        if interaction_type == "chest" then
            return "crate_unknown", meta
        end

        local expedition_kind = _classify_expedition_loot_converter(interaction_type, ui_interaction_type,
            pickup_name, meta)

        if expedition_kind then
            return expedition_kind, meta
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
            -- Each feature module names its own items. The name sets do not
            -- overlap, so the first module to answer is the only one that could.
            local exact_kind = PICKUP_KIND_BY_NAME[pickup_name]
                or _objective_item_kind_for_pickup_name(pickup_name)
                or _expedition_item_kind_for_pickup_name(pickup_name)
                or _live_event_item_kind_for_pickup_name(pickup_name)

            if exact_kind then
                if not _is_live_event_pickup_kind_allowed(exact_kind) then
                    return nil, meta
                end

                return exact_kind, meta
            end
        end

        local event_kind = _live_event_interactable_kind(description)

        if event_kind then
            return event_kind, meta
        end

        local riddle_kind = _classify_martyr_skull_riddle_interactable(interaction_type, ui_interaction_type,
            icon, description, unit_name, pickup_name, pickup_group, unit)

        if riddle_kind then
            return riddle_kind, meta
        end

        -- Runs after every pickup classifier so units that already resolve to a
        -- known kind keep it; only otherwise-unclassified interactables can
        -- become mission objective markers.
        local mission_objective_kind, mission_objective_meta = _classify_mission_objective_interactable(
            interaction_type, unit, meta)

        if mission_objective_kind then
            return mission_objective_kind, mission_objective_meta
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

        _apply_expedition_loot_meta(kind, meta, pickup_name, unit)

        return kind, meta
    end

    -- ----------------------------------------------------------------------------
    -- Heretic Idols
    -- ----------------------------------------------------------------------------

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

    -- ----------------------------------------------------------------------------
    -- Unit scans
    -- ----------------------------------------------------------------------------

    function _scan_chests()
        local chest_map = _safe_unit_to_extension_map("chest_system")
        if not chest_map then
            return
        end

        local tracked_units = mod._tracked_units
        local seen_chests = _scratch_seen_chests
        local track_item_tags = mod:get_show_only_tagged_items()
        table_clear(seen_chests)

        for unit, extension in pairs(chest_map) do
            if _safe_unit_alive(unit) and extension then
                seen_chests[unit] = true

                local is_open_fn = extension.is_open

                if is_open_fn then
                    local ok_open, is_open = pcall(is_open_fn, extension)

                    if ok_open and not is_open then
                        local meta = nil

                        if track_item_tags then
                            meta = {
                                marked_by_player_slot = _marked_by_player_slot_for_unit(unit),
                            }
                        end

                        _track_unit(unit, "crate_unknown", "chest_system", meta)
                    else
                        _clear_tracked_unit_from_source(unit, "chest_system")
                    end
                else
                    _clear_tracked_unit_from_source(unit, "chest_system")
                end
            else
                _clear_tracked_unit_from_source(unit, "chest_system")
            end
        end

        for unit, data in pairs(tracked_units) do
            if data and data.source == "chest_system" and not seen_chests[unit] then
                tracked_units[unit] = nil
            end
        end
    end

    local function _safe_hazard_prop_extension_map()
        local hazard_prop_system = _safe_extension_system("hazard_prop_system")
        if not hazard_prop_system then
            return nil
        end

        local unit_to_extension_map = hazard_prop_system.unit_to_extension_map

        if type(unit_to_extension_map) == "function" then
            local ok_map, map = pcall(unit_to_extension_map, hazard_prop_system)

            if ok_map and type(map) == "table" then
                return map
            end
        end

        if type(hazard_prop_system) == "table" then
            local map = rawget(hazard_prop_system, "_unit_to_extension_map")

            if type(map) == "table" then
                return map
            end
        end

        return nil
    end

    local function _safe_hazard_prop_content(extension)
        local content_fn = extension and extension.content

        if type(content_fn) ~= "function" then
            return nil
        end

        local ok_content, content = pcall(content_fn, extension)

        return ok_content and content or nil
    end

    local function _safe_hazard_prop_state(extension)
        local current_state_fn = extension and extension.current_state

        if type(current_state_fn) ~= "function" then
            return nil
        end

        local ok_state, state = pcall(current_state_fn, extension)

        return ok_state and state or nil
    end

    local function _safe_hazard_prop_broadphase_position(extension)
        local broadphase_position_fn = extension and extension.broadphase_position

        if type(broadphase_position_fn) ~= "function" then
            return nil
        end

        local ok_position, position = pcall(broadphase_position_fn, extension)

        return ok_position and _copy_vector3(position) or nil
    end

    local function _hazard_prop_position(unit, extension)
        return _safe_unit_node_position(unit, "c_explosion")
            or _safe_hazard_prop_broadphase_position(extension)
            or _safe_unit_position(unit)
    end

    local function _hazard_prop_state_is_broken(state)
        local hazard_state = rawget(_G, "hazard_state")

        if type(hazard_state) == "table" and hazard_state.broken ~= nil and state == hazard_state.broken then
            return true
        end

        return _safe_lower_string(state) == "broken"
    end

    local function _hazard_prop_kind_from_content(content)
        local hazard_content = rawget(_G, "hazard_content")

        if type(hazard_content) == "table" then
            if hazard_content.explosion ~= nil and content == hazard_content.explosion then
                return "hazard_explosive_barrel"
            end

            if hazard_content.fire ~= nil and content == hazard_content.fire then
                return "hazard_fire_barrel"
            end
        end

        local content_key = _safe_lower_string(content)

        if content_key == "explosion" then
            return "hazard_explosive_barrel"
        elseif content_key == "fire" then
            return "hazard_fire_barrel"
        end

        return nil
    end

    function _scan_hazard_props()
        local hazard_prop_map = _safe_hazard_prop_extension_map()
        if not hazard_prop_map then
            return
        end

        local tracked_units = mod._tracked_units
        local seen_hazard_props = _scratch_seen_hazard_props
        local track_item_tags = mod:get_show_only_tagged_items()
        table_clear(seen_hazard_props)

        for unit, extension in pairs(hazard_prop_map) do
            if _safe_unit_alive(unit) and extension then
                seen_hazard_props[unit] = true

                local state = _safe_hazard_prop_state(extension)

                if not _hazard_prop_state_is_broken(state) then
                    local content = _safe_hazard_prop_content(extension)
                    local kind = _hazard_prop_kind_from_content(content)
                    local position = kind and _hazard_prop_position(unit, extension) or nil

                    if position then
                        _track_unit(unit, kind, "hazard_prop_system", {
                            content = content,
                            state = state,
                            position = position,
                            marked_by_player_slot = track_item_tags and _marked_by_player_slot_for_unit(unit) or nil,
                        })
                    else
                        _clear_tracked_unit_from_source(unit, "hazard_prop_system")
                    end
                else
                    _clear_tracked_unit_from_source(unit, "hazard_prop_system")
                end
            else
                _clear_tracked_unit_from_source(unit, "hazard_prop_system")
            end
        end

        for unit, data in pairs(tracked_units) do
            if data and data.source == "hazard_prop_system" and not seen_hazard_props[unit] then
                tracked_units[unit] = nil
            end
        end
    end

    function _scan_destructibles()
        local destructible_map = _safe_unit_to_extension_map("destructible_system")
        if not destructible_map then
            return
        end

        local tracked_units = mod._tracked_units
        local seen_destructibles = _scratch_seen_destructibles
        local track_item_tags = mod:get_show_only_tagged_items()
        local dark_rites_scan_allowed = _is_dark_rites_marker_scan_allowed()
        table_clear(seen_destructibles)

        for unit, extension in pairs(destructible_map) do
            if _safe_unit_alive(unit) and extension then
                seen_destructibles[unit] = true

                local collectible_type = _safe_unit_collectible_type(unit)
                local collectible_data = _safe_destructible_collectible_data(extension)
                local collectible_id = collectible_data and collectible_data.id or nil
                local collectible_section_id = collectible_data and collectible_data.section_id or nil
                local collectible_key = _idol_collectible_key(collectible_section_id, collectible_id)
                local prop_data_name = nil
                local unit_data_breed_name = nil
                local is_live_event_skulls_totem = false
                local extension_visible = _safe_destructible_visible(extension)
                local unit_visible = _safe_unit_main_visible(unit)
                local health_alive = _safe_health_alive(unit)
                local has_active_collectible = collectible_id ~= nil and collectible_section_id ~= nil
                local destroyed_by_event = mod._idol_destroyed_units[unit] ~= nil
                    or (collectible_key ~= nil and mod._idol_destroyed_collectible_keys[collectible_key] ~= nil)

                if dark_rites_scan_allowed then
                    if collectible_type == "nurgle_totem" then
                        is_live_event_skulls_totem = true
                    elseif collectible_type ~= "heretic_idol" or not has_active_collectible then
                        prop_data_name = _safe_unit_prop_data_name(unit)
                        unit_data_breed_name = _safe_unit_data_breed_name(unit)
                        is_live_event_skulls_totem = _is_live_event_skulls_totem_unit(collectible_type, unit_data_breed_name,
                            prop_data_name)
                    end
                end

                if not destroyed_by_event
                    and (has_active_collectible or is_live_event_skulls_totem)
                    and extension_visible == true
                    and health_alive ~= false
                    and unit_visible ~= false then
                    local kind = is_live_event_skulls_totem and "dark_rites_totem" or "pickup_heretic_idol"

                    _track_unit(unit, kind, "destructible_system", {
                        collectible_type = collectible_type,
                        collectible_id = collectible_id,
                        collectible_section_id = collectible_section_id,
                        marked_by_player_slot = track_item_tags and _marked_by_player_slot_for_unit(unit) or nil,
                    })
                else
                    _clear_tracked_unit_from_source(unit, "destructible_system")
                end
            else
                _clear_tracked_unit_from_source(unit, "destructible_system")
            end
        end

        for unit, data in pairs(tracked_units) do
            if data and data.source == "destructible_system" and not seen_destructibles[unit] then
                tracked_units[unit] = nil
            end
        end

        _prune_destroyed_idol_state()
    end

    function _scan_smart_tag_targets()
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

    -- ----------------------------------------------------------------------------
    -- Mission lifecycle
    -- ----------------------------------------------------------------------------

    function _reset_destroyed_idol_state()
        mod._idol_destroyed_collectible_keys = {}
        mod._idol_destroyed_units = {}
    end

    -- ----------------------------------------------------------------------------
    -- Hooks
    -- ----------------------------------------------------------------------------

    mod:hook_safe("CollectiblesManager", "rpc_player_destroyed_destructible_collectible",
        function(self, channel_id, peer_id, local_player_id, section_id, id)
            _clear_tracked_idol_by_collectible(section_id, id)
        end)

    mod:hook_safe("CollectiblesManager", "collectible_destroyed", function(self, data, attacking_unit)
        if data then
            _clear_tracked_idol_by_collectible(data.section_id, data.id)
        end
    end)

    mod:hook_safe("DestructibleExtension", "rpc_destructible_last_destruction", function(self)
        _mark_idol_unit_destroyed(self and self._unit or nil, self)
    end)

    mod:hook_safe("DestructibleExtension", "rpc_sync_destructible",
        function(self, current_stage, visible, from_hot_join_sync)
            if current_stage == 0 then
                _mark_idol_unit_destroyed(self and self._unit or nil, self)
            end
        end)

end
