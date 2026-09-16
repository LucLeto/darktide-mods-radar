return function(env)
    setfenv(1, env)

    local mod = mod
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

    -- ----------------------------------------------------------------------------
    -- Constants
    -- ----------------------------------------------------------------------------

    local STATIC_SCAN_INTERVAL = SCAN_INTERVAL * 2

    -- Only self-moving targets (enemies, teammates, companions) follow the
    -- configurable rate. Droppable items (pocketables, deployables, expedition
    -- drops, tag points) rescan at the fixed DROPPABLE_SCAN_INTERVAL, and fully
    -- static props (chests, destructibles, hazards) keep the even slower
    -- STATIC_SCAN_INTERVAL since they never move.
    local SCAN_INTERVAL_BY_RATE = {
        low = SCAN_INTERVAL,
        medium = 0.1,
        high = 0.05,
    }
    local DROPPABLE_SCAN_INTERVAL = SCAN_INTERVAL
    local OVERVIEW_MIN_ZOOM_RANGE = 25
    local OVERVIEW_MAX_ZOOM_RANGE = 500
    local OVERVIEW_DEFAULT_ZOOM_RANGE = OVERVIEW_MAX_ZOOM_RANGE
    local OVERVIEW_SCREEN_PADDING = 80
    local OVERVIEW_RANGE_TRANSITION_DURATION = 0.28
    local OVERVIEW_RANGE_TRANSITION_SCAN_INTERVAL = 0.05
    local OVERVIEW_RESET_FIT_EDGE_FRACTION = 0.9
    local OVERVIEW_RADAR_MARKER_LIMIT = 300
    local NORMAL_RADAR_MIN_ZOOM_RANGE = 10
    local NORMAL_RADAR_MAX_ZOOM_RANGE = 200
    local NORMAL_RADAR_DEFAULT_ZOOM_RANGE = NORMAL_RADAR_MAX_ZOOM_RANGE
    local NORMAL_RADAR_RESET_ZOOM_RANGE = NORMAL_RADAR_MIN_ZOOM_RANGE
    local NORMAL_RADAR_ZOOM_MODIFIER_GRACE = 0.12
    local NORMAL_RADAR_ZOOM_INDICATOR_DURATION = 1
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
    local COMPANION_ACTION_RENDER_LAYER = 6

    -- Sources whose units move on their own every frame (enemies, teammates,
    -- companions). Units from any other source only get their stored position
    -- refreshed on droppable-item ticks, since props never move and droppables
    -- move rarely.
    local MOVING_TRACK_SOURCES = {
        unit_data_system = true,
        player_manager = true,
        player_companion = true,
    }

    -- Kinds that move under their own power even though they are tracked from a
    -- slow scan tier. Their positions refresh at the configurable scan rate, so
    -- a flying servo skull does not lag a quarter of a second behind.
    local MOVING_TRACK_KINDS = {
        mission_objective_servo_skull = true,
    }
    ITEM_VERTICAL_ARROW_Z_DEADZONE = 2

    -- The flying servo skull hovers well above head height and bobs as it moves,
    -- so the shared 2 m deadzone reads it as being on another floor. A larger
    -- deadzone keeps the arrow for genuine floor changes only. This overrides the
    -- height at which an arrow appears; the player's own "show vertical arrows
    -- within range" distance setting still applies unchanged.
    local VERTICAL_ARROW_Z_DEADZONE_BY_KIND = {
        mission_objective_servo_skull = 6,
    }

    -- Kinds that must never be hidden for being above or below the player.
    -- Every mission objective marker qualifies: an objective a floor up is
    -- exactly what you need to see, and losing the marker is worse than an
    -- imprecise one. Objective kinds are matched by predicate so a new category
    -- is covered without a second edit here.
    local VERTICAL_HIDE_EXEMPT_KINDS = {
        pickup_heretic_idol = true,
    }

    -- ----------------------------------------------------------------------------
    -- Mutable runtime state
    -- ----------------------------------------------------------------------------

    mod._next_scan_t = 0
    mod._tracked_units = {}
    mod._tracked_points = {}
    mod._logged_units = {}
    mod._radar_targets = {}
    mod._radar_snapshot = nil
    mod._gameplay_run = false
    mod._last_update_t = nil
    mod._last_scan_signature = nil
    mod._last_block_signature = nil
    mod._screen_highlight_targets = {}
    mod._unclustered_radar_targets = {}
    mod._highlight_source_radar_targets = {}

    local _scratch_kind_enabled_cache = {}
    local _scratch_ignore_range_cache = {}
    local _scratch_infinite_range_cache = {}
    local _scratch_supports_vertical_cache = {}
    local _scratch_render_layer_cache = {}
    local _scratch_selection_priority_cache = {}
    local _scratch_priority_target_cache = {}
    local _scratch_seen_interactees = {}

    -- ----------------------------------------------------------------------------
    -- Generic helpers
    -- ----------------------------------------------------------------------------

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

    function _distance_squared_horizontal(a, b)
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

    function _vertical_delta(a, b)
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

    function _debug_position_text(position)
        local x, y, z = _vector3_components(position)

        if not _is_finite_number(x) or not _is_finite_number(y) or not _is_finite_number(z) then
            return "nil"
        end

        return string_format("%.3f,%.3f,%.3f", x, y, z)
    end

    function _debug_unit_position_text(unit)
        return _debug_position_text(_safe_unit_position(unit))
    end

    -- ----------------------------------------------------------------------------
    -- Unit and point tracking
    -- ----------------------------------------------------------------------------

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

    function _track_point(id, kind, position, source, meta)
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

    -- ----------------------------------------------------------------------------
    -- Marker kind enablement and range
    -- ----------------------------------------------------------------------------

    function _is_boss_marker_kind(kind)
        return kind == "enemy_monstrosity"
            or kind == "enemy_captain"
            or kind == "enemy_karnak_twin"
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

    -- ----------------------------------------------------------------------------
    -- Input and keybind helpers
    -- ----------------------------------------------------------------------------

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

    -- ----------------------------------------------------------------------------
    -- Radar geometry and zoom helpers
    -- ----------------------------------------------------------------------------

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

    -- ----------------------------------------------------------------------------
    -- Unit scans
    -- ----------------------------------------------------------------------------

    local function _scan_interactees()
        local interactee_map = _safe_unit_to_extension_map("interactee_system")
        if not interactee_map then
            return
        end

        local player_unit = _player_unit()
        local tracked_units = mod._tracked_units
        local seen_interactees = _scratch_seen_interactees
        local martyr_skull_riddle_fallback_mission_name = _martyr_skull_riddle_fallback_mission_name()
        local force_hidden_martyr_skull_riddle_interactables = _kind_enabled("martyr_skull_riddle_interactable")
            and _should_scan_hidden_martyr_skull_riddle_interactables()
        table_clear(seen_interactees)

        local scan_hidden_mission_objectives = _refresh_mission_objective_markers()

        for unit, extension in pairs(interactee_map) do
            if _safe_unit_alive(unit) and extension then
                seen_interactees[unit] = true

                local is_active = true
                local is_used = false
                local show_marker = true
                local active_state = nil
                local used_state = nil
                local show_marker_state = nil

                local active = extension.active
                if active then
                    local ok_active, value = pcall(active, extension)
                    if ok_active and (value == true or value == false) then
                        active_state = value
                    end

                    if not ok_active or value ~= true then
                        is_active = false
                    end
                end

                local used = extension.used
                if used then
                    local ok_used, value = pcall(used, extension)
                    if ok_used and (value == true or value == false) then
                        used_state = value
                    end

                    if not ok_used or value == true then
                        is_used = true
                    end
                end

                local show_marker_fn = extension.show_marker
                if show_marker_fn then
                    if player_unit then
                        local ok_show, value = pcall(show_marker_fn, extension, player_unit)
                        if ok_show and (value == true or value == false) then
                            show_marker_state = value
                        end

                        if not ok_show or value ~= true then
                            show_marker = false
                        end
                    else
                        show_marker = false
                    end
                end

                local kind = nil
                local meta = nil

                -- Fed before classification so a step that has just gone
                -- inactive is already retired by the time it is classified.
                _update_mission_objective_lifecycle(unit, active_state, used_state)

                if is_active and not is_used then
                    if show_marker then
                        kind, meta = _classify_interactee(extension, unit)
                    else
                        -- Mission objective interactables have to be visible
                        -- before the game draws their own prompt, so they are
                        -- classified while `show_marker` is still false. The
                        -- pre-check is a table lookup plus at most one extension
                        -- call, so full classification stays limited to units
                        -- that are actually objective-bound.
                        local hidden_objective = scan_hidden_mission_objectives
                            and _hidden_mission_objective_kind(extension, unit) ~= nil

                        if hidden_objective or force_hidden_martyr_skull_riddle_interactables then
                            kind, meta = _classify_interactee(extension, unit, true, true)

                            local keep = (hidden_objective and _is_mission_objective_marker_kind(kind))
                                or (force_hidden_martyr_skull_riddle_interactables
                                    and kind == "martyr_skull_riddle_interactable")

                            if not keep then
                                kind = nil
                                meta = nil
                            end
                        end
                    end

                    if kind
                        and not _should_hide_expedition_store_product_in_open_zone(unit)
                        and (kind ~= "expedition_loot_converter" or _is_in_expedition_safe_zone()) then
                        _track_unit(unit, kind, "interactee_system", meta)
                    else
                        _clear_tracked_unit_from_source(unit, "interactee_system")
                    end
                else
                    -- An interactee that reports itself inactive is not part of
                    -- the current step. Missions place several copies of the same
                    -- device and arm one at a time, so marking inactive ones puts
                    -- every copy on the radar at once. `show_marker` is bypassed
                    -- above so a marker still appears before the prompt does;
                    -- `active` is not, because it is what distinguishes the live
                    -- device from its siblings.
                    _clear_tracked_unit_from_source(unit, "interactee_system")
                end

                if martyr_skull_riddle_fallback_mission_name then
                    _update_martyr_skull_riddle_fallback_state(
                        extension,
                        unit,
                        active_state,
                        used_state,
                        show_marker_state,
                        kind == "martyr_skull_riddle_interactable",
                        martyr_skull_riddle_fallback_mission_name
                    )
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

        -- Runs last: objective zones and targets are often not interactees at
        -- all, so this is the only path that can reach them.
        _scan_mission_objective_targets(interactee_map)
    end

    local function _prune_units(refresh_item_positions)
        local now = _safe_gameplay_time() or 0
        local tracked_units = mod._tracked_units

        for unit, data in pairs(tracked_units) do
            if not _is_trackable_unit_alive(unit, data and data.kind) then
                tracked_units[unit] = nil
            else
                local last_seen_t = data.last_seen_t

                if last_seen_t and now - last_seen_t > 2.5 then
                    tracked_units[unit] = nil
                elseif refresh_item_positions or MOVING_TRACK_SOURCES[data.source]
                    or MOVING_TRACK_KINDS[data.kind] then
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

    -- ----------------------------------------------------------------------------
    -- Target filtering
    -- ----------------------------------------------------------------------------

    local function _is_vertical_hide_exempt(kind)
        return VERTICAL_HIDE_EXEMPT_KINDS[kind] == true or _is_mission_objective_marker_kind(kind)
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

    -- ----------------------------------------------------------------------------
    -- Radar target collection and update
    -- ----------------------------------------------------------------------------

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
        -- Whether the player is carrying a luggable: read once per pass, and only
        -- once a socket asks.
        local carrying_luggable = nil

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
        local distance_squared_horizontal = _distance_squared_horizontal
        local get_vertical_delta = _vertical_delta
        local mastiff_disabled_enemy_units = _mastiff_disabled_enemy_units()

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
                    kind == "martyr_skull_riddle_interactable" or
                    _is_mission_objective_marker_kind(kind) or
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
            local companion_action_active = _player_companion_action_active(kind, position, meta)
            -- A socket is drawn as what goes into it: one fed mission cargo
            -- rather than a power cell is an objective step, shown, coloured and
            -- switched with the other steps. It is still a socket to the range
            -- rule below.
            local is_socket = kind == "luggable_socket"

            if is_socket and _luggable_socket_display_kind ~= nil then
                kind = _luggable_socket_display_kind(unit)
            end

            if not position or not kind or (not _cached_kind_enabled(kind) and not ability_marked_enemy) then
                return
            end

            if kind == "player_companion_servo_skull" and _is_servo_skull_hidden_by_owner(position, meta) then
                return
            end

            if not _passes_tag_visibility_filter(kind, source, meta, only_tagged_enemies, only_tagged_items) then
                return
            end

            -- A luggable still shut in a container the radar is drawing sits
            -- under that container's marker; it comes back when the container
            -- is opened. One a player has tagged is always shown.
            if source == "interactee_system"
                and not explicitly_tagged_target
                and _luggable_hidden_in_container ~= nil
                and _luggable_hidden_in_container(unit) then
                return
            end

            if kind == "pickup_heretic_idol" and source == "destructible_system" then
                if not meta or meta.collectible_id == nil then
                    return
                end
            end

            local distance_sq_horizontal = distance_squared_horizontal(player_pos, position)
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

            -- An objective the game is itself pointing at stays on the radar
            -- however far away it is: the radar's range is there to keep the
            -- display readable, not to hide the step the mission is asking for.
            -- Every objective system answers "is the HUD showing this" its own
            -- way, and they all arrive here as one question, so a new objective
            -- type is a new answer rather than a new case in this decision.
            -- Objectives only; enemies, pickups and luggables are unaffected.
            if not ignore_range
                and _is_mission_objective_marker_kind(kind)
                and _objective_ignores_radar_range ~= nil
                and _objective_ignores_radar_range(unit) then
                ignore_range = true
            end

            -- Carrying a luggable, the sockets are where the mission is sending
            -- the player: like an objective the game points at, they stay on the
            -- radar however far away, and on whatever floor.
            local socket_while_carrying = false

            if is_socket then
                if carrying_luggable == nil then
                    local script_unit = ScriptUnit

                    carrying_luggable = _unit_carries_luggable(player_unit, script_unit and script_unit.has_extension)
                end

                socket_while_carrying = carrying_luggable

                if socket_while_carrying then
                    ignore_range = true
                end
            end

            if distance_sq_horizontal > max_range_sq and not ignore_range then
                return
            end

            local vertical_delta = nil
            local vertical_state = nil

            if _cached_supports_vertical_marker(kind) then
                vertical_delta = get_vertical_delta(player_pos, position)

                if vertical_delta ~= nil then
                    local abs_vertical_delta = math_abs(vertical_delta)

                    if not infinite_range
                        and not _is_vertical_hide_exempt(kind)
                        and not socket_while_carrying
                        and abs_vertical_delta >= item_vertical_hide_threshold then
                        return
                    end

                    if abs_vertical_delta >= (VERTICAL_ARROW_Z_DEADZONE_BY_KIND[kind]
                            or ITEM_VERTICAL_ARROW_Z_DEADZONE)
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
            target.disabled_by_mastiff = mastiff_disabled_enemy_units[unit] == true
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
            or SCAN_INTERVAL_BY_RATE[mod:get("radar_scan_rate")]
            or SCAN_INTERVAL

        mod._next_scan_t = scan_clock + scan_interval

        local droppable_scan_due = scan_clock >= (mod._next_droppable_scan_t or 0)

        if droppable_scan_due then
            mod._next_droppable_scan_t = scan_clock + DROPPABLE_SCAN_INTERVAL
        end

        local static_scan_due = scan_clock >= (mod._next_static_scan_t or 0)

        if static_scan_due then
            mod._next_static_scan_t = scan_clock + STATIC_SCAN_INTERVAL
        end

        local scan_start_time = mod:get("debug_mode") == true and os_clock and os_clock() or nil

        if droppable_scan_due then
            _sync_expedition_item_state()
            _scan_interactees()
        end

        if static_scan_due then
            _scan_chests()
        end

        _scan_minions()

        if static_scan_due then
            _scan_destructibles()
            _scan_hazard_props()
        end

        if droppable_scan_due then
            _scan_smart_tag_targets()
            _sync_martyr_skull_riddle_solve_state()
            _debug_log_martyr_skull_door_candidates()
        end

        _refresh_player_units()

        if droppable_scan_due then
            mod._tracked_points = {}
            _scan_expedition_objectives()
            _scan_martyr_skull_riddle_coordinate_fallbacks()
            _scan_player_tag_points()
        end

        _prune_units(droppable_scan_due)

        mod._radar_targets = _collect_radar_targets()
        mod._screen_highlight_targets = _collect_screen_highlight_targets()
        mod._radar_snapshot = _collect_radar_snapshot()

        if scan_start_time then
            mod._last_scan_cost_ms = (os_clock() - scan_start_time) * 1000
        end

        _debug_log_scan()
    end

    -- ----------------------------------------------------------------------------
    -- Mission lifecycle
    -- ----------------------------------------------------------------------------

    local function _reset_runtime_state()
        mod._screen_highlight_targets = {}
        mod._unclustered_radar_targets = {}
        mod._highlight_source_radar_targets = {}
        mod._next_scan_t = 0
        mod._next_droppable_scan_t = 0
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
        _reset_destroyed_idol_state()
        _reset_martyr_skull_riddle_state()
        _reset_mission_objective_marker_state()
        _reset_expedition_runtime_state()
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
        mod._last_radar_marker_capped = false
        mod._overview_marker_high_raw = 0
        mod._overview_marker_high_candidates = 0
        mod._overview_marker_high_active = 0
        mod._overview_marker_high_drawn = 0
        mod._last_overview_marker_debug_signature = nil

        if mod.reset_strikemap_integration then
            mod:reset_strikemap_integration()
        end

        _refresh_overview_input_capture()
    end

    mod.on_game_state_changed = function(status, state_name)
        if status == "enter" and state_name == "GameplayStateRun" then
            mod._gameplay_run = true
            _warm_radar_target_pool(512)
            mod._next_scan_t = 0
            mod._next_droppable_scan_t = 0
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

    -- ----------------------------------------------------------------------------
    -- Public interface
    -- ----------------------------------------------------------------------------

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

    function mod:get_map_geometry_source()
        local value = self:get("map_geometry_source")

        if value == nil then
            if self:get("use_strikemap_geometry") == true then
                value = "strikemap"
            elseif self:get("show_navmesh") == true then
                value = "live"
            end
        end

        if value ~= "live" and value ~= "strikemap" and value ~= "auto" then
            value = "off"
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

        if NEARBY_HIGHLIGHT_EXCLUDED_KINDS[kind] then
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

    -- ----------------------------------------------------------------------------
    -- Hooks
    -- ----------------------------------------------------------------------------

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

    -- ----------------------------------------------------------------------------
    -- DMF callbacks and initialization
    -- ----------------------------------------------------------------------------

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

end
