local mod = get_mod("Radar")

-- Radar map-geometry (navmesh) layer.
--
-- Fills the world-space walkable geometry produced by Radar_navmesh.lua beneath the radar
-- markers. Projects onto Radar's own basis so the mesh lines up exactly with marker positions,
-- honours the square/circle/auspex styles with true polygon clipping, and filters out floors
-- above and below the player's current level.
--
-- The fill always covers the complete visible range at every zoom. Exact nav triangles are
-- drawn while they fit the configurable triangle budget; when they would overflow it, the
-- minimum projected-triangle-size threshold escalates (0.5px, 1px, 2px, ...) so the smallest
-- on-screen triangles are dropped first and the large floor geometry stays exact. Only when
-- even that cannot fit the budget (extreme range/density combinations) does the layer fall back
-- to a coarse occupancy fill of the spatial-grid cells, which is bounded regardless of range.
--
-- Per frame only a cached selection is projected; the selection is refreshed on a limited
-- cadence (or immediately when the geometry, range, style or settings change), so camera
-- rotation stays perfectly smooth while selection work is decoupled from the frame rate. All
-- drawing runs behind pcall with a failure cooldown so geometry errors can never interrupt
-- normal radar rendering.

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

-- Fallback band colours (a, r, g, b) used when the "radar_navmesh" colour settings are
-- unavailable. Three floor bands relative to the player's height: the current floor reads
-- brightest, floors below sit dimmer beneath it, floors above are faintest and drawn on top so
-- they veil rather than hide. Each mirrors a configurable ARGB setting.
local NAVMESH_CURRENT_FALLBACK_COLOR = { 80, 101, 133, 96 }
local NAVMESH_BELOW_FALLBACK_COLOR = { 60, 92, 104, 120 }
local NAVMESH_ABOVE_FALLBACK_COLOR = { 34, 120, 145, 175 }

-- Fallbacks for the two floor-range settings (metres above / below the player kept visible).
local NAVMESH_DEFAULT_RANGE_ABOVE = 3
local NAVMESH_DEFAULT_RANGE_BELOW = 7

-- Half-height of the "current floor" band, metres. Triangles within +/- this of the player's
-- height read as the current floor; beyond it they fall into the above / below bands. A floor is
-- roughly this tall, so neighbouring floors separate cleanly. Matches Strikemap's same-floor
-- window.
local NAVMESH_CURRENT_FLOOR_HALF_DZ = 2.5

-- Selection cadence and movement threshold. Between refreshes the cached selection is reused;
-- SELECTION_RANGE_SLACK (world metres) of extra reach guarantees the player cannot out-walk the
-- cache before the next refresh pops geometry at the edge. Range/zoom changes (overview
-- transitions animate these every frame) refresh on their own short cadence instead of per
-- frame.
local SELECTION_MIN_INTERVAL = 0.25
local SELECTION_RANGE_REFRESH_INTERVAL = 0.1
local SELECTION_MOVE_THRESHOLD_SQ = 1.5 * 1.5
local SELECTION_RANGE_SLACK = 4

-- Triangle budget (navmesh_max_triangles setting): how many exact triangles the cached
-- selection may hold. Higher values keep more small detail at higher render cost.
local TRIANGLE_LIMIT_DEFAULT = 6000
local TRIANGLE_LIMIT_MIN = 1000
local TRIANGLE_LIMIT_MAX = 20000

-- Safety limits: ceiling of candidate triangles a refresh may examine (beyond it the coarse
-- fill is used directly) and the headroom multiplier for clip-fan draw calls per frame.
local SELECTION_MAX_CANDIDATES = 60000
local DRAW_BUDGET_HEADROOM = 1.25

-- Cell-fill sizing: the aggregation multiple of the base bucket size is chosen so the covered
-- range spans at most ~LOD_CELL_SIDE cells per axis, bounding the cell count independently of
-- the radar range (the cap has rounding headroom for the query's boundary cells).
local LOD_CELL_SIDE = 32
local MAX_LOD_CELLS = (LOD_CELL_SIDE + 4) * (LOD_CELL_SIDE + 4)

-- Packing for the cell-fill dedupe keys (cell coordinates can be negative).
local LOD_KEY_OFFSET = 65536
local LOD_KEY_STRIDE = 131072

-- Base skip threshold: triangles whose projected bounding radius falls below this many screen
-- pixels only produce sub-pixel alpha speckle. When the triangle budget would overflow, this
-- threshold is doubled per attempt (dropping the smallest on-screen triangles first) before the
-- coarse cell fill is ever considered.
local MIN_TRIANGLE_RADIUS_PX = 0.5
local LOD_ESCALATION_MAX_ATTEMPTS = 5

-- World-space reach of the square/auspex corners relative to the radar range (sqrt(2)).
local SQUARE_RANGE_MULT = 1.4143

-- Arc subdivision step for circle clipping, radians (~15 degrees; <1% radius chord error).
local CIRCLE_ARC_STEP = 0.26

-- After a draw error the layer stays off this many seconds before retrying.
local DRAW_FAILURE_COOLDOWN = 5

-- Cadence of the debug-mode performance log.
local METRICS_LOG_INTERVAL = 5

-- Cached selection: either triangle indices into the shared geometry buffer or world-space cell
-- centres for the coarse fill, plus the state the selection was built for.
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

-- Scratch buffers, reused every call: bucket query output, the polygon clip ping-pong pair, the
-- cell dedupe map (cleared via its key list, never reallocated) and the per-band index lists the
-- draw pass bins the cached selection into so floors paint in below -> current -> above order.
local _scratch_buckets = {}
local _poly_ax, _poly_ay = {}, {}
local _poly_bx, _poly_by = {}, {}
local _cell_seen = {}
local _cell_seen_keys = {}
local _below_idx, _current_idx, _above_idx = {}, {}, {}

-- Failure isolation and development metrics.
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

-- Unit-length flattened forward (x, y) of a rotation. Mirrors Radar's _safe_forward_xy exactly
-- (normalized, so pitch does not scale the basis) so the mesh shares the marker projection.
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

-- Configured (a, r, g, b) for one floor band. Returns the cached table from the shared colour
-- system (reused across frames; safe to hold within a single draw) or the fallback.
local function _band_widget_color(prefix, fallback)
    local get_radar_color = mod.get_radar_color

    return get_radar_color and get_radar_color(mod, prefix, fallback) or fallback
end

-- True when any of the three floor bands has a non-zero opacity, i.e. the layer would draw
-- something. Opacity 0 on every band (or the master toggle off) skips all geometry work.
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

-- Metres above and below the player's height kept visible. Above and below are separate settings
-- so the readable window can be asymmetric (you usually care more about the floor beneath you).
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

-- Sutherland-Hodgman clip of a convex polygon against the half-plane a*x + b*y <= limit.
-- Reads in_x/in_y[1..in_count], writes out_x/out_y and returns the output vertex count.
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

-- Clip a triangle against the axis-aligned square [-limit, limit]^2 (radar-space, includes the
-- square's corners). Result polygon lands in _poly_ax/_poly_ay; returns its vertex count.
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

-- Intersection parameters (sorted) of the segment P->Q with the circle of the given squared
-- radius centred on the origin, or nil when the supporting line misses the circle.
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

-- Append intermediate points along the circle between two boundary intersections, following the
-- polygon winding (positive = increasing angle). Endpoints themselves are already appended.
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

-- Clip a triangle against the circle of the given radius centred on the radar origin. The exact
-- intersection is convex; boundary arcs are approximated by short chords. Handles triangles with
-- all three vertices outside whose edges still cross the circle, and triangles that contain the
-- whole circle. Result polygon lands in _poly_ax/_poly_ay; returns its vertex count.
local function _clip_triangle_circle(x1, y1, x2, y2, x3, y3, radius)
    local radius_sq = radius * radius
    local winding = (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1)
    local out_x, out_y = _poly_ax, _poly_ay
    local bx, by = _poly_bx, _poly_by

    -- vertex scratch (reuses the second ping-pong buffer)
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
                    -- leaving the circle: the exit is the larger root
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
                    -- entering the circle: the entry is the smaller root
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
            -- both endpoints outside: the edge may still cut a chord through the circle
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
        -- close the wrap-around arc between the last exit and the first entry
        out_count = _append_arc(out_x, out_y, out_count, pending_exit_angle, first_entry_angle, winding, radius)
    end

    if out_count == 0 and _point_in_triangle(0, 0, x1, y1, x2, y2, x3, y3) then
        -- the triangle surrounds the whole radar circle: emit the full disc
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

-- Clip one radar-space triangle to the active style bounds and emit the resulting fan, spending
-- at most `budget` engine calls. Returns the number of Gui.triangle calls issued.
local function _clip_and_emit(gui, layer, color, is_circle, limit, limit_sq, ui_scale, center_x, center_y,
                              sx1, sy1, sx2, sy2, sx3, sy3, budget)
    local clipped_count

    if is_circle then
        if sx1 * sx1 + sy1 * sy1 <= limit_sq
            and sx2 * sx2 + sy2 * sy2 <= limit_sq
            and sx3 * sx3 + sy3 * sy3 <= limit_sq then
            clipped_count = -1 -- fully inside: draw directly
        else
            clipped_count = _clip_triangle_circle(sx1, sy1, sx2, sy2, sx3, sy3, limit)
        end
    else
        local inside1 = sx1 >= -limit and sx1 <= limit and sy1 >= -limit and sy1 <= limit
        local inside2 = sx2 >= -limit and sx2 <= limit and sy2 >= -limit and sy2 <= limit
        local inside3 = sx3 >= -limit and sx3 <= limit and sy3 >= -limit and sy3 <= limit

        if inside1 and inside2 and inside3 then
            clipped_count = -1 -- fully inside: draw directly
        elseif (sx1 > limit and sx2 > limit and sx3 > limit)
            or (sx1 < -limit and sx2 < -limit and sx3 < -limit)
            or (sy1 > limit and sy2 > limit and sy3 > limit)
            or (sy1 < -limit and sy2 < -limit and sy3 < -limit) then
            clipped_count = 0 -- trivially outside
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

    -- fan-triangulate the convex clip polygon
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

-- Triangle-mode selection: exact nav triangles from the queried buckets, with the asymmetric
-- height filter (range_above above / range_below below the player), the horizontal range cull
-- (including each triangle's bounding radius, so triangles whose centroid is outside but that
-- still poke into view are kept) and the minimum projected size skip. Returns false as soon as
-- the triangle budget would overflow, in which case the caller retries with a larger size
-- threshold instead of truncating the fill jaggedly.
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

-- Cell-mode selection: one entry per occupied spatial cell (aggregated so at most
-- ~LOD_CELL_SIDE cells span the covered range). A cell qualifies when at least one of its
-- triangles lies within the vertical window (range_above above / range_below below the player);
-- the per-bucket z bounds reject wrong floors before any triangle is touched.
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

-- Refresh the cached selection: query the ring-ordered buckets once, then fill the triangle
-- budget, escalating the minimum projected-size threshold (dropping the smallest on-screen
-- triangles first) whenever the budget would overflow. The coarse cell fill is a last resort
-- for candidate counts no threshold escalation can handle, so the fill always reaches the
-- radar's full visible range.
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

-- True while the cached selection still matches the current geometry, settings and (within the
-- refresh cadence and movement threshold) player position.
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
        -- gameplay clock restarted
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

-- Actual layer implementation; runs behind pcall from RadarNavmesh.draw.
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

        -- The square's corners reach past the range in world units; select far enough to fill
        -- them, plus slack so movement between refreshes cannot pop geometry at the edge.
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

    -- Floor-band colours. All three share the single navmesh layer and are painted in
    -- below -> current -> above submission order, so lower floors sit under the current floor
    -- and the floor above veils it -- the "above -> current -> below" fade. Transparent bands
    -- (opacity 0) become nil and are skipped entirely.
    local cur = _band_widget_color("radar_navmesh", NAVMESH_CURRENT_FALLBACK_COLOR)
    local below = _band_widget_color("radar_navmesh_below", NAVMESH_BELOW_FALLBACK_COLOR)
    local above = _band_widget_color("radar_navmesh_above", NAVMESH_ABOVE_FALLBACK_COLOR)
    local color_current = (cur[1] or 0) > 0 and Color(cur[1], cur[2] or 255, cur[3] or 255, cur[4] or 255) or nil
    local color_below = (below[1] or 0) > 0 and Color(below[1], below[2] or 255, below[3] or 255, below[4] or 255)
        or nil
    local color_above = (above[1] or 0) > 0 and Color(above[1], above[2] or 255, above[3] or 255, above[4] or 255)
        or nil

    -- Radar basis, identical to project_target_to_radar: right vector derived from the (already
    -- normalized) flattened forward, world->radar scale = radius / range.
    local right_x = forward_y
    local right_y = -forward_x

    local limit = projection_radius
    local limit_sq = limit * limit
    -- headroom over the triangle budget for the extra fans produced by boundary clipping; never
    -- below what a full cell fill needs (two triangles per cell), so a low triangle setting
    -- cannot truncate the coarse mode
    local budget = math_floor(triangle_limit * DRAW_BUDGET_HEADROOM) + 64
    local cell_budget_floor = MAX_LOD_CELLS * 2 + 64

    if budget < cell_budget_floor then
        budget = cell_budget_floor
    end

    local drawn = 0
    local clip_and_emit = _clip_and_emit

    if draw_cells then
        -- Coarse fill: each occupied cell is a world-aligned square, projected as two triangles
        -- through the same clipping as exact geometry. Adjacent cells share edges exactly, so
        -- the fill is crack-free and reaches the radar's rim at any range. A cell aggregates
        -- several floors, so floor banding is not meaningful here; it uses the current-floor
        -- colour (falling back to whichever band is visible).
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

        -- Bin the cached selection by height relative to the player. Selection already clamped
        -- every triangle into [-range_below, +range_above], so a simple centre test around the
        -- current-floor window classifies each triangle without another range check.
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

        -- Paint below, then current, then above so nearer-the-camera floors overdraw correctly.
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

-- True when the geometry layer should do any work at all: selected as the map-geometry source
-- ("live" always; "auto" only while the Strikemap layer is not drawing, which `suppressed`
-- reports) and not fully transparent. Opacity 0 skips selection, projection and drawing
-- entirely. On the frame the layer turns off the cached mission geometry is released; it is
-- rebuilt lazily when re-enabled, so an "auto" user parked on Strikemap pays no navmesh cost.
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

-- Draw the map-geometry layer. Every parameter is one that _draw_internal already computed for
-- this frame, so the mesh shares the marker projection basis (player position + facing), radius,
-- range and centre exactly. Errors are contained here: a failure pauses only this layer for
-- DRAW_FAILURE_COOLDOWN seconds and never interrupts marker rendering.
function RadarNavmesh.draw(ui_renderer, t, player_pos, rotation, center_x, center_y, projection_radius, range, z)
    if not Gui_triangle or not ui_renderer then
        return
    end

    t = tonumber(t) or 0

    if t < _last_draw_t then
        -- gameplay clock restarted (new mission): drop the failure backoff and cached selection
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
