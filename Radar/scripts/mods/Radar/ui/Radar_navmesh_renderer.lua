local mod = get_mod("Radar")

-- Live map-geometry (navmesh) renderer
-- Author: dreams

local Color = Color
local Vector3 = Vector3
local Quaternion = Quaternion
local pcall = pcall
local tonumber = tonumber
local tostring = tostring
local type = type
local math_abs = math.abs
local math_atan2 = math.atan2
local math_cos = math.cos
local math_floor = math.floor
local math_huge = math.huge
local math_pi = math.pi
local math_sin = math.sin
local math_sqrt = math.sqrt
local string_format = string.format
local os_clock = os and os.clock or nil

local Gui_triangle = Gui and Gui.triangle
local Quaternion_forward = Quaternion and Quaternion.forward

local FULL_CIRCLE = math_pi * 2

local NAVMESH_CURRENT_FALLBACK_COLOR = { 80, 101, 133, 96 }
local NAVMESH_BELOW_FALLBACK_COLOR = { 55, 120, 98, 76 }
local NAVMESH_ABOVE_FALLBACK_COLOR = { 32, 120, 150, 185 }
local NAVMESH_DEFAULT_RANGE_ABOVE = 3
local NAVMESH_DEFAULT_RANGE_BELOW = 7
local NAVMESH_CURRENT_FLOOR_HALF_DZ = 2.5
local SELECTION_MIN_INTERVAL = 0.25
local SELECTION_RANGE_REFRESH_INTERVAL = 0.1
local SELECTION_MOVE_THRESHOLD_SQ = 1.5 * 1.5
local SELECTION_RANGE_SLACK = 4
local TRIANGLE_LIMIT_DEFAULT = 6000
local TRIANGLE_LIMIT_MIN = 1000
local TRIANGLE_LIMIT_MAX = 20000
local SELECTION_MAX_CANDIDATES = 60000
local DRAW_BUDGET_HEADROOM = 1.25
local LOD_CELL_SIDE = 32
local MAX_LOD_CELLS = (LOD_CELL_SIDE + 4) * (LOD_CELL_SIDE + 4)
local LOD_KEY_OFFSET = 65536
local LOD_KEY_STRIDE = 131072
local MIN_TRIANGLE_RADIUS_PX = 0.5
local LOD_ESCALATION_MAX_ATTEMPTS = 5
local SQUARE_RANGE_MULT = 1.4143
local CIRCLE_ARC_STEP = 0.26
local DRAW_FAILURE_COOLDOWN = 5
local METRICS_LOG_INTERVAL = 5
local _visible_mode = "triangles"
local _visible = {}
local _visible_count = 0
local _cell_x, _cell_y = {}, {}
local _cell_count = 0
local _cell_half = 0
local _sel_revision = -1
local _sel_origin_x = math_huge
local _sel_origin_y = math_huge
local _sel_origin_z = math_huge
local _sel_range = -1
local _sel_scale = -1
local _sel_style = nil
local _sel_range_above = -1
local _sel_range_below = -1
local _sel_triangle_limit = -1
local _sel_t = -math_huge
local _scratch_buckets = {}
local _poly_ax, _poly_ay = {}, {}
local _poly_bx, _poly_by = {}, {}
local _cell_seen = {}
local _cell_seen_keys = {}
local _below_idx, _current_idx, _above_idx = {}, {}, {}
local _last_draw_t = -math_huge
local _failed_until_t = -math_huge
local _last_failure_message = nil
local _metric_candidates = 0
local _metric_selected = 0
local _metric_selection_ms = 0
local _metric_drawn = 0
local _metric_draw_ms = 0
local _metric_lod_px = 0
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
    return _clamp_range(mod:get("navmesh_range_above"), NAVMESH_DEFAULT_RANGE_ABOVE),
        _clamp_range(mod:get("navmesh_range_below"), NAVMESH_DEFAULT_RANGE_BELOW)
end

local function _configured_triangle_limit()
    local value = tonumber(mod:get("navmesh_max_triangles")) or TRIANGLE_LIMIT_DEFAULT

    if value < TRIANGLE_LIMIT_MIN then
        value = TRIANGLE_LIMIT_MIN
    elseif value > TRIANGLE_LIMIT_MAX then
        value = TRIANGLE_LIMIT_MAX
    end

    return value
end

local function _clip_polygon_halfplane(in_x, in_y, in_count, a, b, limit, out_x, out_y)
    local out_count = 0
    local prev_x = in_x[in_count]
    local prev_y = in_y[in_count]
    local prev_d = a * prev_x + b * prev_y - limit

    for i = 1, in_count do
        local cur_x = in_x[i]
        local cur_y = in_y[i]
        local cur_d = a * cur_x + b * cur_y - limit

        if cur_d <= 0 then
            if prev_d > 0 then
                local f = prev_d / (prev_d - cur_d)

                out_count = out_count + 1
                out_x[out_count] = prev_x + (cur_x - prev_x) * f
                out_y[out_count] = prev_y + (cur_y - prev_y) * f
            end

            out_count = out_count + 1
            out_x[out_count] = cur_x
            out_y[out_count] = cur_y
        elseif prev_d <= 0 then
            local f = prev_d / (prev_d - cur_d)

            out_count = out_count + 1
            out_x[out_count] = prev_x + (cur_x - prev_x) * f
            out_y[out_count] = prev_y + (cur_y - prev_y) * f
        end

        prev_x, prev_y, prev_d = cur_x, cur_y, cur_d
    end

    return out_count
end

local function _clip_triangle_square(x1, y1, x2, y2, x3, y3, limit)
    local ax, ay = _poly_ax, _poly_ay
    local bx, by = _poly_bx, _poly_by

    ax[1], ay[1] = x1, y1
    ax[2], ay[2] = x2, y2
    ax[3], ay[3] = x3, y3

    local n = _clip_polygon_halfplane(ax, ay, 3, 1, 0, limit, bx, by)

    if n == 0 then
        return 0
    end

    n = _clip_polygon_halfplane(bx, by, n, -1, 0, limit, ax, ay)

    if n == 0 then
        return 0
    end

    n = _clip_polygon_halfplane(ax, ay, n, 0, 1, limit, bx, by)

    if n == 0 then
        return 0
    end

    return _clip_polygon_halfplane(bx, by, n, 0, -1, limit, ax, ay)
end

local function _segment_circle_t(px, py, qx, qy, radius_sq)
    local dx = qx - px
    local dy = qy - py
    local a = dx * dx + dy * dy

    if a <= 1e-9 then
        return nil
    end

    local b = px * dx + py * dy
    local c = px * px + py * py - radius_sq
    local disc = b * b - a * c

    if disc <= 0 then
        return nil
    end

    local root = math_sqrt(disc)

    return (-b - root) / a, (-b + root) / a
end

local function _append_arc(out_x, out_y, out_count, from_angle, to_angle, winding, radius)
    local delta = to_angle - from_angle

    if winding >= 0 then
        while delta < 0 do
            delta = delta + FULL_CIRCLE
        end
    else
        while delta > 0 do
            delta = delta - FULL_CIRCLE
        end
    end

    local steps = math_floor(math_abs(delta) / CIRCLE_ARC_STEP)

    for s = 1, steps do
        local angle = from_angle + delta * s / (steps + 1)

        out_count = out_count + 1
        out_x[out_count] = math_cos(angle) * radius
        out_y[out_count] = math_sin(angle) * radius
    end

    return out_count
end

local function _point_in_triangle(px, py, x1, y1, x2, y2, x3, y3)
    local d1 = (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1)
    local d2 = (x3 - x2) * (py - y2) - (y3 - y2) * (px - x2)
    local d3 = (x1 - x3) * (py - y3) - (y1 - y3) * (px - x3)
    local has_neg = d1 < 0 or d2 < 0 or d3 < 0
    local has_pos = d1 > 0 or d2 > 0 or d3 > 0

    return not (has_neg and has_pos)
end

local function _clip_triangle_circle(x1, y1, x2, y2, x3, y3, radius)
    local radius_sq = radius * radius
    local winding = (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1)
    local out_x, out_y = _poly_ax, _poly_ay
    local bx, by = _poly_bx, _poly_by

    bx[1], by[1] = x1, y1
    bx[2], by[2] = x2, y2
    bx[3], by[3] = x3, y3

    local out_count = 0
    local pending_exit_angle = nil
    local first_entry_angle = nil

    for i = 1, 3 do
        local px, py = bx[i], by[i]
        local qi = i == 3 and 1 or i + 1
        local qx, qy = bx[qi], by[qi]
        local p_inside = (px * px + py * py) <= radius_sq
        local q_inside = (qx * qx + qy * qy) <= radius_sq

        if p_inside then
            out_count = out_count + 1
            out_x[out_count] = px
            out_y[out_count] = py
        end

        if p_inside ~= q_inside then
            local t1, t2 = _segment_circle_t(px, py, qx, qy, radius_sq)

            if t1 then
                if p_inside then
                    local t = t2

                    if t < 0 then
                        t = 0
                    elseif t > 1 then
                        t = 1
                    end

                    local ix = px + (qx - px) * t
                    local iy = py + (qy - py) * t

                    out_count = out_count + 1
                    out_x[out_count] = ix
                    out_y[out_count] = iy
                    pending_exit_angle = math_atan2(iy, ix)
                else
                    local t = t1

                    if t < 0 then
                        t = 0
                    elseif t > 1 then
                        t = 1
                    end

                    local ix = px + (qx - px) * t
                    local iy = py + (qy - py) * t
                    local entry_angle = math_atan2(iy, ix)

                    if pending_exit_angle then
                        out_count = _append_arc(out_x, out_y, out_count, pending_exit_angle, entry_angle, winding,
                            radius)
                        pending_exit_angle = nil
                    elseif not first_entry_angle then
                        first_entry_angle = entry_angle
                    end

                    out_count = out_count + 1
                    out_x[out_count] = ix
                    out_y[out_count] = iy
                end
            end
        elseif not p_inside then
                        local t1, t2 = _segment_circle_t(px, py, qx, qy, radius_sq)

            if t1 and t1 > 0 and t1 < 1 and t2 > 0 and t2 < 1 then
                local entry_x = px + (qx - px) * t1
                local entry_y = py + (qy - py) * t1
                local exit_x = px + (qx - px) * t2
                local exit_y = py + (qy - py) * t2
                local entry_angle = math_atan2(entry_y, entry_x)

                if pending_exit_angle then
                    out_count = _append_arc(out_x, out_y, out_count, pending_exit_angle, entry_angle, winding, radius)
                    pending_exit_angle = nil
                elseif not first_entry_angle then
                    first_entry_angle = entry_angle
                end

                out_count = out_count + 1
                out_x[out_count] = entry_x
                out_y[out_count] = entry_y
                out_count = out_count + 1
                out_x[out_count] = exit_x
                out_y[out_count] = exit_y
                pending_exit_angle = math_atan2(exit_y, exit_x)
            end
        end
    end

    if pending_exit_angle and first_entry_angle then
        out_count = _append_arc(out_x, out_y, out_count, pending_exit_angle, first_entry_angle, winding, radius)
    end

    if out_count == 0 and _point_in_triangle(0, 0, x1, y1, x2, y2, x3, y3) then
        local steps = math_floor(FULL_CIRCLE / CIRCLE_ARC_STEP)
        local step_angle = FULL_CIRCLE / steps

        for s = 1, steps do
            local angle = step_angle * s

            out_x[s] = math_cos(angle) * radius
            out_y[s] = math_sin(angle) * radius
        end

        out_count = steps
    end

    return out_count
end

local function _clip_and_emit(gui, layer, color, is_circle, limit, limit_sq, ui_scale, center_x, center_y,
                              sx1, sy1, sx2, sy2, sx3, sy3, budget)
    local clipped_count

    if is_circle then
        if sx1 * sx1 + sy1 * sy1 <= limit_sq
            and sx2 * sx2 + sy2 * sy2 <= limit_sq
            and sx3 * sx3 + sy3 * sy3 <= limit_sq then
            clipped_count = -1
        else
            clipped_count = _clip_triangle_circle(sx1, sy1, sx2, sy2, sx3, sy3, limit)
        end
    else
        local inside1 = sx1 >= -limit and sx1 <= limit and sy1 >= -limit and sy1 <= limit
        local inside2 = sx2 >= -limit and sx2 <= limit and sy2 >= -limit and sy2 <= limit
        local inside3 = sx3 >= -limit and sx3 <= limit and sy3 >= -limit and sy3 <= limit

        if inside1 and inside2 and inside3 then
            clipped_count = -1
        elseif (sx1 > limit and sx2 > limit and sx3 > limit)
            or (sx1 < -limit and sx2 < -limit and sx3 < -limit)
            or (sy1 > limit and sy2 > limit and sy3 > limit)
            or (sy1 < -limit and sy2 < -limit and sy3 < -limit) then
            clipped_count = 0
        else
            clipped_count = _clip_triangle_square(sx1, sy1, sx2, sy2, sx3, sy3, limit)
        end
    end

    if clipped_count == -1 then
        Gui_triangle(
            gui,
            Vector3((center_x + sx1) * ui_scale, 0, (center_y + sy1) * ui_scale),
            Vector3((center_x + sx2) * ui_scale, 0, (center_y + sy2) * ui_scale),
            Vector3((center_x + sx3) * ui_scale, 0, (center_y + sy3) * ui_scale),
            layer,
            color
        )

        return 1
    end

    if clipped_count < 3 then
        return 0
    end

    local poly_x, poly_y = _poly_ax, _poly_ay
    local base_x = (center_x + poly_x[1]) * ui_scale
    local base_y = (center_y + poly_y[1]) * ui_scale
    local prev_x = (center_x + poly_x[2]) * ui_scale
    local prev_y = (center_y + poly_y[2]) * ui_scale
    local draws = 0

    for v = 3, clipped_count do
        if draws >= budget then
            break
        end

        local cur_x = (center_x + poly_x[v]) * ui_scale
        local cur_y = (center_y + poly_y[v]) * ui_scale

        Gui_triangle(
            gui,
            Vector3(base_x, 0, base_y),
            Vector3(prev_x, 0, prev_y),
            Vector3(cur_x, 0, cur_y),
            layer,
            color
        )
        draws = draws + 1
        prev_x, prev_y = cur_x, cur_y
    end

    return draws
end

local function _select_triangles(geometry, bucket_count, origin_x, origin_y, origin_z, select_range, range_above,
                                 range_below, min_radius_world, max_triangles)
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

            if dz <= range_above and dz >= -range_below and triangle_radius >= min_radius_world then
                local dx = mid_x[i] - origin_x
                local dy = mid_y[i] - origin_y
                local reach = select_range + triangle_radius

                if dx * dx + dy * dy <= reach * reach then
                    if n >= max_triangles then
                        return false
                    end

                    n = n + 1
                    visible[n] = i
                end
            end
        end
    end

    _visible_mode = "triangles"
    _visible_count = n
    _metric_selected = n

    return true
end

local function _select_cells(geometry, bucket_count, origin_z, query_range, range_above, range_below)
    local cell_size = geometry.cell_size
    local cells_side = math_floor(2 * query_range / cell_size) + 1
    local multiple = math_floor((cells_side + LOD_CELL_SIDE - 1) / LOD_CELL_SIDE)

    if multiple < 1 then
        multiple = 1
    end

    local lod_size = cell_size * multiple
    local min_z = origin_z - range_below
    local max_z = origin_z + range_above
    local seen = _cell_seen
    local seen_keys = _cell_seen_keys
    local seen_count = 0
    local mid_z = geometry.mid_z
    local cell_x_out, cell_y_out = _cell_x, _cell_y
    local n = 0
    local scanned = 0

    for bucket_index = 1, bucket_count do
        local bucket = _scratch_buckets[bucket_index]
        local bucket_min_z = bucket.min_z

        if bucket_min_z and bucket_min_z <= max_z and bucket.max_z >= min_z then
            local lod_x = math_floor(bucket.cell_x / multiple)
            local lod_y = math_floor(bucket.cell_y / multiple)
            local key = (lod_x + LOD_KEY_OFFSET) * LOD_KEY_STRIDE + (lod_y + LOD_KEY_OFFSET)

            if not seen[key] then
                local hit = false

                for j = 1, #bucket do
                    scanned = scanned + 1

                    local z = mid_z[bucket[j]]

                    if z >= min_z and z <= max_z then
                        hit = true

                        break
                    end
                end

                if hit then
                    seen[key] = true
                    seen_count = seen_count + 1
                    seen_keys[seen_count] = key
                    n = n + 1
                    cell_x_out[n] = (lod_x + 0.5) * lod_size
                    cell_y_out[n] = (lod_y + 0.5) * lod_size

                    if n >= MAX_LOD_CELLS then
                        break
                    end
                end

                if scanned > SELECTION_MAX_CANDIDATES then
                    break
                end
            end
        end
    end

    for k = 1, seen_count do
        seen[seen_keys[k]] = nil
    end

    _visible_mode = "cells"
    _cell_count = n
    _cell_half = lod_size * 0.5
    _metric_selected = n
end

local function _refresh_selection(geometry, origin_x, origin_y, origin_z, select_range, range_above, range_below,
                                  radar_scale, max_triangles)
    local query_range = select_range + geometry.max_radius
    local bucket_count = mod:get_navmesh_nearby_buckets(origin_x, origin_y, query_range, _scratch_buckets)
    local candidate_total = 0

    for b = 1, bucket_count do
        candidate_total = candidate_total + #_scratch_buckets[b]
    end

    _metric_candidates = candidate_total

    if candidate_total <= SELECTION_MAX_CANDIDATES then
        local min_radius_world = MIN_TRIANGLE_RADIUS_PX / radar_scale

        for _ = 1, LOD_ESCALATION_MAX_ATTEMPTS do
            if _select_triangles(geometry, bucket_count, origin_x, origin_y, origin_z, select_range,
                    range_above, range_below, min_radius_world, max_triangles) then
                _metric_lod_px = min_radius_world * radar_scale

                return
            end

            min_radius_world = min_radius_world * 2
        end
    end

    _metric_lod_px = -1
    _select_cells(geometry, bucket_count, origin_z, query_range, range_above, range_below)
end

local function _selection_current(geometry, t, origin_x, origin_y, origin_z, range, radar_scale, style, range_above,
                                  range_below, triangle_limit)
    if geometry.revision ~= _sel_revision then
        return false
    end

    if style ~= _sel_style or range_above ~= _sel_range_above or range_below ~= _sel_range_below
        or triangle_limit ~= _sel_triangle_limit then
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

        local scale_delta = radar_scale - _sel_scale

        if scale_delta < 0 then
            scale_delta = -scale_delta
        end

        if scale_delta > radar_scale * 0.05 then
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
        "[Radar] navmesh layer | mode=%s cached=%d candidates=%d selected=%d bands(b/c/a)=%d/%d/%d drawn=%d lod_px=%.2f select_ms=%.2f draw_ms=%.2f build_ms=%.2f",
        _visible_mode,
        geometry.count,
        _metric_candidates,
        _metric_selected,
        _metric_band_below,
        _metric_band_current,
        _metric_band_above,
        _metric_drawn,
        _metric_lod_px,
        _metric_selection_ms,
        _metric_draw_ms,
        tonumber(geometry.build_ms) or -1
    ))
end

local function _invalidate_selection()
    _visible_count = 0
    _cell_count = 0
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
    local triangle_limit = _configured_triangle_limit()
    local radar_scale = projection_radius / range
    local debug_mode = mod:get("debug_mode") == true

    if not _selection_current(geometry, t, origin_x, origin_y, origin_z, range, radar_scale, radar_style,
            range_above, range_below, triangle_limit) then
        local selection_start = debug_mode and os_clock and os_clock() or nil

        local select_range = (is_circle and range or range * SQUARE_RANGE_MULT) + SELECTION_RANGE_SLACK

        _refresh_selection(geometry, origin_x, origin_y, origin_z, select_range, range_above, range_below,
            radar_scale, triangle_limit)

        _sel_revision = geometry.revision
        _sel_origin_x = origin_x
        _sel_origin_y = origin_y
        _sel_origin_z = origin_z
        _sel_range = range
        _sel_scale = radar_scale
        _sel_style = radar_style
        _sel_range_above = range_above
        _sel_range_below = range_below
        _sel_triangle_limit = triangle_limit
        _sel_t = t

        if selection_start then
            _metric_selection_ms = (os_clock() - selection_start) * 1000
        end
    end

    local draw_cells = _visible_mode == "cells"

    if (draw_cells and _cell_count == 0) or (not draw_cells and _visible_count == 0) then
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
    local budget = math_floor(triangle_limit * DRAW_BUDGET_HEADROOM) + 64
    local cell_budget_floor = MAX_LOD_CELLS * 2 + 64

    if budget < cell_budget_floor then
        budget = cell_budget_floor
    end

    local drawn = 0
    local clip_and_emit = _clip_and_emit

    if draw_cells then
        local cell_color = color_current or color_below or color_above
        local cell_x_arr, cell_y_arr = _cell_x, _cell_y
        local half = _cell_half

        _metric_band_below = 0
        _metric_band_current = _cell_count
        _metric_band_above = 0

        for k = 1, _cell_count do
            if budget <= 0 then
                break
            end

            local x_min = cell_x_arr[k] - half - origin_x
            local x_max = x_min + half + half
            local y_min = cell_y_arr[k] - half - origin_y
            local y_max = y_min + half + half

            local c1x = (x_min * right_x + y_min * right_y) * radar_scale
            local c1y = -(x_min * forward_x + y_min * forward_y) * radar_scale
            local c2x = (x_max * right_x + y_min * right_y) * radar_scale
            local c2y = -(x_max * forward_x + y_min * forward_y) * radar_scale
            local c3x = (x_max * right_x + y_max * right_y) * radar_scale
            local c3y = -(x_max * forward_x + y_max * forward_y) * radar_scale
            local c4x = (x_min * right_x + y_max * right_y) * radar_scale
            local c4y = -(x_min * forward_x + y_max * forward_y) * radar_scale

            local used = clip_and_emit(gui, layer, cell_color, is_circle, limit, limit_sq, ui_scale, center_x,
                center_y, c1x, c1y, c2x, c2y, c3x, c3y, budget)

            budget = budget - used
            drawn = drawn + used

            if budget > 0 then
                used = clip_and_emit(gui, layer, cell_color, is_circle, limit, limit_sq, ui_scale, center_x,
                    center_y, c1x, c1y, c3x, c3y, c4x, c4y, budget)
                budget = budget - used
                drawn = drawn + used
            end
        end
    else
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
            if budget <= 0 then
                break
            end

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
                    if budget <= 0 then
                        break
                    end

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

                    local used = clip_and_emit(gui, layer, color, is_circle, limit, limit_sq, ui_scale, center_x,
                        center_y, sx1, sy1, sx2, sy2, sx3, sy3, budget)

                    budget = budget - used
                    drawn = drawn + used
                end
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
