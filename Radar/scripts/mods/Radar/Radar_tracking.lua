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
    local math_abs = math.abs
    local math_floor = math.floor
    local math_huge = math.huge
    local math_max = math.max
    local math_min = math.min
    local math_sqrt = math.sqrt
    local string_find = string.find
    local string_format = string.format
    local string_gmatch = string.gmatch
    local string_gsub = string.gsub
    local string_lower = string.lower
    local string_sub = string.sub
    local table_concat = table.concat
    local table_sort = table.sort
    local table_clear = table.clear or function(t)
        for k in pairs(t) do
            t[k] = nil
        end
    end
    local os_clock = os and os.clock or nil


    local function _reuse_or_new_table(t)
        if t then
            table_clear(t)
            return t
        end

        return {}
    end

    local function _reset_runtime_output_tables()
        mod._tracked_points = _reuse_or_new_table(mod._tracked_points)
        mod._radar_targets = _reuse_or_new_table(mod._radar_targets)
        mod._screen_highlight_targets = _reuse_or_new_table(mod._screen_highlight_targets)
        mod._unclustered_radar_targets = _reuse_or_new_table(mod._unclustered_radar_targets)
        mod._highlight_source_radar_targets = _reuse_or_new_table(mod._highlight_source_radar_targets)
        mod._radar_snapshot = nil
    end

    local function _reset_tracked_units_table()
        mod._tracked_units = _reuse_or_new_table(mod._tracked_units)
        mod._radar_player_unit_by_player = _reuse_or_new_table(mod._radar_player_unit_by_player)
    end

    local _scratch_kind_enabled_cache = {}
    local _scratch_ignore_range_cache = {}
    local _scratch_infinite_range_cache = {}
    local _scratch_supports_vertical_cache = {}
    local _scratch_render_layer_cache = {}
    local _scratch_selection_priority_cache = {}
    local _scratch_priority_target_cache = {}
    local _scratch_seen_interactees = {}
    local _scratch_seen_chests = {}
    local _scratch_seen_destructibles = {}
    local _scratch_seen_hazard_props = {}
    local _scratch_seen_radar_players = {}
    local _scratch_mastiff_disabled_enemy_units = {}
    local _scratch_minion_kind_enabled_cache = {}
    local OVERVIEW_MIN_ZOOM_RANGE = 25
    local OVERVIEW_MAX_ZOOM_RANGE = 500
    local OVERVIEW_DEFAULT_ZOOM_RANGE = OVERVIEW_MAX_ZOOM_RANGE
    local OVERVIEW_SCREEN_PADDING = 80
    local OVERVIEW_RANGE_TRANSITION_DURATION = 0.28
    local OVERVIEW_RANGE_TRANSITION_SCAN_INTERVAL = 0.05
    -- Static or slow-changing sources (interactables, chests, destructibles,
    -- hazard props, deployed smart-tag targets) are rescanned less often than
    -- enemies and players. Dead/despawned units are still removed at the fast
    -- cadence by `_prune_units`.
    local STATIC_SCAN_INTERVAL = SCAN_INTERVAL * 2
    local OVERVIEW_RESET_FIT_EDGE_FRACTION = 0.9
    local OVERVIEW_RADAR_MARKER_LIMIT = 300
    local NORMAL_RADAR_MIN_ZOOM_RANGE = 10
    local NORMAL_RADAR_MAX_ZOOM_RANGE = 200
    local NORMAL_RADAR_DEFAULT_ZOOM_RANGE = NORMAL_RADAR_MAX_ZOOM_RANGE
    local NORMAL_RADAR_RESET_ZOOM_RANGE = NORMAL_RADAR_MIN_ZOOM_RANGE
    local NORMAL_RADAR_ZOOM_MODIFIER_GRACE = 0.12
    local NORMAL_RADAR_ZOOM_INDICATOR_DURATION = 1
    local SERVO_SKULL_OWNER_HIDE_DISTANCE_SQ = 2.5 * 2.5
    local COMPANION_TARGET_OVERLAP_DISTANCE_SQ = 2 * 2
    local COMPANION_ACTION_RENDER_LAYER = 6
    local SERVO_SKULL_STATES = CompanionServoSkullSettings.STATES
    local OVERVIEW_CAPTURED_ACTIONS_BY_DIRECTION = {
        up = {
            tactical_overlay_scroll_up = true,
            wield_scroll_up = true,
        },
        down = {
            tactical_overlay_scroll_down = true,
            wield_scroll_down = true,
        },
    }

    local function _clear_scratch_radar_caches()
        table_clear(_scratch_kind_enabled_cache)
        table_clear(_scratch_ignore_range_cache)
        table_clear(_scratch_infinite_range_cache)
        table_clear(_scratch_supports_vertical_cache)
        table_clear(_scratch_render_layer_cache)
        table_clear(_scratch_selection_priority_cache)
        table_clear(_scratch_priority_target_cache)
    end

    local function _warm_radar_target_pool(min_size)
        local pool = mod._radar_target_pool or {}
        local target_size = math_floor(tonumber(min_size) or 0)
        mod._radar_target_pool = pool

        for i = #pool + 1, target_size do
            pool[i] = {}
        end

        return pool
    end

    local function _normalized_keybind_entry(value)
        if value == nil then
            return nil
        end

        local normalized = string_lower(tostring(value))
        normalized = string_gsub(normalized, "_", " ")
        normalized = string_gsub(normalized, "%s+", " ")
        normalized = string_gsub(normalized, "^%s+", "")
        normalized = string_gsub(normalized, "%s+$", "")

        return normalized
    end

    local function _keybind_uses_wheel_direction(binding, direction)
        if type(binding) ~= "table" then
            return false
        end

        for i = 1, #binding do
            local entry = _normalized_keybind_entry(binding[i])

            if entry and string_find(entry, "wheel", 1, true) and string_find(entry, direction, 1, true) then
                return true
            end
        end

        return false
    end

    local function _raw_device_button_held(device, local_name)
        if not device or not local_name then
            return false
        end

        local button_index = device.button_index
        local button = device.button

        if not button_index or not button then
            return false
        end

        local ok_index, index = pcall(button_index, local_name)

        if (not ok_index or not index) and string_find(local_name, "_", 1, true) then
            ok_index, index = pcall(button_index, string_gsub(local_name, "_", " "))
        end

        if not ok_index or not index then
            return false
        end

        local ok_value, value = pcall(button, index)

        return ok_value and (tonumber(value) or 0) > 0.5
    end

    local function _keyboard_modifier_alias_held(name)
        local keyboard = Keyboard

        if name == "shift" then
            return _raw_device_button_held(keyboard, "left shift")
                or _raw_device_button_held(keyboard, "right shift")
        elseif name == "ctrl" or name == "control" then
            return _raw_device_button_held(keyboard, "left ctrl")
                or _raw_device_button_held(keyboard, "right ctrl")
        elseif name == "alt" then
            return _raw_device_button_held(keyboard, "left alt")
                or _raw_device_button_held(keyboard, "right alt")
        end

        return false
    end

    local function _raw_input_button_held(name)
        local normalized = _normalized_keybind_entry(name)

        if not normalized or normalized == "" then
            return false
        end

        if _keyboard_modifier_alias_held(normalized) then
            return true
        end

        local raw_name = string_lower(tostring(name))
        raw_name = string_gsub(raw_name, "^%s+", "")
        raw_name = string_gsub(raw_name, "%s+$", "")

        local keyboard = Keyboard
        local mouse = Mouse

        if string_find(raw_name, "keyboard_", 1, true) == 1 then
            return _raw_device_button_held(keyboard, string_sub(raw_name, 10))
        elseif string_find(raw_name, "mouse_", 1, true) == 1 then
            return _raw_device_button_held(mouse, string_sub(raw_name, 7))
        end

        return _raw_device_button_held(keyboard, raw_name)
            or _raw_device_button_held(keyboard, normalized)
            or _raw_device_button_held(mouse, raw_name)
            or _raw_device_button_held(mouse, normalized)
    end

    local function _raw_input_combo_held(binding_entry)
        if binding_entry == nil then
            return false
        end

        local entry = tostring(binding_entry)
        local has_required_input = false

        for enabled_part in string_gmatch(entry, "([^+]+)") do
            local first = true

            for disabled_part in string_gmatch(enabled_part, "([^-]+)") do
                if first then
                    first = false
                    has_required_input = true

                    if not _raw_input_button_held(disabled_part) then
                        return false
                    end
                elseif _raw_input_button_held(disabled_part) then
                    return false
                end
            end
        end

        return has_required_input
    end

    local function _radar_zoom_modifier_binding_held()
        local binding = mod:get("radar_zoom_modifier_key")

        if type(binding) ~= "table" then
            return _raw_input_combo_held(binding)
        end

        for i = 1, #binding do
            if _raw_input_combo_held(binding[i]) then
                return true
            end
        end

        return false
    end

    local function _refresh_overview_input_capture()
        local capture_actions = mod._overview_capture_actions or {}
        local zoom_in_binding = mod:get("overview_zoom_in_key")
        local zoom_out_binding = mod:get("overview_zoom_out_key")
        local capture_wheel_up = _keybind_uses_wheel_direction(zoom_in_binding, "up")
            or _keybind_uses_wheel_direction(zoom_out_binding, "up")
        local capture_wheel_down = _keybind_uses_wheel_direction(zoom_in_binding, "down")
            or _keybind_uses_wheel_direction(zoom_out_binding, "down")

        table_clear(capture_actions)

        if capture_wheel_up then
            for action_name, _ in pairs(OVERVIEW_CAPTURED_ACTIONS_BY_DIRECTION.up) do
                capture_actions[action_name] = true
            end
        end

        if capture_wheel_down then
            for action_name, _ in pairs(OVERVIEW_CAPTURED_ACTIONS_BY_DIRECTION.down) do
                capture_actions[action_name] = true
            end
        end

        mod._overview_capture_actions = capture_actions
    end

    local function _configured_radar_origin(size)
        local radar_size = tonumber(size) or mod:get_configured_radar_size()
        local anchor = mod:get_radar_anchor()
        local offset_x = mod:get_radar_offset_x(radar_size)
        local offset_y = mod:get_radar_offset_y(radar_size)
        local x, y = _get_radar_origin_from_offsets(anchor, offset_x, offset_y, radar_size)

        return math_floor(x + 0.5), math_floor(y + 0.5)
    end

    local function _overview_radar_origin(size)
        local radar_size = tonumber(size) or mod:get_radar_size()
        local ui_width, ui_height = _get_ui_space_size()
        local x = math_floor((ui_width - radar_size) * 0.5 + 0.5)
        local y = math_floor((ui_height - radar_size) * 0.5 + 0.5)

        return x, y
    end

    local function _overview_max_radar_size()
        local ui_width, ui_height = _get_ui_space_size()
        local max_size = math_min(ui_width, ui_height) - OVERVIEW_SCREEN_PADDING

        if max_size < 100 then
            max_size = 100
        end

        return math_floor(max_size + 0.5)
    end

    local function _normalize_overview_zoom_range(value)
        local normalized = tonumber(value) or OVERVIEW_DEFAULT_ZOOM_RANGE

        if normalized < OVERVIEW_MIN_ZOOM_RANGE then
            normalized = OVERVIEW_MIN_ZOOM_RANGE
        elseif normalized > OVERVIEW_MAX_ZOOM_RANGE then
            normalized = OVERVIEW_MAX_ZOOM_RANGE
        end

        return math_floor(normalized + 0.5)
    end

    local function _normalize_normal_radar_zoom_range(value)
        local normalized = tonumber(value) or NORMAL_RADAR_DEFAULT_ZOOM_RANGE

        if normalized < NORMAL_RADAR_MIN_ZOOM_RANGE then
            normalized = NORMAL_RADAR_MIN_ZOOM_RANGE
        elseif normalized > NORMAL_RADAR_MAX_ZOOM_RANGE then
            normalized = NORMAL_RADAR_MAX_ZOOM_RANGE
        end

        return math_floor(normalized + 0.5)
    end

    local function _next_normal_radar_zoom_range(current_range, direction)
        local current = _normalize_normal_radar_zoom_range(current_range)

        if direction == "in" then
            if current > 150 then
                return 150
            elseif current > 100 then
                return 100
            elseif current > 75 then
                return 75
            elseif current > 50 then
                return 50
            elseif current > 25 then
                return 25
            end

            return 10
        elseif direction == "out" then
            if current < 25 then
                return 25
            elseif current < 50 then
                return 50
            elseif current < 75 then
                return 75
            elseif current < 100 then
                return 100
            elseif current < 150 then
                return 150
            end

            return 200
        end

        return current
    end

    local function _normal_radar_zoom_factor_hundredths(range)
        local normalized = _normalize_normal_radar_zoom_range(range)

        if normalized <= 10 then
            return 200
        elseif normalized <= 25 then
            return math_floor(200 - (normalized - 10) * 25 / 15 + 0.5)
        elseif normalized <= 50 then
            return math_floor(175 - (normalized - 25) + 0.5)
        elseif normalized <= 75 then
            return math_floor(150 - (normalized - 50) + 0.5)
        elseif normalized <= 100 then
            return math_floor(125 - (normalized - 75) + 0.5)
        elseif normalized <= 150 then
            return math_floor(100 - (normalized - 100) + 0.5)
        end

        return math_floor(50 - (normalized - 150) * 25 / 50 + 0.5)
    end

    local function _ease_overview_range_transition(progress)
        if progress <= 0 then
            return 0
        elseif progress >= 1 then
            return 1
        end

        return progress * progress * (3 - 2 * progress)
    end

    local function _current_overview_range_transition()
        if not mod._overview_range_transition_active then
            return nil
        end

        local start_t = mod._overview_range_transition_start_t
        local from_range = tonumber(mod._overview_range_transition_from)
        local to_range = tonumber(mod._overview_range_transition_to)

        if not start_t or not from_range or not to_range then
            mod._overview_range_transition_active = false

            return nil
        end

        local now = _safe_gameplay_time() or start_t
        local duration = mod._overview_range_transition_duration or OVERVIEW_RANGE_TRANSITION_DURATION
        local progress = duration > 0 and (now - start_t) / duration or 1

        if progress >= 1 then
            mod._overview_range_transition_active = false
            mod._overview_range_transition_start_t = nil
            mod._overview_range_transition_from = nil
            mod._overview_range_transition_to = nil

            return nil
        end

        local eased = _ease_overview_range_transition(progress)

        return from_range + (to_range - from_range) * eased
    end

    local function _start_overview_range_transition(from_range, to_range)
        local from = tonumber(from_range) or OVERVIEW_DEFAULT_ZOOM_RANGE
        local to = tonumber(to_range) or from

        if math_abs(from - to) < 0.5 then
            mod._overview_range_transition_active = false
            mod._overview_range_transition_start_t = nil
            mod._overview_range_transition_from = nil
            mod._overview_range_transition_to = nil

            return
        end

        mod._overview_range_transition_active = true
        mod._overview_range_transition_start_t = _safe_gameplay_time() or 0
        mod._overview_range_transition_duration = OVERVIEW_RANGE_TRANSITION_DURATION
        mod._overview_range_transition_from = from
        mod._overview_range_transition_to = to
        mod._next_scan_t = 0
    end

    local function _overview_reset_zoom_range()
        local targets = mod._radar_targets or {}
        local max_distance_sq = 0

        for i = 1, #targets do
            local target = targets[i]

            if target and not target.ignore_radar_range then
                local distance_sq = tonumber(target.distance_sq)

                if distance_sq and _is_finite_number(distance_sq) and distance_sq > max_distance_sq then
                    max_distance_sq = distance_sq
                end
            end
        end

        if max_distance_sq <= 0 then
            return OVERVIEW_MIN_ZOOM_RANGE
        end

        local required_range = math_sqrt(max_distance_sq) / OVERVIEW_RESET_FIT_EDGE_FRACTION
        local step = OVERVIEW_MIN_ZOOM_RANGE
        local stepped_range = math_floor((required_range + step - 0.0001) / step) * step

        return _normalize_overview_zoom_range(stepped_range)
    end

    local ROTTEN_ARMOR_BREED_ALIAS_BY_BASE_BREED = {
        chaos_ogryn_executor = "chaos_ogryn_executor_gibbing_rotten_armor",
        renegade_executor = "renegade_executor_gibbing_rotten_armor",
        renegade_berzerker = "renegade_berzerker_gibbing_rotten_armor",
    }

    local function _resolve_enemy_breed_name(unit, breed_name)
        local rotten_armor_breed_name = ROTTEN_ARMOR_BREED_ALIAS_BY_BASE_BREED[breed_name]

        if rotten_armor_breed_name
            and (_safe_unit_has_keyword(unit, "rotten_armor")
                or _safe_unit_has_buff_template(unit, "mutator_rotten_armor")) then
            return rotten_armor_breed_name
        end

        return breed_name
    end

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
        -- `special_target` is shared by multiple abilities. Only apply the fallback color when the
        -- local veteran stance is active so we do not miscolor Adamant Verispex.
        special_target = {
            default_priority = 3,
        },
    }
    local VETERAN_SPECIAL_TARGET_BRACKET_COLOR = { 255, 220, 120, 26 }
    local CACHED_ABILITY_OUTLINE_BRACKET_COLORS = {}
    local OGRYN_TAUNT_SHOUT_ABILITY_NAME = "ogryn_taunt_shout"

    local function _supported_ability_outline_config(outline_name)
        if outline_name == nil then
            return nil
        end

        return SUPPORTED_ABILITY_OUTLINE_CONFIG_BY_NAME[tostring(outline_name)]
    end

    -- `special_target` is shared, so only honor it when the local player is in a
    -- positively identified owning state.
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

    local function _supported_ability_marker_state_for_unit(unit, outline_extension_map, local_player_unit, local_combat_ability_name)
        local marker_names, bracket_color, primary_marker_name, primary_marker_priority = _supported_ability_outline_state_for_unit(unit, outline_extension_map, local_player_unit)

        if marker_names ~= nil then
            return marker_names, bracket_color, primary_marker_name, primary_marker_priority
        end

        -- Ogryn taunt is buff-driven rather than outline-driven, so only honor it for local players
        -- who actually have the taunt combat ability equipped.
        if local_combat_ability_name == OGRYN_TAUNT_SHOUT_ABILITY_NAME
            and _unit_has_supported_ogryn_taunt_marker(unit) then
            return { OGRYN_TAUNT_SHOUT_ABILITY_NAME }, nil, OGRYN_TAUNT_SHOUT_ABILITY_NAME, 0
        end

        return nil, nil, nil, nil
    end

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

    local function _distance_squared_horizontal(a, b)
        if not a or not b then
            return math_huge
        end

        local ax, ay = a.x, a.y
        local bx, by = b.x, b.y

        if not _is_finite_number(ax) or not _is_finite_number(ay) then
            return math_huge
        end

        if not _is_finite_number(bx) or not _is_finite_number(by) then
            return math_huge
        end

        local dx = ax - bx
        local dy = ay - by

        return dx * dx + dy * dy
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

    local PLAYER_CAPTURE_DISABLING_TYPES = {
        grabbed = true,
        consumed = true,
        mutant_charged = true,
        netted = true,
        pounced = true,
    }
    local SLOT_LUGGABLE = "slot_luggable"

    local function _safe_player_component(unit_data_extension, component_name)
        if not unit_data_extension or not unit_data_extension.read_component then
            return nil
        end

        local ok, component = pcall(unit_data_extension.read_component, unit_data_extension, component_name)

        return ok and component or nil
    end

    local function _player_radar_state(unit, has_extension)
        local unit_data_extension = has_extension and has_extension(unit, "unit_data_system") or nil
        local character_state_component = _safe_player_component(unit_data_extension, "character_state")
        local state_name = character_state_component and character_state_component.state_name or nil

        -- Hogtied is the rescue lifecycle after death, so it must replace a
        -- dead icon even while the health extension still reports not alive.
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

        local inventory_component = _safe_player_component(unit_data_extension, "inventory")

        if inventory_component and inventory_component.wielded_slot == SLOT_LUGGABLE then
            local visual_loadout_extension = has_extension and has_extension(unit, "visual_loadout_system") or nil
            local slot_equipped = PlayerUnitVisualLoadout and PlayerUnitVisualLoadout.slot_equipped

            if visual_loadout_extension and slot_equipped then
                local ok, equipped = pcall(slot_equipped, inventory_component, visual_loadout_extension, SLOT_LUGGABLE)

                if ok and equipped then
                    return "luggable"
                end
            end
        end

        return nil
    end

    local function _refresh_player_units()
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

    local function _scan_interactees()
        local interactee_map = _safe_unit_to_extension_map("interactee_system")
        if not interactee_map then
            return
        end

        local player_unit = _player_unit()
        local tracked_units = mod._tracked_units
        local seen_interactees = _scratch_seen_interactees
        table_clear(seen_interactees)

        for unit, extension in pairs(interactee_map) do
            if _safe_unit_alive(unit) and extension then
                seen_interactees[unit] = true

                local is_active = true
                local is_used = false
                local show_marker = true

                local active = extension.active
                if active then
                    local ok_active, value = pcall(active, extension)
                    if not ok_active or value ~= true then
                        is_active = false
                    end
                end

                local used = extension.used
                if used then
                    local ok_used, value = pcall(used, extension)
                    if not ok_used or value == true then
                        is_used = true
                    end
                end

                local show_marker_fn = extension.show_marker
                if show_marker_fn then
                    if player_unit then
                        local ok_show, value = pcall(show_marker_fn, extension, player_unit)
                        if not ok_show or value ~= true then
                            show_marker = false
                        end
                    else
                        show_marker = false
                    end
                end

                if is_active and not is_used and show_marker then
                    local kind, meta = _classify_interactee(extension, unit)

                    if kind
                        and not _should_hide_expedition_store_product_in_open_zone(unit)
                        and (kind ~= "expedition_loot_converter" or _is_in_expedition_safe_zone()) then
                        _track_unit(unit, kind, "interactee_system", meta)
                    else
                        _clear_tracked_unit_from_source(unit, "interactee_system")
                    end
                else
                    _clear_tracked_unit_from_source(unit, "interactee_system")
                end
            else
                _clear_tracked_unit_from_source(unit, "interactee_system")
            end
        end

        for unit, data in pairs(tracked_units) do
            if data and data.source == "interactee_system" and not seen_interactees[unit] then
                tracked_units[unit] = nil
            end
        end
    end

    local function _scan_chests()
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

    local function _scan_hazard_props()
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

    local function _scan_minions()
        local unit_data_map = _safe_unit_to_extension_map("unit_data_system")
        if not unit_data_map then
            return
        end

        local track_enemy_tags = mod:get_show_only_tagged_enemies()
        local show_ability_marked_enemies = mod:get_show_ability_marked_enemies()
        local outline_extension_map = show_ability_marked_enemies and _safe_outline_extension_data_map() or nil
        local local_player_unit = show_ability_marked_enemies and _player_unit() or nil
        local local_combat_ability_name = show_ability_marked_enemies
            and _safe_unit_ability_name(local_player_unit, "combat_ability")
            or nil
        local kind_enabled_cache = _scratch_minion_kind_enabled_cache
        table_clear(kind_enabled_cache)

        for unit, extension in pairs(unit_data_map) do
            if _safe_unit_alive(unit) and extension then
                local breed_name_fn = extension.breed_name

                if breed_name_fn then
                    local ok_breed, breed_name = pcall(breed_name_fn, extension)

                    if ok_breed and breed_name then
                        local resolved_breed_name = _resolve_enemy_breed_name(unit, breed_name)
                        local kind = _classify_enemy_from_breed(resolved_breed_name)
                        if kind and _is_trackable_unit_alive(unit, kind) then
                            local kind_enabled = kind_enabled_cache[kind]

                            if kind_enabled == nil then
                                kind_enabled = _kind_enabled(kind)
                                kind_enabled_cache[kind] = kind_enabled
                            end

                            -- Disabled enemy kinds skip tracking work entirely unless an
                            -- ability mark can still surface the unit on the radar.
                            local ability_marker_names = nil
                            local ability_marker_bracket_color = nil

                            if show_ability_marked_enemies then
                                ability_marker_names,
                                ability_marker_bracket_color = _supported_ability_marker_state_for_unit(
                                        unit,
                                        outline_extension_map,
                                        local_player_unit,
                                        local_combat_ability_name
                                    )
                            end

                            if kind_enabled or ability_marker_names ~= nil then
                                _track_unit(unit, kind, "unit_data_system", {
                                    breed_name = breed_name,
                                    marked_by_player_slot = track_enemy_tags and _marked_by_player_slot_for_unit(unit) or nil,
                                    ability_marked = ability_marker_names ~= nil,
                                    ability_outline_bracket_color = ability_marker_bracket_color,
                                })
                            else
                                _clear_tracked_unit_from_source(unit, "unit_data_system")
                            end
                        end
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
        local tracked_units = mod._tracked_units

        for unit, data in pairs(tracked_units) do
            if not _is_trackable_unit_alive(unit, data and data.kind) then
                tracked_units[unit] = nil
            else
                local last_seen_t = data.last_seen_t

                if last_seen_t and now - last_seen_t > 2.5 then
                    tracked_units[unit] = nil
                else
                    local meta = data and data.meta
                    local position = meta and _copy_vector3(meta.position) or nil

                    position = position or _safe_unit_position(unit) or data.position

                    if position then
                        data.position = position
                    else
                        tracked_units[unit] = nil
                    end
                end
            end
        end
    end

    local function _vertical_delta(a, b)
        if not a or not b then
            return nil
        end

        local az = a.z
        local bz = b.z

        if not _is_finite_number(az) or not _is_finite_number(bz) then
            return nil
        end

        return bz - az
    end

    local ITEM_VERTICAL_ARROW_Z_DEADZONE = 2

    local function _is_player_smart_tag_kind(kind)
        return kind == "location_attention"
            or kind == "location_ping"
            or kind == "location_threat"
    end

    local function _is_item_kind(kind)
        if not kind then
            return false
        end

        if kind == "player_teammate"
            or kind == "player_companion_dog"
            or kind == "player_companion_servo_skull" then
            return false
        end

        if _is_player_smart_tag_kind(kind) then
            return false
        end

        if _is_enemy_kind(kind) then
            return false
        end

        if _is_expedition_marker_kind(kind) then
            return false
        end

        return true
    end

    local function _target_has_explicit_tag(source, meta)
        if source == "smart_tag_system" then
            return true
        end

        return meta ~= nil and meta.marked_by_player_slot ~= nil
    end

    local function _target_has_ability_outline_mark(meta)
        return meta ~= nil and meta.ability_marked == true
    end

    local function _passes_tag_visibility_filter(kind, source, meta, only_tagged_enemies, only_tagged_items)
        if only_tagged_enemies and _is_enemy_kind(kind) then
            return _target_has_explicit_tag(source, meta) or _target_has_ability_outline_mark(meta)
        end

        if only_tagged_items and _is_item_kind(kind) then
            return _target_has_explicit_tag(source, meta)
        end

        return true
    end

    local function _supports_vertical_marker(kind)
        if _is_item_kind(kind) then
            return true
        end

        if not _is_enemy_kind(kind) then
            return false
        end

        local show_enemy_vertical_arrows = mod.show_enemy_vertical_arrows

        return show_enemy_vertical_arrows ~= nil and show_enemy_vertical_arrows(mod, kind) == true
    end

    local function _expedition_loot_target_value(target)
        local meta = target and target.meta or nil
        local value = meta and tonumber(meta.remnant_value or meta.remnant_cluster_value) or nil

        if value and value > 0 then
            return value
        end

        local pickup_name = meta and meta.pickup_name or nil

        return _expedition_loot_value_for_pickup_name(pickup_name) or 0
    end

    local function _should_cluster_expedition_loot_target(target)
        return target ~= nil and target.kind == "material_expeditions_loot" and target.position ~= nil
    end

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

    local function _cluster_expedition_loot_targets(targets, player_pos, item_vertical_arrow_threshold_sq,
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

    local function _compare_radar_targets_for_display(a, b)
        local a_priority = a and a.selection_priority or 0
        local b_priority = b and b.selection_priority or 0

        if a_priority ~= b_priority then
            return a_priority > b_priority
        end

        local a_distance = a and a.distance_sq or math_huge
        local b_distance = b and b.distance_sq or math_huge

        if a_distance ~= b_distance then
            return a_distance < b_distance
        end

        return tostring(a.kind) < tostring(b.kind)
    end

    local function _collect_radar_targets()
        local player_unit = _player_unit()
        if not _safe_unit_alive(player_unit) then
            return _reuse_or_new_table(mod._radar_targets)
        end

        local player_pos = _safe_unit_position(player_unit)
        if not player_pos then
            return _reuse_or_new_table(mod._radar_targets)
        end

        local max_range = mod:get_radar_collection_range()
        local max_range_sq = max_range * max_range
        local max_markers = mod:get_max_radar_markers()
        local item_vertical_arrow_threshold = mod:get_item_vertical_arrow_threshold()
        local item_vertical_hide_threshold = mod:get_item_vertical_hide_threshold()
        local item_vertical_arrow_threshold_sq = item_vertical_arrow_threshold * item_vertical_arrow_threshold
        local only_tagged_enemies = mod:get_show_only_tagged_enemies()
        local only_tagged_items = mod:get_show_only_tagged_items()
        local show_ability_marked_enemies = mod:get_show_ability_marked_enemies()
        local tracked_units = mod._tracked_units
        local tracked_points = mod._tracked_points
        local targets = _reuse_or_new_table(mod._radar_targets)
        local target_pool = _warm_radar_target_pool(max_markers)
        local target_count = 0

        _clear_scratch_radar_caches()

        local kind_enabled_cache = _scratch_kind_enabled_cache
        local ignore_range_cache = _scratch_ignore_range_cache
        local infinite_range_cache = _scratch_infinite_range_cache
        local supports_vertical_cache = _scratch_supports_vertical_cache
        local render_layer_cache = _scratch_render_layer_cache
        local selection_priority_cache = _scratch_selection_priority_cache
        local priority_target_cache = _scratch_priority_target_cache
        local get_target_render_layer = mod.get_target_render_layer
        local get_target_selection_priority = mod.get_target_selection_priority
        local is_event_marker_kind = mod.is_event_marker_kind

        local function _cached_kind_enabled(kind)
            local enabled = kind_enabled_cache[kind]

            if enabled == nil then
                enabled = _kind_enabled(kind)
                kind_enabled_cache[kind] = enabled
            end

            return enabled
        end

        local function _cached_ignore_radar_range(kind)
            local ignore_range = ignore_range_cache[kind]

            if ignore_range == nil then
                ignore_range = _ignore_radar_range_for_kind(kind)
                ignore_range_cache[kind] = ignore_range
            end

            return ignore_range
        end

        local function _cached_infinite_radar_range(kind)
            local infinite_range = infinite_range_cache[kind]

            if infinite_range == nil then
                infinite_range = _has_infinite_radar_range_for_kind(kind)
                infinite_range_cache[kind] = infinite_range
            end

            return infinite_range
        end

        local function _cached_supports_vertical_marker(kind)
            local supports_vertical = supports_vertical_cache[kind]

            if supports_vertical == nil then
                supports_vertical = _supports_vertical_marker(kind)
                supports_vertical_cache[kind] = supports_vertical
            end

            return supports_vertical
        end

        local function _cached_priority_target(kind)
            local is_priority_target = priority_target_cache[kind]

            if is_priority_target == nil then
                is_priority_target = kind == "enemy_daemonhost" or _is_boss_marker_kind(kind) or
                    ENEMY_RADAR_DEFINITION_BY_KIND[kind] ~= nil or
                    (is_event_marker_kind and is_event_marker_kind(mod, kind) == true) or
                    kind == "player_teammate" or
                    kind == "material_expeditions_loot_player_drop" or
                    kind == "location_attention" or
                    kind == "location_ping" or
                    kind == "location_threat"
                priority_target_cache[kind] = is_priority_target
            end

            return is_priority_target
        end

        local function _cached_render_layer(kind)
            local render_layer = render_layer_cache[kind]

            if render_layer == nil then
                render_layer = get_target_render_layer(mod, kind)
                render_layer_cache[kind] = render_layer
            end

            return render_layer
        end

        local function _cached_selection_priority(kind)
            local selection_priority = selection_priority_cache[kind]

            if selection_priority == nil then
                selection_priority = get_target_selection_priority(mod, kind)
                selection_priority_cache[kind] = selection_priority
            end

            return selection_priority
        end

        local function append_target(unit, data)
            local position = data and data.position
            local kind = data and data.kind
            local source = data and data.source
            local meta = data and data.meta
            local explicitly_tagged_target = _target_has_explicit_tag(source, meta)
            local ability_marked_enemy = show_ability_marked_enemies
                and _is_enemy_kind(kind)
                and _target_has_ability_outline_mark(meta)
            local companion_action = meta and meta.companion_action or nil
            local companion_action_target = meta and meta.companion_action_target or nil
            local companion_target_position = companion_action_target and
                _safe_unit_position(companion_action_target) or nil
            local companion_overlapping_target = kind == "player_companion_dog"
                and companion_target_position ~= nil
                and _distance_squared_horizontal(position, companion_target_position) <=
                COMPANION_TARGET_OVERLAP_DISTANCE_SQ
            local companion_action_active = companion_action == "hacking"
                or companion_action == "inject_ally"
                or companion_action == "flamethrower"
                or companion_overlapping_target

            if not position or not kind or (not _cached_kind_enabled(kind) and not ability_marked_enemy) then
                return
            end

            if kind == "player_companion_servo_skull"
                and meta
                and meta.owner_marker_visible
                and meta.servo_skull_following_owner then
                local owner_position = _safe_unit_position(meta.owner_unit)

                if owner_position
                    and _distance_squared_horizontal(owner_position, position) <=
                    SERVO_SKULL_OWNER_HIDE_DISTANCE_SQ then
                    return
                end
            end

            if not _passes_tag_visibility_filter(kind, source, meta, only_tagged_enemies, only_tagged_items) then
                return
            end

            if kind == "pickup_heretic_idol" and source == "destructible_system" then
                if not meta or meta.collectible_id == nil then
                    return
                end
            end

            local distance_sq_horizontal = _distance_squared_horizontal(player_pos, position)
            local infinite_range = _cached_infinite_radar_range(kind)
            local ignore_range = infinite_range or _cached_ignore_radar_range(kind)

            if explicitly_tagged_target or ability_marked_enemy then
                ignore_range = true
            end

            if only_tagged_enemies and _is_enemy_kind(kind) and explicitly_tagged_target then
                ignore_range = true
            end

            if only_tagged_items and _is_item_kind(kind) and explicitly_tagged_target then
                ignore_range = true
            end

            if distance_sq_horizontal > max_range_sq and not ignore_range then
                return
            end

            local vertical_delta = nil
            local vertical_state = nil

            if _cached_supports_vertical_marker(kind) then
                vertical_delta = _vertical_delta(player_pos, position)

                if vertical_delta ~= nil then
                    local abs_vertical_delta = math_abs(vertical_delta)

                    if not infinite_range
                        and kind ~= "pickup_heretic_idol"
                        and abs_vertical_delta >= item_vertical_hide_threshold then
                        return
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
            end

            local render_layer = 0
            local selection_priority = 0

            if companion_action_active then
                render_layer = COMPANION_ACTION_RENDER_LAYER
            elseif _cached_priority_target(kind) then
                render_layer = _cached_render_layer(kind)
                selection_priority = _cached_selection_priority(kind)
            end

            target_count = target_count + 1
            local target = target_pool[target_count] or {}
            target_pool[target_count] = target

            target.unit = unit
            target.kind = kind
            target.position = position
            target.source = source
            target.meta = meta
            target.distance_sq = distance_sq_horizontal
            target.distance_sq_3d = _distance_squared(player_pos, position)
            target.vertical_delta = vertical_delta
            target.vertical_state = vertical_state
            target.ignore_radar_range = ignore_range
            target.render_layer = render_layer
            target.selection_priority = selection_priority
            target.disabled_by_mastiff = _scratch_mastiff_disabled_enemy_units[unit] == true
                and _is_enemy_kind(kind)

            targets[target_count] = target
        end

        for unit, data in pairs(tracked_units) do
            if _is_trackable_unit_alive(unit, data and data.kind) then
                append_target(unit, data)
            end
        end

        for id, data in pairs(tracked_points) do
            append_target(id, data)
        end

        mod._unclustered_radar_targets = targets

        if mod:has_any_nearby_highlight_enabled() then
            mod._highlight_source_radar_targets = _copy_target_list(targets, mod._highlight_source_radar_targets)
        else
            mod._highlight_source_radar_targets = _reuse_or_new_table(mod._highlight_source_radar_targets)
        end

        local unclustered_total = #targets

        targets = _cluster_expedition_loot_targets(targets, player_pos, item_vertical_arrow_threshold_sq,
            item_vertical_hide_threshold)

        table_sort(targets, _compare_radar_targets_for_display)

        local target_total = #targets
        local was_capped = target_total > max_markers

        if was_capped then
            for i = target_total, max_markers + 1, -1 do
                targets[i] = nil
            end
        end

        mod._last_radar_unclustered_marker_count = unclustered_total
        mod._last_radar_candidate_marker_count = target_total
        mod._last_radar_active_marker_count = #targets
        mod._last_radar_marker_cap = max_markers
        mod._last_radar_marker_capped = was_capped

        return targets
    end

    local function _write_radar_snapshot(player_unit, player_pos)
        local local_player = _local_player()
        local snapshot = mod._radar_snapshot or {}

        snapshot.player_unit = player_unit
        snapshot.player_position = player_pos
        snapshot.player_rotation = _safe_player_rotation(player_unit)
        snapshot.player_slot = _safe_player_slot(local_player)
        snapshot.targets = mod._radar_targets
        snapshot.screen_highlights = mod._screen_highlight_targets

        return snapshot
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

        return _write_radar_snapshot(player_unit, player_pos)
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
                elseif string_find(kind, "ammo", 1, true) then
                    counts.ammo = counts.ammo + 1
                else
                    counts.generic = counts.generic + 1
                end
            end
        end

        local signature = table_concat({
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
            tostring(_safe_player_character_state_name(_player_unit())),
        }, "|")

        if signature == mod._last_scan_signature then
            return
        end

        mod._last_scan_signature = signature

        mod:info(string_format(
            "Radar scan | enemies=%d players=%d ammo=%d crates=%d pocketables=%d materials=%d generic=%d tracked=%d radar_targets=%d scan_ms=%.2f mission=%s activity=%s mechanism=%s player_state=%s",
            counts.enemies,
            counts.players,
            counts.ammo,
            counts.crates,
            counts.pocketables,
            counts.materials,
            counts.generic,
            _table_size(mod._tracked_units),
            #mod._radar_targets,
            tonumber(mod._last_scan_cost_ms) or -1,
            tostring(_safe_mission_name()),
            tostring(_safe_presence_activity()),
            tostring(_safe_mechanism_name()),
            tostring(_safe_player_character_state_name(_player_unit()))
        ))
    end

    local function _reset_runtime_state()
        mod._screen_highlight_targets = {}
        mod._unclustered_radar_targets = {}
        mod._highlight_source_radar_targets = {}
        mod._next_scan_t = 0
        mod._next_static_scan_t = 0
        mod._last_scan_cost_ms = nil
        _invalidate_runtime_state_cache()
        mod._tracked_units = {}
        mod._tracked_points = {}
        mod._logged_units = {}
        mod._radar_targets = {}
        mod._radar_snapshot = nil
        mod._radar_target_pool = {}
        mod._radar_player_unit_by_player = {}
        mod._last_update_t = nil
        mod._last_scan_signature = nil
        mod._last_block_signature = nil
        mod._last_state_gameplay = nil
        _reset_dark_rites_marker_scan_cache()
        mod._idol_destroyed_collectible_keys = {}
        mod._idol_destroyed_units = {}
        mod._last_safe_zone_section_index = nil
        mod._last_expedition_in_safe_zone = nil
        mod._player_smart_tag_generation = 0
        mod._player_smart_tag_state_by_id = {}
        mod._overview_mode_active = false
        mod._overview_zoom_range = _normalize_overview_zoom_range(mod:get("overview_zoom_range"))
        mod._overview_capture_actions = mod._overview_capture_actions or {}
        mod._overview_range_transition_active = false
        mod._overview_range_transition_start_t = nil
        mod._overview_range_transition_from = nil
        mod._overview_range_transition_to = nil
        mod._normal_radar_zoom_modifier_t = nil
        mod._normal_radar_zoom_indicator_t = nil
        mod._last_radar_unclustered_marker_count = 0
        mod._last_radar_candidate_marker_count = 0
        mod._last_radar_active_marker_count = 0
        mod._last_radar_marker_cap = 0
        mod._last_radar_marker_capped = false
        mod._overview_marker_high_raw = 0
        mod._overview_marker_high_candidates = 0
        mod._overview_marker_high_active = 0
        mod._overview_marker_high_drawn = 0
        mod._last_overview_marker_debug_signature = nil

        _refresh_overview_input_capture()
    end

    local function _debug_log_block(reason, gameplay_t, mission_name, activity, mechanism_name)
        if mod:get("debug_mode") ~= true then
            return
        end

        local player_unit = _player_unit()
        local player_state = _safe_player_character_state_name(player_unit)

        local signature = string_format(
            "%s|%s|%s|%s|%s",
            tostring(reason),
            tostring(mission_name),
            tostring(activity),
            tostring(mechanism_name),
            tostring(player_state)
        )

        if signature == mod._last_block_signature then
            return
        end

        mod._last_block_signature = signature
        mod:info(string_format(
            "Radar blocked | reason=%s mission=%s activity=%s mechanism=%s gameplay_t=%s player_state=%s",
            tostring(reason),
            tostring(mission_name),
            tostring(activity),
            tostring(mechanism_name),
            tostring(gameplay_t),
            tostring(player_state)
        ))
    end

    local function _is_ui_input_active()
        local managers = Managers
        local ui_manager = managers and managers.ui
        local using_input = ui_manager and ui_manager.using_input

        return using_input and using_input(ui_manager, true) == true
    end

    local function _is_radar_keybind_runtime_allowed()
        return not _is_ui_input_active()
            and mod.is_radar_runtime_game_mode_allowed
            and mod:is_radar_runtime_game_mode_allowed()
    end

    local function _update_internal(t)
        if mod:get("enable_radar") == false and not mod:is_overview_mode_active() then
            _reset_runtime_output_tables()
            return
        end

        local allowed, reason, gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos = _get_runtime_state()
        local scan_clock = gameplay_t or t or 0

        if mod._last_update_t and scan_clock and scan_clock == mod._last_update_t then
            return
        end
        mod._last_update_t = scan_clock

        if not allowed then
            if reason == "player_not_alive"
                or reason == "player_captured"
                or reason == "no_player_unit"
                or reason == "spectating_teammate" then
                _reset_tracked_units_table()
            end

            if mod:is_overview_mode_active() then
                mod:set_overview_mode_active(false)
            end

            _reset_runtime_output_tables()
            _debug_log_block(reason, gameplay_t, mission_name, activity, mechanism_name)
            return
        end

        mod._last_block_signature = nil
        mod._radar_snapshot = _write_radar_snapshot(player_unit, player_pos)

        if scan_clock < (mod._next_scan_t or 0) then
            return
        end

        _current_overview_range_transition()

        local scan_interval = mod._overview_range_transition_active
            and OVERVIEW_RANGE_TRANSITION_SCAN_INTERVAL
            or SCAN_INTERVAL

        mod._next_scan_t = scan_clock + scan_interval

        local static_scan_due = scan_clock >= (mod._next_static_scan_t or 0)

        if static_scan_due then
            mod._next_static_scan_t = scan_clock + STATIC_SCAN_INTERVAL
        end

        local scan_start_time = mod:get("debug_mode") == true and os_clock and os_clock() or nil

        _sync_expedition_item_state()

        if static_scan_due then
            _scan_interactees()
            _scan_chests()
        end

        _scan_minions()

        if static_scan_due then
            _scan_destructibles()
            _scan_hazard_props()
            _scan_smart_tag_targets()
        end

        _refresh_player_units()
        _scan_expedition_objectives()
        _scan_player_tag_points()
        _prune_units()

        mod._radar_targets = _collect_radar_targets()
        mod._screen_highlight_targets = _collect_screen_highlight_targets()
        mod._radar_snapshot = _collect_radar_snapshot()

        if scan_start_time then
            mod._last_scan_cost_ms = (os_clock() - scan_start_time) * 1000
        end

        _debug_log_scan()
    end

    mod.on_game_state_changed = function(status, state_name)
        if status == "enter" and state_name == "GameplayStateRun" then
            mod._gameplay_run = true
            _warm_radar_target_pool(512)
            mod._next_scan_t = 0
            mod._next_static_scan_t = 0
            mod._last_update_t = nil
            _invalidate_runtime_state_cache()
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
        filename = "Radar/scripts/mods/Radar/ui/Radar_hud_element",
        visibility_groups = {
            "communication_wheel",
            "emote_wheel",
            "alive",
        },
        use_hud_scale = true,
    })

    local function _neutralize_input_value(value)
        local value_type = type(value)

        if value_type == "boolean" then
            return false
        end

        if value_type == "number" then
            return 0
        end

        if value_type == "userdata" and Vector3 then
            return Vector3(0, 0, 0)
        end

        return value
    end

    local function _overview_input_action_hook(func, self, action_name, ...)
        local value = func(self, action_name, ...)

        if not mod:should_capture_overview_input_action(action_name) then
            return value
        end

        return _neutralize_input_value(value)
    end

    mod:hook(CLASS.InputService, "_get", _overview_input_action_hook)
    mod:hook(CLASS.InputService, "_get_simulate", _overview_input_action_hook)

    mod:hook_safe("StateGameplay", "update", function(self, dt, t, ...)
        mod._last_state_gameplay = self
        _update_internal(t)
    end)

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

    mod.update = function()
        if not mod._gameplay_run then
            return
        end

        _update_internal(_safe_gameplay_time())
    end

    local previous_on_setting_changed = mod.on_setting_changed

    mod.on_setting_changed = function(setting_id, ...)
        if previous_on_setting_changed then
            previous_on_setting_changed(setting_id, ...)
        end

        if setting_id == "overview_zoom_in_key" or setting_id == "overview_zoom_out_key" then
            _refresh_overview_input_capture()
        elseif setting_id == "show_player_state_icons" then
            mod._next_scan_t = 0
        end
    end

    function mod:is_overview_mode_active()
        return self._overview_mode_active == true
    end

    function mod:get_overview_zoom_range()
        local value = self._overview_zoom_range

        if value == nil then
            value = _normalize_overview_zoom_range(self:get("overview_zoom_range"))
            self._overview_zoom_range = value
        end

        return _normalize_overview_zoom_range(value)
    end

    function mod:set_overview_zoom_range(value, persist)
        local normalized = _normalize_overview_zoom_range(value)
        local previous_range = self:get_overview_zoom_range()
        local transition_range = _current_overview_range_transition()

        self._overview_zoom_range = normalized

        if persist ~= false then
            self:set("overview_zoom_range", normalized)
        end

        if self:is_overview_mode_active() then
            _start_overview_range_transition(transition_range or previous_range, normalized)
        end

        return normalized
    end

    function mod:is_normal_radar_zoom_modifier_active()
        if self:is_overview_mode_active() then
            return false
        end

        if not _is_radar_keybind_runtime_allowed() then
            return false
        end

        if _radar_zoom_modifier_binding_held() then
            return true
        end

        local last_t = self._normal_radar_zoom_modifier_t

        if not last_t then
            return false
        end

        local now = _safe_gameplay_time() or 0

        return now - last_t <= NORMAL_RADAR_ZOOM_MODIFIER_GRACE
    end

    function mod:set_normal_radar_zoom_range(value)
        local normalized = _normalize_normal_radar_zoom_range(value)

        self:set("radar_range", normalized)
        self._normal_radar_zoom_indicator_t = _safe_gameplay_time() or 0
        self._next_scan_t = 0

        return normalized
    end

    function mod:reset_radar_zoom()
        if not _is_radar_keybind_runtime_allowed() then
            return false
        end

        if self:is_overview_mode_active() then
            return self:set_overview_zoom_range(_overview_reset_zoom_range())
        end

        if not self:is_normal_radar_zoom_modifier_active() then
            return false
        end

        return self:set_normal_radar_zoom_range(NORMAL_RADAR_RESET_ZOOM_RANGE)
    end

    function mod:set_overview_mode_active(active)
        local is_active = active == true

        if is_active and not _is_radar_keybind_runtime_allowed() then
            return false
        end

        if self._overview_mode_active == is_active then
            return is_active
        end

        local transition_range = _current_overview_range_transition()
        local current_range = transition_range
            or (self._overview_mode_active and self:get_overview_zoom_range() or self:get_configured_radar_range())
        local target_range = is_active and self:get_overview_zoom_range() or self:get_configured_radar_range()

        self._overview_mode_active = is_active
        self._overview_zoom_range = self:get_overview_zoom_range()

        if is_active then
            self._overview_marker_high_raw = 0
            self._overview_marker_high_candidates = 0
            self._overview_marker_high_active = 0
            self._overview_marker_high_drawn = 0
            self._last_overview_marker_debug_signature = nil
            _start_overview_range_transition(current_range, target_range)
        else
            self._overview_range_transition_active = false
            self._overview_range_transition_start_t = nil
            self._overview_range_transition_from = nil
            self._overview_range_transition_to = nil
            self._next_scan_t = 0
        end

        _refresh_overview_input_capture()

        if self:get("debug_mode") == true then
            self:notify(
                "Radar overview %s (%dm)",
                is_active and "enabled" or "disabled",
                self:get_overview_zoom_range()
            )
        end

        return is_active
    end

    function mod:adjust_overview_zoom(direction)
        if not self:is_overview_mode_active() then
            return false
        end

        if not _is_radar_keybind_runtime_allowed() then
            return false
        end

        local current_range = self:get_overview_zoom_range()
        local new_range = current_range

        if direction == "in" then
            new_range = current_range - OVERVIEW_MIN_ZOOM_RANGE
        elseif direction == "out" then
            new_range = current_range + OVERVIEW_MIN_ZOOM_RANGE
        end

        return self:set_overview_zoom_range(new_range)
    end

    function mod:adjust_normal_radar_zoom(direction)
        if not _is_radar_keybind_runtime_allowed() then
            return false
        end

        if not self:is_normal_radar_zoom_modifier_active() then
            return false
        end

        local current_range = self:get_configured_radar_range()
        local new_range = _next_normal_radar_zoom_range(current_range, direction)

        return self:set_normal_radar_zoom_range(new_range)
    end

    function mod:adjust_radar_zoom(direction)
        if self:is_overview_mode_active() then
            return self:adjust_overview_zoom(direction)
        end

        return self:adjust_normal_radar_zoom(direction)
    end

    function mod:should_capture_overview_input_action(action_name)
        if action_name == nil then
            return false
        end

        -- This runs inside the InputService hooks for every action lookup, so
        -- check the cheap captured-action table before touching runtime state.
        local capture_actions = self._overview_capture_actions

        if capture_actions == nil then
            _refresh_overview_input_capture()
            capture_actions = self._overview_capture_actions
        end

        if capture_actions[tostring(action_name)] ~= true then
            return false
        end

        if not (self:is_overview_mode_active() or self:is_normal_radar_zoom_modifier_active()) then
            return false
        end

        return _is_radar_keybind_runtime_allowed()
    end

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

    function mod:get_radar_snapshot()
        return self._radar_snapshot
    end

    function mod:get_show_only_tagged_enemies()
        return self:get("show_only_tagged_enemies") == true
    end

    function mod:get_show_ability_marked_enemies()
        return self:get("show_ability_marked_enemies") == true
    end

    function mod:get_show_only_tagged_items()
        return self:get("show_only_tagged_items") == true
    end

    function mod:should_draw_radar()
        if self:get("enable_radar") == false and not self:is_overview_mode_active() then
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

    function mod:get_configured_radar_size()
        local value = tonumber(self:get("radar_size")) or 220

        if value < 100 then
            value = 100
        elseif value > 1200 then
            value = 1200
        end

        return math_floor(value + 0.5)
    end

    function mod:get_radar_size()
        if self:is_overview_mode_active() then
            return _overview_max_radar_size()
        end

        return self:get_configured_radar_size()
    end

    function mod:get_configured_radar_range()
        return _normalize_normal_radar_zoom_range(self:get("radar_range") or 40)
    end

    function mod:get_radar_range()
        if self:is_overview_mode_active() then
            return _current_overview_range_transition() or self:get_overview_zoom_range()
        end

        return self:get_configured_radar_range()
    end

    function mod:get_radar_collection_range()
        if self:is_overview_mode_active() then
            local transition_range = _current_overview_range_transition()

            if transition_range then
                return transition_range
            end

            return math_huge
        end

        _current_overview_range_transition()

        return self:get_radar_range()
    end

    function mod:get_normal_radar_zoom_factor_text(range)
        local hundredths = _normal_radar_zoom_factor_hundredths(range)
        local factor = hundredths / 100

        if hundredths % 10 == 0 then
            return string_format("%.1fx", factor)
        end

        return string_format("%.2fx", factor)
    end

    function mod:get_normal_radar_zoom_indicator()
        if self:is_overview_mode_active() then
            return nil, nil
        end

        local start_t = self._normal_radar_zoom_indicator_t

        if not start_t then
            return nil, nil
        end

        local now = _safe_gameplay_time() or start_t
        local elapsed = now - start_t

        if elapsed < 0 or elapsed > NORMAL_RADAR_ZOOM_INDICATOR_DURATION then
            self._normal_radar_zoom_indicator_t = nil

            return nil, nil
        end

        local fade_start = NORMAL_RADAR_ZOOM_INDICATOR_DURATION * 0.7
        local alpha_scale = 1

        if elapsed > fade_start then
            alpha_scale = (NORMAL_RADAR_ZOOM_INDICATOR_DURATION - elapsed)
                / (NORMAL_RADAR_ZOOM_INDICATOR_DURATION - fade_start)
        end

        return self:get_normal_radar_zoom_factor_text(self:get_configured_radar_range()), alpha_scale
    end

    function mod:log_overview_marker_draw_counts(collected_count, drawn_count, configured_cap, widget_cap, center_dot_drawn)
        if self:get("debug_mode") ~= true or not self:is_overview_mode_active() then
            return
        end

        local raw_count = tonumber(self._last_radar_unclustered_marker_count) or tonumber(collected_count) or 0
        local candidate_count = tonumber(self._last_radar_candidate_marker_count) or tonumber(collected_count) or 0
        local active_count = tonumber(self._last_radar_active_marker_count) or tonumber(collected_count) or 0
        local draw_count = tonumber(drawn_count) or 0
        local marker_cap = tonumber(configured_cap) or self:get_max_radar_markers()
        local pool_cap = tonumber(widget_cap) or marker_cap
        local capped = self._last_radar_marker_capped == true
        local center_dot = center_dot_drawn == true
        local widget_count = draw_count + (center_dot and 1 or 0)
        local limit_ok = active_count <= marker_cap and widget_count <= pool_cap

        self._overview_marker_high_raw = math_max(tonumber(self._overview_marker_high_raw) or 0, raw_count)
        self._overview_marker_high_candidates = math_max(tonumber(self._overview_marker_high_candidates) or 0,
            candidate_count)
        self._overview_marker_high_active = math_max(tonumber(self._overview_marker_high_active) or 0, active_count)
        self._overview_marker_high_drawn = math_max(tonumber(self._overview_marker_high_drawn) or 0, draw_count)

        local signature = table_concat({
            tostring(raw_count),
            tostring(candidate_count),
            tostring(active_count),
            tostring(draw_count),
            tostring(marker_cap),
            tostring(pool_cap),
            tostring(capped),
            tostring(center_dot),
            tostring(widget_count),
            tostring(limit_ok),
            tostring(self._overview_marker_high_raw),
            tostring(self._overview_marker_high_candidates),
            tostring(self._overview_marker_high_active),
            tostring(self._overview_marker_high_drawn),
        }, "|")

        if signature == self._last_overview_marker_debug_signature then
            return
        end

        self._last_overview_marker_debug_signature = signature
        self:info(string_format(
            "Radar overview markers | raw=%d candidates=%d active=%d drawn=%d widgets=%d cap=%d widget_cap=%d capped=%s center_dot=%s limit_ok=%s high_raw=%d high_candidates=%d high_active=%d high_drawn=%d",
            raw_count,
            candidate_count,
            active_count,
            draw_count,
            widget_count,
            marker_cap,
            pool_cap,
            tostring(capped),
            tostring(center_dot),
            tostring(limit_ok),
            self._overview_marker_high_raw,
            self._overview_marker_high_candidates,
            self._overview_marker_high_active,
            self._overview_marker_high_drawn
        ))
    end

    function mod:get_max_radar_markers()
        if self:is_overview_mode_active() then
            return self:get_overview_max_radar_markers()
        end

        local value = tonumber(self:get("max_radar_markers")) or 64

        if value < 10 then
            value = 10
        elseif value > 200 then
            value = 200
        end

        return math_floor(value)
    end

    function mod:get_overview_max_radar_markers()
        local value = tonumber(self:get("overview_max_radar_markers")) or OVERVIEW_RADAR_MARKER_LIMIT

        if value < 100 then
            value = 100
        elseif value > OVERVIEW_RADAR_MARKER_LIMIT then
            value = OVERVIEW_RADAR_MARKER_LIMIT
        end

        return math_floor(value)
    end

    function mod:get_boss_marker_range_mode()
        local value = tostring(self:get("boss_marker_range_mode") or "normal")

        if value ~= "infinite" then
            value = "normal"
        end

        return value
    end

    function mod:get_expedition_loot_marker_mode()
        local value = tostring(self:get("expedition_loot_marker_mode") or "default")

        if value ~= "scaled" and value ~= "clustered" then
            value = "default"
        end

        return value
    end

    function mod:get_show_expedition_loot_cluster_value()
        return self:get("show_expedition_loot_cluster_value") == true
    end

    function mod:get_show_expedition_loot_value_text()
        return self:get_show_expedition_loot_cluster_value()
    end

    function mod:get_expedition_loot_cluster_horizontal_radius()
        local value = tonumber(self:get("expedition_loot_cluster_horizontal_radius")) or 5

        if value < 1 then
            value = 1
        elseif value > 10 then
            value = 10
        end

        return value
    end

    function mod:get_expedition_loot_cluster_vertical_radius()
        local value = tonumber(self:get("expedition_loot_cluster_vertical_radius")) or 3

        if value < 1 then
            value = 1
        elseif value > 5 then
            value = 5
        end

        return value
    end

    function mod:get_item_vertical_arrow_threshold()
        local value = tonumber(self:get("item_vertical_arrow_threshold")) or 25

        if value < 25 then
            value = 25
        elseif value > 100 then
            value = 100
        end

        return value
    end

    function mod:get_item_vertical_hide_threshold()
        local value = tonumber(self:get("item_vertical_hide_threshold")) or 12

        if value < 8 then
            value = 8
        elseif value > 50 then
            value = 50
        end

        return value
    end

    function mod:get_radar_style()
        local value = tostring(self:get("radar_style") or "square")

        if value ~= "circle" and value ~= "auspex" then
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

        if value ~= "crosshair" and value ~= "view_guides" and value ~= "range_rings"
            and value ~= "auspex_background" and value ~= "off" then
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

        return math_floor(value)
    end

    function mod:get_radar_anchor()
        return _normalize_radar_anchor(self:get("radar_anchor"))
    end

    function mod:is_radar_position_unrestricted()
        return self:get("unrestricted_radar_position") == true
    end

    function mod:get_radar_offset_x(size)
        local radar_size = tonumber(size) or self:get_configured_radar_size()
        local max_x = _get_radar_position_bounds(radar_size)
        local value = self:get("radar_pos_x")

        return _resolve_radar_position_value(
            value,
            DEFAULT_RADAR_POS_X,
            0,
            max_x,
            self:is_radar_position_unrestricted()
        )
    end

    function mod:get_radar_offset_y(size)
        local radar_size = tonumber(size) or self:get_configured_radar_size()
        local _, max_y = _get_radar_position_bounds(radar_size)
        local value = self:get("radar_pos_y")

        return _resolve_radar_position_value(
            value,
            DEFAULT_RADAR_POS_Y,
            0,
            max_y,
            self:is_radar_position_unrestricted()
        )
    end

    function mod:get_radar_pos_x(size)
        local radar_size = tonumber(size) or self:get_radar_size()

        if self:is_overview_mode_active() then
            local x = _overview_radar_origin(radar_size)

            return x
        end

        local x = _configured_radar_origin(radar_size)

        return x
    end

    function mod:get_radar_pos_y(size)
        local radar_size = tonumber(size) or self:get_radar_size()

        if self:is_overview_mode_active() then
            local _, y = _overview_radar_origin(radar_size)

            return y
        end

        local _, y = _configured_radar_origin(radar_size)

        return y
    end

    function mod:has_any_nearby_highlight_enabled()
        for _, setting_id in pairs(NEARBY_HIGHLIGHT_SETTING_BY_GROUP) do
            if self:get(setting_id) == true then
                return true
            end
        end

        return false
    end

    function mod:get_nearby_highlight_range()
        local value = tonumber(self:get("highlight_distance")) or 10

        if value < 5 then
            value = 5
        elseif value > 20 then
            value = 20
        end

        return value
    end

    function mod:show_nearby_highlight_distance_text_on_screen()
        local value = self:get("nearby_highlight_distance_text")

        return value == true or value == "screen" or value == "both"
    end

    function mod:get_nearby_highlight_thickness()
        local value = tonumber(self:get("nearby_highlight_thickness")) or 0

        if value < 0 then
            value = 0
        elseif value > 6 then
            value = 6
        end

        return math_floor(value + 0.5)
    end

    function mod:get_nearby_highlight_color(kind)
        if self.get_highlight_color then
            return self:get_highlight_color(kind)
        end

        return _copy_color_array(NEARBY_OUTLINE_COLOR_BY_KIND[kind]) or DEFAULT_COLOR_ARRAY_WHITE
    end

    function mod:is_nearby_highlight_distance_text_enabled_for_kind(kind)
        if not kind or not _kind_enabled(kind) then
            return false
        end

        local group_name = self:get_marker_scale_group(kind)
        local setting_id = group_name and NEARBY_HIGHLIGHT_DISTANCE_TEXT_SETTING_BY_GROUP[group_name] or nil

        if not setting_id then
            return false
        end

        return self:get(setting_id) == true
    end

    function mod:is_nearby_highlight_enabled_for_kind(kind)
        if not kind or not _kind_enabled(kind) then
            return false
        end

        local group_name = self:get_marker_scale_group(kind)
        local setting_id = group_name and NEARBY_HIGHLIGHT_SETTING_BY_GROUP[group_name] or nil

        if not setting_id then
            return false
        end

        return self:get(setting_id) == true
    end

    function mod:set_radar_position(x, y)
        local radar_size = self:get_configured_radar_size()
        local max_x, max_y = _get_radar_position_bounds(radar_size)
        local unrestricted = self:is_radar_position_unrestricted()
        local offset_x = self:get_radar_offset_x(radar_size)
        local offset_y = self:get_radar_offset_y(radar_size)

        if x ~= nil then
            offset_x = _resolve_radar_position_value(x, DEFAULT_RADAR_POS_X, 0, max_x, unrestricted)
            self:set("radar_pos_x", offset_x)
        end

        if y ~= nil then
            offset_y = _resolve_radar_position_value(y, DEFAULT_RADAR_POS_Y, 0, max_y, unrestricted)
            self:set("radar_pos_y", offset_y)
        end

        local anchor = self:get_radar_anchor()
        local resolved_x, resolved_y = _get_radar_origin_from_offsets(anchor, offset_x, offset_y, radar_size)

        local debug_mode = mod:get("debug_mode") == true

        if debug_mode then
            self:notify(
                "Radar anchor %s | offset X %d | offset Y %d | origin X %d | origin Y %d",
                anchor,
                offset_x,
                offset_y,
                resolved_x,
                resolved_y
            )
        end

        return resolved_x, resolved_y
    end

    function mod:set_radar_origin(x, y)
        local radar_size = self:get_configured_radar_size()
        local anchor = self:get_radar_anchor()
        local max_x, max_y = _get_radar_position_bounds(radar_size)
        local unrestricted = self:is_radar_position_unrestricted()

        local resolved_x = _resolve_radar_position_value(x, DEFAULT_RADAR_POS_X, 0, max_x, unrestricted)
        local resolved_y = _resolve_radar_position_value(y, DEFAULT_RADAR_POS_Y, 0, max_y, unrestricted)
        local offset_x, offset_y = _get_radar_offsets_from_origin(anchor, resolved_x, resolved_y, radar_size)

        offset_x = _resolve_radar_position_value(offset_x, DEFAULT_RADAR_POS_X, 0, max_x, unrestricted)
        offset_y = _resolve_radar_position_value(offset_y, DEFAULT_RADAR_POS_Y, 0, max_y, unrestricted)

        self:set("radar_pos_x", offset_x)
        self:set("radar_pos_y", offset_y)

        local debug_mode = mod:get("debug_mode") == true

        if debug_mode then
            self:notify(
                "Radar anchor %s | offset X %d | offset Y %d | origin X %d | origin Y %d",
                anchor,
                self:get_radar_offset_x(radar_size),
                self:get_radar_offset_y(radar_size),
                resolved_x,
                resolved_y
            )
        end

        return resolved_x, resolved_y
    end

    function mod:set_radar_anchor(anchor, preserve_visual_position)
        local radar_size = self:get_configured_radar_size()
        local current_x, current_y = _configured_radar_origin(radar_size)
        local normalized_anchor = _normalize_radar_anchor(anchor)

        self:set("radar_anchor", normalized_anchor)

        if preserve_visual_position then
            return self:set_radar_origin(current_x, current_y)
        end

        return self:set_radar_position(self:get("radar_pos_x"), self:get("radar_pos_y"))
    end

    function mod:nudge_radar(dx, dy)
        if self:is_overview_mode_active() then
            return false
        end

        if not _is_radar_keybind_runtime_allowed() then
            return false
        end

        local x, y = _configured_radar_origin()

        return self:set_radar_origin(x + (tonumber(dx) or 0), y + (tonumber(dy) or 0))
    end

    function mod:set_radar_enabled(enabled)
        local is_enabled = enabled == true

        self:set("enable_radar", is_enabled)

        if not is_enabled then
            self._radar_targets = _reuse_or_new_table(self._radar_targets)
            self._screen_highlight_targets = _reuse_or_new_table(self._screen_highlight_targets)
            self._highlight_source_radar_targets = _reuse_or_new_table(self._highlight_source_radar_targets)
            self._unclustered_radar_targets = _reuse_or_new_table(self._unclustered_radar_targets)
            self._radar_snapshot = nil
        end

        local debug_mode = mod:get("debug_mode") == true

        if debug_mode then
            self:notify("Radar %s", is_enabled and "enabled" or "disabled")
        end

        return is_enabled
    end

    function mod.toggle_radar_keybind(_)
        if not _is_radar_keybind_runtime_allowed() then
            return false
        end

        local current_value = mod:get("enable_radar") ~= false

        return mod:set_radar_enabled(not current_value)
    end

    function mod.toggle_overview_keybind(_)
        if not _is_radar_keybind_runtime_allowed() then
            return false
        end

        return mod:set_overview_mode_active(not mod:is_overview_mode_active())
    end

    function mod.radar_zoom_modifier_keybind(_)
        if not _is_radar_keybind_runtime_allowed() then
            return false
        end

        mod._normal_radar_zoom_modifier_t = _safe_gameplay_time() or 0

        return true
    end

    function mod.overview_zoom_in_keybind(_)
        return mod:adjust_radar_zoom("in")
    end

    function mod.overview_zoom_out_keybind(_)
        return mod:adjust_radar_zoom("out")
    end

    function mod.radar_zoom_reset_keybind(_)
        return mod:reset_radar_zoom()
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
        if outside_range and not ignore_radar_range and not self:is_overview_mode_active() then
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
                local projected_distance = math_sqrt(px * px + py * py)
                if projected_distance > 0 then
                    local circle_scale = max_radius / projected_distance
                    px = px * circle_scale
                    py = py * circle_scale
                end
            else
                local max_component = math_max(math_abs(px), math_abs(py))
                if max_component > 0 then
                    local square_scale = max_radius / max_component
                    px = px * square_scale
                    py = py * square_scale
                end
            end
        end

        return px, py
    end
end
