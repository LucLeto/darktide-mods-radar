--- Draws the live navmesh geometry as the radar's map layer, shaded in height bands.
-- Selects the cached navmesh triangles around the player from the spatial buckets built by
-- `Radar_navmesh.lua`, projects them onto the same camera-aligned basis as the radar
-- markers and submits them through `Radar_triangle_clipper.lua`. A selection reaches past the
-- radar shape, so a triangle that cannot touch the shape is dropped before it is projected.
-- The others are binned into below, current and above floor bands, drawn in that order with
-- their own configurable colours, so lower floors sit under the current floor and the floor
-- above veils it.
--
-- Explicit module loaded by `ui/Radar_hud_element.lua` through `mod:io_dofile`; the chunk
-- returns `RadarNavmesh`. The geometry itself comes from `mod:ensure_navmesh_geometry`
-- and `mod:get_navmesh_nearby_buckets`. The visible set is cached and only rebuilt when
-- the player moves, the Radar player changes, the range or style changes or the geometry is
-- rebuilt, and a failing draw pauses the layer for a few seconds instead of interrupting the
-- marker draw. While debug logs are on, the live floor probe logs on every zoom where the nearby
-- targets sit against the floor, through the marker projection and through this layer's own.
-- module: Radar_navmesh_renderer
-- alias: RadarNavmesh
-- author: dreams
-- author: LucLeto
local mod = get_mod("Radar")
local _clip_and_emit = mod:io_dofile("Radar/scripts/mods/Radar/ui/Radar_triangle_clipper")

local Color = Color
local Quaternion = Quaternion
local pcall = pcall
local tonumber = tonumber
local tostring = tostring
local type = type
local math_floor = math.floor
local math_huge = math.huge
local math_max = math.max
local math_min = math.min
local math_sqrt = math.sqrt
local string_format = string.format
local string_sub = string.sub
local os_clock = os and os.clock or nil
local Gui_triangle = Gui and Gui.triangle
local Quaternion_forward = Quaternion and Quaternion.forward

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

--- Band colours used until the colour runtime is available, and the default floor ranges in metres.
-- Overview mode shows every floor within `NAVMESH_OVERVIEW_RANGE` instead of the configured ranges.
local NAVMESH_CURRENT_FALLBACK_COLOR = { 80, 101, 133, 96 }
local NAVMESH_BELOW_FALLBACK_COLOR = { 55, 120, 98, 76 }
local NAVMESH_ABOVE_FALLBACK_COLOR = { 32, 120, 150, 185 }
local NAVMESH_DEFAULT_RANGE_ABOVE = 7
local NAVMESH_DEFAULT_RANGE_BELOW = 7
local NAVMESH_OVERVIEW_RANGE = 30
--- Half height in metres of the current floor band around the player.
local NAVMESH_CURRENT_FLOOR_HALF_DZ = 2.5
--- Visible set refresh rules.
-- A movement beyond `SELECTION_MOVE_THRESHOLD_SQ` is checked at most every
-- `SELECTION_MIN_INTERVAL` seconds and a range change of more than 2% at most every
-- `SELECTION_RANGE_REFRESH_INTERVAL` seconds. A larger range on the normal radar selects at once,
-- so zooming out never leaves the new outer ring empty; the overview's animated zoom keeps the
-- interval. The selection radius gets `SELECTION_RANGE_SLACK` metres of slack and, for square
-- radars, `SQUARE_RANGE_MULT` (the square's diagonal) so the corners stay filled between refreshes.
local SELECTION_MIN_INTERVAL = 0.25
local SELECTION_RANGE_REFRESH_INTERVAL = 0.1
local SELECTION_MOVE_THRESHOLD_SQ = 1.5 * 1.5
local SELECTION_RANGE_SLACK = 4
local SQUARE_RANGE_MULT = 1.4143
--- Seconds the layer stays paused after a draw error, and between debug metric log lines.
local DRAW_FAILURE_COOLDOWN = 5
local METRICS_LOG_INTERVAL = 5
--- Live floor probe, logged only in debug mode.
-- A new range, projection radius or radar style is logged on its first draw and again once it has
-- held for `PROBE_SETTLE_DELAY` seconds. Each log covers the targets within `PROBE_TARGET_RANGE`
-- metres, every other kind before enemies and then the nearest first, at most `PROBE_MAX_TARGETS`.
-- A triangle is under a target when its plane there lies from `PROBE_FLOOR_BELOW` metres below to
-- `PROBE_FLOOR_ABOVE` metres above the target.
local PROBE_SETTLE_DELAY = 0.5
local PROBE_TARGET_RANGE = 4
local PROBE_MAX_TARGETS = 6
local PROBE_FLOOR_BELOW = 3
local PROBE_FLOOR_ABOVE = 0.5

-- ----------------------------------------------------------------------------
-- Mutable state
-- ----------------------------------------------------------------------------

--- Cached visible set (triangle indices into the geometry buffers) and the inputs it was selected for.
local _visible = {}
local _visible_count = 0
local _sel_revision = -1
local _sel_origin_revision = nil
local _sel_origin_x = math_huge
local _sel_origin_y = math_huge
local _sel_origin_z = math_huge
local _sel_range = -1
local _sel_style = nil
local _sel_range_above = -1
local _sel_range_below = -1
local _sel_t = -math_huge
--- Scratch buffers reused every frame for the bucket query and the per-band triangle indices.
local _scratch_buckets = {}
local _below_idx, _current_idx, _above_idx = {}, {}, {}
--- Draw timing and failure state; a gameplay time lower than the last draw means a new session.
local _last_draw_t = -math_huge
local _failed_until_t = -math_huge
local _last_failure_message = nil
--- Debug metrics of the last selection and draw, logged periodically in debug mode.
local _metric_candidates = 0
local _metric_selected = 0
local _metric_selection_ms = 0
local _metric_drawn = 0
local _metric_draw_ms = 0
local _metric_band_below = 0
local _metric_band_current = 0
local _metric_band_above = 0
local _next_metrics_log_t = 0
--- Whether the layer was active on the previous `RadarNavmesh.is_active` call.
local _was_active = false
--- Live floor probe state; the draw key last seen, when it last changed, the range before the
-- change and whether the settled log is still due.
local _probe_range = nil
local _probe_radius = nil
local _probe_style = nil
local _probe_changed_t = nil
local _probe_from_range = nil
local _probe_settle_due = false
local _probe_last_failure = nil
--- Scratch lists of the probe, for its bucket query and for the targets it reports and their order.
local _probe_buckets = {}
local _probe_targets = {}
local _probe_ranks = {}

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

local function _is_finite(v)
    return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
end

--- Returns the normalised horizontal forward direction of a rotation.
-- ?Quaternion: rotation camera rotation
-- treturn: ?number forward x, or nil when the rotation is missing, invalid or vertical
-- treturn: ?number forward y
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

--- Returns the effective radar style, `square`, `circle` or `auspex`.
-- Auspex radars are clipped like square ones.
-- treturn: string
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

--- Returns the configured ARGB colour of a floor band, or the fallback before the colour runtime exists.
-- string: prefix band colour setting prefix
-- tab: fallback widget colour array
-- treturn: tab widget colour array
local function _band_widget_color(prefix, fallback)
    local get_radar_color = mod.get_radar_color

    return get_radar_color and get_radar_color(mod, prefix, fallback) or fallback
end

--- Returns whether at least one floor band has a non-zero alpha, so there is anything to draw.
-- treturn: bool
local function _any_band_visible()
    local current = _band_widget_color("radar_navmesh", NAVMESH_CURRENT_FALLBACK_COLOR)
    local below = _band_widget_color("radar_navmesh_below", NAVMESH_BELOW_FALLBACK_COLOR)
    local above = _band_widget_color("radar_navmesh_above", NAVMESH_ABOVE_FALLBACK_COLOR)

    return (current[1] or 0) > 0 or (below[1] or 0) > 0 or (above[1] or 0) > 0
end

--- Clamps a configured floor range to 1 to 30 metres, the range of its settings slider.
-- The Strikemap geometry layer clamps the same settings the same way.
-- param: value setting value
-- number: fallback value used when the setting is not a number
-- treturn: number
local function _clamp_range(value, fallback)
    value = tonumber(value) or fallback

    if value < 1 then
        value = 1
    elseif value > 30 then
        value = 30
    end

    return value
end

--- Returns how far above and below the player floors are drawn.
-- treturn: number range above in metres
-- treturn: number range below in metres
local function _configured_ranges()
    if mod:is_overview_mode_active() then
        return NAVMESH_OVERVIEW_RANGE, NAVMESH_OVERVIEW_RANGE
    end

    return _clamp_range(mod:get("navmesh_range_above"), NAVMESH_DEFAULT_RANGE_ABOVE),
        _clamp_range(mod:get("navmesh_range_below"), NAVMESH_DEFAULT_RANGE_BELOW)
end

--- Fills the visible set from the queried buckets.
-- A triangle is kept when its centre lies within the floor range and its bounding circle
-- reaches into the selection radius.
-- tab: geometry navmesh geometry buffers
-- int: bucket_count number of buckets in `_scratch_buckets`
-- number: origin_x player x
-- number: origin_y player y
-- number: origin_z player z
-- number: select_range horizontal selection radius in metres
-- number: range_above floor range above the player
-- number: range_below floor range below the player
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

--- Rebuilds the visible set around the player.
-- Queries the buckets within the selection radius widened by the largest triangle radius, so
-- a large triangle centred just outside the radius is still found.
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

--- Returns whether the cached visible set can still be used for this frame.
-- treturn: bool false when the geometry, the Radar player, style or floor ranges changed, time
--   went backwards, the normal radar zoomed out, or a refresh interval elapsed with the range or
--   player position changed enough
local function _selection_current(geometry, t, origin_x, origin_y, origin_z, range, style, range_above, range_below,
                                  origin_revision)
    if geometry.revision ~= _sel_revision then
        return false
    end

    if style ~= _sel_style or range_above ~= _sel_range_above or range_below ~= _sel_range_below
        or origin_revision ~= _sel_origin_revision then
        return false
    end

    if t < _sel_t then
        return false
    end

    if range > _sel_range and not mod:is_overview_mode_active() then
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

--- Logs the selection and draw metrics at most every `METRICS_LOG_INTERVAL` seconds in debug mode.
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

--- Drops the cached visible set so the next draw selects again.
local function _invalidate_selection()
    _visible_count = 0
    _sel_revision = -1
end

-- ----------------------------------------------------------------------------
-- Live floor probe
-- ----------------------------------------------------------------------------

--- Forgets the probe's draw key, so the next draw logs from the start again.
local function _reset_probe()
    _probe_range = nil
    _probe_radius = nil
    _probe_style = nil
    _probe_changed_t = nil
    _probe_from_range = nil
    _probe_settle_due = false
end

--- Returns which probe log is due in this draw, if any.
-- The first draw logs `start`. A new range, projection radius or radar style logs `zoom` on its
-- first draw, unless an earlier change is still settling, and `settled` is logged once the latest
-- of them has held for `PROBE_SETTLE_DELAY` seconds.
-- number: t gameplay time
-- number: range radar range in metres
-- number: projection_radius radar radius in unscaled UI pixels
-- string: radar_style effective radar style
-- treturn: ?string `start`, `zoom`, `settled` or nil
local function _probe_phase(t, range, projection_radius, radar_style)
    if range ~= _probe_range or projection_radius ~= _probe_radius or radar_style ~= _probe_style then
        local phase = nil

        if _probe_range == nil then
            phase = "start"
            _probe_from_range = nil
            _probe_settle_due = false
        elseif not _probe_settle_due then
            phase = "zoom"
            _probe_from_range = _probe_range
            _probe_settle_due = true
        end

        _probe_range = range
        _probe_radius = projection_radius
        _probe_style = radar_style
        _probe_changed_t = t

        return phase
    end

    if _probe_settle_due and t - _probe_changed_t >= PROBE_SETTLE_DELAY then
        _probe_settle_due = false

        return "settled"
    end

    return nil
end

--- Returns the weights of a point against a triangle's corners, seen from above.
-- All three are at least zero when the point lies inside or on the edge of the triangle.
-- treturn: ?number weight of the first corner, nil for a triangle without area
-- treturn: ?number weight of the second corner
-- treturn: ?number weight of the third corner
local function _probe_weights(px, py, x1, y1, x2, y2, x3, y3)
    local det = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)

    if det == 0 then
        return nil, nil, nil
    end

    local w1 = ((y2 - y3) * (px - x3) + (x3 - x2) * (py - y3)) / det
    local w2 = ((y3 - y1) * (px - x3) + (x1 - x3) * (py - y3)) / det

    return w1, w2, 1 - w1 - w2
end

--- Returns the horizontal distance from a point to a segment.
-- treturn: number
local function _probe_segment_distance(px, py, x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local length_sq = dx * dx + dy * dy
    local f = 0

    if length_sq > 0 then
        f = ((px - x1) * dx + (py - y1) * dy) / length_sq

        if f < 0 then
            f = 0
        elseif f > 1 then
            f = 1
        end
    end

    local ex = x1 + dx * f - px
    local ey = y1 + dy * f - py

    return math_sqrt(ex * ex + ey * ey)
end

--- Finds the navmesh triangle a target stands on, or the nearest one at its height.
-- Searches the whole geometry around the point, not only the visible set. A triangle is under the
-- target when its plane there lies from `PROBE_FLOOR_BELOW` metres below to `PROBE_FLOOR_ABOVE`
-- metres above the target, and the one closest in height wins. Without one, the nearest triangle
-- whose height span reaches into that window is returned.
-- tab: geometry navmesh geometry buffers
-- number: x target x
-- number: y target y
-- number: z target z
-- treturn: ?int triangle index, nil when no triangle is near
-- treturn: bool whether the triangle lies under the target
-- treturn: number plane height under the target, or the triangle's centre height beside it
-- treturn: number horizontal distance from the target to the triangle in metres, 0 under it
-- treturn: int number of triangles at any height under the target
local function _probe_floor_at(geometry, x, y, z)
    local bucket_count = mod:get_navmesh_nearby_buckets(x, y, geometry.max_radius, _probe_buckets)
    local ax, ay, az = geometry.ax, geometry.ay, geometry.az
    local bx, by, bz = geometry.bx, geometry.by, geometry.bz
    local cx, cy, cz = geometry.cx, geometry.cy, geometry.cz
    local low = z - PROBE_FLOOR_BELOW
    local high = z + PROBE_FLOOR_ABOVE
    local stack = 0
    local under_index, under_z, under_dz = nil, 0, math_huge
    local near_index, near_distance = nil, math_huge

    for b = 1, bucket_count do
        local bucket = _probe_buckets[b]

        for j = 1, #bucket do
            local i = bucket[j]
            local x1, y1, x2, y2, x3, y3 = ax[i], ay[i], bx[i], by[i], cx[i], cy[i]
            local w1, w2, w3 = _probe_weights(x, y, x1, y1, x2, y2, x3, y3)

            if w1 and w1 >= -1e-9 and w2 >= -1e-9 and w3 >= -1e-9 then
                local plane_z = w1 * az[i] + w2 * bz[i] + w3 * cz[i]
                local dz = plane_z - z

                stack = stack + 1

                if dz < 0 then
                    dz = -dz
                end

                if plane_z >= low and plane_z <= high and dz < under_dz then
                    under_index, under_z, under_dz = i, plane_z, dz
                end
            elseif math_min(az[i], bz[i], cz[i]) <= high and math_max(az[i], bz[i], cz[i]) >= low then
                local distance = math_min(
                    _probe_segment_distance(x, y, x1, y1, x2, y2),
                    _probe_segment_distance(x, y, x2, y2, x3, y3),
                    _probe_segment_distance(x, y, x3, y3, x1, y1)
                )

                if distance < near_distance then
                    near_index, near_distance = i, distance
                end
            end
        end
    end

    if under_index then
        return under_index, true, under_z, 0, stack
    end

    if near_index then
        return near_index, false, geometry.mid_z[near_index], near_distance, stack
    end

    return nil, false, 0, 0, stack
end

--- Returns what the last draw did with one triangle.
-- tab: geometry navmesh geometry buffers
-- int: i triangle index
-- number: origin_x player x
-- number: origin_y player y
-- number: origin_z player z
-- number: forward_x x of the radar's forward direction
-- number: forward_y y of the radar's forward direction
-- number: range radar range in metres
-- bool: is_circle whether the radar is a circle
-- treturn: bool whether the triangle is in the visible set
-- treturn: bool whether its centre lies in the floor window of the visible set
-- treturn: bool whether its bounding circle reaches into the radar shape
-- treturn: string its floor band, `below`, `current` or `above`
-- treturn: bool whether that band is drawn, which its colour's alpha decides
local function _probe_triangle_status(geometry, i, origin_x, origin_y, origin_z, forward_x, forward_y, range, is_circle)
    local selected = false

    for k = 1, _visible_count do
        if _visible[k] == i then
            selected = true

            break
        end
    end

    local mid_z = geometry.mid_z[i]
    local selection_dz = mid_z - _sel_origin_z
    local in_window = selection_dz <= _sel_range_above and selection_dz >= -_sel_range_below
    local dx = geometry.mid_x[i] - origin_x
    local dy = geometry.mid_y[i] - origin_y
    local reach = range + geometry.radius[i]
    local in_shape

    if is_circle then
        in_shape = dx * dx + dy * dy <= reach * reach
    else
        local along_right = dx * forward_y - dy * forward_x
        local along_forward = dx * forward_x + dy * forward_y

        in_shape = along_right <= reach and along_right >= -reach
            and along_forward <= reach and along_forward >= -reach
    end

    local dz = mid_z - origin_z
    local band, color

    if dz > NAVMESH_CURRENT_FLOOR_HALF_DZ then
        band, color = "above", _band_widget_color("radar_navmesh_above", NAVMESH_ABOVE_FALLBACK_COLOR)
    elseif dz < -NAVMESH_CURRENT_FLOOR_HALF_DZ then
        band, color = "below", _band_widget_color("radar_navmesh_below", NAVMESH_BELOW_FALLBACK_COLOR)
    else
        band, color = "current", _band_widget_color("radar_navmesh", NAVMESH_CURRENT_FALLBACK_COLOR)
    end

    return selected, in_window, in_shape, band, (color[1] or 0) > 0
end

--- Returns how far a unit's node lies from a target's tracked position, in metres.
-- param: unit unit handle
-- ?string: node_name node to read, the unit's root when nil
-- tab: position tracked position
-- treturn: ?string `x,y,z` offset, nil when the unit has no such node or it cannot be read
local function _probe_unit_offset(unit, node_name, position)
    local unit_api = Unit

    if not unit_api then
        return nil
    end

    local node_index = 1

    if node_name then
        local ok_has_node, has_node = pcall(unit_api.has_node, unit, node_name)

        if not ok_has_node or not has_node then
            return nil
        end

        local ok_node, index = pcall(unit_api.node, unit, node_name)

        if not ok_node or index == nil then
            return nil
        end

        node_index = index
    end

    local ok, world = pcall(unit_api.world_position, unit, node_index)

    if not ok or not world then
        return nil
    end

    return string_format("%.2f,%.2f,%.2f", world.x - position.x, world.y - position.y, world.z - position.z)
end

--- Writes the probe for one draw; run inside `pcall` by `_run_probe`.
-- One line describes the draw and the visible set. Then one line per nearby target from the
-- radar snapshot gives where the marker projection and this layer's projection put it, the
-- distance between the two, how its tracked position sits against its unit, and the triangle under
-- it or the nearest one at its height, with what the draw did with that triangle.
-- string: phase `start`, `zoom` or `settled`
-- tab: geometry navmesh geometry buffers
-- number: t gameplay time
-- tab: ui_renderer active UI renderer
-- !Vector3: player_pos player position
-- !Quaternion: rotation camera rotation the radar is aligned to
-- number: center_x radar centre x in unscaled UI pixels
-- number: center_y radar centre y in unscaled UI pixels
-- number: projection_radius radar radius in unscaled UI pixels
-- number: range radar range in metres
-- ?number: origin_revision Radar player revision of `player_pos`
-- bool: refreshed whether this draw selected the visible set
-- string: radar_style effective radar style
-- bool: is_circle whether the radar is a circle
-- number: range_above floor range above the player
-- number: range_below floor range below the player
-- number: forward_x x of the radar's forward direction
-- number: forward_y y of the radar's forward direction
-- number: right_x x of the scaled right axis the triangles were projected with
-- number: right_y y of that axis
-- number: down_x x of the scaled down axis the triangles were projected with
-- number: down_y y of that axis
-- int: below_n triangles binned into the band below
-- int: current_n triangles binned into the current band
-- int: above_n triangles binned into the band above
local function _log_probe(phase, geometry, t, ui_renderer, player_pos, rotation, center_x, center_y, projection_radius,
                          range, origin_revision, refreshed, radar_style, is_circle, range_above, range_below,
                          forward_x, forward_y, right_x, right_y, down_x, down_y, below_n, current_n, above_n)
    local origin_x = player_pos.x
    local origin_y = player_pos.y
    local origin_z = player_pos.z
    local selection_radius = (_sel_style == "circle" and _sel_range or _sel_range * SQUARE_RANGE_MULT)
        + SELECTION_RANGE_SLACK

    mod:info(string_format(
        "[Radar] live floor probe | phase=%s range=%.2f from=%s radius_px=%.1f px_per_m=%.3f ui_scale=%.3f style=%s overview=%s floors=+%.1f/-%.1f origin=%.2f,%.2f,%.2f forward=%.4f,%.4f player_revision=%s geometry_revision=%s triangles=%d selected_now=%s selection_age_ms=%.0f selection_range=%.2f selection_radius=%.2f selection_origin=%.2f,%.2f,%.2f visible=%d bands(b/c/a)=%d/%d/%d",
        phase,
        range,
        _probe_from_range and string_format("%.2f", _probe_from_range) or "-",
        projection_radius,
        projection_radius / range,
        tonumber(ui_renderer.scale) or 1,
        radar_style,
        tostring(mod:is_overview_mode_active() == true),
        range_above,
        range_below,
        origin_x,
        origin_y,
        origin_z,
        forward_x,
        forward_y,
        tostring(origin_revision),
        tostring(geometry.revision),
        geometry.count,
        tostring(refreshed),
        (t - _sel_t) * 1000,
        _sel_range,
        selection_radius,
        _sel_origin_x,
        _sel_origin_y,
        _sel_origin_z,
        _visible_count,
        below_n,
        current_n,
        above_n
    ))

    local snapshot = mod.get_radar_snapshot and mod:get_radar_snapshot() or nil
    local targets = snapshot and snapshot.targets

    if type(targets) ~= "table" then
        return
    end

    local listed = _probe_targets
    local ranks = _probe_ranks
    local listed_n = 0
    local max_distance_sq = PROBE_TARGET_RANGE * PROBE_TARGET_RANGE

    for k = 1, #targets do
        local target = targets[k]
        local position = target and target.position

        if position then
            local dx = position.x - origin_x
            local dy = position.y - origin_y
            local rank = dx * dx + dy * dy

            if rank <= max_distance_sq then
                local kind = target.kind

                if type(kind) == "string" and string_sub(kind, 1, 6) == "enemy_" then
                    rank = rank + max_distance_sq + 1
                end

                local slot = listed_n + 1

                while slot > 1 and ranks[slot - 1] > rank do
                    listed[slot] = listed[slot - 1]
                    ranks[slot] = ranks[slot - 1]
                    slot = slot - 1
                end

                listed[slot] = target
                ranks[slot] = rank
                listed_n = listed_n + 1
            end
        end
    end

    local project_target_to_radar = mod.project_target_to_radar
    local marker_forward_x, marker_forward_y = nil, nil

    if mod.radar_projection_forward then
        marker_forward_x, marker_forward_y = mod:radar_projection_forward(rotation)
    end

    local alive = ALIVE
    local az, bz, cz = geometry.az, geometry.bz, geometry.cz

    for k = 1, math_min(listed_n, PROBE_MAX_TARGETS) do
        local target = listed[k]
        local position = target.position
        local target_x = position.x
        local target_y = position.y
        local target_z = position.z
        local dx = target_x - origin_x
        local dy = target_y - origin_y
        local floor_x = dx * right_x + dy * right_y
        local floor_y = dx * down_x + dy * down_y
        local marker_text = "off"

        if project_target_to_radar then
            local px, py = project_target_to_radar(mod, player_pos, marker_forward_x, marker_forward_y, position,
                projection_radius, range, target.ignore_radar_range)

            if px and py then
                local ex = px - floor_x
                local ey = py - floor_y

                marker_text = string_format("%.2f,%.2f snapped=%d,%d delta=%.4f", center_x + px, center_y + py,
                    math_floor(center_x + px + 0.5), math_floor(center_y + py + 0.5), math_sqrt(ex * ex + ey * ey))
            end
        end

        local unit = target.unit
        local anchor_text = "root=- node=-"

        if unit ~= nil and alive and alive[unit] then
            anchor_text = string_format("root=%s node=%s", _probe_unit_offset(unit, nil, position) or "-",
                _probe_unit_offset(unit, "ui_interaction_marker", position) or "-")
        end

        local index, under, floor_z, distance, stack = _probe_floor_at(geometry, target_x, target_y, target_z)
        local floor_text

        if index then
            local selected, in_window, in_shape, band, band_drawn = _probe_triangle_status(geometry, index,
                origin_x, origin_y, origin_z, forward_x, forward_y, range, is_circle)

            floor_text = string_format(
                "under=%s tri=%d floor_dz=%.2f dist_m=%.2f stack=%d span=%.2f..%.2f selected=%s window=%s shape=%s band=%s drawn=%s",
                under and "inside" or "outside",
                index,
                floor_z - target_z,
                distance,
                stack,
                math_min(az[index], bz[index], cz[index]) - origin_z,
                math_max(az[index], bz[index], cz[index]) - origin_z,
                tostring(selected),
                tostring(in_window),
                tostring(in_shape),
                band,
                tostring(selected and in_shape and band_drawn)
            )
        else
            floor_text = string_format("under=none stack=%d", stack)
        end

        mod:info(string_format(
            "[Radar] live floor probe target | phase=%s kind=%s dist=%.2f dz=%.2f pos=%.2f,%.2f,%.2f %s marker=%s floor=%.2f,%.2f %s",
            phase,
            tostring(target.kind),
            math_sqrt(dx * dx + dy * dy),
            target_z - origin_z,
            target_x,
            target_y,
            target_z,
            anchor_text,
            marker_text,
            center_x + floor_x,
            center_y + floor_y,
            floor_text
        ))
    end
end

--- Writes the probe, keeping any error inside it so the layer keeps drawing.
-- A failure is logged once per distinct message.
-- param: ... the arguments of `_log_probe`
local function _run_probe(...)
    local ok, err = pcall(_log_probe, ...)

    if not ok then
        local message = tostring(err)

        if message ~= _probe_last_failure then
            _probe_last_failure = message
            mod:info(string_format("[Radar] live floor probe failed: %s", message))
        end
    end
end

--- Selects, bins and draws the navmesh triangles for one frame.
-- Runs inside `pcall` from `RadarNavmesh.draw`. A triangle whose bounding circle misses the
-- radar shape is dropped, which the clipper would have done at a much higher cost. The rest
-- have their vertices projected onto the camera's right and forward axes, scaled by
-- `projection_radius / range` and clipped to the radar shape; bands with a zero alpha colour
-- are skipped. In debug mode, a draw that `_probe_phase` picks also writes the live floor probe
-- with the same axes.
-- tab: ui_renderer active UI renderer
-- number: t gameplay time
-- !Vector3: player_pos player position
-- !Quaternion: rotation camera rotation the radar is aligned to
-- number: center_x radar centre x in unscaled UI pixels
-- number: center_y radar centre y in unscaled UI pixels
-- number: projection_radius radar radius in unscaled UI pixels
-- number: range radar range in metres
-- ?number: z layer offset above the pass start layer
-- ?number: origin_revision Radar player revision of `player_pos`
local function _draw_geometry(ui_renderer, t, player_pos, rotation, center_x, center_y, projection_radius, range, z,
                              origin_revision)
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
    local right_x = forward_y * radar_scale
    local right_y = -forward_x * radar_scale
    local down_x = -forward_x * radar_scale
    local down_y = -forward_y * radar_scale
    local debug_mode = mod:get("debug_mode") == true
    local refreshed = false

    if not _selection_current(geometry, t, origin_x, origin_y, origin_z, range, radar_style,
            range_above, range_below, origin_revision) then
        local selection_start = debug_mode and os_clock and os_clock() or nil

        local select_range = (is_circle and range or range * SQUARE_RANGE_MULT) + SELECTION_RANGE_SLACK

        _refresh_selection(geometry, origin_x, origin_y, origin_z, select_range, range_above, range_below)

        _sel_revision = geometry.revision
        _sel_origin_revision = origin_revision
        _sel_origin_x = origin_x
        _sel_origin_y = origin_y
        _sel_origin_z = origin_z
        _sel_range = range
        _sel_style = radar_style
        _sel_range_above = range_above
        _sel_range_below = range_below
        _sel_t = t
        refreshed = true

        if selection_start then
            _metric_selection_ms = (os_clock() - selection_start) * 1000
        end
    end

    local probe_phase = debug_mode and _probe_phase(t, range, projection_radius, radar_style) or nil

    if _visible_count == 0 then
        if debug_mode then
            _log_metrics(geometry, t)
        end

        if probe_phase then
            _run_probe(probe_phase, geometry, t, ui_renderer, player_pos, rotation, center_x, center_y,
                projection_radius, range, origin_revision, refreshed, radar_style, is_circle, range_above,
                range_below, forward_x, forward_y, right_x, right_y, down_x, down_y, 0, 0, 0)
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

    local limit = projection_radius
    local limit_sq = limit * limit
    local drawn = 0
    local clip_and_emit = _clip_and_emit
    local visible = _visible
    local visible_count = _visible_count
    local mid_x, mid_y, mid_z = geometry.mid_x, geometry.mid_y, geometry.mid_z
    local radius = geometry.radius
    local ax, ay = geometry.ax, geometry.ay
    local bx, by = geometry.bx, geometry.by
    local cx, cy = geometry.cx, geometry.cy
    local below_idx, current_idx, above_idx = _below_idx, _current_idx, _above_idx
    local below_n, current_n, above_n = 0, 0, 0
    local current_half = NAVMESH_CURRENT_FLOOR_HALF_DZ

    for k = 1, visible_count do
        local i = visible[k]
        local dx = mid_x[i] - origin_x
        local dy = mid_y[i] - origin_y
        local reach = range + radius[i]
        local in_shape

        if is_circle then
            in_shape = dx * dx + dy * dy <= reach * reach
        else
            local along_right = dx * forward_y - dy * forward_x
            local along_forward = dx * forward_x + dy * forward_y

            in_shape = along_right <= reach and along_right >= -reach
                and along_forward <= reach and along_forward >= -reach
        end

        if in_shape then
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
                local sx1 = dx * right_x + dy * right_y
                local sy1 = dx * down_x + dy * down_y

                dx = bx[i] - origin_x
                dy = by[i] - origin_y

                local sx2 = dx * right_x + dy * right_y
                local sy2 = dx * down_x + dy * down_y

                dx = cx[i] - origin_x
                dy = cy[i] - origin_y

                local sx3 = dx * right_x + dy * right_y
                local sy3 = dx * down_x + dy * down_y

                drawn = drawn + clip_and_emit(gui, layer, color, is_circle, limit, limit_sq, ui_scale, center_x,
                    center_y, sx1, sy1, sx2, sy2, sx3, sy3)
            end
        end
    end

    mod:radar_profiler_value("draw_geometry_selected", visible_count)
    mod:radar_profiler_value("draw_geometry_in_shape", below_n + current_n + above_n)
    mod:radar_profiler_value("draw_geometry_triangles", drawn)

    if draw_start then
        _metric_drawn = drawn
        _metric_draw_ms = (os_clock() - draw_start) * 1000
        _log_metrics(geometry, t)
    end

    if probe_phase then
        _run_probe(probe_phase, geometry, t, ui_renderer, player_pos, rotation, center_x, center_y, projection_radius,
            range, origin_revision, refreshed, radar_style, is_circle, range_above, range_below, forward_x, forward_y,
            right_x, right_y, down_x, down_y, below_n, current_n, above_n)
    end
end

-- ----------------------------------------------------------------------------
-- Interface
-- ----------------------------------------------------------------------------

--- Module interface consumed by `ui/Radar_hud_element.lua`.
local RadarNavmesh = {}

--- Returns whether the navmesh layer should draw this frame.
-- The layer is active for the `live` geometry source, or for `auto` while Strikemap is not
-- drawing, and only while `Gui.triangle` exists and a band is visible. When the layer turns
-- inactive the cached navmesh geometry is released and the selection dropped.
-- bool: suppressed true while the Strikemap layer owns the geometry slot
-- treturn: bool
function RadarNavmesh.is_active(suppressed)
    local source = mod.get_map_geometry_source and mod:get_map_geometry_source() or "off"
    local selected = source == "live" or (source == "auto" and not suppressed)
    local active = Gui_triangle ~= nil and selected and _any_band_visible()

    if _was_active and not active then
        if mod.clear_navmesh_geometry then
            mod:clear_navmesh_geometry()
        end

        _invalidate_selection()
        _reset_probe()
    end

    _was_active = active

    return active
end

--- Draws the navmesh layer, isolating failures from the rest of the radar.
-- A gameplay time lower than the previous draw is treated as a new session and resets the
-- failure pause, metrics, selection and probe. A draw error pauses the layer for
-- `DRAW_FAILURE_COOLDOWN` seconds and is logged once per distinct message in debug mode.
-- tab: ui_renderer active UI renderer
-- ?number: t gameplay time
-- !Vector3: player_pos player position
-- !Quaternion: rotation camera rotation
-- number: center_x radar centre x in unscaled UI pixels
-- number: center_y radar centre y in unscaled UI pixels
-- number: projection_radius radar radius in unscaled UI pixels
-- number: range radar range in metres
-- ?number: z layer offset above the pass start layer
-- ?number: origin_revision Radar player revision of `player_pos`; a new one selects again at once
function RadarNavmesh.draw(ui_renderer, t, player_pos, rotation, center_x, center_y, projection_radius, range, z,
                           origin_revision)
    if not Gui_triangle or not ui_renderer then
        return
    end

    t = tonumber(t) or 0

    if t < _last_draw_t then
        _failed_until_t = -math_huge
        _next_metrics_log_t = 0
        _invalidate_selection()
        _reset_probe()
    end

    _last_draw_t = t

    if t < _failed_until_t then
        return
    end

    if not _any_band_visible() then
        return
    end

    local ok, err = pcall(_draw_geometry, ui_renderer, t, player_pos, rotation, center_x, center_y, projection_radius,
        range, z, origin_revision)

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
