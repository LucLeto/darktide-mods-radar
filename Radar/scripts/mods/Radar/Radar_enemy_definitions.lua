return function(env)
    setfenv(1, env)

    local mod = mod

    local pcall = pcall
    local pairs = pairs
    local tonumber = tonumber
    local tostring = tostring
    local rawget = rawget
    local string_format = string.format
    local string_sub = string.sub
    local RadarColorSettings = mod:io_dofile("Radar/scripts/mods/Radar/Radar_color_settings")

    RadarColorSettings.install_runtime(mod)

    SCAN_INTERVAL = 0.25

    NEARBY_OUTLINE_OCCLUDED_MULTIPLIER = 0.6

    NEARBY_OUTLINE_COLOR_BY_KIND = {
        material_diamantine = { 255, 70, 130, 220 },
        material_plasteel = { 255, 130, 135, 140 },
        crate_unknown = { 255, 225, 200, 136 },
        pickup_ammo = { 255, 240, 210, 80 },
        pickup_ammo_small = { 255, 240, 210, 80 },
        pickup_ammo_big = { 255, 240, 210, 80 },
        pickup_grenade = { 255, 205, 156, 77 },
        pocketable_ammo_crate = { 255, 240, 210, 80 },
        pocketable_medical_crate = { 255, 38, 205, 26 },
        pocketable_syringe_ability = { 255, 230, 192, 13 },
        pocketable_syringe_corruption = { 255, 38, 205, 26 },
        pocketable_syringe_power = { 255, 205, 51, 26 },
        pocketable_syringe_speed = { 255, 0, 127, 218 },
        luggable_power_cell_teal = { 255, 0, 200, 200 },
        luggable_cryonic_rod = { 255, 180, 220, 255 },
        luggable_moebian_pox_zetaphyte_13_sample = { 255, 150, 190, 60 },
        luggable_vacuum_capsule = { 255, 80, 85, 90 },
        luggable_special_issue_ammo = { 255, 95, 125, 70 },
        luggable_prismata_crystal_repository = { 255, 255, 70, 90 },
        pickup_mortis_relic = { 255, 110, 95, 125 },
        pickup_coordinates_paper = DEFAULT_COLOR_ARRAY_WHITE,
        pocketable_grimoire = { 255, 150, 190, 60 },
        pocketable_scripture = { 255, 192, 160, 0 },
        material_expeditions_currency = { 255, 120, 160, 140 },
        material_expeditions_loot = { 255, 192, 160, 0 },
        material_expeditions_loot_player_drop = { 220, 255, 0, 0 },
        luggable_data_reliquary = { 255, 192, 160, 0 },
        pickup_large_ammunition_crate = { 255, 240, 210, 80 },
        luggable_promethium_barrel = { 255, 255, 110, 0 },
        pocketable_anti_rad_stimm = DEFAULT_COLOR_ARRAY_WHITE,
        pocketable_airstrike = { 255, 95, 125, 70 },
        pocketable_artillery_strike = { 255, 95, 125, 70 },
        pocketable_big_grenade = { 255, 205, 156, 77 },
        pocketable_landmine_explosive = { 255, 205, 156, 77 },
        pocketable_landmine_fire = { 255, 255, 110, 0 },
        pocketable_landmine_shock = { 255, 80, 160, 255 },
        pocketable_valkyrie_hover = { 255, 95, 125, 70 },
        pocketable_void_shield = { 255, 181, 166, 66 },
        pickup_martyr_skull = { 255, 255, 215, 0 },
        luggable_power_cell_orange = { 255, 255, 140, 0 },
        medicae_station = { 255, 38, 205, 26 },
        luggable_socket = { 255, 255, 245, 80 },
        pickup_heretic_idol = { 255, 150, 190, 60 },
        pickup_tainted_skull = { 255, 150, 190, 60 },
        dark_rites_totem = { 255, 150, 190, 60 },
        dark_rites_servo_skull = { 255, 150, 190, 60 },
        pocketable_corrupted_auspex_scanner = { 255, 255, 120, 0 },
        pickup_saints = { 255, 192, 160, 0 },
        pickup_stolen_rations = { 255, 150, 190, 60 },
    }

    mod._next_scan_t = 0
    mod._tracked_units = {}
    mod._tracked_points = {}
    mod._logged_units = {}
    mod._radar_targets = {}
    mod._radar_snapshot = nil
    mod._gameplay_run = false
    mod._last_update_t = nil
    mod._last_scan_signature = nil
    mod._last_block_signature = nil
    mod._dark_rites_marker_scan_cache_valid = false
    mod._dark_rites_marker_scan_allowed = true
    mod._dark_rites_marker_cached_circumstance_name = nil
    mod._screen_highlight_targets = {}
    mod._unclustered_radar_targets = {}
    mod._highlight_source_radar_targets = {}
    mod._idol_destroyed_collectible_keys = {}
    mod._idol_destroyed_units = {}
    mod._last_safe_zone_section_index = nil
    mod._last_expedition_in_safe_zone = nil
    mod._player_smart_tag_generation = 0
    mod._player_smart_tag_state_by_id = {}

    MONSTROSITY_BREEDS = {
        chaos_daemonhost = true,
        chaos_beast_of_nurgle = true,
        chaos_plague_ogryn = true,
        chaos_spawn = true,
        chaos_ogryn_houndmaster = true,
    }

    CAPTAIN_BREEDS = {
        renegade_captain = true,
        cultist_captain = true,
    }

    TWIN_BREEDS = {
        renegade_twin_captain = true,
        renegade_twin_captain_two = true,
    }

    KIND_TO_SETTING = {
        pickup_ammo = "show_ammo_small",
        pickup_ammo_small = "show_ammo_small",
        pickup_ammo_big = "show_ammo_big",
        pickup_grenade = "show_grenades",
        pickup_medkit = "show_medkits",
        pickup_stimm = "show_stimms",
        pickup_unknown = "show_unknown_pickups",
        medicae_station = "show_medicae_station",
        luggable_socket = "show_luggable_socket",
        pickup_heretic_idol = "show_heretic_idol",
        pickup_tainted_skull = "show_tainted_skull",
        dark_rites_totem = "show_dark_rites_totem",
        dark_rites_servo_skull = "show_dark_rites_servo_skull",
        crate_unknown = "show_crates",
        enemy_daemonhost = "show_monstrosities",
        enemy_monstrosity = "show_monstrosities",
        enemy_captain = "show_captains",
        enemy_karnak_twin = "show_karnak_twins",
        player_teammate = "show_players",
        location_attention = "show_player_tags",
        location_ping = "show_player_tags",
        location_threat = "show_player_tags",
        material_diamantine = "show_diamantine",
        material_plasteel = "show_plasteel",
        material_expeditions_currency = "show_expeditions_currency",
        material_expeditions_loot = "show_expeditions_loot",
        material_expeditions_loot_player_drop = "show_expeditions_dropped_loot",
        expedition_loot_converter = "show_expedition_loot_converter",
        expedition_objective_opportunity = "show_expedition_objective_opportunity",
        expedition_objective_transition = "show_expedition_objective_transition",
        expedition_objective_main_objective = "show_expedition_objective_main_objective",
        expedition_objective_extraction = "show_expedition_objective_extraction",
        expedition_objective_arrival = "show_expedition_objective_arrival",
        luggable_data_reliquary = "show_data_reliquaries",
        pickup_large_ammunition_crate = "show_large_ammunition_crate",
        luggable_promethium_barrel = "show_promethium_barrel",
        pocketable_anti_rad_stimm = "show_anti_rad_stimm",
        pocketable_ammo_crate = "show_pocketable_ammo_crate",
        pocketable_breach_charge = "show_pocketable_breach_charge",
        pocketable_corrupted_auspex_scanner = "show_pocketable_corrupted_auspex_scanner",
        pocketable_expedition_loot_crate = "show_pocketable_expedition_loot_crate",
        pocketable_airstrike = "show_pocketable_airstrike",
        pocketable_artillery_strike = "show_pocketable_artillery_strike",
        pocketable_big_grenade = "show_pocketable_big_grenade",
        pocketable_grimoire = "show_pocketable_grimoire",
        pocketable_landmine_explosive = "show_pocketable_landmine_explosive",
        pocketable_landmine_fire = "show_pocketable_landmine_fire",
        pocketable_landmine_shock = "show_pocketable_landmine_shock",
        pocketable_medical_crate = "show_pocketable_medical_crate",
        pocketable_scripture = "show_pocketable_scripture",
        pocketable_syringe_ability = "show_pocketable_syringe_ability",
        pocketable_syringe_corruption = "show_pocketable_syringe_corruption",
        pocketable_syringe_power = "show_pocketable_syringe_power",
        pocketable_syringe_speed = "show_pocketable_syringe_speed",
        pocketable_valkyrie_hover = "show_pocketable_valkyrie_hover",
        pocketable_void_shield = "show_pocketable_void_shield",
        pickup_ammo_cache_deployable = "show_ammo_crate_deployable",
        medical_crate_deployable = "show_medical_crate_deployable",
    }

    EXPEDITION_MARKER_KINDS = {
        expedition_loot_converter = true,
        expedition_objective_opportunity = true,
        expedition_objective_transition = true,
        expedition_objective_main_objective = true,
        expedition_objective_extraction = true,
        expedition_objective_arrival = true,
    }

    EXPEDITION_MARKER_DISPLAY_MODE_KIND_TO_SETTING = {
        expedition_loot_converter = "show_expedition_loot_converter",
        expedition_objective_opportunity = "show_expedition_objective_opportunity",
        expedition_objective_transition = "show_expedition_objective_transition",
        expedition_objective_main_objective = "show_expedition_objective_main_objective",
        expedition_objective_extraction = "show_expedition_objective_extraction",
        expedition_objective_arrival = "show_expedition_objective_arrival",
    }

    EXPEDITION_MARKER_DISPLAY_MODE_DEFAULT_BY_SETTING = {
        show_expedition_objective_opportunity = "icon_distance",
        show_expedition_objective_transition = "icon_only",
        show_expedition_objective_main_objective = "icon_only",
        show_expedition_objective_extraction = "icon_only",
        show_expedition_objective_arrival = "icon_only",
        show_expedition_loot_converter = "icon_only",
    }

    EXPEDITION_OBJECTIVE_ICON_DEFAULTS = {
        expedition_loot_converter = "content/ui/materials/hud/interactions/icons/expeditions",
        expedition_objective_transition = "content/ui/materials/backgrounds/scanner/scanner_map_exit",
        expedition_objective_main_objective = "content/ui/materials/hud/interactions/icons/objective_main",
        expedition_objective_extraction = "content/ui/materials/backgrounds/scanner/scanner_map_extract",
        expedition_objective_arrival = "content/ui/materials/icons/mission_types/mission_type_05",
    }

    ARTWORK_MODE_KIND_TO_SETTING = {
        crate_unknown = "show_crates",
        material_diamantine = "show_diamantine",
        material_plasteel = "show_plasteel",
        material_expeditions_currency = "show_expeditions_currency",
        material_expeditions_loot = "show_expeditions_loot",
        material_expeditions_loot_player_drop = "show_expeditions_dropped_loot",
        pocketable_airstrike = "show_pocketable_airstrike",
        pocketable_artillery_strike = "show_pocketable_artillery_strike",
        pocketable_big_grenade = "show_pocketable_big_grenade",
        pocketable_valkyrie_hover = "show_pocketable_valkyrie_hover",
        pocketable_landmine_explosive = "show_pocketable_landmine_explosive",
        pocketable_landmine_fire = "show_pocketable_landmine_fire",
        pocketable_landmine_shock = "show_pocketable_landmine_shock",
        pocketable_void_shield = "show_pocketable_void_shield",
    }

    local MARKER_SCALE_GROUP_BY_KIND = {
        crate_unknown = "common_pickups_group",
        pickup_ammo = "common_pickups_group",
        pickup_ammo_small = "common_pickups_group",
        pickup_ammo_big = "common_pickups_group",
        pickup_grenade = "common_pickups_group",
        pickup_medkit = "common_pickups_group",
        pickup_stimm = "common_pickups_group",
        pocketable_ammo_crate = "common_pickups_group",
        pocketable_medical_crate = "common_pickups_group",
        pocketable_syringe_ability = "common_pickups_group",
        pocketable_syringe_corruption = "common_pickups_group",
        pocketable_syringe_power = "common_pickups_group",
        pocketable_syringe_speed = "common_pickups_group",
        material_diamantine = "materials_group",
        material_plasteel = "materials_group",
        luggable_power_cell_teal = "primary_objective_group",
        luggable_cryonic_rod = "primary_objective_group",
        luggable_moebian_pox_zetaphyte_13_sample = "primary_objective_group",
        luggable_vacuum_capsule = "primary_objective_group",
        luggable_special_issue_ammo = "primary_objective_group",
        luggable_prismata_crystal_repository = "primary_objective_group",
        pickup_mortis_relic = "primary_objective_group",
        pickup_coordinates_paper = "primary_objective_group",
        pocketable_grimoire = "secondary_objective_group",
        pocketable_scripture = "secondary_objective_group",
        expedition_loot_converter = "expeditions_location_group",
        expedition_objective_opportunity = "expeditions_location_group",
        expedition_objective_transition = "expeditions_location_group",
        expedition_objective_main_objective = "expeditions_location_group",
        expedition_objective_extraction = "expeditions_location_group",
        expedition_objective_arrival = "expeditions_location_group",
        material_expeditions_currency = "expeditions_specific_group",
        material_expeditions_loot = "expeditions_specific_group",
        material_expeditions_loot_player_drop = "expeditions_specific_group",
        luggable_data_reliquary = "expeditions_specific_group",
        pickup_large_ammunition_crate = "expeditions_specific_group",
        luggable_promethium_barrel = "expeditions_specific_group",
        pocketable_anti_rad_stimm = "expeditions_specific_group",
        pocketable_airstrike = "expeditions_specific_group",
        pocketable_artillery_strike = "expeditions_specific_group",
        pocketable_big_grenade = "expeditions_specific_group",
        pocketable_landmine_explosive = "expeditions_specific_group",
        pocketable_landmine_fire = "expeditions_specific_group",
        pocketable_landmine_shock = "expeditions_specific_group",
        pocketable_valkyrie_hover = "expeditions_specific_group",
        pocketable_void_shield = "expeditions_specific_group",
        pickup_martyr_skull = "martyr_s_skull_group",
        luggable_power_cell_orange = "martyr_s_skull_group",
        medicae_station = "environment_group",
        luggable_socket = "environment_group",
        pickup_heretic_idol = "environment_group",
        pickup_ammo_cache_deployable = "deployables_group",
        medical_crate_deployable = "deployables_group",
        player_teammate = "players_group",
        location_attention = "players_group",
        location_ping = "players_group",
        location_threat = "players_group",
        pickup_tainted_skull = "event_group",
        dark_rites_totem = "event_group",
        dark_rites_servo_skull = "event_group",
        pocketable_corrupted_auspex_scanner = "event_group",
        pickup_saints = "event_group",
        pickup_stolen_rations = "event_group",
        pickup_unknown = "debug_group",
    }

    local ICON_SCALE_SETTING_BY_GROUP = {
        common_pickups_group = "common_pickups_icon_scale",
        materials_group = "materials_icon_scale",
        primary_objective_group = "primary_objective_icon_scale",
        secondary_objective_group = "secondary_objective_icon_scale",
        expeditions_location_group = "expeditions_location_icon_scale",
        expeditions_specific_group = "expeditions_specific_icon_scale",
        martyr_s_skull_group = "martyr_s_skull_icon_scale",
        environment_group = "environment_icon_scale",
        deployables_group = "deployables_icon_scale",
        enemies_group = "enemies_icon_scale",
        players_group = "players_icon_scale",
        event_group = "event_icon_scale",
        debug_group = "debug_icon_scale",
    }

    local ENEMY_RADAR_SCALE_SETTING_BY_KIND = {
        enemy_daemonhost = "enemy_boss_icon_scale",
        enemy_monstrosity = "enemy_boss_icon_scale",
        enemy_captain = "enemy_boss_icon_scale",
        enemy_karnak_twin = "enemy_boss_icon_scale",
    }

    local ENEMY_RADAR_DEFAULT_COLOR = { 220, 255, 0, 0 }
    local ENEMY_RADAR_DEFAULT_DREG_COLOR = { 255, 255, 255, 0 }
    local ENEMY_RADAR_DEFAULT_SCAB_COLOR = DEFAULT_COLOR_ARRAY_WHITE
    local ENEMY_RADAR_DEFAULT_TOX_COLOR = { 255, 0, 255, 0 }
    local ENEMY_RADAR_DEFAULT_MUTATOR_COLOR = { 255, 150, 190, 60 }

    local ENEMY_RADAR_BACKGROUND_ICON = "content/ui/materials/hud/interactions/icons/default"

    local ENEMY_RADAR_GROUP_SETTING_IDS = {
        shooter = "show_enemy_shooter",
        common = "show_enemy_common",
        horde = "show_enemy_horde",
    }

    local ENEMY_RADAR_SCALE_SETTING_BY_CATEGORY = {
        special = "enemy_special_icon_scale",
        elite = "enemy_elite_icon_scale",
        shooter = "enemy_shooter_icon_scale",
        common = "enemy_common_icon_scale",
        horde = "enemy_horde_icon_scale",
        misc = "enemy_misc_icon_scale",
    }

    local ENEMY_RADAR_VERTICAL_ARROW_SETTING_BY_KIND = {
        enemy_daemonhost = "show_enemy_boss_vertical_arrows",
        enemy_monstrosity = "show_enemy_boss_vertical_arrows",
        enemy_captain = "show_enemy_boss_vertical_arrows",
        enemy_karnak_twin = "show_enemy_boss_vertical_arrows",
    }

    local ENEMY_RADAR_VERTICAL_ARROW_SETTING_BY_CATEGORY = {
        special = "show_enemy_special_vertical_arrows",
        elite = "show_enemy_elite_vertical_arrows",
        shooter = "show_enemy_shooter_vertical_arrows",
        common = "show_enemy_common_vertical_arrows",
        horde = "show_enemy_horde_vertical_arrows",
        misc = "show_enemy_misc_vertical_arrows",
    }

    local ENEMY_RADAR_SELECTION_PRIORITY = {
        boss = 500,
        special = 400,
        elite = 350,
        misc = 325,
        shooter = 200,
        common = 100,
        horde = 50,
    }

    local ENEMY_RADAR_RENDER_LAYER = {
        boss = 5,
        special = 4,
        elite = 4,
        misc = 4,
        shooter = 2,
        common = 1,
        horde = 0,
    }
    local PLAYER_SMART_TAG_SELECTION_PRIORITY = 300
    local PLAYER_SMART_TAG_RENDER_LAYER = 3
    local EVENT_MARKER_SELECTION_PRIORITY = 600
    local EVENT_MARKER_RENDER_LAYER = 7
    local EXPEDITION_PLAYER_DROP_SELECTION_PRIORITY = 650
    local EXPEDITION_PLAYER_DROP_RENDER_LAYER = 6

    local function _enemy_radar_default_icon_size(category)
        if category == "horde" then
            return 8
        end

        if category == "common" then
            return 8
        end

        if category == "shooter" then
            return 8
        end

        return 10
    end

    local function _enemy_radar_default_background_size(category)
        if category == "horde" then
            return nil
        end

        if category == "common" then
            return 8
        end

        if category == "shooter" then
            return 12
        end

        return 14
    end

    local function _enemy_radar_default_size(category)
        return _enemy_radar_default_background_size(category) or _enemy_radar_default_icon_size(category)
    end

    function _enemy_radar_def(category, icon, icon_color, background_color, setting_id, extra)
        local def = extra or {}
        local default_icon_size = _enemy_radar_default_icon_size(category)
        local default_background_size = background_color and _enemy_radar_default_background_size(category) or nil

        def.category = category
        def.scale_category = def.scale_category or category
        def.icon = icon
        def.icon_color = icon_color
        def.background_icon = background_color and ENEMY_RADAR_BACKGROUND_ICON or nil
        def.background_color = background_color
        def.setting_id = setting_id or ENEMY_RADAR_GROUP_SETTING_IDS[category]
        def.priority_group = def.priority_group or category
        def.icon_size = def.icon_size or default_icon_size
        def.background_size = def.background_size or default_background_size
        def.size = def.size or def.background_size or def.icon_size or _enemy_radar_default_size(category)
        def.bracket_size = def.bracket_size or def.background_size or def.icon_size or def.size

        return def
    end

    ENEMY_RADAR_DEFINITIONS_BY_BREED = {
        renegade_grenadier = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/abilities/throwables/default",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_grenadier",
            {
                icon_size = 12,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        cultist_grenadier = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/abilities/throwables/default",
            ENEMY_RADAR_DEFAULT_TOX_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_grenadier",
            {
                icon_size = 12,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        cultist_gunner = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/weapons/actions/full_auto",
            ENEMY_RADAR_DEFAULT_DREG_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_gunner",
            {
                icon_size = 8,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        renegade_gunner = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/weapons/actions/full_auto",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_gunner",
            {
                icon_size = 8,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        renegade_radio_operator = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/weapons/actions/full_auto",
            ENEMY_RADAR_DEFAULT_MUTATOR_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_gunner",
            {
                icon_size = 8,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        renegade_plasma_gunner = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/weapons/actions/charge",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_plasma_gunner",
            {
                icon_size = 10,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        chaos_ogryn_gunner = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/weapons/actions/hipfire",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_chaos_ogryn_gunner",
            {
                icon_size = 10,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        chaos_hound = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/circumstances/hunting_grounds_01",
            ENEMY_RADAR_DEFAULT_DREG_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_chaos_hound",
            {
                icon_size = 10,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        chaos_hound_mutator = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/circumstances/hunting_grounds_01",
            ENEMY_RADAR_DEFAULT_MUTATOR_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_chaos_hound",
            {
                icon_size = 10,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        chaos_armored_hound = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/circumstances/hunting_grounds_01",
            { 255, 150, 150, 150 },
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_chaos_armored_hound",
            {
                icon_size = 10,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        chaos_poxwalker_bomber = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/presets/preset_19",
            ENEMY_RADAR_DEFAULT_TOX_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_chaos_poxwalker_bomber",
            {
                icon_size = 12,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        renegade_executor = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/item_types/melee_weapons",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_executor",
            {
                icon_size = 10,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        renegade_executor_gibbing_rotten_armor = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/item_types/melee_weapons",
            ENEMY_RADAR_DEFAULT_MUTATOR_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_executor",
            {
                icon_size = 10,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        cultist_berzerker = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/presets/preset_01",
            ENEMY_RADAR_DEFAULT_DREG_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_berzerker",
            {
                icon_size = 10,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        renegade_berzerker = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/presets/preset_01",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_berzerker",
            {
                icon_size = 10,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        renegade_berzerker_gibbing_rotten_armor = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/presets/preset_01",
            ENEMY_RADAR_DEFAULT_MUTATOR_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_berzerker",
            {
                icon_size = 10,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        cultist_assault = _enemy_radar_def(
            "shooter",
            "content/ui/materials/icons/item_types/weapons",
            ENEMY_RADAR_DEFAULT_DREG_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_assault",
            {
                icon_size = 7,
                background_size = 24,
                bracket_size = 11,
            }
        ),
        cultist_shocktrooper = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/weapons/actions/shotgun",
            ENEMY_RADAR_DEFAULT_DREG_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_shocktrooper",
            {
                icon_size = 8,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        renegade_assault = _enemy_radar_def(
            "shooter",
            "content/ui/materials/icons/item_types/weapons",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_assault",
            {
                icon_size = 7,
                background_size = 24,
                bracket_size = 11,
            }
        ),
        renegade_rifleman = _enemy_radar_def(
            "shooter",
            "content/ui/materials/icons/item_types/ranged_weapons",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_rifleman",
            {
                icon_size = 7,
                background_size = 24,
                bracket_size = 11,
            }
        ),
        renegade_shocktrooper = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/weapons/actions/shotgun",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_shocktrooper",
            {
                icon_size = 8,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        renegade_sniper = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/presets/preset_14",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_sniper",
            {
                icon_size = 12,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        cultist_flamer = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/presets/preset_20",
            ENEMY_RADAR_DEFAULT_TOX_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_flamer",
            {
                icon_size = 12,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        renegade_flamer = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/presets/preset_20",
            { 255, 255, 102, 0 },
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_flamer",
            {
                icon_size = 12,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        renegade_flamer_mutator = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/presets/preset_20",
            ENEMY_RADAR_DEFAULT_MUTATOR_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_flamer",
            {
                icon_size = 12,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        cultist_mutant = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/weapons/actions/melee_hand",
            ENEMY_RADAR_DEFAULT_DREG_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_mutant",
            {
                icon_size = 10,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        cultist_mutant_mutator = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/weapons/actions/melee_hand",
            ENEMY_RADAR_DEFAULT_MUTATOR_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_mutant",
            {
                icon_size = 10,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        chaos_ogryn_executor = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/difficulty/flat/difficulty_skull_auric",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_chaos_ogryn_executor",
            {
                icon_size = 12,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        chaos_ogryn_executor_gibbing_rotten_armor = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/difficulty/flat/difficulty_skull_auric",
            ENEMY_RADAR_DEFAULT_MUTATOR_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_chaos_ogryn_executor",
            {
                icon_size = 12,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        chaos_ogryn_bulwark = _enemy_radar_def(
            "elite",
            "content/ui/materials/icons/weapons/actions/defence",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_chaos_ogryn_bulwark",
            {
                icon_size = 8,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        renegade_netgunner = _enemy_radar_def(
            "special",
            "content/ui/materials/icons/presets/preset_17",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_netgunner",
            {
                icon_size = 12,
                background_size = 36,
                bracket_size = 15,
            }
        ),
        chaos_lesser_mutated_poxwalker = _enemy_radar_def(
            "horde",
            "content/ui/materials/hud/interactions/icons/default",
            ENEMY_RADAR_DEFAULT_COLOR,
            nil,
            "show_enemy_horde",
            {
                icon_size = 8,
            }
        ),
        chaos_mutated_poxwalker = _enemy_radar_def(
            "horde",
            "content/ui/materials/hud/interactions/icons/default",
            ENEMY_RADAR_DEFAULT_COLOR,
            nil,
            "show_enemy_horde",
            {
                icon_size = 8,
            }
        ),
        chaos_mutator_ritualist = _enemy_radar_def(
            "misc",
            "content/ui/materials/hud/interactions/icons/enemy",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_ritualist",
            {
                priority_group = "misc",
                icon_size = 10,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        cultist_ritualist = _enemy_radar_def(
            "misc",
            "content/ui/materials/hud/interactions/icons/enemy",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_ritualist",
            {
                priority_group = "misc",
                icon_size = 10,
                background_size = 30,
                bracket_size = 13,
            }
        ),
        chaos_newly_infected = _enemy_radar_def(
            "horde",
            "content/ui/materials/hud/interactions/icons/default",
            ENEMY_RADAR_DEFAULT_COLOR,
            nil,
            "show_enemy_horde",
            {
                icon_size = 8,
            }
        ),
        chaos_poxwalker = _enemy_radar_def(
            "horde",
            "content/ui/materials/hud/interactions/icons/default",
            ENEMY_RADAR_DEFAULT_COLOR,
            nil,
            "show_enemy_horde",
            {
                icon_size = 8,
            }
        ),
        cultist_melee = _enemy_radar_def(
            "common",
            "content/ui/materials/hud/interactions/icons/default",
            ENEMY_RADAR_DEFAULT_DREG_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_melee",
            {
                icon_size = 8,
                background_size = 16,
                bracket_size = 9,
            }
        ),
        renegade_melee = _enemy_radar_def(
            "common",
            "content/ui/materials/hud/interactions/icons/default",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_melee",
            {
                icon_size = 8,
                background_size = 16,
                bracket_size = 9,
            }
        ),
        chaos_armored_infected = _enemy_radar_def(
            "horde",
            "content/ui/materials/hud/interactions/icons/default",
            ENEMY_RADAR_DEFAULT_COLOR,
            nil,
            "show_enemy_horde",
            {
                icon_size = 8,
            }
        ),
    }

    ENEMY_RADAR_DEFINITION_BY_KIND = {}
    ENEMY_RADAR_SETTING_BY_KIND = {}

    for breed_name, definition in pairs(ENEMY_RADAR_DEFINITIONS_BY_BREED) do
        local kind = "enemy_" .. breed_name

        definition.breed_name = breed_name
        definition.kind = kind

        ENEMY_RADAR_DEFINITION_BY_KIND[kind] = definition
        ENEMY_RADAR_SETTING_BY_KIND[kind] = definition.setting_id
        KIND_TO_SETTING[kind] = definition.setting_id
    end


    RADAR_GAME_MODE_SETTING_BY_ID = {
        regular_missions = "enable_in_regular_missions",
        havoc = "enable_in_havoc",
        mortis_trials = "enable_in_mortis_trials",
        expeditions = "enable_in_expeditions",
    }

    ARTWORK_MODE_SETTING_IDS = {
        "show_crates",
        "show_diamantine",
        "show_plasteel",
        "show_expeditions_currency",
        "show_expeditions_loot",
        "show_expeditions_dropped_loot",
        "show_pocketable_airstrike",
        "show_pocketable_artillery_strike",
        "show_pocketable_big_grenade",
        "show_pocketable_valkyrie_hover",
        "show_pocketable_landmine_explosive",
        "show_pocketable_landmine_fire",
        "show_pocketable_landmine_shock",
        "show_pocketable_void_shield",
    }

    EXPEDITION_MARKER_DISPLAY_MODE_SETTING_IDS = {
        "show_expedition_objective_opportunity",
        "show_expedition_objective_transition",
        "show_expedition_objective_main_objective",
        "show_expedition_objective_extraction",
        "show_expedition_objective_arrival",
        "show_expedition_loot_converter",
    }

    EXPEDITION_LOOT_VALUE_BY_PICKUP_NAME = {
        expedition_loot_small_tier_1 = 10,
        expedition_loot_small_tier_2 = 25,
        expedition_loot_small_tier_3 = 50,
    }


    NEARBY_HIGHLIGHT_SETTING_BY_GROUP = {
        common_pickups_group = "nearby_highlight_common_pickups",
        materials_group = "nearby_highlight_materials",
        primary_objective_group = "nearby_highlight_primary_objective",
        secondary_objective_group = "nearby_highlight_secondary_objective",
        expeditions_specific_group = "nearby_highlight_expeditions_specific",
        martyr_s_skull_group = "nearby_highlight_martyr_s_skull",
        environment_group = "nearby_highlight_environment",
        event_group = "nearby_highlight_event",
    }

    NEARBY_HIGHLIGHT_DISTANCE_TEXT_SETTING_BY_GROUP = {
        common_pickups_group = "nearby_highlight_distance_text_common_pickups",
        materials_group = "nearby_highlight_distance_text_materials",
        primary_objective_group = "nearby_highlight_distance_text_primary_objective",
        secondary_objective_group = "nearby_highlight_distance_text_secondary_objective",
        expeditions_specific_group = "nearby_highlight_distance_text_expeditions_specific",
        martyr_s_skull_group = "nearby_highlight_distance_text_martyr_s_skull",
        environment_group = "nearby_highlight_distance_text_environment",
        event_group = "nearby_highlight_distance_text_event",
    }

    DEFAULT_COLOR_ARRAY_WHITE = { 255, 255, 255, 255 }

    EXACT_PICKUP_KIND_BY_NAME = {
        small_clip = "pickup_ammo_small",
        large_clip = "pickup_ammo_big",
        small_grenade = "pickup_grenade",
        small_metal = "material_plasteel",
        large_metal = "material_plasteel",
        small_platinum = "material_diamantine",
        large_platinum = "material_diamantine",
        ammo_cache_pocketable = "pocketable_ammo_crate",
        medical_crate_pocketable = "pocketable_medical_crate",
        syringe_ability_boost_pocketable = "pocketable_syringe_ability",
        syringe_corruption_pocketable = "pocketable_syringe_corruption",
        syringe_power_boost_pocketable = "pocketable_syringe_power",
        syringe_speed_boost_pocketable = "pocketable_syringe_speed",
        battery_01_luggable = "luggable_power_cell_teal",
        control_rod_01_luggable = "luggable_cryonic_rod",
        container_01_luggable = "luggable_moebian_pox_zetaphyte_13_sample",
        container_02_luggable = "luggable_vacuum_capsule",
        container_03_luggable = "luggable_special_issue_ammo",
        prismata_case_01_luggable = "luggable_prismata_crystal_repository",
        hordes_mcguffin = "pickup_mortis_relic",
        grimoire = "pocketable_grimoire",
        tome = "pocketable_scripture",
        expedition_loot_player_drop = "material_expeditions_loot_player_drop",
        large_ammunition_crate = "pickup_large_ammunition_crate",
        expedition_deployable_force_field_pocketable = "pocketable_void_shield",
        expedition_grenade_airstrike_pocketable = "pocketable_airstrike",
        expedition_grenade_artillery_strike_pocketable = "pocketable_artillery_strike",
        expedition_grenade_big_pocketable = "pocketable_big_grenade",
        expedition_grenade_valkyrie_hover_pocketable = "pocketable_valkyrie_hover",
        motion_detection_mine_explosive_pocketable = "pocketable_landmine_explosive",
        motion_detection_mine_fire_pocketable = "pocketable_landmine_fire",
        motion_detection_mine_shock_pocketable = "pocketable_landmine_shock",
        expedition_loot_heavy_tier_1 = "luggable_data_reliquary",
        expedition_loot_heavy_tier_2 = "luggable_data_reliquary",
        expedition_loot_heavy_tier_3 = "luggable_data_reliquary",
        expedition_explosive_luggable_01 = "luggable_promethium_barrel",
        expedition_time_syringe_timed = "pocketable_anti_rad_stimm",
        collectible_01_pickup = "pickup_martyr_skull",
        battery_02_luggable = "luggable_power_cell_orange",
        ammo_cache_deployable = "pickup_ammo_cache_deployable",
        medical_crate_deployable = "medical_crate_deployable",
        skulls_01_pickup = "pickup_tainted_skull",
        communications_hack_device = "pocketable_corrupted_auspex_scanner",
        stolen_rations_01_pickup_small = "pickup_stolen_rations",
        stolen_rations_01_pickup_medium = "pickup_stolen_rations",
    }

    PAPER_PICKUP_NAMES = {
        paper_pickup = true,
        paper_pickup_02 = true,
        paper_pickup_03 = true,
        paper_pickup_04 = true,
    }

    SAINTS_PICKUP_NAMES = {
        live_event_saints_01_pickup_small = true,
        live_event_saints_01_pickup_medium = true,
        live_event_saints_01_pickup_large = true,
        consumable = true,
    }

    local function _normalize_marker_display_mode(value)
        if value == false or value == "off" then
            return "off"
        end

        if value == "icon" then
            return "icon"
        end

        return "artwork"
    end

    local function _normalize_expedition_marker_display_mode(value, default_value)
        if value == "icon_only" or value == "icon_distance" or value == "off" then
            return value
        end

        if value == false then
            return "off"
        end

        if value == true then
            return "icon_only"
        end

        return default_value or "icon_only"
    end

    local function _normalize_enemy_marker_display_mode(value)
        if value == false or value == "off" then
            return "off"
        end

        if value == "marked_icon" then
            return "marked_icon"
        end

        return "icon_only"
    end

    local function _normalize_player_display_style(value)
        if value == "icon_only" or value == "marked_icon" or value == "dot_only" or value == "marked_dot" then
            return value
        end

        return "marked_icon"
    end

    function mod:get_marker_scale_group(kind)
        if not kind then
            return nil
        end

        if string_sub(tostring(kind), 1, 6) == "enemy_" then
            return "enemies_group"
        end

        return MARKER_SCALE_GROUP_BY_KIND[kind]
    end

    function mod:is_event_marker_kind(kind)
        return kind ~= nil and MARKER_SCALE_GROUP_BY_KIND[kind] == "event_group"
    end

    local function _percent_scale_from_setting(self, setting_id)
        if not setting_id then
            return 1
        end

        local value = tonumber(self:get(setting_id)) or 100

        if value < 50 then
            value = 50
        elseif value > 300 then
            value = 300
        end

        return value / 100
    end

    function mod:get_marker_scale_factor(group_name)
        local setting_id = ICON_SCALE_SETTING_BY_GROUP[group_name]

        return _percent_scale_from_setting(self, setting_id)
    end

    function mod:get_enemy_radar_definition(kind_or_breed)
        if not kind_or_breed then
            return nil
        end

        return ENEMY_RADAR_DEFINITION_BY_KIND[kind_or_breed] or ENEMY_RADAR_DEFINITIONS_BY_BREED[kind_or_breed]
    end

    function mod:show_enemy_vertical_arrows(kind_or_breed)
        local direct_setting_id = rawget(ENEMY_RADAR_VERTICAL_ARROW_SETTING_BY_KIND, kind_or_breed)

        if direct_setting_id ~= nil then
            return self:get(direct_setting_id) == true
        end

        local definition = self:get_enemy_radar_definition(kind_or_breed)

        if not definition then
            return false
        end

        local category = definition.category
        local setting_id = category and rawget(ENEMY_RADAR_VERTICAL_ARROW_SETTING_BY_CATEGORY, category) or nil

        return setting_id ~= nil and self:get(setting_id) == true
    end

    function mod:get_enemy_marker_mode(kind)
        local setting_id = ENEMY_RADAR_SETTING_BY_KIND[kind]

        if not setting_id then
            return nil
        end

        local value = self:get(setting_id)

        if setting_id == "show_enemy_horde" then
            if value == true or value == "icon" or value == "icon_only" or value == "marked_icon" then
                return "icon_only"
            end

            return "off"
        end

        return _normalize_enemy_marker_display_mode(value)
    end

    function mod:get_enemy_category_scale_factor(kind_or_breed)
        local direct_setting_id = rawget(ENEMY_RADAR_SCALE_SETTING_BY_KIND, kind_or_breed)

        if direct_setting_id ~= nil then
            return _percent_scale_from_setting(self, direct_setting_id)
        end

        local definition = self:get_enemy_radar_definition(kind_or_breed)

        if not definition then
            return 1
        end

        local category = definition.scale_category or definition.category
        local setting_id = category and ENEMY_RADAR_SCALE_SETTING_BY_CATEGORY[category] or nil

        return _percent_scale_from_setting(self, setting_id)
    end

    function mod:get_target_selection_priority(kind)
        if self:is_event_marker_kind(kind) then
            return EVENT_MARKER_SELECTION_PRIORITY
        end

        if kind == "material_expeditions_loot_player_drop" then
            return EXPEDITION_PLAYER_DROP_SELECTION_PRIORITY
        end

        if kind == "location_attention" or kind == "location_ping" or kind == "location_threat" then
            return PLAYER_SMART_TAG_SELECTION_PRIORITY
        end

        if kind == "enemy_daemonhost"
            or kind == "enemy_monstrosity"
            or kind == "enemy_captain"
            or kind == "enemy_karnak_twin" then
            return ENEMY_RADAR_SELECTION_PRIORITY.boss
        end

        local definition = rawget(ENEMY_RADAR_DEFINITION_BY_KIND, kind)

        if definition ~= nil then
            return ENEMY_RADAR_SELECTION_PRIORITY[definition.priority_group] or 0
        end

        return 0
    end

    function mod:get_target_render_layer(kind)
        if self:is_event_marker_kind(kind) then
            return EVENT_MARKER_RENDER_LAYER
        end

        if kind == "material_expeditions_loot_player_drop" then
            return EXPEDITION_PLAYER_DROP_RENDER_LAYER
        end

        if kind == "location_attention" or kind == "location_ping" or kind == "location_threat" then
            return PLAYER_SMART_TAG_RENDER_LAYER
        end

        if kind == "enemy_daemonhost"
            or kind == "enemy_monstrosity"
            or kind == "enemy_captain"
            or kind == "enemy_karnak_twin" then
            return ENEMY_RADAR_RENDER_LAYER.boss
        end

        local definition = rawget(ENEMY_RADAR_DEFINITION_BY_KIND, kind)

        if definition ~= nil then
            return ENEMY_RADAR_RENDER_LAYER[definition.priority_group] or 0
        end

        return 0
    end

    function mod:get_marker_display_mode(kind)
        local setting_id = ARTWORK_MODE_KIND_TO_SETTING[kind]
        if not setting_id then
            return nil
        end

        return _normalize_marker_display_mode(mod:get(setting_id))
    end

    function mod:get_expedition_marker_display_mode(kind)
        local setting_id = EXPEDITION_MARKER_DISPLAY_MODE_KIND_TO_SETTING[kind]
        if not setting_id then
            return nil
        end

        return _normalize_expedition_marker_display_mode(
            mod:get(setting_id),
            EXPEDITION_MARKER_DISPLAY_MODE_DEFAULT_BY_SETTING[setting_id]
        )
    end

    local function _migrate_marker_display_mode_settings()
        local mod_get = mod.get
        local mod_set = mod.set

        for i = 1, #ARTWORK_MODE_SETTING_IDS do
            local setting_id = ARTWORK_MODE_SETTING_IDS[i]
            local value = mod_get(mod, setting_id)

            if value == true then
                mod_set(mod, setting_id, "artwork")
            elseif value == false then
                mod_set(mod, setting_id, "off")
            end
        end
    end

    local function _migrate_expedition_marker_display_mode_settings()
        local mod_get = mod.get
        local mod_set = mod.set

        for i = 1, #EXPEDITION_MARKER_DISPLAY_MODE_SETTING_IDS do
            local setting_id = EXPEDITION_MARKER_DISPLAY_MODE_SETTING_IDS[i]
            local value = mod_get(mod, setting_id)

            if value == true then
                mod_set(mod, setting_id, "icon_only")
            elseif value == false then
                mod_set(mod, setting_id, "off")
            end
        end
    end

    local function _migrate_split_enemy_category_settings()
        local mod_get = mod.get
        local mod_set = mod.set
        local migrations = {
            {
                legacy_setting_id = "show_enemy_common",
                setting_ids = {
                    "show_enemy_cultist_melee",
                    "show_enemy_renegade_melee",
                },
            },
            {
                legacy_setting_id = "show_enemy_shooter",
                setting_ids = {
                    "show_enemy_cultist_assault",
                    "show_enemy_renegade_assault",
                    "show_enemy_renegade_rifleman",
                },
            },
        }

        for i = 1, #migrations do
            local migration = migrations[i]
            local legacy_value = mod_get(mod, migration.legacy_setting_id)

            if legacy_value ~= nil then
                local migrated_value = _normalize_enemy_marker_display_mode(legacy_value)
                local setting_ids = migration.setting_ids

                for j = 1, #setting_ids do
                    local setting_id = setting_ids[j]

                    if mod_get(mod, setting_id) == nil then
                        mod_set(mod, setting_id, migrated_value)
                    end
                end
            end
        end
    end

    local function _migrate_player_visibility_settings()
        if mod:get("show_players") ~= nil then
            return
        end

        local legacy_value = mod:get("show_teammates")
        if legacy_value ~= nil then
            mod:set("show_players", legacy_value == false and "off" or
                _normalize_player_display_style(mod:get("player_display_style")))
        end
    end

    function mod.on_all_mods_loaded()
        if mod.migrate_marker_enabled_dropdown_settings then
            mod:migrate_marker_enabled_dropdown_settings()
        end

        _migrate_marker_display_mode_settings()
        _migrate_expedition_marker_display_mode_settings()
        _migrate_split_enemy_category_settings()
        _migrate_player_visibility_settings()
        if mod.migrate_radar_color_settings then
            mod:migrate_radar_color_settings()
        end

        local debug_mode = mod:get("debug_mode") == true

        -- Preload icon packages
        local function load_package(package_name)
            local ok, err = pcall(function()
                local managers = Managers
                local package_manager = managers and managers.package

                if not package_manager then
                    error("Managers.package unavailable")
                end

                if not package_manager:has_loaded(package_name) then
                    package_manager:load(package_name, "Radar", nil, true)
                    if debug_mode then
                        mod:info(string_format("[Radar] package load requested | %s", tostring(package_name)))
                    end
                else
                    if debug_mode then
                        mod:info(string_format("[Radar] package already loaded | %s", tostring(package_name)))
                    end
                end
            end)

            if not ok and debug_mode then
                mod:error(string_format("[Radar] package load failed | %s | %s", tostring(package_name), tostring(err)))
            end
        end

        load_package("packages/ui/views/inventory_view/inventory_view")
        load_package("packages/ui/views/inventory_weapons_view/inventory_weapons_view")
        load_package("packages/ui/hud/player_weapon/player_weapon")
        load_package("packages/ui/views/inventory_background_view/inventory_background_view")
        load_package("packages/ui/views/inventory_weapon_details_view/inventory_weapon_details_view")
        load_package("packages/ui/views/inventory_weapon_marks_view/inventory_weapon_marks_view")
        load_package("packages/ui/views/main_menu_view/main_menu_view")
        load_package("packages/ui/views/player_character_options_view/player_character_options_view")
        load_package("packages/ui/views/talent_builder_view/talent_builder_view")
        load_package("packages/ui/views/live_events_view/live_events_view")
        load_package("packages/ui/views/group_finder_view/group_finder_view")
        load_package("packages/ui/views/mission_board_view/mission_board_view")
        load_package("packages/ui/views/scanner_display_view/scanner_display_view")
        load_package("packages/ui/material_sets/circumstances")
        load_package("packages/ui/views/crafting_view/crafting_view")
        load_package("packages/ui/views/penance_overview_view/penance_overview_view")
        load_package("packages/ui/views/expedition_play_view/expedition_play_view")

        if debug_mode then
            mod:info("Packages loaded")
        end
    end
end
