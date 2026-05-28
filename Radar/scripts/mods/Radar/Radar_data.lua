local mod = get_mod("Radar")
local RadarColorSettings = mod:io_dofile("Radar/scripts/mods/Radar/Radar_color_settings")

local DROPDOWN_ICON_COLOUR_WHITE = { 255, 255, 255, 255 }
local DROPDOWN_ICON_COLOUR_RED = { 255, 255, 64, 64 }
local DROPDOWN_ICON_COLOUR_DREG = { 255, 255, 255, 0 }
local DROPDOWN_ICON_COLOUR_TOX = { 255, 0, 255, 0 }
local DROPDOWN_ICON_DEFAULT = "content/ui/materials/hud/interactions/icons/default"
local DROPDOWN_ICON_ENEMY = "content/ui/materials/hud/interactions/icons/enemy"
local DROPDOWN_ICON_PLAYER = "content/ui/materials/icons/classes/veteran"
local DROPDOWN_ICON_TECH_REMNANT = "content/ui/materials/icons/currencies/tech_remnant_big"

local PLAYER_MARKER_STYLE_DROPDOWN_ICON = {
    icon_only = DROPDOWN_ICON_PLAYER,
    marked_icon = DROPDOWN_ICON_PLAYER,
    dot_only = DROPDOWN_ICON_DEFAULT,
    marked_dot = DROPDOWN_ICON_DEFAULT,
}

local function _normalized_player_marker_style(value)
    if value == "icon_only" or value == "marked_icon" or value == "dot_only" or value == "marked_dot" then
        return value
    end

    return "marked_icon"
end

local REQUIRED_ICON_PACKAGES = {
    "packages/ui/views/inventory_view/inventory_view",
    "packages/ui/views/inventory_weapons_view/inventory_weapons_view",
    "packages/ui/hud/player_weapon/player_weapon",
    "packages/ui/views/inventory_background_view/inventory_background_view",
    "packages/ui/views/inventory_weapon_details_view/inventory_weapon_details_view",
    "packages/ui/views/inventory_weapon_marks_view/inventory_weapon_marks_view",
    "packages/ui/views/main_menu_view/main_menu_view",
    "packages/ui/views/player_character_options_view/player_character_options_view",
    "packages/ui/views/talent_builder_view/talent_builder_view",
    "packages/ui/views/live_events_view/live_events_view",
    "packages/ui/views/group_finder_view/group_finder_view",
    "packages/ui/views/mission_board_view/mission_board_view",
    "packages/ui/views/scanner_display_view/scanner_display_view",
    "packages/ui/material_sets/circumstances",
    "packages/ui/views/crafting_view/crafting_view",
    "packages/ui/views/penance_overview_view/penance_overview_view",
    "packages/ui/views/expedition_play_view/expedition_play_view",
}

local ARTWORK_DROPDOWN_PRESENTATIONS = {
    show_crates = {
        artwork_icon = "content/ui/materials/icons/engrams/engram_rarity_04",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/icons/generic/loot",
        icon_colour = { 255, 225, 200, 136 },
    },
    show_diamantine = {
        artwork_icon = "content/ui/materials/icons/currencies/diamantine_big",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/environment_generic",
        icon_colour = { 255, 70, 130, 220 },
    },
    show_plasteel = {
        artwork_icon = "content/ui/materials/icons/currencies/plasteel_big",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/environment_generic",
        icon_colour = { 255, 130, 135, 140 },
    },
    show_expeditions_currency = {
        artwork_icon = "content/ui/materials/icons/currencies/salvage_big",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/expeditions_salvage",
        icon_colour = { 255, 120, 160, 140 },
    },
    show_expeditions_loot = {
        artwork_icon = DROPDOWN_ICON_TECH_REMNANT,
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/expeditions_loot",
        icon_colour = { 255, 192, 160, 0 },
    },
    show_expeditions_dropped_loot = {
        artwork_icon = "content/ui/materials/icons/notifications/tech_dropped",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/expeditions_loot",
        icon_colour = { 220, 255, 0, 0 },
    },
    show_pocketable_airstrike = {
        artwork_icon = "content/ui/materials/icons/throwables/hud/valkyrie_payload",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/valkyrie_payload",
        icon_colour = { 255, 95, 125, 70 },
    },
    show_pocketable_artillery_strike = {
        artwork_icon = "content/ui/materials/icons/throwables/hud/artillery_strike",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/artillery_strike",
        icon_colour = { 255, 95, 125, 70 },
    },
    show_pocketable_big_grenade = {
        artwork_icon = "content/ui/materials/icons/throwables/hud/big_fn_grenade",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/big_fn_grenade",
        icon_colour = { 255, 205, 156, 77 },
    },
    show_pocketable_valkyrie_hover = {
        artwork_icon = "content/ui/materials/icons/throwables/hud/valkyrie_hover",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/valkyrie_hover",
        icon_colour = { 255, 95, 125, 70 },
    },
    show_pocketable_landmine_explosive = {
        artwork_icon = "content/ui/materials/icons/pocketables/hud/landmine_explosive",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/landmine_explosive",
        icon_colour = { 255, 205, 156, 77 },
    },
    show_pocketable_landmine_fire = {
        artwork_icon = "content/ui/materials/icons/pocketables/hud/landmine_fire",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/landmine_fire",
        icon_colour = { 255, 255, 110, 0 },
    },
    show_pocketable_landmine_shock = {
        artwork_icon = "content/ui/materials/icons/pocketables/hud/landmine_shock",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/landmine_shock",
        icon_colour = { 255, 80, 160, 255 },
    },
    show_pocketable_void_shield = {
        artwork_icon = "content/ui/materials/icons/pocketables/hud/void_shield",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/void_shield",
        icon_colour = { 255, 181, 166, 66 },
    },
}

local ENEMY_DROPDOWN_PRESENTATIONS = {
    show_enemy_cultist_melee = {
        icon = DROPDOWN_ICON_DEFAULT,
        icon_colour = DROPDOWN_ICON_COLOUR_DREG,
    },
    show_enemy_renegade_melee = {
        icon = DROPDOWN_ICON_DEFAULT,
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_cultist_assault = {
        icon = "content/ui/materials/icons/item_types/weapons",
        icon_colour = DROPDOWN_ICON_COLOUR_DREG,
    },
    show_enemy_renegade_assault = {
        icon = "content/ui/materials/icons/item_types/weapons",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_renegade_rifleman = {
        icon = "content/ui/materials/icons/item_types/ranged_weapons",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_cultist_gunner = {
        icon = "content/ui/materials/icons/weapons/actions/full_auto",
        icon_colour = DROPDOWN_ICON_COLOUR_DREG,
    },
    show_enemy_cultist_berzerker = {
        icon = "content/ui/materials/icons/presets/preset_01",
        icon_colour = DROPDOWN_ICON_COLOUR_DREG,
    },
    show_enemy_cultist_shocktrooper = {
        icon = "content/ui/materials/icons/weapons/actions/shotgun",
        icon_colour = DROPDOWN_ICON_COLOUR_DREG,
    },
    show_enemy_renegade_gunner = {
        icon = "content/ui/materials/icons/weapons/actions/full_auto",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_renegade_executor = {
        icon = "content/ui/materials/icons/item_types/melee_weapons",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_renegade_plasma_gunner = {
        icon = "content/ui/materials/icons/weapons/actions/charge",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_renegade_berzerker = {
        icon = "content/ui/materials/icons/presets/preset_01",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_renegade_shocktrooper = {
        icon = "content/ui/materials/icons/weapons/actions/shotgun",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_chaos_ogryn_bulwark = {
        icon = "content/ui/materials/icons/weapons/actions/defence",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_chaos_ogryn_executor = {
        icon = "content/ui/materials/icons/difficulty/flat/difficulty_skull_auric",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_chaos_ogryn_gunner = {
        icon = "content/ui/materials/icons/weapons/actions/hipfire",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_renegade_grenadier = {
        icon = "content/ui/materials/icons/abilities/throwables/default",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_cultist_grenadier = {
        icon = "content/ui/materials/icons/abilities/throwables/default",
        icon_colour = DROPDOWN_ICON_COLOUR_TOX,
    },
    show_enemy_renegade_flamer = {
        icon = "content/ui/materials/icons/presets/preset_20",
        icon_colour = { 255, 255, 102, 0 },
    },
    show_enemy_cultist_flamer = {
        icon = "content/ui/materials/icons/presets/preset_20",
        icon_colour = DROPDOWN_ICON_COLOUR_TOX,
    },
    show_enemy_cultist_mutant = {
        icon = "content/ui/materials/icons/weapons/actions/melee_hand",
        icon_colour = DROPDOWN_ICON_COLOUR_DREG,
    },
    show_enemy_chaos_poxwalker_bomber = {
        icon = "content/ui/materials/icons/presets/preset_19",
        icon_colour = DROPDOWN_ICON_COLOUR_TOX,
    },
    show_enemy_chaos_armored_hound = {
        icon = "content/ui/materials/icons/circumstances/hunting_grounds_01",
        icon_colour = { 255, 150, 150, 150 },
    },
    show_enemy_chaos_hound = {
        icon = "content/ui/materials/icons/circumstances/hunting_grounds_01",
        icon_colour = DROPDOWN_ICON_COLOUR_DREG,
    },
    show_enemy_renegade_sniper = {
        icon = "content/ui/materials/icons/presets/preset_14",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_renegade_netgunner = {
        icon = "content/ui/materials/icons/presets/preset_17",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_cultist_ritualist = {
        icon = DROPDOWN_ICON_ENEMY,
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
}

local EXPEDITION_DROPDOWN_PRESENTATIONS = {
    show_expedition_objective_opportunity = {
        icon = "content/ui/materials/backgrounds/scanner/scanner_map_greek_01",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_expedition_objective_transition = {
        icon = "content/ui/materials/backgrounds/scanner/scanner_map_exit",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_expedition_objective_main_objective = {
        icon = "content/ui/materials/hud/interactions/icons/objective_main",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_expedition_objective_extraction = {
        icon = "content/ui/materials/backgrounds/scanner/scanner_map_extract",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_expedition_objective_arrival = {
        icon = "content/ui/materials/icons/mission_types/mission_type_05",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_expedition_loot_converter = {
        icon = "content/ui/materials/hud/interactions/icons/expeditions",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
}

local MARKER_DROPDOWN_PRESENTATIONS = {
    show_ammo_small = {
        icon = "content/ui/materials/hud/interactions/icons/ammunition",
        icon_colour = { 255, 240, 210, 80 },
    },
    show_ammo_big = {
        icon = "content/ui/materials/icons/presets/preset_16",
        icon_colour = { 255, 240, 210, 80 },
    },
    show_grenades = {
        icon = "content/ui/materials/hud/interactions/icons/grenade",
        icon_colour = { 255, 205, 156, 77 },
    },
    show_pocketable_ammo_crate = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_ammo_crate",
        icon_colour = { 255, 240, 210, 80 },
    },
    show_pocketable_medical_crate = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_medic_crate",
        icon_colour = { 255, 38, 205, 26 },
    },
    show_pocketable_syringe_ability = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_ability",
        icon_colour = { 255, 230, 192, 13 },
    },
    show_pocketable_syringe_corruption = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_corruption",
        icon_colour = { 255, 38, 205, 26 },
    },
    show_pocketable_syringe_power = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_power",
        icon_colour = { 255, 205, 51, 26 },
    },
    show_pocketable_syringe_speed = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_speed",
        icon_colour = { 255, 0, 127, 218 },
    },
    show_power_cell_teal = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = { 255, 0, 200, 200 },
    },
    show_cryonic_rod = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = { 255, 180, 220, 255 },
    },
    show_moebian_pox_zetaphyte_13_sample = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = { 255, 150, 190, 60 },
    },
    show_vacuum_capsule = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = { 255, 80, 85, 90 },
    },
    show_special_issue_ammo = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = { 255, 95, 125, 70 },
    },
    show_prismata_crystal_repository = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = { 255, 255, 70, 90 },
    },
    show_mortis_relic = {
        icon = "content/ui/materials/icons/item_types/devices",
        icon_colour = { 255, 110, 95, 125 },
    },
    show_coordinates_paper = {
        icon = "content/ui/materials/icons/system/escape/credits",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_pocketable_grimoire = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_grimoire",
        icon_colour = { 255, 150, 190, 60 },
    },
    show_pocketable_scripture = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_scripture",
        icon_colour = { 255, 192, 160, 0 },
    },
    show_data_reliquaries = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = { 255, 192, 160, 0 },
    },
    show_promethium_barrel = {
        icon = "content/ui/materials/hud/interactions/icons/barrel_explosive",
        icon_colour = { 255, 255, 110, 0 },
    },
    show_large_ammunition_crate = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_ammo",
        icon_colour = { 255, 240, 210, 80 },
    },
    show_anti_rad_stimm = {
        icon = "content/ui/materials/hud/interactions/icons/time_syringe",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_martyr_skull = {
        icon = "content/ui/materials/hud/interactions/icons/enemy",
        icon_colour = { 255, 255, 215, 0 },
    },
    show_power_cell_orange = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = { 255, 255, 140, 0 },
    },
    show_medicae_station = {
        icon = "content/ui/materials/hud/interactions/icons/respawn",
        icon_colour = { 255, 38, 205, 26 },
    },
    show_luggable_socket = {
        icon = "content/ui/materials/icons/presets/preset_11",
        icon_colour = { 255, 255, 245, 80 },
    },
    show_heretic_idol = {
        icon = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_rampaging_enemies",
        icon_colour = { 255, 150, 190, 60 },
    },
    show_ammo_crate_deployable = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_ammo",
        icon_colour = { 255, 240, 210, 80 },
    },
    show_medical_crate_deployable = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_medkit",
        icon_colour = { 255, 38, 205, 26 },
    },
    show_monstrosities = {
        icon = "content/ui/materials/icons/presets/preset_05",
        icon_colour = DROPDOWN_ICON_COLOUR_RED,
    },
    show_captains = {
        icon = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_fading_light_1",
        icon_colour = DROPDOWN_ICON_COLOUR_RED,
    },
    show_karnak_twins = {
        icon = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_fading_light_2",
        icon_colour = DROPDOWN_ICON_COLOUR_RED,
    },
    show_enemy_horde = {
        icon = DROPDOWN_ICON_DEFAULT,
        icon_colour = DROPDOWN_ICON_COLOUR_RED,
    },
    show_players = {
        icon = DROPDOWN_ICON_PLAYER,
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_player_center_dot = {
        icon = DROPDOWN_ICON_DEFAULT,
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_tainted_skull = {
        icon = "content/ui/materials/hud/interactions/icons/enemy",
        icon_colour = { 255, 150, 190, 60 },
    },
    show_dark_rites_totem = {
        icon = "content/ui/materials/icons/achievements/categories/category_heretics",
        icon_colour = { 255, 150, 190, 60 },
    },
    show_dark_rites_servo_skull = {
        icon = "content/ui/materials/icons/abilities/default",
        icon_colour = { 255, 150, 190, 60 },
    },
    show_pocketable_corrupted_auspex_scanner = {
        icon = "content/ui/materials/icons/pocketables/hud/auspex_scanner",
        icon_colour = { 255, 255, 120, 0 },
    },
    show_saints = {
        icon = "content/ui/materials/icons/circumstances/live_event_01",
        icon_colour = { 255, 192, 160, 0 },
    },
    show_stolen_rations = {
        icon = "content/ui/materials/icons/pickups/default",
        icon_colour = { 255, 150, 190, 60 },
    },
    show_unknown_pickups = {
        icon = "content/ui/materials/icons/traits/empty",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
}

local DEFAULT_DROPDOWN_PRESENTATION = {
    icon = DROPDOWN_ICON_DEFAULT,
    icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
}

local _dropdown_marker_icon_colour

local function _dropdown_option(text, value, icon, icon_colour)
    local option = {
        text = text,
        value = value,
    }

    if icon then
        option.icon = icon
        option.icon_colour = icon_colour or DROPDOWN_ICON_COLOUR_WHITE
    end

    return option
end

local function _player_marker_style_dropdown_option(text, value)
    return _dropdown_option(text, value, PLAYER_MARKER_STYLE_DROPDOWN_ICON[value] or DROPDOWN_ICON_PLAYER,
        DROPDOWN_ICON_COLOUR_WHITE)
end

local function _player_marker_style_options(include_off)
    local options = {
        _player_marker_style_dropdown_option("display_style_icon_only", "icon_only"),
        _player_marker_style_dropdown_option("display_style_marked_icon", "marked_icon"),
        _player_marker_style_dropdown_option("display_style_dot_only", "dot_only"),
        _player_marker_style_dropdown_option("display_style_marked_dot", "marked_dot"),
    }

    if include_off then
        options[#options + 1] = _dropdown_option("radar_outline_off", "off")
    end

    return options
end

local function _player_markers_dropdown_value()
    local value = mod:get("show_players")

    if value == nil then
        value = mod:get("show_teammates")
    end

    if value == false or value == "off" then
        return "off"
    end

    if _normalized_player_marker_style(value) == value then
        return value
    end

    return _normalized_player_marker_style(mod:get("player_display_style"))
end

local function _set_player_markers_dropdown_value(new_value)
    if new_value == "off" then
        mod:set("show_players", "off")
        return
    end

    local style = _normalized_player_marker_style(new_value)

    mod:set("show_players", style)
    mod:set("player_display_style", style)
end

local function _marker_enabled_options(setting_id)
    local presentation = MARKER_DROPDOWN_PRESENTATIONS[setting_id] or DEFAULT_DROPDOWN_PRESENTATION
    local icon_colour = _dropdown_marker_icon_colour(setting_id, presentation.icon_colour)

    return {
        _dropdown_option("marker_display_mode_icon", "icon", presentation.icon, icon_colour),
        _dropdown_option("radar_outline_off", "off"),
    }
end

local function _marker_enabled_dropdown_value(value, default_value)
    if value == nil then
        return default_value
    end

    if value == false or value == "off" then
        return "off"
    end

    return "icon"
end

local function _migrate_marker_enabled_dropdown_setting(setting_id)
    local value = mod:get(setting_id)

    if setting_id == "show_players" then
        if value == false or value == "off" then
            mod:set(setting_id, "off")
            return
        end

        if value == true or value == "icon" then
            mod:set(setting_id, _normalized_player_marker_style(mod:get("player_display_style")))
            return
        end

        if _normalized_player_marker_style(value) == value then
            mod:set("player_display_style", value)
        end

        return
    end

    if value == true then
        mod:set(setting_id, "icon")
    elseif value == false then
        mod:set(setting_id, "off")
    end
end

function mod:migrate_marker_enabled_dropdown_settings()
    for setting_id in pairs(MARKER_DROPDOWN_PRESENTATIONS) do
        _migrate_marker_enabled_dropdown_setting(setting_id)
    end
end

local function _tab_overrides(tooltip_key)
    return {
        font_size = 16,
        tooltip = mod:localize(tooltip_key),
        truncate_num = 10,
    }
end

local TAB_GENERAL = "General"
local TAB_LAYOUT = "Layout"
local TAB_PICKUPS = "Pickups"
local TAB_OBJECTIVES = "Objectives"
local TAB_EXPEDITIONS = "Expeditions"
local TAB_ENEMIES = "Enemies"
local TAB_PLAYERS = "Players"
local TAB_DEBUG = "Debug"

local TAB_OVERRIDES_GENERAL = _tab_overrides("radar_tab_general_tooltip")
local TAB_OVERRIDES_LAYOUT = _tab_overrides("radar_tab_layout_tooltip")
local TAB_OVERRIDES_PICKUPS = _tab_overrides("radar_tab_pickups_tooltip")
local TAB_OVERRIDES_OBJECTIVES = _tab_overrides("radar_tab_objectives_tooltip")
local TAB_OVERRIDES_EXPEDITIONS = _tab_overrides("radar_tab_expeditions_tooltip")
local TAB_OVERRIDES_ENEMIES = _tab_overrides("radar_tab_enemies_tooltip")
local TAB_OVERRIDES_PLAYERS = _tab_overrides("radar_tab_players_tooltip")
local TAB_OVERRIDES_DEBUG = _tab_overrides("radar_tab_debug_tooltip")

local function _artwork_icon_off_dropdown(setting_id)
    local presentation = ARTWORK_DROPDOWN_PRESENTATIONS[setting_id] or DEFAULT_DROPDOWN_PRESENTATION
    local artwork_icon = presentation.artwork_icon or presentation.icon
    local artwork_colour = presentation.artwork_colour or presentation.icon_colour or DROPDOWN_ICON_COLOUR_WHITE
    local icon = presentation.icon
    local icon_colour = _dropdown_marker_icon_colour(setting_id, presentation.icon_colour)

    return {
        setting_id = setting_id,
        type = "dropdown",
        default_value = "artwork",
        options = {
            _dropdown_option("marker_display_mode_artwork", "artwork", artwork_icon, artwork_colour),
            _dropdown_option("marker_display_mode_icon", "icon", icon, icon_colour),
            _dropdown_option("radar_outline_off", "off"),
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

local COLOR_CHANNELS = {
    {
        suffix = "opacity",
        title_suffix = "opacity",
        index = 1,
    },
    {
        suffix = "red",
        title_suffix = "red",
        index = 2,
    },
    {
        suffix = "green",
        title_suffix = "green",
        index = 3,
    },
    {
        suffix = "blue",
        title_suffix = "blue",
        index = 4,
    },
}

local COLOR_LABEL_SUFFIX_BY_ROLE = {
    icon = {
        key = "color_option_icon_suffix",
        fallback = " icon color",
    },
    highlight = {
        key = "color_option_highlight_suffix",
        fallback = " highlight color",
    },
    background = {
        key = "color_option_background_suffix",
        fallback = " background color",
    },
}

local function _color_channel_slider(setting_id, default_value, title, tooltip)
    return {
        setting_id = setting_id,
        title = title,
        tooltip = tooltip,
        type = "numeric",
        localize = true,
        default_value = default_value or 255,
        range = { 0, 255 },
        decimals_number = 0,
        step_size_value = 1,
    }
end

local function _color_setting_id(prefix, suffix)
    local opacity_setting_by_prefix = RadarColorSettings.opacity_setting_by_prefix

    if suffix == "opacity" and opacity_setting_by_prefix and opacity_setting_by_prefix[prefix] then
        return opacity_setting_by_prefix[prefix]
    end

    return prefix .. "_" .. suffix
end

local DROPDOWN_COLOR_PREFIX_BY_SETTING_ID = {
    show_monstrosities = "enemy_boss_marker",
    show_captains = "enemy_boss_marker",
    show_karnak_twins = "enemy_boss_marker",
    show_enemy_horde = "enemy_horde_marker",
}

local _dropdown_icon_color_by_prefix = {}

local function _dropdown_color_prefix_from_anchor(setting_id)
    local anchored_color_settings = RadarColorSettings.anchored_color_settings
    local color_descriptors = anchored_color_settings and anchored_color_settings[setting_id] or nil

    if color_descriptors == nil then
        return nil
    end

    for i = 1, #color_descriptors do
        local descriptor = color_descriptors[i]

        if descriptor.label_role == "icon" then
            return descriptor.prefix
        end
    end

    return nil
end

local function _dropdown_color_prefix(setting_id)
    local prefix = DROPDOWN_COLOR_PREFIX_BY_SETTING_ID[setting_id]

    if prefix then
        return prefix
    end

    prefix = _dropdown_color_prefix_from_anchor(setting_id)

    if prefix then
        return prefix
    end

    local kind = setting_id and string.sub(setting_id, 1, 5) == "show_" and string.sub(setting_id, 6) or nil

    if kind == nil then
        return nil
    end

    local marker_prefix_by_kind = RadarColorSettings.marker_prefix_by_kind
    local enemy_icon_prefix_by_kind = RadarColorSettings.enemy_icon_prefix_by_kind

    return marker_prefix_by_kind and marker_prefix_by_kind[kind] or
        enemy_icon_prefix_by_kind and enemy_icon_prefix_by_kind[kind] or nil
end

local function _dropdown_color_channel(prefix, suffix, default_value)
    local value = tonumber(mod:get(_color_setting_id(prefix, suffix)))

    if value == nil then
        value = default_value or 255
    end

    if value < 0 then
        value = 0
    elseif value > 255 then
        value = 255
    end

    return math.floor(value + 0.5)
end

local function _refresh_dropdown_icon_colour(prefix)
    local color = prefix and _dropdown_icon_color_by_prefix[prefix] or nil

    if color == nil then
        return
    end

    local defaults = RadarColorSettings.default_by_prefix[prefix] or color

    color[1] = _dropdown_color_channel(prefix, "opacity", defaults[1] or 255)
    color[2] = _dropdown_color_channel(prefix, "red", defaults[2] or 255)
    color[3] = _dropdown_color_channel(prefix, "green", defaults[3] or 255)
    color[4] = _dropdown_color_channel(prefix, "blue", defaults[4] or 255)
end

local function _refresh_dropdown_icon_colours()
    for prefix in pairs(_dropdown_icon_color_by_prefix) do
        _refresh_dropdown_icon_colour(prefix)
    end
end

_dropdown_marker_icon_colour = function(setting_id, fallback)
    local prefix = _dropdown_color_prefix(setting_id)

    if prefix == nil then
        return fallback or DROPDOWN_ICON_COLOUR_WHITE
    end

    local color = _dropdown_icon_color_by_prefix[prefix]

    if color == nil then
        local defaults = RadarColorSettings.default_by_prefix[prefix] or fallback or DROPDOWN_ICON_COLOUR_WHITE

        color = {
            defaults[1] or 255,
            defaults[2] or 255,
            defaults[3] or 255,
            defaults[4] or 255,
        }
        _dropdown_icon_color_by_prefix[prefix] = color
    end

    _refresh_dropdown_icon_colour(prefix)

    return color
end

local function _install_dropdown_icon_color_refresh()
    mod._radar_dropdown_icon_color_refresh = _refresh_dropdown_icon_colours

    if mod._radar_dropdown_icon_color_refresh_installed then
        return
    end

    mod._radar_dropdown_icon_color_refresh_installed = true

    local previous_on_setting_changed = mod.on_setting_changed

    mod.on_setting_changed = function(setting_id, ...)
        if previous_on_setting_changed then
            previous_on_setting_changed(setting_id, ...)
        end

        local refresh_dropdown_icon_color = mod._radar_dropdown_icon_color_refresh

        if refresh_dropdown_icon_color then
            refresh_dropdown_icon_color()
        end
    end
end

_install_dropdown_icon_color_refresh()

local function _localized_or_raw(text_id)
    if text_id == nil then
        return nil
    end

    local success, localized_text = pcall(mod.localize, mod, text_id)

    if success and localized_text ~= nil and localized_text ~= "" and localized_text ~= "<" .. text_id .. ">" then
        return localized_text
    end

    return text_id
end

local function _localized_setting_title(widget)
    local title = widget and (widget.title or widget.setting_id) or nil

    if title == nil then
        return nil
    end

    return _localized_or_raw(title)
end

local function _localized_color_label_suffix(label_role)
    local suffix = COLOR_LABEL_SUFFIX_BY_ROLE[label_role]

    if suffix == nil then
        return nil
    end

    local success, localized_suffix = pcall(mod.localize, mod, suffix.key)

    if success and localized_suffix ~= nil and localized_suffix ~= "" then
        return localized_suffix
    end

    return suffix.fallback
end

local function _color_setting_group_title(descriptor, anchor_widget)
    local label_role = descriptor.label_role
    local label_suffix = descriptor.label_suffix or (label_role and _localized_color_label_suffix(label_role))

    if label_suffix then
        local label_prefix = descriptor.label_prefix or _localized_setting_title(anchor_widget)

        if label_prefix and label_prefix ~= "" then
            return label_prefix .. label_suffix
        end
    end

    return _localized_or_raw(descriptor.title_prefix or "marker_color")
end

local function _color_setting_sliders(descriptor)
    local sliders = {}
    local prefix = descriptor.prefix
    local default = descriptor.default or { 255, 255, 255, 255 }
    local title_prefix = descriptor.title_prefix or "marker_color"
    local tooltip = descriptor.tooltip or "marker_color_slider_tooltip"
    local channels = descriptor.channels

    for i = 1, #COLOR_CHANNELS do
        local channel = COLOR_CHANNELS[i]

        if channels == nil or channels[channel.suffix] == true then
            sliders[#sliders + 1] = _color_channel_slider(
                _color_setting_id(prefix, channel.suffix),
                default[channel.index] or 255,
                title_prefix .. "_" .. channel.title_suffix,
                tooltip
            )
        end
    end

    return sliders
end

local function _color_setting_group(descriptor, anchor_widget, tab, tab_overrides)
    local tooltip = descriptor.tooltip or "marker_color_slider_tooltip"

    local group = {
        setting_id = descriptor.group_setting_id or (descriptor.prefix .. "_group"),
        title = _color_setting_group_title(descriptor, anchor_widget),
        tooltip = mod:localize(tooltip),
        type = "group",
        localize = false,
        sub_widgets = _color_setting_sliders(descriptor),
    }

    if tab then
        group.tab = tab
    end

    if tab_overrides then
        group.tab_overrides = tab_overrides
    end

    return group
end

local function _color_setting_groups(anchor, tab, tab_overrides)
    local groups = {}
    local anchored_color_settings = RadarColorSettings.anchored_color_settings
    local color_descriptors = anchored_color_settings and anchored_color_settings[anchor] or nil

    if color_descriptors == nil then
        return groups
    end

    for i = 1, #color_descriptors do
        groups[#groups + 1] = _color_setting_group(color_descriptors[i], nil, tab, tab_overrides)
    end

    return groups
end

local function _insert_color_settings(widgets, tab, tab_overrides)
    local anchored_color_settings = RadarColorSettings.anchored_color_settings or {}
    local i = 1

    while i <= #widgets do
        local widget = widgets[i]
        local widget_tab = widget.tab or tab
        local widget_tab_overrides = widget.tab_overrides or tab_overrides

        if widget.type == "group" and widget.sub_widgets then
            _insert_color_settings(widget.sub_widgets, widget_tab, widget_tab_overrides)
        end

        local color_descriptors = widget.skip_color_settings ~= true and widget.setting_id and
            anchored_color_settings[widget.setting_id] or nil

        if color_descriptors and #color_descriptors > 0 then
            local insert_at = i

            for descriptor_index = 1, #color_descriptors do
                insert_at = insert_at + 1
                table.insert(widgets, insert_at, _color_setting_group(
                    color_descriptors[descriptor_index],
                    widget,
                    widget.tab,
                    widget.tab_overrides
                ))
            end

            i = insert_at
        end

        i = i + 1
    end
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

local function _normalize_icon_marked_off_default(value, fallback)
    if value == false or value == "off" then
        return "off"
    end

    if value == "marked_icon" then
        return "marked_icon"
    end

    if value == true or value == "icon_only" then
        return "icon_only"
    end

    return fallback or "icon_only"
end

local function _icon_marked_off_dropdown(setting_id, default_value)
    local presentation = ENEMY_DROPDOWN_PRESENTATIONS[setting_id] or DEFAULT_DROPDOWN_PRESENTATION
    local icon = presentation.icon
    local icon_colour = _dropdown_marker_icon_colour(setting_id, presentation.icon_colour)

    return {
        setting_id = setting_id,
        type = "dropdown",
        default_value = default_value,
        options = {
            _dropdown_option("display_style_icon_only", "icon_only", icon, icon_colour),
            _dropdown_option("display_style_marked_icon", "marked_icon", icon, icon_colour),
            _dropdown_option("radar_outline_off", "off"),
        },
    }
end

local function _expedition_marker_display_mode_dropdown(setting_id, default_value)
    local presentation = EXPEDITION_DROPDOWN_PRESENTATIONS[setting_id] or DEFAULT_DROPDOWN_PRESENTATION
    local icon = presentation.icon
    local icon_colour = _dropdown_marker_icon_colour(setting_id, presentation.icon_colour)

    return {
        setting_id = setting_id,
        type = "dropdown",
        default_value = default_value,
        options = {
            _dropdown_option("display_style_icon_only", "icon_only", icon, icon_colour),
            _dropdown_option("display_style_icon_distance", "icon_distance", icon, icon_colour),
            _dropdown_option("radar_outline_off", "off"),
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
            _dropdown_option("expedition_loot_marker_mode_default", "default"),
            _dropdown_option("expedition_loot_marker_mode_scaled", "scaled"),
            _dropdown_option("expedition_loot_marker_mode_clustered", "clustered"),
        },
    }
end


local function _apply_marker_enabled_dropdowns(widgets)
    for i = 1, #widgets do
        local widget = widgets[i]

        if widget.type == "group" and widget.sub_widgets then
            _apply_marker_enabled_dropdowns(widget.sub_widgets)
        elseif widget.type == "checkbox" and widget.setting_id and MARKER_DROPDOWN_PRESENTATIONS[widget.setting_id] then
            local setting_id = widget.setting_id
            local default_value = widget.default_value == nil and true or widget.default_value
            local default_dropdown_value = default_value == false and "off" or "icon"
            local original_get = widget.get

            _migrate_marker_enabled_dropdown_setting(setting_id)

            widget.type = "dropdown"
            if setting_id == "show_players" then
                widget.default_value = "marked_icon"
                widget.options = _player_marker_style_options(true)
                widget.get = _player_markers_dropdown_value
                widget.change = _set_player_markers_dropdown_value
            else
                widget.default_value = default_dropdown_value
                widget.options = _marker_enabled_options(setting_id)
                widget.get = function()
                    local value = mod:get(setting_id)

                    if value == nil and original_get then
                        value = original_get()
                    end

                    return _marker_enabled_dropdown_value(value, default_dropdown_value)
                end
                widget.change = function(new_value)
                    mod:set(setting_id, new_value == "off" and "off" or "icon")
                end
            end
        end
    end
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
    required_icon_packages = REQUIRED_ICON_PACKAGES,
    options = {
        widgets = (function()
            local common_enemy_display_default = _normalize_icon_marked_off_default(mod:get("show_enemy_common"), "icon_only")
            local shooter_enemy_display_default = _normalize_icon_marked_off_default(mod:get("show_enemy_shooter"), "icon_only")
            local widgets = {
                {
                    setting_id = "general_group",
                    type = "group",
                    tab = TAB_GENERAL,
                    tab_overrides = TAB_OVERRIDES_GENERAL,
                    sub_widgets = {
                        {
                            setting_id = "general_availability_group",
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
                            },
                        },
                        {
                            setting_id = "general_input_group",
                            type = "group",
                            sub_widgets = {
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
                            },
                        },
                        {
                            setting_id = "general_limits_filtering_group",
                            type = "group",
                            sub_widgets = {
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
                            },
                        },
                        {
                            setting_id = "general_scale_group",
                            type = "group",
                            sub_widgets = {
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
                                    setting_id = "scale_icons_with_radar_size",
                                    type = "checkbox",
                                    default_value = false,
                                },
                            },
                        },
                    },
                },
                {
                    setting_id = "position_group",
                    type = "group",
                    tab = TAB_LAYOUT,
                    tab_overrides = TAB_OVERRIDES_LAYOUT,
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
                    setting_id = "radar_frame_group",
                    type = "group",
                    tab = TAB_LAYOUT,
                    tab_overrides = TAB_OVERRIDES_LAYOUT,
                    sub_widgets = {
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
                    },
                },
                {
                    setting_id = "radar_colors_group",
                    type = "group",
                    tab = TAB_LAYOUT,
                    tab_overrides = TAB_OVERRIDES_LAYOUT,
                    skip_color_settings = true,
                    sub_widgets = _color_setting_groups("radar_colors_group"),
                },
                {
                    setting_id = "nearby_highlight_group",
                    type = "group",
                    tab = TAB_LAYOUT,
                    tab_overrides = TAB_OVERRIDES_LAYOUT,
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
                    },
                },
                {
                    setting_id = "common_pickups_group",
                    type = "group",
                    tab = TAB_PICKUPS,
                    tab_overrides = TAB_OVERRIDES_PICKUPS,
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
                    tab = TAB_PICKUPS,
                    tab_overrides = TAB_OVERRIDES_PICKUPS,
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
                    tab = TAB_OBJECTIVES,
                    tab_overrides = TAB_OVERRIDES_OBJECTIVES,
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
                    tab = TAB_OBJECTIVES,
                    tab_overrides = TAB_OVERRIDES_OBJECTIVES,
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
                    tab = TAB_EXPEDITIONS,
                    tab_overrides = TAB_OVERRIDES_EXPEDITIONS,
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
                    tab = TAB_EXPEDITIONS,
                    tab_overrides = TAB_OVERRIDES_EXPEDITIONS,
                    sub_widgets = {
                        {
                            setting_id = "expedition_tech_remnants_group",
                            type = "group",
                            sub_widgets = {
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
                            },
                        },
                        {
                            setting_id = "expedition_items_group",
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
                                {
                                    setting_id = "show_data_reliquaries",
                                    type = "checkbox",
                                    default_value = true,
                                },
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
                            setting_id = "expedition_hazards_tools_group",
                            type = "group",
                            sub_widgets = {
                                _artwork_icon_off_dropdown("show_pocketable_landmine_explosive"),
                                _artwork_icon_off_dropdown("show_pocketable_landmine_fire"),
                                _artwork_icon_off_dropdown("show_pocketable_landmine_shock"),
                                _artwork_icon_off_dropdown("show_pocketable_void_shield"),
                                _artwork_icon_off_dropdown("show_pocketable_airstrike"),
                                _artwork_icon_off_dropdown("show_pocketable_artillery_strike"),
                                _artwork_icon_off_dropdown("show_pocketable_big_grenade"),
                                _artwork_icon_off_dropdown("show_pocketable_valkyrie_hover"),
                            },
                        },
                    },
                },
                {
                    setting_id = "martyr_s_skull_group",
                    type = "group",
                    tab = TAB_OBJECTIVES,
                    tab_overrides = TAB_OVERRIDES_OBJECTIVES,
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
                    tab = TAB_PICKUPS,
                    tab_overrides = TAB_OVERRIDES_PICKUPS,
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
                    tab = TAB_PICKUPS,
                    tab_overrides = TAB_OVERRIDES_PICKUPS,
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
                    tab = TAB_ENEMIES,
                    tab_overrides = TAB_OVERRIDES_ENEMIES,
                    sub_widgets = {
                        {
                            setting_id = "enemy_global_settings_group",
                            type = "group",
                            sub_widgets = {
                                _icon_scale_slider("enemies_icon_scale", "enemies_icon_scale"),
                            },
                        },
                        {
                            setting_id = "enemy_bosses_group",
                            type = "group",
                            sub_widgets = {
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
                            },
                        },
                        {
                            setting_id = "enemy_horde_group",
                            type = "group",
                            sub_widgets = {
                                _icon_scale_slider("enemy_horde_icon_scale", "enemy_horde_icon_scale"),
                                {
                                    setting_id = "show_enemy_horde",
                                    type = "checkbox",
                                    default_value = false,
                                    tooltip = "horde_tooltip",
                                },
                                _enemy_vertical_arrows_checkbox("show_enemy_horde_vertical_arrows"),
                            },
                        },
                        {
                            setting_id = "enemy_common_shooters_group",
                            type = "group",
                            sub_widgets = {
                                _icon_scale_slider("enemy_common_icon_scale", "enemy_common_icon_scale"),
                                _icon_marked_off_dropdown("show_enemy_cultist_melee", common_enemy_display_default),
                                _icon_marked_off_dropdown("show_enemy_renegade_melee", common_enemy_display_default),
                                _enemy_vertical_arrows_checkbox("show_enemy_common_vertical_arrows"),
                                _icon_scale_slider("enemy_shooter_icon_scale", "enemy_shooter_icon_scale"),
                                _icon_marked_off_dropdown("show_enemy_cultist_assault", shooter_enemy_display_default),
                                _icon_marked_off_dropdown("show_enemy_renegade_assault", shooter_enemy_display_default),
                                _icon_marked_off_dropdown("show_enemy_renegade_rifleman", shooter_enemy_display_default),
                                _enemy_vertical_arrows_checkbox("show_enemy_shooter_vertical_arrows"),
                            },
                        },
                        {
                            setting_id = "enemy_elites_group",
                            type = "group",
                            sub_widgets = {
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
                            },
                        },
                        {
                            setting_id = "enemy_specials_group",
                            type = "group",
                            sub_widgets = {
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
                            },
                        },
                        {
                            setting_id = "enemy_misc_group",
                            type = "group",
                            sub_widgets = {
                                _icon_scale_slider("enemy_misc_icon_scale", "enemy_misc_icon_scale"),
                                _icon_marked_off_dropdown("show_enemy_cultist_ritualist", "icon_only"),
                                _enemy_vertical_arrows_checkbox("show_enemy_misc_vertical_arrows"),
                            },
                        },
                    },
                },
                {
                    setting_id = "players_group",
                    type = "group",
                    tab = TAB_PLAYERS,
                    tab_overrides = TAB_OVERRIDES_PLAYERS,
                    sub_widgets = {
                        {
                            setting_id = "show_player_center_dot",
                            tooltip = "show_player_center_dot_tooltip",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "player_teammates_group",
                            type = "group",
                            sub_widgets = {
                                _icon_scale_slider("players_icon_scale", nil),
                                {
                                    setting_id = "show_players",
                                    title = "show_teammates",
                                    tooltip = "show_teammates_tooltip",
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
                            },
                        },
                        {
                            setting_id = "player_tags_group",
                            type = "group",
                            sub_widgets = {
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
                    },
                },
                {
                    setting_id = "event_group",
                    type = "group",
                    tab = TAB_OBJECTIVES,
                    tab_overrides = TAB_OVERRIDES_OBJECTIVES,
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
                            setting_id = "show_dark_rites_totem",
                            type = "checkbox",
                            default_value = true,
                        },
                        {
                            setting_id = "show_dark_rites_servo_skull",
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
                    tab = TAB_DEBUG,
                    tab_overrides = TAB_OVERRIDES_DEBUG,
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

            _apply_marker_enabled_dropdowns(widgets)
            _insert_color_settings(widgets)
            _apply_missing_tooltips(widgets)

            return widgets
        end)(),
    },
}
