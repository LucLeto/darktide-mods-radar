--- Radar's DMF mod data; the mod description and the whole settings menu.
-- The returned table names the mod and declares every option widget. Each top-level group is one
-- native DMF tab (General, Layout, Pickups, Objectives, Expeditions, Enemies, Players and Debug).
-- The widget tree is declared inline and then post-processed. Marker visibility checkboxes listed
-- in `MARKER_DROPDOWN_PRESENTATIONS` become icon / off dropdowns (with their saved checkbox values
-- migrated), the native colour widgets registered in `Radar_color_settings.lua` are added to the
-- widget they belong to, marker dropdowns get the `show_widgets` that hide their settings while
-- they are off, and every widget without a tooltip gets `<setting_id>_tooltip`.
--
-- Loaded by DMF as `mod_data`, as declared in `Radar.mod`; not part of the runtime's shared
-- environment. Before the menu is built, colours saved as four channel settings are folded into
-- the native colour settings, which has to happen before DMF saves their defaults. Dropdown
-- options carry icons tinted with the configured marker colours through `icon_style`, and a
-- colour setting change gives the options it tints a new style. Also defines
-- `mod:migrate_marker_enabled_dropdown_settings`, run by `Radar_enemy_definitions.lua` once all
-- mods are loaded.
-- module: Radar_data
-- author: LucLeto
local mod = get_mod("Radar")
local RadarColorSettings = mod:io_dofile("Radar/scripts/mods/Radar/Radar_color_settings")

--- Shared dropdown icon colours and icons.
local DROPDOWN_ICON_COLOUR_WHITE = { 255, 255, 255, 255 }
local DROPDOWN_ICON_COLOUR_RED = RadarColorSettings.default_color("enemy_boss_marker")
local DROPDOWN_ICON_COLOUR_DREG = RadarColorSettings.default_color("enemy_dreg_marker")
local DROPDOWN_ICON_COLOUR_TOX = RadarColorSettings.default_color("enemy_tox_marker")
local DROPDOWN_ICON_DEFAULT = "content/ui/materials/hud/interactions/icons/default"
local DROPDOWN_ICON_ENEMY = "content/ui/materials/hud/interactions/icons/enemy"
local DROPDOWN_ICON_PLAYER = "content/ui/materials/icons/classes/veteran"
local DROPDOWN_ICON_TECH_REMNANT = "content/ui/materials/icons/currencies/tech_remnant_big"

--- Icon of each player marker style option.
local PLAYER_MARKER_STYLE_DROPDOWN_ICON = {
    icon_only = DROPDOWN_ICON_PLAYER,
    marked_icon = DROPDOWN_ICON_PLAYER,
    dot_only = DROPDOWN_ICON_DEFAULT,
    marked_dot = DROPDOWN_ICON_DEFAULT,
}

--- Normalises a player marker style, defaulting to `marked_icon`.
-- treturn: string `icon_only`, `marked_icon`, `dot_only` or `marked_dot`
local function _normalized_player_marker_style(value)
    if value == "icon_only" or value == "marked_icon" or value == "dot_only" or value == "marked_dot" then
        return value
    end

    return "marked_icon"
end

--- Option icons of the artwork / icon / off dropdowns, by setting id.
-- An entry with `icon_glyph` labels its icon option with that glyph instead of carrying an
-- icon material, because a native option icon is a material and cannot render a glyph.
local ARTWORK_DROPDOWN_PRESENTATIONS = {
    show_crates = {
        artwork_icon = "content/ui/materials/icons/engrams/engram_rarity_04",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/icons/generic/loot",
        icon_colour = RadarColorSettings.default_marker_color("crate_unknown"),
    },
    show_diamantine = {
        artwork_icon = "content/ui/materials/icons/currencies/diamantine_big",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon_glyph = "\238\128\172", -- U+E02C, official diamantine glyph
        icon_colour = RadarColorSettings.default_marker_color("material_diamantine"),
    },
    show_plasteel = {
        artwork_icon = "content/ui/materials/icons/currencies/plasteel_big",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon_glyph = "\238\128\173", -- U+E02D, official plasteel glyph
        icon_colour = RadarColorSettings.default_marker_color("material_plasteel"),
    },
    show_expeditions_currency = {
        artwork_icon = "content/ui/materials/icons/currencies/salvage_big",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/expeditions_salvage",
        icon_colour = RadarColorSettings.default_marker_color("material_expeditions_currency"),
    },
    show_expeditions_loot = {
        artwork_icon = DROPDOWN_ICON_TECH_REMNANT,
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/expeditions_loot",
        icon_colour = RadarColorSettings.default_marker_color("material_expeditions_loot"),
    },
    show_expeditions_dropped_loot = {
        artwork_icon = "content/ui/materials/icons/notifications/tech_dropped",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/expeditions_loot",
        icon_colour = RadarColorSettings.default_marker_color("material_expeditions_loot_player_drop"),
    },
    show_pocketable_airstrike = {
        artwork_icon = "content/ui/materials/icons/throwables/hud/valkyrie_payload",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/valkyrie_payload",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_airstrike"),
    },
    show_pocketable_artillery_strike = {
        artwork_icon = "content/ui/materials/icons/throwables/hud/artillery_strike",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/artillery_strike",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_artillery_strike"),
    },
    show_pocketable_big_grenade = {
        artwork_icon = "content/ui/materials/icons/throwables/hud/big_fn_grenade",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/big_fn_grenade",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_big_grenade"),
    },
    show_pocketable_valkyrie_hover = {
        artwork_icon = "content/ui/materials/icons/throwables/hud/valkyrie_hover",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/valkyrie_hover",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_valkyrie_hover"),
    },
    show_pocketable_landmine_explosive = {
        artwork_icon = "content/ui/materials/icons/pocketables/hud/landmine_explosive",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/landmine_explosive",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_landmine_explosive"),
    },
    show_pocketable_landmine_fire = {
        artwork_icon = "content/ui/materials/icons/pocketables/hud/landmine_fire",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/landmine_fire",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_landmine_fire"),
    },
    show_pocketable_landmine_shock = {
        artwork_icon = "content/ui/materials/icons/pocketables/hud/landmine_shock",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/landmine_shock",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_landmine_shock"),
    },
    show_pocketable_void_shield = {
        artwork_icon = "content/ui/materials/icons/pocketables/hud/void_shield",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/void_shield",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_void_shield"),
    },
    show_tainted_skull = {
        artwork_icon = "content/ui/materials/icons/currencies/live_events/skulls_live_event_small",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/hud/interactions/icons/enemy",
        icon_colour = RadarColorSettings.default_marker_color("pickup_tainted_skull"),
    },
    show_saints = {
        artwork_icon = "content/ui/materials/icons/currencies/live_events/saints_live_event_small",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/icons/circumstances/live_event_01",
        icon_colour = RadarColorSettings.default_marker_color("pickup_saints"),
    },
    show_leftover = {
        artwork_icon = "content/ui/materials/icons/currencies/live_events/leftover_live_event_small",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/icons/circumstances/live_event_01",
        icon_colour = RadarColorSettings.default_marker_color("pickup_leftover"),
    },
    show_stolen_rations = {
        artwork_icon = "content/ui/materials/icons/currencies/stolen_rations/rations_live_event_medium",
        artwork_colour = DROPDOWN_ICON_COLOUR_WHITE,
        icon = "content/ui/materials/icons/pickups/default",
        icon_colour = RadarColorSettings.default_marker_color("pickup_stolen_rations"),
    },
}

--- Option icons of the enemy icon / marked icon / off dropdowns, by setting id.
local ENEMY_DROPDOWN_PRESENTATIONS = {
    show_enemy_cultist_melee = {
        icon = DROPDOWN_ICON_DEFAULT,
        icon_colour = DROPDOWN_ICON_COLOUR_DREG,
    },
    show_enemy_renegade_melee = {
        icon = DROPDOWN_ICON_DEFAULT,
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_enemy_cultist_vanguard = {
        icon = "content/ui/materials/icons/presets/preset_04",
        icon_colour = DROPDOWN_ICON_COLOUR_DREG,
    },
    show_enemy_renegade_vanguard = {
        icon = "content/ui/materials/icons/presets/preset_04",
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
        icon_colour = RadarColorSettings.default_color("enemy_renegade_flamer_marker"),
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
        icon_colour = RadarColorSettings.default_color("enemy_armored_hound_marker"),
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

--- Option icons of the Expedition location dropdowns, by setting id.
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

--- Option icons of the marker dropdowns, by setting id.
-- A checkbox whose setting id is listed here is turned into an icon / off dropdown, and the
-- icon / distance / off dropdowns take their icons from here too.
local MARKER_DROPDOWN_PRESENTATIONS = {
    show_ammo_small = {
        icon = "content/ui/materials/hud/interactions/icons/ammunition",
        icon_colour = RadarColorSettings.default_marker_color("pickup_ammo_small"),
    },
    show_ammo_big = {
        icon = "content/ui/materials/icons/presets/preset_16",
        icon_colour = RadarColorSettings.default_marker_color("pickup_ammo_big"),
    },
    show_grenades = {
        icon = "content/ui/materials/hud/interactions/icons/grenade",
        icon_colour = RadarColorSettings.default_marker_color("pickup_grenade"),
    },
    show_pocketable_ammo_crate = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_ammo_crate",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_ammo_crate"),
    },
    show_pocketable_medical_crate = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_medic_crate",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_medical_crate"),
    },
    show_pocketable_syringe_ability = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_ability",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_syringe_ability"),
    },
    show_pocketable_syringe_corruption = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_corruption",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_syringe_corruption"),
    },
    show_pocketable_syringe_power = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_power",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_syringe_power"),
    },
    show_pocketable_syringe_speed = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_syringe_speed",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_syringe_speed"),
    },
    show_power_cell_teal = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = RadarColorSettings.default_marker_color("luggable_power_cell_teal"),
    },
    show_cryonic_rod = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = RadarColorSettings.default_marker_color("luggable_cryonic_rod"),
    },
    show_moebian_pox_zetaphyte_13_sample = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = RadarColorSettings.default_marker_color("luggable_moebian_pox_zetaphyte_13_sample"),
    },
    show_vacuum_capsule = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = RadarColorSettings.default_marker_color("luggable_vacuum_capsule"),
    },
    show_special_issue_ammo = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = RadarColorSettings.default_marker_color("luggable_special_issue_ammo"),
    },
    show_prismata_crystal_repository = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = RadarColorSettings.default_marker_color("luggable_prismata_crystal_repository"),
    },
    show_mortis_relic = {
        icon = "content/ui/materials/icons/item_types/devices",
        icon_colour = RadarColorSettings.default_marker_color("pickup_mortis_relic"),
    },
    show_coordinates_paper = {
        icon = "content/ui/materials/icons/system/escape/credits",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_pocketable_grimoire = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_grimoire",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_grimoire"),
    },
    show_pocketable_scripture = {
        icon = "content/ui/materials/icons/pocketables/hud/small/party_scripture",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_scripture"),
    },
    show_data_reliquaries = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = RadarColorSettings.default_marker_color("luggable_data_reliquary"),
    },
    show_promethium_barrel = {
        icon = "content/ui/materials/hud/interactions/icons/barrel_explosive",
        icon_colour = RadarColorSettings.default_marker_color("luggable_promethium_barrel"),
    },
    show_explosive_barrels = {
        icon = "content/ui/materials/hud/interactions/icons/barrel_explosive",
        icon_colour = RadarColorSettings.default_marker_color("hazard_explosive_barrel"),
    },
    show_fire_barrels = {
        icon = "content/ui/materials/hud/interactions/icons/barrel_explosive",
        icon_colour = RadarColorSettings.default_marker_color("hazard_fire_barrel"),
    },
    show_large_ammunition_crate = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_ammo",
        icon_colour = RadarColorSettings.default_marker_color("pickup_large_ammunition_crate"),
    },
    show_anti_rad_stimm = {
        icon = "content/ui/materials/hud/interactions/icons/time_syringe",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
    show_mission_objective_scanner = {
        icon = "content/ui/materials/icons/mission_types/mission_type_03",
        icon_colour = RadarColorSettings.vanilla_objective_color,
    },
    show_mission_objective_hacking = {
        icon = "content/ui/materials/icons/pocketables/hud/auspex_scanner",
        icon_colour = RadarColorSettings.vanilla_objective_color,
    },
    show_mission_objective_servo_skull = {
        icon = "content/ui/materials/icons/abilities/default",
        icon_colour = RadarColorSettings.vanilla_objective_color,
    },
    show_mission_objective_other = {
        icon = "content/ui/materials/hud/interactions/icons/objective_main",
        icon_colour = RadarColorSettings.vanilla_objective_color,
    },
    show_mission_objective_growth = {
        icon = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_parasite",
        icon_colour = RadarColorSettings.mission_objective_growth_color,
    },
    show_mission_objective_destroy = {
        icon = "content/ui/materials/icons/mission_types/mission_type_01",
        icon_colour = RadarColorSettings.vanilla_objective_color,
    },
    show_martyr_skull = {
        icon = "content/ui/materials/hud/interactions/icons/enemy",
        icon_colour = RadarColorSettings.default_marker_color("pickup_martyr_skull"),
    },
    show_power_cell_orange = {
        icon = "content/ui/materials/icons/player_states/lugged",
        icon_colour = RadarColorSettings.default_marker_color("luggable_power_cell_orange"),
    },
    show_medicae_station = {
        icon = "content/ui/materials/hud/interactions/icons/respawn",
        icon_colour = RadarColorSettings.default_marker_color("medicae_station"),
    },
    show_luggable_socket = {
        icon = "content/ui/materials/icons/presets/preset_11",
        icon_colour = RadarColorSettings.default_marker_color("luggable_socket"),
    },
    show_heretic_idol = {
        icon = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_rampaging_enemies",
        icon_colour = RadarColorSettings.default_marker_color("pickup_heretic_idol"),
    },
    show_ammo_crate_deployable = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_ammo",
        icon_colour = RadarColorSettings.default_marker_color("pickup_ammo_cache_deployable"),
    },
    show_medical_crate_deployable = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_medkit",
        icon_colour = RadarColorSettings.default_marker_color("medical_crate_deployable"),
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
    show_dark_rites_totem = {
        icon = "content/ui/materials/icons/achievements/categories/category_heretics",
        icon_colour = RadarColorSettings.default_marker_color("dark_rites_totem"),
    },
    show_dark_rites_servo_skull = {
        icon = "content/ui/materials/icons/abilities/default",
        icon_colour = RadarColorSettings.default_marker_color("dark_rites_servo_skull"),
    },
    show_pocketable_corrupted_auspex_scanner = {
        icon = "content/ui/materials/icons/pocketables/hud/auspex_scanner",
        icon_colour = RadarColorSettings.default_marker_color("pocketable_corrupted_auspex_scanner"),
    },
    show_unknown_pickups = {
        icon = "content/ui/materials/icons/traits/empty",
        icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
    },
}

--- Option icon for dropdowns without a presentation of their own.
local DEFAULT_DROPDOWN_PRESENTATION = {
    icon = DROPDOWN_ICON_DEFAULT,
    icon_colour = DROPDOWN_ICON_COLOUR_WHITE,
}

--- Dropdown option icon styles by icon colour table, so options with the same colour share one style.
local _dropdown_icon_style_by_colour = {}

--- The live dropdown icon colour tables by colour prefix, refreshed when their colour setting changes.
local _dropdown_icon_color_by_prefix = {}

--- Colour prefix of each live dropdown icon colour table.
local _dropdown_icon_prefix_by_colour = {}

--- Options tinted with each live colour prefix, which get a new icon style when the colour changes.
local _dropdown_icon_options_by_prefix = {}

--- Glyph options tinted with each live colour prefix, relabelled when the colour changes.
-- A glyph carries its colour in the label rather than in an icon style, so these are kept apart
-- from the icon options and each entry keeps the parts its label is rebuilt from.
local _dropdown_glyph_options_by_prefix = {}

--- Colour prefix of each native colour setting that tints dropdown icons.
local _dropdown_icon_prefix_by_setting_id = {}

--- Builds a native dropdown `icon_style` that tints the icon with one colour in every highlight state.
-- DMF copies the style's values into the widget style, so the states can share the colour table,
-- and re-applies a style only when an option gets a different style table.
-- tab: colour ARGB colour array
-- treturn: tab
local function _new_dropdown_icon_style(colour)
    return {
        color = colour,
        default_color = colour,
        hover_color = colour,
        selected_color = colour,
    }
end

--- Returns the shared icon style of a colour table, building it on first use.
-- tab: colour ARGB colour array
-- treturn: tab
local function _dropdown_icon_style(colour)
    local style = _dropdown_icon_style_by_colour[colour]

    if style == nil then
        style = _new_dropdown_icon_style(colour)
        _dropdown_icon_style_by_colour[colour] = style
    end

    return style
end

--- Declared ahead so the dropdown builders below can use them; assigned further down.
local _dropdown_marker_icon_colour
local _register_glyph_option

--- Builds a dropdown option, with an optional tinted icon.
-- string: text localization id of the option
-- param: value option value
-- ?string: icon icon material
-- ?tab: icon_colour icon colour, white when nil; a live marker colour keeps the tint up to date
-- treturn: tab
local function _dropdown_option(text, value, icon, icon_colour)
    local option = {
        text = text,
        value = value,
    }

    if icon then
        icon_colour = icon_colour or DROPDOWN_ICON_COLOUR_WHITE
        option.icon = icon
        option.icon_style = _dropdown_icon_style(icon_colour)

        local prefix = _dropdown_icon_prefix_by_colour[icon_colour]

        if prefix then
            local options = _dropdown_icon_options_by_prefix[prefix]
            options[#options + 1] = option
        end
    end

    return option
end

--- Builds a player marker style option with its style's icon.
local function _player_marker_style_dropdown_option(text, value)
    return _dropdown_option(text, value, PLAYER_MARKER_STYLE_DROPDOWN_ICON[value] or DROPDOWN_ICON_PLAYER,
        DROPDOWN_ICON_COLOUR_WHITE)
end

--- Builds the player marker style options, optionally followed by `off`.
-- treturn: tab
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

--- Builds the icon / off options of a marker dropdown.
local function _marker_enabled_options(setting_id)
    local presentation = MARKER_DROPDOWN_PRESENTATIONS[setting_id] or DEFAULT_DROPDOWN_PRESENTATION
    local icon_colour = _dropdown_marker_icon_colour(setting_id, presentation.icon_colour)

    return {
        _dropdown_option("marker_display_mode_icon", "icon", presentation.icon, icon_colour),
        _dropdown_option("radar_outline_off", "off"),
    }
end

--- Rewrites a saved checkbox value of a marker setting as its dropdown value.
-- The player marker setting keeps its style and mirrors it into the style setting. While it was
-- never saved it takes the teammate checkbox it replaced, before DMF saves its default instead.
-- string: setting_id setting to migrate
local function _migrate_marker_enabled_dropdown_setting(setting_id)
    local value = mod:get(setting_id)

    if setting_id == "show_players" then
        if value == nil then
            value = mod:get("show_teammates")

            if value == nil then
                return
            end
        end

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

--- Migrates every marker setting that changed from a checkbox to a dropdown.
function mod:migrate_marker_enabled_dropdown_settings()
    for setting_id in pairs(MARKER_DROPDOWN_PRESENTATIONS) do
        _migrate_marker_enabled_dropdown_setting(setting_id)
    end
end

--- Converts a display mode setting still saved by the checkbox it replaced into a dropdown value.
-- DMF shows the saved value as it is, so this runs while the menu is built.
-- string: setting_id dropdown setting id
-- string: enabled_value mode a saved `true` becomes; a saved `false` becomes `off`
local function _migrate_checkbox_display_mode_setting(setting_id, enabled_value)
    local value = mod:get(setting_id)

    if value == true then
        mod:set(setting_id, enabled_value)
    elseif value == false then
        mod:set(setting_id, "off")
    end
end

--- Padding between a Darktide glyph and the option text behind it.
-- A dropdown indents an option's text while the option carries an icon material. A glyph
-- option carries none, so this padding lines its text up with its icon-bearing siblings.
local GLYPH_LABEL_PADDING = "     "

--- Returns an icon option label whose glyph carries the marker colour.
-- The menu reads Darktide colour tags, which is the only way to tint a glyph, since the
-- colour of an option applies to its icon material and a glyph is text. Only the glyph is
-- tinted, so the label itself keeps the colour every other option label has.
-- string: glyph glyph character
-- tab: colour ARGB colour array
-- string: text localized option text
-- treturn: string
local function _glyph_option_text(glyph, colour, text)
    return string.format("{#color(%d,%d,%d)}%s{#reset()}%s%s",
        colour[2], colour[3], colour[4], glyph, GLYPH_LABEL_PADDING, text)
end

--- Builds an artwork / icon / off dropdown widget.
-- A value saved by the checkbox it replaced is converted first. Artwork is never tinted, so the
-- widget's `icon_color_mode` limits its icon colour to the `icon` mode. A presentation with
-- `icon_glyph` labels the icon option with a tinted glyph and carries no icon material, and
-- its options are localized here because they are built as finished text.
-- string: setting_id setting id
-- ?string: default_value default mode, `artwork` when nil
-- treturn: tab widget
local function _artwork_icon_off_dropdown(setting_id, default_value)
    local presentation = ARTWORK_DROPDOWN_PRESENTATIONS[setting_id] or DEFAULT_DROPDOWN_PRESENTATION
    local artwork_icon = presentation.artwork_icon or presentation.icon
    local artwork_colour = presentation.artwork_colour or presentation.icon_colour or DROPDOWN_ICON_COLOUR_WHITE
    local icon = presentation.icon
    local icon_glyph = presentation.icon_glyph
    local icon_colour = _dropdown_marker_icon_colour(setting_id, presentation.icon_colour)
    default_value = default_value or "artwork"

    _migrate_checkbox_display_mode_setting(setting_id, default_value)

    local options

    if icon_glyph then
        local icon_label = mod:localize("marker_display_mode_icon")
        local glyph_option = _dropdown_option(_glyph_option_text(icon_glyph, icon_colour, icon_label), "icon")

        _register_glyph_option(setting_id, glyph_option, icon_glyph, icon_label)

        options = {
            _dropdown_option(mod:localize("marker_display_mode_artwork"), "artwork", artwork_icon,
                artwork_colour),
            glyph_option,
            _dropdown_option(mod:localize("radar_outline_off"), "off"),
        }
        options.localize = false
    else
        options = {
            _dropdown_option("marker_display_mode_artwork", "artwork", artwork_icon, artwork_colour),
            _dropdown_option("marker_display_mode_icon", "icon", icon, icon_colour),
            _dropdown_option("radar_outline_off", "off"),
        }
    end

    return {
        setting_id = setting_id,
        type = "dropdown",
        default_value = default_value,
        icon_color_mode = "icon",
        options = options,
    }
end

--- Builds an icon size slider in percent (50 to 300, default 100).
-- treturn: tab widget
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

--- Title suffix of a colour widget by role, with an English fallback.
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

--- Colour prefixes of dropdowns whose colour cannot be derived from their setting id.
local DROPDOWN_COLOR_PREFIX_BY_SETTING_ID = {
    show_monstrosities = "enemy_boss_marker",
    show_captains = "enemy_boss_marker",
    show_karnak_twins = "enemy_boss_marker",
    show_enemy_horde = "enemy_horde_marker",
}

--- Returns the icon colour prefix anchored under a setting widget.
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

--- Returns the colour prefix a dropdown's icon is tinted with.
-- Tries the explicit table, then the colours anchored under the widget, then the marker or
-- enemy kind named by the `show_<kind>` setting id.
-- treturn: ?string
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

--- Converts one channel of a colour setting for a dropdown icon, rounded and clamped to 0 to 255.
-- param: value saved channel
-- ?number: default_value channel used when the value is not a number, 255 when nil
-- treturn: int
local function _dropdown_color_channel(value, default_value)
    value = tonumber(value)

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

--- Refreshes one live dropdown icon colour table from its native colour setting.
-- When the colour changed, every option tinted with it gets a new icon style, which makes DMF
-- apply the new tint to an open menu.
local function _refresh_dropdown_icon_colour(prefix)
    local color = prefix and _dropdown_icon_color_by_prefix[prefix] or nil

    if color == nil then
        return
    end

    local defaults = RadarColorSettings.default_by_prefix[prefix] or color
    local value = mod:get(RadarColorSettings.setting_id(prefix))

    if type(value) ~= "table" then
        value = defaults
    end

    local alpha = _dropdown_color_channel(value[1], defaults[1])
    local red = _dropdown_color_channel(value[2], defaults[2])
    local green = _dropdown_color_channel(value[3], defaults[3])
    local blue = _dropdown_color_channel(value[4], defaults[4])

    if color[1] == alpha and color[2] == red and color[3] == green and color[4] == blue then
        return
    end

    color[1] = alpha
    color[2] = red
    color[3] = green
    color[4] = blue

    local style = _new_dropdown_icon_style(color)
    local options = _dropdown_icon_options_by_prefix[prefix]

    _dropdown_icon_style_by_colour[color] = style

    for i = 1, #options do
        options[i].icon_style = style
    end

    local glyph_options = _dropdown_glyph_options_by_prefix[prefix]

    for i = 1, #glyph_options do
        local entry = glyph_options[i]
        local text = _glyph_option_text(entry.glyph, color, entry.text)

        -- DMF copies an option's text into its display name while it builds the widget, and the
        -- menu reads the display name of the open list and of the closed preview every frame.
        entry.option.text = text
        entry.option.display_name = text
    end
end

--- Records a glyph option against its colour prefix, so a colour change can relabel it.
-- string: setting_id dropdown setting id
-- tab: option dropdown option
-- string: glyph glyph character
-- string: text localized option text
_register_glyph_option = function(setting_id, option, glyph, text)
    local prefix = _dropdown_color_prefix(setting_id)
    local glyph_options = prefix and _dropdown_glyph_options_by_prefix[prefix] or nil

    if glyph_options == nil then
        return
    end

    glyph_options[#glyph_options + 1] = {
        option = option,
        glyph = glyph,
        text = text,
    }
end

--- Refreshes the live dropdown icon colour of a changed colour setting; other settings are ignored.
-- ?string: setting_id changed setting
local function _refresh_dropdown_icon_colours(setting_id)
    local prefix = setting_id and _dropdown_icon_prefix_by_setting_id[setting_id] or nil

    if prefix then
        _refresh_dropdown_icon_colour(prefix)
    end
end

--- Returns the live icon colour table of a dropdown.
-- The table is shared by every option using the same colour prefix and updated in place, and the
-- options using it are tracked so a colour change can give them a new icon style.
-- string: setting_id dropdown setting id
-- ?tab: fallback colour for dropdowns without a colour prefix
-- treturn: tab ARGB colour array
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
        _dropdown_icon_prefix_by_colour[color] = prefix
        _dropdown_icon_options_by_prefix[prefix] = {}
        _dropdown_glyph_options_by_prefix[prefix] = {}
        _dropdown_icon_prefix_by_setting_id[RadarColorSettings.setting_id(prefix)] = prefix
        _refresh_dropdown_icon_colour(prefix)
    end

    return color
end

--- Chains `mod.on_setting_changed` once so the dropdown icon colours follow the colour settings.
-- The refresh function itself is replaced on every load, so a reloaded data file refreshes
-- its own colour tables.
local function _install_dropdown_icon_color_refresh()
    mod._radar_dropdown_icon_color_refresh = _refresh_dropdown_icon_colours

    if mod._radar_dropdown_icon_color_refresh_installed then
        return
    end

    mod._radar_dropdown_icon_color_refresh_installed = true

    local previous_on_setting_changed = mod.on_setting_changed

    --- DMF callback, chained after any previously installed handler; refreshes the dropdown icon colour of a changed colour setting.
    -- string: setting_id changed setting
    -- param: ... further DMF arguments, forwarded to the previous handler
    mod.on_setting_changed = function(setting_id, ...)
        if previous_on_setting_changed then
            previous_on_setting_changed(setting_id, ...)
        end

        local refresh_dropdown_icon_color = mod._radar_dropdown_icon_color_refresh

        if refresh_dropdown_icon_color then
            refresh_dropdown_icon_color(setting_id)
        end
    end
end

_install_dropdown_icon_color_refresh()

--- Returns the localized text of an id, or the id itself when it has no localization.
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

--- Returns the localized title of a widget.
local function _localized_setting_title(widget)
    local title = widget and (widget.title or widget.setting_id) or nil

    if title == nil then
        return nil
    end

    return _localized_or_raw(title)
end

--- Returns the localized title suffix of a colour widget role.
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

--- Returns the title of a colour widget.
-- Combines the label prefix, or the anchor widget's title, with the role suffix; otherwise
-- falls back to the descriptor's title.
local function _color_setting_title(descriptor, anchor_widget)
    local label_role = descriptor.label_role
    local label_suffix = descriptor.label_suffix or (label_role and _localized_color_label_suffix(label_role))

    if label_suffix then
        -- An explicit prefix may be a localization key; anything already
        -- localized, including the anchor widget's own title, passes straight
        -- back out.
        local label_prefix = _localized_or_raw(descriptor.label_prefix) or _localized_setting_title(anchor_widget)

        if label_prefix and label_prefix ~= "" then
            return label_prefix .. label_suffix
        end
    end

    return _localized_or_raw(descriptor.title_prefix or "marker_color")
end

--- Builds the native ARGB colour widget of a colour descriptor.
-- Titles and tooltips are localized here, so the widget turns DMF's localization off.
-- tab: descriptor colour descriptor from `Radar_color_settings.lua`
-- ?tab: anchor_widget widget the colour belongs to
-- treturn: tab widget
local function _color_setting_widget(descriptor, anchor_widget)
    local prefix = descriptor.prefix

    return {
        setting_id = RadarColorSettings.setting_id(prefix),
        title = _color_setting_title(descriptor, anchor_widget),
        tooltip = mod:localize(descriptor.tooltip or "marker_color_slider_tooltip"),
        type = "color",
        localize = false,
        default_value = RadarColorSettings.default_color(prefix) or descriptor.default or { 255, 255, 255, 255 },
        has_alpha = true,
    }
end

--- Builds the colour widgets of every colour anchored to a setting id.
-- treturn: tab widgets
local function _color_setting_widgets(anchor)
    local color_widgets = {}
    local anchored_color_settings = RadarColorSettings.anchored_color_settings
    local color_descriptors = anchored_color_settings and anchored_color_settings[anchor] or nil

    if color_descriptors == nil then
        return color_widgets
    end

    for i = 1, #color_descriptors do
        color_widgets[#color_widgets + 1] = _color_setting_widget(color_descriptors[i], nil)
    end

    return color_widgets
end

--- Adds the colour widgets of every widget with anchored colours, recursively.
-- A checkbox or dropdown owns its colours as its first sub widgets, so DMF hides them while it is
-- off; colours marked `shared`, and the colours of any other widget, follow the widget as
-- siblings. Under a dropdown with `icon_color_mode`, icon colours are only shown in that mode.
-- Widgets with `skip_color_settings` get none.
-- tab: widgets widget list, modified in place
local function _insert_color_settings(widgets)
    local anchored_color_settings = RadarColorSettings.anchored_color_settings or {}
    local i = 1

    while i <= #widgets do
        local widget = widgets[i]
        local sub_widgets = widget.sub_widgets

        if sub_widgets then
            _insert_color_settings(sub_widgets)
        end

        local color_descriptors = widget.skip_color_settings ~= true and widget.setting_id and
            anchored_color_settings[widget.setting_id] or nil

        if color_descriptors and #color_descriptors > 0 then
            local owns_colors = widget.type == "checkbox" or widget.type == "dropdown"
            local insert_at = i
            local child_count = 0

            for descriptor_index = 1, #color_descriptors do
                local descriptor = color_descriptors[descriptor_index]
                local color_widget = _color_setting_widget(descriptor, widget)

                if owns_colors and descriptor.shared ~= true then
                    if sub_widgets == nil then
                        sub_widgets = {}
                        widget.sub_widgets = sub_widgets
                    end

                    if widget.icon_color_mode and descriptor.label_role == "icon" then
                        color_widget.show_in_mode = widget.icon_color_mode
                    end

                    child_count = child_count + 1
                    table.insert(sub_widgets, child_count, color_widget)
                else
                    insert_at = insert_at + 1
                    table.insert(widgets, insert_at, color_widget)
                end
            end

            i = insert_at
        end

        i = i + 1
    end
end

--- Builds the checkbox that shows nearby highlight distance text on the radar for a group.
local function _nearby_highlight_radar_distance_text_checkbox(setting_id)
    return {
        setting_id = setting_id,
        title = "nearby_highlight_radar_distance_text",
        tooltip = "nearby_highlight_radar_distance_text_tooltip",
        type = "checkbox",
        default_value = false,
    }
end

--- Builds a vertical arrows checkbox for an enemy category.
local function _enemy_vertical_arrows_checkbox(setting_id)
    return {
        setting_id = setting_id,
        tooltip = "show_enemy_vertical_arrows_tooltip",
        type = "checkbox",
        default_value = false,
    }
end

--- Maps a saved enemy setting (checkbox or dropdown value) to `icon_only`, `marked_icon` or `off`.
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

--- Builds an enemy icon / marked icon / off dropdown widget.
-- treturn: tab widget
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

--- Builds an icon / icon and distance / off dropdown widget.
-- A value saved by the checkbox it replaced is converted first.
-- string: setting_id setting id
-- string: default_value default mode
-- ?tab: presentations option icon table, `MARKER_DROPDOWN_PRESENTATIONS` when nil
-- treturn: tab widget
local function _icon_distance_off_dropdown(setting_id, default_value, presentations)
    presentations = presentations or MARKER_DROPDOWN_PRESENTATIONS

    local presentation = presentations[setting_id] or DEFAULT_DROPDOWN_PRESENTATION
    local icon = presentation.icon
    local icon_colour = _dropdown_marker_icon_colour(setting_id, presentation.icon_colour)

    _migrate_checkbox_display_mode_setting(setting_id, "icon_only")

    return {
        setting_id = setting_id,
        type = "dropdown",
        default_value = default_value,
        options = {
            _dropdown_option("display_style_icon_only", "icon_only", icon, icon_colour),
            _dropdown_option("display_style_icon_distance", "icon_distance", icon, icon_colour),
            _dropdown_option("radar_outline_off", "off"),
        },
    }
end

--- Builds an Expedition location display mode dropdown.
local function _expedition_marker_display_mode_dropdown(setting_id, default_value)
    return _icon_distance_off_dropdown(setting_id, default_value, EXPEDITION_DROPDOWN_PRESENTATIONS)
end

--- Builds the Tech-Remnant marker mode dropdown (default, scaled, clustered).
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


--- Turns the marker checkboxes listed in `MARKER_DROPDOWN_PRESENTATIONS` into dropdowns, recursively.
-- Saved checkbox values are migrated first. The player marker checkbox becomes the player
-- marker style dropdown; every other one an icon / off dropdown. Sub widgets are kept.
-- tab: widgets widget list, modified in place
local function _apply_marker_enabled_dropdowns(widgets)
    for i = 1, #widgets do
        local widget = widgets[i]
        local setting_id = widget.setting_id

        if widget.sub_widgets then
            _apply_marker_enabled_dropdowns(widget.sub_widgets)
        end

        if widget.type == "checkbox" and setting_id and MARKER_DROPDOWN_PRESENTATIONS[setting_id] then
            local default_value = widget.default_value == nil and true or widget.default_value

            _migrate_marker_enabled_dropdown_setting(setting_id)

            widget.type = "dropdown"
            if setting_id == "show_players" then
                widget.default_value = "marked_icon"
                widget.options = _player_marker_style_options(true)
            else
                widget.default_value = default_value == false and "off" or "icon"
                widget.options = _marker_enabled_options(setting_id)
            end
        end
    end
end

--- Gives every dropdown with sub widgets the option `show_widgets` DMF hides them by, recursively.
-- `off` shows none of them. Every other option shows the sub widgets without a `show_in_mode`
-- and those whose `show_in_mode` is that option's value. Checkboxes need nothing, since DMF hides
-- their sub widgets while they are unticked.
-- tab: widgets widget list, modified in place
local function _apply_sub_widget_visibility(widgets)
    for i = 1, #widgets do
        local widget = widgets[i]
        local sub_widgets = widget.sub_widgets

        if sub_widgets then
            _apply_sub_widget_visibility(sub_widgets)

            if widget.type == "dropdown" then
                local options = widget.options

                for option_index = 1, #options do
                    local option = options[option_index]

                    if option.value ~= "off" then
                        local show_widgets = {}

                        for child_index = 1, #sub_widgets do
                            local show_in_mode = sub_widgets[child_index].show_in_mode

                            if show_in_mode == nil or show_in_mode == option.value then
                                show_widgets[#show_widgets + 1] = child_index
                            end
                        end

                        option.show_widgets = show_widgets
                    end
                end
            end
        end
    end
end

--- Gives every widget without a tooltip the `<setting_id>_tooltip` localization id, recursively.
local function _apply_missing_tooltips(widgets)
    for i = 1, #widgets do
        local widget = widgets[i]

        if widget.type ~= "group" and widget.setting_id and widget.tooltip == nil then
            widget.tooltip = widget.setting_id .. "_tooltip"
        end

        if widget.sub_widgets then
            _apply_missing_tooltips(widget.sub_widgets)
        end
    end
end

--- Picks the map geometry source from the two toggles it replaced, while it was never saved.
-- Runs before DMF saves the dropdown's default over the unset setting.
local function _migrate_map_geometry_source_setting()
    if mod:get("map_geometry_source") ~= nil then
        return
    end

    if mod:get("use_strikemap_geometry") == true then
        mod:set("map_geometry_source", "strikemap")
    elseif mod:get("show_navmesh") == true then
        mod:set("map_geometry_source", "live")
    end
end

-- Settings DMF would otherwise initialise with their defaults take their saved older form first.
RadarColorSettings.migrate_channel_settings(mod)
_migrate_map_geometry_source_setting()

--- The DMF mod data table.
return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = (function()
            local common_enemy_display_default = _normalize_icon_marked_off_default(mod:get("show_enemy_common"), "icon_only")
            local shooter_enemy_display_default = _normalize_icon_marked_off_default(mod:get("show_enemy_shooter"), "icon_only")
            local widgets = {
                {
                    setting_id = "general_group",
                    title = "tab_general",
                    type = "group",
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
                                    setting_id = "radar_scan_rate",
                                    type = "dropdown",
                                    default_value = "low",
                                    options = {
                                        _dropdown_option("radar_scan_rate_low", "low"),
                                        _dropdown_option("radar_scan_rate_medium", "medium"),
                                        _dropdown_option("radar_scan_rate_high", "high"),
                                    },
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
                    setting_id = "layout_group",
                    title = "tab_layout",
                    type = "group",
                    sub_widgets = {
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
                                },
                                {
                                    setting_id = "radar_pos_y",
                                    type = "numeric",
                                    default_value = 220,
                                    range = { -12000, 12000 },
                                    decimals_number = 0,
                                    step_size_value = 5,
                                },
                                {
                                    setting_id = "radar_move_step",
                                    type = "numeric",
                                    default_value = 10,
                                    range = { 1, 200 },
                                    decimals_number = 0,
                                    step_size_value = 1,
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
                            skip_color_settings = true,
                            sub_widgets = _color_setting_widgets("radar_colors_group"),
                        },
                        {
                            setting_id = "radar_map_geometry_group",
                            type = "group",
                            sub_widgets = {
                                {
                                    setting_id = "map_geometry_source",
                                    type = "dropdown",
                                    default_value = "off",
                                    options = {
                                        _dropdown_option("radar_outline_off", "off"),
                                        _dropdown_option("map_geometry_source_live", "live"),
                                        _dropdown_option("map_geometry_source_strikemap", "strikemap"),
                                        _dropdown_option("map_geometry_source_auto", "auto"),
                                    },
                                },
                                {
                                    setting_id = "navmesh_range_above",
                                    type = "numeric",
                                    default_value = 7,
                                    range = { 1, 30 },
                                    decimals_number = 0,
                                    step_size_value = 1,
                                },
                                {
                                    setting_id = "navmesh_range_below",
                                    type = "numeric",
                                    default_value = 7,
                                    range = { 1, 30 },
                                    decimals_number = 0,
                                    step_size_value = 1,
                                },
                                {
                                    setting_id = "strikemap_geometry_in_overview",
                                    type = "checkbox",
                                    default_value = true,
                                },
                                {
                                    setting_id = "strikemap_vector_details",
                                    type = "checkbox",
                                    default_value = true,
                                },
                                {
                                    setting_id = "strikemap_hatch_above",
                                    type = "checkbox",
                                    default_value = false,
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
                    },
                },
                {
                    setting_id = "pickups_group",
                    title = "tab_pickups",
                    type = "group",
                    sub_widgets = {
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
                                _icon_distance_off_dropdown("show_explosive_barrels", "icon_only"),
                                _icon_distance_off_dropdown("show_fire_barrels", "icon_only"),
                                {
                                    setting_id = "show_medicae_station",
                                    type = "checkbox",
                                    default_value = true,
                                    sub_widgets = {
                                        {
                                            setting_id = "show_medicae_station_charges",
                                            type = "checkbox",
                                            default_value = true,
                                        },
                                    },
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
                                _nearby_highlight_radar_distance_text_checkbox("nearby_highlight_distance_text_deployables"),
                                {
                                    setting_id = "show_ammo_crate_deployable",
                                    type = "checkbox",
                                    default_value = true,
                                    sub_widgets = {
                                        {
                                            setting_id = "show_ammo_crate_deployable_charges",
                                            type = "checkbox",
                                            default_value = true,
                                        },
                                    },
                                },
                                {
                                    setting_id = "show_medical_crate_deployable",
                                    type = "checkbox",
                                    default_value = true,
                                },
                            },
                        },
                    },
                },
                {
                    setting_id = "objectives_group",
                    title = "tab_objectives",
                    type = "group",
                    sub_widgets = {
                        {
                            setting_id = "mission_objective_group",
                            type = "group",
                            sub_widgets = {
                                _icon_scale_slider("mission_objective_icon_scale", nil),
                                {
                                    setting_id = "nearby_highlight_mission_objective",
                                    type = "checkbox",
                                    default_value = false,
                                },
                                _nearby_highlight_radar_distance_text_checkbox(
                                    "nearby_highlight_distance_text_mission_objective"),
                                _icon_distance_off_dropdown("show_mission_objective_scanner", "icon_only"),
                                _icon_distance_off_dropdown("show_mission_objective_hacking", "icon_only"),
                                _icon_distance_off_dropdown("show_mission_objective_servo_skull", "icon_only"),
                                _icon_distance_off_dropdown("show_mission_objective_growth", "icon_only"),
                                _icon_distance_off_dropdown("show_mission_objective_destroy", "icon_only"),
                                _icon_distance_off_dropdown("show_mission_objective_other", "icon_only"),
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
                                    setting_id = "show_martyr_skull_riddle_interactables",
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
                                _artwork_icon_off_dropdown("show_tainted_skull", "artwork"),
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
                                _artwork_icon_off_dropdown("show_saints", "artwork"),
                                _artwork_icon_off_dropdown("show_leftover", "artwork"),
                                _artwork_icon_off_dropdown("show_stolen_rations", "artwork"),
                            },
                        },
                    },
                },
                {
                    setting_id = "expeditions_group",
                    title = "tab_expeditions",
                    type = "group",
                    sub_widgets = {
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
                    },
                },
                {
                    setting_id = "enemies_group",
                    title = "tab_enemies",
                    type = "group",
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
                                _icon_marked_off_dropdown("show_enemy_cultist_vanguard", common_enemy_display_default),
                                _icon_marked_off_dropdown("show_enemy_renegade_vanguard", common_enemy_display_default),
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
                    title = "tab_players",
                    type = "group",
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
                                    sub_widgets = {
                                        {
                                            setting_id = "show_player_state_icons",
                                            tooltip = "show_player_state_icons_tooltip",
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
                                        },
                                    },
                                },
                            },
                        },
                        {
                            setting_id = "player_companions_group",
                            type = "group",
                            sub_widgets = {
                                _icon_scale_slider("player_companions_icon_scale", nil),
                                {
                                    setting_id = "show_cyber_mastiff",
                                    type = "checkbox",
                                    default_value = true,
                                },
                                {
                                    setting_id = "show_servo_skulls",
                                    type = "checkbox",
                                    default_value = true,
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
                                    sub_widgets = {
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
                    },
                },
                {
                    setting_id = "debug_group",
                    title = "tab_debug",
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

            _apply_marker_enabled_dropdowns(widgets)
            _insert_color_settings(widgets)
            _apply_sub_widget_visibility(widgets)
            _apply_missing_tooltips(widgets)

            return widgets
        end)(),
    },
}
