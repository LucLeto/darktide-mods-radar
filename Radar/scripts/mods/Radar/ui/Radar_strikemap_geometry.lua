local mod = get_mod("Radar")
local StrikemapCompatibility = mod:io_dofile("Radar/scripts/mods/Radar/compatibility/Radar_strikemap")
local _clip_and_emit = mod:io_dofile("Radar/scripts/mods/Radar/ui/Radar_triangle_clipper")

local Color = Color
local Gui = Gui
local Quaternion = Quaternion
local Vector2 = Vector2
local Vector3 = Vector3
local pairs = pairs
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
local string_gmatch = string.gmatch
local string_match = string.match

local Gui_triangle = Gui and Gui.triangle
local Quaternion_forward = Quaternion and Quaternion.forward
local Vector3_x = Vector3 and Vector3.x
local Vector3_y = Vector3 and Vector3.y

local TRIANGLE_STRIDE = 7
local CURRENT_FLOOR_HALF_HEIGHT = 2.5
local BAND_CURRENT_FALLBACK_COLOR = { 80, 101, 133, 96 }
local BAND_ABOVE_FALLBACK_COLOR = { 32, 120, 150, 185 }
local BAND_BELOW_FALLBACK_COLOR = { 55, 120, 98, 76 }
local DEFAULT_RANGE_ABOVE = 3
local DEFAULT_RANGE_BELOW = 7
local OVERVIEW_RANGE = 30
local GRID_CELL_HASH_OFFSET = 4096
local GRID_CELL_HASH_STRIDE = 8192
local CULL_RANGE_FACTOR = 1.4143

local CONTOUR_STRIDE = 5
local STAIR_STRIDE = 6
local HATCH_STRIDE = 5
local SLOPE_STRIDE = 5
local TRANSITION_STRIDE = 4
local VECTOR_GRID_CELL = 16
local VECTOR_INVERSE_GRID_CELL = 1 / VECTOR_GRID_CELL
local MIN_SEGMENT_SCREEN_LENGTH_SQ = 1e-12
local DASH_ON_PX = 4
local DASH_PERIOD_PX = 7
local STAIR_ASSOC_RADIUS_SQ = 10 * 10
local CHAIN_Z_SLACK = 2
local STEEP_CHAIN_MIN_STEEPNESS = 0.5
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
local SLOPE_ALPHA_MULT = 1.3
local SLOPE_BRIGHTEN = 0.2

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

local _view = {}
local _style = {}

local _diag_context = nil
local _diag_revision = nil

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

mod._strikemap_geometry_renderer_reset = function()
    _reset_grid()
    _reset_vectors()
    _diag_context = nil
    _diag_revision = nil
end

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

local function _ensure_grid(context, revision)
    if _grid.context ~= context or _grid.revision ~= revision then
        _build_grid(context, revision)
    end
end

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

local _poly_ax, _poly_ay = {}, {}
local _poly_bx, _poly_by = {}, {}

local function _clip_edge(src_x, src_y, src_count, dst_x, dst_y, edge, limit)
    local count = 0
    local prev_x = src_x[src_count]
    local prev_y = src_y[src_count]
    local prev_inside

    if edge == 1 then
        prev_inside = prev_x <= limit
    elseif edge == 2 then
        prev_inside = prev_x >= -limit
    elseif edge == 3 then
        prev_inside = prev_y <= limit
    else
        prev_inside = prev_y >= -limit
    end

    for i = 1, src_count do
        local x = src_x[i]
        local y = src_y[i]
        local inside

        if edge == 1 then
            inside = x <= limit
        elseif edge == 2 then
            inside = x >= -limit
        elseif edge == 3 then
            inside = y <= limit
        else
            inside = y >= -limit
        end

        if inside ~= prev_inside then
            local t

            if edge == 1 then
                t = (limit - prev_x) / (x - prev_x)
            elseif edge == 2 then
                t = (-limit - prev_x) / (x - prev_x)
            elseif edge == 3 then
                t = (limit - prev_y) / (y - prev_y)
            else
                t = (-limit - prev_y) / (y - prev_y)
            end

            count = count + 1
            dst_x[count] = prev_x + (x - prev_x) * t
            dst_y[count] = prev_y + (y - prev_y) * t
        end

        if inside then
            count = count + 1
            dst_x[count] = x
            dst_y[count] = y
        end

        prev_x = x
        prev_y = y
        prev_inside = inside
    end

    return count
end

local function _clip_triangle_to_square(px1, py1, px2, py2, px3, py3, limit)
    local ax, ay = _poly_ax, _poly_ay
    local bx, by = _poly_bx, _poly_by

    ax[1], ay[1] = px1, py1
    ax[2], ay[2] = px2, py2
    ax[3], ay[3] = px3, py3

    local count = 3

    count = _clip_edge(ax, ay, count, bx, by, 1, limit)
    if count < 3 then
        return 0
    end

    count = _clip_edge(bx, by, count, ax, ay, 2, limit)
    if count < 3 then
        return 0
    end

    count = _clip_edge(ax, ay, count, bx, by, 3, limit)
    if count < 3 then
        return 0
    end

    count = _clip_edge(bx, by, count, ax, ay, 4, limit)
    if count < 3 then
        return 0
    end

    return count
end

local _triangle_supported = nil

local function _probe_triangle(gui)
    if not Gui_triangle or not Vector3 then
        return false
    end

    local ok = pcall(Gui_triangle, gui,
        Vector3(-40, 0, -40), Vector3(-39, 0, -40), Vector3(-40, 0, -39), 0, Color(0, 0, 0, 0))

    return ok == true
end

local function _submit_triangle(gui, sx1, sy1, sx2, sy2, sx3, sy3, layer, color)
    Gui_triangle(
        gui,
        Vector3(sx1, 0, sy1),
        Vector3(sx2, 0, sy2),
        Vector3(sx3, 0, sy3),
        layer,
        color
    )
end

local function _band_raw_color(prefix, fallback)
    local get_radar_color = mod.get_radar_color

    return get_radar_color and get_radar_color(mod, prefix, fallback) or fallback
end

local function _band_color(prefix, fallback)
    local color = _band_raw_color(prefix, fallback)
    local alpha = tonumber(color[1]) or 0

    if alpha <= 0 then
        return nil
    end

    return Color(alpha, color[2] or 255, color[3] or 255, color[4] or 255)
end

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

local function _clamp_band_range(value, default_value)
    value = tonumber(value) or default_value

    if value < 1 then
        value = 1
    elseif value > 30 then
        value = 30
    end

    return value
end

local function _configured_ranges()
    if mod:is_overview_mode_active() then
        return OVERVIEW_RANGE, OVERVIEW_RANGE
    end

    return _clamp_band_range(mod:get("navmesh_range_above"), DEFAULT_RANGE_ABOVE),
        _clamp_band_range(mod:get("navmesh_range_below"), DEFAULT_RANGE_BELOW)
end

local function _draw_geometry(ui_renderer, context, revision, player_pos, rotation, center_x, center_y, z,
                              projection_radius, range, radar_style)
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

    local gui = ui_renderer.gui
    local scale = ui_renderer.scale or 1
    local render_settings = ui_renderer.render_settings
    local layer = (render_settings and render_settings.start_layer or 0) + z

    local ppx = player_pos.x
    local ppy = player_pos.y
    local ppz = player_pos.z or 0

    local forward_x, forward_y = _forward_xy(rotation)
    local right_x, right_y

    if forward_x and forward_y then
        right_x = forward_y
        right_y = -forward_x
    end

    local limit = projection_radius
    local limit_sq = limit * limit
    local radar_scale = limit / range
    local is_circle = radar_style == "circle"

    local triangles = _grid.triangles
    local cells = _grid.cells
    local stamp = _grid.stamp
    local frame_id = _grid.frame_id + 1
    _grid.frame_id = frame_id

    local cull_range = range * CULL_RANGE_FACTOR
    local inverse_grid_cell = _grid.inverse_grid_cell
    local min_cx = math_max(math_floor((ppx - cull_range) * inverse_grid_cell), _grid.min_cx)
    local max_cx = math_min(math_floor((ppx + cull_range) * inverse_grid_cell), _grid.max_cx)
    local min_cy = math_max(math_floor((ppy - cull_range) * inverse_grid_cell), _grid.min_cy)
    local max_cy = math_min(math_floor((ppy + cull_range) * inverse_grid_cell), _grid.max_cy)

    local screen_center_x = center_x * scale
    local screen_center_y = center_y * scale
    local clip_and_emit = _clip_and_emit

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

                        local base = (i - 1) * TRIANGLE_STRIDE
                        local px1, py1, px2, py2, px3, py3
                        local dx = triangles[base + 1] - ppx
                        local dy = triangles[base + 2] - ppy

                        if right_x then
                            px1 = (dx * right_x + dy * right_y) * radar_scale
                            py1 = -(dx * forward_x + dy * forward_y) * radar_scale
                            dx = triangles[base + 3] - ppx
                            dy = triangles[base + 4] - ppy
                            px2 = (dx * right_x + dy * right_y) * radar_scale
                            py2 = -(dx * forward_x + dy * forward_y) * radar_scale
                            dx = triangles[base + 5] - ppx
                            dy = triangles[base + 6] - ppy
                            px3 = (dx * right_x + dy * right_y) * radar_scale
                            py3 = -(dx * forward_x + dy * forward_y) * radar_scale
                        else
                            px1 = dx * radar_scale
                            py1 = -dy * radar_scale
                            dx = triangles[base + 3] - ppx
                            dy = triangles[base + 4] - ppy
                            px2 = dx * radar_scale
                            py2 = -dy * radar_scale
                            dx = triangles[base + 5] - ppx
                            dy = triangles[base + 6] - ppy
                            px3 = dx * radar_scale
                            py3 = -dy * radar_scale
                        end

                        if not ((px1 > limit and px2 > limit and px3 > limit)
                                or (px1 < -limit and px2 < -limit and px3 < -limit)
                                or (py1 > limit and py2 > limit and py3 > limit)
                                or (py1 < -limit and py2 < -limit and py3 < -limit)) then
                            local dz = triangles[base + 7] - ppz
                            local color = nil

                            if dz <= range_above and dz >= -range_below then
                                if dz > CURRENT_FLOOR_HALF_HEIGHT then
                                    color = above_color
                                elseif dz < -CURRENT_FLOOR_HALF_HEIGHT then
                                    color = below_color
                                else
                                    color = current_color
                                end
                            end

                            if color then
                                if is_circle then
                                    clip_and_emit(gui, layer, color, true, limit, limit_sq, scale,
                                        center_x, center_y, px1, py1, px2, py2, px3, py3)
                                elseif px1 >= -limit and px1 <= limit and py1 >= -limit and py1 <= limit
                                    and px2 >= -limit and px2 <= limit and py2 >= -limit and py2 <= limit
                                    and px3 >= -limit and px3 <= limit and py3 >= -limit and py3 <= limit then
                                    _submit_triangle(gui,
                                        screen_center_x + px1 * scale, screen_center_y + py1 * scale,
                                        screen_center_x + px2 * scale, screen_center_y + py2 * scale,
                                        screen_center_x + px3 * scale, screen_center_y + py3 * scale,
                                        layer, color)
                                else
                                    local clip_count = _clip_triangle_to_square(px1, py1, px2, py2, px3, py3, limit)

                                    if clip_count >= 3 then
                                        local ax, ay = _poly_ax, _poly_ay
                                        local fx = screen_center_x + ax[1] * scale
                                        local fy = screen_center_y + ay[1] * scale

                                        for k = 2, clip_count - 1 do
                                            _submit_triangle(gui, fx, fy,
                                                screen_center_x + ax[k] * scale, screen_center_y + ay[k] * scale,
                                                screen_center_x + ax[k + 1] * scale,
                                                screen_center_y + ay[k + 1] * scale,
                                                layer, color)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function _build_segment_index(segments, count, stride, z_last)
    local layer = {
        segments = segments,
        count = 0,
        stride = stride,
        z_last = z_last,
        cells = {},
        stamp = {},
        keep = nil,
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
    local layer_min_cx = math_huge
    local layer_max_cx = -math_huge
    local layer_min_cy = math_huge
    local layer_max_cy = -math_huge

    for i = 1, count do
        stamp[i] = 0

        local base = (i - 1) * stride
        -- Every vector record starts with x1, y1, x2, y2. Only the height fields differ by layer.
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

    if cell_count > 0 then
        layer.min_cx = layer_min_cx
        layer.max_cx = layer_max_cx
        layer.min_cy = layer_min_cy
        layer.max_cy = layer_max_cy
    end

    return layer, cell_count
end

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

local function _chain_allows_tick(chain, tick_z)
    if type(chain) ~= "table" then
        return true
    end

    if not _chain_is_steep(chain) then
        return false
    end

    local z_min = tonumber(chain.min_z or chain.z_min)
    local z_max = tonumber(chain.max_z or chain.z_max)

    if z_min and z_max then
        return tick_z >= z_min - CHAIN_Z_SLACK and tick_z <= z_max + CHAIN_Z_SLACK
    end

    return true
end

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

                        if dx * dx + dy * dy <= STAIR_ASSOC_RADIUS_SQ then
                            local chain = nil

                            if transition_chain ~= nil and chains ~= nil then
                                local chain_id = transition_chain[a]

                                if chain_id ~= nil then
                                    chain = chains[chain_id]
                                end
                            end

                            if _chain_allows_tick(chain, mz) then
                                keep_tick = true

                                break
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

local function _build_vectors(vector_context, counts, revision)
    _reset_vectors()

    local total_cells = 0
    local layer, cell_count

    layer, cell_count = _build_segment_index(vector_context.contours, counts.contours, CONTOUR_STRIDE, true)
    _vectors.contours = layer
    total_cells = total_cells + cell_count

    layer, cell_count = _build_segment_index(vector_context.stairs, counts.stairs, STAIR_STRIDE, false)
    _vectors.stairs = layer
    total_cells = total_cells + cell_count

    layer, cell_count = _build_segment_index(vector_context.hatches, counts.hatches, HATCH_STRIDE, true)
    _vectors.hatches = layer
    total_cells = total_cells + cell_count

    layer, cell_count = _build_segment_index(vector_context.slopes, counts.slopes, SLOPE_STRIDE, true)
    _vectors.slopes = layer
    total_cells = total_cells + cell_count

    _build_stair_filter(vector_context, counts, _vectors.stairs)

    _vectors.context = vector_context
    _vectors.revision = revision
    _vectors.cell_count = total_cells
end

local function _ensure_vectors(vector_context, counts, revision)
    if _vectors.context ~= vector_context or _vectors.revision ~= revision then
        _build_vectors(vector_context, counts, revision)
    end
end

local function _submit_quad(gui, ax, ay, bx, by, nx, ny, layer, color)
    Gui_triangle(
        gui,
        Vector3(ax + nx, 0, ay + ny),
        Vector3(bx + nx, 0, by + ny),
        Vector3(bx - nx, 0, by - ny),
        layer,
        color
    )
    Gui_triangle(
        gui,
        Vector3(ax + nx, 0, ay + ny),
        Vector3(bx - nx, 0, by - ny),
        Vector3(ax - nx, 0, ay - ny),
        layer,
        color
    )
end

local function _emit_line(wx1, wy1, wx2, wy2, layer, color, half_w, dashed)
    local view = _view
    local radar_scale = view.radar_scale
    local rx = view.rx
    local px1, py1, px2, py2
    local dx = wx1 - view.ppx
    local dy = wy1 - view.ppy

    if rx then
        local ry = view.ry
        local fx = view.fx
        local fy = view.fy

        px1 = (dx * rx + dy * ry) * radar_scale
        py1 = -(dx * fx + dy * fy) * radar_scale
        dx = wx2 - view.ppx
        dy = wy2 - view.ppy
        px2 = (dx * rx + dy * ry) * radar_scale
        py2 = -(dx * fx + dy * fy) * radar_scale
    else
        px1 = dx * radar_scale
        py1 = -dy * radar_scale
        dx = wx2 - view.ppx
        dy = wy2 - view.ppy
        px2 = dx * radar_scale
        py2 = -dy * radar_scale
    end

    local limit = view.limit

    if (px1 > limit and px2 > limit) or (px1 < -limit and px2 < -limit)
        or (py1 > limit and py2 > limit) or (py1 < -limit and py2 < -limit) then
        return
    end

    local ddx = px2 - px1
    local ddy = py2 - py1
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
    local sx1 = view.screen_center_x + nx1 * ui_scale
    local sy1 = view.screen_center_y + ny1 * ui_scale
    local sx2 = view.screen_center_x + nx2 * ui_scale
    local sy2 = view.screen_center_y + ny2 * ui_scale

    local sdx = sx2 - sx1
    local sdy = sy2 - sy1
    local length_sq = sdx * sdx + sdy * sdy

    if length_sq <= MIN_SEGMENT_SCREEN_LENGTH_SQ then
        return
    end

    local length = math_sqrt(length_sq)

    local half = half_w * ui_scale
    local nxo = -sdy / length * half
    local nyo = sdx / length * half
    local gui = view.gui

    if not dashed then
        _submit_quad(gui, sx1, sy1, sx2, sy2, nxo, nyo, layer, color)

        return
    end

    local period = DASH_PERIOD_PX * ui_scale
    local on_length = DASH_ON_PX * ui_scale
    local inverse_length = 1 / length
    local pos = 0

    while pos < length do
        local dash_end = pos + on_length

        if dash_end > length then
            dash_end = length
        end

        if dash_end - pos >= 0.5 then
            local f0 = pos * inverse_length
            local f1 = dash_end * inverse_length

            _submit_quad(gui, sx1 + sdx * f0, sy1 + sdy * f0, sx1 + sdx * f1, sy1 + sdy * f1, nxo, nyo, layer, color)
        end

        pos = pos + period
    end
end

local function _draw_layer(layer_data, mode, layer)
    local count = layer_data.count

    if count <= 0 then
        return
    end

    local view = _view
    local segments = layer_data.segments
    local stride = layer_data.stride
    local z_last = layer_data.z_last
    local cells = layer_data.cells
    local stamp = layer_data.stamp
    local keep = layer_data.keep
    local style = _style
    local frame_id = view.frame_id
    local ppz = view.ppz
    local range_above = view.range_above
    local range_below = view.range_below

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

                    if stamp[i] ~= frame_id and (keep == nil or keep[i]) then
                        stamp[i] = frame_id

                        local base = (i - 1) * stride
                        local x1 = segments[base + 1]
                        local y1 = segments[base + 2]
                        local x2 = segments[base + 3]
                        local y2 = segments[base + 4]
                        local dz

                        if z_last then
                            dz = segments[base + stride] - ppz
                        else
                            dz = (segments[base + 5] + segments[base + 6]) * 0.5 - ppz
                        end

                        local color, half_w, dashed

                        if mode == MODE_CONTOURS then
                            if dz >= -range_below and dz <= range_above then
                                if dz > CURRENT_FLOOR_HALF_HEIGHT then
                                    color = style.contour_above
                                    half_w = CONTOUR_ABOVE_HALF_WIDTH
                                elseif dz < -CURRENT_FLOOR_HALF_HEIGHT then
                                    color = style.contour_below
                                    half_w = CONTOUR_BELOW_HALF_WIDTH
                                    dashed = true
                                else
                                    color = style.contour_current
                                    half_w = CONTOUR_CURRENT_HALF_WIDTH
                                end
                            end
                        elseif mode == MODE_STAIRS then
                            if dz >= -range_below and dz <= range_above then
                                color = style.stair
                                half_w = STAIR_HALF_WIDTH
                            end
                        elseif mode == MODE_HATCHES then
                            if dz < -CURRENT_FLOOR_HALF_HEIGHT then
                                if dz >= -range_below then
                                    color = style.hatch_below
                                    half_w = HATCH_HALF_WIDTH
                                end
                            elseif dz > CURRENT_FLOOR_HALF_HEIGHT and dz <= range_above then
                                color = style.hatch_above
                                half_w = HATCH_HALF_WIDTH
                            end
                        else
                            if dz >= -range_below and dz <= range_above then
                                color = style.slope
                                half_w = SLOPE_HALF_WIDTH
                            end
                        end

                        if color then
                            _emit_line(x1, y1, x2, y2, layer, color, half_w, dashed)
                        end
                    end
                end
            end
        end
    end
end

local function _draw_vectors(ui_renderer, vector_context, counts, revision, player_pos, rotation, center_x, center_y,
                             z, projection_radius, range, radar_style)
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
    local scale = ui_renderer.scale or 1
    local render_settings = ui_renderer.render_settings
    local base_layer = (render_settings and render_settings.start_layer or 0) + z
    local ppx = player_pos.x
    local ppy = player_pos.y

    view.gui = ui_renderer.gui
    view.ui_scale = scale
    view.screen_center_x = center_x * scale
    view.screen_center_y = center_y * scale
    view.ppx = ppx
    view.ppy = ppy
    view.ppz = player_pos.z or 0

    local forward_x, forward_y = _forward_xy(rotation)

    if forward_x and forward_y then
        view.fx = forward_x
        view.fy = forward_y
        view.rx = forward_y
        view.ry = -forward_x
    else
        view.fx = nil
        view.fy = nil
        view.rx = nil
        view.ry = nil
    end

    view.limit = projection_radius
    view.limit_sq = projection_radius * projection_radius
    view.radar_scale = projection_radius / range
    view.is_circle = radar_style == "circle"
    view.range_above, view.range_below = _configured_ranges()

    local frame_id = vectors.frame_id + 1
    vectors.frame_id = frame_id
    view.frame_id = frame_id

    local cull_range = range * CULL_RANGE_FACTOR

    view.min_cx = math_floor((ppx - cull_range) * VECTOR_INVERSE_GRID_CELL)
    view.max_cx = math_floor((ppx + cull_range) * VECTOR_INVERSE_GRID_CELL)
    view.min_cy = math_floor((ppy - cull_range) * VECTOR_INVERSE_GRID_CELL)
    view.max_cy = math_floor((ppy + cull_range) * VECTOR_INVERSE_GRID_CELL)

    local lines_layer = base_layer + 2
    local marks_layer = base_layer + 1

    if style.contour_current or style.contour_above or style.contour_below then
        _draw_layer(vectors.contours, MODE_CONTOURS, lines_layer)
    end

    if style.stair then
        _draw_layer(vectors.stairs, MODE_STAIRS, lines_layer)
    end

    if style.slope then
        _draw_layer(vectors.slopes, MODE_SLOPES, marks_layer)
    end

    if style.hatch_below or style.hatch_above then
        _draw_layer(vectors.hatches, MODE_HATCHES, marks_layer)
    end
end

local function _log_revision_diagnostics(context, vector_context, counts, revision)
    if _diag_context == context and _diag_revision == revision then
        return
    end

    _diag_context = context
    _diag_revision = revision

    local api_version = StrikemapCompatibility.get_api_version and StrikemapCompatibility:get_api_version() or nil

    mod:info(string_format(
        "[Radar] Strikemap geometry revision | api=%s map=%s revision=%s triangles=%d vector=%s contours=%d stairs=%d hatches=%d slopes=%d vector_cells=%d",
        tostring(api_version),
        tostring(context.map_id or context.mission_name),
        tostring(revision),
        _grid.tri_count,
        vector_context ~= nil and "yes" or "no",
        counts and counts.contours or 0,
        counts and counts.stairs or 0,
        counts and counts.hatches or 0,
        counts and counts.slopes or 0,
        _vectors.cell_count))
end

local RadarStrikemapGeometry = {}

RadarStrikemapGeometry.is_active = function(t)
    if _triangle_supported == false then
        return false
    end

    if mod:is_overview_mode_active() and mod:get("strikemap_geometry_in_overview") == false then
        return false
    end

    return StrikemapCompatibility:get_map_context(t) ~= nil
end

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

    local ok, err = pcall(_draw_geometry, ui_renderer, context, revision, player_pos, rotation, center_x, center_y, z,
        projection_radius, range, radar_style)

    if not ok then
        StrikemapCompatibility:mark_error(err)

        return
    end

    if vector_context ~= nil and vector_counts ~= nil then
        if mod:get("strikemap_vector_details") ~= false then
            local ok_vectors, vector_err = pcall(_draw_vectors, ui_renderer, vector_context, vector_counts, revision,
                player_pos, rotation, center_x, center_y, z, projection_radius, range, radar_style)

            if not ok_vectors then
                _reset_vectors()
                StrikemapCompatibility:mark_vector_error(vector_err)
            end
        end
    elseif _vectors.context ~= nil then
        _reset_vectors()
    end

    if mod:get("debug_mode") == true then
        _log_revision_diagnostics(context, vector_context, vector_counts, revision)
    end
end

return RadarStrikemapGeometry
