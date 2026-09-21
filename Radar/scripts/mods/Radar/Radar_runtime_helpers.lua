--- Generic runtime infrastructure shared by every Radar module.
-- Provides defensive access to engine and game state (units, extensions, managers, the
-- player and camera), the rules that decide whether the radar may run at all, the radar
-- position maths, the game's world marker list, the world-to-screen projection and
-- occlusion test used by the HUD element, and the collection of nearby highlight targets.
-- Engine and extension calls are existence-checked and run through `pcall`, so a game
-- patch that changes an API degrades a feature instead of raising in the update loop.
--
-- Installer module, installed second into Radar's shared runtime environment (see
-- `Radar.lua`). Contributes the `_safe_*` accessors, player, mission, runtime state, colour
-- and world marker helpers, the radar position constants (`DEFAULT_RADAR_*`,
-- `RADAR_ANCHORS`) and `SCREEN_HIGHLIGHT_Z_OFFSET_BY_KIND`, plus the HUD projection `mod`
-- methods. It holds no feature-specific marker logic.
--
-- Relies on the registries from `Radar_enemy_definitions.lua`, on the colour runtime, and
-- at call time on tracking state and methods (`mod._last_state_gameplay`,
-- `mod._logged_units`, the radar target lists and the nearby highlight settings getters)
-- from `Radar_tracking.lua`.
-- module: Radar_runtime_helpers
-- author: LucLeto
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

    -- ----------------------------------------------------------------------------
    -- Constants
    -- ----------------------------------------------------------------------------

    --- Raycast setup for the HUD occlusion test.
    -- Each filter is tried in turn until one reports a hit; a hit closer than the target by
    -- more than `HUD_OCCLUSION_EPSILON` metres counts as occluded.
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
    --- Default radar placement, nudge step and the corners the radar position can be anchored to.
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
    --- Height in metres added to a kind's highlight anchor, so the bracket frames the item rather than its base.
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
        martyr_skull_riddle_interactable = 0.12,
        mission_objective_scanner = 0.12,
        mission_objective_hacking = 0.12,
        mission_objective_servo_skull = 0.12,
        mission_objective_other = 0.12,
        mission_objective_growth = 0.12,
        mission_objective_destroy = 0.12,
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

    -- ----------------------------------------------------------------------------
    -- Mutable runtime state
    -- ----------------------------------------------------------------------------

    --- Per-collection cache of whether each kind's nearby highlight is enabled.
    local _scratch_highlight_enabled_by_kind = {}

    --- Result slot for the world marker list request.
    -- Used instead of a per-call closure; the event manager invokes the callback
    -- synchronously, so a single slot is enough.
    local _world_markers_list_result = nil

    --- Units the game currently marks as an objective, as opposed to the prompt a player gets next to something.
    -- Refilled by `_refresh_world_marker_units`.
    local _objective_marker_units = {}

    --- Units with at least one world marker the game is drawing rather than holding out of reach.
    -- Presence in the marker list is unaffected; this only answers whether the game's marker is
    -- on screen, which decides what may bypass the radar's range. Refilled by
    -- `_refresh_world_marker_units`.
    local _marker_in_reach_units = {}

    --- Runtime state computed by `_get_runtime_state`, cached for the gameplay time it was computed at.
    local _runtime_state_cached_t = nil
    local _runtime_state_allowed = false
    local _runtime_state_reason = nil
    local _runtime_state_mission_name = nil
    local _runtime_state_activity = nil
    local _runtime_state_mechanism_name = nil
    local _runtime_state_player_unit = nil
    local _runtime_state_player_pos = nil

    -- ----------------------------------------------------------------------------
    -- Generic helpers
    -- ----------------------------------------------------------------------------

    --- Returns the current gameplay time, or nil before the gameplay timer exists.
    -- treturn: ?number
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

    --- Returns whether a unit handle still refers to a live engine unit, according to the game's `ALIVE` table.
    -- param: unit unit handle, may be nil
    -- treturn: ?bool
    function _safe_unit_alive(unit)
        return unit and ALIVE and ALIVE[unit]
    end

    --- Returns a readable unit name for debug output.
    -- Falls back to the handle's string form, and to `<dead>` for a unit that is gone.
    -- param: unit unit handle
    -- treturn: string
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

    --- Returns the resource a unit was spawned from, identical for every unit of one prefab.
    -- Hashed in a shipping build (`#ID[ab4fec216e4f3c1c]`) but still comparable. Callers
    -- compare these values, so there is deliberately no per-unit stand-in like the one
    -- `_safe_unit_name` returns; that would make every unit its own prefab.
    -- param: unit unit handle
    -- treturn: ?string prefab name, or nil when the engine cannot say
    function _safe_unit_prefab_name(unit)
        local unit_api = Unit
        local debug_name = unit_api and unit_api.debug_name

        if not debug_name then
            return nil
        end

        local ok, result = pcall(debug_name, unit, false)

        if ok and type(result) == "string" and result ~= "" then
            return result
        end

        return nil
    end

    --- Returns whether a value is a number that is neither NaN nor infinite.
    -- treturn: bool
    function _is_finite_number(v)
        return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
    end

    --- Returns the components of an engine `Vector3` or of an `x`/`y`/`z` table.
    -- param: vec vector, may be nil
    -- treturn: ?number x
    -- treturn: ?number y
    -- treturn: ?number z
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

    --- Copies a vector into a plain `{ x, y, z }` table, so it can be kept beyond the current frame.
    -- Engine vectors are temporary; a table copy is safe to store.
    -- param: vec engine vector or table
    -- treturn: ?tab copy, or nil when a component is missing or not finite
    function _copy_vector3(vec)
        local x, y, z = _vector3_components(vec)

        if not _is_finite_number(x) or not _is_finite_number(y) or not _is_finite_number(z) then
            return nil
        end

        return { x = x, y = y, z = z }
    end

    --- Returns the lower-case string form of a value, or nil for nil.
    -- treturn: ?string
    function _safe_lower_string(value)
        if value == nil then
            return nil
        end

        return string_lower(tostring(value))
    end

    --- Returns whether a string starts with a prefix; false when either is nil.
    -- treturn: bool
    function _string_starts_with(value, prefix)
        if value == nil or prefix == nil then
            return false
        end

        return string_sub(value, 1, string_len(prefix)) == prefix
    end

    --- Reads a data field authored on a unit, as a lower-case string.
    -- !Unit: unit unit to read
    -- string: field_name unit data field
    -- treturn: ?string value, or nil when the field is absent
    local function _safe_unit_data_string(unit, field_name)
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

    --- Returns a unit's `pickup_type` data, the pickup name used to classify items.
    -- treturn: ?string
    function _safe_unit_pickup_name(unit)
        return _safe_unit_data_string(unit, "pickup_type")
    end

    --- Returns a unit's `deployable_type` data.
    -- treturn: ?string
    function _safe_unit_deployable_type(unit)
        return _safe_unit_data_string(unit, "deployable_type")
    end

    --- Returns a unit's `smart_tag_target_type` data.
    -- treturn: ?string
    function _safe_unit_smart_tag_target_type(unit)
        return _safe_unit_data_string(unit, "smart_tag_target_type")
    end

    --- Returns the breed name reported by a unit's unit data extension, in lower case.
    -- treturn: ?string
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

    --- Returns the collectible data of a destructible extension, read raw from its private field.
    -- ?tab: extension destructible extension
    -- treturn: ?tab
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

    --- Returns a destructible extension's visibility flag, read raw from its private field.
    -- ?tab: extension destructible extension
    -- treturn: ?bool nil when the extension keeps no visibility info
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

    --- Returns whether a unit's main mesh group is visible, trying the grouped and plain engine call.
    -- treturn: ?bool nil when visibility cannot be read
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

    --- Counts the entries of any table.
    -- treturn: int
    function _table_size(t)
        local n = 0
        for _, _ in pairs(t) do
            n = n + 1
        end
        return n
    end

    --- Clamps a number to a range.
    -- number: value value
    -- number: min_value lower bound
    -- number: max_value upper bound
    -- treturn: number
    function _clamp(value, min_value, max_value)
        if value < min_value then
            return min_value
        end

        if value > max_value then
            return max_value
        end

        return value
    end

    --- Returns the size of the UI coordinate space, 1920 by 1080 scaled by the resolution's inverse UI scale.
    -- treturn: number width
    -- treturn: number height
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

    --- Writes a debug log line once per key, and only while debug mode is enabled.
    -- Keys are remembered in `mod._logged_units`, which the mission reset clears.
    -- string: key de-duplication key
    -- string: text log message
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

    -- ----------------------------------------------------------------------------
    -- Radar position helpers
    -- ----------------------------------------------------------------------------

    --- Returns a valid radar anchor, the default for anything unknown.
    -- treturn: string
    function _normalize_radar_anchor(value)
        if RADAR_ANCHORS[value] then
            return value
        end

        return DEFAULT_RADAR_ANCHOR
    end

    --- Returns the largest top-left position that keeps a radar of the given size on screen.
    -- treturn: number max x
    -- treturn: number max y
    function _get_radar_position_bounds(size)
        local radar_size = tonumber(size) or 0
        local ui_width, ui_height = _get_ui_space_size()
        local max_x = math_max(0, ui_width - radar_size)
        local max_y = math_max(0, ui_height - radar_size)

        return max_x, max_y
    end

    local function _round_radar_position_value(value, default_value)
        return math_floor((tonumber(value) or default_value or 0) + 0.5)
    end

    --- Rounds a radar position value and clamps it to the screen unless positioning is unrestricted.
    -- param: value setting value
    -- number: default_value value used when the setting is not a number
    -- number: min_value lower bound
    -- number: max_value upper bound
    -- ?bool: unrestricted skip clamping when true
    -- treturn: int
    function _resolve_radar_position_value(value, default_value, min_value, max_value, unrestricted)
        local rounded_value = _round_radar_position_value(value, default_value)

        if unrestricted == true then
            return rounded_value
        end

        return math_floor(_clamp(rounded_value, min_value, max_value) + 0.5)
    end

    --- Converts offsets from an anchor corner into a top-left radar position.
    -- treturn: number x
    -- treturn: number y
    -- treturn: number max x
    -- treturn: number max y
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

    --- Converts a top-left radar position into offsets from an anchor corner.
    -- treturn: number offset x
    -- treturn: number offset y
    -- treturn: number max x
    -- treturn: number max y
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

    -- ----------------------------------------------------------------------------
    -- Unit and extension helpers
    -- ----------------------------------------------------------------------------

    --- Returns a copy of a unit's position from the game's `POSITION_LOOKUP`, the cheapest source.
    local function _position_lookup(unit)
        local position_lookup = POSITION_LOOKUP

        if not unit or not position_lookup then
            return nil
        end

        return _copy_vector3(position_lookup[unit])
    end

    --- Returns a live unit's world position as a plain table.
    -- Uses the game's position lookup and falls back to the root node's world position.
    -- param: unit unit handle
    -- treturn: ?tab `{ x, y, z }`
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

    --- Returns the world position of a named node of a live unit.
    -- param: unit unit handle
    -- ?string: node_name node name, such as `ui_interaction_marker`
    -- treturn: ?tab `{ x, y, z }`, or nil when the unit has no such node
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

    --- Returns whether a marker kind is an enemy kind (`enemy_` prefix).
    -- treturn: bool
    function _is_enemy_kind(kind)
        return kind ~= nil and _string_starts_with(kind, "enemy_")
    end

    --- Returns what a unit's health extension says about it being alive.
    -- treturn: ?bool nil when the unit has no health extension
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

    --- Returns whether a unit's buff extension reports a keyword.
    -- treturn: bool
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

    --- Returns whether a unit has a buff using the given buff template.
    -- treturn: bool
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

    --- Returns the name of the ability a unit has equipped in a slot.
    -- For the combat ability the extension's current ability name is also tried.
    -- param: unit unit handle
    -- ?string: ability_type ability slot, such as `combat_ability`
    -- treturn: ?string ability name, nil when none is equipped
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

    --- Returns whether the death manager has taken over a unit, which means it is dying.
    local function _is_owned_by_death_manager(unit)
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

    --- Returns whether a unit should still be tracked as alive for its marker kind.
    -- Enemies stop counting once the death manager owns them or their health says dead;
    -- Heretic Idols and Dark Rites totems once their health says dead. Other kinds only need
    -- a live unit.
    -- param: unit unit handle
    -- ?string: kind marker kind
    -- treturn: bool
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

    --- Returns the world rotation of a live unit's node, the root node by default.
    local function _safe_world_rotation(unit, node)
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

    --- Returns a rotation's direction vector projected onto the horizontal plane and normalised.
    -- func: vector_getter `Quaternion` direction getter, such as `Quaternion.forward`
    -- param: rotation rotation
    -- treturn: ?number x
    -- treturn: ?number y
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

        local length = math_sqrt(x * x + y * y)
        if length <= 0 then
            return nil, nil
        end

        return x / length, y / length
    end

    --- Returns a rotation's horizontal forward direction, normalised.
    -- treturn: ?number x
    -- treturn: ?number y
    function _safe_forward_xy(rotation)
        local quaternion = Quaternion
        local forward = quaternion and quaternion.forward

        return _safe_flat_direction_xy(forward, rotation)
    end

    --- Returns an extension system by name from the state extension manager.
    -- string: system_name system name, such as `interactee_system`
    -- treturn: ?tab
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

    --- Returns the unit-to-extension map of an extension system, the entry point for every unit scan.
    -- string: system_name system name
    -- treturn: ?tab map from unit to extension
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

    --- Returns the outline system's per-unit outline data, read raw from its private field.
    -- treturn: ?tab
    function _safe_outline_extension_data_map()
        local outline_system = _safe_extension_system("outline_system")
        local unit_extension_data = outline_system and rawget(outline_system, "_unit_extension_data")

        if type(unit_extension_data) == "table" then
            return unit_extension_data
        end

        return nil
    end

    --- Returns a unit's outline data.
    -- param: unit unit handle
    -- ?tab: outline_extension_map map from `_safe_outline_extension_data_map`, fetched when nil
    -- treturn: ?tab
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

    local function _safe_game_mode_manager()
        return Managers and Managers.state and Managers.state.game_mode or nil
    end

    --- Returns the active game mode object.
    -- treturn: ?tab
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

    --- Returns the active game mode name, such as `coop_complete_objective`, `survival` or `expedition`.
    -- treturn: ?string
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

    -- ----------------------------------------------------------------------------
    -- Mission and mechanism helpers
    -- ----------------------------------------------------------------------------

    --- Returns the current mission name from the first source that has one.
    -- Tries the last gameplay state's shared state, the game mode manager, the gameplay state
    -- manager, the package synchronizer and the mechanism in turn.
    -- treturn: ?string mission name, such as `hub_ship` or `cm_habs`
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

    --- Returns the presence activity (such as `hub`, `loading` or `main_menu`) from the first source that has one.
    -- treturn: ?string
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

    --- Returns the current mechanism name (such as `adventure`, `hub`, `onboarding` or `expedition`).
    -- treturn: ?string
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

    --- Returns whether the game is in the hub, main menu or title screen.
    -- Values that are not passed in are read.
    -- ?string: mission_name mission name
    -- ?string: activity presence activity
    -- ?string: mechanism_name mechanism name
    -- treturn: bool
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

    -- ----------------------------------------------------------------------------
    -- Player helpers
    -- ----------------------------------------------------------------------------

    --- Returns the player manager.
    -- treturn: ?tab
    function _player_manager()
        return Managers and Managers.player
    end

    --- Returns the first local player, or nil while no players exist.
    -- treturn: ?tab
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

    --- Returns the local player's unit, which can be a teammate's while spectating.
    -- return: unit handle, or nil
    function _player_unit()
        local local_player = _local_player()
        return local_player and local_player.player_unit
    end

    --- Returns the `character_state` component of a player unit.
    local function _safe_player_character_state_component(player_unit)
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

    --- Returns the character state name of a player unit, such as `hogtied` or `knocked_down`.
    -- treturn: ?string
    function _safe_player_character_state_name(player_unit)
        local character_state_component = _safe_player_character_state_component(player_unit)
        return character_state_component and character_state_component.state_name or nil
    end

    --- Returns the player that owns a player unit.
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

    --- Returns whether the local player's unit belongs to another player, as while spectating a teammate.
    -- treturn: bool
    function _is_local_player_using_foreign_unit(player_unit)
        local local_player = _local_player()

        if not local_player or not player_unit then
            return false
        end

        local owning_player = _player_for_unit(player_unit)

        return owning_player ~= nil and owning_player ~= local_player
    end

    --- Returns whether a player unit is still a live unit.
    -- treturn: ?bool
    function _is_player_unit_alive(player_unit)
        return _safe_unit_alive(player_unit)
    end

    --- Returns whether a player unit is captured (hogtied).
    -- treturn: bool
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

    --- Returns whether the local player is alive in their own unit.
    -- treturn: bool
    function _is_local_player_alive()
        local player_unit = _player_unit()

        if _is_local_player_using_foreign_unit(player_unit) then
            return false
        end

        return _is_player_unit_alive(player_unit)
    end

    --- Returns whether the local player is captured in their own unit.
    -- treturn: bool
    function _is_local_player_captured()
        local player_unit = _player_unit()

        if _is_local_player_using_foreign_unit(player_unit) then
            return false
        end

        return _is_player_unit_captured(player_unit)
    end

    --- Returns the rotation of the local player's camera, or nil without a visible camera.
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

    --- Returns the rotation the radar is aligned to.
    -- Prefers the camera, then the player's first person rotation, and finally the unit's root rotation.
    -- param: player_unit local player unit
    -- return: rotation, or nil
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

    -- ----------------------------------------------------------------------------
    -- Game mode and runtime state
    -- ----------------------------------------------------------------------------

    --- Returns whether the current mission runs under Havoc, by havoc data or the game mode's havoc extension.
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

    --- Maps the current game mode to one of Radar's per-mode enable settings.
    -- ?string: mission_name mission name
    -- ?string: mechanism_name mechanism name
    -- treturn: ?string `expeditions`, `mortis_trials`, `havoc` or `regular_missions`; nil when unsupported
    -- treturn: ?string game mode name
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

    --- Returns whether the radar is enabled for a game mode id; unset settings count as enabled.
    -- string: game_mode_id id from `RADAR_GAME_MODE_SETTING_BY_ID`
    -- treturn: bool
    function mod:is_radar_enabled_for_game_mode(game_mode_id)
        local setting_id = RADAR_GAME_MODE_SETTING_BY_ID[game_mode_id]

        if not setting_id then
            return false
        end

        return self:get(setting_id) ~= false
    end

    --- Returns whether the radar is enabled for the game mode currently running.
    local function _is_radar_enabled_for_current_mode(mission_name, mechanism_name)
        local game_mode_id = _classify_radar_game_mode(mission_name, mechanism_name)

        if not game_mode_id then
            return false
        end

        return mod:is_radar_enabled_for_game_mode(game_mode_id)
    end

    --- Returns whether the current game state is a mission the radar may run in.
    -- Loading screens, the hub, the main menu and onboarding other than the Psykhanium are
    -- excluded, and so is any game mode whose enable setting is off.
    -- treturn: bool
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

    --- Forces the next `_get_runtime_state` call to evaluate the runtime state again.
    function _invalidate_runtime_state_cache()
        _runtime_state_cached_t = nil
    end

    --- Caches a runtime state evaluation and returns it unchanged.
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

    --- Evaluates whether the radar may run right now, cached per gameplay time.
    -- treturn: bool allowed
    -- treturn: string reason, `ok` when allowed; otherwise such as `loading`, `hub_runtime`,
    --   `game_mode_disabled`, `spectating_teammate`, `no_player_unit`, `player_not_alive` or
    --   `player_captured`
    -- treturn: ?number gameplay time
    -- treturn: ?string mission name
    -- treturn: ?string presence activity
    -- treturn: ?string mechanism name
    -- return: local player unit, or nil
    -- treturn: ?tab local player position
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

        if not player_unit then
            return _store_runtime_state(false, "no_player_unit", gameplay_t, mission_name, activity, mechanism_name,
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

    --- Returns whether the radar may run right now.
    -- treturn: bool
    function _is_allowed_runtime()
        local allowed = _get_runtime_state()
        return allowed
    end

    -- ----------------------------------------------------------------------------
    -- Colour helpers
    -- ----------------------------------------------------------------------------

    --- Returns a copy of an ARGB colour array with missing channels set to 255.
    -- ?tab: color colour array
    -- treturn: ?tab
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

    --- Returns a new colour array with its RGB channels scaled, for occluded highlights.
    local function _darkened_color_array(color, multiplier)
        local src = color or DEFAULT_COLOR_ARRAY_WHITE
        local mul = multiplier or 1

        return {
            src[1] or 255,
            math_floor(_clamp((src[2] or 255) * mul, 0, 255) + 0.5),
            math_floor(_clamp((src[3] or 255) * mul, 0, 255) + 0.5),
            math_floor(_clamp((src[4] or 255) * mul, 0, 255) + 0.5),
        }
    end

    --- Returns the configured nearby highlight colour of a kind, or its default before the settings getter exists.
    local function _screen_highlight_color_for_kind(kind)
        if mod.get_nearby_highlight_color then
            return mod:get_nearby_highlight_color(kind)
        end

        return _copy_color_array(NEARBY_OUTLINE_COLOR_BY_KIND[kind])
    end

    -- ----------------------------------------------------------------------------
    -- World marker helpers
    -- ----------------------------------------------------------------------------

    --- Returns the emptied per-unit cache of interaction world markers, stored on `mod`.
    local function _interaction_world_marker_cache()
        local cache = mod._interaction_world_markers_by_unit

        if type(cache) ~= "table" then
            cache = {}
            mod._interaction_world_markers_by_unit = cache
        else
            table_clear(cache)
        end

        return cache
    end

    --- Receives the world marker list requested from the HUD.
    local function _world_markers_list_response(response)
        _world_markers_list_result = response
    end

    --- Requests the game's world marker list from the HUD through the event manager.
    -- Shared by every world marker consumer so the request is issued the same way each time.
    -- treturn: ?tab the live list owned by the HUD element, which callers must only read
    function _safe_world_markers_list()
        local managers = Managers
        local event_manager = managers and managers.event or nil
        local trigger = event_manager and event_manager.trigger or nil

        if not trigger then
            return nil
        end

        _world_markers_list_result = nil

        local ok = pcall(trigger, event_manager, "request_world_markers_list", _world_markers_list_response)
        local markers = _world_markers_list_result
        _world_markers_list_result = nil

        if not ok or type(markers) ~= "table" then
            return nil
        end

        return markers
    end

    --- Returns whether the game is drawing a world marker rather than holding it out of reach.
    -- Mirrors the game's own test, the camera distance it keeps on the marker against its
    -- template's `max_distance`, unless the marker lifts the limit. A marker not measured yet
    -- counts as drawn.
    -- tab: marker world marker
    -- treturn: bool
    local function _world_marker_in_reach(marker)
        if marker.block_max_distance then
            return true
        end

        local template = marker.template
        local max_distance = type(template) == "table" and template.max_distance or nil
        local distance = marker.distance

        return type(max_distance) ~= "number" or type(distance) ~= "number" or distance <= max_distance
    end

    --- Rebuilds the sets of units the game currently holds world markers for.
    -- Fills `out` with every unit that has a world marker of any type, and refills the objective
    -- and in-reach sets read by `_game_marks_as_objective` and `_game_draws_marker_on`. This is
    -- presence only, deliberately not the marker's `draw` flag or widget visibility; a marker the
    -- player is too far away to see is still a live objective, and filtering on visibility would
    -- make markers blink with distance.
    -- tab: out set to fill with units, cleared first
    -- treturn: bool false when the list cannot be read, so callers can fall back rather than
    --   treat an unavailable list as "nothing exists"
    function _refresh_world_marker_units(out)
        table_clear(out)
        table_clear(_objective_marker_units)
        table_clear(_marker_in_reach_units)

        local markers = _safe_world_markers_list()

        if not markers then
            return false
        end

        for i = 1, #markers do
            local marker = markers[i]
            local unit = marker and marker.unit or nil

            if unit ~= nil then
                out[unit] = true

                if marker.type == "objective" then
                    _objective_marker_units[unit] = true
                end

                if _world_marker_in_reach(marker) then
                    _marker_in_reach_units[unit] = true
                end
            end
        end

        return true
    end

    --- Returns whether the game marks a unit as an objective, as of the last world marker refresh.
    -- treturn: bool
    function _game_marks_as_objective(unit)
        return _objective_marker_units[unit] == true
    end

    --- Returns whether the game is drawing a world marker on a unit, as of the last world marker refresh.
    -- treturn: bool
    function _game_draws_marker_on(unit)
        return _marker_in_reach_units[unit] == true
    end

    --- Empties the world marker sets and the interaction marker cache on mission reset.
    -- Each of them holds units and is otherwise only emptied by the next refresh.
    function _clear_world_marker_units()
        table_clear(_objective_marker_units)
        table_clear(_marker_in_reach_units)

        local cache = mod._interaction_world_markers_by_unit

        if type(cache) == "table" then
            table_clear(cache)
        end
    end

    -- ----------------------------------------------------------------------------
    -- HUD projection interface
    -- ----------------------------------------------------------------------------

    --- Returns the interaction world markers the game is currently drawing, keyed by unit.
    -- Only markers whose widget is visible are included. The returned table is reused.
    -- treturn: tab map from unit to marker
    function mod:get_interaction_world_markers_by_unit()
        local cache = _interaction_world_marker_cache()
        local markers = _safe_world_markers_list()

        if not markers then
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

    --- Returns where and how large the game draws its interaction marker for a unit.
    -- ?Unit: unit unit to look up
    -- treturn: ?number marker centre x in UI space
    -- treturn: ?number marker centre y in UI space
    -- treturn: ?number icon size, or the ring size, or 0
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

    --- Returns the player camera of the HUD that owns a HUD element.
    -- tab: hud_element HUD element
    -- return: camera, or nil
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

    --- Returns the HUD player camera position.
    -- treturn: ?tab `{ x, y, z }`
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

    --- Returns the HUD player camera rotation.
    -- return: rotation, or nil
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

    --- Returns the local player's vertical field of view in radians.
    -- treturn: ?number
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

    --- Returns a rotation's forward, right and up axes as plain tables.
    -- treturn: ?tab `{ forward, right, up }`, nil when an axis is not finite
    local function _hud_rotation_basis(rotation)
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

    --- Returns the level's physics world from the physics manager or the level world.
    local function _safe_hud_physics_world()
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

    --- Extracts a hit distance from one raycast return value (a number, a hit table or a list of hits).
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

    --- Returns the first hit distance found among the raycast return values, whose layout varies by call.
    local function _extract_hud_raycast_distance(a, b, c, d)
        return _extract_hud_raycast_distance_from_value(a)
            or _extract_hud_raycast_distance_from_value(b)
            or _extract_hud_raycast_distance_from_value(c)
            or _extract_hud_raycast_distance_from_value(d)
    end

    --- Returns whether level geometry blocks the line of sight from the camera to a world position.
    -- Casts one ray per occlusion filter until a filter reports a hit; any failure counts as
    -- visible.
    -- tab: camera_position camera position
    -- tab: world_position target position
    -- treturn: bool
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

    --- Builds the camera data needed to project world positions onto the HUD for one frame.
    -- Uses the HUD player camera, or the fallbacks when it is unavailable, and a 65 degree
    -- vertical field of view when none can be read.
    -- tab: hud_element HUD element
    -- ?tab: fallback_camera_position camera position used without a HUD camera
    -- param: fallback_rotation rotation used without a HUD camera
    -- treturn: ?tab projection context, nil without a camera position or basis
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

    --- Projects a world position into UI space with a projection context.
    -- Positions behind the camera or outside the view are rejected.
    -- ?tab: world_position world position
    -- ?tab: projection_context context from `get_hud_projection_context`
    -- treturn: ?number screen x
    -- treturn: ?number screen y
    -- treturn: ?tab camera position used
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

    --- Projects a world position into UI space, building the projection context first.
    -- treturn: ?number screen x
    -- treturn: ?number screen y
    -- treturn: ?tab camera position used
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

    --- Returns the on-screen highlight bracket size for a distance, shrinking from 24 px at 5 m to 18 px at 20 m.
    -- ?number: distance_sq squared distance to the target
    -- treturn: number
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

    -- ----------------------------------------------------------------------------
    -- Screen highlights
    -- ----------------------------------------------------------------------------

    --- Returns the emptied highlight output list stored on `mod`, creating it on first use.
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

    --- Returns the UI interaction type of a unit's interactee extension, in lower case.
    local function _safe_interactee_ui_interaction_type(unit, interactee_extension_map)
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

    --- Returns the world position a highlight bracket is anchored to for the occlusion test.
    -- Uses the unit's `ui_interaction_marker` node, then its origin, then the target's stored
    -- position, raised by the kind's offset and a further 0.8 m for pickups.
    -- tab: target radar target
    -- ?tab: interactee_extension_map interactee extensions by unit
    -- treturn: ?tab `{ x, y, z }`
    local function _screen_highlight_anchor_position(target, interactee_extension_map)
        local unit = target and target.unit or nil
        local position = target and target.position

        local anchor_position = nil
        local node_position = nil

        if unit then
            node_position = _safe_unit_node_position(unit, "ui_interaction_marker")
            anchor_position = node_position or _safe_unit_position(unit)
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

    --- Returns the centre of a unit's oriented bounding box.
    -- A prefab's root is wherever its author put the pivot, which on a wall-mounted terminal is
    -- the mounting point rather than the panel, and a highlight bracket wants the middle of what
    -- it frames. `Unit.box` returns the box's pose and half extents, and the pose's translation
    -- is its centre; the Strikemap mod uses the same call to centre its door bars on the leaf
    -- instead of the hinge. These engine functions are checked for existence and called through
    -- `pcall`, and any failure simply means no box, so the caller keeps the origin.
    -- param: unit unit handle
    -- treturn: ?tab `{ x, y, z }`
    function _safe_unit_box_center(unit)
        if not _safe_unit_alive(unit) then
            return nil
        end

        local unit_api = Unit
        local box = unit_api and unit_api.box
        local matrix_api = Matrix4x4
        local translation = matrix_api and matrix_api.translation

        if not box or not translation then
            return nil
        end

        local ok_box, pose = pcall(box, unit)

        if not ok_box or pose == nil then
            return nil
        end

        local ok_center, center = pcall(translation, pose)

        if not ok_center or center == nil then
            return nil
        end

        return _copy_vector3(center)
    end

    --- Returns where a highlight bracket is placed when the game draws no interaction marker for the unit.
    -- For a scan target that is always the case. The anchor position only feeds the occlusion
    -- test on the path where the game's marker exists; it never positions the bracket. A hazard
    -- barrel is placed on the live `c_explosion` node the game detonates from, then on its
    -- tracked position, since a hanging barrel's origin is its ceiling mount.
    -- tab: target radar target
    -- treturn: ?tab `{ x, y, z }`
    function _screen_highlight_projection_fallback_position(target)
        local unit = target and target.unit or nil
        local kind = target and target.kind or nil
        local position = nil

        if unit then
            -- Objectives are framed on the middle of the prop. Pickups keep their
            -- origin on purpose (#103): their `ui_interaction_marker` floats above
            -- the item where the prompt goes, and with no prompt showing a
            -- bracket up there looks detached, so the lower anchor is right for
            -- them. A scan target is the opposite case -- a wall terminal whose
            -- root is its mounting point -- and the bracket sat above and beside
            -- the panel the auspex had to be pointed at. All six scan targets of
            -- an Archivum Sycorax run had neither the game's marker nor a node,
            -- so this is the only thing that can place them.
            if type(kind) == "string" and kind:sub(1, 18) == "mission_objective_" then
                position = _safe_unit_box_center(unit)
            elseif kind == "hazard_explosive_barrel" or kind == "hazard_fire_barrel" then
                position = _safe_unit_node_position(unit, "c_explosion") or target.position
            end

            position = position or _safe_unit_position(unit)
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

    --- Copies a target list into a reused destination list.
    -- ?tab: targets source list
    -- ?tab: destination list to overwrite, created when nil
    -- treturn: tab
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

    --- Returns the squared 3D distance between two positions, `math.huge` when either is missing or invalid.
    -- treturn: number
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

    --- Collects the radar targets that get a nearby highlight bracket this frame.
    -- Considers the highlight source targets kept by tracking (falling back to the unclustered
    -- and then the drawn radar targets) that lie within the highlight range, belong to a settings
    -- group with highlights enabled and are not of an excluded kind. Each entry carries the anchor and
    -- fallback positions, the highlight colour (following the marker's puzzle state colour) and
    -- the colour used while occluded. The output list is reused between frames.
    -- treturn: tab highlight entries
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
        local marker_color_kind = mod.get_marker_color_kind or function(_, kind)
            return kind
        end
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

                    -- This screen-space bracket is gated separately from the radar-side
                    -- highlight (`is_nearby_highlight_enabled_for_kind`), so it applies the
                    -- per-kind exclusion list itself; without this an excluded kind still
                    -- gets a bracket drawn around it in the world.
                    if enabled and NEARBY_HIGHLIGHT_EXCLUDED_KINDS[kind] then
                        enabled = false
                    end

                    highlight_enabled_by_kind[kind] = enabled
                end

                if enabled then
                    local position = target.position
                    local distance_sq = target.distance_sq_3d

                    if distance_sq == nil and position then
                        distance_sq = distance_squared(player_pos, position)
                    end

                    if distance_sq ~= nil and distance_sq <= max_distance_sq then
                        -- Follows the radar marker, so a puzzle's bracket and its
                        -- dot never disagree about whether it needs a player, in
                        -- view or behind level geometry.
                        local color_kind = marker_color_kind(mod, kind, target.meta)
                        local color = screen_highlight_color_for_kind(color_kind)
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
                                    get_occluded_highlight_color(mod, color_kind, NEARBY_OUTLINE_OCCLUDED_MULTIPLIER) or
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

end
