--- Marker kind registry, enemy radar definitions and the enemy scan.
-- Declares the static tables every other runtime module reads to turn a marker kind into
-- settings, icon scale, display mode, highlight colour, selection priority and render
-- layer, and defines per enemy breed how it is drawn on the radar. It also classifies and
-- tracks live enemies, migrates settings from older versions and preloads the UI packages
-- that hold Radar's icons.
--
-- Installer module, installed first into Radar's shared runtime environment (see
-- `Radar.lua`), so its upper-case tables exist before any other module installs. It
-- installs the colour runtime from `Radar_color_settings.lua`.
--
-- Contributes to `shared_env` the registries (`KIND_TO_SETTING`, `EXPEDITION_*`,
-- `ARTWORK_MODE_*`, `NEARBY_*`, `ENEMY_RADAR_*`, `RADAR_GAME_MODE_SETTING_BY_ID`,
-- `SCAN_INTERVAL`), `_classify_enemy_from_breed` and `_scan_minions`, and the display mode,
-- scale and priority `mod` methods. `_scan_minions` relies at call time on tracking
-- (`_track_unit`, `_kind_enabled`), player (`_marked_by_player_slot_for_unit`,
-- `_supported_ability_marker_state_for_unit`) and runtime helper functions installed later.
-- module: Radar_enemy_definitions
-- author: LucLeto
return function(env)
    setfenv(1, env)

    local mod = mod

    local pcall = pcall
    local pairs = pairs
    local tonumber = tonumber
    local tostring = tostring
    local rawget = rawget
    local string_find = string.find
    local string_lower = string.lower
    local string_sub = string.sub
    local RadarColorSettings = mod:io_dofile("Radar/scripts/mods/Radar/Radar_color_settings")

    local table_clear = table.clear or function(t)
        for k in pairs(t) do
            t[k] = nil
        end
    end

    RadarColorSettings.install_runtime(mod)

    --- Base scan interval in seconds; `Radar_tracking.lua` derives its scan tiers from it.
    SCAN_INTERVAL = 0.25

    --- RGB multiplier applied to a nearby highlight bracket whose target is hidden behind geometry.
    NEARBY_OUTLINE_OCCLUDED_MULTIPLIER = 0.6

    --- Marker kinds that have a default nearby highlight colour.
    local NEARBY_OUTLINE_KINDS = {
        "material_diamantine",
        "material_plasteel",
        "crate_unknown",
        "pickup_ammo",
        "pickup_ammo_small",
        "pickup_ammo_big",
        "pickup_grenade",
        "pocketable_ammo_crate",
        "pocketable_medical_crate",
        "pocketable_syringe_ability",
        "pocketable_syringe_corruption",
        "pocketable_syringe_power",
        "pocketable_syringe_speed",
        "luggable_power_cell_teal",
        "luggable_cryonic_rod",
        "luggable_moebian_pox_zetaphyte_13_sample",
        "luggable_vacuum_capsule",
        "luggable_special_issue_ammo",
        "luggable_prismata_crystal_repository",
        "pickup_mortis_relic",
        "pickup_coordinates_paper",
        "pocketable_grimoire",
        "pocketable_scripture",
        "material_expeditions_currency",
        "material_expeditions_loot",
        "material_expeditions_loot_player_drop",
        "luggable_data_reliquary",
        "pickup_large_ammunition_crate",
        "luggable_promethium_barrel",
        "hazard_explosive_barrel",
        "hazard_fire_barrel",
        "pocketable_anti_rad_stimm",
        "pocketable_airstrike",
        "pocketable_artillery_strike",
        "pocketable_big_grenade",
        "pocketable_landmine_explosive",
        "pocketable_landmine_fire",
        "pocketable_landmine_shock",
        "pocketable_valkyrie_hover",
        "pocketable_void_shield",
        "pickup_martyr_skull",
        "martyr_skull_riddle_interactable",
        "mission_objective_scanner",
        "mission_objective_hacking",
        "mission_objective_servo_skull",
        "mission_objective_other",
        "mission_objective_growth",
        "mission_objective_destroy",
        "luggable_power_cell_orange",
        "medicae_station",
        "luggable_socket",
        "pickup_heretic_idol",
        "pickup_tainted_skull",
        "dark_rites_totem",
        "dark_rites_servo_skull",
        "pocketable_corrupted_auspex_scanner",
        "pickup_saints",
        "pickup_leftover",
        "pickup_stolen_rations",
    }

    --- Default highlight colour per marker kind.
    -- Read from the colour registry, so each default is written down in one place only.
    NEARBY_OUTLINE_COLOR_BY_KIND = {}

    for i = 1, #NEARBY_OUTLINE_KINDS do
        local kind = NEARBY_OUTLINE_KINDS[i]

        NEARBY_OUTLINE_COLOR_BY_KIND[kind] = RadarColorSettings.default_highlight_color(kind)
    end

    --- Boss breed sets, matched by exact name before the name patterns in `_classify_enemy_from_breed`.
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

    --- Visibility setting of each marker kind; the enemy kinds are added from their definitions below.
    KIND_TO_SETTING = {
        pickup_ammo = "show_ammo_small",
        pickup_ammo_small = "show_ammo_small",
        pickup_ammo_big = "show_ammo_big",
        pickup_grenade = "show_grenades",
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
        player_companion_dog = "show_cyber_mastiff",
        player_companion_servo_skull = "show_servo_skulls",
        location_attention = "show_player_tags",
        location_ping = "show_player_tags",
        location_threat = "show_player_tags",
        martyr_skull_riddle_interactable = "show_martyr_skull_riddle_interactables",
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
        hazard_explosive_barrel = "show_explosive_barrels",
        hazard_fire_barrel = "show_fire_barrels",
        pocketable_anti_rad_stimm = "show_anti_rad_stimm",
        pocketable_ammo_crate = "show_pocketable_ammo_crate",
        pocketable_corrupted_auspex_scanner = "show_pocketable_corrupted_auspex_scanner",
        pocketable_expedition_loot_crate = "show_pocketable_expedition_loot_crate",
        pickup_saints = "show_saints",
        pickup_leftover = "show_leftover",
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

    --- Expedition location marker kinds, the icon / icon and distance / off dropdown of each, and the dropdown defaults.
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

    --- Other kinds using an icon / icon and distance / off dropdown, and the dropdown defaults.
    local ICON_DISTANCE_MARKER_DISPLAY_MODE_KIND_TO_SETTING = {
        hazard_explosive_barrel = "show_explosive_barrels",
        hazard_fire_barrel = "show_fire_barrels",
        mission_objective_scanner = "show_mission_objective_scanner",
        mission_objective_hacking = "show_mission_objective_hacking",
        mission_objective_servo_skull = "show_mission_objective_servo_skull",
        mission_objective_other = "show_mission_objective_other",
        mission_objective_growth = "show_mission_objective_growth",
        mission_objective_destroy = "show_mission_objective_destroy",
    }

    local ICON_DISTANCE_MARKER_DISPLAY_MODE_DEFAULT_BY_SETTING = {
        show_explosive_barrels = "icon_only",
        show_fire_barrels = "icon_only",
        show_mission_objective_scanner = "icon_only",
        show_mission_objective_hacking = "icon_only",
        show_mission_objective_servo_skull = "icon_only",
        show_mission_objective_other = "icon_only",
        show_mission_objective_growth = "icon_only",
        show_mission_objective_destroy = "icon_only",
    }

    --- Icon of each Expedition location marker kind when the game provides none.
    EXPEDITION_OBJECTIVE_ICON_DEFAULTS = {
        expedition_loot_converter = "content/ui/materials/hud/interactions/icons/expeditions",
        expedition_objective_transition = "content/ui/materials/backgrounds/scanner/scanner_map_exit",
        expedition_objective_main_objective = "content/ui/materials/hud/interactions/icons/objective_main",
        expedition_objective_extraction = "content/ui/materials/backgrounds/scanner/scanner_map_extract",
        expedition_objective_arrival = "content/ui/materials/icons/mission_types/mission_type_05",
    }

    --- Kinds using an artwork / icon / off dropdown, and dropdowns with an explicit default.
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
        pickup_tainted_skull = "show_tainted_skull",
        pickup_saints = "show_saints",
        pickup_leftover = "show_leftover",
    }

    local ARTWORK_MODE_DEFAULT_BY_SETTING = {
        show_tainted_skull = "artwork",
        show_saints = "artwork",
        show_leftover = "artwork",
    }

    --- Settings group of each non-enemy marker kind.
    -- The group selects the icon scale slider and the nearby highlight settings, and
    -- `event_group` marks live event kinds. Every `enemy_` kind belongs to `enemies_group`.
    local MARKER_SCALE_GROUP_BY_KIND = {
        crate_unknown = "common_pickups_group",
        pickup_ammo = "common_pickups_group",
        pickup_ammo_small = "common_pickups_group",
        pickup_ammo_big = "common_pickups_group",
        pickup_grenade = "common_pickups_group",
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
        mission_objective_scanner = "mission_objective_group",
        mission_objective_hacking = "mission_objective_group",
        mission_objective_servo_skull = "mission_objective_group",
        mission_objective_other = "mission_objective_group",
        mission_objective_growth = "mission_objective_group",
        mission_objective_destroy = "mission_objective_group",
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
        martyr_skull_riddle_interactable = "martyr_s_skull_group",
        luggable_power_cell_orange = "martyr_s_skull_group",
        medicae_station = "environment_group",
        luggable_socket = "environment_group",
        pickup_heretic_idol = "environment_group",
        hazard_explosive_barrel = "environment_group",
        hazard_fire_barrel = "environment_group",
        pickup_ammo_cache_deployable = "deployables_group",
        medical_crate_deployable = "deployables_group",
        player_teammate = "players_group",
        player_companion_dog = "player_companions_group",
        player_companion_servo_skull = "player_companions_group",
        location_attention = "players_group",
        location_ping = "players_group",
        location_threat = "players_group",
        pickup_tainted_skull = "event_group",
        dark_rites_totem = "event_group",
        dark_rites_servo_skull = "event_group",
        pocketable_corrupted_auspex_scanner = "event_group",
        pickup_saints = "event_group",
        pickup_leftover = "event_group",
        pickup_stolen_rations = "event_group",
        pickup_unknown = "debug_group",
    }

    --- Icon scale slider of each settings group.
    local ICON_SCALE_SETTING_BY_GROUP = {
        common_pickups_group = "common_pickups_icon_scale",
        materials_group = "materials_icon_scale",
        primary_objective_group = "primary_objective_icon_scale",
        secondary_objective_group = "secondary_objective_icon_scale",
        mission_objective_group = "mission_objective_icon_scale",
        expeditions_location_group = "expeditions_location_icon_scale",
        expeditions_specific_group = "expeditions_specific_icon_scale",
        martyr_s_skull_group = "martyr_s_skull_icon_scale",
        environment_group = "environment_icon_scale",
        deployables_group = "deployables_icon_scale",
        enemies_group = "enemies_icon_scale",
        players_group = "players_icon_scale",
        player_companions_group = "player_companions_icon_scale",
        event_group = "event_icon_scale",
        debug_group = "debug_icon_scale",
    }

    --- Boss kinds, which share one icon scale slider instead of their category's.
    local ENEMY_RADAR_SCALE_SETTING_BY_KIND = {
        enemy_daemonhost = "enemy_boss_icon_scale",
        enemy_monstrosity = "enemy_boss_icon_scale",
        enemy_captain = "enemy_boss_icon_scale",
        enemy_karnak_twin = "enemy_boss_icon_scale",
    }

    --- Default enemy icon and background colours, copied from the colour registry for the definitions below.
    local ENEMY_RADAR_DEFAULT_COLOR = RadarColorSettings.default_color("enemy_background_marker")
    local ENEMY_RADAR_DEFAULT_HORDE_COLOR = RadarColorSettings.default_color("enemy_horde_marker")
    local ENEMY_RADAR_DEFAULT_DREG_COLOR = RadarColorSettings.default_color("enemy_dreg_marker")
    local ENEMY_RADAR_DEFAULT_SCAB_COLOR = RadarColorSettings.default_color("enemy_scab_marker")
    local ENEMY_RADAR_DEFAULT_TOX_COLOR = RadarColorSettings.default_color("enemy_tox_marker")
    local ENEMY_RADAR_DEFAULT_MUTATOR_COLOR = RadarColorSettings.default_color("enemy_mutator_marker")
    local ENEMY_RADAR_DEFAULT_ARMORED_HOUND_COLOR = RadarColorSettings.default_color("enemy_armored_hound_marker")
    local ENEMY_RADAR_DEFAULT_RENEGADE_FLAMER_COLOR =
        RadarColorSettings.default_color("enemy_renegade_flamer_marker")

    local ENEMY_RADAR_BACKGROUND_ICON = "content/ui/materials/hud/interactions/icons/default"

    --- Shared visibility setting of the enemy categories whose definitions name no setting of their own.
    local ENEMY_RADAR_GROUP_SETTING_IDS = {
        shooter = "show_enemy_shooter",
        common = "show_enemy_common",
        horde = "show_enemy_horde",
    }

    --- Icon scale slider of each enemy category.
    local ENEMY_RADAR_SCALE_SETTING_BY_CATEGORY = {
        special = "enemy_special_icon_scale",
        elite = "enemy_elite_icon_scale",
        shooter = "enemy_shooter_icon_scale",
        common = "enemy_common_icon_scale",
        horde = "enemy_horde_icon_scale",
        misc = "enemy_misc_icon_scale",
    }

    --- Vertical arrow settings for the boss kinds and for each enemy category.
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

    --- Selection priority and render layer per enemy priority group and for other special kinds.
    -- Targets with a higher selection priority are drawn first when the radar sorts its
    -- targets, and so survive the marker limit; a higher render layer draws above lower ones.
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
    local PLAYER_TEAMMATE_RENDER_LAYER = 1
    local EVENT_MARKER_SELECTION_PRIORITY = 600
    local EVENT_MARKER_RENDER_LAYER = 7
    local EXPEDITION_PLAYER_DROP_SELECTION_PRIORITY = 650
    local EXPEDITION_PLAYER_DROP_RENDER_LAYER = 6

    --- Returns the default icon size in pixels of an enemy category.
    -- string: category enemy category
    -- treturn: int
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

    --- Returns the default background size in pixels of an enemy category.
    -- string: category enemy category
    -- treturn: ?int nil for hordes, which draw without a background
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

    --- Builds an enemy radar definition with category defaults.
    -- The marker, background and bracket sizes fall back to the category defaults unless
    -- `extra` sets them; without a background colour the definition has no background layer.
    -- string: category enemy category (`special`, `elite`, `shooter`, `common`, `horde`, `misc`)
    -- string: icon icon material
    -- tab: icon_color default icon colour
    -- ?tab: background_color default background colour, nil for no background
    -- ?string: setting_id visibility setting, the category's shared setting when nil
    -- ?tab: extra definition fields to keep; filled in and returned
    -- treturn: tab definition
    local function _enemy_radar_def(category, icon, icon_color, background_color, setting_id, extra)
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

    --- Radar definition of every supported enemy breed, keyed by breed name.
    -- Each definition holds the category, icon, colours, sizes and visibility setting of the
    -- breed's marker. Boss breeds are not listed here; they are classified by name.
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
            ENEMY_RADAR_DEFAULT_ARMORED_HOUND_COLOR,
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
                background_size = 28,
                bracket_size = 12,
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
                background_size = 28,
                bracket_size = 12,
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
                background_size = 28,
                bracket_size = 12,
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
            ENEMY_RADAR_DEFAULT_RENEGADE_FLAMER_COLOR,
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
            ENEMY_RADAR_DEFAULT_HORDE_COLOR,
            nil,
            "show_enemy_horde",
            {
                icon_size = 8,
            }
        ),
        chaos_mutated_poxwalker = _enemy_radar_def(
            "horde",
            "content/ui/materials/hud/interactions/icons/default",
            ENEMY_RADAR_DEFAULT_HORDE_COLOR,
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
            ENEMY_RADAR_DEFAULT_HORDE_COLOR,
            nil,
            "show_enemy_horde",
            {
                icon_size = 8,
            }
        ),
        chaos_poxwalker = _enemy_radar_def(
            "horde",
            "content/ui/materials/hud/interactions/icons/default",
            ENEMY_RADAR_DEFAULT_HORDE_COLOR,
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
                bracket_size = 8,
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
                bracket_size = 8,
            }
        ),
        cultist_vanguard = _enemy_radar_def(
            "common",
            "content/ui/materials/icons/presets/preset_04",
            ENEMY_RADAR_DEFAULT_DREG_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_cultist_vanguard",
            {
                icon_size = 10,
                background_size = 32,
                bracket_size = 14,
            }
        ),
        renegade_vanguard = _enemy_radar_def(
            "common",
            "content/ui/materials/icons/presets/preset_04",
            ENEMY_RADAR_DEFAULT_SCAB_COLOR,
            ENEMY_RADAR_DEFAULT_COLOR,
            "show_enemy_renegade_vanguard",
            {
                icon_size = 10,
                background_size = 32,
                bracket_size = 14,
            }
        ),
        chaos_armored_infected = _enemy_radar_def(
            "horde",
            "content/ui/materials/hud/interactions/icons/default",
            ENEMY_RADAR_DEFAULT_HORDE_COLOR,
            nil,
            "show_enemy_horde",
            {
                icon_size = 8,
            }
        ),
    }

    --- Enemy definitions and visibility settings keyed by marker kind (`enemy_<breed>`).
    -- Derived from the breed table, which also gains `breed_name` and `kind` on every definition.
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


    --- Setting that enables the radar in each supported game mode.
    RADAR_GAME_MODE_SETTING_BY_ID = {
        regular_missions = "enable_in_regular_missions",
        havoc = "enable_in_havoc",
        mortis_trials = "enable_in_mortis_trials",
        expeditions = "enable_in_expeditions",
    }

    --- Dropdown settings that were checkboxes in older versions, migrated on load.
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
        "show_tainted_skull",
        "show_saints",
        "show_leftover",
    }

    EXPEDITION_MARKER_DISPLAY_MODE_SETTING_IDS = {
        "show_expedition_objective_opportunity",
        "show_expedition_objective_transition",
        "show_expedition_objective_main_objective",
        "show_expedition_objective_extraction",
        "show_expedition_objective_arrival",
        "show_expedition_loot_converter",
    }


    --- Kinds the game already marks on screen.
    -- A radar marker is still useful for them, but a second highlight bracket around the same
    -- object is not, so they never get a nearby highlight.
    NEARBY_HIGHLIGHT_EXCLUDED_KINDS = {
        mission_objective_servo_skull = true,
    }

    --- Nearby highlight toggle, and the toggle for its distance text, of each settings group.
    NEARBY_HIGHLIGHT_SETTING_BY_GROUP = {
        common_pickups_group = "nearby_highlight_common_pickups",
        materials_group = "nearby_highlight_materials",
        primary_objective_group = "nearby_highlight_primary_objective",
        secondary_objective_group = "nearby_highlight_secondary_objective",
        mission_objective_group = "nearby_highlight_mission_objective",
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
        mission_objective_group = "nearby_highlight_distance_text_mission_objective",
        expeditions_specific_group = "nearby_highlight_distance_text_expeditions_specific",
        martyr_s_skull_group = "nearby_highlight_distance_text_martyr_s_skull",
        environment_group = "nearby_highlight_distance_text_environment",
        deployables_group = "nearby_highlight_distance_text_deployables",
        event_group = "nearby_highlight_distance_text_event",
    }

    --- Shared white ARGB colour used as a fallback; must not be modified.
    DEFAULT_COLOR_ARRAY_WHITE = { 255, 255, 255, 255 }

    --- Breeds whose rotten armour mutator variant has a definition of its own under the aliased name.
    local ROTTEN_ARMOR_BREED_ALIAS_BY_BASE_BREED = {
        chaos_ogryn_executor = "chaos_ogryn_executor_gibbing_rotten_armor",
        renegade_executor = "renegade_executor_gibbing_rotten_armor",
        renegade_berzerker = "renegade_berzerker_gibbing_rotten_armor",
    }
    --- Marker kind per breed name (`false` for breeds without one), and a per-scan kind enablement cache.
    local _enemy_kind_by_breed_cache = {}
    local _scratch_minion_kind_enabled_cache = {}

    --- Returns the breed name to classify a unit by, resolving rotten armour variants.
    -- The variant keeps its base breed name, so it is recognised by the `rotten_armor` keyword
    -- or the `mutator_rotten_armor` buff.
    -- !Unit: unit enemy unit
    -- string: breed_name breed name reported by the unit
    -- treturn: string
    local function _resolve_enemy_breed_name(unit, breed_name)
        local rotten_armor_breed_name = ROTTEN_ARMOR_BREED_ALIAS_BY_BASE_BREED[breed_name]

        if rotten_armor_breed_name
            and (_safe_unit_has_keyword(unit, "rotten_armor")
                or _safe_unit_has_buff_template(unit, "mutator_rotten_armor")) then
            return rotten_armor_breed_name
        end

        return breed_name
    end

    --- Returns the radar marker kind of an enemy breed.
    -- Daemonhosts, twins, captains and monstrosities are matched by name pattern so new
    -- variants of these bosses are covered; every other breed needs a definition. Results,
    -- including misses, are cached per breed name.
    -- ?string: breed_name breed name
    -- treturn: ?string marker kind, or nil for breeds the radar does not draw
    function _classify_enemy_from_breed(breed_name)
        local cache_key = breed_name or ""
        local cached = _enemy_kind_by_breed_cache[cache_key]

        if cached ~= nil then
            return cached or nil
        end

        local key = string_lower(cache_key)
        local kind = nil

        if key == "chaos_daemonhost" or key == "chaos_mutator_daemonhost" or string_find(key, "daemonhost", 1, true) then
            kind = "enemy_daemonhost"
        elseif TWIN_BREEDS[key] or string_find(key, "twin_captain", 1, true) then
            kind = "enemy_karnak_twin"
        elseif CAPTAIN_BREEDS[key] or string_find(key, "captain", 1, true) then
            kind = "enemy_captain"
        elseif MONSTROSITY_BREEDS[key]
            or string_find(key, "beast_of_nurgle", 1, true)
            or string_find(key, "plague_ogryn", 1, true)
            or string_find(key, "chaos_spawn", 1, true)
            or string_find(key, "houndmaster", 1, true) then
            kind = "enemy_monstrosity"
        else
            local definition = ENEMY_RADAR_DEFINITIONS_BY_BREED[key]

            if definition then
                kind = definition.kind
            end
        end

        _enemy_kind_by_breed_cache[cache_key] = kind or false

        return kind
    end

    --- Tracks every live enemy with a radar definition from the unit data system.
    -- An enemy is tracked while its kind is enabled or while an ability of the local player
    -- outlines it (when that option is on); otherwise it is removed from tracking. The meta
    -- records the breed, the player slot that tagged it (when only tagged enemies are shown)
    -- and the ability outline state.
    function _scan_minions()
        local unit_data_map = _safe_unit_to_extension_map("unit_data_system")
        if not unit_data_map then
            return
        end

        local track_enemy_tags = mod:get_show_only_tagged_enemies()
        local show_ability_marked_enemies = mod:get_show_ability_marked_enemies()
        local outline_extension_map = show_ability_marked_enemies and _safe_outline_extension_data_map() or nil
        local local_player_unit = show_ability_marked_enemies and _player_unit() or nil
        local local_combat_ability_name = show_ability_marked_enemies
            and _safe_unit_ability_name(local_player_unit, "combat_ability")
            or nil
        local kind_enabled_cache = _scratch_minion_kind_enabled_cache
        table_clear(kind_enabled_cache)

        for unit, extension in pairs(unit_data_map) do
            if _safe_unit_alive(unit) and extension then
                local breed_name_fn = extension.breed_name

                if breed_name_fn then
                    local ok_breed, breed_name = pcall(breed_name_fn, extension)

                    if ok_breed and breed_name then
                        local resolved_breed_name = _resolve_enemy_breed_name(unit, breed_name)
                        local kind = _classify_enemy_from_breed(resolved_breed_name)
                        if kind and _is_trackable_unit_alive(unit, kind) then
                            local kind_enabled = kind_enabled_cache[kind]

                            if kind_enabled == nil then
                                kind_enabled = _kind_enabled(kind)
                                kind_enabled_cache[kind] = kind_enabled
                            end

                            local ability_marker_names = nil
                            local ability_marker_bracket_color = nil

                            if show_ability_marked_enemies then
                                ability_marker_names,
                                ability_marker_bracket_color = _supported_ability_marker_state_for_unit(
                                        unit,
                                        outline_extension_map,
                                        local_player_unit,
                                        local_combat_ability_name
                                    )
                            end

                            if kind_enabled or ability_marker_names ~= nil then
                                _track_unit(unit, kind, "unit_data_system", {
                                    breed_name = breed_name,
                                    marked_by_player_slot = track_enemy_tags and _marked_by_player_slot_for_unit(unit) or nil,
                                    ability_marked = ability_marker_names ~= nil,
                                    ability_outline_bracket_color = ability_marker_bracket_color,
                                })
                            else
                                _clear_tracked_unit_from_source(unit, "unit_data_system")
                            end
                        end
                    end
                end
            end
        end
    end

    --- Normalises an artwork dropdown value, including legacy checkbox values.
    -- param: value setting value
    -- ?string: default_value mode used for unset or `true`, `artwork` when nil
    -- treturn: string `artwork`, `icon` or `off`
    local function _normalize_marker_display_mode(value, default_value)
        if value == nil then
            return default_value or "artwork"
        end

        if value == false or value == "off" then
            return "off"
        end

        if value == "icon" then
            return "icon"
        end

        if value == true then
            return default_value or "artwork"
        end

        return "artwork"
    end

    --- Normalises an icon / icon and distance / off dropdown value, including legacy checkbox values.
    -- param: value setting value
    -- ?string: default_value mode used for unknown values, `icon_only` when nil
    -- treturn: string `icon_only`, `icon_distance` or `off`
    local function _normalize_expedition_marker_display_mode(value, default_value)
        if value == "icon_only" or value == "icon_distance" or value == "off" then
            return value
        end

        if value == "icon" then
            return "icon_only"
        end

        if value == false then
            return "off"
        end

        if value == true then
            return "icon_only"
        end

        return default_value or "icon_only"
    end

    --- Normalises an enemy dropdown value, including legacy checkbox values.
    -- treturn: string `icon_only`, `marked_icon` or `off`
    local function _normalize_enemy_marker_display_mode(value)
        if value == false or value == "off" then
            return "off"
        end

        if value == "marked_icon" then
            return "marked_icon"
        end

        return "icon_only"
    end

    --- Normalises a player marker style, defaulting to `marked_icon`.
    -- treturn: string `icon_only`, `marked_icon`, `dot_only` or `marked_dot`
    local function _normalize_player_display_style(value)
        if value == "icon_only" or value == "marked_icon" or value == "dot_only" or value == "marked_dot" then
            return value
        end

        return "marked_icon"
    end

    --- Returns the settings group of a marker kind.
    -- ?string: kind marker kind
    -- treturn: ?string group name, `enemies_group` for every enemy kind
    function mod:get_marker_scale_group(kind)
        if not kind then
            return nil
        end

        if string_sub(tostring(kind), 1, 6) == "enemy_" then
            return "enemies_group"
        end

        return MARKER_SCALE_GROUP_BY_KIND[kind]
    end

    --- Returns whether a marker kind belongs to a live event.
    -- treturn: bool
    function mod:is_event_marker_kind(kind)
        return kind ~= nil and MARKER_SCALE_GROUP_BY_KIND[kind] == "event_group"
    end

    --- Converts a percentage slider into a scale factor clamped to 0.5 to 3.
    -- tab: self mod object
    -- ?string: setting_id slider setting; 1 when nil
    -- treturn: number
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

    --- Returns the icon scale factor of a settings group.
    -- ?string: group_name group from `get_marker_scale_group`
    -- treturn: number 1 for groups without a slider
    function mod:get_marker_scale_factor(group_name)
        local setting_id = ICON_SCALE_SETTING_BY_GROUP[group_name]

        return _percent_scale_from_setting(self, setting_id)
    end

    --- Returns the radar definition of an enemy marker kind or breed name.
    -- treturn: ?tab definition
    function mod:get_enemy_radar_definition(kind_or_breed)
        if not kind_or_breed then
            return nil
        end

        return ENEMY_RADAR_DEFINITION_BY_KIND[kind_or_breed] or ENEMY_RADAR_DEFINITIONS_BY_BREED[kind_or_breed]
    end

    --- Returns whether vertical arrows are enabled for an enemy, by boss kind or by category.
    -- treturn: bool
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

    --- Returns the display mode of an enemy marker kind.
    -- The shared horde setting only supports showing or hiding.
    -- ?string: kind marker kind
    -- treturn: ?string `icon_only`, `marked_icon` or `off`; nil for kinds without an enemy setting
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

    --- Returns the icon scale factor of an enemy, by boss kind or by the definition's scale category.
    -- treturn: number
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

    --- Returns a marker kind's selection priority; higher priorities are kept first under the marker limit.
    -- ?string: kind marker kind
    -- treturn: number 0 for kinds without a priority
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

    --- Returns a marker kind's render layer offset; higher layers draw above lower ones.
    -- ?string: kind marker kind
    -- treturn: number 0 for kinds without a layer
    function mod:get_target_render_layer(kind)
        if self:is_event_marker_kind(kind) then
            return EVENT_MARKER_RENDER_LAYER
        end

        if kind == "player_teammate" then
            return PLAYER_TEAMMATE_RENDER_LAYER
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

    --- Returns the artwork dropdown mode of a marker kind.
    -- ?string: kind marker kind
    -- treturn: ?string `artwork`, `icon` or `off`; nil for kinds without that dropdown
    function mod:get_marker_display_mode(kind)
        local setting_id = ARTWORK_MODE_KIND_TO_SETTING[kind]
        if not setting_id then
            return nil
        end

        return _normalize_marker_display_mode(mod:get(setting_id), ARTWORK_MODE_DEFAULT_BY_SETTING[setting_id])
    end

    --- Returns the icon / icon and distance / off dropdown mode of a non-Expedition marker kind.
    -- ?string: kind marker kind
    -- treturn: ?string `icon_only`, `icon_distance` or `off`; nil for kinds without that dropdown
    function mod:get_icon_distance_marker_display_mode(kind)
        local setting_id = ICON_DISTANCE_MARKER_DISPLAY_MODE_KIND_TO_SETTING[kind]
        if not setting_id then
            return nil
        end

        return _normalize_expedition_marker_display_mode(
            mod:get(setting_id),
            ICON_DISTANCE_MARKER_DISPLAY_MODE_DEFAULT_BY_SETTING[setting_id]
        )
    end

    --- Returns the dropdown mode of an Expedition location marker kind.
    -- ?string: kind marker kind
    -- treturn: ?string `icon_only`, `icon_distance` or `off`; nil for other kinds
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

    --- Converts artwork dropdown settings saved as checkboxes into dropdown values.
    local function _migrate_marker_display_mode_settings()
        local mod_get = mod.get
        local mod_set = mod.set

        for i = 1, #ARTWORK_MODE_SETTING_IDS do
            local setting_id = ARTWORK_MODE_SETTING_IDS[i]
            local value = mod_get(mod, setting_id)

            if value == true then
                mod_set(mod, setting_id, ARTWORK_MODE_DEFAULT_BY_SETTING[setting_id] or "artwork")
            elseif value == false then
                mod_set(mod, setting_id, "off")
            end
        end
    end

    --- Converts Expedition marker dropdown settings saved as checkboxes into dropdown values.
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

    --- Seeds the per-breed enemy settings split out of the old common and shooter settings.
    -- Only settings that were never saved take the old category's value.
    local function _migrate_split_enemy_category_settings()
        local mod_get = mod.get
        local mod_set = mod.set
        local migrations = {
            {
                legacy_setting_id = "show_enemy_common",
                setting_ids = {
                    "show_enemy_cultist_melee",
                    "show_enemy_renegade_melee",
                    "show_enemy_cultist_vanguard",
                    "show_enemy_renegade_vanguard",
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

    --- Folds the old teammate checkbox and player style into the player marker dropdown, once.
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

    --- DMF callback run once all mods are loaded.
    -- Migrates settings saved by older versions. The UI packages holding the icon materials Radar
    -- draws are declared in `Radar.mod`, which DMF loads and releases itself.
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
    end
end
