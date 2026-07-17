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

-- Strikemap compatibility API v1 geometry layout (see COMPATIBILITY_API.txt):
-- context.triangles is a flat number array with 7 numbers per triangle
-- (x1, y1, x2, y2, x3, y3, z) in Z-up world metres; the three vertices share
-- one floor height z. context.spatial_index maps "gx:gy" cell keys
-- (gx = floor(world_x / context.grid_cell)) to comma-separated strings of
-- 1-based triangle indices. All context tables are read-only; the parsed
-- index below is cached on Radar's side only.
local TRIANGLE_STRIDE = 7
local DEFAULT_GEOMETRY_WIDGET_COLOR = { 255, 130, 190, 130 }
local DEFAULT_CURRENT_FLOOR_ALPHA = 110
local DEFAULT_OTHER_FLOOR_ALPHA = 45
local CURRENT_FLOOR_HALF_HEIGHT = 2.5
local GRID_CELL_HASH_OFFSET = 4096
local GRID_CELL_HASH_STRIDE = 8192
-- Safety valve for very large maps at overview zoom ranges; geometry beyond
-- the cap is skipped for the frame instead of stalling the draw pass.
local MAX_TRIANGLE_DRAWS_PER_FRAME = 3000
-- Points on the square radar edge can be up to range * sqrt(2) world meters
-- away once camera rotation is applied.
local CULL_RANGE_FACTOR = 1.4143

-- Mission geometry is static, so Strikemap's packed spatial index is parsed
-- once per map context into numeric-keyed buckets and reused every frame
-- without further allocations. Triangle coordinates are read directly from
-- the (read-only) context array.
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

    -- Parse Strikemap's packed "gx:gy" -> "1,5,9" index into Radar-side
    -- buckets; the context itself must never be written to.
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
    -- Strikemap returns the same context table for the whole mission and
    -- bumps geometry_revision (handled in the compatibility module) when it
    -- changes, so identity is a sufficient rebuild trigger.
    if _grid.context ~= context then
        _build_grid(context)
    end
end

-- Sutherland-Hodgman clipping against the square [-limit, limit]^2 using
-- reused scratch buffers, so edge triangles never allocate per frame.
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

    -- The final polygon ends up back in _poly_ax/_poly_ay.
    return count
end

-- Darktide's screen-space Gui.triangle takes three Vector3 points plus a
-- separate integer sort layer. A 2D screen point (x, y) maps to
-- Vector3(x, 0, y): the vertical screen axis lives in the Z component, NOT Y,
-- and depth comes from the layer argument (unlike Gui.rect, which packs depth
-- into the point's Z). This mirrors Strikemap's own verified in-game geometry
-- rendering exactly. Probe the call once, guarded, and disable safely if the
-- engine build does not expose it.
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

local function _floor_alpha(setting_id, default_value)
    local value = tonumber(mod:get(setting_id))

    if value == nil then
        value = default_value
    end

    if value < 0 then
        value = 0
    elseif value > 255 then
        value = 255
    end

    return math_floor(value + 0.5)
end

local function _geometry_base_color(context)
    local color = context.color

    if type(color) == "table" then
        local r = tonumber(color[2] or color.r)
        local g = tonumber(color[3] or color.g)
        local b = tonumber(color[4] or color.b)

        if r and g and b then
            return r, g, b
        end
    end

    return DEFAULT_GEOMETRY_WIDGET_COLOR[2], DEFAULT_GEOMETRY_WIDGET_COLOR[3], DEFAULT_GEOMETRY_WIDGET_COLOR[4]
end

local function _draw_geometry(ui_renderer, context, player_pos, rotation, center_x, center_y, z, projection_radius,
                              range, radar_style)
    local current_alpha = _floor_alpha("strikemap_geometry_current_floor_opacity", DEFAULT_CURRENT_FLOOR_ALPHA)
    local other_alpha = _floor_alpha("strikemap_geometry_other_floor_opacity", DEFAULT_OTHER_FLOOR_ALPHA)

    if current_alpha <= 0 and other_alpha <= 0 then
        return
    end

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

    local base_r, base_g, base_b = _geometry_base_color(context)
    local current_color = current_alpha > 0 and Color(current_alpha, base_r, base_g, base_b) or nil
    local other_color = other_alpha > 0 and Color(other_alpha, base_r, base_g, base_b) or nil

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
                            local color = (dz >= -CURRENT_FLOOR_HALF_HEIGHT and dz <= CURRENT_FLOOR_HALF_HEIGHT)
                                and current_color or other_color

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

-- True when this layer will draw this frame: the map-geometry source selects
-- Strikemap ("strikemap" or "auto"), the layer is allowed in the current view,
-- and a validated map context is available. The hud element uses this to give
-- the single geometry slot to exactly one layer; in "auto" the live navmesh
-- takes over whenever this returns false. get_map_context() handles the
-- disabled state, retries and sticky failures internally and is cheap when
-- cached, so this is safe to call every frame.
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
