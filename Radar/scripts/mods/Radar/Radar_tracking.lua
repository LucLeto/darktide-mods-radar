return function(env)
    setfenv(1, env)

    local mod = mod

    local pcall = pcall
    local pairs = pairs
    local tonumber = tonumber
    local tostring = tostring
    local math_abs = math.abs
    local math_floor = math.floor
    local math_huge = math.huge
    local math_max = math.max
    local math_sqrt = math.sqrt
    local string_find = string.find
    local string_format = string.format
    local table_concat = table.concat
    local table_sort = table.sort

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

    local function _refresh_player_units()
        local player_manager = _player_manager()
        if not player_manager or not player_manager.players then
            return
        end

        local local_player = _local_player()

        for _, player in pairs(player_manager:players()) do
            local unit = player.player_unit
            if unit and _safe_unit_alive(unit) and player ~= local_player then
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

                local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
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
                })
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
        local seen_interactees = {}

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
                    if kind and (kind ~= "expedition_loot_converter" or _is_in_expedition_safe_zone()) then
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
        local seen_chests = {}

        for unit, extension in pairs(chest_map) do
            if _safe_unit_alive(unit) and extension then
                seen_chests[unit] = true

                local is_open_fn = extension.is_open

                if is_open_fn then
                    local ok_open, is_open = pcall(is_open_fn, extension)

                    if ok_open and not is_open then
                        _track_unit(unit, "crate_unknown", "chest_system")
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

    local function _scan_minions()
        local unit_data_map = _safe_unit_to_extension_map("unit_data_system")
        if not unit_data_map then
            return
        end

        for unit, extension in pairs(unit_data_map) do
            if _safe_unit_alive(unit) and extension then
                local breed_name_fn = extension.breed_name

                if breed_name_fn then
                    local ok_breed, breed_name = pcall(breed_name_fn, extension)

                    if ok_breed and breed_name then
                        local resolved_breed_name = _resolve_enemy_breed_name(unit, breed_name)
                        local kind = _classify_enemy_from_breed(resolved_breed_name)
                        if kind and _is_trackable_unit_alive(unit, kind) then
                            _track_unit(unit, kind, "unit_data_system", {
                                breed_name = breed_name,
                                resolved_breed_name = resolved_breed_name,
                            })
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
        local seen_destructibles = {}

        for unit, extension in pairs(destructible_map) do
            if _safe_unit_alive(unit) and extension then
                seen_destructibles[unit] = true

                local collectible_type = _safe_unit_collectible_type(unit)
                local collectible_data = _safe_destructible_collectible_data(extension)
                local collectible_id = collectible_data and collectible_data.id or nil
                local collectible_section_id = collectible_data and collectible_data.section_id or nil
                local collectible_name = collectible_data and collectible_data.name or nil
                local collectible_key = _idol_collectible_key(collectible_section_id, collectible_id)
                local extension_visible = _safe_destructible_visible(extension)
                local unit_visible = _safe_unit_main_visible(unit)
                local health_alive = _safe_health_alive(unit)
                local has_active_collectible = collectible_id ~= nil and collectible_section_id ~= nil
                local destroyed_by_event = mod._idol_destroyed_units[unit] ~= nil
                    or (collectible_key ~= nil and mod._idol_destroyed_collectible_keys[collectible_key] ~= nil)

                if not destroyed_by_event and has_active_collectible and extension_visible == true and health_alive ~= false and unit_visible ~= false then
                    _track_unit(unit, "pickup_heretic_idol", "destructible_system", {
                        collectible_type = collectible_type,
                        unit_name = _safe_lower_string(_safe_unit_name(unit)),
                        extension_visible = extension_visible,
                        unit_visible = unit_visible,
                        health_alive = health_alive,
                        collectible_id = collectible_id,
                        collectible_name = collectible_name,
                        collectible_section_id = collectible_section_id,
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
                    local position = _safe_unit_position(unit) or data.position

                    if position then
                        data.position = position
                    else
                        tracked_units[unit] = nil
                    end
                end
            end
        end
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

    local function _supports_vertical_item_marker(kind)
        if not kind then
            return false
        end

        if kind == "player_teammate" then
            return false
        end

        if _is_player_smart_tag_kind(kind) then
            return mod:get("show_player_tag_elevation") == true
        end

        if _is_enemy_kind(kind) then
            return false
        end

        if _is_expedition_marker_kind(kind) then
            return false
        end

        return true
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
        local cluster_count = 0
        local marked_by_player_slot = nil

        for i = 1, #cluster_members do
            local member = cluster_members[i]
            local meta = member and member.meta or nil

            cluster_count = cluster_count + 1
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
                remnant_cluster_count = cluster_count,
                remnant_cluster_value = total_value,
                remnant_value = total_value,
                remnant_show_value_text = cluster_count > 1,
                remnant_value_text = tostring(total_value),
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

    local function _compare_radar_targets_by_distance(a, b)
        return (a.distance_sq or math_huge) < (b.distance_sq or math_huge)
    end

    local function _compare_radar_targets_boss_first(a, b)
        local a_is_boss = _is_boss_marker_kind(a.kind)
        local b_is_boss = _is_boss_marker_kind(b.kind)

        if a_is_boss ~= b_is_boss then
            return a_is_boss
        end

        return (a.distance_sq or math_huge) < (b.distance_sq or math_huge)
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
            return {}
        end

        local player_pos = _safe_unit_position(player_unit)
        if not player_pos then
            return {}
        end

        local max_range = mod:get_radar_range()
        local max_range_sq = max_range * max_range
        local max_markers = mod:get_max_radar_markers()
        local item_vertical_arrow_threshold = mod:get_item_vertical_arrow_threshold()
        local item_vertical_hide_threshold = mod:get_item_vertical_hide_threshold()
        local item_vertical_arrow_threshold_sq = item_vertical_arrow_threshold * item_vertical_arrow_threshold
        local tracked_units = mod._tracked_units
        local tracked_points = mod._tracked_points
        local targets = {}
        local target_count = 0
        local kind_enabled_cache = {}
        local ignore_range_cache = {}
        local supports_vertical_cache = {}
        local render_layer_cache = {}
        local selection_priority_cache = {}
        local priority_target_cache = {}
        local get_target_render_layer = mod.get_target_render_layer
        local get_target_selection_priority = mod.get_target_selection_priority

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

        local function _cached_supports_vertical_item_marker(kind)
            local supports_vertical = supports_vertical_cache[kind]

            if supports_vertical == nil then
                supports_vertical = _supports_vertical_item_marker(kind)
                supports_vertical_cache[kind] = supports_vertical
            end

            return supports_vertical
        end

        local function _cached_priority_target(kind)
            local is_priority_target = priority_target_cache[kind]

            if is_priority_target == nil then
                is_priority_target = kind == "enemy_daemonhost" or _is_boss_marker_kind(kind) or
                    ENEMY_RADAR_DEFINITION_BY_KIND[kind] ~= nil or
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

            if not position or not kind or not _cached_kind_enabled(kind) then
                return
            end

            local source = data.source
            local meta = data.meta

            if kind == "pickup_heretic_idol" and source == "destructible_system" then
                if not meta or meta.collectible_id == nil then
                    return
                end
            end

            local distance_sq_horizontal = _distance_squared_horizontal(player_pos, position)
            local ignore_range = _cached_ignore_radar_range(kind)

            if distance_sq_horizontal > max_range_sq and not ignore_range then
                return
            end

            local vertical_delta = nil
            local vertical_state = nil

            if _cached_supports_vertical_item_marker(kind) then
                vertical_delta = _vertical_delta(player_pos, position)

                if vertical_delta ~= nil then
                    local abs_vertical_delta = math_abs(vertical_delta)

                    if abs_vertical_delta >= item_vertical_hide_threshold then
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

            if _cached_priority_target(kind) then
                render_layer = _cached_render_layer(kind)
                selection_priority = _cached_selection_priority(kind)
            end

            target_count = target_count + 1
            targets[target_count] = {
                unit = unit,
                kind = kind,
                position = position,
                source = source,
                meta = meta,
                distance_sq = distance_sq_horizontal,
                distance_sq_3d = _distance_squared(player_pos, position),
                vertical_delta = vertical_delta,
                vertical_state = vertical_state,
                ignore_radar_range = ignore_range,
                render_layer = render_layer,
                selection_priority = selection_priority,
            }
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
        mod._highlight_source_radar_targets = _copy_target_list(targets)

        targets = _cluster_expedition_loot_targets(targets, player_pos, item_vertical_arrow_threshold_sq,
            item_vertical_hide_threshold)

        table_sort(targets, _compare_radar_targets_for_display)

        local target_total = #targets

        if target_total > max_markers then
            for i = target_total, max_markers + 1, -1 do
                targets[i] = nil
            end
        end

        return targets
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

        local local_player = _local_player()

        return {
            player_unit = player_unit,
            player_position = player_pos,
            player_rotation = _safe_player_rotation(player_unit),
            player_slot = _safe_player_slot(local_player),
            targets = mod._radar_targets,
            screen_highlights = mod._screen_highlight_targets,
        }
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

        mod:echo(string_format(
            "Radar scan | enemies=%d players=%d ammo=%d crates=%d pocketables=%d materials=%d generic=%d tracked=%d radar_targets=%d mission=%s activity=%s mechanism=%s player_state=%s",
            counts.enemies,
            counts.players,
            counts.ammo,
            counts.crates,
            counts.pocketables,
            counts.materials,
            counts.generic,
            _table_size(mod._tracked_units),
            #mod._radar_targets,
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
        mod._tracked_units = {}
        mod._tracked_points = {}
        mod._logged_units = {}
        mod._radar_targets = {}
        mod._radar_snapshot = nil
        mod._last_update_t = nil
        mod._last_scan_signature = nil
        mod._last_block_signature = nil
        mod._last_state_gameplay = nil
        mod._idol_destroyed_collectible_keys = {}
        mod._idol_destroyed_units = {}
    end

    local function _debug_log_block(reason, gameplay_t, mission_name, activity, mechanism_name)
        if mod:get("debug_mode") ~= true then
            return
        end

        local player_unit = _player_unit()
        local player_state = _safe_player_character_state_name(player_unit)

        local signature = table_concat({
            tostring(reason),
            tostring(mission_name),
            tostring(activity),
            tostring(mechanism_name),
            tostring(gameplay_t),
            tostring(player_state),
        }, "|")

        if signature == mod._last_block_signature then
            return
        end

        mod._last_block_signature = signature
        mod:echo(string_format(
            "Radar blocked | reason=%s mission=%s activity=%s mechanism=%s gameplay_t=%s player_state=%s",
            tostring(reason),
            tostring(mission_name),
            tostring(activity),
            tostring(mechanism_name),
            tostring(gameplay_t),
            tostring(player_state)
        ))
    end

    local function _update_internal(dt, t)
        if mod:get("enable_radar") == false then
            mod._tracked_points = {}
            mod._radar_targets = {}
            mod._screen_highlight_targets = {}
            mod._unclustered_radar_targets = {}
            mod._highlight_source_radar_targets = {}
            mod._radar_snapshot = nil
            return
        end

        local allowed, reason, gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos =
            _get_runtime_state()
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
                mod._tracked_units = {}
            end

            mod._tracked_points = {}
            mod._radar_targets = {}
            mod._screen_highlight_targets = {}
            mod._unclustered_radar_targets = {}
            mod._highlight_source_radar_targets = {}
            mod._radar_snapshot = nil
            _debug_log_block(reason, gameplay_t, mission_name, activity, mechanism_name)
            return
        end

        mod._radar_snapshot = {
            player_unit = player_unit,
            player_position = player_pos,
            player_rotation = _safe_player_rotation(player_unit),
            player_slot = _safe_player_slot(_local_player()),
            targets = mod._radar_targets,
            screen_highlights = mod._screen_highlight_targets,
        }

        if scan_clock < (mod._next_scan_t or 0) then
            return
        end

        mod._next_scan_t = scan_clock + SCAN_INTERVAL

        _scan_interactees()
        _scan_chests()
        _scan_minions()
        _scan_destructibles()
        _scan_smart_tag_targets()
        _refresh_player_units()
        _scan_expedition_objectives()
        _scan_player_tag_points()
        _prune_units()

        mod._radar_targets = _collect_radar_targets()
        mod._screen_highlight_targets = _collect_screen_highlight_targets()
        mod._radar_snapshot = _collect_radar_snapshot()

        _debug_log_scan()
    end

    mod.on_game_state_changed = function(status, state_name)
        if status == "enter" and state_name == "GameplayStateRun" then
            mod._gameplay_run = true
            mod._next_scan_t = 0
            mod._last_update_t = nil
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

    mod:hook_safe("StateGameplay", "update", function(self, dt, t, ...)
        mod._last_state_gameplay = self
        _update_internal(dt, t)
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

    mod.update = function(dt)
        if not mod._gameplay_run then
            return
        end

        _update_internal(dt, _safe_gameplay_time())
    end

    function mod:get_player_display_style()
        local value = tostring(self:get("player_display_style") or "marked_icon")

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

        return value ~= false
    end

    function mod:get_show_player_center_dot()
        return self:get("show_player_center_dot") ~= false
    end

    function mod:get_radar_snapshot()
        return self._radar_snapshot
    end

    function mod:get_screen_highlight_targets()
        return self._screen_highlight_targets or {}
    end

    function mod:should_draw_radar()
        if self:get("enable_radar") == false then
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

    function mod:get_radar_size()
        return self:get("radar_size") or 220
    end

    function mod:get_radar_range()
        local value = tonumber(self:get("radar_range")) or 40

        if value < 25 then
            value = 25
        elseif value > 100 then
            value = 100
        end

        return value
    end

    function mod:get_max_radar_markers()
        local value = tonumber(self:get("max_radar_markers")) or 64

        if value < 10 then
            value = 10
        elseif value > 200 then
            value = 200
        end

        return math_floor(value)
    end

    function mod:get_background_opacity()
        local value = tonumber(self:get("background_opacity")) or 90

        if value < 0 then
            value = 0
        elseif value > 255 then
            value = 255
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

        if value ~= "circle" then
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

        if value ~= "crosshair" and value ~= "view_guides" and value ~= "range_rings" and value ~= "off" then
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
        local radar_size = tonumber(size) or self:get_radar_size()
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
        local radar_size = tonumber(size) or self:get_radar_size()
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
        local anchor = self:get_radar_anchor()
        local offset_x = self:get_radar_offset_x(radar_size)
        local offset_y = self:get_radar_offset_y(radar_size)
        local x = _get_radar_origin_from_offsets(anchor, offset_x, offset_y, radar_size)

        return math_floor(x + 0.5)
    end

    function mod:get_radar_pos_y(size)
        local radar_size = tonumber(size) or self:get_radar_size()
        local anchor = self:get_radar_anchor()
        local offset_x = self:get_radar_offset_x(radar_size)
        local offset_y = self:get_radar_offset_y(radar_size)
        local _, y = _get_radar_origin_from_offsets(anchor, offset_x, offset_y, radar_size)

        return math_floor(y + 0.5)
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
        local radar_size = self:get_radar_size()
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

        if mod:get("debug_mode") == true then
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
        local radar_size = self:get_radar_size()
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

        if mod:get("debug_mode") == true then
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
        local radar_size = self:get_radar_size()
        local current_x = self:get_radar_pos_x(radar_size)
        local current_y = self:get_radar_pos_y(radar_size)
        local normalized_anchor = _normalize_radar_anchor(anchor)

        self:set("radar_anchor", normalized_anchor)

        if preserve_visual_position then
            return self:set_radar_origin(current_x, current_y)
        end

        return self:set_radar_position(self:get("radar_pos_x"), self:get("radar_pos_y"))
    end

    function mod:nudge_radar(dx, dy)
        local x = self:get_radar_pos_x()
        local y = self:get_radar_pos_y()

        return self:set_radar_origin(x + (tonumber(dx) or 0), y + (tonumber(dy) or 0))
    end

    function mod:set_radar_enabled(enabled)
        local is_enabled = enabled == true

        self:set("enable_radar", is_enabled)

        if not is_enabled then
            self._radar_targets = {}
            self._screen_highlight_targets = {}
            self._highlight_source_radar_targets = {}
            self._unclustered_radar_targets = {}
            self._radar_snapshot = nil
        end

        if mod:get("debug_mode") == true then
            self:notify("Radar %s", is_enabled and "enabled" or "disabled")
        end

        return is_enabled
    end

    function mod.toggle_radar_keybind(_)
        local current_value = mod:get("enable_radar") ~= false

        return mod:set_radar_enabled(not current_value)
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
        if outside_range and not ignore_radar_range then
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
