local mod = get_mod("Radar")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UISettings = require("scripts/settings/ui/ui_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

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

local function _widget_to_color(color)
    if not color then
        return Color(255, 255, 255, 255)
    end

    local a = color[1] or color.a or 255
    local r = color[2] or color.r or 255
    local g = color[3] or color.g or 255
    local b = color[4] or color.b or 255

    return Color(a, r, g, b)
end

local function _any_to_widget_color(color, fallback)
    local src = color or fallback or { 255, 255, 255, 255 }
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
        size = 14,
    },
    pickup_medkit = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_medkit",
        color = _widget_color(255, 38, 205, 26),
        size = 14,
    },
    medical_crate_deployable = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_medkit",
        color = _widget_color(255, 38, 205, 26),
        size = 14,
    },
    pickup_coordinates_paper = {
        icon = "content/ui/materials/icons/system/escape/credits",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    luggable_data_reliquary = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 192, 160, 0),
        size = 20,
    },
    luggable_power_cell_teal = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 0, 200, 200),
        size = 20,
    },
    luggable_power_cell_orange = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 255, 140, 0),
        size = 20,
    },
    luggable_cryonic_rod = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 180, 220, 255),
        size = 20,
    },
    luggable_moebian_pox_zetaphyte_13_sample = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 150, 190, 60),
        size = 20,
    },
    luggable_vacuum_capsule = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 80, 85, 90),
        size = 20,
    },
    luggable_special_issue_ammo = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 95, 125, 70),
        size = 20,
    },
    luggable_prismata_crystal_repository = {
        icon = "content/ui/materials/icons/player_states/lugged",
        color = _widget_color(255, 255, 70, 90),
        size = 20,
    },
    luggable_promethium_barrel = {
        icon = "content/ui/materials/hud/interactions/icons/barrel_explosive",
        color = _widget_color(255, 255, 110, 0),
        size = 14,
    },
    pickup_unknown = {
        icon = "content/ui/materials/icons/traits/empty",
        color = _widget_color(255, 255, 255, 255),
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
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    material_diamantine = {
        icon = "content/ui/materials/icons/currencies/diamantine_big",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    material_plasteel = {
        icon = "content/ui/materials/icons/currencies/plasteel_big",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    material_expeditions_currency = {
        icon = "content/ui/materials/icons/currencies/salvage_big",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    material_expeditions_loot = {
        icon = "content/ui/materials/icons/currencies/tech_remnant_big",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    material_expeditions_loot_player_drop = {
        icon = "content/ui/materials/icons/notifications/tech_dropped",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    pocketable_ammo_crate = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_ammo_crate",
        color = _widget_color(255, 240, 210, 80),
        size = 14,
    },
    pocketable_anti_rad_stimm = {
        icon = "content/ui/materials/hud/interactions/icons/time_syringe",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    pocketable_corrupted_auspex_scanner = {
        icon = "content/ui/materials/icons/pocketables/hud/auspex_scanner",
        color = _widget_color(255, 255, 120, 0),
        size = 14,
    },
    pocketable_airstrike = {
        icon = "content/ui/materials/icons/throwables/hud/valkyrie_payload",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    pocketable_artillery_strike = {
        icon = "content/ui/materials/icons/throwables/hud/artillery_strike",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    pocketable_big_grenade = {
        icon = "content/ui/materials/icons/throwables/hud/big_fn_grenade",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    pocketable_grimoire = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_grimoire",
        color = _widget_color(255, 150, 190, 60),
        size = 14,
    },
    pocketable_landmine_explosive = {
        icon = "content/ui/materials/icons/pocketables/hud/landmine_explosive",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    pocketable_landmine_fire = {
        icon = "content/ui/materials/icons/pocketables/hud/landmine_fire",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    pocketable_landmine_shock = {
        icon = "content/ui/materials/icons/pocketables/hud/landmine_shock",
        color = _widget_color(255, 255, 255, 255),
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
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
    pocketable_void_shield = {
        icon = "content/ui/materials/icons/pocketables/hud/void_shield",
        color = _widget_color(255, 255, 255, 255),
        size = 14,
    },
}

local function _draw_box(ui_renderer, x, y, z, w, h, color)
    if not ui_renderer or not ui_renderer.gui then
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

    Gui.rect(ui_renderer.gui, position, size, color)
end

local function _draw_marker_brackets(ui_renderer, x, y, z, size, color)
    local thickness = size >= 16 and 2 or 1
    local length = math.max(4, math.floor(size * 0.35))
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
    local integer_radius = math.max(1, math.floor(radius))

    for dy = -integer_radius, integer_radius do
        local span = math.floor(math.sqrt(math.max(0, integer_radius * integer_radius - dy * dy)))
        _draw_box(ui_renderer, center_x - span, center_y + dy, z, span * 2 + 1, 1, color)
    end
end

local function _round(n)
    return math.floor(n + 0.5)
end

local function _draw_dot(ui_renderer, x, y, z, size, color)
    size = tonumber(size) or 1
    size = math.max(1, size)

    local half = size / 2
    _draw_box(ui_renderer, _round(x - half), _round(y - half), z, size, size, color)
end

local function _draw_circle_outline(ui_renderer, center_x, center_y, z, radius, color)
    local circumference = math.max(24, 2 * math.pi * radius)
    local steps = math.max(96, math.floor(circumference * 1.25))
    local dot_size = 1

    for i = 0, steps - 1 do
        local angle = (math.pi * 2 * i) / steps
        local px = center_x + math.cos(angle) * radius
        local py = center_y + math.sin(angle) * radius
        _draw_dot(ui_renderer, px, py, z, dot_size, color)
    end
end

local function _draw_hline_dotted(ui_renderer, x, y, z, length, thickness, color, dash, gap)
    local step = dash + gap
    local i = 0

    while i < length do
        local segment = math.min(dash, length - i)
        _draw_box(ui_renderer, x + i, y, z, segment, thickness, color)
        i = i + step
    end
end

local function _draw_vline_dotted(ui_renderer, x, y, z, thickness, length, color, dash, gap)
    local step = dash + gap
    local i = 0

    while i < length do
        local segment = math.min(dash, length - i)
        _draw_box(ui_renderer, x, y + i, z, thickness, segment, color)
        i = i + step
    end
end

local function _draw_circle_outline_dotted(ui_renderer, center_x, center_y, z, radius, color)
    local point_size = radius >= 90 and 2 or 1
    local steps = 64

    for i = 0, steps - 1 do
        local angle = (math.pi * 2 * i) / steps
        local px = center_x + math.cos(angle) * radius
        local py = center_y + math.sin(angle) * radius
        _draw_box(ui_renderer, px - point_size / 2, py - point_size / 2, z, point_size, point_size, color)
    end
end

local function _draw_square_outline(ui_renderer, x, y, z, size, thickness, color)
    x = _round(x)
    y = _round(y)
    size = math.max(1, _round(size))
    thickness = math.max(1, _round(thickness))

    _draw_box(ui_renderer, x, y, z, size, thickness, color)
    _draw_box(ui_renderer, x, y + size - thickness, z, size, thickness, color)
    _draw_box(ui_renderer, x, y, z, thickness, size, color)
    _draw_box(ui_renderer, x + size - thickness, y, z, thickness, size, color)
end

local function _draw_diagonal_line(ui_renderer, x1, y1, x2, y2, z, color, dot_size)
    local dx = x2 - x1
    local dy = y2 - y1
    local steps = math.max(math.abs(dx), math.abs(dy), 1)

    for i = 0, steps do
        local t = i / steps
        local px = x1 + dx * t
        local py = y1 + dy * t
        _draw_dot(ui_renderer, px, py, z, dot_size or 1, color)
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

    local ok, player = pcall(function()
        return getter(player_manager, 1)
    end)

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
        local ok_has_camera, has_camera = pcall(function()
            return camera_manager:has_camera(viewport_name)
        end)

        if ok_has_camera and not has_camera then
            return nil
        end
    end

    local ok_fov, vertical_fov = pcall(function()
        return camera_manager:fov(viewport_name)
    end)

    vertical_fov = ok_fov and tonumber(vertical_fov) or nil
    if not vertical_fov or vertical_fov <= 0 then
        return nil
    end

    local aspect_ratio = 16 / 9
    if rawget(_G, "RESOLUTION_LOOKUP") and RESOLUTION_LOOKUP.width and RESOLUTION_LOOKUP.height and RESOLUTION_LOOKUP.height > 0 then
        aspect_ratio = RESOLUTION_LOOKUP.width / RESOLUTION_LOOKUP.height
    end

    return 2 * math.atan(math.tan(vertical_fov * 0.5) * aspect_ratio)
end

local function _view_cone_half_angle()
    local horizontal_fov = _safe_player_horizontal_fov() or math.rad(90)
    local half_angle = horizontal_fov * 0.5

    return math.clamp(half_angle, math.rad(15), math.rad(85))
end

local function _view_cone_direction(angle)
    return math.sin(angle), -math.cos(angle)
end

local function _view_cone_endpoint_circle(center_x, center_y, radius, angle)
    local dx, dy = _view_cone_direction(angle)

    return center_x + dx * radius, center_y + dy * radius
end

local function _view_cone_endpoint_square(center_x, center_y, left, top, right, bottom, angle)
    local dx, dy = _view_cone_direction(angle)
    local t_candidates = {}

    if math.abs(dx) > 0.0001 then
        if dx > 0 then
            t_candidates[#t_candidates + 1] = (right - center_x) / dx
        else
            t_candidates[#t_candidates + 1] = (left - center_x) / dx
        end
    end

    if math.abs(dy) > 0.0001 then
        if dy > 0 then
            t_candidates[#t_candidates + 1] = (bottom - center_y) / dy
        else
            t_candidates[#t_candidates + 1] = (top - center_y) / dy
        end
    end

    local best_t = nil

    for i = 1, #t_candidates do
        local t = t_candidates[i]
        if t and t > 0 and (not best_t or t < best_t) then
            best_t = t
        end
    end

    best_t = best_t or 0

    return center_x + dx * best_t, center_y + dy * best_t
end

local function _draw_circle_ring(ui_renderer, center_x, center_y, z, outer_radius, thickness, color)
    local outer_r = math.max(1, math.floor((outer_radius or 0) + 0.5))
    local inner_r = math.max(0, outer_r - math.max(1, math.floor((thickness or 1) + 0.5)))

    for dy = -outer_r, outer_r do
        local outer_span = math.floor(math.sqrt(math.max(0, outer_r * outer_r - dy * dy)))
        local inner_span = 0

        if math.abs(dy) <= inner_r then
            inner_span = math.floor(math.sqrt(math.max(0, inner_r * inner_r - dy * dy)))
        end

        if outer_span > inner_span then
            local y_pos = center_y + dy
            local left_x = center_x - outer_span
            local right_x = center_x + inner_span + 1
            local segment_width = outer_span - inner_span

            _draw_box(ui_renderer, left_x, y_pos, z, segment_width, 1, color)
            _draw_box(ui_renderer, right_x, y_pos, z, segment_width, 1, color)
        end
    end
end

local function _draw_radar_guides(ui_renderer, x, y, z, size, is_circle)
    local guide_style = mod.get_radar_guides and mod:get_radar_guides() or "crosshair"

    if guide_style == "off" then
        return
    end

    local center_x = x + size / 2
    local center_y = y + size / 2
    local radius = size / 2
    local guide_color = _color(90, 255, 255, 255)

    if guide_style == "crosshair" then
        if is_circle then
            local guide_radius = math.max(1, radius - 2)
            local top = _round(center_y - guide_radius)
            local left = _round(center_x - guide_radius)
            local span = math.max(1, _round(guide_radius * 2))

            _draw_box(ui_renderer, _round(center_x), top, z, 1, span, guide_color)
            _draw_box(ui_renderer, left, _round(center_y), z, span, 1, guide_color)
        else
            local inset = 1
            local left = x + inset
            local top = y + inset
            local span = math.max(1, size - inset * 2)

            _draw_box(ui_renderer, _round(center_x), top, z, 1, span, guide_color)
            _draw_box(ui_renderer, left, _round(center_y), z, span, 1, guide_color)
        end

        return
    end

    if guide_style == "view_guides" then
        local half_angle = _view_cone_half_angle()
        local thickness = 1
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

        _draw_diagonal_line(ui_renderer, center_x, center_y, left_x, left_y, z, guide_color, thickness)
        _draw_diagonal_line(ui_renderer, center_x, center_y, right_x, right_y, z, guide_color, thickness)

        return
    end

    if guide_style == "range_rings" then
        local ring_gap = radius / 4
        local ring_thickness = 1

        for ring = 1, 3 do
            local r = ring_gap * ring

            if is_circle then
                _draw_circle_ring(ui_renderer, center_x, center_y, z, r, ring_thickness, guide_color)
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
    local fill_color = _color(90, 0, 0, 0)
    local outline_color = _color(255, 213, 226, 206)

    _draw_box(ui_renderer, x, y, z, size, size, fill_color)

    if outline_style == "solid" then
        _draw_box(ui_renderer, x, y, z + 1, size, thickness, outline_color)
        _draw_box(ui_renderer, x, y + size - thickness, z + 1, size, thickness, outline_color)
        _draw_box(ui_renderer, x, y, z + 1, thickness, size, outline_color)
        _draw_box(ui_renderer, x + size - thickness, y, z + 1, thickness, size, outline_color)
    elseif outline_style == "dotted" then
        local dash = 8
        local gap = 5

        _draw_hline_dotted(ui_renderer, x, y, z + 1, size, thickness, outline_color, dash, gap)
        _draw_hline_dotted(ui_renderer, x, y + size - thickness, z + 1, size, thickness, outline_color, dash, gap)
        _draw_vline_dotted(ui_renderer, x, y, z + 1, thickness, size, outline_color, dash, gap)
        _draw_vline_dotted(ui_renderer, x + size - thickness, y, z + 1, thickness, size, outline_color, dash, gap)
    end
end

local function _draw_radar_frame_circle(ui_renderer, x, y, z, size, outline_style)
    local center_x = x + size / 2
    local center_y = y + size / 2
    local radius = math.max(1, size / 2 - 1)
    local fill_color = _color(90, 0, 0, 0)
    local outline_color = _color(255, 213, 226, 206)

    _draw_circle_fill(ui_renderer, center_x, center_y, z, radius, fill_color)

    if outline_style == "solid" then
        _draw_circle_outline(ui_renderer, center_x, center_y, z + 1, radius, outline_color)
    elseif outline_style == "dotted" then
        _draw_circle_outline_dotted(ui_renderer, center_x, center_y, z + 1, radius, outline_color)
    end
end

local function _draw_radar_frame(ui_renderer, x, y, z, size)
    local outline_style = mod.get_radar_outline and mod:get_radar_outline() or "solid"
    local is_circle = mod:get_radar_style() == "circle"

    if is_circle then
        _draw_radar_frame_circle(ui_renderer, x, y, z, size, outline_style)
    else
        _draw_radar_frame_square(ui_renderer, x, y, z, size, outline_style)
    end

    _draw_radar_guides(ui_renderer, x, y, z + 1, size, is_circle)
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
                color = { 255, 255, 255, 255 },
            },
            visibility_function = function(content, style)
                return content.icon ~= nil and content.icon ~= ""
            end,
        },
        {
            pass_type = "texture",
            value_id = "title_icon",
            style_id = "title_icon",
            style = {
                vertical_alignment = "top",
                horizontal_alignment = "left",
                offset = { 0, 0, 11 },
                size = { 16, 16 },
                color = { 255, 255, 255, 255 },
            },
            visibility_function = function(content, style)
                return content.title_icon ~= nil and content.title_icon ~= ""
            end,
        },
    }, "screen")
end

local MAX_RADAR_MARKERS = 100

local function _create_marker_widget(index)
    return UIWidget.init("RadarMarker_" .. index, _marker_definition())
end

local function _clear_marker_widget(widget)
    widget.content.icon = nil
    widget.content.title_icon = nil
end

local function _ensure_marker_widgets(self)
    if self._marker_widgets then
        return
    end

    self._marker_widgets = {}

    for i = 1, MAX_RADAR_MARKERS do
        self._marker_widgets[i] = _create_marker_widget(i)
    end

    _log_once(_logged_draws, "widget_pool_init",
        string.format("[Radar] widget pool created | count=%d", MAX_RADAR_MARKERS))
end

local function _icon_scale_factor()
    if mod:get("scale_icons_with_radar_size") == false then
        return 1
    end

    local radar_size = tonumber(mod:get("radar_size")) or 180
    local scale = radar_size / 180

    if scale < 0.6 then
        scale = 0.6
    elseif scale > 2.0 then
        scale = 2.0
    end

    return scale
end

local function _scaled_icon_size(base_size)
    local scaled = math.floor((tonumber(base_size) or 14) * _icon_scale_factor() + 0.5)

    if scaled < 10 then
        scaled = 10
    end

    return scaled
end

local function _is_enemy_kind(kind)
    return kind ~= nil and string.sub(tostring(kind), 1, 6) == "enemy_"
end

local function _is_expedition_objective_kind(kind)
    return kind ~= nil and EXPEDITION_OBJECTIVE_KINDS[kind] == true
end

local function _display_style_for_kind(kind)
    if kind == "player_teammate" then
        local value = tostring(mod:get("player_display_style") or "marked_icon")

        if value ~= "icon_only"
            and value ~= "marked_icon"
            and value ~= "dot_only"
            and value ~= "marked_dot" then
            value = "marked_icon"
        end

        return value
    end

    if _is_enemy_kind(kind) then
        local value = tostring(mod:get("enemy_display_style") or "marked_icon")
        return value == "icon_only" and "icon_only" or "marked_icon"
    end

    if _is_expedition_objective_kind(kind) then
        return "marked_icon"
    end

    return "icon_only"
end

local function _should_draw_marker_brackets(target)
    local style = _display_style_for_kind(target and target.kind)
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

local function _apply_marker_widget(widget, visual, x, y, z)
    local icon_style = widget.style.icon
    local title_icon_style = widget.style.title_icon
    local size = _scaled_icon_size(visual and visual.size or 14)
    local color = _any_to_widget_color(visual and visual.color or nil)

    widget.content.icon = visual and visual.icon or nil
    widget.content.title_icon = visual and visual.title_icon or nil

    icon_style.offset[1] = math.floor((x or 0) + 0.5)
    icon_style.offset[2] = math.floor((y or 0) + 0.5)
    icon_style.offset[3] = math.floor((z or 0) + 0.5)
    icon_style.size[1] = size
    icon_style.size[2] = size
    icon_style.color = color

    if title_icon_style then
        title_icon_style.offset[1] = icon_style.offset[1]
        title_icon_style.offset[2] = icon_style.offset[2]
        title_icon_style.offset[3] = (icon_style.offset[3] or 0) + 1
        title_icon_style.size[1] = size
        title_icon_style.size[2] = size
        title_icon_style.color = color
    end
end

local DEFAULT_INTERACTION_ICON = "content/ui/materials/hud/interactions/icons/default"
local DEFAULT_EXPEDITION_UNMARKED_COLOR = _widget_color(255, 54, 198, 49)

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

local function _artwork_mode_icon_visual(kind)
    local mode = mod.get_marker_display_mode and mod:get_marker_display_mode(kind) or nil

    if mode ~= "icon" then
        return nil
    end

    return _copy_visual(ARTWORK_MODE_ICON_PRESENTATIONS[kind])
end

local function _expedition_objective_visual(target)
    local meta = target and target.meta or {}
    local player_slot = tonumber(meta.marked_by_player_slot)
    local slot_colors = UISettings and UISettings.player_slot_colors
    local player_color = player_slot and slot_colors and slot_colors[player_slot] or nil
    local default_color = _expedition_unmarked_color(target)
    local widget_color = _any_to_widget_color(player_color, default_color)

    local accent_color = nil
    local icon = nil

    if target and target.kind == "expedition_loot_converter" then
        icon = meta.objective_icon or DEFAULT_INTERACTION_ICON
    else
        local interaction_icon = meta.interaction_icon
        icon = interaction_icon

        if icon == nil or icon == DEFAULT_INTERACTION_ICON then
            icon = meta.objective_icon or DEFAULT_INTERACTION_ICON
        end
    end

    if player_slot then
        accent_color = _with_alpha_widget(player_color or widget_color, 180)
    end

    return {
        icon = icon,
        title_icon = meta.objective_title_icon,
        color = widget_color,
        accent_color = accent_color,
        size = 15,
    }
end

local function _target_visual(target)
    if not target then
        return nil
    end

    if target.kind == "player_teammate" then
        local meta = target.meta or {}
        local archetype_name = meta.archetype_name and string.lower(tostring(meta.archetype_name)) or nil
        local player_slot = tonumber(meta.player_slot)
        local slot_colors = UISettings and UISettings.player_slot_colors
        local player_color = player_slot and slot_colors and slot_colors[player_slot] or nil
        local display_style = mod:get_player_display_style()
        local use_dot = display_style == "dot_only" or display_style == "marked_dot"

        local icon = use_dot and DEFAULT_INTERACTION_ICON or PLAYER_CLASS_ICONS[archetype_name]
        local widget_color = _any_to_widget_color(player_color)

        if mod:get("debug_mode") then
            _log_once(
                _logged_visuals,
                "player:" .. tostring(archetype_name) .. ":" .. tostring(player_slot),
                string.format("[Radar] visual player | archetype=%s slot=%s icon=%s", tostring(archetype_name),
                    tostring(player_slot), tostring(icon))
            )
        end

        return {
            icon = icon,
            color = widget_color,
            accent_color = _with_alpha_widget(widget_color, 180),
            size = use_dot or 15,
        }
    end

    if _is_expedition_objective_kind(target.kind) then
        if mod:get("debug_mode") then
            _log_once(
                _logged_visuals,
                "expedition:" ..
                tostring(target.kind) ..
                ":" ..
                tostring((target.meta or {}).interaction_icon or (target.meta or {}).objective_icon) ..
                ":" .. tostring((target.meta or {}).objective_title_icon),
                string.format("[Radar] visual expedition | kind=%s icon=%s title_icon=%s marked_by=%s",
                    tostring(target.kind),
                    tostring((target.meta or {}).interaction_icon or (target.meta or {}).objective_icon),
                    tostring((target.meta or {}).objective_title_icon),
                    tostring((target.meta or {}).marked_by_player_slot))
            )
        end

        return _expedition_objective_visual(target)
    end

    local icon_visual = _artwork_mode_icon_visual(target.kind)
    if icon_visual then
        if mod:get("debug_mode") then
            _log_once(
                _logged_visuals,
                "icon_mode:" .. tostring(target.kind),
                string.format("[Radar] visual icon mode | kind=%s icon=%s", tostring(target.kind), tostring(icon_visual.icon))
            )
        end

        return icon_visual
    end

    local presentation = PRESENTATIONS[target.kind]
    if presentation then
        if mod:get("debug_mode") then
            _log_once(
                _logged_visuals,
                "kind:" .. tostring(target.kind),
                string.format("[Radar] visual presentation | kind=%s icon=%s", tostring(target.kind),
                    tostring(presentation.icon))
            )
        end

        return presentation
    end

    local meta = target.meta or {}
    if meta.interaction_icon and meta.interaction_icon ~= "" then
        if mod:get("debug_mode") then
            _log_once(
                _logged_visuals,
                "interaction:" .. tostring(meta.interaction_icon),
                string.format("[Radar] visual interaction_icon | kind=%s icon=%s", tostring(target.kind),
                    tostring(meta.interaction_icon))
            )
        end

        return {
            icon = meta.interaction_icon,
            color = _widget_color(255, 255, 255, 255),
            size = 14,
        }
    end

    if mod:get("debug_mode") then
        _log_once(
            _logged_visuals,
            "fallback_kind:" .. tostring(target.kind),
            string.format("[Radar] visual fallback | kind=%s icon=%s", tostring(target.kind),
                tostring(PRESENTATIONS.pickup_unknown.icon))
        )
    end

    return PRESENTATIONS.pickup_unknown
end

local function _safe_player_camera_rotation(self)
    local parent = self and self._parent
    if not parent or not parent.player_camera then
        return nil
    end

    local ok_camera, camera = pcall(function()
        return parent:player_camera()
    end)

    if not ok_camera or not camera then
        return nil
    end

    local ok_rotation, rotation = pcall(function()
        return Camera.local_rotation(camera)
    end)

    if ok_rotation and rotation then
        return rotation
    end

    return nil
end

HudElementRadar.init = function(self, parent, draw_layer, start_scale, optional_context)
    HudElementRadar.super.init(self, parent, draw_layer, start_scale, Definitions)
    _ensure_marker_widgets(self)
end

HudElementRadar.update = function(self, dt, t)
    return
end

HudElementRadar.draw = function(self, dt, t, ui_renderer, render_settings, input_service)
    if not mod:is_enabled() or mod:get("enable_radar") == false or not mod:should_draw_radar() then
        return
    end

    local snapshot = mod:get_radar_snapshot()

    render_settings = render_settings or {}
    render_settings.start_layer = self._draw_layer

    UIRenderer.begin_pass(ui_renderer, self._ui_scenegraph, input_service, dt, render_settings)

    local ok, err = pcall(function()
        _ensure_marker_widgets(self)

        local size = mod:get_radar_size()
        local range = mod:get_radar_range()
        local x, y, z, radius = mod:get_radar_origin(size)
        local center_x = x + radius
        local center_y = y + radius

        _draw_radar_frame(ui_renderer, x, y, z + 1, size)

        local next_widget_index = 1
        local max_markers = mod:get_max_radar_markers()

        if snapshot and snapshot.player_position then
            local player_pos = snapshot.player_position
            local targets = snapshot.targets or {}
            local live_camera_rotation = _safe_player_camera_rotation(self)
            local projection_rotation = live_camera_rotation or snapshot.player_rotation

            local player_slot = tonumber(snapshot.player_slot)
            local slot_colors = UISettings and UISettings.player_slot_colors
            local player_color = player_slot and slot_colors and slot_colors[player_slot] or nil

            local self_visual = {
                icon = DEFAULT_INTERACTION_ICON,
                color = _any_to_widget_color(player_color, _widget_color(255, 255, 255, 255)),
                size = 4,
            }

            local self_icon_size = _scaled_icon_size(self_visual.size)
            local self_draw_x = center_x - self_icon_size / 2
            local self_draw_y = center_y - self_icon_size / 2
            local self_widget = self._marker_widgets[next_widget_index]

            _apply_marker_widget(self_widget, self_visual, self_draw_x, self_draw_y, z + 5)
            UIWidget.draw(self_widget, ui_renderer)

            next_widget_index = next_widget_index + 1

            if #targets > max_markers then
                _log_once(
                    _logged_draws,
                    "marker_pool_overflow:" .. tostring(max_markers),
                    string.format("[Radar] marker pool overflow | targets=%d configured=%d pool=%d", #targets,
                        max_markers,
                        MAX_RADAR_MARKERS)
                )
            end

            for i = 1, #targets do
                if next_widget_index > max_markers or next_widget_index > MAX_RADAR_MARKERS then
                    break
                end

                local target = targets[i]
                local px, py = mod:project_target_to_radar(player_pos, projection_rotation, target.position, radius - 8,
                    range, target.ignore_radar_range)

                if px and py then
                    local visual = _target_visual(target)
                    local icon_size = _scaled_icon_size(visual and visual.size or 14)
                    local draw_x = center_x + px - icon_size / 2
                    local draw_y = center_y + py - icon_size / 2
                    local widget = self._marker_widgets[next_widget_index]

                    if visual and visual.accent_color and _should_draw_marker_brackets(target) then
                        _draw_marker_brackets(ui_renderer, draw_x, draw_y, z + 4, icon_size, visual.accent_color)
                    end

                    _apply_marker_widget(widget, visual, draw_x, draw_y, z + 5)

                    _log_once(
                        _logged_draws,
                        "widget_material:" .. tostring(visual and visual.icon),
                        string.format("[Radar] widget material scheduled | material=%s title_material=%s",
                            tostring(visual and visual.icon),
                            tostring(visual and visual.title_icon))
                    )

                    local widget_ok, widget_err = pcall(function()
                        UIWidget.draw(widget, ui_renderer)
                    end)

                    if not widget_ok then
                        _log_once(
                            _logged_draws,
                            "widget_draw_fail:" .. tostring(visual and visual.icon),
                            string.format("[Radar] widget draw failed | material=%s err=%s",
                                tostring(visual and visual.icon), tostring(widget_err))
                        )
                        _draw_box(ui_renderer, draw_x, draw_y, z + 5, icon_size, icon_size,
                            _widget_to_color(visual and visual.color or nil))
                    end

                    next_widget_index = next_widget_index + 1
                end
            end
        end

        for i = next_widget_index, #self._marker_widgets do
            _clear_marker_widget(self._marker_widgets[i])
        end
    end)

    UIRenderer.end_pass(ui_renderer)

    if not ok then
        mod:error("HudElementRadar.draw failed: %s", tostring(err))
    end
end

return HudElementRadar
