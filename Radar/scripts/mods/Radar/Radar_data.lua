local mod = get_mod("Radar")

local function _artwork_icon_off_dropdown(setting_id)
    return {
        setting_id = setting_id,
        type = "dropdown",
        default_value = "artwork",
        options = {
            {
                text = "marker_display_mode_artwork",
                value = "artwork",
            },
            {
                text = "marker_display_mode_icon",
                value = "icon",
            },
            {
                text = "radar_outline_off",
                value = "off",
            },
        },
        get = function()
            local value = mod:get(setting_id)

            if value == "icon" or value == "off" or value == "artwork" then
                return value
            end

            return value == false and "off" or "artwork"
        end,
        change = function(new_value)
            mod:set(setting_id, new_value)
        end,
    }
end

local function _icon_scale_slider(setting_id, title_key)
    return {
        setting_id = setting_id,
        title = title_key or "icon_size_percent",
        type = "numeric",
        default_value = 100,
        range = { 50, 300 },
        decimals_number = 0,
        step_size_value = 5,
    }
end

local function _color_channel_slider(setting_id)
    return {
        setting_id = setting_id,
        type = "numeric",
        default_value = 255,
        range = { 0, 255 },
        decimals_number = 0,
        step_size_value = 1,
    }
end

local function _nearby_highlight_radar_distance_text_checkbox(setting_id)
    return {
        setting_id = setting_id,
        title = "nearby_highlight_radar_distance_text",
        tooltip = "nearby_highlight_radar_distance_text_tooltip",
        type = "checkbox",
        default_value = false,
    }
end

local function _enemy_vertical_arrows_checkbox(setting_id)
    return {
        setting_id = setting_id,
        tooltip = "show_enemy_vertical_arrows_tooltip",
        type = "checkbox",
        default_value = false,
    }
end

local function _icon_marked_off_dropdown(setting_id, default_value)
    local tooltip = nil

    if setting_id == "show_enemy_common" then
        tooltip = "common_tooltip"
    end

    if setting_id == "show_enemy_shooter" then
        tooltip = "shooter_enemies_tooltip"
    end

    return {
        setting_id = setting_id,
        type = "dropdown",
        default_value = default_value,
        tooltip = tooltip,
        options = {
            {
                text = "display_style_icon_only",
                value = "icon_only",
            },
            {
                text = "display_style_marked_icon",
                value = "marked_icon",
            },
            {
                text = "radar_outline_off",
                value = "off",
            },
        },
    }
end

local function _expedition_marker_display_mode_dropdown(setting_id, default_value)
    return {
        setting_id = setting_id,
        type = "dropdown",
        default_value = default_value,
        options = {
            {
                text = "display_style_icon_only",
                value = "icon_only",
            },
            {
                text = "display_style_icon_distance",
                value = "icon_distance",
            },
            {
                text = "radar_outline_off",
                value = "off",
            },
        },
        get = function()
            local value = mod:get(setting_id)

            if value == nil then
                return default_value
            end

            if value == "icon_only" or value == "icon_distance" or value == "off" then
                return value
            end

            return value == false and "off" or "icon_only"
        end,
        change = function(new_value)
            mod:set(setting_id, new_value)
        end,
    }
end

local function _expedition_loot_marker_mode_dropdown(setting_id)
    return {
        setting_id = setting_id,
        type = "dropdown",
        default_value = "default",
        options = {
            {
                text = "expedition_loot_marker_mode_default",
                value = "default",
            },
            {
                text = "expedition_loot_marker_mode_scaled",
                value = "scaled",
            },
            {
                text = "expedition_loot_marker_mode_clustered",
                value = "clustered",
            },
        },
    }
end


local function _apply_missing_tooltips(widgets)
    for i = 1, #widgets do
        local widget = widgets[i]

        if widget.type == "group" and widget.sub_widgets then
            _apply_missing_tooltips(widget.sub_widgets)
        elseif widget.setting_id and widget.tooltip == nil then
            widget.tooltip = widget.setting_id .. "_tooltip"
        end
    end
end
return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = (function()
            local widgets = {
                {
                    setting_id = "general_group",
                    type = "group",
                    sub_widgets = {
                        {
                            setting_id = "enable_radar",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "enable_in_regular_missions",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "enable_in_havoc",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "enable_in_mortis_trials",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "enable_in_expeditions",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "toggle_radar_key",
                            type = "keybind",
                            default_value = {},
                            keybind_trigger = "pressed",
                            keybind_type = "function_call",
                            function_name = "toggle_radar_keybind",
                        },
                        {
                            setting_id = "toggle_overview_key",
                            type = "keybind",
                            default_value = {},
                            keybind_trigger = "pressed",
                            keybind_type = "function_call",
                            function_name = "toggle_overview_keybind",
                        },
                        {
                            setting_id = "radar_zoom_modifier_key",
                            type = "keybind",
                            default_value = {},
                            keybind_trigger = "held",
                            keybind_type = "function_call",
                            function_name = "radar_zoom_modifier_keybind",
                        },
                        {
                            setting_id = "overview_zoom_in_key",
                            type = "keybind",
                            default_value = { "wheel_down" },
                            keybind_trigger = "pressed",
                            keybind_type = "function_call",
                            function_name = "overview_zoom_in_keybind",
                        },
                        {
                            setting_id = "overview_zoom_out_key",
                            type = "keybind",
                            default_value = { "wheel_up" },
                            keybind_trigger = "pressed",
                            keybind_type = "function_call",
                            function_name = "overview_zoom_out_keybind",
                        },
                        {
                            setting_id = "radar_zoom_reset_key",
                            type = "keybind",
                            default_value = {},
                            keybind_trigger = "pressed",
                            keybind_type = "function_call",
                            function_name = "radar_zoom_reset_keybind",
                        },
                        {
                            setting_id = "show_scale_legends",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "radar_size",
                            type = "numeric",
                            default_value = 180,
                            range = { 100, 1200 },
                            decimals_number = 0,
                            step_size_value = 5,
                            change = function(new_value)
                                mod:set("radar_size", new_value)
                                mod:set_radar_position(mod:get_radar_offset_x(new_value),
                                    mod:get_radar_offset_y(new_value),
                                    true)
                            end,
                            get = function()
                                return mod.get_configured_radar_size and mod:get_configured_radar_size()
                                    or mod:get_radar_size()
                            end,
                        },
                        {
                            setting_id = "radar_range",
                            type = "numeric",
                            default_value = 40,
                            range = { 10, 200 },
                            decimals_number = 0,
                            step_size_value = 1,
                        },
                        {
                            setting_id = "item_vertical_arrow_threshold",
                            type = "numeric",
                            default_value = 25,
                            range = { 25, 100 },
                            decimals_number = 0,
                            step_size_value = 1,
                        },
                        {
                            setting_id = "item_vertical_hide_threshold",
                            type = "numeric",
                            default_value = 12,
                            range = { 8, 50 },
                            decimals_number = 0,
                            step_size_value = 1,
                        },
                        {
                            setting_id = "max_radar_markers",
                            type = "numeric",
                            default_value = 64,
                            range = { 10, 200 },
                        },
                        {
                            setting_id = "overview_max_radar_markers",
                            type = "numeric",
                            default_value = 300,
                            range = { 100, 300 },
                            decimals_number = 0,
                            step_size_value = 25,
                        },
                        {
                            setting_id = "show_only_tagged_enemies",
                            type = "checkbox",
                            default_value = false,
                        },
                        {
                            setting_id = "show_ability_marked_enemies",
                            type = "checkbox",
                            default_value = false,
                        },
                        {
                            setting_id = "show_only_tagged_items",
                            type = "checkbox",
                            default_value = false,
                        },
                        {
                            setting_id = "scale_icons_with_radar_size",
                            type = "checkbox",
                            default_value = false,
                        },
                        {
                            setting_id = "radar_style",
                            type = "dropdown",
                            default_value = "square",
                            options = {
                                {
                                    text = "radar_style_square",
                                    value = "square",
                                },
                                {
                                    text = "radar_style_circle",
                                    value = "circle",
                                },
                                {
                                    text = "radar_style_auspex",
                                    value = "auspex",
                                },
                            },
                            get = function()
                                local value = mod:get("radar_style")

                                if value == "circle" or value == "auspex" then
                                    return value
                                end

                                return "square"
                            end,
                        },
                        {
                            setting_id = "auspex_animated_sweep",
                            type = "checkbox",
                            default_value = true,
                            tooltip = "auspex_animated_sweep_tooltip",
                        },
                        {
                            setting_id = "radar_outline",
                            type = "dropdown",
                            default_value = "solid",
                            options = {
                                {
                                    text = "radar_outline_solid",
                                    value = "solid",
                                },
                                {
                                    text = "radar_outline_dotted",
                                    value = "dotted",
                                },
                                {
                                    text = "radar_outline_off",
                                    value = "off",
                                },
                            },
                        },
                        {
                            setting_id = "radar_guides",
                            type = "dropdown",
                            default_value = "crosshair",
                            options = {
                                {
                                    text = "radar_guides_crosshair",
                                    value = "crosshair",
                                },
                                {
                                    text = "radar_guides_view_guides",
                                    value = "view_guides",
                                },
                                {
                                    text = "radar_guides_range_rings",
                                    value = "range_rings",
                                },
                                {
                                    text = "radar_style_auspex",
                                    value = "auspex_background",
                                },
                                {
                                    text = "radar_guides_off",
                                    value = "off",
                                },
                            },
                        },
                        {
                            setting_id = "background_opacity",
                            type = "numeric",
                            default_value = 90,
                            range = { 0, 255 },
                            decimals_number = 0,
                            step_size_value = 5,
                            get = function()
                                return mod:get_background_opacity()
                            end,
                        },
                    },
                },
                {
                    setting_id = "position_group",
                    type = "group",
                    sub_widgets = {
                        {
                            setting_id = "radar_anchor",
                            type = "dropdown",
                            default_value = "top_left",
                            options = {
                                {
                                    text = "radar_anchor_top_left",
                                    value = "top_left",
                                },
                                {
                                    text = "radar_anchor_top_right",
                                    value = "top_right",
                                },
                                {
                                    text = "radar_anchor_bottom_left",
                                    value = "bottom_left",
                                },
                                {
                                    text = "radar_anchor_bottom_right",
                                    value = "bottom_right",
                                },
                            },
                            change = function(new_value)
                                mod:set_radar_anchor(new_value, true)
                            end,
                            get = function()
                                return mod:get_radar_anchor()
                            end,
                        },
                        {
                            setting_id = "unrestricted_radar_position",
                            type = "checkbox",
                            default_value = false,
                        },
                        {
                            setting_id = "radar_pos_x",
                            type = "numeric",
                            default_value = 40,
                            range = { -12000, 12000 },
                            decimals_number = 0,
                            step_size_value = 5,
                            change = function(new_value)
                                mod:set_radar_position(new_value, nil, true)
                            end,
                            get = function()
                                return mod:get_radar_offset_x()
                            end,
                        },
                        {
                            setting_id = "radar_pos_y",
                            type = "numeric",
                            default_value = 220,
                            range = { -12000, 12000 },
                            decimals_number = 0,
                            step_size_value = 5,
                            change = function(new_value)
                                mod:set_radar_position(nil, new_value, true)
                            end,
                            get = function()
                                return mod:get_radar_offset_y()
                            end,
                        },
                        {
                            setting_id = "radar_move_step",
                            type = "numeric",
                            default_value = 10,
                            range = { 1, 200 },
                            decimals_number = 0,
                            step_size_value = 1,
                            change = function(new_value)
                                local value = math.floor(tonumber(new_value) or 10)

                                if value < 1 then
                                    value = 1
                                elseif value > 200 then
                                    value = 200
                                end

                                mod:set("radar_move_step", value)
                            end,
                            get = function()
                                return mod:get_radar_move_step()
                            end,
                        },
                        {
                            setting_id = "move_radar_left_key",
                            type = "keybind",
                            default_value = {},
                            keybind_trigger = "pressed",
                            keybind_type = "function_call",
                            function_name = "move_radar_left",
                        },
                        {
                            setting_id = "move_radar_right_key",
                            type = "keybind",
                            default_value = {},
                            keybind_trigger = "pressed",
                            keybind_type = "function_call",
                            function_name = "move_radar_right",
                        },
                        {
                            setting_id = "move_radar_up_key",
                            type = "keybind",
                            default_value = {},
                            keybind_trigger = "pressed",
                            keybind_type = "function_call",
                            function_name = "move_radar_up",
                        },
                        {
                            setting_id = "move_radar_down_key",
                            type = "keybind",
                            default_value = {},
                            keybind_trigger = "pressed",
                            keybind_type = "function_call",
                            function_name = "move_radar_down",
                        },
                    },
                },
                {
                    setting_id = "nearby_highlight_group",
                    type = "group",
                    sub_widgets = {
                        {
                            setting_id = "highlight_distance",
                            type = "numeric",
                            default_value = 10,
                            range = { 5, 20 },
                            decimals_number = 0,
                            step_size_value = 1,
                            get = function()
                                return mod:get_nearby_highlight_range()
                            end,
                        },
                        {
                            setting_id = "nearby_highlight_distance_text",
                            tooltip = "nearby_highlight_screen_distance_text_tooltip",
                            type = "checkbox",
                            default_value = false,
                        },
                        {
                            setting_id = "nearby_highlight_thickness",
                            type = "numeric",
                            default_value = 0,
                            range = { 0, 6 },
                            decimals_number = 0,
                            step_size_value = 1,
                        },
                        {
                            setting_id = "nearby_highlight_opacity",
                            type = "numeric",
                            default_value = 255,
                            range = { 25, 255 },
                            decimals_number = 0,
                            step_size_value = 5,
                        },
                        {
                            setting_id = "nearby_highlight_use_custom_color",
                            type = "checkbox",
                            default_value = false,
                        },
                        _color_channel_slider("nearby_highlight_color_red"),
                        _color_channel_slider("nearby_highlight_color_green"),
                        _color_channel_slider("nearby_highlight_color_blue"),
                    },
                },
                {
                    setting_id = "common_pickups_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("common_pickups_icon_scale", nil),
                        {
                            setting_id = "nearby_highlight_common_pickups",
                            type = "checkbox",
                            default_value = false,
                        },
                        _nearby_highlight_radar_distance_text_checkbox("nearby_highlight_distance_text_common_pickups"),
                        _artwork_icon_off_dropdown("show_crates"),
                        {
                            setting_id = "show_ammo_small",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_ammo_big",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_grenades",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_pocketable_ammo_crate",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_pocketable_medical_crate",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_pocketable_syringe_ability",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_pocketable_syringe_corruption",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_pocketable_syringe_power",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_pocketable_syringe_speed",
                            type = "checkbox",
                            default_value = true,
                        },
                    },
                },
                {
                    setting_id = "materials_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("materials_icon_scale", nil),
                        {
                            setting_id = "nearby_highlight_materials",
                            type = "checkbox",
                            default_value = false,
                        },
                        _nearby_highlight_radar_distance_text_checkbox("nearby_highlight_distance_text_materials"),
                        _artwork_icon_off_dropdown("show_diamantine"),
                        _artwork_icon_off_dropdown("show_plasteel"),
                    },
                },
                {
                    setting_id = "primary_objective_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("primary_objective_icon_scale", nil),
                        {
                            setting_id = "nearby_highlight_primary_objective",
                            type = "checkbox",
                            default_value = false,
                        },
                        _nearby_highlight_radar_distance_text_checkbox(
                            "nearby_highlight_distance_text_primary_objective"),
                        {
                            setting_id = "show_power_cell_teal",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_cryonic_rod",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_moebian_pox_zetaphyte_13_sample",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_vacuum_capsule",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_special_issue_ammo",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_prismata_crystal_repository",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_mortis_relic",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_coordinates_paper",
                            type = "checkbox",
                            default_value = true,
                        },
                    },
                },
                {
                    setting_id = "secondary_objective_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("secondary_objective_icon_scale", nil),
                        {
                            setting_id = "nearby_highlight_secondary_objective",
                            type = "checkbox",
                            default_value = false,
                        },
                        _nearby_highlight_radar_distance_text_checkbox(
                            "nearby_highlight_distance_text_secondary_objective"),
                        {
                            setting_id = "show_pocketable_grimoire",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_pocketable_scripture",
                            type = "checkbox",
                            default_value = true,
                        },
                    },
                },
                {
                    setting_id = "expeditions_location_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("expeditions_location_icon_scale", nil),
                        {
                            setting_id = "ignore_radar_range_for_expedition_markers",
                            type = "checkbox",
                            default_value = true,
                        },
                        _expedition_marker_display_mode_dropdown(
                            "show_expedition_objective_opportunity",
                            "icon_distance"),
                        _expedition_marker_display_mode_dropdown(
                            "show_expedition_objective_transition",
                            "icon_only"),
                        _expedition_marker_display_mode_dropdown(
                            "show_expedition_objective_main_objective",
                            "icon_only"),
                        _expedition_marker_display_mode_dropdown(
                            "show_expedition_objective_extraction",
                            "icon_only"),
                        _expedition_marker_display_mode_dropdown(
                            "show_expedition_objective_arrival",
                            "icon_only"),
                        _expedition_marker_display_mode_dropdown(
                            "show_expedition_loot_converter",
                            "icon_only"),
                    },
                },
                {
                    setting_id = "expeditions_specific_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("expeditions_specific_icon_scale", nil),
                        {
                            setting_id = "nearby_highlight_expeditions_specific",
                            type = "checkbox",
                            default_value = false,
                        },
                        _nearby_highlight_radar_distance_text_checkbox(
                            "nearby_highlight_distance_text_expeditions_specific"),
                        _artwork_icon_off_dropdown("show_expeditions_currency"),
                        _artwork_icon_off_dropdown("show_expeditions_loot"),
                        _artwork_icon_off_dropdown("show_expeditions_dropped_loot"),
                        _expedition_loot_marker_mode_dropdown("expedition_loot_marker_mode"),
                        {
                            setting_id = "expedition_loot_cluster_horizontal_radius",
                            type = "numeric",
                            default_value = 5,
                            range = { 1, 10 },
                            decimals_number = 0,
                            step_size_value = 1,
                        },
                        {
                            setting_id = "expedition_loot_cluster_vertical_radius",
                            type = "numeric",
                            default_value = 3,
                            range = { 1, 5 },
                            decimals_number = 0,
                            step_size_value = 1,
                        },
                        {
                            setting_id = "show_expedition_loot_cluster_value",
                            type = "checkbox",
                            default_value = false,
                        },
                        {
                            setting_id = "show_data_reliquaries",
                            type = "checkbox",
                            default_value = true,
                        },
                        _artwork_icon_off_dropdown("show_pocketable_landmine_explosive"),
                        _artwork_icon_off_dropdown("show_pocketable_landmine_fire"),
                        _artwork_icon_off_dropdown("show_pocketable_landmine_shock"),
                        _artwork_icon_off_dropdown("show_pocketable_void_shield"),
                        _artwork_icon_off_dropdown("show_pocketable_airstrike"),
                        _artwork_icon_off_dropdown("show_pocketable_artillery_strike"),
                        _artwork_icon_off_dropdown("show_pocketable_big_grenade"),
                        _artwork_icon_off_dropdown("show_pocketable_valkyrie_hover"),
                        {
                            setting_id = "show_promethium_barrel",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_large_ammunition_crate",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_anti_rad_stimm",
                            type = "checkbox",
                            default_value = true,
                        },
                    },
                },
                {
                    setting_id = "martyr_s_skull_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("martyr_s_skull_icon_scale", nil),
                        {
                            setting_id = "nearby_highlight_martyr_s_skull",
                            type = "checkbox",
                            default_value = false,
                        },
                        _nearby_highlight_radar_distance_text_checkbox("nearby_highlight_distance_text_martyr_s_skull"),
                        {
                            setting_id = "show_martyr_skull",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_power_cell_orange",
                            type = "checkbox",
                            default_value = true,
                        },
                    },
                },
                {
                    setting_id = "environment_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("environment_icon_scale", nil),
                        {
                            setting_id = "nearby_highlight_environment",
                            type = "checkbox",
                            default_value = false,
                        },
                        _nearby_highlight_radar_distance_text_checkbox("nearby_highlight_distance_text_environment"),
                        {
                            setting_id = "show_medicae_station",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_luggable_socket",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_heretic_idol",
                            type = "checkbox",
                            default_value = true,
                        },
                    },
                },
                {
                    setting_id = "deployables_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("deployables_icon_scale"),
                        {
                            setting_id = "show_ammo_crate_deployable",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_medical_crate_deployable",
                            type = "checkbox",
                            default_value = true,
                        },
                    },
                },
                {
                    setting_id = "enemies_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("enemies_icon_scale", "enemies_icon_scale"),
                        {
                            setting_id = "boss_display_style",
                            type = "dropdown",
                            default_value = "marked_icon",
                            options = {
                                {
                                    text = "display_style_icon_only",
                                    value = "icon_only",
                                },
                                {
                                    text = "display_style_marked_icon",
                                    value = "marked_icon",
                                },
                            },
                        },
                        {
                            setting_id = "boss_marker_range_mode",
                            type = "dropdown",
                            default_value = "normal",
                            options = {
                                {
                                    text = "boss_marker_range_mode_normal",
                                    value = "normal",
                                },
                                {
                                    text = "boss_marker_range_mode_infinite",
                                    value = "infinite",
                                },
                            },
                            get = function()
                                return mod:get_boss_marker_range_mode()
                            end,
                            change = function(new_value)
                                mod:set("boss_marker_range_mode", new_value)
                            end,
                        },
                        {
                            setting_id = "show_boss_distance_text",
                            type = "checkbox",
                            default_value = true,
                        },
                        _icon_scale_slider("enemy_boss_icon_scale", "enemy_boss_icon_scale"),
                        {
                            setting_id = "show_monstrosities",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_captains",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_karnak_twins",
                            type = "checkbox",
                            default_value = true,
                        },
                        _enemy_vertical_arrows_checkbox("show_enemy_boss_vertical_arrows"),
                        _icon_scale_slider("enemy_horde_icon_scale", "enemy_horde_icon_scale"),
                        {
                            setting_id = "show_enemy_horde",
                            type = "checkbox",
                            default_value = false,
                            tooltip = "horde_tooltip",
                        },
                        _enemy_vertical_arrows_checkbox("show_enemy_horde_vertical_arrows"),
                        _icon_scale_slider("enemy_common_icon_scale", "enemy_common_icon_scale"),
                        _icon_marked_off_dropdown("show_enemy_common", "icon_only"),
                        _enemy_vertical_arrows_checkbox("show_enemy_common_vertical_arrows"),
                        _icon_scale_slider("enemy_shooter_icon_scale", "enemy_shooter_icon_scale"),
                        _icon_marked_off_dropdown("show_enemy_shooter", "icon_only"),
                        _enemy_vertical_arrows_checkbox("show_enemy_shooter_vertical_arrows"),
                        _icon_scale_slider("enemy_elite_icon_scale", "enemy_elite_icon_scale"),
                        _icon_marked_off_dropdown("show_enemy_cultist_gunner", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_cultist_berzerker", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_cultist_shocktrooper", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_renegade_gunner", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_renegade_executor", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_renegade_plasma_gunner", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_renegade_berzerker", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_renegade_shocktrooper", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_chaos_ogryn_bulwark", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_chaos_ogryn_executor", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_chaos_ogryn_gunner", "icon_only"),
                        _enemy_vertical_arrows_checkbox("show_enemy_elite_vertical_arrows"),
                        _icon_scale_slider("enemy_special_icon_scale", "enemy_special_icon_scale"),
                        _icon_marked_off_dropdown("show_enemy_renegade_grenadier", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_cultist_grenadier", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_renegade_flamer", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_cultist_flamer", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_cultist_mutant", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_chaos_poxwalker_bomber", "marked_icon"),
                        _icon_marked_off_dropdown("show_enemy_chaos_armored_hound", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_chaos_hound", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_renegade_sniper", "icon_only"),
                        _icon_marked_off_dropdown("show_enemy_renegade_netgunner", "marked_icon"),
                        _enemy_vertical_arrows_checkbox("show_enemy_special_vertical_arrows"),
                        _icon_scale_slider("enemy_misc_icon_scale", "enemy_misc_icon_scale"),
                        _icon_marked_off_dropdown("show_enemy_cultist_ritualist", "icon_only"),
                        _enemy_vertical_arrows_checkbox("show_enemy_misc_vertical_arrows"),
                    },
                },
                {
                    setting_id = "players_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("players_icon_scale", nil),
                        {
                            setting_id = "show_players",
                            title = "show_teammates",
                            tooltip = "show_teammates_tooltip",
                            type = "checkbox",
                            default_value = true,
                            get = function()
                                if mod.get_show_players then
                                    return mod:get_show_players()
                                end

                                local value = mod:get("show_players")
                                if value == nil then
                                    value = mod:get("show_teammates")
                                end

                                return value ~= false
                            end,
                            change = function(new_value)
                                mod:set("show_players", new_value)
                            end,
                        },
                        {
                            setting_id = "show_player_center_dot",
                            tooltip = "show_player_center_dot_tooltip",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "player_marker_range_mode",
                            type = "dropdown",
                            default_value = "normal",
                            options = {
                                {
                                    text = "player_marker_range_mode_normal",
                                    value = "normal",
                                },
                                {
                                    text = "player_marker_range_mode_infinite",
                                    value = "infinite",
                                },
                            },
                            get = function()
                                return mod:get_player_marker_range_mode()
                            end,
                            change = function(new_value)
                                mod:set("player_marker_range_mode", new_value)
                            end,
                        },
                        {
                            setting_id = "player_display_style",
                            type = "dropdown",
                            default_value = "marked_icon",
                            options = {
                                {
                                    text = "display_style_icon_only",
                                    value = "icon_only",
                                },
                                {
                                    text = "display_style_marked_icon",
                                    value = "marked_icon",
                                },
                                {
                                    text = "display_style_dot_only",
                                    value = "dot_only",
                                },
                                {
                                    text = "display_style_marked_dot",
                                    value = "marked_dot",
                                },
                            },
                        },
                        {
                            setting_id = "show_player_tags",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_player_tag_distance_text",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "player_tag_display_style",
                            tooltip = "player_tag_display_style_tooltip",
                            type = "dropdown",
                            default_value = "marked_icon",
                            options = {
                                {
                                    text = "display_style_icon_only",
                                    value = "icon_only",
                                },
                                {
                                    text = "display_style_marked_icon",
                                    value = "marked_icon",
                                },
                            },
                        },
                    },
                },
                {
                    setting_id = "event_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("event_icon_scale", nil),
                        {
                            setting_id = "nearby_highlight_event",
                            type = "checkbox",
                            default_value = false,
                        },
                        _nearby_highlight_radar_distance_text_checkbox("nearby_highlight_distance_text_event"),
                        {
                            setting_id = "show_tainted_skull",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_pocketable_corrupted_auspex_scanner",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_saints",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_stolen_rations",
                            type = "checkbox",
                            default_value = true,
                        },
                    },
                },
                {
                    setting_id = "debug_group",
                    type = "group",
                    sub_widgets = {
                        _icon_scale_slider("debug_icon_scale", nil),
                        {
                            setting_id = "debug_mode",
                            type = "checkbox",
                            default_value = false,
                        },
                        {
                            setting_id = "show_unknown_pickups",
                            type = "checkbox",
                            default_value = false,
                        },
                    },
                },
            }

            _apply_missing_tooltips(widgets)

            return widgets
        end)(),
    },
}
