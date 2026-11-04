--- Widget definitions and widget pools for the radar HUD element.
-- Defines the Auspex frame widget, the overview scale widget and the pooled marker widgets,
-- the helpers that create them lazily on the HUD element and reset them between uses, and
-- the draw of a marker widget. Every optional pass is gated by a visibility function on its
-- content value, so a pass only draws while the HUD element has assigned it a material, icon
-- or glyph.
--
-- Explicit module loaded by `ui/Radar_hud_element.lua` through `mod:io_dofile`; the chunk
-- returns the pool size and the ensure, clear and draw helpers. The widgets are stored on the
-- HUD element instance passed in as `self`.
-- module: Radar_hud_widgets
-- author: LucLeto
local mod = get_mod("Radar")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIScenegraph = require("scripts/managers/ui/ui_scenegraph")
local UIWidget = require("scripts/managers/ui/ui_widget")
local Gui = Gui
local Vector2 = Vector2
local Vector3 = Vector3
local string_format = string.format

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

local WHITE_WIDGET_COLOR = { 255, 255, 255, 255 }
--- Number of marker widgets in the pool; the HUD element reserves the last one for the player's centre dot.
local MAX_RADAR_MARKERS = 301
--- The plain texture layers of a marker widget, in pass order, which `_draw_marker_widget` draws itself.
-- The marker definition's other two layers, the marked ring (a texture with material values) and
-- the glyph (a text pass), are left to `UIWidget.draw`.
local MARKER_TEXTURE_LAYERS = {
    "radius_icon",
    "plate_icon",
    "icon",
    "overlay_icon",
    "title_icon",
    "arrow_icon",
}
local MARKER_TEXTURE_LAYER_COUNT = #MARKER_TEXTURE_LAYERS

-- ----------------------------------------------------------------------------
-- Mutable state
-- ----------------------------------------------------------------------------

--- Keys already logged by `_log_once`, per log category, for the lifetime of the module.
local LogBuckets = {
    draws = {},
}

-- ----------------------------------------------------------------------------
-- Helpers and widget definitions
-- ----------------------------------------------------------------------------

--- Returns a new white ARGB colour array, so no two widget styles share a colour table.
-- treturn: tab
local function _white_widget_color()
    return {
        WHITE_WIDGET_COLOR[1],
        WHITE_WIDGET_COLOR[2],
        WHITE_WIDGET_COLOR[3],
        WHITE_WIDGET_COLOR[4],
    }
end

--- Writes a debug log line once per key, and only while debug mode is enabled.
-- tab: bucket set of keys already logged
-- string: key de-duplication key
-- string: message log message
local function _log_once(bucket, key, message)
    if mod:get("debug_mode") ~= true then
        return
    end

    if bucket[key] then
        return
    end

    bucket[key] = true
    mod:info(message)
end

--- Visibility functions for the optional widget passes.
-- A pass is drawn only while its content value is a non-empty string, so the HUD element
-- turns layers on and off by assigning or clearing content fields instead of rebuilding
-- widgets.
local WidgetVisibility = {
    has_icon = function(content)
        return content.icon ~= nil and content.icon ~= ""
    end,
    has_glyph_icon = function(content)
        return content.glyph_icon ~= nil and content.glyph_icon ~= ""
    end,
    has_overlay_icon = function(content)
        return content.overlay_icon ~= nil and content.overlay_icon ~= ""
    end,
    has_plate_icon = function(content)
        return content.plate_icon ~= nil and content.plate_icon ~= ""
    end,
    has_title_icon = function(content)
        return content.title_icon ~= nil and content.title_icon ~= ""
    end,
    has_arrow_icon = function(content)
        return content.arrow_icon ~= nil and content.arrow_icon ~= ""
    end,
    has_marked_ring = function(content)
        return content.marked_ring ~= nil and content.marked_ring ~= ""
    end,
    has_radius_icon = function(content)
        return content.radius_icon ~= nil and content.radius_icon ~= ""
    end,
    has_background_material = function(content)
        return content.background_material ~= nil and content.background_material ~= ""
    end,
    has_noise_material = function(content)
        return content.noise_material ~= nil and content.noise_material ~= ""
    end,
    has_scan_noise_material = function(content)
        return content.scan_noise_material ~= nil and content.scan_noise_material ~= ""
    end,
    has_sweep_material = function(content)
        return content.sweep_material ~= nil and content.sweep_material ~= ""
    end,
    has_overview_scale_x_left_icon = function(content)
        return content.overview_scale_x_left_icon ~= nil and content.overview_scale_x_left_icon ~= ""
    end,
    has_overview_scale_x_right_icon = function(content)
        return content.overview_scale_x_right_icon ~= nil and content.overview_scale_x_right_icon ~= ""
    end,
    has_overview_scale_y_top_icon = function(content)
        return content.overview_scale_y_top_icon ~= nil and content.overview_scale_y_top_icon ~= ""
    end,
    has_overview_scale_y_bottom_icon = function(content)
        return content.overview_scale_y_bottom_icon ~= nil and content.overview_scale_y_bottom_icon ~= ""
    end,
}

--- Builds the Auspex frame widget definition with four layers.
-- The layers are the rotated scanner background, background noise, scan noise and the
-- rotated sweep, each sized and placed per frame by the renderer.
-- treturn: tab widget definition
local function _frame_definition()
    return UIWidget.create_definition({
        {
            pass_type = "rotated_texture",
            value_id = "background_material",
            style_id = "background",
            style = {
                angle = 0,
                hdr = true,
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 1 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_background_material,
        },
        {
            pass_type = "texture",
            value_id = "noise_material",
            style_id = "noise",
            style = {
                hdr = true,
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 2 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_noise_material,
        },
        {
            pass_type = "texture",
            value_id = "scan_noise_material",
            style_id = "scan_noise",
            style = {
                hdr = true,
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 3 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_scan_noise_material,
        },
        {
            pass_type = "rotated_texture",
            value_id = "sweep_material",
            style_id = "sweep",
            style = {
                angle = 0,
                pivot = { 0, 0 },
                hdr = true,
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 4 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_sweep_material,
        },
    }, "screen")
end

--- Builds the widget definition for the overview mode scale indicators and the normal radar zoom icon.
-- treturn: tab widget definition
local function _overview_scale_definition()
    return UIWidget.create_definition({
        {
            pass_type = "rotated_texture",
            value_id = "overview_scale_x_left_icon",
            style_id = "overview_scale_x_left_icon",
            style = {
                angle = 0,
                pivot = { 0, 0 },
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 40 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_overview_scale_x_left_icon,
        },
        {
            pass_type = "rotated_texture",
            value_id = "overview_scale_x_right_icon",
            style_id = "overview_scale_x_right_icon",
            style = {
                angle = 0,
                pivot = { 0, 0 },
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 40 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_overview_scale_x_right_icon,
        },
        {
            pass_type = "rotated_texture",
            value_id = "overview_scale_y_top_icon",
            style_id = "overview_scale_y_top_icon",
            style = {
                angle = 0,
                pivot = { 0, 0 },
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 40 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_overview_scale_y_top_icon,
        },
        {
            pass_type = "rotated_texture",
            value_id = "overview_scale_y_bottom_icon",
            style_id = "overview_scale_y_bottom_icon",
            style = {
                angle = 0,
                pivot = { 0, 0 },
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 40 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_overview_scale_y_bottom_icon,
        },
        {
            pass_type = "texture",
            value_id = "normal_zoom_icon",
            style_id = "normal_zoom_icon",
            style = {
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 40 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = function(content)
                return content.normal_zoom_icon ~= nil and content.normal_zoom_icon ~= ""
            end,
        },
    }, "screen")
end

--- Builds the widget definition shared by every pooled radar marker.
-- Passes are listed bottom to top by layer offset; radius icon, marked ring, backplate,
-- base icon or glyph, overlay icon, title icon and vertical arrow. The backplate sits below
-- the base icon and only draws for markers that name one, so enemy markers, which build
-- their own background into the base icon, are unaffected.
-- treturn: tab widget definition
local function _marker_definition()
    return UIWidget.create_definition({
        {
            pass_type = "texture",
            value_id = "radius_icon",
            style_id = "radius_icon",
            style = {
                hdr = true,
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 8 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_radius_icon,
        },
        {
            pass_type = "texture",
            value_id = "marked_ring",
            style_id = "marked_ring",
            style = {
                hdr = true,
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 9 },
                size = { 23, 23 },
                material_values = {
                    display_mode = 1,
                    part_1_color = { 0, 0, 0, 0 },
                    part_2_color = { 0, 0, 0, 0 },
                    part_3_color = { 0, 0, 0, 0 },
                    part_4_color = { 0, 0, 0, 0 },
                },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_marked_ring,
        },
        {
            pass_type = "texture",
            value_id = "plate_icon",
            style_id = "plate_icon",
            style = {
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 9 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_plate_icon,
        },
        {
            pass_type = "texture",
            value_id = "icon",
            style_id = "icon",
            style = {
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 10 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_icon,
        },
        {
            pass_type = "text",
            value = "<glyph_icon>",
            value_id = "glyph_icon",
            style_id = "glyph_icon",
            style = {
                drop_shadow = false,
                font_size = 16,
                font_type = UIFontSettings.hud_body.font_type,
                vertical_alignment = "top",
                horizontal_alignment = "left",
                text_horizontal_alignment = "center",
                text_vertical_alignment = "center",
                offset = { 0, 0, 10 },
                size = { 16, 16 },
                text_color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_glyph_icon,
        },
        {
            pass_type = "texture",
            value_id = "overlay_icon",
            style_id = "overlay_icon",
            style = {
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 11 },
                size = { 10, 10 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_overlay_icon,
        },
        {
            pass_type = "texture",
            value_id = "title_icon",
            style_id = "title_icon",
            style = {
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 12 },
                size = { 16, 16 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_title_icon,
        },
        {
            pass_type = "texture",
            value_id = "arrow_icon",
            style_id = "arrow_icon",
            style = {
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 2, 2, 16 },
                size = { 4, 4 },
                color = _white_widget_color(),
            },
            visibility_function = WidgetVisibility.has_arrow_icon,
        },
    }, "screen")
end

local function _create_frame_widget()
    return UIWidget.init("RadarFrame_Auspex", _frame_definition())
end

local function _create_overview_scale_widget()
    return UIWidget.init("RadarOverviewScale", _overview_scale_definition())
end

local function _create_marker_widget(index)
    return UIWidget.init("RadarMarker_" .. index, _marker_definition())
end

--- Clears every material of the Auspex frame widget so none of its layers draw.
-- tab: widget frame widget
local function _clear_frame_widget(widget)
    widget.content.background_material = nil
    widget.content.noise_material = nil
    widget.content.scan_noise_material = nil
    widget.content.sweep_material = nil
end

--- Clears every icon of the overview scale widget so none of its passes draw.
-- tab: widget overview scale widget
local function _clear_overview_scale_widget(widget)
    widget.content.overview_scale_x_left_icon = nil
    widget.content.overview_scale_x_right_icon = nil
    widget.content.overview_scale_y_top_icon = nil
    widget.content.overview_scale_y_bottom_icon = nil
    widget.content.normal_zoom_icon = nil
end

--- Resets a pooled marker widget before it is reused for another target.
-- Every optional layer must be cleared here; a layer left set would carry one marker's
-- icon or backplate over to the next target drawn with this widget.
-- tab: widget marker widget
local function _clear_marker_widget(widget)
    widget.content.radius_icon = nil
    widget.content.radius_icon_size = nil
    widget.content.marked_ring = nil
    widget.content.marked_ring_slots_mask = nil
    widget.content.marked_ring_size = nil
    widget.content.icon = nil
    widget.content.glyph_icon = ""
    widget.content.plate_icon = nil
    widget.content.overlay_icon = nil
    widget.content.title_icon = nil
    widget.content.arrow_icon = nil
    widget.content.value_text = ""
end

--- Creates the Auspex frame widget on the HUD element on first use.
-- tab: self HUD element
local function _ensure_frame_widget(self)
    if self._frame_widget then
        return
    end

    self._frame_widget = _create_frame_widget()
    _clear_frame_widget(self._frame_widget)
end

--- Creates the overview scale widget on the HUD element on first use.
-- tab: self HUD element
local function _ensure_overview_scale_widget(self)
    if self._overview_scale_widget then
        return
    end

    self._overview_scale_widget = _create_overview_scale_widget()
    _clear_overview_scale_widget(self._overview_scale_widget)
end

--- Fills the HUD element's marker widget pool up to `MAX_RADAR_MARKERS`.
-- Creates `_marker_widgets` and resets `_last_active_marker_widget_index` on first use, and
-- only adds the missing widgets afterwards, so it is cheap to call every frame.
-- tab: self HUD element
local function _ensure_marker_widgets(self)
    if not self._marker_widgets then
        self._marker_widgets = {}
        self._last_active_marker_widget_index = 0
    end

    local existing_count = #self._marker_widgets

    if existing_count >= MAX_RADAR_MARKERS then
        return
    end

    for i = existing_count + 1, MAX_RADAR_MARKERS do
        self._marker_widgets[i] = _create_marker_widget(i)
    end

    if mod:get("debug_mode") == true then
        _log_once(LogBuckets.draws, "widget_pool_init",
            string_format("[Radar] widget pool created | count=%d", #self._marker_widgets))
    end
end

--- Draws a pooled marker widget.
-- Each visible texture layer is drawn with the calls the game's texture pass makes, in pass
-- order and at the same position, size and colour, which saves `UIWidget.draw` stepping
-- through the passes of every marker. Like `UIWidget.draw`, the renderer's alpha and colour
-- intensity multipliers apply while the widget draws, and the render settings are left with
-- material flags. A widget showing its marked ring or its glyph, or a draw without render
-- settings or in forced retained mode, goes through `UIWidget.draw`.
-- tab: widget marker widget
-- tab: ui_renderer active UI renderer
local function _draw_marker_widget(widget, ui_renderer)
    local content = widget.content
    local render_settings = ui_renderer.render_settings
    local marked_ring = content.marked_ring
    local glyph_icon = content.glyph_icon

    if not render_settings
        or render_settings.force_retained_mode
        or (marked_ring ~= nil and marked_ring ~= "")
        or (glyph_icon ~= nil and glyph_icon ~= "") then
        return UIWidget.draw(widget, ui_renderer)
    end

    local previous_alpha_multiplier = render_settings.alpha_multiplier
    local previous_color_intensity_multiplier = render_settings.color_intensity_multiplier
    local world_position = UIScenegraph.world_position(ui_renderer.ui_scenegraph, widget.scenegraph_id)
    local widget_offset = widget.offset
    local x = world_position[1] + widget_offset[1]
    local y = world_position[2] + widget_offset[2]
    local z = world_position[3] + widget_offset[3]
    local style = widget.style
    local scale = ui_renderer.scale
    local scale_vector3 = Gui.scale_vector3
    local script_draw_bitmap = UIRenderer.script_draw_bitmap

    render_settings.alpha_multiplier = (previous_alpha_multiplier or 1) * (ui_renderer.alpha_multiplier or 1)
    render_settings.color_intensity_multiplier = (previous_color_intensity_multiplier or 1)
        * (ui_renderer.color_intensity_multiplier or 1)
    render_settings.material_flags = render_settings.material_flags or 0

    for i = 1, MARKER_TEXTURE_LAYER_COUNT do
        local layer = MARKER_TEXTURE_LAYERS[i]
        local material = content[layer]

        if material ~= nil and material ~= "" then
            local layer_style = style[layer]
            local offset = layer_style.offset
            local size = layer_style.size

            script_draw_bitmap(ui_renderer, material,
                scale_vector3(Vector3(x + offset[1], y + offset[2], z + (offset[3] or 0)), scale),
                scale_vector3(Vector2(size[1], size[2]), scale), layer_style.color)
        end
    end

    render_settings.alpha_multiplier = previous_alpha_multiplier
    render_settings.color_intensity_multiplier = previous_color_intensity_multiplier
    widget.dirty = nil
end

--- Module interface consumed by `ui/Radar_hud_element.lua`.
return {
    MAX_RADAR_MARKERS = MAX_RADAR_MARKERS,
    ensure_frame_widget = _ensure_frame_widget,
    ensure_overview_scale_widget = _ensure_overview_scale_widget,
    ensure_marker_widgets = _ensure_marker_widgets,
    clear_frame_widget = _clear_frame_widget,
    clear_overview_scale_widget = _clear_overview_scale_widget,
    clear_marker_widget = _clear_marker_widget,
    draw_marker_widget = _draw_marker_widget,
}
