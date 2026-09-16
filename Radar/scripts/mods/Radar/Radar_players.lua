return function(env)
    setfenv(1, env)

    local mod = mod
    local GameSession = GameSession
    local PlayerUnitVisualLoadout = PlayerUnitVisualLoadout
    local pcall = pcall
    local pairs = pairs
    local rawget = rawget
    local tonumber = tonumber
    local tostring = tostring
    local type = type
    local math_floor = math.floor
    local math_huge = math.huge
    local string_format = string.format

    local table_clear = table.clear or function(t)
        for k in pairs(t) do
            t[k] = nil
        end
    end

    -- ----------------------------------------------------------------------------
    -- Constants
    -- ----------------------------------------------------------------------------

    local PLAYER_SMART_TAG_KINDS = {
        location_attention = true,
        location_ping = true,
        location_threat = true,
    }
    local SERVO_SKULL_OWNER_HIDE_DISTANCE_SQ = 2.5 * 2.5
    local COMPANION_TARGET_OVERLAP_DISTANCE_SQ = 2 * 2
    local SERVO_SKULL_STATES = CompanionServoSkullSettings.STATES
    local ABILITY_OUTLINE_BRACKET_ALPHA = 220
    local SUPPORTED_ABILITY_OUTLINE_CONFIG_BY_NAME = {
        psyker_marked_target = {
            default_color = { 255, 80, 160, 255 },
            default_priority = 1,
        },
        veteran_smart_tag = {
            default_color = { ABILITY_OUTLINE_BRACKET_ALPHA, 255, 204, 102 },
            default_priority = 1,
        },
        adamant_mark_target = {
            default_color = { ABILITY_OUTLINE_BRACKET_ALPHA, 128, 102, 255 },
            default_priority = 2,
        },
        adamant_smart_tag = {
            default_color = { ABILITY_OUTLINE_BRACKET_ALPHA, 255, 64, 64 },
            default_priority = 2,
        },
        broker_proximity_target = {
            default_color = { ABILITY_OUTLINE_BRACKET_ALPHA, 122, 204, 245 },
            default_priority = 2,
        },
        special_target = {
            default_priority = 3,
        },
    }
    local VETERAN_SPECIAL_TARGET_BRACKET_COLOR = { 255, 220, 120, 26 }
    local OGRYN_TAUNT_SHOUT_ABILITY_NAME = "ogryn_taunt_shout"
    local PLAYER_CAPTURE_DISABLING_TYPES = {
        grabbed = true,
        consumed = true,
        mutant_charged = true,
        netted = true,
        pounced = true,
    }
    local SLOT_LUGGABLE = "slot_luggable"

    -- ----------------------------------------------------------------------------
    -- Mutable runtime state
    -- ----------------------------------------------------------------------------

    local _scratch_seen_player_tag_ids = {}
    local _scratch_seen_radar_players = {}
    local _scratch_mastiff_disabled_enemy_units = {}
    local CACHED_ABILITY_OUTLINE_BRACKET_COLORS = {}

    -- ----------------------------------------------------------------------------
    -- Player kinds and tag attribution
    -- ----------------------------------------------------------------------------

    function _is_player_smart_tag_kind(kind)
        return kind == "location_attention"
            or kind == "location_ping"
            or kind == "location_threat"
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

    -- ----------------------------------------------------------------------------
    -- Ability outline markers
    -- ----------------------------------------------------------------------------


    local function _supported_ability_outline_config(outline_name)
        if outline_name == nil then
            return nil
        end

        return SUPPORTED_ABILITY_OUTLINE_CONFIG_BY_NAME[tostring(outline_name)]
    end

    local function _special_target_local_context(player_unit)
        if not _safe_unit_alive(player_unit) then
            return nil
        end

        if _safe_unit_has_keyword(player_unit, "veteran_combat_ability_stance") then
            return "veteran_executioners_stance"
        end

        return nil
    end

    local function _special_target_fallback_bracket_color()
        local player_unit = _player_unit()
        local local_context = _special_target_local_context(player_unit)

        if local_context == "veteran_executioners_stance" then
            return VETERAN_SPECIAL_TARGET_BRACKET_COLOR
        end

        return nil
    end

    local function _default_ability_outline_bracket_color(outline_name)
        local config = _supported_ability_outline_config(outline_name)

        if not config then
            return nil
        end

        if outline_name == "special_target" then
            return _special_target_fallback_bracket_color()
        end

        return config.default_color
    end

    local function _cached_ability_outline_bracket_color(outline_name, color)
        if type(color) ~= "table" then
            return _default_ability_outline_bracket_color(outline_name)
        end

        local alpha = tonumber(color.a)
        local red = tonumber(color.r)
        local green = tonumber(color.g)
        local blue = tonumber(color.b)

        if red == nil and green == nil and blue == nil then
            local fourth = tonumber(color[4])

            if fourth ~= nil then
                alpha = tonumber(color[1])
                red = tonumber(color[2])
                green = tonumber(color[3])
                blue = fourth
            else
                red = tonumber(color[1])
                green = tonumber(color[2])
                blue = tonumber(color[3])
            end
        end

        if not red or not green or not blue then
            return _default_ability_outline_bracket_color(outline_name)
        end

        if red <= 1 and green <= 1 and blue <= 1 then
            red = red * 255
            green = green * 255
            blue = blue * 255
        end

        if alpha == nil then
            alpha = ABILITY_OUTLINE_BRACKET_ALPHA
        elseif alpha <= 1 then
            alpha = alpha * 255
        end

        alpha = _clamp(math_floor(alpha + 0.5), 0, 255)
        red = _clamp(math_floor(red + 0.5), 0, 255)
        green = _clamp(math_floor(green + 0.5), 0, 255)
        blue = _clamp(math_floor(blue + 0.5), 0, 255)

        local cache_key = tostring(outline_name) .. ":" .. tostring(alpha) .. ":" .. tostring(red) .. ":" ..
            tostring(green) .. ":" .. tostring(blue)
        local cached_color = CACHED_ABILITY_OUTLINE_BRACKET_COLORS[cache_key]

        if cached_color == nil then
            cached_color = {
                alpha,
                red,
                green,
                blue,
            }
            CACHED_ABILITY_OUTLINE_BRACKET_COLORS[cache_key] = cached_color
        end

        return cached_color
    end

    local function _outline_setting_bracket_color(outline_extension, outline_name)
        if type(outline_extension) ~= "table" or outline_name == nil then
            return nil
        end

        local settings = rawget(outline_extension, "settings")
        local outline_settings = type(settings) == "table" and settings[outline_name] or nil
        local color = type(outline_settings) == "table" and rawget(outline_settings, "color") or nil

        return _cached_ability_outline_bracket_color(outline_name, color)
    end

    local function _outline_setting_priority(outline_extension, outline_name)
        if outline_name == nil then
            return 0
        end

        local priority = nil

        if type(outline_extension) == "table" then
            local settings = rawget(outline_extension, "settings")
            local outline_settings = type(settings) == "table" and settings[outline_name] or nil
            priority = type(outline_settings) == "table" and tonumber(rawget(outline_settings, "priority")) or nil
        end

        if priority == nil then
            local config = _supported_ability_outline_config(outline_name)
            priority = config and config.default_priority or 0
        end

        return priority or 0
    end

    local function _supported_ability_outline_state_for_unit(unit, outline_extension_map, local_player_unit)
        local outline_extension = _safe_unit_outline_extension(unit, outline_extension_map)

        if type(outline_extension) ~= "table" then
            return nil, nil
        end

        local outlines = rawget(outline_extension, "outlines")

        if type(outlines) ~= "table" or #outlines == 0 then
            return nil, nil
        end

        local outline_names = nil
        local seen_outline_names = nil
        local bracket_color = nil
        local primary_outline_name = nil
        local primary_outline_priority = -math_huge
        local bracket_outline_priority = -math_huge
        local special_target_allowed = _special_target_local_context(local_player_unit) ~= nil

        for i = 1, #outlines do
            local outline = outlines[i]
            local outline_name = outline and outline.name and tostring(outline.name) or nil

            if outline_name ~= nil
                and _supported_ability_outline_config(outline_name) ~= nil
                and (outline_name ~= "special_target" or special_target_allowed) then
                if seen_outline_names == nil or not seen_outline_names[outline_name] then
                    seen_outline_names = seen_outline_names or {}
                    seen_outline_names[outline_name] = true
                    outline_names = outline_names or {}
                    outline_names[#outline_names + 1] = outline_name
                end

                local outline_priority = _outline_setting_priority(outline_extension, outline_name)

                if outline_priority > primary_outline_priority then
                    primary_outline_name = outline_name
                    primary_outline_priority = outline_priority
                end

                local outline_bracket_color = _outline_setting_bracket_color(outline_extension, outline_name)

                if outline_bracket_color ~= nil and outline_priority > bracket_outline_priority then
                    bracket_color = outline_bracket_color
                    bracket_outline_priority = outline_priority
                end
            end
        end

        return outline_names, bracket_color, primary_outline_name, primary_outline_priority
    end

    local function _unit_has_supported_ogryn_taunt_marker(unit)
        return _safe_unit_has_keyword(unit, "taunted")
            or _safe_unit_has_buff_template(unit, "taunted")
            or _safe_unit_has_buff_template(unit, "taunted_short")
    end

    function _supported_ability_marker_state_for_unit(unit, outline_extension_map, local_player_unit, local_combat_ability_name)
        local marker_names, bracket_color, primary_marker_name, primary_marker_priority = _supported_ability_outline_state_for_unit(unit, outline_extension_map, local_player_unit)

        if marker_names ~= nil then
            return marker_names, bracket_color, primary_marker_name, primary_marker_priority
        end

        if local_combat_ability_name == OGRYN_TAUNT_SHOUT_ABILITY_NAME
            and _unit_has_supported_ogryn_taunt_marker(unit) then
            return { OGRYN_TAUNT_SHOUT_ABILITY_NAME }, nil, OGRYN_TAUNT_SHOUT_ABILITY_NAME, 0
        end

        return nil, nil, nil, nil
    end

    -- ----------------------------------------------------------------------------
    -- Companion and player state helpers
    -- ----------------------------------------------------------------------------

    local function _player_companion_kind(unit, has_extension)
        if not unit or not has_extension or not _safe_unit_alive(unit) then
            return nil
        end

        local unit_data_extension = has_extension(unit, "unit_data_system")
        local breed_fn = unit_data_extension and unit_data_extension.breed

        if not breed_fn then
            return nil
        end

        local ok_breed, breed = pcall(breed_fn, unit_data_extension)
        local tags = ok_breed and breed and breed.tags or nil

        if not tags or tags.companion ~= true then
            return nil
        end

        local breed_name = breed.name

        if breed_name == "companion_dog" then
            return "player_companion_dog"
        elseif breed_name == "companion_servo_skull" then
            return "player_companion_servo_skull"
        end

        return nil
    end

    local function _companion_dog_target_uses_disable_action(unit, has_extension)
        local unit_data_extension = has_extension and has_extension(unit, "unit_data_system")
        local breed_fn = unit_data_extension and unit_data_extension.breed

        if not breed_fn then
            return false
        end

        local ok_breed, breed = pcall(breed_fn, unit_data_extension)
        local pounce_setting = ok_breed and breed and breed.companion_pounce_setting or nil

        return pounce_setting and pounce_setting.companion_pounce_action == "human" or false
    end

    local function _safe_spawned_companion_unit(companion_spawner_extension, special_rule)
        local lookup_fn = companion_spawner_extension and companion_spawner_extension.spawned_unit_lookup

        if not lookup_fn then
            return nil
        end

        local ok_lookup, unit = pcall(lookup_fn, companion_spawner_extension, special_rule)

        return ok_lookup and unit or nil
    end

    local function _safe_unit_game_object_field(unit, field_name)
        local state = Managers and Managers.state
        local game_session_manager = state and state.game_session
        local unit_spawner_manager = state and state.unit_spawner
        local game_session_fn = game_session_manager and game_session_manager.game_session
        local game_object_id_fn = unit_spawner_manager and unit_spawner_manager.game_object_id
        local game_object_field = GameSession and GameSession.game_object_field
        local game_object_exists = GameSession and GameSession.game_object_exists

        if not game_session_fn or not game_object_id_fn or not game_object_field then
            return nil
        end

        local ok_session, game_session = pcall(game_session_fn, game_session_manager)
        local ok_id, game_object_id = pcall(game_object_id_fn, unit_spawner_manager, unit)

        if not ok_session or not game_session or not ok_id or game_object_id == nil then
            return nil
        end

        if game_object_exists then
            local ok_exists, exists = pcall(game_object_exists, game_session, game_object_id)

            if not ok_exists or not exists then
                return nil
            end
        end

        local ok_field, value = pcall(game_object_field, game_session, game_object_id, field_name)

        return ok_field and value or nil
    end

    local function _safe_unit_from_game_object_id(game_object_id)
        if game_object_id == nil then
            return nil
        end

        local state = Managers and Managers.state
        local unit_spawner_manager = state and state.unit_spawner
        local unit_fn = unit_spawner_manager and unit_spawner_manager.unit

        if not unit_fn then
            return nil
        end

        local ok_unit, unit = pcall(unit_fn, unit_spawner_manager, game_object_id)

        return ok_unit and _safe_unit_alive(unit) and unit or nil
    end

    local function _safe_companion_dog_target(unit)
        local blackboard = BLACKBOARDS and BLACKBOARDS[unit]
        local pounce_component = blackboard and blackboard.pounce
        local pounce_target = pounce_component and pounce_component.pounce_target or nil

        if pounce_target
            and (pounce_component.has_pounce_target or pounce_component.has_pounce_started)
            and _safe_unit_alive(pounce_target) then
            return pounce_target, true
        end

        local target_unit_id = _safe_unit_game_object_field(unit, "target_unit_id")
        local target_unit = _safe_unit_from_game_object_id(target_unit_id)

        if pounce_component then
            return target_unit, false
        end

        return target_unit, nil
    end

    local function _servo_skull_state_is(state, state_name)
        return state == state_name or state == SERVO_SKULL_STATES[state_name]
    end

    local function _safe_player_component(unit_data_extension, component_name)
        if not unit_data_extension or not unit_data_extension.read_component then
            return nil
        end

        local ok, component = pcall(unit_data_extension.read_component, unit_data_extension, component_name)

        return ok and component or nil
    end

    -- Whether a player is carrying a luggable: wielding the luggable slot with
    -- something equipped in it.
    function _unit_carries_luggable(unit, has_extension)
        local unit_data_extension = has_extension and has_extension(unit, "unit_data_system") or nil
        local inventory_component = _safe_player_component(unit_data_extension, "inventory")

        if not inventory_component or inventory_component.wielded_slot ~= SLOT_LUGGABLE then
            return false
        end

        local visual_loadout_extension = has_extension(unit, "visual_loadout_system")
        local slot_equipped = PlayerUnitVisualLoadout and PlayerUnitVisualLoadout.slot_equipped

        if not visual_loadout_extension or not slot_equipped then
            return false
        end

        local ok, equipped = pcall(slot_equipped, inventory_component, visual_loadout_extension, SLOT_LUGGABLE)

        return ok and equipped and true or false
    end

    local function _player_radar_state(unit, has_extension)
        local unit_data_extension = has_extension and has_extension(unit, "unit_data_system") or nil
        local character_state_component = _safe_player_component(unit_data_extension, "character_state")
        local state_name = character_state_component and character_state_component.state_name or nil

        if state_name == "hogtied" then
            return "rescue"
        end

        if state_name == "dead" or _safe_health_alive(unit) == false then
            return "dead"
        end

        if state_name == "knocked_down" or state_name == "ledge_hanging" then
            return "rescue"
        end

        local disabled_state_component = _safe_player_component(unit_data_extension, "disabled_character_state")
        local disabling_type = disabled_state_component
            and disabled_state_component.is_disabled
            and disabled_state_component.disabling_type or nil

        if PLAYER_CAPTURE_DISABLING_TYPES[disabling_type] then
            return "captured"
        end

        if _unit_carries_luggable(unit, has_extension) then
            return "luggable"
        end

        return nil
    end

    -- ----------------------------------------------------------------------------
    -- Player and companion scan
    -- ----------------------------------------------------------------------------

    function _refresh_player_units()
        local mastiff_disabled_enemy_units = _scratch_mastiff_disabled_enemy_units
        table_clear(mastiff_disabled_enemy_units)

        local player_manager = _player_manager()
        if not player_manager or not player_manager.players then
            return
        end

        local local_player = _local_player()
        local players = player_manager:players()
        local script_unit = ScriptUnit
        local has_extension = script_unit and script_unit.has_extension
        local radar_player_unit_by_player = mod._radar_player_unit_by_player or {}
        local seen_radar_players = _scratch_seen_radar_players
        local scan_player_states = mod:get("show_player_state_icons") ~= false
            and mod:get_show_players()
        local show_cyber_mastiff = mod:get("show_cyber_mastiff") ~= false
        local scan_player_companions = show_cyber_mastiff
            or mod:get("show_servo_skulls") ~= false

        mod._radar_player_unit_by_player = radar_player_unit_by_player
        table_clear(seen_radar_players)

        for _, player in pairs(players) do
            local unit = player.player_unit
            local unit_alive = unit and _safe_unit_alive(unit)
            local player_radar_state = unit_alive
                and player ~= local_player
                and scan_player_states
                and _player_radar_state(unit, has_extension) or nil

            if player ~= local_player then
                seen_radar_players[player] = true

                if unit_alive then
                    local previous_unit = radar_player_unit_by_player[player]

                    if previous_unit and previous_unit ~= unit then
                        _clear_tracked_unit_from_source(previous_unit, "player_manager")
                    end

                    radar_player_unit_by_player[player] = unit
                end
            end

            if scan_player_companions and unit_alive then
                local player_slot = _safe_player_slot(player)
                local owner_marker_visible

                if player == local_player then
                    owner_marker_visible = mod:get_show_player_center_dot()
                else
                    owner_marker_visible = mod:get_show_players()
                end

                local companion_spawner_extension = has_extension and
                    has_extension(unit, "companion_spawner_system") or nil
                local owned_units = player.owned_units
                local hack_skull = nil
                local medicae_skull = nil
                local flamer_skull = nil
                local servo_skull_roles_resolved = false

                if type(owned_units) == "table" then
                    for owned_unit, _ in pairs(owned_units) do
                        local companion_kind = _player_companion_kind(owned_unit, has_extension)

                        if companion_kind then
                            local servo_skull_role = nil
                            local servo_skull_following_owner = false
                            local companion_action = nil
                            local companion_action_target = nil
                            local companion_pounce_active = nil

                            if companion_kind == "player_companion_servo_skull" then
                                if not servo_skull_roles_resolved then
                                    hack_skull = _safe_spawned_companion_unit(
                                        companion_spawner_extension,
                                        "cryptic_servo_skull_hack"
                                    )
                                    medicae_skull = _safe_spawned_companion_unit(
                                        companion_spawner_extension,
                                        "cryptic_servo_skull_inject_ally"
                                    )
                                    flamer_skull = _safe_spawned_companion_unit(
                                        companion_spawner_extension,
                                        "cryptic_servo_skull_flamethrower"
                                    )
                                    servo_skull_roles_resolved = true
                                end

                                if owned_unit == medicae_skull then
                                    servo_skull_role = "medicae"
                                elseif owned_unit == flamer_skull then
                                    servo_skull_role = "flamer"
                                elseif owned_unit == hack_skull then
                                    servo_skull_role = "default"
                                end

                                local servo_skull_state = _safe_unit_game_object_field(owned_unit, "state")

                                if _servo_skull_state_is(servo_skull_state, "hacking") then
                                    companion_action = "hacking"
                                elseif _servo_skull_state_is(servo_skull_state, "inject_ally") then
                                    companion_action = "inject_ally"
                                elseif _servo_skull_state_is(servo_skull_state, "flamethrower")
                                    or _servo_skull_state_is(servo_skull_state, "flamethrower_shooting") then
                                    companion_action = "flamethrower"
                                elseif _servo_skull_state_is(servo_skull_state, "following")
                                    or _servo_skull_state_is(servo_skull_state, "following_shooting")
                                    or _servo_skull_state_is(servo_skull_state, "following_shooting_ability") then
                                    servo_skull_following_owner = true
                                end
                            elseif companion_kind == "player_companion_dog" then
                                companion_action_target, companion_pounce_active =
                                    _safe_companion_dog_target(owned_unit)

                                if show_cyber_mastiff
                                    and companion_action_target
                                    and companion_pounce_active ~= false
                                    and _companion_dog_target_uses_disable_action(
                                        companion_action_target,
                                        has_extension
                                    ) then
                                    local companion_position = _safe_unit_position(owned_unit)
                                    local target_position = _safe_unit_position(companion_action_target)

                                    if companion_position
                                        and target_position
                                        and _distance_squared_horizontal(companion_position, target_position) <=
                                        COMPANION_TARGET_OVERLAP_DISTANCE_SQ then
                                        mastiff_disabled_enemy_units[companion_action_target] = true
                                    end
                                end
                            end

                            _track_unit(owned_unit, companion_kind, "player_companion", {
                                player_slot = player_slot,
                                owner_unit = unit,
                                owner_marker_visible = owner_marker_visible,
                                servo_skull_following_owner = servo_skull_following_owner,
                                servo_skull_role = servo_skull_role,
                                companion_action = companion_action,
                                companion_action_target = companion_action_target,
                            })
                        end
                    end
                end
            end

            if unit_alive and player ~= local_player then
                local archetype_name = nil
                local player_name = nil
                local player_slot = _safe_player_slot(player)

                local ok_player_name, resolved_player_name = pcall(player.name, player)
                if ok_player_name then
                    player_name = resolved_player_name
                end

                local ok_profile, profile = pcall(player.profile, player)
                if ok_profile and profile and profile.archetype and profile.archetype.name then
                    archetype_name = profile.archetype.name
                end

                local unit_data_extension = has_extension and has_extension(unit, "unit_data_system")
                if unit_data_extension and unit_data_extension.archetype_name then
                    local ok_archetype, value = pcall(unit_data_extension.archetype_name, unit_data_extension)
                    if ok_archetype and value ~= nil then
                        archetype_name = value
                    end
                end

                _track_unit(unit, "player_teammate", "player_manager", {
                    player = player_name,
                    player_slot = player_slot,
                    archetype_name = archetype_name,
                    player_radar_state = player_radar_state,
                })
            end
        end

        for player, unit in pairs(radar_player_unit_by_player) do
            if not seen_radar_players[player] then
                _clear_tracked_unit_from_source(unit, "player_manager")
                radar_player_unit_by_player[player] = nil
            end
        end
    end

    -- ----------------------------------------------------------------------------
    -- Companion target rules
    -- ----------------------------------------------------------------------------

    -- A companion at work is drawn on the companion layer: a skull hacking,
    -- injecting or burning, or a mastiff on top of the target it is holding.
    function _player_companion_action_active(kind, position, meta)
        local companion_action = meta and meta.companion_action or nil
        local companion_action_target = meta and meta.companion_action_target or nil
        local companion_target_position = companion_action_target and
            _safe_unit_position(companion_action_target) or nil
        local companion_overlapping_target = kind == "player_companion_dog"
            and companion_target_position ~= nil
            and _distance_squared_horizontal(position, companion_target_position) <=
            COMPANION_TARGET_OVERLAP_DISTANCE_SQ

        return companion_action == "hacking"
            or companion_action == "inject_ally"
            or companion_action == "flamethrower"
            or companion_overlapping_target
    end

    -- A servo skull following its owner sits on the owner's own marker.
    function _is_servo_skull_hidden_by_owner(position, meta)
        if meta
            and meta.owner_marker_visible
            and meta.servo_skull_following_owner then
            local owner_position = _safe_unit_position(meta.owner_unit)

            if owner_position
                and _distance_squared_horizontal(owner_position, position) <=
                SERVO_SKULL_OWNER_HIDE_DISTANCE_SQ then
                return true
            end
        end

        return false
    end

    -- Enemies a mastiff is holding down, refilled by every player scan.
    function _mastiff_disabled_enemy_units()
        return _scratch_mastiff_disabled_enemy_units
    end

    -- ----------------------------------------------------------------------------
    -- Player smart tags
    -- ----------------------------------------------------------------------------

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
            _reset_player_smart_tag_states()
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

    -- ----------------------------------------------------------------------------
    -- Public interface
    -- ----------------------------------------------------------------------------

    function mod:get_player_display_style()
        local value = self:get("show_players")

        if value ~= "icon_only"
            and value ~= "marked_icon"
            and value ~= "dot_only"
            and value ~= "marked_dot" then
            value = self:get("player_display_style")
        end

        value = tostring(value or "marked_icon")

        if value ~= "icon_only"
            and value ~= "marked_icon"
            and value ~= "dot_only"
            and value ~= "marked_dot" then
            value = "marked_icon"
        end

        return value
    end

    function mod:get_show_players()
        local value = self:get("show_players")

        if value == nil then
            value = self:get("show_teammates")
        end

        return value ~= false and value ~= "off"
    end

    function mod:get_show_player_center_dot()
        local value = self:get("show_player_center_dot")

        return value ~= false and value ~= "off"
    end

    function mod:get_player_marker_range_mode()
        local value = tostring(self:get("player_marker_range_mode") or "normal")

        if value ~= "infinite" then
            value = "normal"
        end

        return value
    end

end
