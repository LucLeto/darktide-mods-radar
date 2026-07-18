local mod = get_mod("Radar")
local StrikemapCompatibility = mod:io_dofile("Radar/scripts/mods/Radar/compatibility/Radar_strikemap")

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
local GRID_CELL_HASH_OFFSET = 4096
local GRID_CELL_HASH_STRIDE = 8192
local MAX_TRIANGLE_DRAWS_PER_FRAME = 3000
local CULL_RANGE_FACTOR = 1.4143

local _grid = {
    context = nil,
    triangles = nil,
    tri_count = 0,
    inverse_grid_cell = 1 / 16,
    cells = {},
    stamp = {},
    frame_id = 0,
    min_cx = 0,
    max_cx = -1,
    min_cy = 0,
    max_cy = -1,
    draw_cap_logged = false,
}

local function _reset_grid()
    _grid.context = nil
    _grid.triangles = nil
    _grid.tri_count = 0
    _grid.inverse_grid_cell = 1 / 16
    _grid.cells = {}
    _grid.stamp = {}
    _grid.frame_id = 0
    _grid.min_cx = 0
    _grid.max_cx = -1
    _grid.min_cy = 0
    _grid.max_cy = -1
    _grid.draw_cap_logged = false
end

mod._strikemap_geometry_renderer_reset = _reset_grid

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

local function _build_grid(context)
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

    local cells = {}
    local stamp = {}
    local cell_count = 0
    local grid_min_cx = math_huge
    local grid_max_cx = -math_huge
    local grid_min_cy = math_huge
    local grid_max_cy = -math_huge

    for i = 1, tri_count do
        stamp[i] = 0
    end

    for key, packed in pairs(spatial_index) do
        local gx, gy = string_match(tostring(key), "^(-?%d+):(-?%d+)$")

        gx = tonumber(gx)
        gy = tonumber(gy)

        if gx and gy and type(packed) == "string" then
            local bucket = nil

            for token in string_gmatch(packed, "[^,]+") do
                local index = tonumber(token)

                if index and index >= 1 and index <= tri_count then
                    if not bucket then
                        bucket = {}
                    end

                    bucket[#bucket + 1] = index
                end
            end

            if bucket then
                cells[(gx + GRID_CELL_HASH_OFFSET) * GRID_CELL_HASH_STRIDE + gy + GRID_CELL_HASH_OFFSET] = bucket
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
    end

    if cell_count == 0 then
        error("the Strikemap spatial index is empty or malformed")
    end

    _grid.context = context
    _grid.triangles = triangles
    _grid.tri_count = tri_count
    _grid.inverse_grid_cell = 1 / grid_cell
    _grid.cells = cells
    _grid.stamp = stamp
    _grid.frame_id = 0
    _grid.min_cx = grid_min_cx
    _grid.max_cx = grid_max_cx
    _grid.min_cy = grid_min_cy
    _grid.max_cy = grid_max_cy
    _grid.draw_cap_logged = false

    if mod:get("debug_mode") == true then
        mod:info(string_format("[Radar] Strikemap geometry grid parsed | map=%s triangles=%d cells=%d",
            tostring(context.map_id or context.mission_name), tri_count, cell_count))
    end
end

local function _ensure_grid(context)
    if _grid.context ~= context then
        _build_grid(context)
    end
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

local function _band_color(prefix, fallback)
    local get_radar_color = mod.get_radar_color
    local color = get_radar_color and get_radar_color(mod, prefix, fallback) or fallback
    local alpha = tonumber(color[1]) or 0

    if alpha <= 0 then
        return nil
    end

    return Color(alpha, color[2] or 255, color[3] or 255, color[4] or 255)
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

local function _draw_geometry(ui_renderer, context, player_pos, rotation, center_x, center_y, z, projection_radius,
                              range, radar_style)
    local current_color = _band_color("radar_navmesh", BAND_CURRENT_FALLBACK_COLOR)
    local above_color = _band_color("radar_navmesh_above", BAND_ABOVE_FALLBACK_COLOR)
    local below_color = _band_color("radar_navmesh_below", BAND_BELOW_FALLBACK_COLOR)

    if not current_color and not above_color and not below_color then
        return
    end

    local range_above = _clamp_band_range(mod:get("navmesh_range_above"), DEFAULT_RANGE_ABOVE)
    local range_below = _clamp_band_range(mod:get("navmesh_range_below"), DEFAULT_RANGE_BELOW)

    _ensure_grid(context)

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
    local draws = 0

    for cx = min_cx, max_cx do
        local row_key = (cx + GRID_CELL_HASH_OFFSET) * GRID_CELL_HASH_STRIDE

        for cy = min_cy, max_cy do
            local bucket = cells[row_key + cy + GRID_CELL_HASH_OFFSET]

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
                                    if px1 * px1 + py1 * py1 <= limit_sq
                                        and px2 * px2 + py2 * py2 <= limit_sq
                                        and px3 * px3 + py3 * py3 <= limit_sq then
                                        _submit_triangle(gui,
                                            screen_center_x + px1 * scale, screen_center_y + py1 * scale,
                                            screen_center_x + px2 * scale, screen_center_y + py2 * scale,
                                            screen_center_x + px3 * scale, screen_center_y + py3 * scale,
                                            layer, color)
                                        draws = draws + 1
                                    end
                                elseif px1 >= -limit and px1 <= limit and py1 >= -limit and py1 <= limit
                                    and px2 >= -limit and px2 <= limit and py2 >= -limit and py2 <= limit
                                    and px3 >= -limit and px3 <= limit and py3 >= -limit and py3 <= limit then
                                    _submit_triangle(gui,
                                        screen_center_x + px1 * scale, screen_center_y + py1 * scale,
                                        screen_center_x + px2 * scale, screen_center_y + py2 * scale,
                                        screen_center_x + px3 * scale, screen_center_y + py3 * scale,
                                        layer, color)
                                    draws = draws + 1
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
                                            draws = draws + 1
                                        end
                                    end
                                end

                                if draws >= MAX_TRIANGLE_DRAWS_PER_FRAME then
                                    if not _grid.draw_cap_logged and mod:get("debug_mode") == true then
                                        _grid.draw_cap_logged = true
                                        mod:info(string_format(
                                            "[Radar] Strikemap geometry draw cap reached | cap=%d",
                                            MAX_TRIANGLE_DRAWS_PER_FRAME))
                                    end

                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
    end
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

    local context = StrikemapCompatibility:get_map_context(t)

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

    local ok, err = pcall(_draw_geometry, ui_renderer, context, player_pos, rotation, center_x, center_y, z,
        projection_radius, range, radar_style)

    if not ok then
        StrikemapCompatibility:mark_error(err)
    end
end

return RadarStrikemapGeometry
