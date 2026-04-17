local mod = get_mod("Radar")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIFonts = require("scripts/managers/ui/ui_fonts")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UISettings = require("scripts/settings/ui/ui_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local Color = Color
local Gui = Gui
local PhysicsWorld = PhysicsWorld
local Quaternion = Quaternion
local Vector2 = Vector2
local Vector3 = Vector3
local pcall = pcall
local pairs = pairs
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
local string_format = string.format
local string_len = string.len
local string_lower = string.lower
local string_sub = string.sub
local table_clear = table.clear

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

local _logged_visuals = {}
local _logged_draws = {}

local PLAYER_CLASS_ICONS = {
    veteran = "content/ui/materials/icons/classes/veteran",
    zealot = "content/ui/materials/icons/classes/zealot",
    psyker = "content/ui/materials/icons/classes/psyker",
    ogryn = "content/ui/materials/icons/classes/ogryn",
    adamant = "content/ui/materials/icons/classes/adamant",
    broker = "content/ui/materials/icons/classes/broker",
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
    mod:echo(message)
end

local function _widget_color(a, r, g, b)
    return { a, r, g, b }
end

local function _color(a, r, g, b)
    return Color(a, r, g, b)
end

local WHITE_WIDGET_COLOR = { 255, 255, 255, 255 }
local AUSPEX_BACKGROUND_MATERIAL = "content/ui/materials/backgrounds/scanner/scanner_map_background"
local AUSPEX_BACKGROUND_NOISE_MATERIAL = "content/ui/materials/backgrounds/scanner/scanner_background_noise"
local AUSPEX_SCAN_NOISE_MATERIAL = "content/ui/materials/backgrounds/scanner/scanner_noise"
local AUSPEX_SWEEP_MATERIAL = "content/ui/materials/backgrounds/scanner/scanner_map_radar"
local AUSPEX_BACKGROUND_WIDGET_COLOR = _widget_color(255, 0, 255, 0)
local AUSPEX_BACKGROUND_NOISE_WIDGET_COLOR = _widget_color(255, 0, 255, 0)
local AUSPEX_SCAN_NOISE_WIDGET_COLOR = _widget_color(90, 0, 255, 0)
local AUSPEX_SWEEP_WIDGET_COLOR = _widget_color(128, 0, 255, 0)
local OCCLUSION_RAYCAST_FILTERS = {
    "filter_player_character_shooting",
    "filter_ray_projectile",
    "filter_minion_shooting",
    "filter_cover",
}
local FULL_CIRCLE = math_pi * 2
local OCCLUSION_EPSILON = 0.05
local OCCLUSION_RAYCAST_MODE = "closest"
local OCCLUSION_COLLISION_FILTER = "collision_filter"
local OCCLUSION_RAYCAST_FILTER_COUNT = #OCCLUSION_RAYCAST_FILTERS

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

local function _any_to_widget_color(color, fallback)
    local src = color or fallback or WHITE_WIDGET_COLOR

    return {
        src[1] or src.a or 255,
        src[2] or src.r or 255,
        src[3] or src.g or 255,
        src[4] or src.b or 255,
    }
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

local function _safe_yaw(rotation)
    if not rotation or not Quaternion or not Quaternion.yaw then
        return nil
    end

    local ok, yaw = pcall(Quaternion.yaw, rotation)
    yaw = ok and tonumber(yaw) or nil

    if type(yaw) ~= "number" or yaw ~= yaw or yaw == math_huge or yaw == -math_huge then
        return nil
    end

    return yaw
end

local function _is_finite_number(v)
    return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
end

local function _vector3_components(vec)
    if not vec then
        return nil, nil, nil
    end

    if type(vec) == "table" then
        return vec.x, vec.y, vec.z
    end

    local ok_x, x = pcall(Vector3.x, vec)
    local ok_y, y = pcall(Vector3.y, vec)
    local ok_z, z = pcall(Vector3.z, vec)

    if ok_x and ok_y and ok_z then
        return x, y, z
    end

    return nil, nil, nil
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
        size = 14,
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
        color = WHITE_WIDGET_COLOR,
        size = 14,
    },
    medicae_station = {
        icon = "content/ui/materials/hud/interactions/icons/respawn",
        color = _widget_color(255, 38, 205, 26),
        size = 14,
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
        size = 14,
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

    Gui.rect(gui, position, size, color)
end

local function _draw_marker_brackets(ui_renderer, x, y, z, size, color)
    x = math_floor((tonumber(x) or 0) + 0.5)
    y = math_floor((tonumber(y) or 0) + 0.5)
    size = math_max(1, math_floor((tonumber(size) or 0) + 0.5))

    local thickness = size >= 16 and 2 or 1
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

    Gui.rect(
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

local function _draw_radar_guides(ui_renderer, x, y, z, size, is_circle)
    local guide_style = mod.get_radar_guides and mod:get_radar_guides() or "crosshair"

    if guide_style == "off" then
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

    local guide_color = _color(90, 255, 255, 255)

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

local function _draw_radar_frame_auspex(self, ui_renderer, x, y, z, size, camera_rotation)
    local frame_widget = self._frame_widget
    if not frame_widget then
        return
    end

    local fill_alpha = mod.get_background_opacity and mod:get_background_opacity() or 90
    local animated_sweep_enabled = mod:get("auspex_animated_sweep") ~= false
    local outline_style = mod.get_radar_outline and mod:get_radar_outline() or "solid"
    local camera_yaw = _safe_yaw(camera_rotation)
    local fill_color = _color(fill_alpha, 0, 0, 0)
    local background_inset = outline_style ~= "off" and 5 or 0
    local background_size = math_max(1, size - background_inset * 2)
    local background_x = x + background_inset
    local background_y = y + background_inset

    _draw_square_fill_soft(ui_renderer, x, y, z - 1, size, fill_color)

    frame_widget.content.background_material = AUSPEX_BACKGROUND_MATERIAL
    frame_widget.content.noise_material = AUSPEX_BACKGROUND_NOISE_MATERIAL
    frame_widget.content.scan_noise_material = AUSPEX_SCAN_NOISE_MATERIAL
    frame_widget.content.sweep_material = animated_sweep_enabled and AUSPEX_SWEEP_MATERIAL or nil

    _apply_frame_layer_style(
        frame_widget.style.background,
        background_x,
        background_y,
        z,
        background_size,
        AUSPEX_BACKGROUND_WIDGET_COLOR
    )
    do
        local background_style = frame_widget.style.background
        local background_size = background_style and background_style.size
        local background_pivot = background_style and background_style.pivot

        if background_style and not background_pivot then
            background_pivot = { 0, 0 }
            background_style.pivot = background_pivot
        end

        if background_pivot and background_size then
            background_pivot[1] = (background_size[1] or 0) * 0.5
            background_pivot[2] = (background_size[2] or 0) * 0.5
        end

        if background_style then
            background_style.angle = camera_yaw and -camera_yaw or 0
        end
    end
    _apply_frame_layer_style(
        frame_widget.style.noise,
        x,
        y,
        z + 1,
        size,
        AUSPEX_BACKGROUND_NOISE_WIDGET_COLOR
    )
    _apply_frame_layer_style(
        frame_widget.style.scan_noise,
        x,
        y,
        z + 2,
        size,
        AUSPEX_SCAN_NOISE_WIDGET_COLOR
    )
    _apply_frame_layer_style(
        frame_widget.style.sweep,
        background_x,
        background_y,
        z + 3,
        background_size,
        animated_sweep_enabled and AUSPEX_SWEEP_WIDGET_COLOR or WHITE_WIDGET_COLOR
    )

    UIWidget.draw(frame_widget, ui_renderer)

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

    _draw_radar_guides(ui_renderer, x, y, z + 1, size, is_circle)
end

local function _has_icon(content)
    return content.icon ~= nil and content.icon ~= ""
end

local function _has_overlay_icon(content)
    return content.overlay_icon ~= nil and content.overlay_icon ~= ""
end

local function _has_title_icon(content)
    return content.title_icon ~= nil and content.title_icon ~= ""
end

local function _has_arrow_icon(content)
    return content.arrow_icon ~= nil and content.arrow_icon ~= ""
end

local function _has_background_material(content)
    return content.background_material ~= nil and content.background_material ~= ""
end

local function _has_noise_material(content)
    return content.noise_material ~= nil and content.noise_material ~= ""
end

local function _has_scan_noise_material(content)
    return content.scan_noise_material ~= nil and content.scan_noise_material ~= ""
end

local function _has_sweep_material(content)
    return content.sweep_material ~= nil and content.sweep_material ~= ""
end

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
                color = WHITE_WIDGET_COLOR,
            },
            visibility_function = _has_background_material,
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
                color = WHITE_WIDGET_COLOR,
            },
            visibility_function = _has_noise_material,
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
                color = WHITE_WIDGET_COLOR,
            },
            visibility_function = _has_scan_noise_material,
        },
        {
            pass_type = "texture",
            value_id = "sweep_material",
            style_id = "sweep",
            style = {
                hdr = true,
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 4 },
                size = { 16, 16 },
                color = WHITE_WIDGET_COLOR,
            },
            visibility_function = _has_sweep_material,
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
                color = WHITE_WIDGET_COLOR,
            },
            visibility_function = _has_icon,
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
                color = WHITE_WIDGET_COLOR,
            },
            visibility_function = _has_overlay_icon,
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
                color = WHITE_WIDGET_COLOR,
            },
            visibility_function = _has_title_icon,
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
                color = WHITE_WIDGET_COLOR,
            },
            visibility_function = _has_arrow_icon,
        },
    }, "screen")
end

local MAX_RADAR_MARKERS = 200

local function _create_frame_widget()
    return UIWidget.init("RadarFrame_Auspex", _frame_definition())
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

local function _ensure_marker_widgets(self)
    if self._marker_widgets then
        return
    end

    self._marker_widgets = {}
    self._last_active_marker_widget_index = 0

    for i = 1, MAX_RADAR_MARKERS do
        self._marker_widgets[i] = _create_marker_widget(i)
    end

    if mod:get("debug_mode") == true then
        _log_once(_logged_draws, "widget_pool_init",
            string_format("[Radar] widget pool created | count=%d", MAX_RADAR_MARKERS))
    end
end

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
    enemy_marker_mode_by_kind = {},
    marker_scale_by_group = {},
    enemy_scale_by_kind = {},
    enemy_visual_by_kind = {},
    show_boss_distance_text = false,
}

local function _build_draw_cache()
    local draw_cache = _draw_cache

    table_clear(draw_cache.marker_display_mode_by_kind)
    table_clear(draw_cache.enemy_marker_mode_by_kind)
    table_clear(draw_cache.marker_scale_by_group)
    table_clear(draw_cache.enemy_scale_by_kind)
    table_clear(draw_cache.enemy_visual_by_kind)

    draw_cache.icon_scale = _icon_scale_factor()
    draw_cache.player_display_style = _normalized_player_display_style(mod:get("player_display_style"))
    draw_cache.boss_display_style = _normalized_enemy_display_style(mod:get("boss_display_style"))
    draw_cache.expedition_loot_marker_mode = mod.get_expedition_loot_marker_mode and
        mod:get_expedition_loot_marker_mode() or "default"
    draw_cache.show_expedition_loot_value_text = mod.get_show_expedition_loot_value_text and
        mod:get_show_expedition_loot_value_text() or false
    draw_cache.show_boss_distance_text = mod:get("show_boss_distance_text") == true
    draw_cache.slot_colors = UISettings and UISettings.player_slot_colors or nil
    draw_cache.debug_mode = mod:get("debug_mode") == true

    return draw_cache
end

_icon_scale_factor = function()
    if mod:get("scale_icons_with_radar_size") == false then
        return 1
    end

    local radar_size = tonumber(mod:get("radar_size")) or 300
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

    local group_name = mod.get_marker_scale_group and mod:get_marker_scale_group(kind)

    if not group_name then
        return 1
    end

    local cache = draw_cache and draw_cache.marker_scale_by_group

    if cache then
        local cached = cache[group_name]

        if cached ~= nil then
            return cached
        end

        cached = mod.get_marker_scale_factor and mod:get_marker_scale_factor(group_name) or 1
        cache[group_name] = cached

        return cached
    end

    return mod.get_marker_scale_factor and mod:get_marker_scale_factor(group_name) or 1
end

local function _cached_enemy_category_icon_scale(kind, draw_cache)
    if not kind or string_sub(tostring(kind), 1, 6) ~= "enemy_" then
        return 1
    end

    local cache = draw_cache and draw_cache.enemy_scale_by_kind

    if cache then
        local cached = cache[kind]

        if cached ~= nil then
            return cached
        end

        cached = mod.get_enemy_category_scale_factor and mod:get_enemy_category_scale_factor(kind) or 1
        cache[kind] = cached

        return cached
    end

    return mod.get_enemy_category_scale_factor and mod:get_enemy_category_scale_factor(kind) or 1
end

local function _resolved_icon_scale_for_target(target, draw_cache)
    local scale = tonumber(draw_cache and draw_cache.icon_scale) or _icon_scale_factor()
    local kind = target and target.kind

    if kind then
        scale = scale * _cached_group_icon_scale(kind, draw_cache)

        if string_sub(tostring(kind), 1, 6) == "enemy_" then
            scale = scale * _cached_enemy_category_icon_scale(kind, draw_cache)
        end
    end

    return scale
end

local function _enemy_icon_size_limits(kind)
    local definition = mod.get_enemy_radar_definition and mod:get_enemy_radar_definition(kind)
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

    if target and target.kind and string_sub(tostring(target.kind), 1, 6) == "enemy_" then
        local min_size, max_size = _enemy_icon_size_limits(target.kind)
        return _scaled_icon_size(base_size, icon_scale, min_size, max_size)
    end

    return _scaled_icon_size(base_size, icon_scale, 10, 48)
end

local function _target_bracket_size(target, visual, draw_cache, marker_size)
    local base_size = visual and (visual.bracket_base_size or visual.size) or 14

    if target and target.kind and string_sub(tostring(target.kind), 1, 6) == "enemy_" then
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
    if kind == nil then
        return false
    end

    if type(kind) == "string" then
        return string_sub(kind, 1, 6) == "enemy_"
    end

    return string_sub(tostring(kind), 1, 6) == "enemy_"
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
            mode = mod.get_enemy_marker_mode and mod:get_enemy_marker_mode(kind) or "off"
            mode = _normalized_enemy_marker_mode(mode)
            cache[kind] = mode
        end

        return mode
    end

    return _normalized_enemy_marker_mode(mod.get_enemy_marker_mode and mod:get_enemy_marker_mode(kind) or "off")
end

local function _display_style_for_kind(kind, draw_cache)
    if kind == "player_teammate" then
        return draw_cache and draw_cache.player_display_style or
            _normalized_player_display_style(mod:get("player_display_style"))
    end

    if _is_enemy_kind(kind) then
        return _enemy_marker_mode_for_kind(kind, draw_cache)
    end

    if _is_expedition_objective_kind(kind) then
        return "marked_icon"
    end

    return "icon_only"
end

local function _should_draw_marker_brackets(target, draw_cache)
    local style = _display_style_for_kind(target and target.kind, draw_cache)
    return style == "marked_icon" or style == "marked_dot"
end

local function _center_dot_color(snapshot)
    local slot_colors = UISettings and UISettings.player_slot_colors
    local player_slot = snapshot and snapshot.player_slot or nil
    local player_color = player_slot and slot_colors and slot_colors[player_slot] or nil

    if player_color then
        return _widget_to_color(_any_to_widget_color(player_color))
    end

    return _color(255, 0, 255, 0)
end

local MARKER_VALUE_TEXT_STYLE = table.merge_recursive(table.clone(UIFontSettings.body_small), {
    font_size = 12,
    font_type = "proxima_nova_bold",
    text_horizontal_alignment = "center",
    text_vertical_alignment = "center",
    text_color = Color(255, 255, 225, 0),
    offset = { 0, 0, 0 },
})
local _marker_value_text_position = { 0, 0, 0 }
local _marker_value_text_size = { 0, 0 }
local _marker_value_text_color = { 255, 255, 225, 0 }
local _marker_value_text_options = {}

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

    local position = _marker_value_text_position
    local size = _marker_value_text_size
    local color = _marker_value_text_color
    local source_color = value_text_color or color

    position[1] = text_x
    position[2] = text_y
    position[3] = math_floor(z0 + 4 + 0.5)

    size[1] = text_box_width
    size[2] = text_box_height

    color[1] = source_color[1] or 255
    color[2] = source_color[2] or 255
    color[3] = source_color[3] or 225
    color[4] = source_color[4] or 0

    table_clear(_marker_value_text_options)
    UIFonts.get_font_options_by_style(MARKER_VALUE_TEXT_STYLE, _marker_value_text_options)

    UIRenderer.draw_text(
        ui_renderer,
        value_text,
        font_size,
        MARKER_VALUE_TEXT_STYLE.font_type,
        Vector3(position[1], position[2], position[3]),
        size,
        color,
        _marker_value_text_options
    )
end

local ITEM_VERTICAL_ARROW_UP_ICON = "content/ui/materials/icons/circumstances/more_resistance_01"
local ITEM_VERTICAL_ARROW_DOWN_ICON = "content/ui/materials/icons/circumstances/less_resistance_01"

local function _apply_marker_widget(widget, visual, x, y, z, target, icon_size)
    local icon_style = widget.style.icon
    local overlay_icon_style = widget.style.overlay_icon
    local title_icon_style = widget.style.title_icon
    local arrow_icon_style = widget.style.arrow_icon
    local size = tonumber(icon_size) or _scaled_icon_size(visual and visual.size or 14)
    local color = _any_to_widget_color(visual and visual.color or nil)
    local overlay_color = _any_to_widget_color(visual and visual.overlay_color or nil)
    local vertical_state = target and target.vertical_state or nil
    local arrow_icon = nil

    if vertical_state == "up" then
        arrow_icon = ITEM_VERTICAL_ARROW_UP_ICON
    elseif vertical_state == "down" then
        arrow_icon = ITEM_VERTICAL_ARROW_DOWN_ICON
    end

    widget.content.icon = visual and visual.icon or nil
    widget.content.overlay_icon = visual and visual.overlay_icon or nil
    widget.content.title_icon = visual and visual.title_icon or nil
    widget.content.arrow_icon = arrow_icon
    widget.content.value_text = visual and visual.value_text or ""

    local icon_offset = icon_style.offset
    local icon_size_tbl = icon_style.size
    local icon_z = math_floor((z or 0) + 0.5)

    icon_offset[1] = math_floor((x or 0) + 0.5)
    icon_offset[2] = math_floor((y or 0) + 0.5)
    icon_offset[3] = icon_z
    icon_size_tbl[1] = size
    icon_size_tbl[2] = size
    icon_style.color = color

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
    end

    if title_icon_style then
        local title_offset = title_icon_style.offset
        local title_size = title_icon_style.size

        title_offset[1] = icon_offset[1]
        title_offset[2] = icon_offset[2]
        title_offset[3] = icon_z + 2
        title_size[1] = size
        title_size[2] = size
        title_icon_style.color = color
    end

    if arrow_icon_style then
        local arrow_offset = arrow_icon_style.offset
        local arrow_size_tbl = arrow_icon_style.size
        local arrow_size = math_max(6, math_floor(size * 0.45 + 1))
        local overlap = math_floor(arrow_size * 0.5 + 1) + 2

        arrow_offset[1] = icon_offset[1] + size - overlap
        arrow_offset[2] = icon_offset[2] + size - overlap
        arrow_offset[3] = icon_z + 3
        arrow_size_tbl[1] = arrow_size
        arrow_size_tbl[2] = arrow_size
        arrow_icon_style.color = WHITE_WIDGET_COLOR
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

    return EXPEDITION_UNMARKED_COLORS[kind] or DEFAULT_EXPEDITION_UNMARKED_COLOR
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

    local distance_sq_3d = target and tonumber(target.distance_sq_3d) or nil

    if not distance_sq_3d or distance_sq_3d < 0 then
        return nil
    end

    return math_floor(math_sqrt(distance_sq_3d) + 0.5) .. " m"
end

local BOSS_DISTANCE_TEXT_WIDGET_COLOR = { 255, 255, 225, 0 }

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

        if scaled_size == base_size and value_text == nil and visual.value_text == nil then
            return visual
        end

        local result = _copy_visual(visual)

        if should_scale then
            result.size = scaled_size
        end

        result.value_text = value_text

        return result
    end

    local boss_distance_text = _boss_distance_text(target, draw_cache)

    if boss_distance_text == nil then
        return visual
    end

    local result = _copy_visual(visual)
    result.value_text = boss_distance_text
    result.value_text_color = BOSS_DISTANCE_TEXT_WIDGET_COLOR
    result.value_text_anchor = "bottom_center"
    result.value_text_offset_x = 3
    result.value_text_offset_y = -3

    return result
end

local function _artwork_mode_icon_visual(kind, draw_cache)
    local mode = nil

    if draw_cache then
        mode = draw_cache.marker_display_mode_by_kind[kind]

        if mode == nil then
            mode = mod.get_marker_display_mode and mod:get_marker_display_mode(kind) or false
            draw_cache.marker_display_mode_by_kind[kind] = mode
        end
    else
        mode = mod.get_marker_display_mode and mod:get_marker_display_mode(kind) or nil
    end

    if mode ~= "icon" then
        return nil
    end

    return ARTWORK_MODE_ICON_PRESENTATIONS[kind]
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

    local definition = mod.get_enemy_radar_definition and mod:get_enemy_radar_definition(kind)

    if not definition then
        return nil
    end

    local definition_size = tonumber(definition.size)
    local background_size = tonumber(definition.background_size) or definition_size or 10
    local icon_size = tonumber(definition.icon_size) or definition_size or background_size
    local bracket_size = tonumber(definition.bracket_size)
    local icon = definition.icon
    local icon_color = _any_to_widget_color(definition.icon_color)
    local background_icon = definition.background_icon
    local background_color = definition.background_color and _any_to_widget_color(definition.background_color) or nil
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
                _logged_visuals,
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
                _logged_visuals,
                "expedition:" .. tostring(target_kind) .. ":" .. tostring(interaction_icon or objective_icon) .. ":" ..
                tostring(objective_title_icon),
                string_format("[Radar] visual expedition | kind=%s icon=%s title_icon=%s marked_by=%s",
                    tostring(target_kind),
                    tostring(interaction_icon or objective_icon),
                    tostring(objective_title_icon),
                    tostring(marked_by_player_slot))
            )
        end

        return _expedition_objective_visual(target, draw_cache)
    end

    local icon_visual = _artwork_mode_icon_visual(target_kind, draw_cache)

    if icon_visual then
        if debug_mode then
            _log_once(
                _logged_visuals,
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
                _logged_visuals,
                "kind:" .. tostring(target_kind),
                string_format("[Radar] visual presentation | kind=%s icon=%s", tostring(target_kind),
                    tostring(presentation.icon))
            )
        end

        return _apply_target_specific_visual_overrides(target, presentation, draw_cache)
    end

    local interaction_icon = meta and meta.interaction_icon or nil

    if interaction_icon and interaction_icon ~= "" then
        if debug_mode then
            _log_once(
                _logged_visuals,
                "interaction:" .. tostring(interaction_icon),
                string_format("[Radar] visual interaction_icon | kind=%s icon=%s", tostring(target_kind),
                    tostring(interaction_icon))
            )
        end

        return _apply_target_specific_visual_overrides(target, {
            icon = interaction_icon,
            color = WHITE_WIDGET_COLOR,
            size = 14,
        }, draw_cache)
    end

    if debug_mode then
        _log_once(
            _logged_visuals,
            "fallback_kind:" .. tostring(target_kind),
            string_format("[Radar] visual fallback | kind=%s icon=%s", tostring(target_kind),
                tostring(PRESENTATIONS.pickup_unknown.icon))
        )
    end

    return _apply_target_specific_visual_overrides(target, PRESENTATIONS.pickup_unknown, draw_cache)
end

local function _safe_player_camera(self)
    local parent = self and self._parent

    if not parent or not parent.player_camera then
        return nil
    end

    local ok_camera, camera = pcall(parent.player_camera, parent)

    if ok_camera and camera then
        return camera
    end

    return nil
end

local function _safe_player_camera_position(self)
    local camera = _safe_player_camera(self)

    if not camera or not Camera or not Camera.local_position then
        return nil
    end

    local ok_position, position = pcall(Camera.local_position, camera)

    if ok_position and position then
        local x, y, z = _vector3_components(position)

        if _is_finite_number(x) and _is_finite_number(y) and _is_finite_number(z) then
            return { x = x, y = y, z = z }
        end
    end

    return nil
end

local function _safe_player_vertical_fov()
    local local_player = _safe_local_player()

    if not local_player then
        return nil
    end

    local viewport_name = local_player.viewport_name
    local camera_manager = Managers and Managers.state and Managers.state.camera

    if not viewport_name or not camera_manager or type(camera_manager.fov) ~= "function" then
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

    if vertical_fov and vertical_fov > 0 then
        return vertical_fov
    end

    return nil
end

local function _rotation_basis(rotation)
    if not rotation then
        return nil
    end

    local ok_forward, forward = pcall(Quaternion.forward, rotation)
    local ok_right, right = pcall(Quaternion.right, rotation)
    local ok_up, up = pcall(Quaternion.up, rotation)

    if not ok_forward or not ok_right or not ok_up or not forward or not right or not up then
        return nil
    end

    local fx, fy, fz = _vector3_components(forward)
    local rx, ry, rz = _vector3_components(right)
    local ux, uy, uz = _vector3_components(up)

    if not (_is_finite_number(fx) and _is_finite_number(fy) and _is_finite_number(fz)) then
        return nil
    end

    if not (_is_finite_number(rx) and _is_finite_number(ry) and _is_finite_number(rz)) then
        return nil
    end

    if not (_is_finite_number(ux) and _is_finite_number(uy) and _is_finite_number(uz)) then
        return nil
    end

    return {
        forward = { x = fx, y = fy, z = fz },
        right = { x = rx, y = ry, z = rz },
        up = { x = ux, y = uy, z = uz },
    }
end

local function _safe_physics_world()
    local physics_manager = Managers and Managers.state and Managers.state.physics

    if physics_manager and type(physics_manager.physics_world) == "function" then
        local ok, physics_world = pcall(physics_manager.physics_world, physics_manager)

        if ok and physics_world then
            return physics_world
        end
    end

    if World and World.physics_world then
        local state_world_manager = Managers and Managers.state and Managers.state.world

        if state_world_manager and type(state_world_manager.world) == "function" then
            local ok_world, world = pcall(state_world_manager.world, state_world_manager, "level_world")

            if ok_world and world then
                local ok_physics_world, physics_world = pcall(World.physics_world, world)

                if ok_physics_world and physics_world then
                    return physics_world
                end
            end
        end

        local world_manager = Managers and Managers.world

        if world_manager and type(world_manager.world) == "function" then
            local ok_world, world = pcall(world_manager.world, world_manager, "level_world")

            if ok_world and world then
                local ok_physics_world, physics_world = pcall(World.physics_world, world)

                if ok_physics_world and physics_world then
                    return physics_world
                end
            end
        end
    end

    return nil
end

local function _extract_raycast_distance(a, b, c, d)
    local value = a

    if type(value) == "number" and _is_finite_number(value) then
        return value
    end

    if type(value) == "table" then
        if _is_finite_number(value.distance) then
            return value.distance
        end

        local first = value[1]

        if type(first) == "table" and _is_finite_number(first.distance) then
            return first.distance
        end
    end

    value = b

    if type(value) == "number" and _is_finite_number(value) then
        return value
    end

    if type(value) == "table" then
        if _is_finite_number(value.distance) then
            return value.distance
        end

        local first = value[1]

        if type(first) == "table" and _is_finite_number(first.distance) then
            return first.distance
        end
    end

    value = c

    if type(value) == "number" and _is_finite_number(value) then
        return value
    end

    if type(value) == "table" then
        if _is_finite_number(value.distance) then
            return value.distance
        end

        local first = value[1]

        if type(first) == "table" and _is_finite_number(first.distance) then
            return first.distance
        end
    end

    value = d

    if type(value) == "number" and _is_finite_number(value) then
        return value
    end

    if type(value) == "table" then
        if _is_finite_number(value.distance) then
            return value.distance
        end

        local first = value[1]

        if type(first) == "table" and _is_finite_number(first.distance) then
            return first.distance
        end
    end

    return nil
end

local function _is_world_position_occluded(camera_position, world_position)
    local physics_world = _safe_physics_world()
    local immediate_raycast = PhysicsWorld and PhysicsWorld.immediate_raycast

    if not physics_world or not immediate_raycast then
        return false
    end

    local dx = world_position.x - camera_position.x
    local dy = world_position.y - camera_position.y
    local dz = world_position.z - camera_position.z
    local distance = math_sqrt(dx * dx + dy * dy + dz * dz)

    if not _is_finite_number(distance) or distance <= OCCLUSION_EPSILON then
        return false
    end

    local origin = Vector3(camera_position.x, camera_position.y, camera_position.z)
    local direction = Vector3(dx / distance, dy / distance, dz / distance)
    local threshold = distance - OCCLUSION_EPSILON

    for i = 1, OCCLUSION_RAYCAST_FILTER_COUNT do
        local ok, a, b, c, d = pcall(
            immediate_raycast,
            physics_world,
            origin,
            direction,
            distance,
            OCCLUSION_RAYCAST_MODE,
            OCCLUSION_COLLISION_FILTER,
            OCCLUSION_RAYCAST_FILTERS[i]
        )

        if ok then
            local hit_distance = _extract_raycast_distance(a, b, c, d)

            if hit_distance ~= nil then
                return hit_distance < threshold
            end
        end
    end

    return false
end

local _safe_player_camera_rotation = function(self)
    local parent = self and self._parent
    if not parent or not parent.player_camera then
        return nil
    end

    local ok_camera, camera = pcall(parent.player_camera, parent)

    if not ok_camera or not camera then
        return nil
    end

    local ok_rotation, rotation = pcall(Camera.local_rotation, camera)

    if ok_rotation and rotation then
        return rotation
    end

    return nil
end

local function _build_projection_context(self, fallback_camera_position, fallback_rotation)
    local camera_position = _safe_player_camera_position(self) or fallback_camera_position
    local camera_rotation = _safe_player_camera_rotation(self) or fallback_rotation
    local basis = _rotation_basis(camera_rotation)

    if not camera_position or not basis then
        return nil
    end

    local ui_width, ui_height = _ui_space_size()
    local vertical_fov = _safe_player_vertical_fov() or math_rad(65)
    local tan_half_vertical = math_tan(vertical_fov * 0.5)
    local aspect_ratio = ui_width / math_max(ui_height, 1)
    local tan_half_horizontal = tan_half_vertical * aspect_ratio

    if tan_half_vertical <= 0 or tan_half_horizontal <= 0 then
        return nil
    end

    return {
        camera_position = camera_position,
        basis = basis,
        ui_width = ui_width,
        ui_height = ui_height,
        tan_half_vertical = tan_half_vertical,
        tan_half_horizontal = tan_half_horizontal,
    }
end

local function _project_world_to_screen_with_context(world_position, projection_context)
    if not world_position or not projection_context then
        return nil, nil, nil
    end

    local camera_position = projection_context.camera_position
    local basis = projection_context.basis

    local dx = world_position.x - camera_position.x
    local dy = world_position.y - camera_position.y
    local dz = world_position.z - camera_position.z

    local view_x = dx * basis.right.x + dy * basis.right.y + dz * basis.right.z
    local view_y = dx * basis.up.x + dy * basis.up.y + dz * basis.up.z
    local view_z = dx * basis.forward.x + dy * basis.forward.y + dz * basis.forward.z

    if not (_is_finite_number(view_x) and _is_finite_number(view_y) and _is_finite_number(view_z)) then
        return nil, nil, nil
    end

    if view_z <= 0.05 then
        return nil, nil, nil
    end

    local ndc_x = view_x / (view_z * projection_context.tan_half_horizontal)
    local ndc_y = view_y / (view_z * projection_context.tan_half_vertical)

    if not (_is_finite_number(ndc_x) and _is_finite_number(ndc_y)) then
        return nil, nil, nil
    end

    if math_abs(ndc_x) > 1 or math_abs(ndc_y) > 1 then
        return nil, nil, nil
    end

    local screen_x = (ndc_x * 0.5 + 0.5) * projection_context.ui_width
    local screen_y = (0.5 - ndc_y * 0.5) * projection_context.ui_height

    if not (_is_finite_number(screen_x) and _is_finite_number(screen_y)) then
        return nil, nil, nil
    end

    return screen_x, screen_y, camera_position
end

local function _project_world_to_screen(self, world_position, fallback_camera_position, fallback_rotation)
    if not world_position then
        return nil, nil, nil
    end

    local projection_context = _build_projection_context(self, fallback_camera_position, fallback_rotation)

    if not projection_context then
        return nil, nil, nil
    end

    return _project_world_to_screen_with_context(world_position, projection_context)
end

local function _screen_highlight_bracket_size(distance_sq)
    local distance = math_sqrt(math_max(distance_sq or 0, 0))
    local min_distance = 5
    local max_distance = 20
    local near_size = 24
    local far_size = 18

    if distance <= min_distance then
        return near_size
    end

    if distance >= max_distance then
        return far_size
    end

    local t = (distance - min_distance) / (max_distance - min_distance)
    return near_size + (far_size - near_size) * t
end

local function _draw_screen_highlights(self, ui_renderer, snapshot, z)
    local highlights = snapshot and snapshot.screen_highlights or nil
    local highlight_count = highlights and #highlights or 0

    if highlight_count == 0 then
        return
    end

    local fallback_camera_position = snapshot and snapshot.player_position or nil
    local fallback_rotation = snapshot and snapshot.player_rotation or nil
    local projection_context = _build_projection_context(self, fallback_camera_position, fallback_rotation)

    for i = 1, highlight_count do
        local highlight = highlights[i]
        local world_position = highlight.world_position
        local screen_x, screen_y, camera_position

        if projection_context then
            screen_x, screen_y, camera_position = _project_world_to_screen_with_context(world_position,
                projection_context)
        else
            screen_x, screen_y, camera_position = _project_world_to_screen(self, world_position,
                fallback_camera_position, fallback_rotation)
        end

        if screen_x and screen_y then
            local bracket_size = _screen_highlight_bracket_size(highlight.distance_sq_3d)
            local draw_x = screen_x - bracket_size * 0.5
            local draw_y = screen_y - bracket_size * 0.5
            local draw_color = highlight.color

            if camera_position and world_position then
                local ok_occluded, occluded = pcall(_is_world_position_occluded, camera_position, world_position)

                if ok_occluded and occluded == true then
                    draw_color = highlight.occluded_color or highlight.color
                end
            end

            _draw_marker_brackets(ui_renderer, draw_x, draw_y, z, bracket_size, draw_color)
        end
    end
end

HudElementRadar.init = function(self, parent, draw_layer, start_scale, optional_context)
    HudElementRadar.super.init(self, parent, draw_layer, start_scale, Definitions)
    _sync_screen_scenegraph(self)
    _ensure_frame_widget(self)
    _ensure_marker_widgets(self)
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

local function _draw_internal(self, ui_renderer, snapshot, render_settings, input_service, dt)
    _ensure_marker_widgets(self)

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
    local draw_marker_brackets = _draw_marker_brackets
    local draw_marker_value_text = _draw_marker_value_text
    local snap_center = _snap_center
    local top_left_from_center = _top_left_from_center
    local base_icon_z = z + 5
    local projection_radius = radius - 8
    local live_camera_rotation = _safe_player_camera_rotation(self)
    local projection_rotation = live_camera_rotation or (snapshot and snapshot.player_rotation) or nil

    _draw_radar_frame(self, ui_renderer, x, y, z + 1, size, projection_rotation)

    local next_widget_index = 1
    local max_markers = mod:get_max_radar_markers()
    local max_widget_index = math_min(max_markers, MAX_RADAR_MARKERS)

    if snapshot and snapshot.player_position then
        local player_pos = snapshot.player_position
        local targets = snapshot.targets or {}
        local target_count = #targets
        local project_target_to_radar = mod.project_target_to_radar

        local player_slot = tonumber(snapshot.player_slot)
        local slot_colors = draw_cache.slot_colors
        local player_color = player_slot and slot_colors and slot_colors[player_slot] or nil

        local self_visual = _self_visual
        self_visual.color = _any_to_widget_color(player_color, WHITE_WIDGET_COLOR)

        local self_scale = (draw_cache.icon_scale or 1) * _cached_group_icon_scale("player_teammate", draw_cache)
        local self_icon_size = _scaled_icon_size(self_visual.size, self_scale, 10, 40)
        local self_draw_x = center_x - self_icon_size / 2
        local self_draw_y = center_y - self_icon_size / 2
        local self_widget = marker_widgets[next_widget_index]

        apply_marker_widget(self_widget, self_visual, self_draw_x, self_draw_y, base_icon_z, nil, self_icon_size)
        UIWidget_draw(self_widget, ui_renderer)

        next_widget_index = next_widget_index + 1

        if debug_mode and target_count > max_markers then
            _log_once(
                _logged_draws,
                "marker_pool_overflow:" .. tostring(max_markers),
                string_format("[Radar] marker pool overflow | targets=%d configured=%d pool=%d", target_count,
                    max_markers,
                    MAX_RADAR_MARKERS)
            )
        end

        for i = 1, target_count do
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
                local accent_color = visual and visual.accent_color or nil
                local visual_icon = visual and visual.icon or nil
                local visual_title_icon = visual and visual.title_icon or nil
                local value_text = visual and visual.value_text or nil
                local value_text_color = visual and visual.value_text_color or nil
                local value_text_anchor = visual and visual.value_text_anchor or nil
                local value_text_offset_x = visual and visual.value_text_offset_x or nil
                local value_text_offset_y = visual and visual.value_text_offset_y or nil

                if accent_color and should_draw_marker_brackets(target, draw_cache) then
                    draw_marker_brackets(ui_renderer, bracket_x, bracket_y, bracket_z, bracket_size, accent_color)
                end

                apply_marker_widget(widget, visual, draw_x, draw_y, icon_z, target, marker_size)

                if debug_mode then
                    _log_once(
                        _logged_draws,
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
                            _logged_draws,
                            "widget_draw_fail:" .. tostring(visual_icon),
                            string_format("[Radar] widget draw failed | material=%s err=%s",
                                tostring(visual_icon), tostring(widget_err))
                        )
                    end

                    _draw_box(ui_renderer, draw_x, draw_y, base_icon_z, marker_size, marker_size,
                        _widget_to_color(visual and visual.color or nil))
                end

                draw_marker_value_text(
                    ui_renderer,
                    value_text,
                    draw_x,
                    draw_y,
                    base_icon_z,
                    marker_size,
                    target.vertical_state ~= nil,
                    value_text_color,
                    value_text_anchor,
                    value_text_offset_x,
                    value_text_offset_y
                )

                next_widget_index = next_widget_index + 1
            end
        end
    end

    _draw_screen_highlights(self, ui_renderer, snapshot, z + 40)

    local last_active_marker_widget_index = next_widget_index - 1
    local previous_active_marker_widget_index = self._last_active_marker_widget_index or 0

    if previous_active_marker_widget_index > last_active_marker_widget_index then
        for i = last_active_marker_widget_index + 1, previous_active_marker_widget_index do
            _clear_marker_widget(marker_widgets[i])
        end
    end

    self._last_active_marker_widget_index = last_active_marker_widget_index
end

HudElementRadar.draw = function(self, dt, t, ui_renderer, render_settings, input_service)
    if not mod:is_enabled() or mod:get("enable_radar") == false or not mod:should_draw_radar() then
        return
    end

    local snapshot = mod:get_radar_snapshot()

    render_settings = render_settings or {}
    render_settings.start_layer = self._draw_layer

    _sync_screen_scenegraph(self)

    UIRenderer.begin_pass(ui_renderer, self._ui_scenegraph, input_service, dt, render_settings)

    local ok, err = pcall(_draw_internal, self, ui_renderer, snapshot, render_settings, input_service, dt)

    UIRenderer.end_pass(ui_renderer)

    if not ok then
        mod:error("HudElementRadar.draw failed: %s", tostring(err))
    end
end

return HudElementRadar
