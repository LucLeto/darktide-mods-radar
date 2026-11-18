--- Draws Strikemap's pre-baked floor plan as the radar's map layer.
-- Draws the walkable triangles of the Strikemap map context in the same below, current and
-- above floor bands as the live navmesh layer, and optionally the vector details (floor
-- contours, stair ticks, slope marks and hatching of other floors). The bands are measured
-- from the walkable floor under the Radar player instead of its raw height, eased, so a jump,
-- a stair or a small height offset between the player and the floor plan never re-bands a
-- whole walkway at once.
--
-- Each frame first sorts the triangles and vector segments in range into lists by floor band
-- and line class, then draws them in a fixed order. On the geometry layer that is the floors
-- below with their hatching and dashed outlines, the current floor and the faint floors above;
-- one layer up the hatching of the floors above and the current floor's slope marks; two
-- layers up the outlines of the floors above, the current floor's walls and its stair ticks.
-- Lower floors therefore always sit beneath the current floor's fill, whatever order the
-- spatial grid lists them in. Geometry is projected with the radar's own basis, range and
-- centre so it stays aligned with the markers, and is culled through spatial grids so only
-- nearby cells are visited per frame.
--
-- Explicit module loaded by `ui/Radar_hud_element.lua` through `mod:io_dofile`; the chunk
-- returns `RadarStrikemapGeometry`. Contexts come from `compatibility/Radar_strikemap.lua`,
-- which validates them first. The parsed grids are cached per context and revision, and
-- `mod._strikemap_geometry_renderer_reset` lets the compatibility module drop them. Draw
-- errors are reported back to the compatibility module instead of being raised.
-- module: Radar_strikemap_geometry
-- alias: RadarStrikemapGeometry
-- author: LucLeto
local mod = get_mod("Radar")
local StrikemapCompatibility = mod:io_dofile("Radar/scripts/mods/Radar/compatibility/Radar_strikemap")
local _clip_and_emit = mod:io_dofile("Radar/scripts/mods/Radar/ui/Radar_triangle_clipper")
local Color = Color
local Gui = Gui
local Quaternion = Quaternion
local Vector3 = Vector3
local pairs = pairs
local pcall = pcall
local tonumber = tonumber
local tostring = tostring
local type = type
local math_abs = math.abs
local math_ceil = math.ceil
local math_exp = math.exp
local math_floor = math.floor
local math_huge = math.huge
local math_log = math.log
local math_max = math.max
local math_min = math.min
local math_sqrt = math.sqrt
local string_format = string.format
local string_gmatch = string.gmatch
local string_match = string.match
local Gui_triangle = Gui and Gui.triangle
local Quaternion_forward = Quaternion and Quaternion.forward
local Vector3_x = Vector3 and Vector3.x
local Vector3_y = Vector3 and Vector3.y

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

--- Map triangle record layout, floor bands and fallback band colours.
-- A triangle record is `x1, y1, x2, y2, x3, y3, z`, with `z` the height used for its band.
local TRIANGLE_STRIDE = 7
local CURRENT_FLOOR_HALF_HEIGHT = 2.5
local BAND_CURRENT_FALLBACK_COLOR = { 80, 101, 133, 96 }
local BAND_ABOVE_FALLBACK_COLOR = { 32, 120, 150, 185 }
local BAND_BELOW_FALLBACK_COLOR = { 55, 120, 98, 76 }
local DEFAULT_RANGE_ABOVE = 7
local DEFAULT_RANGE_BELOW = 7
local OVERVIEW_RANGE = 30
--- Floor reference tuning, a Radar heuristic after Strikemap's floor reference for maps without levels.
-- The floor is picked from the triangles in the player's grid cell. A triangle under the player
-- scores its height difference, `FLOOR_ABOVE_WEIGHT` times over when it lies above the feet, so
-- the deck underfoot wins over an overhang during a jump. Without one, the triangle whose centre
-- lies within `FLOOR_NEARBY_RADIUS_SQ` scores its squared distance. A pick more than
-- `FLOOR_PIT_GUARD` metres off the feet gives way to the nearby pick and then to the raw height,
-- so the floor of a pit never takes over while the player stands at its edge. The shown height
-- eases towards the pick with time constant `FLOOR_EASE_SECONDS`, in steps of at most
-- `FLOOR_MAX_EASE_STEP` seconds, and takes it at once after a pause longer than
-- `FLOOR_STALE_SECONDS`. The pick is renewed once the player has moved the square root of
-- `FLOOR_RESAMPLE_DISTANCE_SQ` from where it was taken.
local FLOOR_ABOVE_WEIGHT = 1.6
local FLOOR_NEARBY_RADIUS_SQ = 4 * 4
local FLOOR_PIT_GUARD = 4
local FLOOR_EASE_SECONDS = 0.24
local FLOOR_MAX_EASE_STEP = 0.1
local FLOOR_STALE_SECONDS = 0.5
local FLOOR_RESAMPLE_DISTANCE_SQ = 0.25 * 0.25
local POINT_IN_TRIANGLE_EPSILON = 0.0001
--- Integer key packing for grid cells, `(cx + OFFSET) * STRIDE + cy + OFFSET`.
-- `CULL_RANGE_FACTOR` widens the cull square to the radar's diagonal.
local GRID_CELL_HASH_OFFSET = 4096
local GRID_CELL_HASH_STRIDE = 8192
local CULL_RANGE_FACTOR = 1.4143
--- Vector record strides and the vector grid cell size in metres.
-- Every vector record starts with `x1, y1, x2, y2`; only the height fields differ by layer
-- (one trailing `z` for contours, hatches and slopes, `z1, z2` for stairs).
local CONTOUR_STRIDE = 5
local STAIR_STRIDE = 6
local HATCH_STRIDE = 5
local SLOPE_STRIDE = 5
local TRANSITION_STRIDE = 4
local VECTOR_GRID_CELL = 16
local VECTOR_INVERSE_GRID_CELL = 1 / VECTOR_GRID_CELL
--- Line drawing tuning; the minimum lengths are screen pixels, the dash period unscaled UI pixels.
-- Dashes are anchored to the world. Their period is the power of two metres whose length on the
-- radar first reaches `DASH_PERIOD_PX`, so it stays between one and two times that length at any
-- zoom, and `DASH_ON_FRACTION` of every period is drawn.
local MIN_SEGMENT_SCREEN_LENGTH_SQ = 1e-12
local MIN_DASH_SCREEN_LENGTH = 0.5
local DASH_PERIOD_PX = 7
local DASH_ON_FRACTION = 4 / 7
local INVERSE_LN2 = 1 / math_log(2)
--- Line styles of `_emit_line`; a wall is extended by half its width at both ends so corners join.
local LINE_SOLID = 1
local LINE_WALL = 2
local LINE_DASHED = 3
--- Stair tick filtering, after Strikemap's tactical renderer.
-- A tick is kept only when its midpoint lies within `STAIR_ANCHOR_REACH` metres of a transition
-- anchor along both axes, the tick's height lies within `STAIR_ANCHOR_Z_SLACK` metres of the
-- anchor's two heights, and the anchor's chain is steep. Kept ticks are drawn only within
-- `STAIR_FLOOR_RANGE` metres of the floor reference.
local STAIR_ANCHOR_REACH = 2.5
local STAIR_ANCHOR_Z_SLACK = 1.4
local STAIR_FLOOR_RANGE = 4
local STEEP_CHAIN_MIN_STEEPNESS = 0.5
--- Vector layer select modes and their line half widths, alpha multipliers and brightening towards white.
local MODE_CONTOURS = 1
local MODE_STAIRS = 2
local MODE_HATCHES = 3
local MODE_SLOPES = 4
local CONTOUR_CURRENT_HALF_WIDTH = 1.0
local CONTOUR_ABOVE_HALF_WIDTH = 0.5
local CONTOUR_BELOW_HALF_WIDTH = 0.7
local STAIR_HALF_WIDTH = 0.7
local HATCH_HALF_WIDTH = 0.5
local SLOPE_HALF_WIDTH = 0.5
local CONTOUR_CURRENT_ALPHA_MULT = 2.6
local CONTOUR_CURRENT_BRIGHTEN = 0.55
local CONTOUR_ABOVE_ALPHA_MULT = 1.8
local CONTOUR_ABOVE_BRIGHTEN = 0.4
local CONTOUR_BELOW_ALPHA_MULT = 2.2
local CONTOUR_BELOW_BRIGHTEN = 0.15
local STAIR_ALPHA_MULT = 2.2
local STAIR_BRIGHTEN = 0.35
local HATCH_ALPHA_MULT = 0.9
local SLOPE_ALPHA_MULT = 1.0
local SLOPE_BRIGHTEN = 0.2

-- ----------------------------------------------------------------------------
-- Mutable state
-- ----------------------------------------------------------------------------

--- Parsed triangle grid for the current map context and revision.
-- `packed` holds each cell's comma separated triangle list as Strikemap delivered it;
-- `cells` caches parsed cells on first visit (`false` for a cell without valid triangles);
-- `stamp` records the frame a triangle was last drawn in, so a triangle listed in several
-- cells is drawn once per frame.
local _grid = {
    context = nil,
    revision = nil,
    triangles = nil,
    tri_count = 0,
    inverse_grid_cell = 1 / 16,
    packed = {},
    cells = {},
    stamp = {},
    frame_id = 0,
    min_cx = 0,
    max_cx = -1,
    min_cy = 0,
    max_cy = -1,
    cell_count = 0,
}
--- Segment indices for the vector layers of the current vector context and revision.
local _vectors = {
    context = nil,
    revision = nil,
    frame_id = 0,
    cell_count = 0,
    contours = nil,
    stairs = nil,
    hatches = nil,
    slopes = nil,
}
--- Floor reference the bands are measured from, and what it was derived from.
-- `display_z` is the eased height in use and `target_z` the last pick, taken at `sample_x`,
-- `sample_y` and `sample_z` from the grid of `sample_revision`. `triangles`, `tri_count` and
-- `map_id` identify the source map and `player_revision` the Radar player, so a new mission,
-- Expedition section or Radar player takes the pick at once instead of easing. `t` is the
-- gameplay time of the last update.
local _floor_state = {
    display_z = nil,
    target_z = nil,
    sample_x = 0,
    sample_y = 0,
    sample_z = 0,
    sample_revision = nil,
    triangles = nil,
    tri_count = 0,
    map_id = nil,
    player_revision = nil,
    t = nil,
}
--- Per-frame selection, reused every frame; list entries past their count are stale.
-- `below`, `current` and `above` hold triangle indices by floor band, the other lists vector
-- segment indices by how they are drawn.
local _bins = {
    below = {},
    below_n = 0,
    current = {},
    current_n = 0,
    above = {},
    above_n = 0,
    below_hatches = {},
    below_hatches_n = 0,
    below_contours = {},
    below_contours_n = 0,
    above_hatches = {},
    above_hatches_n = 0,
    above_contours = {},
    above_contours_n = 0,
    slopes = {},
    slopes_n = 0,
    walls = {},
    walls_n = 0,
    stairs = {},
    stairs_n = 0,
}
--- Per-frame projection, band and line style state shared by the select and draw steps, reused to avoid allocations.
-- `ready` is set once the geometry step has selected this frame's triangles, and the later steps
-- only run then. The projection basis is pre-scaled to unscaled UI pixels per metre.
local _view = {
    ready = false,
    gui = false,
    ui_scale = 1,
    layer = 0,
    center_x = 0,
    center_y = 0,
    screen_center_x = 0,
    screen_center_y = 0,
    ppx = 0,
    ppy = 0,
    ref_z = 0,
    basis_ax = 0,
    basis_ay = 0,
    basis_bx = 0,
    basis_by = 0,
    limit = 0,
    limit_sq = 0,
    radar_scale = 0,
    screen_px_per_m = 0,
    is_circle = false,
    range_above = 0,
    range_below = 0,
    current_color = false,
    above_color = false,
    below_color = false,
    cull_min_x = 0,
    cull_max_x = 0,
    cull_min_y = 0,
    cull_max_y = 0,
    selected = 0,
    in_shape = 0,
    drawn = 0,
    vector_frame_id = 0,
    min_cx = 0,
    max_cx = -1,
    min_cy = 0,
    max_cy = -1,
    dash_period_m = 0,
    dash_on_m = 0,
}
local _style = {
    contour_current = false,
    contour_above = false,
    contour_below = false,
    stair = false,
    hatch_below = false,
    hatch_above = false,
    slope = false,
}
--- Context and revision last reported by the debug diagnostics.
local _diag_context = nil
local _diag_revision = nil
--- Whether `Gui.triangle` works in this game build; nil until probed on the first draw.
local _triangle_supported = nil

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

--- Drops the parsed triangle grid so the next draw parses the context again.
local function _reset_grid()
    _grid.context = nil
    _grid.revision = nil
    _grid.triangles = nil
    _grid.tri_count = 0
    _grid.inverse_grid_cell = 1 / 16
    _grid.packed = {}
    _grid.cells = {}
    _grid.stamp = {}
    _grid.frame_id = 0
    _grid.min_cx = 0
    _grid.max_cx = -1
    _grid.min_cy = 0
    _grid.max_cy = -1
    _grid.cell_count = 0
end

--- Drops the vector segment indices so the next vector draw rebuilds them.
local function _reset_vectors()
    _vectors.context = nil
    _vectors.revision = nil
    _vectors.frame_id = 0
    _vectors.cell_count = 0
    _vectors.contours = nil
    _vectors.stairs = nil
    _vectors.hatches = nil
    _vectors.slopes = nil
end

--- Forgets the floor reference, so the next draw takes its pick at once.
local function _reset_floor()
    local floor = _floor_state

    floor.display_z = nil
    floor.target_z = nil
    floor.sample_x = 0
    floor.sample_y = 0
    floor.sample_z = 0
    floor.sample_revision = nil
    floor.triangles = nil
    floor.tri_count = 0
    floor.map_id = nil
    floor.player_revision = nil
    floor.t = nil
end

--- Empties every per-frame selection list and marks the frame as not set up.
local function _reset_bins()
    local bins = _bins

    bins.below_n = 0
    bins.current_n = 0
    bins.above_n = 0
    bins.below_hatches_n = 0
    bins.below_contours_n = 0
    bins.above_hatches_n = 0
    bins.above_contours_n = 0
    bins.slopes_n = 0
    bins.walls_n = 0
    bins.stairs_n = 0
    _view.ready = false
end

--- Returns the normalised horizontal forward direction of a rotation.
-- ?Quaternion: rotation camera rotation
-- treturn: ?number forward x, or nil when it cannot be derived
-- treturn: ?number forward y
local function _forward_xy(rotation)
    if not rotation or not Quaternion_forward or not Vector3_x or not Vector3_y then
        return nil, nil
    end

    local ok, direction = pcall(Quaternion_forward, rotation)

    if not ok or not direction then
        return nil, nil
    end

    local ok_x, x = pcall(Vector3_x, direction)
    local ok_y, y = pcall(Vector3_y, direction)

    x = ok_x and tonumber(x) or nil
    y = ok_y and tonumber(y) or nil

    if not x or not y or x ~= x or y ~= y then
        return nil, nil
    end

    local length = math_sqrt(x * x + y * y)

    if length <= 0 or length == math_huge then
        return nil, nil
    end

    return x / length, y / length
end

--- Parses a map context's spatial index into the triangle grid.
-- Only the cell keys (`"cx:cy"`) are parsed here; each cell's triangle list stays packed
-- until the cell is first visited. Raises an error for unusable data, which the caller's
-- `pcall` turns into the integration's `error` status.
-- tab: context validated Strikemap map context
-- param: revision geometry revision of the context
local function _build_grid(context, revision)
    local triangles = context.triangles
    local spatial_index = context.spatial_index
    local grid_cell = tonumber(context.grid_cell)
    local tri_count = tonumber(context.tri_count)
        or (type(triangles) == "table" and math_floor(#triangles / TRIANGLE_STRIDE))
        or 0

    if type(triangles) ~= "table" or type(spatial_index) ~= "table"
        or not grid_cell or grid_cell <= 0 or tri_count <= 0 then
        error("the Strikemap map context is missing usable geometry data")
    end

    if type(triangles[1]) ~= "number" or type(triangles[tri_count * TRIANGLE_STRIDE]) ~= "number" then
        error("the Strikemap map context uses an unsupported triangle format")
    end

    local packed_cells = {}
    local cell_count = 0
    local grid_min_cx = math_huge
    local grid_max_cx = -math_huge
    local grid_min_cy = math_huge
    local grid_max_cy = -math_huge

    for key, packed in pairs(spatial_index) do
        local gx, gy = string_match(tostring(key), "^(-?%d+):(-?%d+)$")

        gx = tonumber(gx)
        gy = tonumber(gy)

        if gx and gy and type(packed) == "string" then
            packed_cells[(gx + GRID_CELL_HASH_OFFSET) * GRID_CELL_HASH_STRIDE + gy + GRID_CELL_HASH_OFFSET] = packed
            cell_count = cell_count + 1

            if gx < grid_min_cx then
                grid_min_cx = gx
            end

            if gx > grid_max_cx then
                grid_max_cx = gx
            end

            if gy < grid_min_cy then
                grid_min_cy = gy
            end

            if gy > grid_max_cy then
                grid_max_cy = gy
            end
        end
    end

    if cell_count == 0 then
        error("the Strikemap spatial index is empty or malformed")
    end

    local stamp = {}

    for i = 1, tri_count do
        stamp[i] = 0
    end

    _grid.context = context
    _grid.revision = revision
    _grid.triangles = triangles
    _grid.tri_count = tri_count
    _grid.inverse_grid_cell = 1 / grid_cell
    _grid.packed = packed_cells
    _grid.cells = {}
    _grid.stamp = stamp
    _grid.frame_id = 0
    _grid.min_cx = grid_min_cx
    _grid.max_cx = grid_max_cx
    _grid.min_cy = grid_min_cy
    _grid.max_cy = grid_max_cy
    _grid.cell_count = cell_count
    if mod:get("debug_mode") == true then
        mod:info(string_format("[Radar] Strikemap geometry grid parsed | map=%s revision=%s triangles=%d cells=%d",
            tostring(context.map_id or context.mission_name), tostring(revision), tri_count, cell_count))
    end
end

--- Rebuilds the triangle grid when the context or its revision changed.
local function _ensure_grid(context, revision)
    if _grid.context ~= context or _grid.revision ~= revision then
        _build_grid(context, revision)
    end
end

--- Parses and caches the triangle indices of one grid cell, dropping out-of-range entries.
-- int: cell_key packed cell key
-- treturn: tab|bool list of triangle indices, or false when the cell has none
local function _parse_cell(cell_key)
    local packed = _grid.packed[cell_key]
    local bucket = false

    if packed then
        local tri_count = _grid.tri_count
        local n = 0

        for token in string_gmatch(packed, "[^,]+") do
            local index = tonumber(token)

            if index and index >= 1 and index <= tri_count then
                if not bucket then
                    bucket = {}
                end

                n = n + 1
                bucket[n] = index
            end
        end
    end

    _grid.cells[cell_key] = bucket

    return bucket
end

--- Picks the floor height under a position from the triangles of its grid cell.
-- Follows the rules described at `FLOOR_ABOVE_WEIGHT`. Reads only the cell cache, never the
-- per-frame stamps, so it can run before the selection walk of the same frame.
-- number: px player x
-- number: py player y
-- number: pz player z
-- treturn: ?number floor height, or nil when no triangle qualifies
local function _sample_floor_height(px, py, pz)
    local inverse_grid_cell = _grid.inverse_grid_cell
    local cell_key = (math_floor(px * inverse_grid_cell) + GRID_CELL_HASH_OFFSET) * GRID_CELL_HASH_STRIDE
        + math_floor(py * inverse_grid_cell) + GRID_CELL_HASH_OFFSET
    local bucket = _grid.cells[cell_key]

    if bucket == nil then
        bucket = _parse_cell(cell_key)
    end

    if not bucket then
        return nil
    end

    local triangles = _grid.triangles
    local stride = TRIANGLE_STRIDE
    local above_weight = FLOOR_ABOVE_WEIGHT
    local nearby_radius_sq = FLOOR_NEARBY_RADIUS_SQ
    local epsilon = POINT_IN_TRIANGLE_EPSILON
    local best_z = nil
    local best_score = math_huge
    local near_z = nil
    local near_score = math_huge

    for bucket_index = 1, #bucket do
        local base = (bucket[bucket_index] - 1) * stride
        local ax = triangles[base + 1]
        local ay = triangles[base + 2]
        local bx = triangles[base + 3]
        local by = triangles[base + 4]
        local cx = triangles[base + 5]
        local cy = triangles[base + 6]
        local tz = triangles[base + 7]
        local dz = tz - pz
        local d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by)
        local d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy)
        local d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay)

        if not ((d1 < -epsilon or d2 < -epsilon or d3 < -epsilon)
                and (d1 > epsilon or d2 > epsilon or d3 > epsilon)) then
            local score = dz >= 0 and dz * above_weight or -dz

            if score < best_score then
                best_score = score
                best_z = tz
            end
        else
            local mx = (ax + bx + cx) / 3 - px
            local my = (ay + by + cy) / 3 - py
            local horizontal_sq = mx * mx + my * my

            if horizontal_sq <= nearby_radius_sq then
                local score = horizontal_sq + dz * dz

                if score < near_score then
                    near_score = score
                    near_z = tz
                end
            end
        end
    end

    local pick = best_z or near_z

    if best_z and near_z and math_abs(best_z - pz) > FLOOR_PIT_GUARD
        and math_abs(near_z - pz) < math_abs(best_z - pz) then
        pick = near_z
    end

    if pick and math_abs(pick - pz) > FLOOR_PIT_GUARD then
        return nil
    end

    return pick
end

--- Updates the floor reference for this frame and returns the height the bands are measured from.
-- Runs right after `_ensure_grid`. A new source map (another triangle array, fewer triangles or
-- another map id), a new Radar player, a missing or rewound gameplay time and a pause longer
-- than `FLOOR_STALE_SECONDS` take the new pick at once; otherwise the shown height eases towards
-- it. A live revision of the same map picks again from the new grid but keeps easing, as
-- Strikemap does, so a growing Expedition map never flickers between floor treatments.
-- tab: context validated map context
-- param: revision geometry revision of the context
-- !Vector3: player_pos Radar player position
-- param: player_revision Radar player revision
-- ?number: t gameplay time
-- treturn: number floor reference height
local function _update_floor_reference(context, revision, player_pos, player_revision, t)
    local floor = _floor_state
    local px = player_pos.x
    local py = player_pos.y
    local pz = player_pos.z or 0
    local triangles = _grid.triangles
    local tri_count = _grid.tri_count
    local map_id = context.map_id or context.mission_name
    local last_t = floor.t
    local snap = floor.display_z == nil
        or triangles ~= floor.triangles
        or tri_count < floor.tri_count
        or map_id ~= floor.map_id
        or player_revision ~= floor.player_revision
        or not t or not last_t or t < last_t or t - last_t > FLOOR_STALE_SECONDS
    local target_z = floor.target_z
    local dx = px - floor.sample_x
    local dy = py - floor.sample_y
    local dz = pz - floor.sample_z

    if snap or target_z == nil or floor.sample_revision ~= revision
        or dx * dx + dy * dy + dz * dz >= FLOOR_RESAMPLE_DISTANCE_SQ then
        target_z = _sample_floor_height(px, py, pz) or pz
        floor.target_z = target_z
        floor.sample_x = px
        floor.sample_y = py
        floor.sample_z = pz
        floor.sample_revision = revision
    end

    local display_z = floor.display_z

    if snap then
        display_z = target_z
    else
        local dt = t - last_t

        if dt > FLOOR_MAX_EASE_STEP then
            dt = FLOOR_MAX_EASE_STEP
        end

        display_z = display_z + (target_z - display_z) * (1 - math_exp(-dt / FLOOR_EASE_SECONDS))
    end

    floor.display_z = display_z
    floor.triangles = triangles
    floor.tri_count = tri_count
    floor.map_id = map_id
    floor.player_revision = player_revision
    floor.t = t

    return display_z
end

--- Checks once whether `Gui.triangle` can be called, with a transparent triangle off screen.
-- param: gui GUI to probe
-- treturn: bool
local function _probe_triangle(gui)
    if not Gui_triangle or not Vector3 then
        return false
    end

    local ok = pcall(Gui_triangle, gui,
        Vector3(-40, 0, -40), Vector3(-39, 0, -40), Vector3(-40, 0, -39), 0, Color(0, 0, 0, 0))

    return ok == true
end

--- Returns the configured ARGB colour of a floor band, or the fallback before the colour runtime exists.
-- string: prefix band colour setting prefix, shared with the live navmesh layer
-- tab: fallback widget colour array
-- treturn: tab widget colour array
local function _band_raw_color(prefix, fallback)
    local get_radar_color = mod.get_radar_color

    return get_radar_color and get_radar_color(mod, prefix, fallback) or fallback
end

--- Returns a floor band's engine colour, or nil when the band is fully transparent and should be skipped.
-- treturn: ?Color
local function _band_color(prefix, fallback)
    local color = _band_raw_color(prefix, fallback)
    local alpha = tonumber(color[1]) or 0

    if alpha <= 0 then
        return nil
    end

    return Color(alpha, color[2] or 255, color[3] or 255, color[4] or 255)
end

--- Derives a vector line colour from a band colour, so details stay readable over the band fill.
-- tab: raw band widget colour array
-- number: alpha_mult alpha multiplier, capped at 255
-- number: brighten fraction to move each channel towards white
-- treturn: ?Color nil when the band is fully transparent
local function _line_color(raw, alpha_mult, brighten)
    local alpha = tonumber(raw[1]) or 0

    if alpha <= 0 then
        return nil
    end

    alpha = math_floor(alpha * alpha_mult + 0.5)

    if alpha > 255 then
        alpha = 255
    end

    local r = raw[2] or 255
    local g = raw[3] or 255
    local b = raw[4] or 255

    if brighten > 0 then
        r = math_floor(r + (255 - r) * brighten + 0.5)
        g = math_floor(g + (255 - g) * brighten + 0.5)
        b = math_floor(b + (255 - b) * brighten + 0.5)
    end

    return Color(alpha, r, g, b)
end

--- Clamps a configured floor range to 1 to 30 metres, the range of its settings slider.
-- The navmesh layer clamps the same settings the same way.
local function _clamp_band_range(value, default_value)
    value = tonumber(value) or default_value

    if value < 1 then
        value = 1
    elseif value > 30 then
        value = 30
    end

    return value
end

--- Returns how far above and below the player floors are drawn; overview mode uses `OVERVIEW_RANGE`.
-- treturn: number range above in metres
-- treturn: number range below in metres
local function _configured_ranges()
    if mod:is_overview_mode_active() then
        return OVERVIEW_RANGE, OVERVIEW_RANGE
    end

    return _clamp_band_range(mod:get("navmesh_range_above"), DEFAULT_RANGE_ABOVE),
        _clamp_band_range(mod:get("navmesh_range_below"), DEFAULT_RANGE_BELOW)
end

--- Projects and draws one band's selected triangles, clipped to the radar shape.
-- A triangle entirely beyond one side of the radar square is skipped before clipping.
-- tab: indices triangle indices of the band
-- int: count number of indices
-- param: color engine `Color` of the band
-- treturn: int triangles handed to the clipper
-- treturn: int `Gui.triangle` calls made
local function _draw_band(indices, count, color)
    local view = _view
    local triangles = _grid.triangles
    local stride = TRIANGLE_STRIDE
    local gui = view.gui
    local layer = view.layer
    local ppx = view.ppx
    local ppy = view.ppy
    local ax = view.basis_ax
    local ay = view.basis_ay
    local bx = view.basis_bx
    local by = view.basis_by
    local limit = view.limit
    local limit_sq = view.limit_sq
    local is_circle = view.is_circle
    local ui_scale = view.ui_scale
    local center_x = view.center_x
    local center_y = view.center_y
    local clip_and_emit = _clip_and_emit
    local in_shape = 0
    local drawn = 0

    for k = 1, count do
        local base = (indices[k] - 1) * stride
        local dx = triangles[base + 1] - ppx
        local dy = triangles[base + 2] - ppy
        local px1 = dx * ax + dy * ay
        local py1 = dx * bx + dy * by

        dx = triangles[base + 3] - ppx
        dy = triangles[base + 4] - ppy

        local px2 = dx * ax + dy * ay
        local py2 = dx * bx + dy * by

        dx = triangles[base + 5] - ppx
        dy = triangles[base + 6] - ppy

        local px3 = dx * ax + dy * ay
        local py3 = dx * bx + dy * by

        if not ((px1 > limit and px2 > limit and px3 > limit)
                or (px1 < -limit and px2 < -limit and px3 < -limit)
                or (py1 > limit and py2 > limit and py3 > limit)
                or (py1 < -limit and py2 < -limit and py3 < -limit)) then
            in_shape = in_shape + 1
            drawn = drawn + clip_and_emit(gui, layer, color, is_circle, limit, limit_sq, ui_scale, center_x, center_y,
                px1, py1, px2, py2, px3, py3)
        end
    end

    return in_shape, drawn
end

--- Sets up this frame's view, selects the map triangles in range by floor band and draws the floors below.
-- Visits the grid cells inside the cull square once, measures each triangle against the floor
-- reference and the floor range and lists it in `_bins` by band, then draws the floors below.
-- `_draw_upper_fills` draws the rest after the lower vectors. Leaves `_view.ready` false when
-- nothing can be drawn. Runs inside `pcall` from `RadarStrikemapGeometry.draw`.
-- tab: ui_renderer active UI renderer
-- tab: context validated map context
-- param: revision geometry revision
-- !Vector3: player_pos Radar player position
-- param: player_revision Radar player revision
-- ?Quaternion: rotation camera rotation; the map stays north-up without one
-- number: center_x radar centre x in unscaled UI pixels
-- number: center_y radar centre y in unscaled UI pixels
-- number: z layer offset above the pass start layer
-- number: projection_radius radar radius in unscaled UI pixels
-- number: range radar range in metres
-- string: radar_style radar style
-- ?number: t gameplay time
local function _select_geometry(ui_renderer, context, revision, player_pos, player_revision, rotation, center_x,
                                center_y, z, projection_radius, range, radar_style, t)
    local view = _view

    view.ready = false

    local current_color = _band_color("radar_navmesh", BAND_CURRENT_FALLBACK_COLOR)
    local above_color = _band_color("radar_navmesh_above", BAND_ABOVE_FALLBACK_COLOR)
    local below_color = _band_color("radar_navmesh_below", BAND_BELOW_FALLBACK_COLOR)

    if not current_color and not above_color and not below_color then
        return
    end

    local range_above, range_below = _configured_ranges()

    _ensure_grid(context, revision)

    if _grid.tri_count == 0 then
        return
    end

    local ref_z = _update_floor_reference(context, revision, player_pos, player_revision, t)
    local scale = ui_renderer.scale or 1
    local render_settings = ui_renderer.render_settings
    local ppx = player_pos.x
    local ppy = player_pos.y
    local radar_scale = projection_radius / range
    local forward_x, forward_y = _forward_xy(rotation)

    view.gui = ui_renderer.gui
    view.ui_scale = scale
    view.layer = (render_settings and render_settings.start_layer or 0) + z
    view.center_x = center_x
    view.center_y = center_y
    view.screen_center_x = center_x * scale
    view.screen_center_y = center_y * scale
    view.ppx = ppx
    view.ppy = ppy
    view.ref_z = ref_z

    if forward_x and forward_y then
        view.basis_ax = forward_y * radar_scale
        view.basis_ay = -forward_x * radar_scale
        view.basis_bx = -forward_x * radar_scale
        view.basis_by = -forward_y * radar_scale
    else
        view.basis_ax = radar_scale
        view.basis_ay = 0
        view.basis_bx = 0
        view.basis_by = -radar_scale
    end

    view.limit = projection_radius
    view.limit_sq = projection_radius * projection_radius
    view.radar_scale = radar_scale
    view.screen_px_per_m = radar_scale * scale
    view.is_circle = radar_style == "circle"
    view.range_above = range_above
    view.range_below = range_below
    view.current_color = current_color
    view.above_color = above_color
    view.below_color = below_color

    local cull_range = range * CULL_RANGE_FACTOR

    view.cull_min_x = ppx - cull_range
    view.cull_max_x = ppx + cull_range
    view.cull_min_y = ppy - cull_range
    view.cull_max_y = ppy + cull_range

    local triangles = _grid.triangles
    local cells = _grid.cells
    local stamp = _grid.stamp
    local frame_id = _grid.frame_id + 1
    _grid.frame_id = frame_id

    local inverse_grid_cell = _grid.inverse_grid_cell
    local min_cx = math_max(math_floor(view.cull_min_x * inverse_grid_cell), _grid.min_cx)
    local max_cx = math_min(math_floor(view.cull_max_x * inverse_grid_cell), _grid.max_cx)
    local min_cy = math_max(math_floor(view.cull_min_y * inverse_grid_cell), _grid.min_cy)
    local max_cy = math_min(math_floor(view.cull_max_y * inverse_grid_cell), _grid.max_cy)

    local bins = _bins
    local below = bins.below
    local current = bins.current
    local above = bins.above
    local below_n = 0
    local current_n = 0
    local above_n = 0
    local selected = 0
    local stride = TRIANGLE_STRIDE
    local half = CURRENT_FLOOR_HALF_HEIGHT

    for cx = min_cx, max_cx do
        local row_key = (cx + GRID_CELL_HASH_OFFSET) * GRID_CELL_HASH_STRIDE

        for cy = min_cy, max_cy do
            local cell_key = row_key + cy + GRID_CELL_HASH_OFFSET
            local bucket = cells[cell_key]

            if bucket == nil then
                bucket = _parse_cell(cell_key)
            end

            if bucket then
                for bucket_index = 1, #bucket do
                    local i = bucket[bucket_index]

                    if stamp[i] ~= frame_id then
                        stamp[i] = frame_id
                        selected = selected + 1

                        local dz = triangles[i * stride] - ref_z

                        if dz <= range_above and dz >= -range_below then
                            if dz > half then
                                if above_color then
                                    above_n = above_n + 1
                                    above[above_n] = i
                                end
                            elseif dz < -half then
                                if below_color then
                                    below_n = below_n + 1
                                    below[below_n] = i
                                end
                            elseif current_color then
                                current_n = current_n + 1
                                current[current_n] = i
                            end
                        end
                    end
                end
            end
        end
    end

    bins.below_n = below_n
    bins.current_n = current_n
    bins.above_n = above_n
    view.selected = selected
    view.in_shape = 0
    view.drawn = 0
    view.ready = true

    if below_n > 0 then
        view.in_shape, view.drawn = _draw_band(below, below_n, below_color)
    end
end

--- Draws the current floor and then the floors above, after the lower vectors, and reports the profiler counts.
-- Runs inside `pcall` from `RadarStrikemapGeometry.draw` once `_select_geometry` set the frame up.
local function _draw_upper_fills()
    local view = _view
    local bins = _bins
    local in_shape = view.in_shape
    local drawn = view.drawn

    if bins.current_n > 0 then
        local band_in_shape, band_drawn = _draw_band(bins.current, bins.current_n, view.current_color)

        in_shape = in_shape + band_in_shape
        drawn = drawn + band_drawn
    end

    if bins.above_n > 0 then
        local band_in_shape, band_drawn = _draw_band(bins.above, bins.above_n, view.above_color)

        in_shape = in_shape + band_in_shape
        drawn = drawn + band_drawn
    end

    mod:radar_profiler_value("draw_geometry_selected", view.selected)
    mod:radar_profiler_value("draw_geometry_in_shape", in_shape)
    mod:radar_profiler_value("draw_geometry_triangles", drawn)
end

--- Builds the grid index of one vector layer, registering each segment in every cell its bounds touch.
-- ?tab: segments flat vector records
-- ?int: count number of records
-- int: stride record length
-- bool: z_last whether the height is the record's last field (otherwise two heights follow the points)
-- ?tab: skip set of record indices to leave out, such as Strikemap's `dead_contours`
-- treturn: tab layer index
-- treturn: int number of cells used
local function _build_segment_index(segments, count, stride, z_last, skip)
    local layer = {
        segments = segments,
        count = 0,
        stride = stride,
        z_last = z_last,
        cells = {},
        stamp = {},
        keep = nil,
        skipped = 0,
        min_cx = 0,
        max_cx = -1,
        min_cy = 0,
        max_cy = -1,
    }

    if type(segments) ~= "table" or not count or count <= 0 then
        return layer, 0
    end

    layer.count = count

    local cells = layer.cells
    local stamp = layer.stamp
    local cell_count = 0
    local skipped = 0
    local layer_min_cx = math_huge
    local layer_max_cx = -math_huge
    local layer_min_cy = math_huge
    local layer_max_cy = -math_huge

    for i = 1, count do
        stamp[i] = 0

        if skip and skip[i] then
            skipped = skipped + 1
        else
            local base = (i - 1) * stride
            local x1 = segments[base + 1]
            local y1 = segments[base + 2]
            local x2 = segments[base + 3]
            local y2 = segments[base + 4]

            local min_x, max_x = x1, x2

            if min_x > max_x then
                min_x, max_x = max_x, min_x
            end

            local min_y, max_y = y1, y2

            if min_y > max_y then
                min_y, max_y = max_y, min_y
            end

            local min_cx = math_floor(min_x * VECTOR_INVERSE_GRID_CELL)
            local max_cx = math_floor(max_x * VECTOR_INVERSE_GRID_CELL)
            local min_cy = math_floor(min_y * VECTOR_INVERSE_GRID_CELL)
            local max_cy = math_floor(max_y * VECTOR_INVERSE_GRID_CELL)

            if min_cx < layer_min_cx then
                layer_min_cx = min_cx
            end

            if max_cx > layer_max_cx then
                layer_max_cx = max_cx
            end

            if min_cy < layer_min_cy then
                layer_min_cy = min_cy
            end

            if max_cy > layer_max_cy then
                layer_max_cy = max_cy
            end

            for cx = min_cx, max_cx do
                local row_key = (cx + GRID_CELL_HASH_OFFSET) * GRID_CELL_HASH_STRIDE

                for cy = min_cy, max_cy do
                    local key = row_key + cy + GRID_CELL_HASH_OFFSET
                    local bucket = cells[key]

                    if not bucket then
                        bucket = {}
                        cells[key] = bucket
                        cell_count = cell_count + 1
                    end

                    bucket[#bucket + 1] = i
                end
            end
        end
    end

    layer.skipped = skipped

    if cell_count > 0 then
        layer.min_cx = layer_min_cx
        layer.max_cx = layer_max_cx
        layer.min_cy = layer_min_cy
        layer.max_cy = layer_max_cy
    end

    return layer, cell_count
end

--- Returns whether a transition chain is steep enough to carry stair ticks.
-- Uses the explicit `steep` flag, then a `stairs`/`steep` classification, then the numeric
-- steepness; a chain that says nothing counts as steep.
-- tab: chain Strikemap transition chain
-- treturn: bool
local function _chain_is_steep(chain)
    local steep = chain.steep

    if steep ~= nil then
        return steep == true
    end

    local kind = chain.kind or chain.classification or chain.type

    if kind ~= nil then
        kind = tostring(kind)

        return kind == "stairs" or kind == "stair" or kind == "steep"
    end

    local steepness = tonumber(chain.steepness)

    if steepness ~= nil then
        return steepness >= STEEP_CHAIN_MIN_STEEPNESS
    end

    return true
end

--- Marks which stair ticks to draw, keeping only those at an anchor of a steep chain at a matching height.
-- A tick is kept when its midpoint lies within `STAIR_ANCHOR_REACH` of an anchor along both
-- axes, its height lies within `STAIR_ANCHOR_Z_SLACK` of the anchor's two heights (in either
-- order), and the anchor's chain is steep; an anchor without a chain counts as steep. Stores
-- the result as `stair_layer.keep`. `_build_vectors` builds no stair index without transitions.
-- tab: vector_context validated vector context
-- tab: counts record count per layer
-- tab: stair_layer stair layer index
local function _build_stair_filter(vector_context, counts, stair_layer)
    local stair_count = stair_layer.count
    local transition_count = counts.transitions or 0

    if stair_count <= 0 or transition_count <= 0 then
        return
    end

    local transitions = vector_context.transitions
    local transition_chain = vector_context.transition_chain
    local chains = vector_context.chains
    local anchor_cells = {}

    for a = 1, transition_count do
        local base = (a - 1) * TRANSITION_STRIDE
        local key = (math_floor(transitions[base + 1] * VECTOR_INVERSE_GRID_CELL) + GRID_CELL_HASH_OFFSET)
            * GRID_CELL_HASH_STRIDE
            + math_floor(transitions[base + 2] * VECTOR_INVERSE_GRID_CELL) + GRID_CELL_HASH_OFFSET
        local bucket = anchor_cells[key]

        if not bucket then
            bucket = {}
            anchor_cells[key] = bucket
        end

        bucket[#bucket + 1] = a
    end

    local segments = stair_layer.segments
    local keep = {}
    local reach = STAIR_ANCHOR_REACH
    local z_slack = STAIR_ANCHOR_Z_SLACK

    for i = 1, stair_count do
        local base = (i - 1) * STAIR_STRIDE
        local mx = (segments[base + 1] + segments[base + 3]) * 0.5
        local my = (segments[base + 2] + segments[base + 4]) * 0.5
        local mz = (segments[base + 5] + segments[base + 6]) * 0.5
        local ccx = math_floor(mx * VECTOR_INVERSE_GRID_CELL)
        local ccy = math_floor(my * VECTOR_INVERSE_GRID_CELL)
        local keep_tick = false

        for cx = ccx - 1, ccx + 1 do
            local row_key = (cx + GRID_CELL_HASH_OFFSET) * GRID_CELL_HASH_STRIDE

            for cy = ccy - 1, ccy + 1 do
                local bucket = anchor_cells[row_key + cy + GRID_CELL_HASH_OFFSET]

                if bucket then
                    for j = 1, #bucket do
                        local a = bucket[j]
                        local anchor_base = (a - 1) * TRANSITION_STRIDE
                        local dx = transitions[anchor_base + 1] - mx
                        local dy = transitions[anchor_base + 2] - my

                        if dx >= -reach and dx <= reach and dy >= -reach and dy <= reach then
                            local z_low = transitions[anchor_base + 3]
                            local z_high = transitions[anchor_base + 4]

                            if z_low > z_high then
                                z_low, z_high = z_high, z_low
                            end

                            if mz >= z_low - z_slack and mz <= z_high + z_slack then
                                local chain = nil

                                if transition_chain ~= nil and chains ~= nil then
                                    local chain_id = transition_chain[a]

                                    if chain_id ~= nil then
                                        chain = chains[chain_id]
                                    end
                                end

                                if type(chain) ~= "table" or _chain_is_steep(chain) then
                                    keep_tick = true

                                    break
                                end
                            end
                        end
                    end
                end

                if keep_tick then
                    break
                end
            end

            if keep_tick then
                break
            end
        end

        keep[i] = keep_tick
    end

    stair_layer.keep = keep
end

--- Rebuilds all vector layer indices and the stair filter for a vector context.
-- Contours listed in `dead_contours` are left out. Without transitions there is no steep chain to
-- place stair ticks at, so the stair layer stays empty instead of indexing every elevation step.
local function _build_vectors(vector_context, counts, revision)
    _reset_vectors()

    local total_cells = 0
    local layer, cell_count

    layer, cell_count = _build_segment_index(vector_context.contours, counts.contours, CONTOUR_STRIDE, true,
        vector_context.dead_contours)
    _vectors.contours = layer
    total_cells = total_cells + cell_count

    if (counts.transitions or 0) > 0 then
        layer, cell_count = _build_segment_index(vector_context.stairs, counts.stairs, STAIR_STRIDE, false, nil)
    else
        layer, cell_count = _build_segment_index(nil, 0, STAIR_STRIDE, false, nil)
    end

    _vectors.stairs = layer
    total_cells = total_cells + cell_count

    layer, cell_count = _build_segment_index(vector_context.hatches, counts.hatches, HATCH_STRIDE, true, nil)
    _vectors.hatches = layer
    total_cells = total_cells + cell_count

    layer, cell_count = _build_segment_index(vector_context.slopes, counts.slopes, SLOPE_STRIDE, true, nil)
    _vectors.slopes = layer
    total_cells = total_cells + cell_count

    _build_stair_filter(vector_context, counts, _vectors.stairs)

    _vectors.context = vector_context
    _vectors.revision = revision
    _vectors.cell_count = total_cells
end

--- Rebuilds the vector layer indices when the vector context or its revision changed.
local function _ensure_vectors(vector_context, counts, revision)
    if _vectors.context ~= vector_context or _vectors.revision ~= revision then
        _build_vectors(vector_context, counts, revision)
    end
end

--- Draws a screen-space line segment as a quad of two triangles, offset by the normal `(nx, ny)`.
-- The two corners both triangles share are built once.
local function _submit_quad(gui, ax, ay, bx, by, nx, ny, layer, color)
    local start_corner = Vector3(ax + nx, 0, ay + ny)
    local end_corner = Vector3(bx - nx, 0, by - ny)

    Gui_triangle(gui, start_corner, Vector3(bx + nx, 0, by + ny), end_corner, layer, color)
    Gui_triangle(gui, start_corner, end_corner, Vector3(ax - nx, 0, ay - ny), layer, color)
end

--- Projects a world-space segment with `_view`, clips it to the radar shape and draws it as a thick line.
-- A wall is first extended by half its width at both ends, so neighbouring segments join at
-- corners, and only then clipped, so it never reaches past the radar edge. A dashed line takes
-- its dashes from the world (see `DASH_PERIOD_PX`), measured along the segment from its end with
-- the lower x (the lower y when it runs along y), so the pattern does not depend on the
-- segment's direction and never moves with clipping, rotation or zoom within one period step.
-- number: wx1 start x in world space
-- number: wy1 start y in world space
-- number: wx2 end x in world space
-- number: wy2 end y in world space
-- int: layer GUI layer
-- param: color engine `Color`
-- number: half_w half line width in unscaled pixels
-- int: line_style `LINE_SOLID`, `LINE_WALL` or `LINE_DASHED`
local function _emit_line(wx1, wy1, wx2, wy2, layer, color, half_w, line_style)
    local view = _view
    local ax = view.basis_ax
    local ay = view.basis_ay
    local bx = view.basis_bx
    local by = view.basis_by
    local dx = wx1 - view.ppx
    local dy = wy1 - view.ppy
    local px1 = dx * ax + dy * ay
    local py1 = dx * bx + dy * by

    dx = wx2 - view.ppx
    dy = wy2 - view.ppy

    local px2 = dx * ax + dy * ay
    local py2 = dx * bx + dy * by
    local limit = view.limit

    if (px1 > limit and px2 > limit) or (px1 < -limit and px2 < -limit)
        or (py1 > limit and py2 > limit) or (py1 < -limit and py2 < -limit) then
        return
    end

    local ddx = px2 - px1
    local ddy = py2 - py1

    if line_style == LINE_WALL then
        local wall_length_sq = ddx * ddx + ddy * ddy

        if wall_length_sq > MIN_SEGMENT_SCREEN_LENGTH_SQ then
            local extend = half_w / math_sqrt(wall_length_sq)

            px1 = px1 - ddx * extend
            py1 = py1 - ddy * extend
            px2 = px2 + ddx * extend
            py2 = py2 + ddy * extend
            ddx = px2 - px1
            ddy = py2 - py1
        end
    end

    local t0 = 0
    local t1 = 1

    if view.is_circle then
        local limit_sq = view.limit_sq

        if px1 * px1 + py1 * py1 > limit_sq or px2 * px2 + py2 * py2 > limit_sq then
            local a = ddx * ddx + ddy * ddy

            if a <= 1e-9 then
                return
            end

            local b = px1 * ddx + py1 * ddy
            local c = px1 * px1 + py1 * py1 - limit_sq
            local disc = b * b - a * c

            if disc <= 0 then
                return
            end

            local root = math_sqrt(disc)

            t0 = (-b - root) / a
            t1 = (-b + root) / a

            if t0 < 0 then
                t0 = 0
            end

            if t1 > 1 then
                t1 = 1
            end

            if t0 >= t1 then
                return
            end
        end
    else
        if ddx == 0 then
            if px1 < -limit or px1 > limit then
                return
            end
        else
            local ta = (-limit - px1) / ddx
            local tb = (limit - px1) / ddx

            if ta > tb then
                ta, tb = tb, ta
            end

            if ta > t0 then
                t0 = ta
            end

            if tb < t1 then
                t1 = tb
            end

            if t0 > t1 then
                return
            end
        end

        if ddy == 0 then
            if py1 < -limit or py1 > limit then
                return
            end
        else
            local ta = (-limit - py1) / ddy
            local tb = (limit - py1) / ddy

            if ta > tb then
                ta, tb = tb, ta
            end

            if ta > t0 then
                t0 = ta
            end

            if tb < t1 then
                t1 = tb
            end

            if t0 > t1 then
                return
            end
        end
    end

    local nx1 = px1 + ddx * t0
    local ny1 = py1 + ddy * t0
    local nx2 = px1 + ddx * t1
    local ny2 = py1 + ddy * t1

    local ui_scale = view.ui_scale
    local screen_center_x = view.screen_center_x
    local screen_center_y = view.screen_center_y
    local sx1 = screen_center_x + nx1 * ui_scale
    local sy1 = screen_center_y + ny1 * ui_scale
    local sx2 = screen_center_x + nx2 * ui_scale
    local sy2 = screen_center_y + ny2 * ui_scale

    local sdx = sx2 - sx1
    local sdy = sy2 - sy1
    local length_sq = sdx * sdx + sdy * sdy

    if not (length_sq > MIN_SEGMENT_SCREEN_LENGTH_SQ) then
        return
    end

    local length = math_sqrt(length_sq)

    local half = half_w * ui_scale
    local nxo = -sdy / length * half
    local nyo = sdx / length * half
    local gui = view.gui
    local period = view.dash_period_m

    if line_style ~= LINE_DASHED or period <= 0 then
        _submit_quad(gui, sx1, sy1, sx2, sy2, nxo, nyo, layer, color)

        return
    end

    local screen_px_per_m = view.screen_px_per_m
    local world_length = length / ((t1 - t0) * screen_px_per_m)
    local inverse_world_length = 1 / world_length
    local wdx = wx2 - wx1
    local wdy = wy2 - wy1
    local start_x = wx1
    local start_y = wy1
    local u0 = t0
    local u1 = t1
    local origin_x = screen_center_x + px1 * ui_scale
    local origin_y = screen_center_y + py1 * ui_scale
    local delta_x = ddx * ui_scale
    local delta_y = ddy * ui_scale

    if wdx < 0 or (wdx == 0 and wdy < 0) then
        wdx = -wdx
        wdy = -wdy
        start_x = wx2
        start_y = wy2
        u0 = 1 - t1
        u1 = 1 - t0
        origin_x = origin_x + delta_x
        origin_y = origin_y + delta_y
        delta_x = -delta_x
        delta_y = -delta_y
    end

    local along = (start_x * wdx + start_y * wdy) * inverse_world_length
    local on_fraction = view.dash_on_m * inverse_world_length
    local min_fraction = MIN_DASH_SCREEN_LENGTH / (world_length * screen_px_per_m)
    local k = math_floor((along + u0 * world_length) / period)
    local f0 = (k * period - along) * inverse_world_length

    while f0 < u1 do
        local f1 = f0 + on_fraction

        if f0 < u0 then
            f0 = u0
        end

        if f1 > u1 then
            f1 = u1
        end

        if f1 - f0 >= min_fraction then
            _submit_quad(gui, origin_x + delta_x * f0, origin_y + delta_y * f0, origin_x + delta_x * f1,
                origin_y + delta_y * f1, nxo, nyo, layer, color)
        end

        k = k + 1
        f0 = (k * period - along) * inverse_world_length
    end
end

--- Sorts one vector layer's segments within the cull square into the class lists of `_bins`.
-- Contours split into below, above and current-band walls and hatches into below and above by
-- floor band, slope marks keep only the current band and stair ticks only those within
-- `STAIR_FLOOR_RANGE` of the floor reference; everything outside the floor range is dropped.
-- Each segment is visited at most once per frame, and indices `dead` lists are skipped.
-- tab: layer_data layer index
-- int: mode `MODE_CONTOURS`, `MODE_STAIRS`, `MODE_HATCHES` or `MODE_SLOPES`
-- ?tab: dead set of contour indices that are no longer walls
-- treturn: int number of segments listed below
-- treturn: int number of segments listed above
-- treturn: int number of segments listed for the current floor
local function _select_layer(layer_data, mode, dead)
    local count = layer_data.count

    if count <= 0 then
        return 0, 0, 0
    end

    local view = _view
    local bins = _bins
    local style = _style
    local segments = layer_data.segments
    local stride = layer_data.stride
    local z_last = layer_data.z_last
    local cells = layer_data.cells
    local stamp = layer_data.stamp
    local keep = layer_data.keep
    local frame_id = view.vector_frame_id
    local ref_z = view.ref_z
    local range_above = view.range_above
    local range_below = view.range_below
    local reach = CURRENT_FLOOR_HALF_HEIGHT
    local below_list = nil
    local above_list = nil
    local current_list = nil

    if mode == MODE_CONTOURS then
        below_list = style.contour_below and bins.below_contours or nil
        above_list = style.contour_above and bins.above_contours or nil
        current_list = style.contour_current and bins.walls or nil
    elseif mode == MODE_HATCHES then
        below_list = style.hatch_below and bins.below_hatches or nil
        above_list = style.hatch_above and bins.above_hatches or nil
    elseif mode == MODE_SLOPES then
        current_list = style.slope and bins.slopes or nil
    else
        current_list = style.stair and bins.stairs or nil
        reach = STAIR_FLOOR_RANGE
    end

    local below_n = 0
    local above_n = 0
    local current_n = 0

    local min_cx = view.min_cx
    local max_cx = view.max_cx
    local min_cy = view.min_cy
    local max_cy = view.max_cy

    if layer_data.min_cx > min_cx then
        min_cx = layer_data.min_cx
    end

    if layer_data.max_cx < max_cx then
        max_cx = layer_data.max_cx
    end

    if layer_data.min_cy > min_cy then
        min_cy = layer_data.min_cy
    end

    if layer_data.max_cy < max_cy then
        max_cy = layer_data.max_cy
    end

    for cx = min_cx, max_cx do
        local row_key = (cx + GRID_CELL_HASH_OFFSET) * GRID_CELL_HASH_STRIDE

        for cy = min_cy, max_cy do
            local bucket = cells[row_key + cy + GRID_CELL_HASH_OFFSET]

            if bucket then
                for bucket_index = 1, #bucket do
                    local i = bucket[bucket_index]

                    if stamp[i] ~= frame_id and (keep == nil or keep[i]) and not (dead and dead[i]) then
                        stamp[i] = frame_id

                        local dz

                        if z_last then
                            dz = segments[i * stride] - ref_z
                        else
                            local base = (i - 1) * stride

                            dz = (segments[base + 5] + segments[base + 6]) * 0.5 - ref_z
                        end

                        if dz <= range_above and dz >= -range_below then
                            if dz > reach then
                                if above_list then
                                    above_n = above_n + 1
                                    above_list[above_n] = i
                                end
                            elseif dz < -reach then
                                if below_list then
                                    below_n = below_n + 1
                                    below_list[below_n] = i
                                end
                            elseif current_list then
                                current_n = current_n + 1
                                current_list[current_n] = i
                            end
                        end
                    end
                end
            end
        end
    end

    return below_n, above_n, current_n
end

--- Derives this frame's line colours and dash period and sorts the vector segments in range into `_bins`.
-- Rebuilds the vector indices first when the context or revision changed. Runs inside `pcall`
-- from `RadarStrikemapGeometry.draw` after `_select_geometry` set the frame up.
-- tab: vector_context validated vector context
-- tab: counts record count per layer
-- param: revision geometry revision
local function _select_vectors(vector_context, counts, revision)
    local bins = _bins

    bins.below_hatches_n = 0
    bins.below_contours_n = 0
    bins.above_hatches_n = 0
    bins.above_contours_n = 0
    bins.slopes_n = 0
    bins.walls_n = 0
    bins.stairs_n = 0

    _ensure_vectors(vector_context, counts, revision)

    local vectors = _vectors

    if vectors.context == nil or vectors.cell_count == 0 then
        return
    end

    local raw_current = _band_raw_color("radar_navmesh", BAND_CURRENT_FALLBACK_COLOR)
    local raw_above = _band_raw_color("radar_navmesh_above", BAND_ABOVE_FALLBACK_COLOR)
    local raw_below = _band_raw_color("radar_navmesh_below", BAND_BELOW_FALLBACK_COLOR)

    local style = _style

    style.contour_current = _line_color(raw_current, CONTOUR_CURRENT_ALPHA_MULT, CONTOUR_CURRENT_BRIGHTEN)
    style.contour_above = _line_color(raw_above, CONTOUR_ABOVE_ALPHA_MULT, CONTOUR_ABOVE_BRIGHTEN)
    style.contour_below = _line_color(raw_below, CONTOUR_BELOW_ALPHA_MULT, CONTOUR_BELOW_BRIGHTEN)
    style.stair = _line_color(raw_current, STAIR_ALPHA_MULT, STAIR_BRIGHTEN)
    style.hatch_below = _line_color(raw_below, HATCH_ALPHA_MULT, 0)
    style.hatch_above = mod:get("strikemap_hatch_above") == true
        and _line_color(raw_above, HATCH_ALPHA_MULT, 0) or nil
    style.slope = _line_color(raw_current, SLOPE_ALPHA_MULT, SLOPE_BRIGHTEN)

    if not (style.contour_current or style.contour_above or style.contour_below or style.stair
            or style.hatch_below or style.hatch_above or style.slope) then
        return
    end

    local view = _view
    local frame_id = vectors.frame_id + 1
    vectors.frame_id = frame_id
    view.vector_frame_id = frame_id

    view.min_cx = math_floor(view.cull_min_x * VECTOR_INVERSE_GRID_CELL)
    view.max_cx = math_floor(view.cull_max_x * VECTOR_INVERSE_GRID_CELL)
    view.min_cy = math_floor(view.cull_min_y * VECTOR_INVERSE_GRID_CELL)
    view.max_cy = math_floor(view.cull_max_y * VECTOR_INVERSE_GRID_CELL)

    local dash_period = 2 ^ math_ceil(math_log(DASH_PERIOD_PX / view.radar_scale) * INVERSE_LN2 - 1e-9)

    if not (dash_period > 0 and dash_period < math_huge) then
        dash_period = 0
    end

    view.dash_period_m = dash_period
    view.dash_on_m = dash_period * DASH_ON_FRACTION

    if style.contour_current or style.contour_above or style.contour_below then
        bins.below_contours_n, bins.above_contours_n, bins.walls_n =
            _select_layer(vectors.contours, MODE_CONTOURS, vector_context.dead_contours)
    end

    if style.hatch_below or style.hatch_above then
        bins.below_hatches_n, bins.above_hatches_n = _select_layer(vectors.hatches, MODE_HATCHES, nil)
    end

    if style.slope then
        local _, _, slope_n = _select_layer(vectors.slopes, MODE_SLOPES, nil)

        bins.slopes_n = slope_n
    end

    if style.stair then
        local _, _, stair_n = _select_layer(vectors.stairs, MODE_STAIRS, nil)

        bins.stairs_n = stair_n
    end
end

--- Draws one class list of vector segments in one style.
-- tab: indices segment indices
-- int: count number of indices
-- tab: layer_data vector layer index the indices point into
-- int: layer GUI layer
-- param: color engine `Color`
-- number: half_w half line width in unscaled pixels
-- int: line_style `LINE_SOLID`, `LINE_WALL` or `LINE_DASHED`
local function _draw_segments(indices, count, layer_data, layer, color, half_w, line_style)
    local segments = layer_data.segments
    local stride = layer_data.stride
    local emit_line = _emit_line

    for k = 1, count do
        local base = (indices[k] - 1) * stride

        emit_line(segments[base + 1], segments[base + 2], segments[base + 3], segments[base + 4], layer, color,
            half_w, line_style)
    end
end

--- Draws the hatching and dashed outlines of the floors below on the geometry layer, before the current floor's fill.
-- Runs inside `pcall` after `_select_vectors`.
local function _draw_lower_vectors()
    local bins = _bins
    local style = _style
    local layer = _view.layer

    if bins.below_hatches_n > 0 then
        _draw_segments(bins.below_hatches, bins.below_hatches_n, _vectors.hatches, layer, style.hatch_below,
            HATCH_HALF_WIDTH, LINE_SOLID)
    end

    if bins.below_contours_n > 0 then
        _draw_segments(bins.below_contours, bins.below_contours_n, _vectors.contours, layer, style.contour_below,
            CONTOUR_BELOW_HALF_WIDTH, LINE_DASHED)
    end
end

--- Draws the vector details above the fills.
-- One layer up go the hatching of the floors above and the current floor's slope marks, two
-- layers up the thin outlines of the floors above, then the current floor's walls and stair
-- ticks over them. Runs inside `pcall` after `_draw_upper_fills`.
local function _draw_upper_vectors()
    local bins = _bins
    local style = _style
    local vectors = _vectors
    local marks_layer = _view.layer + 1
    local lines_layer = _view.layer + 2

    if bins.above_hatches_n > 0 then
        _draw_segments(bins.above_hatches, bins.above_hatches_n, vectors.hatches, marks_layer, style.hatch_above,
            HATCH_HALF_WIDTH, LINE_SOLID)
    end

    if bins.slopes_n > 0 then
        _draw_segments(bins.slopes, bins.slopes_n, vectors.slopes, marks_layer, style.slope, SLOPE_HALF_WIDTH,
            LINE_DASHED)
    end

    if bins.above_contours_n > 0 then
        _draw_segments(bins.above_contours, bins.above_contours_n, vectors.contours, lines_layer, style.contour_above,
            CONTOUR_ABOVE_HALF_WIDTH, LINE_SOLID)
    end

    if bins.walls_n > 0 then
        _draw_segments(bins.walls, bins.walls_n, vectors.contours, lines_layer, style.contour_current,
            CONTOUR_CURRENT_HALF_WIDTH, LINE_WALL)
    end

    if bins.stairs_n > 0 then
        _draw_segments(bins.stairs, bins.stairs_n, vectors.stairs, lines_layer, style.stair, STAIR_HALF_WIDTH,
            LINE_SOLID)
    end
end

--- Logs the geometry and vector counts once per map context and revision, in debug mode.
local function _log_revision_diagnostics(context, vector_context, counts, revision)
    if _diag_context == context and _diag_revision == revision then
        return
    end

    _diag_context = context
    _diag_revision = revision

    local api_version = StrikemapCompatibility.get_api_version and StrikemapCompatibility:get_api_version() or nil
    local contour_layer = _vectors.contours

    mod:info(string_format(
        "[Radar] Strikemap geometry revision | api=%s map=%s revision=%s triangles=%d vector=%s contours=%d dead=%d stairs=%d hatches=%d slopes=%d vector_cells=%d",
        tostring(api_version),
        tostring(context.map_id or context.mission_name),
        tostring(revision),
        _grid.tri_count,
        vector_context ~= nil and "yes" or "no",
        counts and counts.contours or 0,
        contour_layer and contour_layer.skipped or 0,
        counts and counts.stairs or 0,
        counts and counts.hatches or 0,
        counts and counts.slopes or 0,
        _vectors.cell_count))
end

-- ----------------------------------------------------------------------------
-- Interface
-- ----------------------------------------------------------------------------

--- Module interface consumed by `ui/Radar_hud_element.lua`.
local RadarStrikemapGeometry = {}

--- Returns whether the Strikemap layer has a map to draw this frame.
-- False when triangle rendering is unsupported, or in overview mode when the layer is
-- disabled there. Otherwise asks the compatibility module, which also refreshes the context.
-- ?number: t gameplay time
-- treturn: bool
RadarStrikemapGeometry.is_active = function(t)
    if _triangle_supported == false then
        return false
    end

    if mod:is_overview_mode_active() and mod:get("strikemap_geometry_in_overview") == false then
        return false
    end

    return StrikemapCompatibility:get_map_context(t) ~= nil
end

--- Draws the Strikemap map layer for one frame.
-- Probes triangle support on first use and marks the integration unsupported when it is
-- missing. The frame runs in four protected steps -- selecting the triangles and drawing the
-- floors below, selecting the vector segments and drawing the lower floors' details, drawing
-- the current floor and the floors above, and drawing the remaining details. Triangle errors
-- put the integration into its `error` status; vector errors only disable vectors for the
-- current revision, and a frame whose vector selection failed draws no later vectors.
-- tab: ui_renderer active UI renderer
-- tab: snapshot radar snapshot providing `player_position` and `player_revision`
-- number: center_x radar centre x in unscaled UI pixels
-- number: center_y radar centre y in unscaled UI pixels
-- number: z layer offset above the pass start layer
-- number: projection_radius radar radius in unscaled UI pixels
-- number: range radar range in metres
-- ?Quaternion: rotation camera rotation
-- string: radar_style radar style
-- ?number: t gameplay time
RadarStrikemapGeometry.draw = function(ui_renderer, snapshot, center_x, center_y, z, projection_radius, range,
                                       rotation, radar_style, t)
    local player_pos = snapshot and snapshot.player_position or nil

    if not player_pos then
        return
    end

    if mod:is_overview_mode_active() and mod:get("strikemap_geometry_in_overview") == false then
        return
    end

    local context, vector_context, revision, vector_counts = StrikemapCompatibility:get_geometry_contexts(t)

    if not context then
        return
    end

    local gui = ui_renderer and ui_renderer.gui

    if not gui then
        return
    end

    if _triangle_supported == nil then
        _triangle_supported = _probe_triangle(gui)

        if not _triangle_supported then
            StrikemapCompatibility:mark_unsupported("triangle rendering is unavailable in this game build")
        end
    end

    if not _triangle_supported then
        return
    end

    range = tonumber(range)
    projection_radius = tonumber(projection_radius)

    if not range or range <= 0 or not projection_radius or projection_radius <= 0 then
        return
    end

    if (vector_context == nil or vector_counts == nil) and _vectors.context ~= nil then
        _reset_vectors()
    end

    local ok, err = pcall(_select_geometry, ui_renderer, context, revision, player_pos, snapshot.player_revision,
        rotation, center_x, center_y, z, projection_radius, range, radar_style, t)

    if not ok then
        StrikemapCompatibility:mark_error(err)

        return
    end

    if _view.ready then
        local vectors_ok = vector_context ~= nil and vector_counts ~= nil
            and mod:get("strikemap_vector_details") ~= false
        local vector_err = nil

        if vectors_ok then
            vectors_ok, vector_err = pcall(_select_vectors, vector_context, vector_counts, revision)

            if vectors_ok then
                vectors_ok, vector_err = pcall(_draw_lower_vectors)
            end

            if not vectors_ok then
                _reset_vectors()
                StrikemapCompatibility:mark_vector_error(vector_err)
            end
        end

        ok, err = pcall(_draw_upper_fills)

        if not ok then
            StrikemapCompatibility:mark_error(err)

            return
        end

        if vectors_ok then
            vectors_ok, vector_err = pcall(_draw_upper_vectors)

            if not vectors_ok then
                _reset_vectors()
                StrikemapCompatibility:mark_vector_error(vector_err)
            end
        end
    end

    if mod:get("debug_mode") == true then
        _log_revision_diagnostics(context, vector_context, vector_counts, revision)
    end
end

--- Drops every cached grid, floor reference, selection and diagnostic state; called by `StrikemapCompatibility:reset`.
mod._strikemap_geometry_renderer_reset = function()
    _reset_grid()
    _reset_vectors()
    _reset_floor()
    _reset_bins()
    _diag_context = nil
    _diag_revision = nil
end

return RadarStrikemapGeometry
