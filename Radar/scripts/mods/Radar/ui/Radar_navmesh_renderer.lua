local mod = get_mod("Radar")
local _clip_and_emit = mod:io_dofile("Radar/scripts/mods/Radar/ui/Radar_triangle_clipper")

-- Live map-geometry (navmesh) renderer
-- Author: dreams

local Color = Color
local Quaternion = Quaternion
local pcall = pcall
local tonumber = tonumber
local tostring = tostring
local type = type
local math_huge = math.huge
local math_sqrt = math.sqrt
local string_format = string.format
local os_clock = os and os.clock or nil

local Gui_triangle = Gui and Gui.triangle
local Quaternion_forward = Quaternion and Quaternion.forward

local NAVMESH_CURRENT_FALLBACK_COLOR = { 80, 101, 133, 96 }
local NAVMESH_BELOW_FALLBACK_COLOR = { 55, 120, 98, 76 }
local NAVMESH_ABOVE_FALLBACK_COLOR = { 32, 120, 150, 185 }
local NAVMESH_DEFAULT_RANGE_ABOVE = 3
local NAVMESH_DEFAULT_RANGE_BELOW = 7
local NAVMESH_OVERVIEW_RANGE = 30
local NAVMESH_CURRENT_FLOOR_HALF_DZ = 2.5
local SELECTION_MIN_INTERVAL = 0.25
local SELECTION_RANGE_REFRESH_INTERVAL = 0.1
local SELECTION_MOVE_THRESHOLD_SQ = 1.5 * 1.5
local SELECTION_RANGE_SLACK = 4
local SQUARE_RANGE_MULT = 1.4143
local DRAW_FAILURE_COOLDOWN = 5
local METRICS_LOG_INTERVAL = 5
local _visible = {}
local _visible_count = 0
local _sel_revision = -1
local _sel_origin_x = math_huge
local _sel_origin_y = math_huge
local _sel_origin_z = math_huge
local _sel_range = -1
local _sel_style = nil
local _sel_range_above = -1
local _sel_range_below = -1
local _sel_t = -math_huge
local _scratch_buckets = {}
local _below_idx, _current_idx, _above_idx = {}, {}, {}
local _last_draw_t = -math_huge
local _failed_until_t = -math_huge
local _last_failure_message = nil
local _metric_candidates = 0
local _metric_selected = 0
local _metric_selection_ms = 0
local _metric_drawn = 0
local _metric_draw_ms = 0
local _metric_band_below = 0
local _metric_band_current = 0
local _metric_band_above = 0
local _next_metrics_log_t = 0

local function _is_finite(v)
    return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
end

local function _forward_xy(rotation)
    if not rotation or not Quaternion_forward then
        return nil, nil
    end

    local ok, forward = pcall(Quaternion_forward, rotation)

    if not ok or not forward then
        return nil, nil
    end

    local fx, fy = forward.x, forward.y

    if not _is_finite(fx) or not _is_finite(fy) then
        return nil, nil
    end

    local length = math_sqrt(fx * fx + fy * fy)

    if length <= 0 then
        return nil, nil
    end

    return fx / length, fy / length
end

local function _current_radar_style()
    local value = mod:get("radar_style")

    if value == nil and mod.get_radar_style then
        value = mod:get_radar_style()
    end

    value = tostring(value or "square")

    if value ~= "circle" and value ~= "auspex" then
        value = "square"
    end

    return value
end

local function _band_widget_color(prefix, fallback)
    local get_radar_color = mod.get_radar_color

    return get_radar_color and get_radar_color(mod, prefix, fallback) or fallback
end

local function _any_band_visible()
    local current = _band_widget_color("radar_navmesh", NAVMESH_CURRENT_FALLBACK_COLOR)
    local below = _band_widget_color("radar_navmesh_below", NAVMESH_BELOW_FALLBACK_COLOR)
    local above = _band_widget_color("radar_navmesh_above", NAVMESH_ABOVE_FALLBACK_COLOR)

    return (current[1] or 0) > 0 or (below[1] or 0) > 0 or (above[1] or 0) > 0
end

local function _clamp_range(value, fallback)
    value = tonumber(value) or fallback

    if value < 0.5 then
        value = 0.5
    elseif value > 100 then
        value = 100
    end

    return value
end

local function _configured_ranges()
    if mod:is_overview_mode_active() then
        return NAVMESH_OVERVIEW_RANGE, NAVMESH_OVERVIEW_RANGE
    end

    return _clamp_range(mod:get("navmesh_range_above"), NAVMESH_DEFAULT_RANGE_ABOVE),
        _clamp_range(mod:get("navmesh_range_below"), NAVMESH_DEFAULT_RANGE_BELOW)
end

local function _select_triangles(geometry, bucket_count, origin_x, origin_y, origin_z, select_range, range_above,
                                 range_below)
    local visible = _visible
    local mid_x, mid_y, mid_z = geometry.mid_x, geometry.mid_y, geometry.mid_z
    local radius = geometry.radius
    local n = 0

    for bucket_index = 1, bucket_count do
        local bucket = _scratch_buckets[bucket_index]

        for j = 1, #bucket do
            local i = bucket[j]
            local triangle_radius = radius[i]
            local dz = mid_z[i] - origin_z

            if dz <= range_above and dz >= -range_below then
                local dx = mid_x[i] - origin_x
                local dy = mid_y[i] - origin_y
                local reach = select_range + triangle_radius

                if dx * dx + dy * dy <= reach * reach then
                    n = n + 1
                    visible[n] = i
                end
            end
        end
    end

    _visible_count = n
    _metric_selected = n
end

local function _refresh_selection(geometry, origin_x, origin_y, origin_z, select_range, range_above, range_below)
    local query_range = select_range + geometry.max_radius
    local bucket_count = mod:get_navmesh_nearby_buckets(origin_x, origin_y, query_range, _scratch_buckets)
    local candidate_total = 0

    for b = 1, bucket_count do
        candidate_total = candidate_total + #_scratch_buckets[b]
    end

    _metric_candidates = candidate_total

    _select_triangles(geometry, bucket_count, origin_x, origin_y, origin_z, select_range, range_above, range_below)
end

local function _selection_current(geometry, t, origin_x, origin_y, origin_z, range, style, range_above, range_below)
    if geometry.revision ~= _sel_revision then
        return false
    end

    if style ~= _sel_style or range_above ~= _sel_range_above or range_below ~= _sel_range_below then
        return false
    end

    if t < _sel_t then
        return false
    end

    local elapsed = t - _sel_t

    if elapsed >= SELECTION_RANGE_REFRESH_INTERVAL then
        local range_delta = range - _sel_range

        if range_delta < 0 then
            range_delta = -range_delta
        end

        if range_delta > range * 0.02 then
            return false
        end
    end

    if elapsed >= SELECTION_MIN_INTERVAL then
        local dx = origin_x - _sel_origin_x
        local dy = origin_y - _sel_origin_y
        local dz = origin_z - _sel_origin_z

        if dx * dx + dy * dy + dz * dz > SELECTION_MOVE_THRESHOLD_SQ then
            return false
        end
    end

    return true
end

local function _log_metrics(geometry, t)
    if mod:get("debug_mode") ~= true then
        return
    end

    if t < _next_metrics_log_t and _next_metrics_log_t - t <= METRICS_LOG_INTERVAL then
        return
    end

    _next_metrics_log_t = t + METRICS_LOG_INTERVAL

    mod:info(string_format(
        "[Radar] navmesh layer | cached=%d candidates=%d selected=%d bands(b/c/a)=%d/%d/%d drawn=%d select_ms=%.2f draw_ms=%.2f build_ms=%.2f",
        geometry.count,
        _metric_candidates,
        _metric_selected,
        _metric_band_below,
        _metric_band_current,
        _metric_band_above,
        _metric_drawn,
        _metric_selection_ms,
        _metric_draw_ms,
        tonumber(geometry.build_ms) or -1
    ))
end

local function _invalidate_selection()
    _visible_count = 0
    _sel_revision = -1
end

local function _draw_geometry(ui_renderer, t, player_pos, rotation, center_x, center_y, projection_radius, range, z)
    if not player_pos or not rotation then
        return
    end

    range = tonumber(range) or 0
    projection_radius = tonumber(projection_radius) or 0

    if range <= 0 or projection_radius <= 0 then
        return
    end

    local origin_x = player_pos.x
    local origin_y = player_pos.y
    local origin_z = player_pos.z

    if not _is_finite(origin_x) or not _is_finite(origin_y) or not _is_finite(origin_z) then
        return
    end

    local geometry = mod:ensure_navmesh_geometry(t)

    if not geometry or geometry.count == 0 then
        _invalidate_selection()

        return
    end

    local gui = ui_renderer.gui

    if not gui then
        return
    end

    local forward_x, forward_y = _forward_xy(rotation)

    if not forward_x then
        return
    end

    local radar_style = _current_radar_style()
    local is_circle = radar_style == "circle"
    local range_above, range_below = _configured_ranges()
    local radar_scale = projection_radius / range
    local debug_mode = mod:get("debug_mode") == true

    if not _selection_current(geometry, t, origin_x, origin_y, origin_z, range, radar_style,
            range_above, range_below) then
        local selection_start = debug_mode and os_clock and os_clock() or nil

        local select_range = (is_circle and range or range * SQUARE_RANGE_MULT) + SELECTION_RANGE_SLACK

        _refresh_selection(geometry, origin_x, origin_y, origin_z, select_range, range_above, range_below)

        _sel_revision = geometry.revision
        _sel_origin_x = origin_x
        _sel_origin_y = origin_y
        _sel_origin_z = origin_z
        _sel_range = range
        _sel_style = radar_style
        _sel_range_above = range_above
        _sel_range_below = range_below
        _sel_t = t

        if selection_start then
            _metric_selection_ms = (os_clock() - selection_start) * 1000
        end
    end

    if _visible_count == 0 then
        if debug_mode then
            _log_metrics(geometry, t)
        end

        return
    end

    local draw_start = debug_mode and os_clock and os_clock() or nil
    local ui_scale = ui_renderer.scale or 1
    local render_settings = ui_renderer.render_settings
    local start_layer = render_settings and render_settings.start_layer or 0
    local layer = start_layer + (tonumber(z) or 0)

    local cur = _band_widget_color("radar_navmesh", NAVMESH_CURRENT_FALLBACK_COLOR)
    local below = _band_widget_color("radar_navmesh_below", NAVMESH_BELOW_FALLBACK_COLOR)
    local above = _band_widget_color("radar_navmesh_above", NAVMESH_ABOVE_FALLBACK_COLOR)
    local color_current = (cur[1] or 0) > 0 and Color(cur[1], cur[2] or 255, cur[3] or 255, cur[4] or 255) or nil
    local color_below = (below[1] or 0) > 0 and Color(below[1], below[2] or 255, below[3] or 255, below[4] or 255)
        or nil
    local color_above = (above[1] or 0) > 0 and Color(above[1], above[2] or 255, above[3] or 255, above[4] or 255)
        or nil

    local right_x = forward_y
    local right_y = -forward_x

    local limit = projection_radius
    local limit_sq = limit * limit
    local drawn = 0
    local clip_and_emit = _clip_and_emit
    local visible = _visible
    local visible_count = _visible_count
    local mid_z = geometry.mid_z
    local ax, ay = geometry.ax, geometry.ay
    local bx, by = geometry.bx, geometry.by
    local cx, cy = geometry.cx, geometry.cy
    local below_idx, current_idx, above_idx = _below_idx, _current_idx, _above_idx
    local below_n, current_n, above_n = 0, 0, 0
    local current_half = NAVMESH_CURRENT_FLOOR_HALF_DZ

    for k = 1, visible_count do
        local i = visible[k]
        local dz = mid_z[i] - origin_z

        if dz > current_half then
            above_n = above_n + 1
            above_idx[above_n] = i
        elseif dz < -current_half then
            below_n = below_n + 1
            below_idx[below_n] = i
        else
            current_n = current_n + 1
            current_idx[current_n] = i
        end
    end

    _metric_band_below = below_n
    _metric_band_current = current_n
    _metric_band_above = above_n

    for band = 1, 3 do
        local idx, count, color

        if band == 1 then
            idx, count, color = below_idx, below_n, color_below
        elseif band == 2 then
            idx, count, color = current_idx, current_n, color_current
        else
            idx, count, color = above_idx, above_n, color_above
        end

        if color then
            for k = 1, count do
                local i = idx[k]

                local dx = ax[i] - origin_x
                local dy = ay[i] - origin_y
                local sx1 = (dx * right_x + dy * right_y) * radar_scale
                local sy1 = -(dx * forward_x + dy * forward_y) * radar_scale

                dx = bx[i] - origin_x
                dy = by[i] - origin_y

                local sx2 = (dx * right_x + dy * right_y) * radar_scale
                local sy2 = -(dx * forward_x + dy * forward_y) * radar_scale

                dx = cx[i] - origin_x
                dy = cy[i] - origin_y

                local sx3 = (dx * right_x + dy * right_y) * radar_scale
                local sy3 = -(dx * forward_x + dy * forward_y) * radar_scale

                drawn = drawn + clip_and_emit(gui, layer, color, is_circle, limit, limit_sq, ui_scale, center_x,
                    center_y, sx1, sy1, sx2, sy2, sx3, sy3)
            end
        end
    end

    if draw_start then
        _metric_drawn = drawn
        _metric_draw_ms = (os_clock() - draw_start) * 1000
        _log_metrics(geometry, t)
    end
end

local RadarNavmesh = {}

local _was_active = false

function RadarNavmesh.is_active(suppressed)
    local source = mod.get_map_geometry_source and mod:get_map_geometry_source() or "off"
    local selected = source == "live" or (source == "auto" and not suppressed)
    local active = Gui_triangle ~= nil and selected and _any_band_visible()

    if _was_active and not active then
        if mod.clear_navmesh_geometry then
            mod:clear_navmesh_geometry()
        end

        _invalidate_selection()
    end

    _was_active = active

    return active
end

function RadarNavmesh.draw(ui_renderer, t, player_pos, rotation, center_x, center_y, projection_radius, range, z)
    if not Gui_triangle or not ui_renderer then
        return
    end

    t = tonumber(t) or 0

    if t < _last_draw_t then
        _failed_until_t = -math_huge
        _next_metrics_log_t = 0
        _invalidate_selection()
    end

    _last_draw_t = t

    if t < _failed_until_t then
        return
    end

    if not _any_band_visible() then
        return
    end

    local ok, err = pcall(_draw_geometry, ui_renderer, t, player_pos, rotation, center_x, center_y, projection_radius,
        range, z)

    if not ok then
        _failed_until_t = t + DRAW_FAILURE_COOLDOWN
        _invalidate_selection()

        if mod:get("debug_mode") == true then
            local message = tostring(err)

            if message ~= _last_failure_message then
                _last_failure_message = message
                mod:info(string_format("[Radar] navmesh draw failed (layer paused %ds): %s",
                    DRAW_FAILURE_COOLDOWN, message))
            end
        end
    end
end

return RadarNavmesh
