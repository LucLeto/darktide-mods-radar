local mod = get_mod("Radar")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIFonts = require("scripts/managers/ui/ui_fonts")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UISettings = require("scripts/settings/ui/ui_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local RadarHudRenderer = mod:io_dofile("Radar/scripts/mods/Radar/ui/Radar_hud_renderer")
local RadarHudWidgets = mod:io_dofile("Radar/scripts/mods/Radar/ui/Radar_hud_widgets")

local Color = Color
local Vector3 = Vector3
local pcall = pcall
local pairs = pairs
local rawget = rawget
local tonumber = tonumber
local tostring = tostring
local type = type
local math_clamp = math.clamp
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_rad = math.rad
local math_sqrt = math.sqrt
local math_huge = math.huge
local string_format = string.format
local string_len = string.len
local string_lower = string.lower
local string_sub = string.sub
local table_clear = table.clear or function(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local UIRenderer_begin_pass = UIRenderer.begin_pass
local UIRenderer_draw_text = UIRenderer.draw_text
local UIRenderer_end_pass = UIRenderer.end_pass

local HudElementRadar = class("HudElementRadar", "HudElementBase")

local Definitions = {
    scenegraph_definition = {
        screen = {
            scale = "fit",
            position = { 0, 0, 0 },
            size = { 1920, 1080 },
        },
    },
    widget_definitions = {},
}

local LogBuckets = {
    visuals = {},
    draws = {},
}

local PLAYER_CLASS_ICONS = {
    veteran = "content/ui/materials/icons/classes/veteran",
    zealot = "content/ui/materials/icons/classes/zealot",
    psyker = "content/ui/materials/icons/classes/psyker",
    ogryn = "content/ui/materials/icons/classes/ogryn",
    adamant = "content/ui/materials/icons/classes/adamant",
    broker = "content/ui/materials/icons/classes/broker",
}

local PLAYER_SMART_TAG_PRESENTATIONS = {
    location_attention = {
        icon = "content/ui/materials/hud/interactions/icons/attention",
        size = 15,
        use_player_color = true,
    },
    location_ping = {
        icon = "content/ui/materials/hud/interactions/icons/location",
        size = 15,
        use_player_color = true,
    },
    location_threat = {
        icon = "content/ui/materials/hud/interactions/icons/enemy",
        color = { 255, 255, 64, 64 },
        accent_color = { 220, 255, 0, 0 },
        size = 15,
    },
}

local EXPEDITION_OBJECTIVE_KINDS = {
    expedition_loot_converter = true,
    expedition_objective_opportunity = true,
    expedition_objective_transition = true,
    expedition_objective_main_objective = true,
    expedition_objective_extraction = true,
    expedition_objective_arrival = true,
}

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

local function _widget_color(a, r, g, b)
    return { a, r, g, b }
end

local WHITE_WIDGET_COLOR = { 255, 255, 255, 255 }
local RADAR_OUTLINE_WIDGET_COLOR = { 255, 213, 226, 206 }
local RADAR_LEGEND_INDICATOR_WIDGET_COLOR = { 255, 213, 226, 206 }
local MARKER_VALUE_TEXT_WIDGET_COLOR = { 255, 255, 225, 0 }
local VERTICAL_ARROW_WIDGET_COLOR = { 255, 255, 255, 255 }
local RADAR_ZOOM_INDICATOR_WIDGET_COLOR = { 210, 0, 255, 0 }

local function _any_to_widget_color(color, fallback)
    local src = color or fallback or WHITE_WIDGET_COLOR

    return {
        src[1] or src.a or 255,
        src[2] or src.r or 255,
        src[3] or src.g or 255,
        src[4] or src.b or 255,
    }
end

local function _style_color_table(style)
    if style._radar_private_color ~= true then
        style.color = _any_to_widget_color(style.color, WHITE_WIDGET_COLOR)
        style._radar_private_color = true
    end

    return style.color
end

local function _copy_into_widget_color(destination, color, fallback)
    local src = color or fallback or WHITE_WIDGET_COLOR

    destination[1] = src[1] or src.a or 255
    destination[2] = src[2] or src.r or 255
    destination[3] = src[3] or src.g or 255
    destination[4] = src[4] or src.b or 255

    return destination
end

local function _configured_marker_color(kind, fallback)
    local get_marker_color = mod.get_marker_color

    return get_marker_color and get_marker_color(mod, kind, fallback) or fallback
end

local function _configured_marker_background_color(kind, fallback)
    local get_marker_background_color = mod.get_marker_background_color

    return get_marker_background_color and get_marker_background_color(mod, kind, fallback) or fallback
end

local function _configured_enemy_icon_color(kind, fallback)
    local get_enemy_radar_icon_color = mod.get_enemy_radar_icon_color

    return get_enemy_radar_icon_color and get_enemy_radar_icon_color(mod, kind, fallback) or fallback
end

local function _configured_enemy_background_color(kind, fallback)
    local get_enemy_radar_background_color = mod.get_enemy_radar_background_color

    return get_enemy_radar_background_color and get_enemy_radar_background_color(mod, kind, fallback) or fallback
end

local function _configured_radar_color(prefix, fallback)
    local get_radar_color = mod.get_radar_color

    return get_radar_color and get_radar_color(mod, prefix, fallback) or fallback
end

local function _with_alpha_widget(color, alpha)
    local c = _any_to_widget_color(color)
    c[1] = alpha or c[1] or 255
    return c
end

local function _scaled_alpha(alpha, scale)
    local base_alpha = tonumber(alpha) or 0
    local alpha_scale = tonumber(scale) or 1

    return math_max(0, math_min(255, math_floor(base_alpha * alpha_scale + 0.5)))
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

local function _is_finite_number(v)
    return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
end

local function _ui_space_size()
    local width = 1920.0
    local height = 1080.0

    if RESOLUTION_LOOKUP and RESOLUTION_LOOKUP.width and RESOLUTION_LOOKUP.height then
        local inverse_scale = RESOLUTION_LOOKUP.inverse_scale or 1
        width = RESOLUTION_LOOKUP.width * inverse_scale
        height = RESOLUTION_LOOKUP.height * inverse_scale
    end

    return width, height
end

local function _sync_screen_scenegraph(self)
    local scenegraph = self and self._ui_scenegraph
    local screen = scenegraph and scenegraph.screen

    if not screen then
        return
    end

    local width, height = _ui_space_size()
    width = math_max(1, math_floor(width + 0.5))
    height = math_max(1, math_floor(height + 0.5))

    screen.scale = "fit"

    local size = screen.size
    if size then
        size[1] = width
        size[2] = height
    else
        screen.size = { width, height }
    end

    local position = screen.position
    if position then
        position[1] = 0
        position[2] = 0
        position[3] = 0
    else
        screen.position = { 0, 0, 0 }
    end
end

local ARTWORK_MODE_ICON_PRESENTATIONS = {
    crate_unknown = {
        icon = "content/ui/materials/icons/generic/loot",
        color = _widget_color(255, 225, 200, 136),
        size = 20,
    },
    material_diamantine = {
        icon = "content/ui/materials/hud/interactions/icons/environment_generic",
        color = _widget_color(255, 70, 130, 220),
        size = 14,
    },
    material_plasteel = {
        icon = "content/ui/materials/hud/interactions/icons/environment_generic",
        color = _widget_color(255, 130, 135, 140),
        size = 14,
    },
    material_expeditions_currency = {
        icon = "content/ui/materials/hud/interactions/icons/expeditions_salvage",
        color = _widget_color(255, 120, 160, 140),
        size = 14,
    },
    material_expeditions_loot = {
        icon = "content/ui/materials/hud/interactions/icons/expeditions_loot",
        color = _widget_color(255, 192, 160, 0),
        size = 14,
    },
    material_expeditions_loot_player_drop = {
        icon = "content/ui/materials/hud/interactions/icons/expeditions_loot",
        color = _widget_color(220, 255, 0, 0),
        size = 14,
    },
    pocketable_airstrike = {
        icon = "content/ui/materials/hud/interactions/icons/valkyrie_payload",
        color = _widget_color(255, 95, 125, 70),
        size = 14,
    },
    pocketable_artillery_strike = {
        icon = "content/ui/materials/hud/interactions/icons/artillery_strike",
        color = _widget_color(255, 95, 125, 70),
        size = 14,
    },
    pocketable_big_grenade = {
        icon = "content/ui/materials/hud/interactions/icons/big_fn_grenade",
        color = _widget_color(255, 205, 156, 77),
        size = 14,
    },
    pocketable_valkyrie_hover = {
        icon = "content/ui/materials/hud/interactions/icons/valkyrie_hover",
        color = _widget_color(255, 95, 125, 70),
        size = 14,
    },
    pocketable_landmine_explosive = {
        icon = "content/ui/materials/hud/interactions/icons/landmine_explosive",
        color = _widget_color(255, 205, 156, 77),
        size = 14,
    },
    pocketable_landmine_fire = {
        icon = "content/ui/materials/hud/interactions/icons/landmine_fire",
        color = _widget_color(255, 255, 110, 0),
        size = 14,
    },
    pocketable_landmine_shock = {
        icon = "content/ui/materials/hud/interactions/icons/landmine_shock",
        color = _widget_color(255, 80, 160, 255),
        size = 14,
    },
    pocketable_void_shield = {
        icon = "content/ui/materials/hud/interactions/icons/void_shield",
        color = _widget_color(255, 181, 166, 66),
        size = 14,
    },
}

local PRESENTATIONS = {
    enemy_daemonhost = {
        icon = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_heinous_rituals",
        color = _widget_color(255, 255, 64, 64),
        accent_color = _widget_color(220, 255, 0, 0),
        size = 16,
    },
    enemy_monstrosity = {
        icon = "content/ui/materials/icons/presets/preset_05",
        color = _widget_color(255, 255, 64, 64),
        accent_color = _widget_color(220, 255, 0, 0),
        size = 16,
    },
    enemy_captain = {
        icon = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_fading_light_1",
        color = _widget_color(255, 255, 64, 64),
        accent_color = _widget_color(220, 255, 0, 0),
        size = 16,
    },
    enemy_karnak_twin = {
        icon = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_fading_light_2",
        color = _widget_color(255, 255, 64, 64),
        accent_color = _widget_color(220, 255, 0, 0),
        size = 16,
    },
    pickup_ammo_small = {
        icon = "content/ui/materials/hud/interactions/icons/ammunition",
        color = _widget_color(255, 240, 210, 80),
        size = 14,
    },
    pickup_ammo_big = {
        icon = "content/ui/materials/icons/presets/preset_16",
        color = _widget_color(255, 240, 210, 80),
        size = 14,
    },
    pickup_large_ammunition_crate = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_ammo",
        color = _widget_color(255, 240, 210, 80),
        size = 14,
    },
    pickup_grenade = {
        icon = "content/ui/materials/hud/interactions/icons/grenade",
        color = _widget_color(255, 205, 156, 77),
        size = 14,
    },
    pickup_ammo_cache_deployable = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_ammo",
        color = _widget_color(255, 240, 210, 80),
        size = 7,
    },
    pickup_medkit = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_medkit",
        color = _widget_color(255, 38, 205, 26),
        size = 7,
    },
    medical_crate_deployable = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_medkit",
        color = _widget_color(255, 38, 205, 26),
        size = 14,
    },
    pickup_coordinates_paper = {
        icon = "content/ui/materials/icons/system/escape/credits",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    luggable_data_reliquary = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 192, 160, 0),
        size = 25,
    },
    luggable_power_cell_teal = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 0, 200, 200),
        size = 25,
    },
    luggable_power_cell_orange = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 255, 140, 0),
        size = 25,
    },
    luggable_cryonic_rod = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 180, 220, 255),
        size = 25,
    },
    luggable_moebian_pox_zetaphyte_13_sample = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 150, 190, 60),
        size = 25,
    },
    luggable_vacuum_capsule = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 80, 85, 90),
        size = 25,
    },
    luggable_special_issue_ammo = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 95, 125, 70),
        size = 25,
    },
    luggable_prismata_crystal_repository = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 255, 70, 90),
        size = 25,
    },
    luggable_promethium_barrel = {
        icon = "content/ui/materials/hud/interactions/icons/barrel_explosive",
        color = _widget_color(255, 255, 110, 0),
        size = 14,
    },
    pickup_unknown = {
        icon = "content/ui/materials/icons/traits/empty",
        size = 14,
    },
    medicae_station = {
        icon = "content/ui/materials/hud/interactions/icons/respawn",
        color = _widget_color(255, 38, 205, 26),
        size = 20,
    },
    luggable_socket = {
        icon = "content/ui/materials/icons/presets/preset_11",
        color = _widget_color(255, 255, 245, 80),
        size = 14,
    },
    pickup_heretic_idol = {
        icon = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_rampaging_enemies",
        color = _widget_color(255, 150, 190, 60),
        size = 14,
    },
    pickup_mortis_relic = {
        icon = "content/ui/materials/icons/item_types/devices",
        color = _widget_color(255, 110, 95, 125),
        size = 14,
    },
    pickup_martyr_skull = {
        icon = "content/ui/materials/hud/interactions/icons/enemy",
        color = _widget_color(255, 255, 215, 0),
        size = 14,
    },
    pickup_tainted_skull = {
        icon = "content/ui/materials/hud/interactions/icons/enemy",
        color = _widget_color(255, 150, 190, 60),
        size = 14,
    },
    dark_rites_totem = {
        icon = "content/ui/materials/icons/achievements/categories/category_heretics",
        color = _widget_color(255, 150, 190, 60),
        size = 20,
    },
    dark_rites_servo_skull = {
        icon = "content/ui/materials/icons/abilities/default",
        color = _widget_color(255, 150, 190, 60),
        size = 14,
    },
    pickup_saints = {
        icon = "content/ui/materials/icons/circumstances/live_event_01",
        color = _widget_color(255, 192, 160, 0),
        size = 14,
    },
    pickup_stolen_rations = {
        icon = "content/ui/materials/icons/pickups/default",
        color = _widget_color(255, 150, 190, 60),
        size = 14,
    },
    crate_unknown = {
        icon = "content/ui/materials/icons/engrams/engram_rarity_04",
        color = WHITE_WIDGET_COLOR,
        size = 20,
    },
    material_diamantine = {
        icon = "content/ui/materials/icons/currencies/diamantine_big",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    material_plasteel = {
        icon = "content/ui/materials/icons/currencies/plasteel_big",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    material_expeditions_currency = {
        icon = "content/ui/materials/icons/currencies/salvage_big",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    material_expeditions_loot = {
        icon = "content/ui/materials/icons/currencies/tech_remnant_big",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    material_expeditions_loot_player_drop = {
        icon = "content/ui/materials/icons/notifications/tech_dropped",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    pocketable_ammo_crate = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_ammo_crate",
        color = _widget_color(255, 240, 210, 80),
        size = 14,
    },
    pocketable_anti_rad_stimm = {
        icon = "content/ui/materials/hud/interactions/icons/time_syringe",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    pocketable_corrupted_auspex_scanner = {
        icon = "content/ui/materials/icons/pocketables/hud/auspex_scanner",
        color = _widget_color(255, 255, 120, 0),
        size = 14,
    },
    pocketable_airstrike = {
        icon = "content/ui/materials/icons/throwables/hud/valkyrie_payload",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    pocketable_artillery_strike = {
        icon = "content/ui/materials/icons/throwables/hud/artillery_strike",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    pocketable_big_grenade = {
        icon = "content/ui/materials/icons/throwables/hud/big_fn_grenade",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    pocketable_grimoire = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_grimoire",
        color = _widget_color(255, 150, 190, 60),
        size = 14,
    },
    pocketable_landmine_explosive = {
        icon = "content/ui/materials/icons/pocketables/hud/landmine_explosive",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    pocketable_landmine_fire = {
        icon = "content/ui/materials/icons/pocketables/hud/landmine_fire",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    pocketable_landmine_shock = {
        icon = "content/ui/materials/icons/pocketables/hud/landmine_shock",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    pocketable_medical_crate = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_medic_crate",
        color = _widget_color(255, 38, 205, 26),
        size = 14,
    },
    pocketable_scripture = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_scripture",
        color = _widget_color(255, 192, 160, 0),
        size = 14,
    },
    pocketable_syringe_ability = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_ability",
        color = _widget_color(255, 230, 192, 13),
        size = 14,
    },
    pocketable_syringe_corruption = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_corruption",
        color = _widget_color(255, 38, 205, 26),
        size = 14,
    },
    pocketable_syringe_power = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_power",
        color = _widget_color(255, 205, 51, 26),
        size = 14,
    },
    pocketable_syringe_speed = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_speed",
        color = _widget_color(255, 0, 127, 218),
        size = 14,
    },
    pocketable_valkyrie_hover = {
        icon = "content/ui/materials/icons/throwables/hud/valkyrie_hover",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    pocketable_void_shield = {
        icon = "content/ui/materials/icons/pocketables/hud/void_shield",
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
}

local MAX_RADAR_MARKERS = RadarHudWidgets.MAX_RADAR_MARKERS

local function _normalized_player_display_style(value)
    value = tostring(value or "marked_icon")

    if value ~= "icon_only"
        and value ~= "marked_icon"
        and value ~= "dot_only"
        and value ~= "marked_dot" then
        value = "marked_icon"
    end

    return value
end

local function _normalized_enemy_display_style(value)
    value = tostring(value or "marked_icon")
    return value == "icon_only" and "icon_only" or "marked_icon"
end

local _icon_scale_factor
local _draw_cache = {
    marker_display_mode_by_kind = {},
    expedition_marker_display_mode_by_kind = {},
    enemy_marker_mode_by_kind = {},
    marker_scale_by_group = {},
    enemy_scale_by_kind = {},
    enemy_visual_by_kind = {},
    nearby_highlight_enabled_by_kind = {},
    nearby_highlight_distance_text_enabled_by_kind = {},
    show_player_tag_distance_text = false,
    show_boss_distance_text = false,
    show_ability_marked_enemies = false,
    show_nearby_highlight_distance_text_on_screen = false,
    nearby_highlight_range_sq = 0,
    nearby_highlight_thickness = 0,
}

local function _build_draw_cache()
    local draw_cache = _draw_cache
    local get = mod.get
    local get_show_player_center_dot = mod.get_show_player_center_dot
    local get_player_display_style = mod.get_player_display_style
    local get_show_ability_marked_enemies = mod.get_show_ability_marked_enemies
    local get_expedition_loot_marker_mode = mod.get_expedition_loot_marker_mode
    local get_show_expedition_loot_value_text = mod.get_show_expedition_loot_value_text
    local show_nearby_highlight_distance_text_on_screen = mod.show_nearby_highlight_distance_text_on_screen
    local get_nearby_highlight_range = mod.get_nearby_highlight_range
    local get_nearby_highlight_thickness = mod.get_nearby_highlight_thickness

    table_clear(draw_cache.marker_display_mode_by_kind)
    table_clear(draw_cache.expedition_marker_display_mode_by_kind)
    table_clear(draw_cache.enemy_marker_mode_by_kind)
    table_clear(draw_cache.marker_scale_by_group)
    table_clear(draw_cache.enemy_scale_by_kind)
    table_clear(draw_cache.enemy_visual_by_kind)
    table_clear(draw_cache.nearby_highlight_enabled_by_kind)
    table_clear(draw_cache.nearby_highlight_distance_text_enabled_by_kind)

    draw_cache.icon_scale = _icon_scale_factor()
    draw_cache.player_display_style = get_player_display_style and get_player_display_style(mod) or
        _normalized_player_display_style(get(mod, "player_display_style"))
    draw_cache.player_tag_display_style = _normalized_enemy_display_style(get(mod, "player_tag_display_style"))
    local show_player_center_dot = get(mod, "show_player_center_dot")
    draw_cache.show_player_center_dot = get_show_player_center_dot and get_show_player_center_dot(mod) or
        (show_player_center_dot ~= false and show_player_center_dot ~= "off")
    draw_cache.show_player_tag_distance_text = get(mod, "show_player_tag_distance_text") == true
    draw_cache.boss_display_style = _normalized_enemy_display_style(get(mod, "boss_display_style"))
    draw_cache.show_ability_marked_enemies = get_show_ability_marked_enemies and
        get_show_ability_marked_enemies(mod) or false
    draw_cache.expedition_loot_marker_mode = get_expedition_loot_marker_mode and
        get_expedition_loot_marker_mode(mod) or "default"
    draw_cache.show_expedition_loot_value_text = get_show_expedition_loot_value_text and
        get_show_expedition_loot_value_text(mod) or false
    draw_cache.show_boss_distance_text = get(mod, "show_boss_distance_text") == true
    draw_cache.show_nearby_highlight_distance_text_on_screen = show_nearby_highlight_distance_text_on_screen and
        show_nearby_highlight_distance_text_on_screen(mod) or false
    local nearby_highlight_range = get_nearby_highlight_range and get_nearby_highlight_range(mod) or 10
    draw_cache.nearby_highlight_range_sq = nearby_highlight_range * nearby_highlight_range
    draw_cache.nearby_highlight_thickness = get_nearby_highlight_thickness and
        get_nearby_highlight_thickness(mod) or 0
    draw_cache.slot_colors = UISettings and UISettings.player_slot_colors or nil
    draw_cache.debug_mode = get(mod, "debug_mode") == true

    return draw_cache
end

_icon_scale_factor = function()
    if mod:get("scale_icons_with_radar_size") == false then
        return 1
    end

    local radar_size = mod.get_configured_radar_size and mod:get_configured_radar_size()
        or tonumber(mod:get("radar_size")) or 300
    local scale = radar_size / 300

    if scale < 0.5 then
        scale = 0.5
    elseif scale > 3.0 then
        scale = 3.0
    end

    return scale
end

local function _scaled_icon_size(base_size, icon_scale, min_size, max_size)
    local scale = tonumber(icon_scale) or _icon_scale_factor()
    local scaled = math_floor((tonumber(base_size) or 14) * scale + 0.5)
    local resolved_min = tonumber(min_size) or 1
    local resolved_max = tonumber(max_size)

    if scaled < resolved_min then
        scaled = resolved_min
    end

    if resolved_max and scaled > resolved_max then
        scaled = resolved_max
    end

    return scaled
end

local function _cached_group_icon_scale(kind, draw_cache)
    if not kind then
        return 1
    end

    local get_marker_scale_group = mod.get_marker_scale_group
    local group_name = get_marker_scale_group and get_marker_scale_group(mod, kind)

    if not group_name then
        return 1
    end

    local cache = draw_cache and draw_cache.marker_scale_by_group

    if cache then
        local cached = cache[group_name]

        if cached ~= nil then
            return cached
        end

        local get_marker_scale_factor = mod.get_marker_scale_factor
        cached = get_marker_scale_factor and get_marker_scale_factor(mod, group_name) or 1
        cache[group_name] = cached

        return cached
    end

    local get_marker_scale_factor = mod.get_marker_scale_factor
    return get_marker_scale_factor and get_marker_scale_factor(mod, group_name) or 1
end

local function _has_enemy_prefix(kind)
    if kind == nil then
        return false
    end

    if type(kind) == "string" then
        return string_sub(kind, 1, 6) == "enemy_"
    end

    return string_sub(tostring(kind), 1, 6) == "enemy_"
end

local function _cached_enemy_category_icon_scale(kind, draw_cache)
    if not _has_enemy_prefix(kind) then
        return 1
    end

    local cache = draw_cache and draw_cache.enemy_scale_by_kind

    if cache then
        local cached = cache[kind]

        if cached ~= nil then
            return cached
        end

        local get_enemy_category_scale_factor = mod.get_enemy_category_scale_factor
        cached = get_enemy_category_scale_factor and get_enemy_category_scale_factor(mod, kind) or 1
        cache[kind] = cached

        return cached
    end

    local get_enemy_category_scale_factor = mod.get_enemy_category_scale_factor
    return get_enemy_category_scale_factor and get_enemy_category_scale_factor(mod, kind) or 1
end

local function _resolved_icon_scale_for_target(target, draw_cache)
    local scale = tonumber(draw_cache and draw_cache.icon_scale) or _icon_scale_factor()
    local kind = target and target.kind

    if kind then
        scale = scale * _cached_group_icon_scale(kind, draw_cache)

        if _has_enemy_prefix(kind) then
            scale = scale * _cached_enemy_category_icon_scale(kind, draw_cache)
        end
    end

    return scale
end

local function _enemy_icon_size_limits(kind)
    local get_enemy_radar_definition = mod.get_enemy_radar_definition
    local definition = get_enemy_radar_definition and get_enemy_radar_definition(mod, kind)
    local category = definition and definition.category or nil

    if category == "special" or category == "elite" or category == "misc" then
        return 10, 72
    end

    if category == "shooter" then
        return 8, 56
    end

    if category == "common" then
        return 6, 40
    end

    if category == "horde" then
        return 6, 28
    end

    return 10, 72
end

local function _target_icon_size(target, visual, draw_cache)
    local base_size = visual and visual.size or 14
    local icon_scale = _resolved_icon_scale_for_target(target, draw_cache)

    if target and _has_enemy_prefix(target.kind) then
        local min_size, max_size = _enemy_icon_size_limits(target.kind)
        return _scaled_icon_size(base_size, icon_scale, min_size, max_size)
    end

    return _scaled_icon_size(base_size, icon_scale, 10, 48)
end

local function _target_bracket_size(target, visual, draw_cache, marker_size)
    local base_size = visual and (visual.bracket_base_size or visual.size) or 14

    if target and _has_enemy_prefix(target.kind) then
        local base_marker_size = tonumber(visual and visual.size) or base_size
        local actual_marker_size = tonumber(marker_size) or _target_icon_size(target, visual, draw_cache)
        local actual_marker_scale = actual_marker_size / math_max(1, base_marker_size)
        local bracket_scale = 1 + (actual_marker_scale - 1)
        local min_size, max_size = _enemy_icon_size_limits(target.kind)

        return _scaled_icon_size(base_size, bracket_scale, min_size, max_size)
    end

    local icon_scale = _resolved_icon_scale_for_target(target, draw_cache)

    return _scaled_icon_size(base_size, icon_scale, 10, 64)
end

local function _is_enemy_kind(kind)
    return _has_enemy_prefix(kind)
end

local function _is_expedition_objective_kind(kind)
    return kind ~= nil and EXPEDITION_OBJECTIVE_KINDS[kind] == true
end

local function _normalized_enemy_marker_mode(value)
    value = tostring(value or "icon_only")

    if value ~= "icon_only" and value ~= "marked_icon" and value ~= "off" then
        value = "icon_only"
    end

    return value
end

local function _is_boss_enemy_kind(kind)
    return kind == "enemy_daemonhost"
        or kind == "enemy_monstrosity"
        or kind == "enemy_captain"
        or kind == "enemy_karnak_twin"
end

local function _enemy_marker_mode_for_kind(kind, draw_cache)
    if _is_boss_enemy_kind(kind) then
        return draw_cache and draw_cache.boss_display_style or
            _normalized_enemy_display_style(mod:get("boss_display_style"))
    end

    if draw_cache then
        local cache = draw_cache.enemy_marker_mode_by_kind
        local mode = cache[kind]

        if mode == nil then
            local get_enemy_marker_mode = mod.get_enemy_marker_mode
            mode = get_enemy_marker_mode and get_enemy_marker_mode(mod, kind) or "off"
            mode = _normalized_enemy_marker_mode(mode)
            cache[kind] = mode
        end

        return mode
    end

    local get_enemy_marker_mode = mod.get_enemy_marker_mode
    return _normalized_enemy_marker_mode(get_enemy_marker_mode and get_enemy_marker_mode(mod, kind) or "off")
end

local function _display_style_for_kind(kind, draw_cache)
    if kind == "player_teammate" then
        if draw_cache and draw_cache.player_display_style then
            return draw_cache.player_display_style
        end

        local get_player_display_style = mod.get_player_display_style

        return get_player_display_style and get_player_display_style(mod) or
            _normalized_player_display_style(mod:get("player_display_style"))
    end

    if PLAYER_SMART_TAG_PRESENTATIONS[kind] ~= nil then
        return draw_cache and draw_cache.player_tag_display_style or
            _normalized_enemy_display_style(mod:get("player_tag_display_style"))
    end

    if _is_enemy_kind(kind) then
        return _enemy_marker_mode_for_kind(kind, draw_cache)
    end

    if _is_expedition_objective_kind(kind) then
        return "marked_icon"
    end

    return "icon_only"
end

local function _target_has_ability_outline_mark(target)
    local meta = target and target.meta or nil

    return meta ~= nil and meta.ability_marked == true
end

local function _target_bracket_color(target, visual)
    local meta = target and target.meta or nil
    local ability_outline_bracket_color = meta and meta.ability_outline_bracket_color or nil

    if ability_outline_bracket_color ~= nil then
        return ability_outline_bracket_color
    end

    return visual and visual.accent_color or nil
end

local function _should_draw_marker_brackets(target, draw_cache)
    local show_ability_marked_enemies = draw_cache and draw_cache.show_ability_marked_enemies or
        (mod.get_show_ability_marked_enemies and mod:get_show_ability_marked_enemies() or false)

    if show_ability_marked_enemies and _target_has_ability_outline_mark(target) then
        return true
    end

    local style = _display_style_for_kind(target and target.kind, draw_cache)
    return style == "marked_icon" or style == "marked_dot"
end

local MARKER_VALUE_TEXT_STYLE = table.merge_recursive(table.clone(UIFontSettings.body_small), {
    font_size = 12,
    font_type = "proxima_nova_bold",
    text_horizontal_alignment = "center",
    text_vertical_alignment = "center",
    text_color = Color(255, 255, 225, 0),
    offset = { 0, 0, 0 },
})
local _marker_value_text_scratch = {
    position = { 0, 0, 0 },
    size = { 0, 0 },
    color = { 255, 255, 225, 0 },
    options = {},
}
local OVERVIEW_SCALE_TEXT_STYLE = table.merge_recursive(table.clone(UIFontSettings.body_small), {
    font_size = 18,
    font_type = "proxima_nova_bold",
    text_horizontal_alignment = "center",
    text_vertical_alignment = "center",
    text_color = Color(255, 213, 226, 206),
    offset = { 0, 0, 0 },
})
local _overview_scale_text_scratch = {
    position = { 0, 0, 0 },
    size = { 0, 0 },
    color = { 255, 213, 226, 206 },
    options = {},
}

local function _marker_value_font_size(icon_size, digits)
    local font_size = math_max(10, math_floor(icon_size * 0.52 + 0.5))

    if digits >= 4 then
        font_size = math_max(9, font_size - 3)
    elseif digits >= 3 then
        font_size = math_max(10, font_size - 2)
    end

    return font_size
end

local function _draw_marker_value_text(ui_renderer, value_text, x, y, z, icon_size, has_arrow, value_text_color,
                                       value_text_anchor, value_text_offset_x, value_text_offset_y)
    if value_text == nil or value_text == "" then
        return
    end

    local digits = string_len(value_text)

    if digits <= 0 then
        return
    end

    local x0 = x or 0
    local y0 = y or 0
    local z0 = z or 0
    local half_icon_size = icon_size * 0.5
    local font_size = _marker_value_font_size(icon_size, digits)
    local arrow_size = math_max(6, math_floor(icon_size * 0.45 + 1))
    local text_box_width = math_max(font_size + 2, math_floor(font_size * (digits * 0.62 + 0.45) + 0.5))
    local text_box_height = font_size + 2
    local anchor = value_text_anchor or "bottom_right"
    local text_x
    local text_y

    if anchor == "top_center" then
        text_x = math_floor(x0 + half_icon_size - text_box_width * 0.5 + 0.5)
        text_y = math_floor(y0 - text_box_height - 2 + 0.5)
    elseif anchor == "bottom_center" then
        text_x = math_floor(x0 + half_icon_size - text_box_width * 0.5 + 0.5)
        text_y = math_floor(y0 + icon_size + 2 + 0.5)
    else
        text_x = math_floor(x0 + icon_size - text_box_width + 0.5)
        text_y = math_floor(y0 + icon_size - text_box_height + 0.5)

        if has_arrow then
            text_x = text_x - math_floor(arrow_size * 0.8 + 0.5)
        end
    end

    text_x = text_x + (value_text_offset_x or 0)
    text_y = text_y + (value_text_offset_y or 0)

    local scratch = _marker_value_text_scratch
    local position = scratch.position
    local size = scratch.size
    local color = scratch.color
    local options = scratch.options

    position[1] = text_x
    position[2] = text_y
    position[3] = math_floor(z0 + 4 + 0.5)

    size[1] = text_box_width
    size[2] = text_box_height

    if value_text_color ~= nil then
        color[1] = value_text_color[1] or 255
        color[2] = value_text_color[2] or 255
        color[3] = value_text_color[3] or 225
        color[4] = value_text_color[4] or 0
    else
        local marker_value_color = _configured_radar_color("marker_value_text", MARKER_VALUE_TEXT_WIDGET_COLOR)

        color[1] = marker_value_color[1]
        color[2] = marker_value_color[2]
        color[3] = marker_value_color[3]
        color[4] = marker_value_color[4]
    end

    table_clear(options)
    UIFonts.get_font_options_by_style(MARKER_VALUE_TEXT_STYLE, options)

    UIRenderer_draw_text(
        ui_renderer,
        value_text,
        font_size,
        MARKER_VALUE_TEXT_STYLE.font_type,
        Vector3(position[1], position[2], position[3]),
        size,
        color,
        options
    )
end

local ITEM_VERTICAL_ARROW_UP_ICON = "content/ui/materials/icons/circumstances/more_resistance_01"
local ITEM_VERTICAL_ARROW_DOWN_ICON = "content/ui/materials/icons/circumstances/less_resistance_01"

local function _overview_scale_font_size(radar_size)
    local font_size = math_floor((tonumber(radar_size) or 0) * 0.022 + 0.5)

    if font_size < 14 then
        font_size = 14
    elseif font_size > 24 then
        font_size = 24
    end

    return font_size
end

local function _overview_scale_text_box_size(scale_text, font_size)
    local length = string_len(scale_text or "")
    local width = math_max(font_size + 8, math_floor(font_size * (length * 0.58 + 0.9) + 0.5))
    local height = font_size + 6

    return width, height
end

local function _draw_overview_scale_text(ui_renderer, scale_text, center_x, center_y, z, font_size, text_color)
    local text_box_width, text_box_height = _overview_scale_text_box_size(scale_text, font_size)
    local scratch = _overview_scale_text_scratch
    local position = scratch.position
    local size = scratch.size
    local color = scratch.color
    local options = scratch.options
    local source_color = text_color or _configured_radar_color("radar_outline", RADAR_OUTLINE_WIDGET_COLOR)

    position[1] = math_floor((center_x or 0) - text_box_width * 0.5 + 0.5)
    position[2] = math_floor((center_y or 0) - text_box_height * 0.5 + 0.5)
    position[3] = math_floor((z or 0) + 0.5)

    size[1] = text_box_width
    size[2] = text_box_height

    color[1] = source_color[1]
    color[2] = source_color[2]
    color[3] = source_color[3]
    color[4] = source_color[4]

    table_clear(options)
    UIFonts.get_font_options_by_style(OVERVIEW_SCALE_TEXT_STYLE, options)

    UIRenderer_draw_text(
        ui_renderer,
        scale_text,
        font_size,
        OVERVIEW_SCALE_TEXT_STYLE.font_type,
        Vector3(position[1], position[2], position[3]),
        size,
        color,
        options
    )

    return text_box_width, text_box_height
end

local function _apply_overview_scale_icon(style, center_x, center_y, z, icon_size, angle, icon_color)
    local offset = style.offset
    local size = style.size
    local pivot = style.pivot
    local resolved_size = math_max(1, math_floor((tonumber(icon_size) or 0) + 0.5))

    offset[1] = math_floor((tonumber(center_x) or 0) + 0.5) - math_floor(resolved_size * 0.5)
    offset[2] = math_floor((tonumber(center_y) or 0) + 0.5) - math_floor(resolved_size * 0.5)
    offset[3] = math_floor((z or 0) + 0.5)

    size[1] = resolved_size
    size[2] = resolved_size

    pivot[1] = resolved_size * 0.5
    pivot[2] = resolved_size * 0.5
    style.angle = angle or 0
    style.color = icon_color or _configured_radar_color("radar_outline", RADAR_OUTLINE_WIDGET_COLOR)
end

local function _draw_overview_scale_overlay(self, ui_renderer, x, y, z, radar_size, radar_range)
    if not (mod.is_overview_mode_active and mod:is_overview_mode_active()) or mod:get("show_scale_legends") == false then
        return
    end

    RadarHudWidgets.ensure_overview_scale_widget(self)

    local widget = self._overview_scale_widget
    local content = widget.content
    local scale_text = string_format("%d m", math_max(1, math_floor((tonumber(radar_range) or 0) + 0.5)))
    local font_size = _overview_scale_font_size(radar_size)
    local icon_size = math_max(12, math_floor(font_size * 1.1 + 0.5))
    local gap = math_max(4, math_floor(font_size * 0.35 + 0.5))
    local center_x = x + radar_size * 0.5
    local center_y = y + radar_size * 0.5
    local text_box_width, text_box_height = _overview_scale_text_box_size(scale_text, font_size)
    local outside_gap = math_max(8, math_floor(font_size * 0.45 + 0.5))
    local x_text_center_y = y + radar_size + outside_gap + text_box_height * 0.5
    local y_text_center_x = x - outside_gap - math_max(text_box_width, icon_size) * 0.5
    local legend_color = _overview_scale_text_scratch.color

    content.normal_zoom_icon = nil

    if _current_radar_style() == "auspex" then
        local zoom_indicator_color = _configured_radar_color("radar_zoom_indicator", RADAR_ZOOM_INDICATOR_WIDGET_COLOR)

        legend_color[1] = zoom_indicator_color[1]
        legend_color[2] = zoom_indicator_color[2]
        legend_color[3] = zoom_indicator_color[3]
        legend_color[4] = zoom_indicator_color[4]
    else
        local legend_indicator_color = _configured_radar_color("radar_legend_indicator",
            RADAR_LEGEND_INDICATOR_WIDGET_COLOR)

        legend_color[1] = legend_indicator_color[1]
        legend_color[2] = legend_indicator_color[2]
        legend_color[3] = legend_indicator_color[3]
        legend_color[4] = legend_indicator_color[4]
    end

    content.overview_scale_x_left_icon = ITEM_VERTICAL_ARROW_UP_ICON
    content.overview_scale_x_right_icon = ITEM_VERTICAL_ARROW_DOWN_ICON
    content.overview_scale_y_top_icon = ITEM_VERTICAL_ARROW_UP_ICON
    content.overview_scale_y_bottom_icon = ITEM_VERTICAL_ARROW_DOWN_ICON

    _apply_overview_scale_icon(
        widget.style.overview_scale_x_left_icon,
        center_x - text_box_width * 0.5 - gap - icon_size * 0.5,
        x_text_center_y,
        z,
        icon_size,
        math_rad(90),
        legend_color
    )
    _apply_overview_scale_icon(
        widget.style.overview_scale_x_right_icon,
        center_x + text_box_width * 0.5 + gap + icon_size * 0.5,
        x_text_center_y,
        z,
        icon_size,
        math_rad(90),
        legend_color
    )
    _apply_overview_scale_icon(
        widget.style.overview_scale_y_top_icon,
        y_text_center_x,
        center_y - text_box_height * 0.5 - gap - icon_size * 0.5,
        z,
        icon_size,
        0,
        legend_color
    )
    _apply_overview_scale_icon(
        widget.style.overview_scale_y_bottom_icon,
        y_text_center_x,
        center_y + text_box_height * 0.5 + gap + icon_size * 0.5,
        z,
        icon_size,
        0,
        legend_color
    )

    UIWidget.draw(widget, ui_renderer)
    _draw_overview_scale_text(ui_renderer, scale_text, center_x, x_text_center_y, z + 1, font_size, legend_color)
    _draw_overview_scale_text(ui_renderer, scale_text, y_text_center_x, center_y, z + 1, font_size, legend_color)
end

local function _apply_marker_widget(widget, visual, x, y, z, target, icon_size, bracket_x, bracket_y, bracket_size)
    local icon_style = widget.style.icon
    local overlay_icon_style = widget.style.overlay_icon
    local title_icon_style = widget.style.title_icon
    local arrow_icon_style = widget.style.arrow_icon
    local size = tonumber(icon_size) or _scaled_icon_size(visual and visual.size or 14)
    local color = _copy_into_widget_color(_style_color_table(icon_style), visual and visual.color or nil)
    local overlay_color = overlay_icon_style and _copy_into_widget_color(
        _style_color_table(overlay_icon_style),
        visual and visual.overlay_color or nil
    ) or nil
    local title_color = title_icon_style and _copy_into_widget_color(
        _style_color_table(title_icon_style),
        visual and visual.color or nil
    ) or nil
    local vertical_state = target and target.vertical_state or nil
    local arrow_icon = nil

    if vertical_state == "up" then
        arrow_icon = ITEM_VERTICAL_ARROW_UP_ICON
    elseif vertical_state == "down" then
        arrow_icon = ITEM_VERTICAL_ARROW_DOWN_ICON
    end

    local arrow_color = arrow_icon_style and arrow_icon and _copy_into_widget_color(
        _style_color_table(arrow_icon_style),
        _configured_radar_color("vertical_arrow", VERTICAL_ARROW_WIDGET_COLOR)
    ) or nil

    widget.content.icon = visual and visual.icon or nil
    widget.content.overlay_icon = visual and visual.overlay_icon or nil
    widget.content.title_icon = visual and visual.title_icon or nil
    widget.content.arrow_icon = arrow_icon
    widget.content.value_text = visual and visual.value_text or ""

    local icon_offset = icon_style.offset
    local icon_size_tbl = icon_style.size
    local icon_z = math_floor((z or 0) + 0.5)
    local arrow_anchor_x = nil
    local arrow_anchor_y = nil
    local arrow_anchor_size = nil
    local arrow_size_base = nil

    icon_offset[1] = math_floor((x or 0) + 0.5)
    icon_offset[2] = math_floor((y or 0) + 0.5)
    icon_offset[3] = icon_z
    icon_size_tbl[1] = size
    icon_size_tbl[2] = size
    icon_style.color = color

    if target
        and _is_enemy_kind(target.kind)
        and not _is_boss_enemy_kind(target.kind) then
        local anchor_size = tonumber(bracket_size)

        if anchor_size and anchor_size > 0 then
            arrow_anchor_x = math_floor((tonumber(bracket_x) or icon_offset[1]) + 0.5)
            arrow_anchor_y = math_floor((tonumber(bracket_y) or icon_offset[2]) + 0.5)
            arrow_anchor_size = math_floor(anchor_size + 0.5)
        end

        arrow_size_base = size
    end

    if overlay_icon_style then
        local overlay_size = nil
        local overlay_base_size = visual and tonumber(visual.overlay_base_size) or nil
        local background_base_size = visual and tonumber(visual.background_base_size or visual.size) or nil

        if overlay_base_size and background_base_size and background_base_size > 0 then
            overlay_size = math_floor(size * (overlay_base_size / background_base_size) + 0.5)
        else
            overlay_size = math_floor((visual and visual.overlay_size or (size - 2)) + 0.5)
        end

        overlay_size = math_max(4, overlay_size)

        local overlay_offset = overlay_icon_style.offset
        local overlay_size_tbl = overlay_icon_style.size
        local icon_center_x = icon_offset[1] + math_floor(size * 0.5)
        local icon_center_y = icon_offset[2] + math_floor(size * 0.5)

        overlay_offset[1] = icon_center_x - math_floor(overlay_size * 0.5)
        overlay_offset[2] = icon_center_y - math_floor(overlay_size * 0.5)
        overlay_offset[3] = icon_z + 1
        overlay_size_tbl[1] = overlay_size
        overlay_size_tbl[2] = overlay_size
        overlay_icon_style.color = overlay_color

        if target
            and _is_enemy_kind(target.kind)
            and not _is_boss_enemy_kind(target.kind)
            and overlay_base_size ~= nil then
            arrow_size_base = overlay_size
        end
    end

    if title_icon_style then
        local title_offset = title_icon_style.offset
        local title_size = title_icon_style.size

        title_offset[1] = icon_offset[1]
        title_offset[2] = icon_offset[2]
        title_offset[3] = icon_z + 2
        title_size[1] = size
        title_size[2] = size
        title_icon_style.color = title_color or color
    end

    if arrow_icon_style then
        local arrow_offset = arrow_icon_style.offset
        local arrow_size_tbl = arrow_icon_style.size
        local base_x = arrow_anchor_x or icon_offset[1]
        local base_y = arrow_anchor_y or icon_offset[2]
        local base_size = arrow_anchor_size or size
        local arrow_size = math_max(6, math_floor((arrow_size_base or base_size) * 0.45 + 1))
        local overlap = math_floor(arrow_size * 0.5 + 1) + 2

        arrow_offset[1] = base_x + base_size - overlap
        arrow_offset[2] = base_y + base_size - overlap
        arrow_offset[3] = icon_z + 3
        arrow_size_tbl[1] = arrow_size
        arrow_size_tbl[2] = arrow_size
        arrow_icon_style.color = arrow_color or WHITE_WIDGET_COLOR
    end
end

local DEFAULT_INTERACTION_ICON = "content/ui/materials/hud/interactions/icons/default"
local DEFAULT_EXPEDITION_UNMARKED_COLOR = _widget_color(255, 54, 198, 49)
local _self_visual = {
    icon = DEFAULT_INTERACTION_ICON,
    color = nil,
    size = 4,
}

local EXPEDITION_UNMARKED_COLORS = {
    expedition_loot_converter = _widget_color(255, 192, 160, 0),
    expedition_objective_opportunity = DEFAULT_EXPEDITION_UNMARKED_COLOR,
    expedition_objective_transition = DEFAULT_EXPEDITION_UNMARKED_COLOR,
    expedition_objective_main_objective = DEFAULT_EXPEDITION_UNMARKED_COLOR,
    expedition_objective_extraction = DEFAULT_EXPEDITION_UNMARKED_COLOR,
    expedition_objective_arrival = DEFAULT_EXPEDITION_UNMARKED_COLOR,
}

local function _expedition_unmarked_color(target)
    local kind = target and target.kind

    return _configured_marker_color(kind, EXPEDITION_UNMARKED_COLORS[kind] or DEFAULT_EXPEDITION_UNMARKED_COLOR)
end

local function _copy_visual(visual)
    if not visual then
        return nil
    end

    local copy = {}

    for key, value in pairs(visual) do
        if type(value) == "table" then
            local value_copy = {}

            for index, item in pairs(value) do
                value_copy[index] = item
            end

            copy[key] = value_copy
        else
            copy[key] = value
        end
    end

    return copy
end

local function _is_tech_remnant_kind(kind)
    return kind == "material_expeditions_loot" or kind == "material_expeditions_loot_player_drop"
end

local function _tech_remnant_target_value(target)
    local meta = target and target.meta or nil
    local value = meta and tonumber(meta.remnant_cluster_value or meta.remnant_value) or nil

    if value and value > 0 then
        return value
    end

    return nil
end

local function _tech_remnant_scaled_size(base_size, value)
    local size = tonumber(base_size) or 14
    local amount = tonumber(value) or 0

    if amount <= 10 then
        return size
    elseif amount <= 25 then
        return size + 2
    elseif amount <= 50 then
        return size + 4
    elseif amount <= 75 then
        return size + 6
    elseif amount <= 100 then
        return size + 8
    elseif amount <= 150 then
        return size + 10
    elseif amount <= 200 then
        return size + 12
    end

    return size + 14
end

local function _tech_remnant_value_text(target, draw_cache)
    local show_value_text = draw_cache and draw_cache.show_expedition_loot_value_text or
        (mod.get_show_expedition_loot_value_text and mod:get_show_expedition_loot_value_text())

    if not show_value_text then
        return nil
    end

    if not _is_tech_remnant_kind(target and target.kind) then
        return nil
    end

    local value = _tech_remnant_target_value(target)

    if not value or value <= 0 then
        return nil
    end

    return tostring(math_floor(value + 0.5))
end

local function _distance_text_from_squared_distance(distance_sq_3d, suffix)
    distance_sq_3d = tonumber(distance_sq_3d)

    if not distance_sq_3d or distance_sq_3d < 0 then
        return nil
    end

    return math_floor(math_sqrt(distance_sq_3d) + 0.5) .. (suffix or " m")
end

local function _cached_nearby_highlight_enabled(kind, draw_cache)
    if kind == nil then
        return false
    end

    local cache = draw_cache and draw_cache.nearby_highlight_enabled_by_kind or nil

    if cache then
        local cached = cache[kind]

        if cached ~= nil then
            return cached
        end
    end

    local enabled = mod.is_nearby_highlight_enabled_for_kind and mod:is_nearby_highlight_enabled_for_kind(kind) or false

    if cache then
        cache[kind] = enabled
    end

    return enabled
end

local function _cached_nearby_highlight_distance_text_enabled(kind, draw_cache)
    if kind == nil then
        return false
    end

    local cache = draw_cache and draw_cache.nearby_highlight_distance_text_enabled_by_kind or nil

    if cache then
        local cached = cache[kind]

        if cached ~= nil then
            return cached
        end
    end

    local enabled = mod.is_nearby_highlight_distance_text_enabled_for_kind and
        mod:is_nearby_highlight_distance_text_enabled_for_kind(kind) or false

    if cache then
        cache[kind] = enabled
    end

    return enabled
end

local function _screen_nearby_highlight_item_distance_text(target, draw_cache)
    local show_distance_text = draw_cache and draw_cache.show_nearby_highlight_distance_text_on_screen or false

    if not show_distance_text then
        return nil
    end

    local kind = target and target.kind or nil

    if not _cached_nearby_highlight_enabled(kind, draw_cache) then
        return nil
    end

    local distance_sq_3d = target and tonumber(target.distance_sq_3d) or nil
    local max_distance_sq = draw_cache and tonumber(draw_cache.nearby_highlight_range_sq) or nil

    if not distance_sq_3d or distance_sq_3d < 0 then
        return nil
    end

    if max_distance_sq and distance_sq_3d > max_distance_sq then
        return nil
    end

    return _distance_text_from_squared_distance(distance_sq_3d, "m")
end

local function _radar_nearby_highlight_item_distance_text(target, draw_cache)
    local kind = target and target.kind or nil

    if not _cached_nearby_highlight_distance_text_enabled(kind, draw_cache) then
        return nil
    end

    return _distance_text_from_squared_distance(target and target.distance_sq_3d, "m")
end

local function _is_boss_distance_text_kind(kind)
    return kind == "enemy_monstrosity"
        or kind == "enemy_captain"
        or kind == "enemy_karnak_twin"
end

local function _boss_distance_text(target, draw_cache)
    local show_distance_text = draw_cache and draw_cache.show_boss_distance_text or
        (mod:get("show_boss_distance_text") == true)

    if not show_distance_text or not _is_boss_distance_text_kind(target and target.kind) then
        return nil
    end

    return _distance_text_from_squared_distance(target and target.distance_sq_3d, " m")
end

local BOSS_DISTANCE_TEXT_WIDGET_COLOR = MARKER_VALUE_TEXT_WIDGET_COLOR

local function _player_smart_tag_distance_text(target, draw_cache)
    local show_distance_text = draw_cache and draw_cache.show_player_tag_distance_text or
        (mod:get("show_player_tag_distance_text") == true)
    local kind = target and target.kind or nil

    if not show_distance_text or PLAYER_SMART_TAG_PRESENTATIONS[kind] == nil then
        return nil
    end

    return _distance_text_from_squared_distance(target and target.distance_sq_3d, " m")
end

local function _cached_expedition_marker_display_mode(kind, draw_cache)
    if kind == nil then
        return nil
    end

    local cache = draw_cache and draw_cache.expedition_marker_display_mode_by_kind or nil

    if cache then
        local cached = cache[kind]

        if cached ~= nil then
            return cached
        end
    end

    local get_expedition_marker_display_mode = mod.get_expedition_marker_display_mode
    local mode = get_expedition_marker_display_mode and get_expedition_marker_display_mode(mod, kind) or nil

    if cache then
        cache[kind] = mode or false
    end

    return mode
end

local function _expedition_marker_distance_text(target, draw_cache)
    local kind = target and target.kind or nil

    if not _is_expedition_objective_kind(kind) then
        return nil
    end

    if _cached_expedition_marker_display_mode(kind, draw_cache) ~= "icon_distance" then
        return nil
    end

    return _distance_text_from_squared_distance(target and target.distance_sq_3d, " m")
end

local function _apply_target_specific_visual_overrides(target, visual, draw_cache)
    if not visual then
        return nil
    end

    local kind = target and target.kind

    if _is_tech_remnant_kind(kind) then
        local mode = draw_cache and draw_cache.expedition_loot_marker_mode or
            (mod.get_expedition_loot_marker_mode and mod:get_expedition_loot_marker_mode() or "default")
        local meta = target and target.meta or nil
        local base_size = visual.size or 14
        local should_scale = mode == "scaled" or (meta and meta.is_tech_remnant_cluster == true) or false
        local scaled_size = should_scale and _tech_remnant_scaled_size(base_size, _tech_remnant_target_value(target)) or
            base_size
        local value_text = _tech_remnant_value_text(target, draw_cache)
        local radar_distance_text = _radar_nearby_highlight_item_distance_text(target, draw_cache)

        if scaled_size == base_size and value_text == nil and visual.value_text == nil and radar_distance_text == nil then
            return visual
        end

        local result = _copy_visual(visual)

        if should_scale then
            result.size = scaled_size
        end

        result.value_text = value_text
        result.value_text_color = value_text ~= nil and
            _configured_radar_color("marker_value_text", MARKER_VALUE_TEXT_WIDGET_COLOR) or nil

        if radar_distance_text ~= nil then
            result.secondary_value_text = radar_distance_text
            result.secondary_value_text_color = _configured_radar_color("marker_distance_text",
                BOSS_DISTANCE_TEXT_WIDGET_COLOR)
            result.secondary_value_text_anchor = "bottom_center"
            result.secondary_value_text_offset_y = -3
        end

        return result
    end

    local player_smart_tag_distance_text = _player_smart_tag_distance_text(target, draw_cache)

    if player_smart_tag_distance_text ~= nil then
        local result = _copy_visual(visual)
        result.value_text = player_smart_tag_distance_text
        result.value_text_color = _configured_radar_color("marker_distance_text", BOSS_DISTANCE_TEXT_WIDGET_COLOR)
        result.value_text_anchor = "bottom_center"
        result.value_text_offset_x = 3
        result.value_text_offset_y = -3

        return result
    end

    local boss_distance_text = _boss_distance_text(target, draw_cache)

    if boss_distance_text ~= nil then
        local result = _copy_visual(visual)
        result.value_text = boss_distance_text
        result.value_text_color = _configured_radar_color("marker_distance_text", BOSS_DISTANCE_TEXT_WIDGET_COLOR)
        result.value_text_anchor = "bottom_center"
        result.value_text_offset_x = 3
        result.value_text_offset_y = -3

        return result
    end

    local expedition_marker_distance_text = _expedition_marker_distance_text(target, draw_cache)

    if expedition_marker_distance_text ~= nil then
        local result = _copy_visual(visual)
        result.value_text = expedition_marker_distance_text
        result.value_text_color = _configured_radar_color("marker_distance_text", BOSS_DISTANCE_TEXT_WIDGET_COLOR)
        result.value_text_anchor = "bottom_center"
        result.value_text_offset_x = 3
        result.value_text_offset_y = -3

        return result
    end

    if visual.value_text ~= nil then
        return visual
    end

    local nearby_highlight_distance_text = _radar_nearby_highlight_item_distance_text(target, draw_cache)

    if nearby_highlight_distance_text == nil then
        return visual
    end

    local result = _copy_visual(visual)
    result.value_text = nearby_highlight_distance_text
    result.value_text_color = _configured_radar_color("marker_distance_text", BOSS_DISTANCE_TEXT_WIDGET_COLOR)
    result.value_text_anchor = "bottom_center"
    result.value_text_offset_y = -3

    return result
end

local function _artwork_mode(kind, draw_cache)
    local mode = nil

    if draw_cache then
        mode = draw_cache.marker_display_mode_by_kind[kind]

        if mode == nil then
            local get_marker_display_mode = mod.get_marker_display_mode
            mode = get_marker_display_mode and get_marker_display_mode(mod, kind) or false
            draw_cache.marker_display_mode_by_kind[kind] = mode
        end
    else
        local get_marker_display_mode = mod.get_marker_display_mode
        mode = get_marker_display_mode and get_marker_display_mode(mod, kind) or nil
    end

    return mode
end

local function _artwork_mode_icon_visual(kind, draw_cache)
    local mode = _artwork_mode(kind, draw_cache)

    if mode ~= "icon" then
        return nil
    end

    local visual = ARTWORK_MODE_ICON_PRESENTATIONS[kind]

    if visual ~= nil then
        visual.color = _configured_marker_color(kind, visual.color)
    end

    return visual
end

local function _expedition_objective_visual(target, draw_cache)
    local meta = target and target.meta or nil
    local marked_by_player_slot = meta and meta.marked_by_player_slot or nil
    local player_slot = tonumber(marked_by_player_slot)
    local slot_colors = draw_cache and draw_cache.slot_colors or (UISettings and UISettings.player_slot_colors)
    local player_color = player_slot and slot_colors and slot_colors[player_slot] or nil
    local default_color = _expedition_unmarked_color(target)
    local widget_color = _any_to_widget_color(player_color, default_color)

    local accent_color = nil
    local icon = nil

    if target and target.kind == "expedition_loot_converter" then
        icon = meta and meta.objective_icon or DEFAULT_INTERACTION_ICON
    else
        local interaction_icon = meta and meta.interaction_icon or nil
        icon = interaction_icon

        if icon == nil or icon == DEFAULT_INTERACTION_ICON then
            icon = meta and meta.objective_icon or DEFAULT_INTERACTION_ICON
        end
    end

    if player_slot then
        accent_color = _with_alpha_widget(player_color or widget_color, 180)
    end

    return {
        icon = icon,
        title_icon = meta and meta.objective_title_icon or nil,
        color = widget_color,
        accent_color = accent_color,
        size = 15,
    }
end

local function _same_widget_color(a, b)
    if a == b then
        return true
    end

    if not a or not b then
        return false
    end

    return a[1] == b[1]
        and a[2] == b[2]
        and a[3] == b[3]
        and a[4] == b[4]
end

local function _enemy_radar_visual(target, draw_cache)
    local kind = target and target.kind
    local cache = draw_cache and draw_cache.enemy_visual_by_kind or nil

    if cache and kind ~= nil then
        local cached = cache[kind]

        if cached ~= nil then
            return cached
        end
    end

    local get_enemy_radar_definition = mod.get_enemy_radar_definition
    local definition = get_enemy_radar_definition and get_enemy_radar_definition(mod, kind)

    if not definition then
        return nil
    end

    local definition_size = tonumber(definition.size)
    local background_size = tonumber(definition.background_size) or definition_size or 10
    local icon_size = tonumber(definition.icon_size) or definition_size or background_size
    local bracket_size = tonumber(definition.bracket_size)
    local icon = definition.icon
    local icon_color = _any_to_widget_color(_configured_enemy_icon_color(kind, definition.icon_color))
    local background_icon = definition.background_icon
    local background_color = definition.background_color and
        _any_to_widget_color(_configured_enemy_background_color(kind, definition.background_color)) or nil
    local should_compose = definition.category ~= "horde"
        and background_icon ~= nil
        and background_color ~= nil
        and icon ~= nil
    local visual = nil

    if should_compose
        and background_icon == icon
        and _same_widget_color(background_color, icon_color)
        and background_size == icon_size then
        should_compose = false
    end

    if should_compose then
        visual = {
            icon = background_icon,
            color = background_color,
            overlay_icon = icon,
            overlay_color = icon_color,
            background_base_size = background_size,
            overlay_base_size = icon_size,
            bracket_base_size = bracket_size or background_size,
            accent_color = _with_alpha_widget(background_color, 180),
            size = background_size,
        }
    else
        visual = {
            icon = icon or background_icon or DEFAULT_INTERACTION_ICON,
            color = icon_color or background_color or WHITE_WIDGET_COLOR,
            accent_color = background_color and _with_alpha_widget(background_color, 180) or nil,
            bracket_base_size = bracket_size or icon_size,
            size = icon_size,
        }
    end

    if cache and kind ~= nil then
        cache[kind] = visual
    end

    return visual
end

local function _player_smart_tag_visual(target, draw_cache)
    local kind = target and target.kind
    local presentation = kind and PLAYER_SMART_TAG_PRESENTATIONS[kind] or nil

    if not presentation then
        return nil
    end

    local widget_color = presentation.color
    local accent_color = presentation.accent_color

    if presentation.use_player_color then
        local meta = target and target.meta or nil
        local player_slot = tonumber(meta and (meta.marked_by_player_slot or meta.player_slot) or nil)
        local slot_colors = draw_cache and draw_cache.slot_colors or (UISettings and UISettings.player_slot_colors)
        local player_color = player_slot and slot_colors and slot_colors[player_slot] or nil

        widget_color = _any_to_widget_color(player_color, WHITE_WIDGET_COLOR)
        accent_color = _with_alpha_widget(player_color or widget_color, 180)
    else
        widget_color = _any_to_widget_color(widget_color, WHITE_WIDGET_COLOR)
        accent_color = accent_color and _any_to_widget_color(accent_color) or nil
    end

    return {
        icon = presentation.icon,
        color = widget_color,
        accent_color = accent_color,
        size = presentation.size or 14,
    }
end

local function _target_visual(target, draw_cache)
    if not target then
        return nil
    end

    local target_kind = target.kind
    local enemy_visual = _enemy_radar_visual(target, draw_cache)

    if enemy_visual then
        return _apply_target_specific_visual_overrides(target, enemy_visual, draw_cache)
    end

    local debug_mode = draw_cache and draw_cache.debug_mode or mod:get("debug_mode")
    local meta = target.meta or nil
    local player_smart_tag_visual = _player_smart_tag_visual(target, draw_cache)

    if player_smart_tag_visual then
        return _apply_target_specific_visual_overrides(target, player_smart_tag_visual, draw_cache)
    end

    if target_kind == "player_teammate" then
        local archetype_name = meta and meta.archetype_name and string_lower(tostring(meta.archetype_name)) or nil
        local player_slot = meta and tonumber(meta.player_slot) or nil
        local slot_colors = draw_cache and draw_cache.slot_colors or (UISettings and UISettings.player_slot_colors)
        local player_color = player_slot and slot_colors and slot_colors[player_slot] or nil
        local display_style = draw_cache and draw_cache.player_display_style or mod:get_player_display_style()
        local use_dot = display_style == "dot_only" or display_style == "marked_dot"

        local icon = use_dot and DEFAULT_INTERACTION_ICON or PLAYER_CLASS_ICONS[archetype_name]
        local widget_color = _any_to_widget_color(player_color)

        if debug_mode then
            _log_once(
                LogBuckets.visuals,
                "player:" .. tostring(archetype_name) .. ":" .. tostring(player_slot),
                string_format("[Radar] visual player | archetype=%s slot=%s icon=%s", tostring(archetype_name),
                    tostring(player_slot), tostring(icon))
            )
        end

        return {
            icon = icon,
            color = widget_color,
            accent_color = _with_alpha_widget(widget_color, 180),
            size = use_dot and 14 or 15,
        }
    end

    if _is_expedition_objective_kind(target_kind) then
        if debug_mode then
            local interaction_icon = meta and meta.interaction_icon or nil
            local objective_icon = meta and meta.objective_icon or nil
            local objective_title_icon = meta and meta.objective_title_icon or nil
            local marked_by_player_slot = meta and meta.marked_by_player_slot or nil

            _log_once(
                LogBuckets.visuals,
                "expedition:" .. tostring(target_kind) .. ":" .. tostring(interaction_icon or objective_icon) .. ":" ..
                tostring(objective_title_icon),
                string_format("[Radar] visual expedition | kind=%s icon=%s title_icon=%s marked_by=%s",
                    tostring(target_kind),
                    tostring(interaction_icon or objective_icon),
                    tostring(objective_title_icon),
                    tostring(marked_by_player_slot))
            )
        end

        return _apply_target_specific_visual_overrides(target, _expedition_objective_visual(target, draw_cache),
            draw_cache)
    end

    local icon_visual = _artwork_mode_icon_visual(target_kind, draw_cache)

    if icon_visual then
        if debug_mode then
            _log_once(
                LogBuckets.visuals,
                "icon_mode:" .. tostring(target_kind),
                string_format("[Radar] visual icon mode | kind=%s icon=%s", tostring(target_kind),
                    tostring(icon_visual.icon))
            )
        end

        return _apply_target_specific_visual_overrides(target, icon_visual, draw_cache)
    end

    local presentation = rawget(PRESENTATIONS, target_kind)

    if presentation ~= nil then
        if debug_mode then
            _log_once(
                LogBuckets.visuals,
                "kind:" .. tostring(target_kind),
                string_format("[Radar] visual presentation | kind=%s icon=%s", tostring(target_kind),
                    tostring(presentation.icon))
            )
        end

        if _artwork_mode(target_kind, draw_cache) ~= "artwork" then
            presentation.color = _configured_marker_color(target_kind, presentation.color)
        end

        presentation.accent_color = _configured_marker_background_color(target_kind, presentation.accent_color)

        return _apply_target_specific_visual_overrides(target, presentation, draw_cache)
    end

    local interaction_icon = meta and meta.interaction_icon or nil

    if interaction_icon and interaction_icon ~= "" then
        if debug_mode then
            _log_once(
                LogBuckets.visuals,
                "interaction:" .. tostring(interaction_icon),
                string_format("[Radar] visual interaction_icon | kind=%s icon=%s", tostring(target_kind),
                    tostring(interaction_icon))
            )
        end

        return _apply_target_specific_visual_overrides(target, {
            icon = interaction_icon,
            size = 14,
        }, draw_cache)
    end

    if debug_mode then
        _log_once(
            LogBuckets.visuals,
            "fallback_kind:" .. tostring(target_kind),
            string_format("[Radar] visual fallback | kind=%s icon=%s", tostring(target_kind),
                tostring(PRESENTATIONS.pickup_unknown.icon))
        )
    end

    return _apply_target_specific_visual_overrides(target, PRESENTATIONS.pickup_unknown, draw_cache)
end

local function _draw_screen_highlights(self, ui_renderer, snapshot, z, draw_cache)
    local highlights = snapshot and snapshot.screen_highlights or nil
    local highlight_count = highlights and #highlights or 0
    local highlight_thickness = draw_cache and draw_cache.nearby_highlight_thickness or 0

    if highlight_count == 0 then
        return
    end

    local fallback_camera_position = snapshot and snapshot.player_position or nil
    local fallback_rotation = snapshot and snapshot.player_rotation or nil
    local projection_context = mod.get_hud_projection_context and
        mod:get_hud_projection_context(self, fallback_camera_position, fallback_rotation) or nil

    for i = 1, highlight_count do
        local highlight = highlights[i]
        local world_position = highlight.world_position
        local fallback_world_position = highlight.fallback_world_position or world_position
        local screen_x, screen_y, camera_position, marker_draw_size

        if mod.get_interaction_world_marker_draw_data then
            screen_x, screen_y, marker_draw_size = mod:get_interaction_world_marker_draw_data(highlight.unit)
        end

        if not (screen_x and screen_y) then
            if projection_context then
                screen_x, screen_y, camera_position = mod:project_hud_world_to_screen_with_context(
                    fallback_world_position,
                    projection_context)
            else
                screen_x, screen_y, camera_position = mod:project_hud_world_to_screen(self, fallback_world_position,
                    fallback_camera_position, fallback_rotation)
            end
        else
            camera_position = mod.get_hud_player_camera_position and mod:get_hud_player_camera_position(self)
                or fallback_camera_position
        end

        if screen_x and screen_y then
            local bracket_size = mod.get_screen_highlight_bracket_size and
                mod:get_screen_highlight_bracket_size(highlight.distance_sq_3d) or 24

            if _is_finite_number(marker_draw_size) and marker_draw_size > 0 then
                bracket_size = math_max(bracket_size, math_floor(marker_draw_size + 0.5))
            end

            local draw_x = screen_x - bracket_size * 0.5
            local draw_y = screen_y - bracket_size * 0.5
            local draw_color = highlight.color
            local occlusion_world_position = marker_draw_size ~= nil and world_position or fallback_world_position

            if camera_position and occlusion_world_position then
                local ok_occluded, occluded = pcall(mod.is_hud_world_position_occluded, mod, camera_position,
                    occlusion_world_position)

                if ok_occluded and occluded == true then
                    draw_color = highlight.occluded_color or highlight.color
                end
            end

            RadarHudRenderer.draw_marker_brackets(ui_renderer, draw_x, draw_y, z, bracket_size, draw_color, highlight_thickness)

            local distance_text = _screen_nearby_highlight_item_distance_text(highlight, draw_cache)

            if distance_text ~= nil then
                _draw_marker_value_text(
                    ui_renderer,
                    distance_text,
                    draw_x,
                    draw_y,
                    z,
                    bracket_size,
                    false,
                    draw_color,
                    "top_center",
                    0,
                    -4
                )
            end
        end
    end
end

HudElementRadar.init = function(self, parent, draw_layer, start_scale, optional_context)
    HudElementRadar.super.init(self, parent, draw_layer, start_scale, Definitions)
    _sync_screen_scenegraph(self)
    RadarHudWidgets.ensure_frame_widget(self)
    RadarHudWidgets.ensure_overview_scale_widget(self)
    RadarHudWidgets.ensure_marker_widgets(self)
end

HudElementRadar.update = function(self, dt, t)
    return
end

local function _snap_center(value)
    return math_floor((tonumber(value) or 0) + 0.5)
end

local function _top_left_from_center(center_value, size)
    local snapped_center = _snap_center(center_value)
    local snapped_size = math_max(1, math_floor((tonumber(size) or 0) + 0.5))

    return snapped_center - math_floor(snapped_size * 0.5)
end

local function _draw_internal(self, ui_renderer, snapshot)
    RadarHudWidgets.ensure_overview_scale_widget(self)
    RadarHudWidgets.ensure_marker_widgets(self)

    local draw_cache = _build_draw_cache()
    local marker_widgets = self._marker_widgets
    local size = mod:get_radar_size()
    local range = mod:get_radar_range()
    local x, y, z, radius = mod:get_radar_origin(size)
    local center_x = x + radius
    local center_y = y + radius
    local debug_mode = draw_cache.debug_mode
    local UIWidget_draw = UIWidget.draw
    local apply_marker_widget = _apply_marker_widget
    local target_visual = _target_visual
    local target_icon_size = _target_icon_size
    local target_bracket_size = _target_bracket_size
    local should_draw_marker_brackets = _should_draw_marker_brackets
    local draw_marker_brackets = RadarHudRenderer.draw_marker_brackets
    local draw_marker_value_text = _draw_marker_value_text
    local snap_center = _snap_center
    local top_left_from_center = _top_left_from_center
    local base_icon_z = z + 5
    local projection_radius = radius - 8
    local live_camera_rotation = mod.get_hud_player_camera_rotation and mod:get_hud_player_camera_rotation(self)
    local projection_rotation = live_camera_rotation or (snapshot and snapshot.player_rotation) or nil

    RadarHudRenderer.draw_radar_frame(self, ui_renderer, x, y, z + 1, size, projection_rotation)

    local next_widget_index = 1
    local max_markers = mod:get_max_radar_markers()
    local max_widget_index = math_min(max_markers, MAX_RADAR_MARKERS - 1)
    local collected_marker_count = 0
    local drawn_marker_count = 0
    local center_dot_drawn = false

    if snapshot and snapshot.player_position then
        local player_pos = snapshot.player_position
        local targets = snapshot.targets or {}
        collected_marker_count = #targets
        local project_target_to_radar = mod.project_target_to_radar

        if draw_cache.show_player_center_dot then
            local player_slot = tonumber(snapshot.player_slot)
            local slot_colors = draw_cache.slot_colors
            local player_color = player_slot and slot_colors and slot_colors[player_slot] or nil

            local self_visual = _self_visual
            self_visual.color = _any_to_widget_color(player_color, WHITE_WIDGET_COLOR)

            local self_scale = (draw_cache.icon_scale or 1) * _cached_group_icon_scale("player_teammate", draw_cache)
            local self_icon_size = _scaled_icon_size(self_visual.size, self_scale, 10, 40)
            local self_draw_x = center_x - self_icon_size / 2
            local self_draw_y = center_y - self_icon_size / 2
            local self_widget = marker_widgets[MAX_RADAR_MARKERS]

            apply_marker_widget(self_widget, self_visual, self_draw_x, self_draw_y, base_icon_z, nil, self_icon_size)
            UIWidget_draw(self_widget, ui_renderer)

            center_dot_drawn = true
        end

        if debug_mode and collected_marker_count > max_markers then
            _log_once(
                LogBuckets.draws,
                "marker_pool_overflow:" .. tostring(max_markers),
                string_format("[Radar] marker pool overflow | targets=%d configured=%d pool=%d", collected_marker_count,
                    max_markers,
                    max_widget_index)
            )
        end

        for i = 1, collected_marker_count do
            if next_widget_index > max_widget_index then
                break
            end

            local target = targets[i]
            local px, py = project_target_to_radar(
                mod,
                player_pos,
                projection_rotation,
                target.position,
                projection_radius,
                range,
                target.ignore_radar_range
            )

            if px and py then
                local visual = target_visual(target, draw_cache)
                local marker_size = target_icon_size(target, visual, draw_cache)
                local bracket_size = target_bracket_size(target, visual, draw_cache, marker_size)
                local marker_center_x = snap_center(center_x + px)
                local marker_center_y = snap_center(center_y + py)

                local draw_x = top_left_from_center(marker_center_x, marker_size)
                local draw_y = top_left_from_center(marker_center_y, marker_size)
                local bracket_x = top_left_from_center(marker_center_x, bracket_size)
                local bracket_y = top_left_from_center(marker_center_y, bracket_size)

                local widget = marker_widgets[next_widget_index]
                local render_layer = tonumber(target.render_layer) or 0
                local bracket_z = z + 4 + render_layer
                local icon_z = base_icon_z + render_layer
                local bracket_color = _target_bracket_color(target, visual)
                local visual_icon = visual and visual.icon or nil
                local visual_title_icon = visual and visual.title_icon or nil
                local value_text = visual and visual.value_text or nil
                local value_text_color = visual and visual.value_text_color or nil
                local value_text_anchor = visual and visual.value_text_anchor or nil
                local value_text_offset_x = visual and visual.value_text_offset_x or nil
                local value_text_offset_y = visual and visual.value_text_offset_y or nil
                local secondary_value_text = visual and visual.secondary_value_text or nil
                local secondary_value_text_color = visual and visual.secondary_value_text_color or nil
                local secondary_value_text_anchor = visual and visual.secondary_value_text_anchor or nil
                local secondary_value_text_offset_x = visual and visual.secondary_value_text_offset_x or nil
                local secondary_value_text_offset_y = visual and visual.secondary_value_text_offset_y or nil
                local has_vertical_state = target.vertical_state ~= nil

                if bracket_color and should_draw_marker_brackets(target, draw_cache) then
                    draw_marker_brackets(ui_renderer, bracket_x, bracket_y, bracket_z, bracket_size, bracket_color)
                end

                apply_marker_widget(widget, visual, draw_x, draw_y, icon_z, target, marker_size,
                    bracket_x, bracket_y, bracket_size)

                if debug_mode then
                    _log_once(
                        LogBuckets.draws,
                        "widget_material:" .. tostring(visual_icon),
                        string_format("[Radar] widget material scheduled | material=%s title_material=%s",
                            tostring(visual_icon),
                            tostring(visual_title_icon))
                    )
                end

                local widget_ok, widget_err = pcall(UIWidget_draw, widget, ui_renderer)

                if not widget_ok then
                    if debug_mode then
                        _log_once(
                            LogBuckets.draws,
                            "widget_draw_fail:" .. tostring(visual_icon),
                            string_format("[Radar] widget draw failed | material=%s err=%s",
                                tostring(visual_icon), tostring(widget_err))
                        )
                    end

                    RadarHudRenderer.draw_box(ui_renderer, draw_x, draw_y, base_icon_z, marker_size, marker_size,
                        RadarHudRenderer.widget_to_color(visual and visual.color or nil))
                end

                draw_marker_value_text(
                    ui_renderer,
                    value_text,
                    draw_x,
                    draw_y,
                    base_icon_z,
                    marker_size,
                    has_vertical_state,
                    value_text_color,
                    value_text_anchor,
                    value_text_offset_x,
                    value_text_offset_y
                )

                draw_marker_value_text(
                    ui_renderer,
                    secondary_value_text,
                    draw_x,
                    draw_y,
                    base_icon_z,
                    marker_size,
                    has_vertical_state,
                    secondary_value_text_color,
                    secondary_value_text_anchor,
                    secondary_value_text_offset_x,
                    secondary_value_text_offset_y
                )

                next_widget_index = next_widget_index + 1
                drawn_marker_count = drawn_marker_count + 1
            end
        end
    end

    if debug_mode
        and mod.is_overview_mode_active
        and mod:is_overview_mode_active()
        and mod.log_overview_marker_draw_counts then
        mod:log_overview_marker_draw_counts(
            collected_marker_count,
            drawn_marker_count,
            max_markers,
            MAX_RADAR_MARKERS,
            center_dot_drawn
        )
    end

    _draw_overview_scale_overlay(
        self,
        ui_renderer,
        x,
        y,
        z + 30,
        size,
        (mod.is_overview_mode_active and mod:is_overview_mode_active() and mod.get_overview_zoom_range
            and mod:get_overview_zoom_range()) or range
    )

    local normal_zoom_text, normal_zoom_alpha = nil, nil

    if mod.get_normal_radar_zoom_indicator then
        normal_zoom_text, normal_zoom_alpha = mod:get_normal_radar_zoom_indicator()
    end

    if normal_zoom_text and normal_zoom_alpha and normal_zoom_alpha > 0 then
        local widget = self._overview_scale_widget

        RadarHudWidgets.clear_overview_scale_widget(widget)

        widget.content.normal_zoom_icon = "content/ui/materials/icons/crafting/replace_trait"

        local font_size = _overview_scale_font_size(size)
        local icon_size = math_max(16, math_floor(font_size * 1.3 + 0.5))
        local gap = math_max(5, math_floor(font_size * 0.35 + 0.5))
        local text_width, text_height = _overview_scale_text_box_size(normal_zoom_text, font_size)
        local box_width = icon_size + gap + text_width
        local box_height = math_max(icon_size, text_height)
        local outside_gap = math_max(8, math_floor(font_size * 0.55 + 0.5))
        local ui_width, ui_height = _ui_space_size()
        local toast_x = center_x - box_width * 0.5
        local toast_y = center_y < ui_height * 0.5
            and y + size + outside_gap
            or y - outside_gap - box_height

        if toast_y < 0 or toast_y + box_height > ui_height then
            toast_x = center_x < ui_width * 0.5
                and x + size + outside_gap
                or x - outside_gap - box_width
            toast_y = center_y - box_height * 0.5
        end

        toast_x = math_clamp(toast_x, 0, math_max(0, ui_width - box_width))
        toast_y = math_clamp(toast_y, 0, math_max(0, ui_height - box_height))

        local zoom_color = _overview_scale_text_scratch.color

        if _current_radar_style() == "auspex" then
            local zoom_indicator_color = _configured_radar_color("radar_zoom_indicator", RADAR_ZOOM_INDICATOR_WIDGET_COLOR)

            zoom_color[1] = _scaled_alpha(zoom_indicator_color[1], normal_zoom_alpha)
            zoom_color[2] = zoom_indicator_color[2]
            zoom_color[3] = zoom_indicator_color[3]
            zoom_color[4] = zoom_indicator_color[4]
        else
            local legend_indicator_color = _configured_radar_color("radar_legend_indicator",
                RADAR_LEGEND_INDICATOR_WIDGET_COLOR)

            zoom_color[1] = _scaled_alpha(legend_indicator_color[1], normal_zoom_alpha)
            zoom_color[2] = legend_indicator_color[2]
            zoom_color[3] = legend_indicator_color[3]
            zoom_color[4] = legend_indicator_color[4]
        end

        local icon_style = widget.style.normal_zoom_icon
        local icon_offset = icon_style.offset
        local icon_style_size = icon_style.size
        local icon_color = icon_style.color
        local icon_x = toast_x
        local icon_y = toast_y + (box_height - icon_size) * 0.5
        local text_center_x = toast_x + icon_size + gap + text_width * 0.5
        local toast_center_y = toast_y + box_height * 0.5

        icon_offset[1] = icon_x
        icon_offset[2] = icon_y
        icon_offset[3] = z + 50
        icon_style_size[1] = icon_size
        icon_style_size[2] = icon_size
        icon_color[1] = zoom_color[1]
        icon_color[2] = zoom_color[2]
        icon_color[3] = zoom_color[3]
        icon_color[4] = zoom_color[4]

        UIWidget.draw(widget, ui_renderer)
        _draw_overview_scale_text(ui_renderer, normal_zoom_text, text_center_x, toast_center_y, z + 51, font_size,
            zoom_color)
    end

    _draw_screen_highlights(self, ui_renderer, snapshot, z + 40, draw_cache)

    local last_active_marker_widget_index = next_widget_index - 1
    local previous_active_marker_widget_index = self._last_active_marker_widget_index or 0

    if not center_dot_drawn then
        RadarHudWidgets.clear_marker_widget(marker_widgets[MAX_RADAR_MARKERS])
    end

    if previous_active_marker_widget_index > last_active_marker_widget_index then
        for i = last_active_marker_widget_index + 1, previous_active_marker_widget_index do
            RadarHudWidgets.clear_marker_widget(marker_widgets[i])
        end
    end

    self._last_active_marker_widget_index = last_active_marker_widget_index
end

HudElementRadar.draw = function(self, dt, t, ui_renderer, render_settings, input_service)
    if not mod:is_enabled() or not mod:should_draw_radar() then
        return
    end

    local snapshot = mod:get_radar_snapshot()

    render_settings = render_settings or {}
    render_settings.start_layer = self._draw_layer

    _sync_screen_scenegraph(self)

    UIRenderer_begin_pass(ui_renderer, self._ui_scenegraph, input_service, dt, render_settings)

    local ok, err = pcall(_draw_internal, self, ui_renderer, snapshot)

    UIRenderer_end_pass(ui_renderer)

    if not ok then
        mod:error("HudElementRadar.draw failed: %s", tostring(err))
    end
end

return HudElementRadar
