local mod = get_mod("Radar")
local UIWidget = require("scripts/managers/ui/ui_widget")

local string_format = string.format
local WHITE_WIDGET_COLOR = { 255, 255, 255, 255 }
local LogBuckets = {
    draws = {},
}

local function _white_widget_color()
    return {
        WHITE_WIDGET_COLOR[1],
        WHITE_WIDGET_COLOR[2],
        WHITE_WIDGET_COLOR[3],
        WHITE_WIDGET_COLOR[4],
    }
end

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

local WidgetVisibility = {
    has_icon = function(content)
        return content.icon ~= nil and content.icon ~= ""
    end,
    has_overlay_icon = function(content)
        return content.overlay_icon ~= nil and content.overlay_icon ~= ""
    end,
    has_title_icon = function(content)
        return content.title_icon ~= nil and content.title_icon ~= ""
    end,
    has_arrow_icon = function(content)
        return content.arrow_icon ~= nil and content.arrow_icon ~= ""
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

local function _marker_definition()
    return UIWidget.create_definition({
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

local MAX_RADAR_MARKERS = 301

local function _create_frame_widget()
    return UIWidget.init("RadarFrame_Auspex", _frame_definition())
end

local function _create_overview_scale_widget()
    return UIWidget.init("RadarOverviewScale", _overview_scale_definition())
end

local function _create_marker_widget(index)
    return UIWidget.init("RadarMarker_" .. index, _marker_definition())
end

local function _clear_frame_widget(widget)
    widget.content.background_material = nil
    widget.content.noise_material = nil
    widget.content.scan_noise_material = nil
    widget.content.sweep_material = nil
end

local function _clear_overview_scale_widget(widget)
    widget.content.overview_scale_x_left_icon = nil
    widget.content.overview_scale_x_right_icon = nil
    widget.content.overview_scale_y_top_icon = nil
    widget.content.overview_scale_y_bottom_icon = nil
    widget.content.normal_zoom_icon = nil
end

local function _clear_marker_widget(widget)
    widget.content.icon = nil
    widget.content.overlay_icon = nil
    widget.content.title_icon = nil
    widget.content.arrow_icon = nil
    widget.content.value_text = ""
end

local function _ensure_frame_widget(self)
    if self._frame_widget then
        return
    end

    self._frame_widget = _create_frame_widget()
    _clear_frame_widget(self._frame_widget)
end

local function _ensure_overview_scale_widget(self)
    if self._overview_scale_widget then
        return
    end

    self._overview_scale_widget = _create_overview_scale_widget()
    _clear_overview_scale_widget(self._overview_scale_widget)
end

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

return {
    MAX_RADAR_MARKERS = MAX_RADAR_MARKERS,
    ensure_frame_widget = _ensure_frame_widget,
    ensure_overview_scale_widget = _ensure_overview_scale_widget,
    ensure_marker_widgets = _ensure_marker_widgets,
    clear_frame_widget = _clear_frame_widget,
    clear_overview_scale_widget = _clear_overview_scale_widget,
    clear_marker_widget = _clear_marker_widget,
}
