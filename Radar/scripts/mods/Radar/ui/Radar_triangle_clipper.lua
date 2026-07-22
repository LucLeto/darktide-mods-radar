local Vector3 = Vector3
local math_abs = math.abs
local math_atan2 = math.atan2
local math_cos = math.cos
local math_floor = math.floor
local math_pi = math.pi
local math_sin = math.sin
local math_sqrt = math.sqrt

local Gui_triangle = Gui and Gui.triangle

local FULL_CIRCLE = math_pi * 2
local CIRCLE_ARC_STEP = 0.26

local _poly_ax, _poly_ay = {}, {}
local _poly_bx, _poly_by = {}, {}

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
                              sx1, sy1, sx2, sy2, sx3, sy3)
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

return _clip_and_emit
