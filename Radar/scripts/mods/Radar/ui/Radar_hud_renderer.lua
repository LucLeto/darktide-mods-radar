local mod = get_mod("Radar")
local UIWidget = require("scripts/managers/ui/ui_widget")

local Color = Color
local Gui = Gui
local Quaternion = Quaternion
local Vector2 = Vector2
local Vector3 = Vector3
local pcall = pcall
local rawget = rawget
local tonumber = tonumber
local tostring = tostring
local type = type
local math_abs = math.abs
local math_atan = math.atan
local math_clamp = math.clamp
local math_cos = math.cos
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_pi = math.pi
local math_rad = math.rad
local math_sin = math.sin
local math_sqrt = math.sqrt
local math_tan = math.tan
local math_huge = math.huge

local Gui_rect = Gui and Gui.rect
local Quaternion_yaw = Quaternion and Quaternion.yaw

local function _widget_color(a, r, g, b)
    return { a, r, g, b }
end

local function _color(a, r, g, b)
    return Color(a, r, g, b)
end

local WHITE_WIDGET_COLOR = { 255, 255, 255, 255 }
local RADAR_OUTLINE_WIDGET_COLOR = { 255, 213, 226, 206 }
local AUSPEX_BACKGROUND_MATERIAL = "content/ui/materials/backgrounds/scanner/scanner_map_background"
local AUSPEX_BACKGROUND_NOISE_MATERIAL = "content/ui/materials/backgrounds/scanner/scanner_background_noise"
local AUSPEX_SCAN_NOISE_MATERIAL = "content/ui/materials/backgrounds/scanner/scanner_noise"
local AUSPEX_SWEEP_MATERIAL = "content/ui/materials/backgrounds/scanner/scanner_map_radar"
local AUSPEX_BACKGROUND_WIDGET_COLOR = _widget_color(255, 0, 255, 0)
local AUSPEX_BACKGROUND_NOISE_WIDGET_COLOR = _widget_color(255, 0, 255, 0)
local AUSPEX_SCAN_NOISE_WIDGET_COLOR = _widget_color(90, 0, 255, 0)
local AUSPEX_SWEEP_WIDGET_COLOR = _widget_color(128, 0, 255, 0)
local FULL_CIRCLE = math_pi * 2

local function _widget_to_color(color)
    if not color then
        return WHITE_WIDGET_COLOR
    end

    local a = color[1] or color.a or 255
    local r = color[2] or color.r or 255
    local g = color[3] or color.g or 255
    local b = color[4] or color.b or 255

    return Color(a, r, g, b)
end

local function _normalized_radar_style(value)
    value = tostring(value or "square")

    if value ~= "circle" and value ~= "auspex" then
        value = "square"
    end

    return value
end

local function _current_radar_style()
    local value = mod:get("radar_style")

    if value == nil and mod.get_radar_style then
        value = mod:get_radar_style()
    end

    return _normalized_radar_style(value)
end

local function _safe_yaw(rotation)
    if not rotation or not Quaternion_yaw then
        return nil
    end

    local ok, yaw = pcall(Quaternion_yaw, rotation)
    yaw = ok and tonumber(yaw) or nil

    if type(yaw) ~= "number" or yaw ~= yaw or yaw == math_huge or yaw == -math_huge then
        return nil
    end

    return yaw
end

local function _draw_box(ui_renderer, x, y, z, w, h, color)
    local gui = ui_renderer and ui_renderer.gui

    if not gui then
        return
    end

    x = tonumber(x) or 0
    y = tonumber(y) or 0
    z = tonumber(z) or 0
    w = tonumber(w) or 0
    h = tonumber(h) or 0

    if w <= 0 or h <= 0 then
        return
    end

    local scale = ui_renderer.scale or 1
    local render_settings = ui_renderer.render_settings
    local start_layer = render_settings and render_settings.start_layer or 0
    local position = Vector3(x * scale, y * scale, start_layer + z)
    local size = Vector2(w * scale, h * scale)

    Gui_rect(gui, position, size, color)
end

local function _draw_marker_brackets(ui_renderer, x, y, z, size, color, thickness_override)
    x = math_floor((tonumber(x) or 0) + 0.5)
    y = math_floor((tonumber(y) or 0) + 0.5)
    size = math_max(1, math_floor((tonumber(size) or 0) + 0.5))

    local thickness = tonumber(thickness_override)

    if thickness and thickness > 0 then
        thickness = math_max(1, math_floor(thickness + 0.5))
    else
        thickness = size >= 16 and 2 or 1
    end

    local length = math_max(4, math_floor(size * 0.35))
    local pad = 1
    local left = x - pad
    local top = y - pad
    local right = x + size + pad
    local bottom = y + size + pad
    local bracket_color = _widget_to_color(color)

    _draw_box(ui_renderer, left, top, z, length, thickness, bracket_color)
    _draw_box(ui_renderer, left, top, z, thickness, length, bracket_color)

    _draw_box(ui_renderer, right - length, top, z, length, thickness, bracket_color)
    _draw_box(ui_renderer, right - thickness, top, z, thickness, length, bracket_color)

    _draw_box(ui_renderer, left, bottom - thickness, z, length, thickness, bracket_color)
    _draw_box(ui_renderer, left, bottom - length, z, thickness, length, bracket_color)

    _draw_box(ui_renderer, right - length, bottom - thickness, z, length, thickness, bracket_color)
    _draw_box(ui_renderer, right - thickness, bottom - length, z, thickness, length, bracket_color)
end

local function _draw_circle_fill(ui_renderer, center_x, center_y, z, radius, color)
    local integer_radius = math_max(1, math_floor((radius or 0) + 0.5))
    local radius_sq = integer_radius * integer_radius

    for dy = -integer_radius, integer_radius do
        local span = math_floor(math_sqrt(math_max(0, radius_sq - dy * dy)))
        _draw_box(ui_renderer, center_x - span, center_y + dy, z, span * 2 + 1, 1, color)
    end
end

local function _round(n)
    return math_floor(n + 0.5)
end

local function _color_with_alpha_scale(color, scale)
    if not color then
        return WHITE_WIDGET_COLOR
    end

    local a = color[1] or color.a or 255
    local r = color[2] or color.r or 255
    local g = color[3] or color.g or 255
    local b = color[4] or color.b or 255
    local scaled_alpha = math_max(0, math_min(255, math_floor(a * scale + 0.5)))

    return Color(scaled_alpha, r, g, b)
end

local function _circle_metrics(x, y, size)
    local snapped_size = math_max(2, math_floor((tonumber(size) or 0) + 0.5))
    local center_x = math_floor(x + snapped_size * 0.5 + 0.5)
    local center_y = math_floor(y + snapped_size * 0.5 + 0.5)
    local radius = math_max(1, math_floor(snapped_size * 0.5 - 1 + 0.5))

    return center_x, center_y, radius
end

local function _draw_dot(ui_renderer, x, y, z, size, color)
    size = tonumber(size) or 1
    size = math_max(1, size)

    local half = size / 2
    _draw_box(ui_renderer, _round(x - half), _round(y - half), z, size, size, color)
end

local function _draw_circle_pixel(ui_renderer, x, y, z, color)
    _draw_box(ui_renderer, x, y, z, 1, 1, color)
end

local function _plot_circle_octants(ui_renderer, center_x, center_y, z, x, y, color)
    if x == 0 and y == 0 then
        _draw_circle_pixel(ui_renderer, center_x, center_y, z, color)
        return
    end

    if y == 0 then
        _draw_circle_pixel(ui_renderer, center_x + x, center_y, z, color)
        _draw_circle_pixel(ui_renderer, center_x - x, center_y, z, color)
        _draw_circle_pixel(ui_renderer, center_x, center_y + x, z, color)
        _draw_circle_pixel(ui_renderer, center_x, center_y - x, z, color)
        return
    end

    if x == 0 then
        _draw_circle_pixel(ui_renderer, center_x + y, center_y, z, color)
        _draw_circle_pixel(ui_renderer, center_x - y, center_y, z, color)
        _draw_circle_pixel(ui_renderer, center_x, center_y + y, z, color)
        _draw_circle_pixel(ui_renderer, center_x, center_y - y, z, color)
        return
    end

    if x == y then
        _draw_circle_pixel(ui_renderer, center_x + x, center_y + y, z, color)
        _draw_circle_pixel(ui_renderer, center_x - x, center_y + y, z, color)
        _draw_circle_pixel(ui_renderer, center_x + x, center_y - y, z, color)
        _draw_circle_pixel(ui_renderer, center_x - x, center_y - y, z, color)
        return
    end

    _draw_circle_pixel(ui_renderer, center_x + x, center_y + y, z, color)
    _draw_circle_pixel(ui_renderer, center_x - x, center_y + y, z, color)
    _draw_circle_pixel(ui_renderer, center_x + x, center_y - y, z, color)
    _draw_circle_pixel(ui_renderer, center_x - x, center_y - y, z, color)
    _draw_circle_pixel(ui_renderer, center_x + y, center_y + x, z, color)
    _draw_circle_pixel(ui_renderer, center_x - y, center_y + x, z, color)
    _draw_circle_pixel(ui_renderer, center_x + y, center_y - x, z, color)
    _draw_circle_pixel(ui_renderer, center_x - y, center_y - x, z, color)
end

local function _draw_circle_perimeter(ui_renderer, center_x, center_y, z, radius, color)
    radius = math_max(1, math_floor((radius or 0) + 0.5))

    local x = radius
    local y = 0
    local decision = 1 - radius

    while y <= x do
        _plot_circle_octants(ui_renderer, center_x, center_y, z, x, y, color)

        y = y + 1

        if decision < 0 then
            decision = decision + 2 * y + 1
        else
            x = x - 1
            decision = decision + 2 * (y - x) + 1
        end
    end
end

local _draw_circle_ring = function(ui_renderer, center_x, center_y, z, outer_radius, thickness, color)
    local outer_r = math_max(1, math_floor((outer_radius or 0) + 0.5))
    local band = math_max(1, math_floor((thickness or 1) + 0.5))

    for i = 0, band - 1 do
        local r = outer_r - i

        if r > 0 then
            _draw_circle_perimeter(ui_renderer, center_x, center_y, z, r, color)
        end
    end
end

local _draw_circle_ring_soft = function(ui_renderer, center_x, center_y, z, outer_radius, thickness, color)
    local outer_r = math_max(1, math_floor((outer_radius or 0) + 0.5))
    local main_thickness = math_max(1, math_floor((thickness or 1) + 0.5))
    local feather_color = _color_with_alpha_scale(color, 0.35)

    _draw_circle_ring(ui_renderer, center_x, center_y, z, outer_r, main_thickness, color)
    _draw_circle_ring(ui_renderer, center_x, center_y, z, outer_r + 1, 1, feather_color)

    local inner_r = outer_r - main_thickness
    if inner_r > 0 then
        _draw_circle_ring(ui_renderer, center_x, center_y, z, inner_r, 1, feather_color)
    end
end

local function _draw_circle_fill_soft(ui_renderer, center_x, center_y, z, radius, color)
    local integer_radius = math_max(1, math_floor((radius or 0) + 0.5))

    if integer_radius <= 1 then
        _draw_circle_fill(ui_renderer, center_x, center_y, z, integer_radius, color)
        return
    end

    _draw_circle_fill(ui_renderer, center_x, center_y, z, integer_radius - 1, color)
    _draw_circle_ring(ui_renderer, center_x, center_y, z, integer_radius, 1, _color_with_alpha_scale(color, 0.45))
end

local function _draw_circle_outline(ui_renderer, center_x, center_y, z, radius, color)
    _draw_circle_ring_soft(ui_renderer, center_x, center_y, z, radius, 1, color)
end

local function _draw_hline_dotted(ui_renderer, x, y, z, length, thickness, color, dash, gap)
    length = math_max(0, _round(length))
    dash = math_max(1, _round(dash or 1))
    gap = math_max(0, _round(gap or 0))

    if length <= 0 then
        return
    end

    if length <= dash then
        local offset = math_floor((length - math_min(dash, length)) * 0.5 + 0.5)
        _draw_box(ui_renderer, x + offset, y, z, math_min(dash, length), thickness, color)

        return
    end

    local dash_count = math_max(1, math_floor((length + gap) / (dash + gap)))

    if dash_count <= 1 then
        local offset = math_floor((length - dash) * 0.5 + 0.5)
        _draw_box(ui_renderer, x + offset, y, z, dash, thickness, color)

        return
    end

    local total_dash_length = dash_count * dash
    local total_gap_length = math_max(0, length - total_dash_length)
    local gap_count = dash_count - 1
    local base_gap = math_floor(total_gap_length / gap_count)
    local gap_remainder = total_gap_length - base_gap * gap_count
    local cursor = x

    for i = 1, dash_count do
        _draw_box(ui_renderer, cursor, y, z, dash, thickness, color)
        cursor = cursor + dash

        if i < dash_count then
            local current_gap = base_gap + (i <= gap_remainder and 1 or 0)
            cursor = cursor + current_gap
        end
    end
end

local function _draw_vline_dotted(ui_renderer, x, y, z, thickness, length, color, dash, gap)
    length = math_max(0, _round(length))
    dash = math_max(1, _round(dash or 1))
    gap = math_max(0, _round(gap or 0))

    if length <= 0 then
        return
    end

    if length <= dash then
        local offset = math_floor((length - math_min(dash, length)) * 0.5 + 0.5)
        _draw_box(ui_renderer, x, y + offset, z, thickness, math_min(dash, length), color)

        return
    end

    local dash_count = math_max(1, math_floor((length + gap) / (dash + gap)))

    if dash_count <= 1 then
        local offset = math_floor((length - dash) * 0.5 + 0.5)
        _draw_box(ui_renderer, x, y + offset, z, thickness, dash, color)

        return
    end

    local total_dash_length = dash_count * dash
    local total_gap_length = math_max(0, length - total_dash_length)
    local gap_count = dash_count - 1
    local base_gap = math_floor(total_gap_length / gap_count)
    local gap_remainder = total_gap_length - base_gap * gap_count
    local cursor = y

    for i = 1, dash_count do
        _draw_box(ui_renderer, x, cursor, z, thickness, dash, color)
        cursor = cursor + dash

        if i < dash_count then
            local current_gap = base_gap + (i <= gap_remainder and 1 or 0)
            cursor = cursor + current_gap
        end
    end
end

local function _draw_square_outline_dotted_cornered(ui_renderer, x, y, z, size, thickness, color, dash, gap)
    x = _round(x)
    y = _round(y)
    size = math_max(1, _round(size))
    thickness = math_max(1, _round(thickness))
    dash = math_max(1, _round(dash or 1))
    gap = math_max(0, _round(gap or 0))

    local max_corner_length = math_max(thickness, math_floor(size / 3))
    local corner_length = math_min(max_corner_length, math_max(dash, thickness * 2))
    local vertical_arm_length = math_max(0, corner_length - thickness)

    _draw_box(ui_renderer, x, y, z, corner_length, thickness, color)
    if vertical_arm_length > 0 then
        _draw_box(ui_renderer, x, y + thickness, z, thickness, vertical_arm_length, color)
    end

    _draw_box(ui_renderer, x + size - corner_length, y, z, corner_length, thickness, color)
    if vertical_arm_length > 0 then
        _draw_box(ui_renderer, x + size - thickness, y + thickness, z, thickness, vertical_arm_length, color)
    end

    _draw_box(ui_renderer, x, y + size - thickness, z, corner_length, thickness, color)
    if vertical_arm_length > 0 then
        _draw_box(ui_renderer, x, y + size - corner_length, z, thickness, vertical_arm_length, color)
    end

    _draw_box(ui_renderer, x + size - corner_length, y + size - thickness, z, corner_length, thickness, color)
    if vertical_arm_length > 0 then
        _draw_box(ui_renderer, x + size - thickness, y + size - corner_length, z, thickness, vertical_arm_length, color)
    end

    local edge_start = corner_length + gap
    local edge_length = size - edge_start * 2

    if edge_length > 0 then
        _draw_hline_dotted(ui_renderer, x + edge_start, y, z, edge_length, thickness, color, dash, gap)
        _draw_hline_dotted(ui_renderer, x + edge_start, y + size - thickness, z, edge_length, thickness, color, dash, gap)
        _draw_vline_dotted(ui_renderer, x, y + edge_start, z, thickness, edge_length, color, dash, gap)
        _draw_vline_dotted(ui_renderer, x + size - thickness, y + edge_start, z, thickness, edge_length, color, dash, gap)
    end
end

local function _draw_circle_outline_dotted(ui_renderer, center_x, center_y, z, radius, color)
    local point_size = radius >= 90 and 2 or 1
    local steps = 64
    local step_angle = FULL_CIRCLE / steps

    for i = 0, steps - 1 do
        local angle = step_angle * i
        local px = center_x + math_cos(angle) * radius
        local py = center_y + math_sin(angle) * radius
        _draw_dot(ui_renderer, px, py, z, point_size, color)
    end
end

local function _draw_square_outline(ui_renderer, x, y, z, size, thickness, color)
    x = _round(x)
    y = _round(y)
    size = math_max(1, _round(size))
    thickness = math_max(1, _round(thickness))

    if size <= thickness * 2 then
        _draw_box(ui_renderer, x, y, z, size, size, color)

        return
    end

    _draw_box(ui_renderer, x, y, z, size, thickness, color)
    _draw_box(ui_renderer, x, y + size - thickness, z, size, thickness, color)
    _draw_box(ui_renderer, x, y + thickness, z, thickness, size - thickness * 2, color)
    _draw_box(ui_renderer, x + size - thickness, y + thickness, z, thickness, size - thickness * 2, color)
end

local function _draw_square_fill_soft(ui_renderer, x, y, z, size, color)
    size = math_max(1, _round(size))

    if size <= 2 then
        _draw_box(ui_renderer, x, y, z, size, size, color)
        return
    end

    local feather_color = _color_with_alpha_scale(color, 0.45)

    _draw_box(ui_renderer, x + 1, y + 1, z, size - 2, size - 2, color)
    _draw_box(ui_renderer, x, y, z, size, 1, feather_color)
    _draw_box(ui_renderer, x, y + size - 1, z, size, 1, feather_color)
    _draw_box(ui_renderer, x, y + 1, z, 1, size - 2, feather_color)
    _draw_box(ui_renderer, x + size - 1, y + 1, z, 1, size - 2, feather_color)
end

local function _draw_screen_pixel(ui_renderer, screen_x, screen_y, z, color)
    local gui = ui_renderer and ui_renderer.gui

    if not gui then
        return
    end

    local render_settings = ui_renderer.render_settings
    local start_layer = render_settings and render_settings.start_layer or 0

    Gui_rect(
        gui,
        Vector3(screen_x, screen_y, start_layer + z),
        Vector2(1, 1),
        color
    )
end

local function _draw_diagonal_line(ui_renderer, x1, y1, x2, y2, z, color)
    local scale = ui_renderer.scale or 1

    local sx = _round(x1 * scale)
    local sy = _round(y1 * scale)
    local ex = _round(x2 * scale)
    local ey = _round(y2 * scale)
    local dx = math_abs(ex - sx)
    local dy = math_abs(ey - sy)
    local step_x = sx < ex and 1 or -1
    local step_y = sy < ey and 1 or -1
    local err = dx - dy

    if sx == ex and sy == ey then
        return
    end

    while true do
        local e2 = err * 2

        if e2 > -dy then
            err = err - dy
            sx = sx + step_x
        end

        if e2 < dx then
            err = err + dx
            sy = sy + step_y
        end

        if sx == ex and sy == ey then
            break
        end

        _draw_screen_pixel(ui_renderer, sx, sy, z, color)
    end
end

local function _safe_local_player()
    local player_manager = Managers and Managers.state and Managers.state.player
    if not player_manager then
        return nil
    end

    local getter = player_manager.local_player or player_manager.player
    if type(getter) ~= "function" then
        return nil
    end

    local ok, player = pcall(getter, player_manager, 1)

    if ok then
        return player
    end

    return nil
end

local function _safe_player_horizontal_fov()
    local local_player = _safe_local_player()
    if not local_player then
        return nil
    end

    local viewport_name = local_player.viewport_name
    if not viewport_name then
        return nil
    end

    local camera_manager = Managers and Managers.state and Managers.state.camera
    if not camera_manager or type(camera_manager.fov) ~= "function" then
        return nil
    end

    if type(camera_manager.has_camera) == "function" then
        local ok_has_camera, has_camera = pcall(camera_manager.has_camera, camera_manager, viewport_name)

        if ok_has_camera and not has_camera then
            return nil
        end
    end

    local ok_fov, vertical_fov = pcall(camera_manager.fov, camera_manager, viewport_name)

    vertical_fov = ok_fov and tonumber(vertical_fov) or nil
    if not vertical_fov or vertical_fov <= 0 then
        return nil
    end

    local aspect_ratio = 16 / 9
    if rawget(_G, "RESOLUTION_LOOKUP") and RESOLUTION_LOOKUP.width and RESOLUTION_LOOKUP.height and RESOLUTION_LOOKUP.height > 0 then
        aspect_ratio = RESOLUTION_LOOKUP.width / RESOLUTION_LOOKUP.height
    end

    return 2 * math_atan(math_tan(vertical_fov * 0.5) * aspect_ratio)
end

local function _view_cone_half_angle()
    local horizontal_fov = _safe_player_horizontal_fov() or math_rad(90)
    local half_angle = horizontal_fov * 0.5

    return math_clamp(half_angle, math_rad(15), math_rad(85))
end

local function _view_cone_direction(angle)
    return math_sin(angle), -math_cos(angle)
end

local function _view_cone_endpoint_circle(center_x, center_y, radius, angle)
    local dx, dy = _view_cone_direction(angle)

    return center_x + dx * radius, center_y + dy * radius
end

local function _view_cone_endpoint_square(center_x, center_y, left, top, right, bottom, angle)
    local dx, dy = _view_cone_direction(angle)
    local best_t = nil

    if math_abs(dx) > 0.0001 then
        local t = ((dx > 0 and right) or left) - center_x
        t = t / dx

        if t > 0 then
            best_t = t
        end
    end

    if math_abs(dy) > 0.0001 then
        local t = ((dy > 0 and bottom) or top) - center_y
        t = t / dy

        if t > 0 and (not best_t or t < best_t) then
            best_t = t
        end
    end

    best_t = best_t or 0

    return center_x + dx * best_t, center_y + dy * best_t
end

local _draw_auspex_material_layers = nil

local function _apply_layer_rotation(style, angle)
    if not style then
        return
    end

    local layer_size = style.size
    local layer_pivot = style.pivot

    if not layer_pivot then
        layer_pivot = { 0, 0 }
        style.pivot = layer_pivot
    end

    if layer_size then
        layer_pivot[1] = (layer_size[1] or 0) * 0.5
        layer_pivot[2] = (layer_size[2] or 0) * 0.5
    end

    style.angle = angle or 0
end

local AUSPEX_GUIDE_OPTIONS_WITH_OUTLINE = {
    background_inset = 3,
    sweep_inset = 3,
    background_z_offset = 1,
    draw_noise = false,
    draw_scan_noise = false,
    background_color = RADAR_OUTLINE_WIDGET_COLOR,
    sweep_color = RADAR_OUTLINE_WIDGET_COLOR,
}

local AUSPEX_GUIDE_OPTIONS_NO_OUTLINE = {
    background_inset = 0,
    sweep_inset = 0,
    background_z_offset = 1,
    draw_noise = false,
    draw_scan_noise = false,
    background_color = RADAR_OUTLINE_WIDGET_COLOR,
    sweep_color = RADAR_OUTLINE_WIDGET_COLOR,
}

local AUSPEX_FRAME_OPTIONS_WITH_OUTLINE = {
    background_inset = 5,
    sweep_inset = 5,
}

local AUSPEX_FRAME_OPTIONS_NO_OUTLINE = {
    background_inset = 0,
    sweep_inset = 0,
}

local function _draw_radar_guides(self, ui_renderer, x, y, z, size, is_circle, camera_rotation)
    local guide_style = mod.get_radar_guides and mod:get_radar_guides() or "crosshair"

    if guide_style == "off" then
        return
    end

    local guide_color = _color(90, 255, 255, 255)

    if guide_style == "auspex_background" then
        local outline_style = mod.get_radar_outline and mod:get_radar_outline() or "solid"
        local options = outline_style ~= "off" and AUSPEX_GUIDE_OPTIONS_WITH_OUTLINE or AUSPEX_GUIDE_OPTIONS_NO_OUTLINE

        _draw_auspex_material_layers(self, ui_renderer, x, y, z - 1, size, camera_rotation, options)

        return
    end

    local center_x, center_y, radius

    if is_circle then
        center_x, center_y, radius = _circle_metrics(x, y, size)
    else
        center_x = x + size / 2
        center_y = y + size / 2
        radius = size / 2
    end

    if guide_style == "crosshair" then
        if is_circle then
            local guide_radius = math_max(1, radius - 2)
            local top = _round(center_y - guide_radius)
            local left = _round(center_x - guide_radius)
            local span = math_max(1, _round(guide_radius * 2))

            _draw_box(ui_renderer, _round(center_x), top, z, 1, span, guide_color)
            _draw_box(ui_renderer, left, _round(center_y), z, span, 1, guide_color)
        else
            local inset = 1
            local left = x + inset
            local top = y + inset
            local span = math_max(1, size - inset * 2)

            _draw_box(ui_renderer, _round(center_x), top, z, 1, span, guide_color)
            _draw_box(ui_renderer, left, _round(center_y), z, span, 1, guide_color)
        end

        return
    end

    if guide_style == "view_guides" then
        local half_angle = _view_cone_half_angle()
        local left_x, left_y
        local right_x, right_y

        if is_circle then
            left_x, left_y = _view_cone_endpoint_circle(center_x, center_y, radius - 1, -half_angle)
            right_x, right_y = _view_cone_endpoint_circle(center_x, center_y, radius - 1, half_angle)
        else
            left_x, left_y = _view_cone_endpoint_square(center_x, center_y, x + 1, y + 1, x + size - 1, y + size - 1,
                -half_angle)
            right_x, right_y = _view_cone_endpoint_square(center_x, center_y, x + 1, y + 1, x + size - 1, y + size - 1,
                half_angle)
        end

        _draw_diagonal_line(ui_renderer, center_x, center_y, left_x, left_y, z, guide_color)
        _draw_diagonal_line(ui_renderer, center_x, center_y, right_x, right_y, z, guide_color)

        return
    end

    if guide_style == "range_rings" then
        local ring_gap = radius / 4
        local ring_thickness = 1

        for ring = 1, 3 do
            local r = ring_gap * ring

            if is_circle then
                _draw_circle_ring_soft(ui_renderer, center_x, center_y, z, r, ring_thickness, guide_color)
            else
                local inset = radius - r
                local ring_x = x + inset
                local ring_y = y + inset
                local ring_size = size - inset * 2
                _draw_square_outline(ui_renderer, ring_x, ring_y, z, ring_size, ring_thickness, guide_color)
            end
        end
    end
end

local function _draw_radar_frame_square(ui_renderer, x, y, z, size, outline_style)
    local thickness = 2
    local fill_alpha = mod.get_background_opacity and mod:get_background_opacity() or 90
    local fill_color = _color(fill_alpha, 0, 0, 0)
    local outline_color = _color(255, 213, 226, 206)

    _draw_square_fill_soft(ui_renderer, x, y, z, size, fill_color)

    if outline_style == "solid" then
        _draw_square_outline(ui_renderer, x, y, z + 1, size, thickness, outline_color)
    elseif outline_style == "dotted" then
        local dash = 8
        local gap = 5

        _draw_square_outline_dotted_cornered(ui_renderer, x, y, z + 1, size, thickness, outline_color, dash, gap)
    end
end

local function _draw_radar_frame_circle(ui_renderer, x, y, z, size, outline_style)
    local center_x, center_y, radius = _circle_metrics(x, y, size)
    local fill_alpha = mod.get_background_opacity and mod:get_background_opacity() or 90
    local fill_color = _color(fill_alpha, 0, 0, 0)
    local outline_color = _color(255, 213, 226, 206)

    _draw_circle_fill_soft(ui_renderer, center_x, center_y, z, radius, fill_color)

    if outline_style == "solid" then
        _draw_circle_outline(ui_renderer, center_x, center_y, z + 1, radius, outline_color)
    elseif outline_style == "dotted" then
        _draw_circle_outline_dotted(ui_renderer, center_x, center_y, z + 1, radius, outline_color)
    end
end

local function _apply_frame_layer_style(style, x, y, z, size, color)
    if not style then
        return
    end

    local layer_offset = style.offset
    local layer_size = style.size
    local rounded_x = math_floor((tonumber(x) or 0) + 0.5)
    local rounded_y = math_floor((tonumber(y) or 0) + 0.5)
    local rounded_z = math_floor((tonumber(z) or 0) + 0.5)
    local rounded_size = math_max(1, math_floor((tonumber(size) or 0) + 0.5))

    layer_offset[1] = rounded_x
    layer_offset[2] = rounded_y
    layer_offset[3] = rounded_z
    layer_size[1] = rounded_size
    layer_size[2] = rounded_size
    style.color = color or WHITE_WIDGET_COLOR
end

_draw_auspex_material_layers = function(self, ui_renderer, x, y, z, size, camera_rotation, options)
    local frame_widget = self and self._frame_widget
    if not frame_widget then
        return
    end

    options = options or {}

    local animated_sweep_enabled = mod:get("auspex_animated_sweep") ~= false
    local camera_yaw = _safe_yaw(camera_rotation)
    local rotation_angle = camera_yaw and -camera_yaw or 0
    local background_inset = options.background_inset or 0
    local noise_inset = options.noise_inset or 0
    local scan_noise_inset = options.scan_noise_inset or noise_inset
    local sweep_inset = options.sweep_inset or background_inset
    local background_size = math_max(1, size - background_inset * 2)
    local noise_size = math_max(1, size - noise_inset * 2)
    local scan_noise_size = math_max(1, size - scan_noise_inset * 2)
    local sweep_size = math_max(1, size - sweep_inset * 2)
    local draw_noise = options.draw_noise ~= false
    local draw_scan_noise = options.draw_scan_noise ~= false

    frame_widget.content.background_material = AUSPEX_BACKGROUND_MATERIAL
    frame_widget.content.noise_material = draw_noise and AUSPEX_BACKGROUND_NOISE_MATERIAL or nil
    frame_widget.content.scan_noise_material = draw_scan_noise and AUSPEX_SCAN_NOISE_MATERIAL or nil
    frame_widget.content.sweep_material = animated_sweep_enabled and AUSPEX_SWEEP_MATERIAL or nil

    _apply_frame_layer_style(
        frame_widget.style.background,
        x + background_inset,
        y + background_inset,
        z + (options.background_z_offset or 0),
        background_size,
        options.background_color or AUSPEX_BACKGROUND_WIDGET_COLOR
    )
    _apply_layer_rotation(frame_widget.style.background, rotation_angle)
    if draw_noise then
        _apply_frame_layer_style(
            frame_widget.style.noise,
            x + noise_inset,
            y + noise_inset,
            z + 1,
            noise_size,
            options.noise_color or AUSPEX_BACKGROUND_NOISE_WIDGET_COLOR
        )
    end
    if draw_scan_noise then
        _apply_frame_layer_style(
            frame_widget.style.scan_noise,
            x + scan_noise_inset,
            y + scan_noise_inset,
            z + 2,
            scan_noise_size,
            options.scan_noise_color or AUSPEX_SCAN_NOISE_WIDGET_COLOR
        )
    end
    _apply_frame_layer_style(
        frame_widget.style.sweep,
        x + sweep_inset,
        y + sweep_inset,
        z + 3,
        sweep_size,
        animated_sweep_enabled and (options.sweep_color or AUSPEX_SWEEP_WIDGET_COLOR) or WHITE_WIDGET_COLOR
    )
    _apply_layer_rotation(frame_widget.style.sweep, rotation_angle)

    UIWidget.draw(frame_widget, ui_renderer)
end

local function _draw_radar_frame_auspex(self, ui_renderer, x, y, z, size, camera_rotation)
    local fill_alpha = mod.get_background_opacity and mod:get_background_opacity() or 90
    local outline_style = mod.get_radar_outline and mod:get_radar_outline() or "solid"
    local fill_color = _color(fill_alpha, 0, 0, 0)
    local options = outline_style ~= "off" and AUSPEX_FRAME_OPTIONS_WITH_OUTLINE or AUSPEX_FRAME_OPTIONS_NO_OUTLINE

    _draw_square_fill_soft(ui_renderer, x, y, z - 1, size, fill_color)
    _draw_auspex_material_layers(self, ui_renderer, x, y, z, size, camera_rotation, options)

    if outline_style == "solid" then
        local thickness = math_max(1, math_floor(size * 0.012 + 0.5))
        local inset = thickness + 2
        local frame_color = _color(210, 0, 255, 0)
        local inner_glow_color = _color(80, 0, 255, 0)

        _draw_square_outline(ui_renderer, x, y, z + 4, size, thickness, frame_color)

        if size > inset * 2 + 2 then
            _draw_square_outline(ui_renderer, x + inset, y + inset, z + 3, size - inset * 2, 1, inner_glow_color)
        end
    elseif outline_style == "dotted" then
        local thickness = math_max(1, math_floor(size * 0.01 + 0.5))
        local dash = math_max(6, math_floor(size * 0.06 + 0.5))
        local gap = math_max(4, math_floor(size * 0.04 + 0.5))
        local frame_color = _color(190, 0, 255, 0)

        _draw_square_outline_dotted_cornered(ui_renderer, x, y, z + 4, size, thickness, frame_color, dash, gap)
    end
end

local function _draw_radar_frame(self, ui_renderer, x, y, z, size, camera_rotation)
    local radar_style = _current_radar_style()

    if radar_style == "auspex" then
        _draw_radar_frame_auspex(self, ui_renderer, x, y, z, size, camera_rotation)

        return
    end

    local outline_style = mod.get_radar_outline and mod:get_radar_outline() or "solid"
    local is_circle = radar_style == "circle"

    if is_circle then
        _draw_radar_frame_circle(ui_renderer, x, y, z, size, outline_style)
    else
        _draw_radar_frame_square(ui_renderer, x, y, z, size, outline_style)
    end

    _draw_radar_guides(self, ui_renderer, x, y, z + 1, size, is_circle, camera_rotation)
end

return {
    draw_box = _draw_box,
    draw_marker_brackets = _draw_marker_brackets,
    draw_radar_frame = _draw_radar_frame,
    widget_to_color = _widget_to_color,
}
