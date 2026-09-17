--- Expedition-specific detection, state, filtering and marker handling.
-- An Expedition is split into sections separated by sanctuaries (safe zones). This module
-- resolves which section a unit belongs to and keeps items, pickups and player tags from
-- other sections off the radar, clears them when the players move on, classifies the
-- Expedition pickups (Tech-Remnants, currency, luggables, pocketables), attaches Tech-Remnant
-- values and optionally clusters Tech-Remnant piles into one marker, and tracks the
-- navigation points of the current section (opportunities, exits, extractions, main
-- objectives and arrivals) with the players who marked them.
--
-- Installer module, installed after `Radar_mission_objectives.lua` into Radar's shared
-- runtime environment (see `Radar.lua`). Contributes the section rules
-- `_is_valid_expedition_item_for_current_section` (used by `_track_unit`) and
-- `_is_valid_expedition_player_smart_tag_for_current_section`, `_sync_expedition_item_state`,
-- `_scan_expedition_objectives`, the pickup classifiers, `_cluster_expedition_loot_targets`,
-- the safe zone and store checks, the resets and the Tech-Remnant settings `mod` getters.
-- Every game mode read is guarded, and outside an Expedition every rule lets everything pass.
-- module: Radar_expeditions
-- author: LucLeto
return function(env)
    setfenv(1, env)

    local mod = mod
    local pcall = pcall
    local pairs = pairs
    local tonumber = tonumber
    local tostring = tostring
    local type = type
    local rawget = rawget
    local math_abs = math.abs
    local math_floor = math.floor
    local string_format = string.format
    local table_sort = table.sort

    -- ----------------------------------------------------------------------------
    -- Constants
    -- ----------------------------------------------------------------------------

    --- Candidate unit spawner methods, lookup tables and unit data fields that map a unit to its level or section.
    -- Each list is tried in order and the first name that yields a value is used.
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

    --- Bit of each player slot in a mask of the players who marked a navigation point.
    local PLAYER_SLOT_MASK_BY_SLOT = {
        1,
        2,
        4,
        8,
    }

    --- Fixed Tech-Remnant value of each loot pile tier.
    local EXPEDITION_LOOT_VALUE_BY_PICKUP_NAME = {
        expedition_loot_small_tier_1 = 10,
        expedition_loot_small_tier_2 = 25,
        expedition_loot_small_tier_3 = 50,
    }

    --- Marker kind of each Expedition item, by pickup name; currency and loot piles are matched by prefix.
    local EXPEDITION_ITEM_KIND_BY_PICKUP_NAME = {
        expedition_loot_player_drop = "material_expeditions_loot_player_drop",
        large_ammunition_crate = "pickup_large_ammunition_crate",
        expedition_deployable_force_field_pocketable = "pocketable_void_shield",
        expedition_grenade_airstrike_pocketable = "pocketable_airstrike",
        expedition_grenade_artillery_strike_pocketable = "pocketable_artillery_strike",
        expedition_grenade_big_pocketable = "pocketable_big_grenade",
        expedition_grenade_valkyrie_hover_pocketable = "pocketable_valkyrie_hover",
        motion_detection_mine_explosive_pocketable = "pocketable_landmine_explosive",
        motion_detection_mine_fire_pocketable = "pocketable_landmine_fire",
        motion_detection_mine_shock_pocketable = "pocketable_landmine_shock",
        expedition_loot_heavy_tier_1 = "luggable_data_reliquary",
        expedition_loot_heavy_tier_2 = "luggable_data_reliquary",
        expedition_loot_heavy_tier_3 = "luggable_data_reliquary",
        expedition_explosive_luggable_01 = "luggable_promethium_barrel",
        expedition_time_syringe_timed = "pocketable_anti_rad_stimm",
    }

    -- ----------------------------------------------------------------------------
    -- Mutable runtime state
    -- ----------------------------------------------------------------------------

    --- Section state; the last sanctuary section and whether the players were in a sanctuary, and the player tag generation and per-tag state.
    -- The generation increases on every sanctuary transition, which invalidates the tags placed before it.
    mod._last_safe_zone_section_index = nil
    mod._last_expedition_in_safe_zone = nil
    mod._player_smart_tag_generation = 0
    mod._player_smart_tag_state_by_id = {}

    --- Entries reused to sort navigation points by level index without allocating.
    local _scratch_expedition_registered_entries = {}

    -- ----------------------------------------------------------------------------
    -- Generic helpers
    -- ----------------------------------------------------------------------------

    --- Returns a position table from a boxed vector, an engine vector or a plain position table.
    -- treturn: ?tab `{ x, y, z }`
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

    -- ----------------------------------------------------------------------------
    -- Expedition runtime and level lookups
    -- ----------------------------------------------------------------------------

    --- Returns whether the current game mode is an Expedition.
    local function _is_expedition_runtime()
        return _safe_game_mode_name() == "expedition"
    end

    --- Returns the fixed Tech-Remnant value of a loot pile.
    -- ?string: pickup_name pickup name
    -- treturn: ?number
    function _expedition_loot_value_for_pickup_name(pickup_name)
        if not pickup_name then
            return nil
        end

        return EXPEDITION_LOOT_VALUE_BY_PICKUP_NAME[pickup_name]
    end

    --- Returns the Expedition game mode's loot handler.
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

    --- Returns how many Tech-Remnants a player dropped in a pickup, from the loot handler.
    -- treturn: ?int
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

    --- Returns whether the players are in a sanctuary.
    -- treturn: bool
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

    --- Returns whether a unit is a sanctuary store product while the players are outside a sanctuary.
    -- param: unit interactee unit
    -- treturn: bool
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

    --- Returns the unit spawner manager.
    local function _safe_unit_spawner()
        return Managers and Managers.state and Managers.state.unit_spawner or nil
    end

    --- Normalises a level or section index to a number where possible, so indices from different sources compare equal.
    local function _normalized_expedition_index(index)
        return tonumber(index) or index
    end

    --- Reads a raw data field authored on a unit.
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

    --- Returns the first index found in a unit's data fields.
    local function _safe_unit_data_index(unit, field_names)
        for i = 1, #field_names do
            local value = _safe_unit_data_value(unit, field_names[i])

            if value ~= nil then
                return _normalized_expedition_index(value)
            end
        end

        return nil
    end

    --- Returns the first value a unit spawner method from the list returns for a unit.
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

    --- Returns the first value a unit spawner lookup table from the list holds for a unit.
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

    --- Returns the level a unit belongs to, from the engine or the unit spawner.
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

    --- Returns the index of the level a unit belongs to, from its data or the unit spawner.
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

    --- Returns the unit spawner's index of a level.
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

    --- Returns the level with a unit spawner index.
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

    --- Returns the Expedition's level data of a level.
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

    --- Returns the Expedition's level data of a level index.
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

    --- Returns the section index stored in level data.
    local function _safe_expedition_section_index_from_level_data(level_data)
        local section = level_data and level_data.section or nil
        local section_index = section and section.index or nil

        return _normalized_expedition_index(section_index)
    end

    --- Returns the section a level belongs to.
    local function _safe_expedition_section_index_by_level(game_mode, level)
        local level_data = _safe_expedition_level_data_by_level(game_mode, level)

        return _safe_expedition_section_index_from_level_data(level_data)
    end

    --- Returns the section a level index belongs to.
    local function _safe_expedition_section_index_by_level_index(game_mode, level_index, sub_level_index)
        local level_data = _safe_expedition_level_data_by_index(game_mode, level_index, sub_level_index)

        return _safe_expedition_section_index_from_level_data(level_data)
    end

    --- Returns the section a unit belongs to, from its data, its level or its level index.
    -- tab: game_mode Expedition game mode
    -- param: unit unit handle
    -- return: section index, or nil when it cannot be resolved
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

    --- Returns the section of the current sanctuary, read from the game mode logic.
    local function _safe_current_safe_zone_section_index(game_mode)
        local logic = game_mode and game_mode._game_mode_logic or nil
        local index = logic and logic._current_safe_zone_section_index or nil

        return _normalized_expedition_index(index)
    end

    --- Returns the section the players are in; the sanctuary's section inside a sanctuary, otherwise the current location.
    -- ?tab: game_mode Expedition game mode
    -- return: section index, or nil when unknown
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

    --- Returns whether a level lies in the active section; anything unresolvable counts as in it.
    -- treturn: bool
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

    --- Returns the scanner map glyph of an opportunity, cycling through the 24 Greek letter icons by level index.
    -- treturn: string material path
    local function _expedition_opportunity_icon(level_index)
        local numeric_index = tonumber(level_index) or 0
        local icon_index = 1 + numeric_index % 24

        return string_format("content/ui/materials/backgrounds/scanner/scanner_map_greek_%02d", icon_index)
    end

    --- Returns the scanner map number icon of an opportunity's location id.
    -- treturn: string material path
    local function _expedition_opportunity_title_icon(location_id)
        local numeric_id = tonumber(location_id) or 0
        return string_format("content/ui/materials/backgrounds/scanner/scanner_map_%d", numeric_id % 9)
    end

    -- ----------------------------------------------------------------------------
    -- Expedition marker kinds and section filtering
    -- ----------------------------------------------------------------------------

    --- Returns whether a kind is an Expedition location marker.
    -- treturn: bool
    function _is_expedition_marker_kind(kind)
        return EXPEDITION_MARKER_KINDS[kind] == true
    end

    --- Returns whether a kind is filtered by section; items only, not players, companions, tags, enemies or locations.
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

    --- Returns whether an item may be tracked in the section the players are in.
    -- Everything passes outside an Expedition, for kinds that are not section-filtered, and
    -- whenever the active or the unit's section cannot be resolved (logged once).
    -- ?string: kind marker kind
    -- param: unit unit handle
    -- treturn: bool
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

    -- ----------------------------------------------------------------------------
    -- Expedition item state
    -- ----------------------------------------------------------------------------

    --- Drops every tracked unit that is not valid for the current section.
    local function _clear_invalid_expedition_item_units()
        local tracked_units = mod._tracked_units

        for unit, data in pairs(tracked_units) do
            if data and not _is_valid_expedition_item_for_current_section(data.kind, unit) then
                tracked_units[unit] = nil
            end
        end
    end

    --- Resets the sanctuary flag and the player tag generation and state.
    local function _reset_expedition_player_smart_tag_state()
        mod._last_expedition_in_safe_zone = nil
        mod._player_smart_tag_generation = 0
        mod._player_smart_tag_state_by_id = {}
    end

    --- Starts a new player tag generation, invalidating the tags placed before it.
    local function _advance_expedition_player_smart_tag_generation()
        mod._player_smart_tag_generation = (tonumber(mod._player_smart_tag_generation) or 0) + 1
    end

    --- Follows sanctuary transitions and drops items of other sections, once per droppable scan.
    -- Entering or leaving a sanctuary, or reaching a new sanctuary section, starts a new player
    -- tag generation. Outside an Expedition the state is reset.
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

    -- ----------------------------------------------------------------------------
    -- Expedition pickup classification
    -- ----------------------------------------------------------------------------

    --- Returns the marker kind of an Expedition pickup.
    -- ?string: pickup_name pickup name
    -- treturn: ?string
    function _expedition_item_kind_for_pickup_name(pickup_name)
        local kind = EXPEDITION_ITEM_KIND_BY_PICKUP_NAME[pickup_name]

        if kind then
            return kind
        end

        if _string_starts_with(pickup_name, "expedition_currency_") then
            return "material_expeditions_currency"
        end

        if _string_starts_with(pickup_name, "expedition_loot_small_") then
            return "material_expeditions_loot"
        end

        return nil
    end

    --- Classifies the Tech-Remnant loot converter and gives it its default icon.
    -- ?string: interaction_type lower-case interaction type
    -- ?string: ui_interaction_type lower-case UI interaction type
    -- ?string: pickup_name pickup name
    -- tab: meta classification meta, extended in place
    -- treturn: ?string `expedition_loot_converter`
    function _classify_expedition_loot_converter(interaction_type, ui_interaction_type, pickup_name, meta)
        if interaction_type == "expedition_loot_converter"
            or (ui_interaction_type == "point_of_interest" and pickup_name == "expedition_loot_converter") then
            meta.objective_icon = EXPEDITION_OBJECTIVE_ICON_DEFAULTS.expedition_loot_converter
            return "expedition_loot_converter"
        end

        return nil
    end

    --- Adds a Tech-Remnant pile's value to its meta; a fixed value by tier, or the amount a player dropped.
    -- ?string: kind marker kind
    -- tab: meta classification meta, extended in place
    -- ?string: pickup_name pickup name
    -- param: unit pickup unit
    function _apply_expedition_loot_meta(kind, meta, pickup_name, unit)
        if kind == "material_expeditions_loot" then
            meta.remnant_value = _expedition_loot_value_for_pickup_name(pickup_name)
            meta.is_player_drop = false
        elseif kind == "material_expeditions_loot_player_drop" then
            meta.remnant_value = _safe_expedition_player_drop_amount(unit)
            meta.is_player_drop = true
        end
    end

    -- ----------------------------------------------------------------------------
    -- Tech-Remnant clustering
    -- ----------------------------------------------------------------------------

    --- Returns the Tech-Remnant value of a radar target, 0 when unknown.
    local function _expedition_loot_target_value(target)
        local meta = target and target.meta or nil
        local value = meta and tonumber(meta.remnant_value or meta.remnant_cluster_value) or nil

        if value and value > 0 then
            return value
        end

        local pickup_name = meta and meta.pickup_name or nil

        return _expedition_loot_value_for_pickup_name(pickup_name) or 0
    end

    --- Returns whether a target is a positioned Tech-Remnant pile that may be clustered (player drops never are).
    local function _should_cluster_expedition_loot_target(target)
        return target ~= nil and target.kind == "material_expeditions_loot" and target.position ~= nil
    end

    --- Returns the value-weighted centre of a Tech-Remnant cluster.
    -- treturn: ?tab `{ x, y, z }`
    local function _expedition_loot_cluster_center(cluster_members)
        local total_weight = 0
        local sum_x = 0
        local sum_y = 0
        local sum_z = 0
        local fallback_position = cluster_members[1] and cluster_members[1].position or nil

        for i = 1, #cluster_members do
            local member = cluster_members[i]
            local position = member and member.position

            if position then
                local weight = _expedition_loot_target_value(member)

                if weight <= 0 then
                    weight = 1
                end

                total_weight = total_weight + weight
                sum_x = sum_x + position.x * weight
                sum_y = sum_y + position.y * weight
                sum_z = sum_z + (position.z or 0) * weight
            end
        end

        if total_weight <= 0 or not fallback_position then
            return fallback_position
        end

        return {
            x = sum_x / total_weight,
            y = sum_y / total_weight,
            z = sum_z / total_weight,
        }
    end

    --- Applies the radar's floor rules to a cluster position.
    -- treturn: ?number vertical delta
    -- treturn: ?string `up` or `down`
    -- treturn: bool whether the cluster is hidden as being on another floor
    local function _expedition_loot_vertical_state(player_pos, position, item_vertical_arrow_threshold_sq,
                                                   item_vertical_hide_threshold)
        local vertical_delta = _vertical_delta(player_pos, position)
        local vertical_state = nil

        if vertical_delta ~= nil then
            local abs_vertical_delta = math_abs(vertical_delta)
            local distance_sq_horizontal = _distance_squared_horizontal(player_pos, position)

            if abs_vertical_delta >= item_vertical_hide_threshold then
                return nil, nil, true
            end

            if abs_vertical_delta >= ITEM_VERTICAL_ARROW_Z_DEADZONE
                and distance_sq_horizontal <= item_vertical_arrow_threshold_sq then
                if vertical_delta > 0 then
                    vertical_state = "up"
                elseif vertical_delta < 0 then
                    vertical_state = "down"
                end
            end
        end

        return vertical_delta, vertical_state, false
    end

    --- Builds the radar target of a Tech-Remnant cluster with its total value.
    -- treturn: ?tab target, nil when the cluster is hidden by the floor rules
    local function _create_expedition_loot_cluster_target(cluster_members, player_pos, item_vertical_arrow_threshold_sq,
                                                          item_vertical_hide_threshold)
        local position = _expedition_loot_cluster_center(cluster_members)

        if not position then
            return nil
        end

        local total_value = 0
        local marked_by_player_slot = nil

        for i = 1, #cluster_members do
            local member = cluster_members[i]
            local meta = member and member.meta or nil

            total_value = total_value + _expedition_loot_target_value(member)

            if meta and meta.marked_by_player_slot ~= nil and marked_by_player_slot == nil then
                marked_by_player_slot = meta.marked_by_player_slot
            end
        end

        local vertical_delta, vertical_state, should_hide = _expedition_loot_vertical_state(player_pos, position,
            item_vertical_arrow_threshold_sq, item_vertical_hide_threshold)

        if should_hide then
            return nil
        end

        return {
            unit = nil,
            kind = "material_expeditions_loot",
            position = position,
            source = "expedition_loot_cluster",
            meta = {
                is_tech_remnant_cluster = true,
                remnant_cluster_value = total_value,
                remnant_value = total_value,
                marked_by_player_slot = marked_by_player_slot,
            },
            distance_sq = _distance_squared_horizontal(player_pos, position),
            distance_sq_3d = _distance_squared(player_pos, position),
            vertical_delta = vertical_delta,
            vertical_state = vertical_state,
            ignore_radar_range = false,
        }
    end

    --- Merges nearby Tech-Remnant piles into cluster targets when the loot marker mode is `clustered`.
    -- Piles join a cluster while they lie within the horizontal and vertical radii of its
    -- growing weighted centre. A cluster hidden by the floor rules keeps its piles as they were.
    -- tab: targets radar targets
    -- tab: player_pos player position
    -- number: item_vertical_arrow_threshold_sq squared vertical arrow distance
    -- number: item_vertical_hide_threshold floor hide height
    -- treturn: tab the targets, a new list when clustering is on
    function _cluster_expedition_loot_targets(targets, player_pos, item_vertical_arrow_threshold_sq,
                                                    item_vertical_hide_threshold)
        if mod:get_expedition_loot_marker_mode() ~= "clustered" then
            return targets
        end

        local pass_through_targets = {}
        local cluster_candidates = {}
        local pass_count = 0
        local cluster_candidate_count = 0

        for i = 1, #targets do
            local target = targets[i]

            if _should_cluster_expedition_loot_target(target) then
                cluster_candidate_count = cluster_candidate_count + 1
                cluster_candidates[cluster_candidate_count] = target
            else
                pass_count = pass_count + 1
                pass_through_targets[pass_count] = target
            end
        end

        local horizontal_radius = mod:get_expedition_loot_cluster_horizontal_radius()
        local vertical_threshold = mod:get_expedition_loot_cluster_vertical_radius()
        local radius_sq = horizontal_radius * horizontal_radius
        local consumed = {}

        for i = 1, cluster_candidate_count do
            if not consumed[i] then
                local seed = cluster_candidates[i]
                local cluster_members = { seed }
                local cluster_member_count = 1

                consumed[i] = true

                local changed = true

                while changed do
                    changed = false

                    local center = _expedition_loot_cluster_center(cluster_members)

                    for j = i + 1, cluster_candidate_count do
                        if not consumed[j] then
                            local candidate = cluster_candidates[j]
                            local distance_sq_horizontal = _distance_squared_horizontal(center, candidate.position)
                            local vertical_delta = _vertical_delta(center, candidate.position)
                            local abs_vertical_delta = vertical_delta and math_abs(vertical_delta) or 0

                            if distance_sq_horizontal <= radius_sq
                                and abs_vertical_delta <= vertical_threshold then
                                consumed[j] = true
                                cluster_member_count = cluster_member_count + 1
                                cluster_members[cluster_member_count] = candidate
                                changed = true
                            end
                        end
                    end
                end

                if cluster_member_count > 1 then
                    local clustered_target = _create_expedition_loot_cluster_target(cluster_members, player_pos,
                        item_vertical_arrow_threshold_sq, item_vertical_hide_threshold)

                    if clustered_target then
                        pass_count = pass_count + 1
                        pass_through_targets[pass_count] = clustered_target
                    else
                        for j = 1, cluster_member_count do
                            pass_count = pass_count + 1
                            pass_through_targets[pass_count] = cluster_members[j]
                        end
                    end
                else
                    pass_count = pass_count + 1
                    pass_through_targets[pass_count] = seed
                end
            end
        end

        return pass_through_targets
    end

    -- ----------------------------------------------------------------------------
    -- Player smart tag section validation
    -- ----------------------------------------------------------------------------

    --- Returns the per-tag section state table, creating it when missing.
    local function _smart_tag_state_by_id()
        local state_by_id = mod._player_smart_tag_state_by_id

        if type(state_by_id) ~= "table" then
            state_by_id = {}
            mod._player_smart_tag_state_by_id = state_by_id
        end

        return state_by_id
    end

    --- Returns the current player tag generation.
    local function _current_player_smart_tag_generation()
        return tonumber(mod._player_smart_tag_generation) or 0
    end

    --- Returns whether a player location tag belongs to the section the players are in.
    -- A tag remembers the generation and section it was first seen in. Tags from an earlier
    -- generation, or whose target unit or remembered section lies in another section, are
    -- invalid. Everything passes outside an Expedition.
    -- param: tag_id smart tag id
    -- ?Unit: target_unit unit the tag points at
    -- treturn: bool
    function _is_valid_expedition_player_smart_tag_for_current_section(tag_id, target_unit)
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

    --- Forgets the section state of tags that no longer exist.
    -- tab: seen_tag_ids ids of the tags seen this scan
    function _prune_player_smart_tag_states(seen_tag_ids)
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

    --- Forgets every tag's section state.
    function _reset_player_smart_tag_states()
        mod._player_smart_tag_state_by_id = {}
    end

    -- ----------------------------------------------------------------------------
    -- Expedition objectives
    -- ----------------------------------------------------------------------------

    --- Picks the player slot to colour a navigation point by, and builds the mask of every marking slot.
    -- The local player's slot is preferred, then the lowest numeric slot.
    -- tab: marked_slots map from slot to marked level index
    -- param: marked_level_index level index to filter by, nil for all
    -- return: player slot, or nil
    -- treturn: ?int slot mask
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

    --- Returns which players marked a navigation level, from whichever query the navigation handler provides.
    -- return: player slot, or nil
    -- treturn: ?int slot mask
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

    --- Returns whether the navigation handler reports a level as completed.
    local function _safe_navigation_handler_level_completed(navigation_handler, level_index)
        local is_level_completed = navigation_handler and navigation_handler.is_level_completed

        if not is_level_completed or level_index == nil then
            return false
        end

        local ok, completed = pcall(is_level_completed, navigation_handler, level_index)

        return ok and completed == true or false
    end

    --- Returns the level data of a section's parent level by reference name.
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

    --- Returns the world position of a tagged level's slot unit in its parent level.
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

    --- Tracks the registered navigation points of one kind in the active section.
    -- Opportunities are skipped once completed and numbered by location; other kinds are
    -- numbered by level index order.
    -- tab: game_mode Expedition game mode
    -- ?tab: navigation_handler navigation handler
    -- param: active_section_index active section
    -- ?tab: points boxed positions by level index
    -- string: kind marker kind
    -- string: objective_tag navigation tag of the kind
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

    --- Tracks the levels of the current location carrying a tag (main objective or arrival) as points.
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

    --- Tracks the Expedition's navigation points for the current section.
    function _scan_expedition_objectives()
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

    -- ----------------------------------------------------------------------------
    -- Mission lifecycle
    -- ----------------------------------------------------------------------------

    --- Resets all Expedition section and tag state on mission reset.
    function _reset_expedition_runtime_state()
        mod._last_safe_zone_section_index = nil
        mod._last_expedition_in_safe_zone = nil
        mod._player_smart_tag_generation = 0
        mod._player_smart_tag_state_by_id = {}
    end

    -- ----------------------------------------------------------------------------
    -- Public interface
    -- ----------------------------------------------------------------------------

    --- Returns how Tech-Remnant piles are drawn.
    -- treturn: string `default`, `scaled` or `clustered`
    function mod:get_expedition_loot_marker_mode()
        local value = tostring(self:get("expedition_loot_marker_mode") or "default")

        if value ~= "scaled" and value ~= "clustered" then
            value = "default"
        end

        return value
    end

    --- Returns whether Tech-Remnant values are shown next to their markers.
    -- treturn: bool
    function mod:get_show_expedition_loot_cluster_value()
        return self:get("show_expedition_loot_cluster_value") == true
    end

    --- Returns whether Tech-Remnant value text is shown; follows the cluster value setting.
    -- treturn: bool
    function mod:get_show_expedition_loot_value_text()
        return self:get_show_expedition_loot_cluster_value()
    end

    --- Returns the horizontal radius in metres within which Tech-Remnant piles cluster (1 to 10).
    -- treturn: number
    function mod:get_expedition_loot_cluster_horizontal_radius()
        local value = tonumber(self:get("expedition_loot_cluster_horizontal_radius")) or 5

        if value < 1 then
            value = 1
        elseif value > 10 then
            value = 10
        end

        return value
    end

    --- Returns the height difference in metres within which Tech-Remnant piles cluster (1 to 5).
    -- treturn: number
    function mod:get_expedition_loot_cluster_vertical_radius()
        local value = tonumber(self:get("expedition_loot_cluster_vertical_radius")) or 3

        if value < 1 then
            value = 1
        elseif value > 5 then
            value = 5
        end

        return value
    end
end
