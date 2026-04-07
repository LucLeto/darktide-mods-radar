local mod = get_mod("Radar")
local Pickups = require("scripts/settings/pickup/pickups")
local PlayerUnitStatus = require("scripts/utilities/attack/player_unit_status")

local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local type = type
local rawget = rawget
local math_abs = math.abs
local math_floor = math.floor
local math_huge = math.huge
local math_max = math.max
local math_sqrt = math.sqrt
local string_find = string.find
local string_format = string.format
local string_len = string.len
local string_lower = string.lower
local string_match = string.match
local string_sub = string.sub
local table_concat = table.concat
local table_sort = table.sort

local SCAN_INTERVAL = 0.25

local NEARBY_OUTLINE_OCCLUDED_MULTIPLIER = 0.6

local NEARBY_OUTLINE_COLOR_BY_KIND = {
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
    pickup_coordinates_paper = { 255, 255, 255, 255 },
    pocketable_grimoire = { 255, 150, 190, 60 },
    pocketable_scripture = { 255, 192, 160, 0 },
    material_expeditions_currency = { 255, 120, 160, 140 },
    material_expeditions_loot = { 255, 192, 160, 0 },
    material_expeditions_loot_player_drop = { 220, 255, 0, 0 },
    luggable_data_reliquary = { 255, 192, 160, 0 },
    pickup_large_ammunition_crate = { 255, 240, 210, 80 },
    luggable_promethium_barrel = { 255, 255, 110, 0 },
    pocketable_anti_rad_stimm = { 255, 255, 255, 255 },
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
mod._screen_highlight_targets = {}
mod._unclustered_radar_targets = {}
mod._highlight_source_radar_targets = {}
mod._idol_destroyed_collectible_keys = {}
mod._idol_destroyed_units = {}

local MONSTROSITY_BREEDS = {
    chaos_daemonhost = true,
    chaos_beast_of_nurgle = true,
    chaos_plague_ogryn = true,
    chaos_spawn = true,
    chaos_ogryn_houndmaster = true,
}

local CAPTAIN_BREEDS = {
    renegade_captain = true,
    cultist_captain = true,
}

local TWIN_BREEDS = {
    renegade_twin_captain = true,
    renegade_twin_captain_two = true,
}

local KIND_TO_SETTING = {
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
    crate_unknown = "show_crates",
    enemy_daemonhost = "show_monstrosities",
    enemy_monstrosity = "show_monstrosities",
    enemy_captain = "show_captains",
    enemy_karnak_twin = "show_karnak_twins",
    player_teammate = "show_teammates",
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

local EXPEDITION_MARKER_KINDS = {
    expedition_loot_converter = true,
    expedition_objective_opportunity = true,
    expedition_objective_transition = true,
    expedition_objective_main_objective = true,
    expedition_objective_extraction = true,
    expedition_objective_arrival = true,
}

local EXPEDITION_OBJECTIVE_ICON_DEFAULTS = {
    expedition_loot_converter = "content/ui/materials/hud/interactions/icons/expeditions",
    expedition_objective_transition = "content/ui/materials/backgrounds/scanner/scanner_map_exit",
    expedition_objective_main_objective = "content/ui/materials/hud/interactions/icons/objective_main",
    expedition_objective_extraction = "content/ui/materials/backgrounds/scanner/scanner_map_extract",
    expedition_objective_arrival = "content/ui/materials/icons/mission_types/mission_type_05",
}

local ARTWORK_MODE_KIND_TO_SETTING = {
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
    pickup_tainted_skull = "event_group",
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


local RADAR_GAME_MODE_SETTING_BY_ID = {
    regular_missions = "enable_in_regular_missions",
    havoc = "enable_in_havoc",
    mortis_trials = "enable_in_mortis_trials",
    expeditions = "enable_in_expeditions",
}

local ARTWORK_MODE_SETTING_IDS = {
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

local EXPEDITION_LOOT_VALUE_BY_PICKUP_NAME = {
    expedition_loot_small_tier_1 = 10,
    expedition_loot_small_tier_2 = 25,
    expedition_loot_small_tier_3 = 50,
}


local NEARBY_HIGHLIGHT_SETTING_BY_GROUP = {
    common_pickups_group = "nearby_highlight_common_pickups",
    materials_group = "nearby_highlight_materials",
    primary_objective_group = "nearby_highlight_primary_objective",
    secondary_objective_group = "nearby_highlight_secondary_objective",
    expeditions_specific_group = "nearby_highlight_expeditions_specific",
    martyr_s_skull_group = "nearby_highlight_martyr_s_skull",
    environment_group = "nearby_highlight_environment",
    event_group = "nearby_highlight_event",
}


local DEFAULT_COLOR_ARRAY = { 255, 255, 255, 255 }

local EXACT_PICKUP_KIND_BY_NAME = {
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

local PAPER_PICKUP_NAMES = {
    paper_pickup = true,
    paper_pickup_02 = true,
    paper_pickup_03 = true,
    paper_pickup_04 = true,
}

local SAINTS_PICKUP_NAMES = {
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

function mod:get_marker_scale_group(kind)
    if not kind then
        return nil
    end

    if string_sub(tostring(kind), 1, 6) == "enemy_" then
        return "enemies_group"
    end

    return MARKER_SCALE_GROUP_BY_KIND[kind]
end

function mod:get_marker_scale_factor(group_name)
    local setting_id = ICON_SCALE_SETTING_BY_GROUP[group_name]

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

function mod:get_marker_display_mode(kind)
    local setting_id = ARTWORK_MODE_KIND_TO_SETTING[kind]
    if not setting_id then
        return nil
    end

    return _normalize_marker_display_mode(mod:get(setting_id))
end

local function _migrate_marker_display_mode_settings()
    for _, setting_id in ipairs(ARTWORK_MODE_SETTING_IDS) do
        local value = mod:get(setting_id)

        if value == true then
            mod:set(setting_id, "artwork")
        elseif value == false then
            mod:set(setting_id, "off")
        end
    end
end

function mod.on_all_mods_loaded()
    _migrate_marker_display_mode_settings()

    -- Preload icon packages
    local function load_package(package_name)
        local ok, err = pcall(function()
            if not Managers or not Managers.package then
                error("Managers.package unavailable")
            end

            if not Managers.package:has_loaded(package_name) then
                Managers.package:load(package_name, "Radar", nil, true)
                if mod:get("debug_mode") then
                    mod:echo(string_format("[Radar] package load requested | %s", tostring(package_name)))
                end
            else
                if mod:get("debug_mode") then
                    mod:echo(string_format("[Radar] package already loaded | %s", tostring(package_name)))
                end
            end
        end)

        if not ok then
            if mod:get("debug_mode") then
                mod:echo(string_format("[Radar] package load failed | %s | %s", tostring(package_name), tostring(err)))
            end
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

    if mod:get("debug_mode") then
        mod:echo("Packages loaded")
    end
end

local function _safe_gameplay_time()
    local time_manager = Managers and Managers.time
    if not time_manager then
        return nil
    end

    local timers = time_manager._timers
    if not timers or not timers.gameplay then
        return nil
    end

    return time_manager:time("gameplay")
end

local function _safe_unit_alive(unit)
    return unit and ALIVE and ALIVE[unit]
end

local function _safe_unit_name(unit)
    if not _safe_unit_alive(unit) then
        return "<dead>"
    end

    local ok, result = pcall(Unit.debug_name, unit, false)
    if ok and result then
        return tostring(result)
    end

    return tostring(unit)
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

local function _copy_vector3(vec)
    local x, y, z = _vector3_components(vec)

    if not _is_finite_number(x) or not _is_finite_number(y) or not _is_finite_number(z) then
        return nil
    end

    return { x = x, y = y, z = z }
end

local function _safe_lower_string(value)
    if value == nil then
        return nil
    end

    return string_lower(tostring(value))
end

local function _string_starts_with(value, prefix)
    if value == nil or prefix == nil then
        return false
    end

    return string_sub(value, 1, string_len(prefix)) == prefix
end

local function _safe_unit_data_string(unit, field_name)
    if not unit or not field_name or not Unit or not Unit.has_data or not Unit.get_data then
        return nil
    end

    local ok_has_data, has_data = pcall(Unit.has_data, unit, field_name)
    if not ok_has_data or not has_data then
        return nil
    end

    local ok_value, value = pcall(Unit.get_data, unit, field_name)
    if ok_value and value ~= nil then
        return _safe_lower_string(value)
    end

    return nil
end

local function _safe_unit_pickup_name(unit)
    return _safe_unit_data_string(unit, "pickup_type")
end

local function _safe_unit_deployable_type(unit)
    return _safe_unit_data_string(unit, "deployable_type")
end

local function _safe_unit_smart_tag_target_type(unit)
    return _safe_unit_data_string(unit, "smart_tag_target_type")
end

local function _safe_unit_collectible_type(unit)
    return _safe_unit_data_string(unit, "collectible_type")
end

local function _safe_destructible_collectible_data(extension)
    if not extension then
        return nil
    end

    local collectible_data = rawget(extension, "_collectible_data")
    if type(collectible_data) == "table" then
        return collectible_data
    end

    return nil
end

local function _safe_destructible_visible(extension)
    if not extension then
        return nil
    end

    local visibility_info = rawget(extension, "_visibility_info")
    if type(visibility_info) == "table" and visibility_info.visible ~= nil then
        return visibility_info.visible == true
    end

    return nil
end

local function _safe_unit_main_visible(unit)
    if not unit or not Unit or not Unit.is_visible then
        return nil
    end

    local ok_visible, is_visible = pcall(Unit.is_visible, unit, "main")

    if ok_visible then
        return is_visible == true
    end

    local ok_visible_2, is_visible_2 = pcall(Unit.is_visible, unit)

    if ok_visible_2 then
        return is_visible_2 == true
    end

    return nil
end

local function _table_size(t)
    local n = 0
    for _, _ in pairs(t) do
        n = n + 1
    end
    return n
end

local DEFAULT_RADAR_POS_X = 40
local DEFAULT_RADAR_POS_Y = 220
local DEFAULT_RADAR_MOVE_STEP = 10
local DEFAULT_RADAR_ANCHOR = "top_left"

local RADAR_ANCHORS = {
    top_left = true,
    top_right = true,
    bottom_left = true,
    bottom_right = true,
}

local function _clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end

    if value > max_value then
        return max_value
    end

    return value
end

local function _get_ui_space_size()
    local width = 1920
    local height = 1080
    local resolution_lookup = RESOLUTION_LOOKUP

    if resolution_lookup and resolution_lookup.width and resolution_lookup.height then
        local inverse_scale = resolution_lookup.inverse_scale or 1

        width = resolution_lookup.width * inverse_scale
        height = resolution_lookup.height * inverse_scale
    end

    return width, height
end

local function _normalize_radar_anchor(value)
    if RADAR_ANCHORS[value] then
        return value
    end

    return DEFAULT_RADAR_ANCHOR
end

local function _get_radar_position_bounds(size)
    local radar_size = tonumber(size) or 0
    local ui_width, ui_height = _get_ui_space_size()
    local max_x = math_max(0, ui_width - radar_size)
    local max_y = math_max(0, ui_height - radar_size)

    return max_x, max_y
end

local function _round_radar_position_value(value, default_value)
    return math_floor((tonumber(value) or default_value or 0) + 0.5)
end

local function _resolve_radar_position_value(value, default_value, min_value, max_value, unrestricted)
    local rounded_value = _round_radar_position_value(value, default_value)

    if unrestricted == true then
        return rounded_value
    end

    return math_floor(_clamp(rounded_value, min_value, max_value) + 0.5)
end

local function _get_radar_origin_from_offsets(anchor, offset_x, offset_y, size)
    local max_x, max_y = _get_radar_position_bounds(size)
    local x = offset_x
    local y = offset_y

    if anchor == "top_right" or anchor == "bottom_right" then
        x = max_x - offset_x
    end

    if anchor == "bottom_left" or anchor == "bottom_right" then
        y = max_y - offset_y
    end

    return x, y, max_x, max_y
end

local function _get_radar_offsets_from_origin(anchor, x, y, size)
    local max_x, max_y = _get_radar_position_bounds(size)
    local offset_x = x
    local offset_y = y

    if anchor == "top_right" or anchor == "bottom_right" then
        offset_x = max_x - x
    end

    if anchor == "bottom_left" or anchor == "bottom_right" then
        offset_y = max_y - y
    end

    return offset_x, offset_y, max_x, max_y
end

local function _log_once(key, text)
    if mod:get("debug_mode") ~= true then
        return
    end

    if mod._logged_units[key] then
        return
    end

    mod._logged_units[key] = true
    mod:echo(text)
end

local function _position_lookup(unit)
    if not unit or not POSITION_LOOKUP then
        return nil
    end

    return _copy_vector3(POSITION_LOOKUP[unit])
end

local function _safe_unit_position(unit)
    if not _safe_unit_alive(unit) then
        return nil
    end

    local position = _position_lookup(unit)
    if position then
        return position
    end

    local ok, world_position = pcall(Unit.world_position, unit, 1)
    if ok and world_position then
        return _copy_vector3(world_position)
    end

    return nil
end

local function _is_enemy_kind(kind)
    return kind ~= nil and _string_starts_with(kind, "enemy_")
end

local function _safe_health_alive(unit)
    if not unit or not ScriptUnit or not ScriptUnit.has_extension then
        return nil
    end

    local health_extension = ScriptUnit.has_extension(unit, "health_system")
    if not health_extension or not health_extension.is_alive then
        return nil
    end

    local ok_alive, is_alive = pcall(health_extension.is_alive, health_extension)

    if ok_alive then
        return is_alive
    end

    return nil
end

local function _is_owned_by_death_manager(unit)
    if not unit or not ScriptUnit or not ScriptUnit.has_extension then
        return false
    end

    local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
    if not unit_data_extension or not unit_data_extension.is_owned_by_death_manager then
        return false
    end

    local ok_owned, owned = pcall(unit_data_extension.is_owned_by_death_manager, unit_data_extension)

    return ok_owned and owned or false
end

local function _is_trackable_unit_alive(unit, kind)
    if not _safe_unit_alive(unit) then
        return false
    end

    if _is_enemy_kind(kind) then
        if _is_owned_by_death_manager(unit) then
            return false
        end

        local health_alive = _safe_health_alive(unit)
        if health_alive == false then
            return false
        end
    end

    if kind == "pickup_heretic_idol" then
        local health_alive = _safe_health_alive(unit)
        if health_alive == false then
            return false
        end
    end

    return true
end

local function _safe_world_rotation(unit, node)
    if not _safe_unit_alive(unit) then
        return nil
    end

    local ok, rotation = pcall(Unit.world_rotation, unit, node or 1)
    if ok then
        return rotation
    end

    return nil
end

local function _safe_flat_direction_xy(vector_getter, rotation)
    if not rotation or not vector_getter then
        return nil, nil
    end

    local ok, direction = pcall(vector_getter, rotation)
    if not ok or not direction then
        return nil, nil
    end

    local x, y = _vector3_components(direction)
    if not _is_finite_number(x) or not _is_finite_number(y) then
        return nil, nil
    end

    local length = math_sqrt(x * x + y * y)
    if length <= 0 then
        return nil, nil
    end

    return x / length, y / length
end

local function _safe_forward_xy(rotation)
    return _safe_flat_direction_xy(Quaternion.forward, rotation)
end

local function _safe_mission_name()
    local state_gameplay = mod._last_state_gameplay
    if state_gameplay then
        local shared_state = state_gameplay._shared_state
        local mission_name = shared_state and shared_state.mission_name
        if mission_name ~= nil then
            return mission_name
        end
    end

    local state_manager = Managers and Managers.state
    local game_mode_manager = state_manager and state_manager.game_mode
    if game_mode_manager and game_mode_manager.mission_name then
        local ok, mission_name = pcall(game_mode_manager.mission_name, game_mode_manager)

        if ok and mission_name ~= nil then
            return mission_name
        end
    end

    local gameplay = state_manager and state_manager.gameplay
    local shared_state = gameplay and gameplay._shared_state
    local mission_name = shared_state and shared_state.mission_name
    if mission_name ~= nil then
        return mission_name
    end

    local package_synchronizer_client = Managers and Managers.package_synchronizer_client
    mission_name = package_synchronizer_client and package_synchronizer_client._mission_name
    if mission_name ~= nil then
        return mission_name
    end

    local mechanism_manager = Managers and Managers.mechanism
    local mechanism = mechanism_manager and mechanism_manager._mechanism
    mission_name = mechanism and mechanism._mission_name
    if mission_name ~= nil then
        return mission_name
    end

    return nil
end

local function _safe_presence_activity()
    local presence_manager = Managers and Managers.presence
    if not presence_manager then
        return nil
    end

    if presence_manager.activity then
        local ok, value = pcall(presence_manager.activity, presence_manager)
        if ok and value ~= nil then
            return tostring(value)
        end
    end

    if presence_manager.current_activity then
        local ok, value = pcall(presence_manager.current_activity, presence_manager)
        if ok and value ~= nil then
            return tostring(value)
        end
    end

    local value = presence_manager._current_activity
    if value ~= nil then
        return tostring(value)
    end

    value = presence_manager._activity
    if value ~= nil then
        return tostring(value)
    end

    value = presence_manager._presence_name
    if value ~= nil then
        return tostring(value)
    end

    return nil
end

local function _safe_mechanism_name()
    local mechanism_manager = Managers and Managers.mechanism
    if not mechanism_manager then
        return nil
    end

    if mechanism_manager.current_mechanism_name then
        local ok, value = pcall(mechanism_manager.current_mechanism_name, mechanism_manager)
        if ok and value ~= nil then
            return tostring(value)
        end
    end

    if mechanism_manager.mechanism_name then
        local ok, value = pcall(mechanism_manager.mechanism_name, mechanism_manager)
        if ok and value ~= nil then
            return tostring(value)
        end
    end

    local value = mechanism_manager._mechanism_name
    if value ~= nil then
        return tostring(value)
    end

    local mechanism = mechanism_manager._mechanism
    if mechanism ~= nil then
        if type(mechanism) == "table" then
            value = mechanism.name or mechanism._name
            if value ~= nil then
                return tostring(value)
            end
        else
            return tostring(mechanism)
        end
    end

    return nil
end

local function _is_hub_runtime(mission_name, activity, mechanism_name)
    mission_name = mission_name or _safe_mission_name()
    activity = activity or _safe_presence_activity()
    mechanism_name = mechanism_name or _safe_mechanism_name()

    return mission_name == "hub_ship"
        or activity == "hub"
        or activity == "main_menu"
        or activity == "title_screen"
        or mechanism_name == "hub"
end

local function _player_manager()
    return Managers and Managers.player
end

local function _local_player()
    local player_manager = _player_manager()
    if not player_manager then
        return nil
    end

    local num_players = tonumber(player_manager._num_players) or 0
    if num_players <= 0 then
        return nil
    end

    local getter = player_manager.local_player_safe or player_manager.local_player
    if not getter then
        return nil
    end

    local ok, player = pcall(getter, player_manager, 1)

    if ok then
        return player
    end

    return nil
end

local function _player_unit()
    local local_player = _local_player()
    return local_player and local_player.player_unit
end

local function _is_player_unit_alive(player_unit)
    return _safe_unit_alive(player_unit)
end

local function _is_player_unit_captured(player_unit)
    if not _safe_unit_alive(player_unit) or not PlayerUnitStatus or not PlayerUnitStatus.is_hogtied then
        return false
    end

    local ok, captured = pcall(PlayerUnitStatus.is_hogtied, player_unit)

    return ok and captured == true or false
end

local function _is_local_player_alive()
    return _is_player_unit_alive(_player_unit())
end

local function _is_local_player_captured()
    return _is_player_unit_captured(_player_unit())
end

local function _safe_camera_rotation()
    local local_player = _local_player()
    if not local_player then
        return nil
    end

    local viewport_name = local_player.viewport_name
    if not viewport_name then
        return nil
    end

    local camera_manager = Managers and Managers.state and Managers.state.camera
    if not camera_manager then
        return nil
    end

    if camera_manager.has_camera then
        local ok_has_camera, has_camera = pcall(camera_manager.has_camera, camera_manager, viewport_name)

        if ok_has_camera and not has_camera then
            return nil
        end
    end

    if not camera_manager.camera_rotation then
        return nil
    end

    local ok_rotation, rotation = pcall(camera_manager.camera_rotation, camera_manager, viewport_name)

    if ok_rotation and rotation then
        return rotation
    end

    return nil
end

local function _safe_player_rotation(player_unit)
    local camera_rotation = _safe_camera_rotation()
    if camera_rotation then
        return camera_rotation
    end

    if not _safe_unit_alive(player_unit) then
        return nil
    end

    local unit_data_extension = ScriptUnit and ScriptUnit.has_extension and
        ScriptUnit.has_extension(player_unit, "unit_data_system")
    if unit_data_extension and unit_data_extension.read_component then
        local ok_component, first_person_component = pcall(unit_data_extension.read_component, unit_data_extension,
            "first_person")

        if ok_component and first_person_component and first_person_component.rotation then
            return first_person_component.rotation
        end
    end

    local first_person_extension = ScriptUnit and ScriptUnit.has_extension and
        ScriptUnit.has_extension(player_unit, "first_person_system")
    if first_person_extension and first_person_extension.extrapolated_rotation then
        local ok_rotation, rotation = pcall(first_person_extension.extrapolated_rotation, first_person_extension)

        if ok_rotation and rotation then
            return rotation
        end
    end

    return _safe_world_rotation(player_unit, 1)
end

local function _safe_extension_system(system_name)
    local extension_manager = Managers and Managers.state and Managers.state.extension
    if not extension_manager or not extension_manager.system then
        return nil
    end

    local ok, system = pcall(extension_manager.system, extension_manager, system_name)

    if ok then
        return system
    end

    return nil
end

local function _copy_color_array(color)
    if not color then
        return nil
    end

    return {
        color[1] or 255,
        color[2] or 255,
        color[3] or 255,
        color[4] or 255,
    }
end

local function _darkened_color_array(color, multiplier)
    local src = color or DEFAULT_COLOR_ARRAY
    local mul = multiplier or 1

    return {
        src[1] or 255,
        math_floor(_clamp((src[2] or 255) * mul, 0, 255) + 0.5),
        math_floor(_clamp((src[3] or 255) * mul, 0, 255) + 0.5),
        math_floor(_clamp((src[4] or 255) * mul, 0, 255) + 0.5),
    }
end

local function _outline_color_vector3(color)
    local src = color or DEFAULT_COLOR_ARRAY

    return Vector3(
        (src[2] or 255) / 255,
        (src[3] or 255) / 255,
        (src[4] or 255) / 255
    )
end

local function _nearby_outline_color_signature(color)
    local src = color or DEFAULT_COLOR_ARRAY

    return string_format(
        "%d:%d:%d",
        src[2] or 255,
        src[3] or 255,
        src[4] or 255
    )
end

local SCREEN_HIGHLIGHT_Z_OFFSET_BY_KIND = {
    material_diamantine = 0.1,
    material_plasteel = 0.1,
    crate_unknown = 0.08,
    pickup_ammo = 0.08,
    pickup_ammo_small = 0.08,
    pickup_ammo_big = 0.08,
    pickup_grenade = 0.08,
    pocketable_ammo_crate = 0.08,
    pocketable_medical_crate = 0.08,
    pocketable_syringe_ability = 0.08,
    pocketable_syringe_corruption = 0.08,
    pocketable_syringe_power = 0.08,
    pocketable_syringe_speed = 0.08,
    luggable_power_cell_teal = 0.18,
    luggable_cryonic_rod = 0.18,
    luggable_moebian_pox_zetaphyte_13_sample = 0.18,
    luggable_vacuum_capsule = 0.18,
    luggable_special_issue_ammo = 0.18,
    luggable_prismata_crystal_repository = 0.18,
    pickup_mortis_relic = 0.1,
    pickup_coordinates_paper = 0.08,
    pocketable_grimoire = 0.08,
    pocketable_scripture = 0.08,
    material_expeditions_currency = 0.1,
    material_expeditions_loot = 0.1,
    material_expeditions_loot_player_drop = 0.1,
    luggable_data_reliquary = 0.18,
    pickup_large_ammunition_crate = 0.1,
    luggable_promethium_barrel = 0.12,
    pocketable_anti_rad_stimm = 0.08,
    pocketable_airstrike = 0.08,
    pocketable_artillery_strike = 0.08,
    pocketable_big_grenade = 0.08,
    pocketable_landmine_explosive = 0.08,
    pocketable_landmine_fire = 0.08,
    pocketable_landmine_shock = 0.08,
    pocketable_valkyrie_hover = 0.08,
    pocketable_void_shield = 0.08,
    pickup_martyr_skull = 0.1,
    luggable_power_cell_orange = 0.18,
    medicae_station = 0.2,
    luggable_socket = 0.18,
    pickup_heretic_idol = 0.12,
    pickup_tainted_skull = 0.1,
    pocketable_corrupted_auspex_scanner = 0.08,
    pickup_saints = 0.12,
    pickup_stolen_rations = 0.08,
}

local function _screen_highlight_color_for_kind(kind)
    return _copy_color_array(NEARBY_OUTLINE_COLOR_BY_KIND[kind])
end

local function _screen_highlight_anchor_position(target)
    local position = target and target.position

    if not position then
        return nil
    end

    local z_offset = SCREEN_HIGHLIGHT_Z_OFFSET_BY_KIND[target.kind] or 0

    return {
        x = position.x,
        y = position.y,
        z = (position.z or 0) + z_offset,
    }
end

local function _copy_target_list(targets)
    local copy = {}

    if not targets then
        return copy
    end

    for i = 1, #targets do
        copy[i] = targets[i]
    end

    return copy
end

local function _distance_squared(a, b)
    if not a or not b then
        return math_huge
    end

    local ax, ay, az = a.x, a.y, a.z
    local bx, by, bz = b.x, b.y, b.z

    if not _is_finite_number(ax) or not _is_finite_number(ay) or not _is_finite_number(az) then
        return math_huge
    end

    if not _is_finite_number(bx) or not _is_finite_number(by) or not _is_finite_number(bz) then
        return math_huge
    end

    local dx = ax - bx
    local dy = ay - by
    local dz = az - bz

    return dx * dx + dy * dy + dz * dz
end

local function _collect_screen_highlight_targets()
    if not mod:has_any_nearby_highlight_enabled() then
        return {}
    end

    local player_unit = _player_unit()

    if not _safe_unit_alive(player_unit) then
        return {}
    end

    local player_pos = _safe_unit_position(player_unit)

    if not player_pos then
        return {}
    end

    local get_setting = mod.get
    local get_marker_scale_group = mod.get_marker_scale_group
    local highlight_setting_by_group = NEARBY_HIGHLIGHT_SETTING_BY_GROUP
    local max_distance = mod:get_nearby_highlight_range()
    local max_distance_sq = max_distance * max_distance
    local highlights = {}
    local highlight_count = 0
    local highlight_enabled_by_kind = {}
    local source_targets = mod._highlight_source_radar_targets or mod._unclustered_radar_targets or mod._radar_targets or
        {}

    for i = 1, #source_targets do
        local target = source_targets[i]
        local kind = target and target.kind

        if kind ~= nil then
            local enabled = highlight_enabled_by_kind[kind]

            if enabled == nil then
                local group_name = get_marker_scale_group(mod, kind)
                local setting_id = group_name and highlight_setting_by_group[group_name] or nil

                enabled = setting_id ~= nil and get_setting(mod, setting_id) == true or false
                highlight_enabled_by_kind[kind] = enabled
            end

            if enabled then
                local position = target.position
                local distance_sq = target.distance_sq_3d

                if distance_sq == nil and position then
                    distance_sq = _distance_squared(player_pos, position)
                end

                if distance_sq ~= nil and distance_sq <= max_distance_sq then
                    local color = _screen_highlight_color_for_kind(kind)
                    local world_position = _screen_highlight_anchor_position(target)

                    if color and world_position then
                        highlight_count = highlight_count + 1
                        highlights[highlight_count] = {
                            unit = target.unit,
                            kind = kind,
                            world_position = world_position,
                            color = color,
                            occluded_color = _darkened_color_array(color, NEARBY_OUTLINE_OCCLUDED_MULTIPLIER),
                            distance_sq_3d = distance_sq,
                        }
                    end
                end
            end
        end
    end

    return highlights
end

local function _safe_unit_to_extension_map(system_name)
    local system = _safe_extension_system(system_name)
    local unit_to_extension_map = system and system.unit_to_extension_map

    if not unit_to_extension_map then
        return nil
    end

    local ok, map = pcall(unit_to_extension_map, system)

    if ok and type(map) == "table" then
        return map
    end

    return nil
end

local function _safe_game_mode_manager()
    return Managers and Managers.state and Managers.state.game_mode or nil
end

local function _safe_game_mode()
    local game_mode_manager = _safe_game_mode_manager()
    if not game_mode_manager or not game_mode_manager.game_mode then
        return nil
    end

    local ok, game_mode = pcall(game_mode_manager.game_mode, game_mode_manager)

    if ok then
        return game_mode
    end

    return nil
end

local function _safe_game_mode_name()
    local game_mode_manager = _safe_game_mode_manager()
    if not game_mode_manager or not game_mode_manager.game_mode_name then
        return nil
    end

    local ok, game_mode_name = pcall(game_mode_manager.game_mode_name, game_mode_manager)

    if ok then
        return game_mode_name
    end

    return nil
end

local function _is_expedition_runtime()
    return _safe_game_mode_name() == "expedition"
end

local function _expedition_loot_value_for_pickup_name(pickup_name)
    if not pickup_name then
        return nil
    end

    return EXPEDITION_LOOT_VALUE_BY_PICKUP_NAME[pickup_name]
end

local function _safe_expedition_loot_handler()
    if not _is_expedition_runtime() then
        return nil
    end

    local game_mode = _safe_game_mode()

    if not game_mode then
        return nil
    end

    local logic = rawget(game_mode, "_game_mode_logic")

    if logic and logic.loot_handler then
        local ok_handler, handler = pcall(logic.loot_handler, logic)

        if ok_handler and handler then
            return handler
        end
    end

    if logic then
        local handler = rawget(logic, "_loot_handler")

        if handler then
            return handler
        end
    end

    return nil
end

local function _safe_expedition_player_drop_amount(unit)
    if not unit then
        return nil
    end

    local loot_handler = _safe_expedition_loot_handler()
    local dropped_loot_by_pickup_unit = loot_handler and rawget(loot_handler, "_dropped_loot_by_pickup_unit")
    local amount = dropped_loot_by_pickup_unit and dropped_loot_by_pickup_unit[unit] or nil
    local numeric_amount = tonumber(amount)

    if numeric_amount and numeric_amount > 0 then
        return math_floor(numeric_amount + 0.5)
    end

    return nil
end

local function _is_in_expedition_safe_zone()
    if not _is_expedition_runtime() then
        return false
    end

    local game_mode = _safe_game_mode()
    local in_safe_zone = game_mode and game_mode.in_safe_zone

    if not in_safe_zone then
        return false
    end

    local ok, value = pcall(in_safe_zone, game_mode)

    return ok and value == true or false
end

local function _safe_vector3_unbox(value)
    if not value then
        return nil
    end

    if type(value) == "table" and value.x ~= nil and value.y ~= nil and value.z ~= nil then
        return _copy_vector3(value)
    end

    if value.unbox then
        local ok, vector = pcall(value.unbox, value)

        if ok and vector then
            return _copy_vector3(vector)
        end
    end

    return _copy_vector3(value)
end

local function _safe_expedition_level_index(level)
    if not level or not Managers or not Managers.state or not Managers.state.unit_spawner then
        return nil
    end

    local unit_spawner = Managers.state.unit_spawner
    if not unit_spawner.index_by_level then
        return nil
    end

    local ok, level_index = pcall(unit_spawner.index_by_level, unit_spawner, level)

    if ok then
        return level_index
    end

    return nil
end

local function _safe_expedition_level_by_index(level_index, sub_level_index)
    if level_index == nil or not Managers or not Managers.state or not Managers.state.unit_spawner then
        return nil
    end

    local unit_spawner = Managers.state.unit_spawner
    if not unit_spawner.level_by_index then
        return nil
    end

    local ok, level = pcall(unit_spawner.level_by_index, unit_spawner, level_index, sub_level_index)

    if ok then
        return level
    end

    return nil
end

local function _safe_expedition_level_data_by_index(game_mode, level_index, sub_level_index)
    if not game_mode or not game_mode.get_level_data then
        return nil
    end

    local level = _safe_expedition_level_by_index(level_index, sub_level_index)
    if not level then
        return nil
    end

    local ok, level_data = pcall(game_mode.get_level_data, game_mode, level)

    if ok then
        return level_data
    end

    return nil
end

local function _safe_expedition_section_index_by_level_index(game_mode, level_index, sub_level_index)
    local level_data = _safe_expedition_level_data_by_index(game_mode, level_index, sub_level_index)
    local section = level_data and level_data.section or nil

    return section and section.index or nil
end

local function _safe_current_safe_zone_section_index(game_mode)
    local logic = game_mode and game_mode._game_mode_logic or nil
    local index = logic and logic._current_safe_zone_section_index or nil

    return tonumber(index) or index
end

local function _safe_expedition_active_section_index(game_mode)
    if not game_mode then
        return nil
    end

    local in_safe_zone = false
    local in_safe_zone_fn = game_mode.in_safe_zone

    if in_safe_zone_fn then
        local ok, value = pcall(in_safe_zone_fn, game_mode)

        if ok then
            in_safe_zone = value == true
        end
    end

    if in_safe_zone then
        local safe_zone_section_index = _safe_current_safe_zone_section_index(game_mode)
        if safe_zone_section_index ~= nil then
            return safe_zone_section_index
        end
    end

    local current_location_index = game_mode.current_location_index

    if current_location_index then
        local ok, value = pcall(current_location_index, game_mode)

        if ok then
            return value
        end
    end

    return nil
end

local function _is_expedition_level_in_active_section(game_mode, active_section_index, level_index, sub_level_index)
    if active_section_index == nil or level_index == nil then
        return true
    end

    local section_index = _safe_expedition_section_index_by_level_index(game_mode, level_index, sub_level_index)
    if section_index == nil then
        return true
    end

    return section_index == active_section_index
end

local function _expedition_opportunity_icon(level_index)
    local numeric_index = tonumber(level_index) or 0
    local icon_index = 1 + numeric_index % 24

    return string_format("content/ui/materials/backgrounds/scanner/scanner_map_greek_%02d", icon_index)
end

local function _expedition_opportunity_title_icon(location_id)
    local numeric_id = tonumber(location_id) or 0
    return string_format("content/ui/materials/backgrounds/scanner/scanner_map_%d", numeric_id % 9)
end

local function _safe_havoc_runtime_active()
    local state_gameplay = mod._last_state_gameplay
    local shared_state = state_gameplay and state_gameplay._shared_state
    local havoc_data = shared_state and shared_state.havoc_data

    if havoc_data ~= nil and havoc_data ~= "" then
        return true
    end

    local difficulty_manager = Managers and Managers.state and Managers.state.difficulty
    if difficulty_manager and difficulty_manager.get_parsed_havoc_data then
        local ok_parsed, parsed_havoc_data = pcall(difficulty_manager.get_parsed_havoc_data, difficulty_manager)

        if ok_parsed and parsed_havoc_data then
            return true
        end
    end

    local game_mode = _safe_game_mode()
    if game_mode and game_mode.extension then
        local ok_extension, havoc_extension = pcall(game_mode.extension, game_mode, "havoc")

        if ok_extension and havoc_extension then
            return true
        end
    end

    return false
end

local function _classify_radar_game_mode(mission_name, mechanism_name)
    local game_mode_name = _safe_game_mode_name()

    if game_mode_name == "expedition" or mechanism_name == "expedition" then
        return "expeditions", game_mode_name
    end

    if game_mode_name == "survival" then
        return "mortis_trials", game_mode_name
    end

    if _safe_havoc_runtime_active() then
        return "havoc", game_mode_name
    end

    if game_mode_name == "coop_complete_objective"
        or game_mode_name == "training_grounds"
        or game_mode_name == "shooting_range"
        or mechanism_name == "adventure"
        or mission_name == "tg_shooting_range" then
        return "regular_missions", game_mode_name
    end

    return nil, game_mode_name
end

function mod:is_radar_enabled_for_game_mode(game_mode_id)
    local setting_id = RADAR_GAME_MODE_SETTING_BY_ID[game_mode_id]

    if not setting_id then
        return false
    end

    return self:get(setting_id) ~= false
end

function mod:get_current_radar_game_mode()
    local mission_name = _safe_mission_name()
    local mechanism_name = _safe_mechanism_name()

    return _classify_radar_game_mode(mission_name, mechanism_name)
end

local function _is_radar_enabled_for_current_mode(mission_name, mechanism_name)
    local game_mode_id = _classify_radar_game_mode(mission_name, mechanism_name)

    if not game_mode_id then
        return false
    end

    return mod:is_radar_enabled_for_game_mode(game_mode_id)
end

local function _get_runtime_state()
    local gameplay_t = _safe_gameplay_time()
    local mission_name = _safe_mission_name()
    local activity = _safe_presence_activity()
    local mechanism_name = _safe_mechanism_name()
    local player_unit = _player_unit()
    local player_pos = _safe_unit_position(player_unit)

    if activity == "loading" then
        return false, "loading", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if mechanism_name == "left_session" or mechanism_name == "hub" then
        return false, "hub_mechanism", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if not mission_name then
        return false, "no_mission", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if mission_name == "hub_ship" then
        return false, "hub_mission", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if mechanism_name == "onboarding" and mission_name ~= "tg_shooting_range" then
        return false, "onboarding_non_psykhanium", gameplay_t, mission_name, activity, mechanism_name, player_unit,
            player_pos
    end

    if _is_hub_runtime(mission_name, activity, mechanism_name) then
        return false, "hub_runtime", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if not _is_radar_enabled_for_current_mode(mission_name, mechanism_name) then
        return false, "game_mode_disabled", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if not _is_player_unit_alive(player_unit) then
        return false, "player_not_alive", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if _is_player_unit_captured(player_unit) then
        return false, "player_captured", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    if not player_pos then
        return false, "no_player_position", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
    end

    return true, "ok", gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos
end

local function _is_allowed_runtime()
    local allowed = _get_runtime_state()
    return allowed
end

local function _is_expedition_marker_kind(kind)
    return EXPEDITION_MARKER_KINDS[kind] == true
end

local function _is_boss_marker_kind(kind)
    return kind == "enemy_monstrosity"
        or kind == "enemy_captain"
        or kind == "enemy_karnak_twin"
end

local function _ignore_radar_range_for_kind(kind)
    if kind == "expedition_loot_converter" then
        return false
    end

    if _is_boss_marker_kind(kind) and mod:get_boss_marker_range_mode() == "infinite" then
        return true
    end

    return _is_expedition_marker_kind(kind) and mod:get("ignore_radar_range_for_expedition_markers") == true
end

local function _kind_enabled(kind)
    local display_mode = mod:get_marker_display_mode(kind)
    if display_mode ~= nil then
        return display_mode ~= "off"
    end

    local setting_id = KIND_TO_SETTING[kind]
    if not setting_id then
        return true
    end

    return mod:get(setting_id) ~= false
end

local function _pickup_meta(pickup_name, pickup_data, interaction_type, ui_interaction_type, interaction_icon,
                            description, unit_name, marked_by_player_slot)
    return {
        pickup_name = pickup_name,
        pickup_group = pickup_data and pickup_data.group or nil,
        interaction_type = interaction_type,
        ui_interaction_type = ui_interaction_type,
        interaction_icon = interaction_icon,
        description = description,
        unit_name = unit_name,
        marked_by_player_slot = marked_by_player_slot,
    }
end

local function _classify_pickup_like(interaction_type, ui_interaction_type, icon, description, unit_name, pickup_name,
                                     pickup_data, marked_by_player_slot)
    local meta = _pickup_meta(pickup_name, pickup_data, interaction_type, ui_interaction_type, icon, description,
        unit_name,
        marked_by_player_slot)

    -- default items
    if interaction_type == "chest" then
        return "crate_unknown", meta
    end

    if interaction_type == "expedition_loot_converter"
        or (ui_interaction_type == "point_of_interest" and pickup_name == "expedition_loot_converter") then
        meta.objective_icon = EXPEDITION_OBJECTIVE_ICON_DEFAULTS.expedition_loot_converter
        return "expedition_loot_converter", meta
    end

    if interaction_type == "health_station" or pickup_name == "health_station" then
        return "medicae_station", meta
    end

    if (interaction_type == "health" or pickup_name == "health")
        and pickup_name ~= "medical_crate_deployable"
        and icon == "content/ui/materials/hud/interactions/icons/respawn" then
        return "medicae_station", meta
    end

    if interaction_type == "luggable_socket" or pickup_name == "luggable_socket" then
        return "luggable_socket", meta
    end

    if pickup_name ~= nil then
        local exact_kind = EXACT_PICKUP_KIND_BY_NAME[pickup_name]

        if exact_kind then
            return exact_kind, meta
        end

        if PAPER_PICKUP_NAMES[pickup_name] then
            return "pickup_coordinates_paper", meta
        end

        if SAINTS_PICKUP_NAMES[pickup_name] then
            return "pickup_saints", meta
        end

        if _string_starts_with(pickup_name, "expedition_currency_") then
            return "material_expeditions_currency", meta
        end

        if _string_starts_with(pickup_name, "expedition_loot_small_") then
            return "material_expeditions_loot", meta
        end
    end

    local key = string_format("%s|%s|%s|%s|%s|%s",
        tostring(pickup_name or ""),
        tostring(interaction_type or ""),
        tostring(icon or ""),
        tostring(description or ""),
        tostring(unit_name or ""),
        tostring(pickup_data and pickup_data.group or ""))
    key = string_lower(key)

    if string_find(key, "grimoire", 1, true)
        or string_find(key, "scripture", 1, true)
        or string_find(key, "side_mission", 1, true)
        or string_find(key, "objective_side", 1, true)
        or string_find(key, "objective_pickup", 1, true)
        or string_find(key, "luggable", 1, true)
        or string_find(key, "forge_material", 1, true)
        or string_find(key, "tainted_skull", 1, true)
        or string_find(key, "saints_pickup", 1, true)
        or string_find(key, "stolen_rations", 1, true)
        or string_find(key, "penance_collectible", 1, true) then
        _log_once(key, "Unknown pickup: " .. key)
        return "pickup_unknown", meta
    end

    return nil, meta
end

local function _safe_player_slot(player)
    local slot_fn = player and player.slot

    if not slot_fn then
        return nil
    end

    local ok_slot, slot = pcall(slot_fn, player)

    if ok_slot then
        return slot
    end

    return nil
end

local _marked_by_player_slot_for_unit = function(unit)
    if not _safe_unit_alive(unit) then
        return nil
    end

    local smart_tag_system = _safe_extension_system("smart_tag_system")
    local unit_tag = smart_tag_system and smart_tag_system.unit_tag

    if not unit_tag then
        return nil
    end

    local ok_tag, tag = pcall(unit_tag, smart_tag_system, unit)
    local tagger_player = tag and tag.tagger_player

    if not ok_tag or not tagger_player then
        return nil
    end

    local ok_player, player = pcall(tagger_player, tag)

    if not ok_player or not player then
        return nil
    end

    return _safe_player_slot(player)
end

local function _classify_interactee(extension, unit)
    if not extension then
        return nil, nil
    end

    local interaction_type = nil
    local ui_interaction_type = nil
    local icon = nil
    local description = nil

    local ok_interaction_type, interaction_type_value = pcall(extension.interaction_type, extension)
    if ok_interaction_type then
        interaction_type = _safe_lower_string(interaction_type_value)
    end

    local ok_ui_interaction_type, ui_interaction_type_value = pcall(extension.ui_interaction_type, extension)
    if ok_ui_interaction_type then
        ui_interaction_type = _safe_lower_string(ui_interaction_type_value)
    end

    local ok_icon, icon_value = pcall(extension.interaction_icon, extension)
    if ok_icon then
        icon = _safe_lower_string(icon_value)
    end

    local ok_description, description_value = pcall(extension.description, extension)
    if ok_description then
        description = _safe_lower_string(description_value)
    end

    local unit_name = _safe_lower_string(_safe_unit_name(unit))
    local pickup_name = _safe_unit_pickup_name(unit)
    local pickup_data = pickup_name and Pickups and Pickups.by_name and Pickups.by_name[pickup_name] or nil
    local marked_by_player_slot = _marked_by_player_slot_for_unit(unit)

    local kind, meta = _classify_pickup_like(interaction_type, ui_interaction_type, icon, description, unit_name,
        pickup_name, pickup_data, marked_by_player_slot)

    if kind == "material_expeditions_loot" then
        meta.remnant_value = _expedition_loot_value_for_pickup_name(pickup_name)
        meta.remnant_tier = pickup_name and string_match(pickup_name, "tier_(%d+)$") or nil
        meta.is_player_drop = false
    elseif kind == "material_expeditions_loot_player_drop" then
        meta.remnant_value = _safe_expedition_player_drop_amount(unit)
        meta.is_player_drop = true
    end

    return kind, meta
end

local function _classify_enemy_from_breed(breed_name)
    local key = string_lower(breed_name or "")

    if key == "chaos_daemonhost" or string_find(key, "daemonhost", 1, true) then
        return "enemy_daemonhost"
    end

    if TWIN_BREEDS[key] or string_find(key, "twin_captain", 1, true) then
        return "enemy_karnak_twin"
    end

    if CAPTAIN_BREEDS[key] or string_find(key, "captain", 1, true) then
        return "enemy_captain"
    end

    if MONSTROSITY_BREEDS[key]
        or string_find(key, "beast_of_nurgle", 1, true)
        or string_find(key, "plague_ogryn", 1, true)
        or string_find(key, "chaos_spawn", 1, true)
        or string_find(key, "houndmaster", 1, true) then
        return "enemy_monstrosity"
    end

    return nil
end

local function _track_unit(unit, kind, source, meta)
    if not kind or not _is_trackable_unit_alive(unit, kind) then
        return
    end

    local tracked_units = mod._tracked_units
    local existing = tracked_units[unit]
    local now = _safe_gameplay_time() or 0
    local position = _safe_unit_position(unit)

    if existing then
        existing.kind = kind
        existing.source = source or existing.source
        existing.last_seen_t = now
        existing.position = position or existing.position

        if meta ~= nil then
            existing.meta = meta
        end
    else
        tracked_units[unit] = {
            kind = kind,
            source = source,
            last_seen_t = now,
            position = position,
            meta = meta,
        }
    end
end

local function _clear_tracked_unit_from_source(unit, source)
    local tracked_units = mod._tracked_units
    local tracked = tracked_units and tracked_units[unit]

    if tracked and tracked.source == source then
        tracked_units[unit] = nil
    end
end

local function _idol_collectible_key(section_id, id)
    if section_id == nil or id == nil then
        return nil
    end

    return tostring(section_id) .. ":" .. tostring(id)
end

local function _remember_destroyed_idol_collectible(section_id, id)
    local collectible_key = _idol_collectible_key(section_id, id)

    if collectible_key ~= nil then
        mod._idol_destroyed_collectible_keys[collectible_key] = _safe_gameplay_time() or 0
    end
end

local function _remember_destroyed_idol_unit(unit)
    if unit ~= nil then
        mod._idol_destroyed_units[unit] = _safe_gameplay_time() or 0
    end
end

local function _clear_tracked_idol_by_collectible(section_id, id)
    local collectible_key = _idol_collectible_key(section_id, id)

    if collectible_key == nil then
        return
    end

    local now = _safe_gameplay_time() or 0
    mod._idol_destroyed_collectible_keys[collectible_key] = now

    for unit, data in pairs(mod._tracked_units) do
        local meta = data and data.meta or nil

        if data and data.source == "destructible_system" and data.kind == "pickup_heretic_idol"
            and meta and meta.collectible_section_id == section_id and meta.collectible_id == id then
            mod._tracked_units[unit] = nil
            mod._idol_destroyed_units[unit] = now
        end
    end
end

local function _mark_idol_unit_destroyed(unit, extension)
    if unit == nil or _safe_unit_collectible_type(unit) ~= "heretic_idol" then
        return
    end

    local collectible_data = _safe_destructible_collectible_data(extension)

    if collectible_data then
        _remember_destroyed_idol_collectible(collectible_data.section_id, collectible_data.id)
    end

    _remember_destroyed_idol_unit(unit)
    _clear_tracked_unit_from_source(unit, "destructible_system")
end

local function _prune_destroyed_idol_state()
    local now = _safe_gameplay_time() or 0

    for collectible_key, destroyed_t in pairs(mod._idol_destroyed_collectible_keys) do
        if now - (destroyed_t or 0) > 60 then
            mod._idol_destroyed_collectible_keys[collectible_key] = nil
        end
    end

    for unit, destroyed_t in pairs(mod._idol_destroyed_units) do
        if now - (destroyed_t or 0) > 60 or not _safe_unit_alive(unit) then
            mod._idol_destroyed_units[unit] = nil
        end
    end
end

local function _track_point(id, kind, position, source, meta)
    if not id or not kind or not position then
        return
    end

    mod._tracked_points[id] = {
        kind = kind,
        source = source,
        position = position,
        meta = meta,
    }
end

local function _safe_navigation_handler_marked_by_slot(navigation_handler, level_index)
    local player_slot_by_level_marked = navigation_handler and navigation_handler.player_slot_by_level_marked

    if not player_slot_by_level_marked or level_index == nil then
        return nil
    end

    local ok, player_slot = pcall(player_slot_by_level_marked, navigation_handler, level_index)

    if ok then
        return player_slot
    end

    return nil
end

local function _safe_navigation_handler_level_completed(navigation_handler, level_index)
    local is_level_completed = navigation_handler and navigation_handler.is_level_completed

    if not is_level_completed or level_index == nil then
        return false
    end

    local ok, completed = pcall(is_level_completed, navigation_handler, level_index)

    return ok and completed == true or false
end

local function _safe_expedition_parent_level_data(section, parent_level_reference_name)
    if not section or not section.levels_data then
        return nil
    end

    local wanted_reference_name = parent_level_reference_name or "level"

    for i = 1, #section.levels_data do
        local level_data = section.levels_data[i]
        if level_data and level_data.reference_name == wanted_reference_name then
            return level_data
        end
    end

    return nil
end

local function _safe_expedition_level_slot_position(level_data)
    if not level_data then
        return nil
    end

    local section = level_data.section
    local custom_data = level_data.custom_data
    local level_slot_id = custom_data and custom_data.level_slot_id
    local parent_level_reference_name = level_data.parent_level_reference_name or "level"
    local parent_level_data = _safe_expedition_parent_level_data(section, parent_level_reference_name)
    local parent_level = parent_level_data and parent_level_data.level or nil

    if not parent_level or not level_slot_id or not Level or not Level.unit_by_id then
        return nil
    end

    local ok_unit, level_slot_unit = pcall(Level.unit_by_id, parent_level, level_slot_id)
    if not ok_unit or not level_slot_unit or not Unit or not Unit.world_position then
        return nil
    end

    local ok_position, world_position = pcall(Unit.world_position, level_slot_unit, 1)
    if ok_position and world_position then
        return _copy_vector3(world_position)
    end

    return nil
end

local function _track_expedition_registered_points(game_mode, navigation_handler, active_section_index, points, kind,
                                                   objective_tag)
    if type(points) ~= "table" then
        return
    end

    if kind == "expedition_objective_opportunity" then
        local location_id = 1

        for level_index, boxed_position in pairs(points) do
            local position = _safe_vector3_unbox(boxed_position)
            local is_active_section = _is_expedition_level_in_active_section(game_mode, active_section_index, level_index)
            local is_completed = _safe_navigation_handler_level_completed(navigation_handler, level_index)
            local section_index = is_active_section and
                _safe_expedition_section_index_by_level_index(game_mode, level_index) or nil

            if position and is_active_section and not is_completed then
                _track_point(
                    string_format("%s:%s", tostring(kind), tostring(level_index)),
                    kind,
                    position,
                    "expedition_navigation",
                    {
                        objective_icon = _expedition_opportunity_icon(level_index),
                        objective_title_icon = _expedition_opportunity_title_icon(location_id),
                        marked_by_player_slot = _safe_navigation_handler_marked_by_slot(navigation_handler, level_index),
                        expedition_level_index = level_index,
                        expedition_section_index = section_index,
                        objective_location_id = location_id,
                        objective_tag = objective_tag,
                    }
                )
            end

            if position and is_active_section then
                location_id = location_id + 1
            end
        end

        return
    end

    local entries = {}

    for level_index, boxed_position in pairs(points) do
        local position = _safe_vector3_unbox(boxed_position)

        if position and _is_expedition_level_in_active_section(game_mode, active_section_index, level_index) then
            entries[#entries + 1] = {
                level_index = level_index,
                position = position,
                section_index = _safe_expedition_section_index_by_level_index(game_mode, level_index),
            }
        end
    end

    table_sort(entries, function(a, b)
        local a_level_index = tonumber(a.level_index)
        local b_level_index = tonumber(b.level_index)

        if a_level_index ~= nil and b_level_index ~= nil and a_level_index ~= b_level_index then
            return a_level_index < b_level_index
        end

        if a_level_index ~= nil and b_level_index == nil then
            return true
        end

        if a_level_index == nil and b_level_index ~= nil then
            return false
        end

        return tostring(a.level_index) < tostring(b.level_index)
    end)

    for index = 1, #entries do
        local entry = entries[index]
        local level_index = entry.level_index
        local position = entry.position

        _track_point(
            string_format("%s:%s", tostring(kind), tostring(level_index)),
            kind,
            position,
            "expedition_navigation",
            {
                objective_icon = EXPEDITION_OBJECTIVE_ICON_DEFAULTS[kind],
                marked_by_player_slot = _safe_navigation_handler_marked_by_slot(navigation_handler, level_index),
                expedition_level_index = level_index,
                expedition_section_index = entry.section_index,
                objective_location_id = index,
                objective_tag = objective_tag,
            }
        )
    end
end

local function _track_expedition_tagged_levels(game_mode, navigation_handler, current_location_index, level_tag, kind)
    if not game_mode or not game_mode.get_all_levels_of_specified_tag or current_location_index == nil then
        return
    end

    local ok_levels, levels = pcall(game_mode.get_all_levels_of_specified_tag, game_mode, current_location_index,
        { [level_tag] = true })
    if not ok_levels or type(levels) ~= "table" then
        return
    end

    for i = 1, #levels do
        local level_data = levels[i]
        local position = _safe_expedition_level_slot_position(level_data)

        if position then
            local level_index = _safe_expedition_level_index(level_data and level_data.level or nil)

            _track_point(
                string_format("%s:%s:%s", tostring(kind), tostring(level_index or i),
                    tostring(level_data and level_data.reference_name or i)),
                kind,
                position,
                "expedition_level_tag",
                {
                    objective_icon = EXPEDITION_OBJECTIVE_ICON_DEFAULTS[kind],
                    marked_by_player_slot = _safe_navigation_handler_marked_by_slot(navigation_handler, level_index),
                    expedition_level_index = level_index,
                    objective_tag = level_tag,
                    reference_name = level_data and level_data.reference_name or nil,
                    level_name = level_data and level_data.level_name or nil,
                }
            )
        end
    end
end

local function _scan_expedition_objectives()
    mod._tracked_points = {}

    if not _is_expedition_runtime() then
        return
    end

    local game_mode = _safe_game_mode()
    if not game_mode then
        return
    end

    local navigation_handler = nil
    if game_mode.get_navigation_handler then
        local ok_navigation, value = pcall(game_mode.get_navigation_handler, game_mode)
        if ok_navigation then
            navigation_handler = value
        end
    end

    local current_location_index = nil
    if game_mode.current_location_index then
        local ok_location, value = pcall(game_mode.current_location_index, game_mode)
        if ok_location then
            current_location_index = value
        end
    end

    local active_section_index = _safe_expedition_active_section_index(game_mode) or current_location_index

    if navigation_handler and navigation_handler.get_registered_opportunities then
        local ok, opportunities = pcall(navigation_handler.get_registered_opportunities, navigation_handler)
        if ok then
            _track_expedition_registered_points(game_mode, navigation_handler, active_section_index, opportunities,
                "expedition_objective_opportunity", "type_opportunity")
        end
    end

    if navigation_handler and navigation_handler.get_registered_exits then
        local ok, exits = pcall(navigation_handler.get_registered_exits, navigation_handler)
        if ok then
            _track_expedition_registered_points(game_mode, navigation_handler, active_section_index, exits,
                "expedition_objective_transition", "type_transition")
        end
    end

    if navigation_handler and navigation_handler.get_registered_extractions then
        local ok, extractions = pcall(navigation_handler.get_registered_extractions, navigation_handler)
        if ok then
            _track_expedition_registered_points(game_mode, navigation_handler, active_section_index, extractions,
                "expedition_objective_extraction", "type_extraction")
        end
    end

    _track_expedition_tagged_levels(game_mode, navigation_handler, current_location_index, "type_main_objective",
        "expedition_objective_main_objective")
    _track_expedition_tagged_levels(game_mode, navigation_handler, current_location_index, "type_arrival",
        "expedition_objective_arrival")
end

local function _refresh_player_units()
    local player_manager = _player_manager()
    if not player_manager or not player_manager.players then
        return
    end

    local local_player = _local_player()

    for _, player in pairs(player_manager:players()) do
        local unit = player.player_unit
        if unit and _safe_unit_alive(unit) and player ~= local_player then
            local archetype_name = nil
            local player_name = nil
            local player_slot = _safe_player_slot(player)

            local ok_player_name, resolved_player_name = pcall(player.name, player)
            if ok_player_name then
                player_name = resolved_player_name
            end

            local ok_profile, profile = pcall(player.profile, player)
            if ok_profile and profile and profile.archetype and profile.archetype.name then
                archetype_name = profile.archetype.name
            end

            local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
            if unit_data_extension and unit_data_extension.archetype_name then
                local ok_archetype, value = pcall(unit_data_extension.archetype_name, unit_data_extension)
                if ok_archetype and value ~= nil then
                    archetype_name = value
                end
            end

            _track_unit(unit, "player_teammate", "player_manager", {
                player = player_name,
                player_slot = player_slot,
                archetype_name = archetype_name,
            })
        end
    end
end

local function _scan_interactees()
    local interactee_map = _safe_unit_to_extension_map("interactee_system")
    if not interactee_map then
        return
    end

    local player_unit = _player_unit()
    local tracked_units = mod._tracked_units
    local seen_interactees = {}

    for unit, extension in pairs(interactee_map) do
        if _safe_unit_alive(unit) and extension then
            seen_interactees[unit] = true

            local is_active = true
            local is_used = false
            local show_marker = true

            local active = extension.active
            if active then
                local ok_active, value = pcall(active, extension)
                if not ok_active or value ~= true then
                    is_active = false
                end
            end

            local used = extension.used
            if used then
                local ok_used, value = pcall(used, extension)
                if not ok_used or value == true then
                    is_used = true
                end
            end

            local show_marker_fn = extension.show_marker
            if show_marker_fn then
                if player_unit then
                    local ok_show, value = pcall(show_marker_fn, extension, player_unit)
                    if not ok_show or value ~= true then
                        show_marker = false
                    end
                else
                    show_marker = false
                end
            end

            if is_active and not is_used and show_marker then
                local kind, meta = _classify_interactee(extension, unit)
                if kind and (kind ~= "expedition_loot_converter" or _is_in_expedition_safe_zone()) then
                    _track_unit(unit, kind, "interactee_system", meta)
                else
                    _clear_tracked_unit_from_source(unit, "interactee_system")
                end
            else
                _clear_tracked_unit_from_source(unit, "interactee_system")
            end
        else
            _clear_tracked_unit_from_source(unit, "interactee_system")
        end
    end

    for unit, data in pairs(tracked_units) do
        if data and data.source == "interactee_system" and not seen_interactees[unit] then
            tracked_units[unit] = nil
        end
    end
end

local function _scan_chests()
    local chest_map = _safe_unit_to_extension_map("chest_system")
    if not chest_map then
        return
    end

    local tracked_units = mod._tracked_units
    local seen_chests = {}

    for unit, extension in pairs(chest_map) do
        if _safe_unit_alive(unit) and extension then
            seen_chests[unit] = true

            local is_open_fn = extension.is_open

            if is_open_fn then
                local ok_open, is_open = pcall(is_open_fn, extension)

                if ok_open and not is_open then
                    _track_unit(unit, "crate_unknown", "chest_system")
                else
                    _clear_tracked_unit_from_source(unit, "chest_system")
                end
            else
                _clear_tracked_unit_from_source(unit, "chest_system")
            end
        else
            _clear_tracked_unit_from_source(unit, "chest_system")
        end
    end

    for unit, data in pairs(tracked_units) do
        if data and data.source == "chest_system" and not seen_chests[unit] then
            tracked_units[unit] = nil
        end
    end
end

local function _scan_minions()
    local unit_data_map = _safe_unit_to_extension_map("unit_data_system")
    if not unit_data_map then
        return
    end

    for unit, extension in pairs(unit_data_map) do
        if _safe_unit_alive(unit) and extension then
            local breed_name_fn = extension.breed_name

            if breed_name_fn then
                local ok_breed, breed_name = pcall(breed_name_fn, extension)

                if ok_breed and breed_name then
                    local kind = _classify_enemy_from_breed(breed_name)
                    if kind and _is_trackable_unit_alive(unit, kind) then
                        _track_unit(unit, kind, "unit_data_system", {
                            breed_name = breed_name,
                        })
                    end
                end
            end
        end
    end
end

local function _scan_destructibles()
    local destructible_map = _safe_unit_to_extension_map("destructible_system")
    if not destructible_map then
        return
    end

    local tracked_units = mod._tracked_units
    local seen_destructibles = {}

    for unit, extension in pairs(destructible_map) do
        if _safe_unit_alive(unit) and extension then
            seen_destructibles[unit] = true

            local collectible_type = _safe_unit_collectible_type(unit)
            local collectible_data = _safe_destructible_collectible_data(extension)
            local collectible_id = collectible_data and collectible_data.id or nil
            local collectible_section_id = collectible_data and collectible_data.section_id or nil
            local collectible_name = collectible_data and collectible_data.name or nil
            local collectible_key = _idol_collectible_key(collectible_section_id, collectible_id)
            local extension_visible = _safe_destructible_visible(extension)
            local unit_visible = _safe_unit_main_visible(unit)
            local health_alive = _safe_health_alive(unit)
            local has_active_collectible = collectible_id ~= nil and collectible_section_id ~= nil
            local destroyed_by_event = mod._idol_destroyed_units[unit] ~= nil
                or (collectible_key ~= nil and mod._idol_destroyed_collectible_keys[collectible_key] ~= nil)

            if not destroyed_by_event and has_active_collectible and extension_visible == true and health_alive ~= false and unit_visible ~= false then
                _track_unit(unit, "pickup_heretic_idol", "destructible_system", {
                    collectible_type = collectible_type,
                    unit_name = _safe_lower_string(_safe_unit_name(unit)),
                    extension_visible = extension_visible,
                    unit_visible = unit_visible,
                    health_alive = health_alive,
                    collectible_id = collectible_id,
                    collectible_name = collectible_name,
                    collectible_section_id = collectible_section_id,
                })
            else
                _clear_tracked_unit_from_source(unit, "destructible_system")
            end
        else
            _clear_tracked_unit_from_source(unit, "destructible_system")
        end
    end

    for unit, data in pairs(tracked_units) do
        if data and data.source == "destructible_system" and not seen_destructibles[unit] then
            tracked_units[unit] = nil
        end
    end

    _prune_destroyed_idol_state()
end

local function _scan_smart_tag_targets()
    local smart_tag_map = _safe_unit_to_extension_map("smart_tag_system")
    if not smart_tag_map then
        return
    end

    for unit, extension in pairs(smart_tag_map) do
        if _safe_unit_alive(unit) and extension then
            local smart_tag_target_type = _safe_unit_smart_tag_target_type(unit)

            if smart_tag_target_type == "medical_crate_deployable" then
                _track_unit(unit, "medical_crate_deployable", "smart_tag_system", {
                    smart_tag_target_type = smart_tag_target_type,
                    deployable_type = _safe_unit_deployable_type(unit),
                    unit_name = _safe_lower_string(_safe_unit_name(unit)),
                })
            end
        end
    end
end

local function _prune_units()
    local now = _safe_gameplay_time() or 0
    local tracked_units = mod._tracked_units

    for unit, data in pairs(tracked_units) do
        if not _is_trackable_unit_alive(unit, data and data.kind) then
            tracked_units[unit] = nil
        else
            local last_seen_t = data.last_seen_t

            if last_seen_t and now - last_seen_t > 2.5 then
                tracked_units[unit] = nil
            else
                local position = _safe_unit_position(unit) or data.position

                if position then
                    data.position = position
                else
                    tracked_units[unit] = nil
                end
            end
        end
    end
end

local function _distance_squared_horizontal(a, b)
    if not a or not b then
        return math_huge
    end

    local ax, ay = a.x, a.y
    local bx, by = b.x, b.y

    if not _is_finite_number(ax) or not _is_finite_number(ay) then
        return math_huge
    end

    if not _is_finite_number(bx) or not _is_finite_number(by) then
        return math_huge
    end

    local dx = ax - bx
    local dy = ay - by

    return dx * dx + dy * dy
end

local function _vertical_delta(a, b)
    if not a or not b then
        return nil
    end

    local az = a.z
    local bz = b.z

    if not _is_finite_number(az) or not _is_finite_number(bz) then
        return nil
    end

    return bz - az
end

local ITEM_VERTICAL_ARROW_Z_DEADZONE = 2

local function _supports_vertical_item_marker(kind)
    if not kind then
        return false
    end

    if kind == "player_teammate" then
        return false
    end

    if _is_enemy_kind(kind) then
        return false
    end

    if _is_expedition_marker_kind(kind) then
        return false
    end

    return true
end

local function _expedition_loot_target_value(target)
    local meta = target and target.meta or nil
    local value = meta and tonumber(meta.remnant_value or meta.remnant_cluster_value) or nil

    if value and value > 0 then
        return value
    end

    local pickup_name = meta and meta.pickup_name or nil

    return _expedition_loot_value_for_pickup_name(pickup_name) or 0
end

local function _should_cluster_expedition_loot_target(target)
    return target ~= nil and target.kind == "material_expeditions_loot" and target.position ~= nil
end

local function _expedition_loot_cluster_center(cluster_members)
    local total_weight = 0
    local sum_x = 0
    local sum_y = 0
    local sum_z = 0
    local fallback_position = cluster_members[1] and cluster_members[1].position or nil

    for i = 1, #cluster_members do
        local member = cluster_members[i]
        local position = member and member.position

        if position then
            local weight = _expedition_loot_target_value(member)

            if weight <= 0 then
                weight = 1
            end

            total_weight = total_weight + weight
            sum_x = sum_x + position.x * weight
            sum_y = sum_y + position.y * weight
            sum_z = sum_z + (position.z or 0) * weight
        end
    end

    if total_weight <= 0 or not fallback_position then
        return fallback_position
    end

    return {
        x = sum_x / total_weight,
        y = sum_y / total_weight,
        z = sum_z / total_weight,
    }
end

local function _expedition_loot_vertical_state(player_pos, position, item_vertical_arrow_threshold_sq,
                                               item_vertical_hide_threshold)
    local vertical_delta = _vertical_delta(player_pos, position)
    local vertical_state = nil

    if vertical_delta ~= nil then
        local abs_vertical_delta = math_abs(vertical_delta)
        local distance_sq_horizontal = _distance_squared_horizontal(player_pos, position)

        if abs_vertical_delta >= item_vertical_hide_threshold then
            return nil, nil, true
        end

        if abs_vertical_delta >= ITEM_VERTICAL_ARROW_Z_DEADZONE
            and distance_sq_horizontal <= item_vertical_arrow_threshold_sq then
            if vertical_delta > 0 then
                vertical_state = "up"
            elseif vertical_delta < 0 then
                vertical_state = "down"
            end
        end
    end

    return vertical_delta, vertical_state, false
end

local function _create_expedition_loot_cluster_target(cluster_members, player_pos, item_vertical_arrow_threshold_sq,
                                                      item_vertical_hide_threshold)
    local position = _expedition_loot_cluster_center(cluster_members)

    if not position then
        return nil
    end

    local total_value = 0
    local cluster_count = 0
    local marked_by_player_slot = nil

    for i = 1, #cluster_members do
        local member = cluster_members[i]
        local meta = member and member.meta or nil

        cluster_count = cluster_count + 1
        total_value = total_value + _expedition_loot_target_value(member)

        if meta and meta.marked_by_player_slot ~= nil and marked_by_player_slot == nil then
            marked_by_player_slot = meta.marked_by_player_slot
        end
    end

    local vertical_delta, vertical_state, should_hide = _expedition_loot_vertical_state(player_pos, position,
        item_vertical_arrow_threshold_sq, item_vertical_hide_threshold)

    if should_hide then
        return nil
    end

    return {
        unit = nil,
        kind = "material_expeditions_loot",
        position = position,
        source = "expedition_loot_cluster",
        meta = {
            is_tech_remnant_cluster = true,
            remnant_cluster_count = cluster_count,
            remnant_cluster_value = total_value,
            remnant_value = total_value,
            remnant_show_value_text = cluster_count > 1,
            remnant_value_text = tostring(total_value),
            marked_by_player_slot = marked_by_player_slot,
        },
        distance_sq = _distance_squared_horizontal(player_pos, position),
        distance_sq_3d = _distance_squared(player_pos, position),
        vertical_delta = vertical_delta,
        vertical_state = vertical_state,
        ignore_radar_range = false,
    }
end

local function _cluster_expedition_loot_targets(targets, player_pos, item_vertical_arrow_threshold_sq,
                                                item_vertical_hide_threshold)
    if mod:get_expedition_loot_marker_mode() ~= "clustered" then
        return targets
    end

    local pass_through_targets = {}
    local cluster_candidates = {}
    local pass_count = 0
    local cluster_candidate_count = 0

    for i = 1, #targets do
        local target = targets[i]

        if _should_cluster_expedition_loot_target(target) then
            cluster_candidate_count = cluster_candidate_count + 1
            cluster_candidates[cluster_candidate_count] = target
        else
            pass_count = pass_count + 1
            pass_through_targets[pass_count] = target
        end
    end

    local horizontal_radius = mod:get_expedition_loot_cluster_horizontal_radius()
    local vertical_threshold = mod:get_expedition_loot_cluster_vertical_radius()
    local radius_sq = horizontal_radius * horizontal_radius
    local consumed = {}

    for i = 1, cluster_candidate_count do
        if not consumed[i] then
            local seed = cluster_candidates[i]
            local cluster_members = { seed }
            local cluster_member_count = 1

            consumed[i] = true

            local changed = true

            while changed do
                changed = false

                local center = _expedition_loot_cluster_center(cluster_members)

                for j = i + 1, cluster_candidate_count do
                    if not consumed[j] then
                        local candidate = cluster_candidates[j]
                        local distance_sq_horizontal = _distance_squared_horizontal(center, candidate.position)
                        local vertical_delta = _vertical_delta(center, candidate.position)
                        local abs_vertical_delta = vertical_delta and math_abs(vertical_delta) or 0

                        if distance_sq_horizontal <= radius_sq
                            and abs_vertical_delta <= vertical_threshold then
                            consumed[j] = true
                            cluster_member_count = cluster_member_count + 1
                            cluster_members[cluster_member_count] = candidate
                            changed = true
                        end
                    end
                end
            end

            if cluster_member_count > 1 then
                local clustered_target = _create_expedition_loot_cluster_target(cluster_members, player_pos,
                    item_vertical_arrow_threshold_sq, item_vertical_hide_threshold)

                if clustered_target then
                    pass_count = pass_count + 1
                    pass_through_targets[pass_count] = clustered_target
                else
                    for j = 1, cluster_member_count do
                        pass_count = pass_count + 1
                        pass_through_targets[pass_count] = cluster_members[j]
                    end
                end
            else
                pass_count = pass_count + 1
                pass_through_targets[pass_count] = seed
            end
        end
    end

    return pass_through_targets
end

local function _compare_radar_targets_by_distance(a, b)
    return (a.distance_sq or math_huge) < (b.distance_sq or math_huge)
end

local function _compare_radar_targets_boss_first(a, b)
    local a_is_boss = _is_boss_marker_kind(a.kind)
    local b_is_boss = _is_boss_marker_kind(b.kind)

    if a_is_boss ~= b_is_boss then
        return a_is_boss
    end

    return (a.distance_sq or math_huge) < (b.distance_sq or math_huge)
end

local function _collect_radar_targets()
    local player_unit = _player_unit()
    if not _safe_unit_alive(player_unit) then
        return {}
    end

    local player_pos = _safe_unit_position(player_unit)
    if not player_pos then
        return {}
    end

    local max_range = mod:get_radar_range()
    local max_range_sq = max_range * max_range
    local max_markers = mod:get_max_radar_markers()
    local item_vertical_arrow_threshold = mod:get_item_vertical_arrow_threshold()
    local item_vertical_hide_threshold = mod:get_item_vertical_hide_threshold()
    local item_vertical_arrow_threshold_sq = item_vertical_arrow_threshold * item_vertical_arrow_threshold
    local tracked_units = mod._tracked_units
    local tracked_points = mod._tracked_points
    local targets = {}
    local target_count = 0

    local function append_target(unit, data)
        local position = data and data.position
        local kind = data and data.kind

        if not position or not kind or not _kind_enabled(kind) then
            return
        end

        if kind == "pickup_heretic_idol" and data.source == "destructible_system" then
            local meta = data.meta

            if not meta or meta.collectible_id == nil then
                return
            end
        end

        local distance_sq_horizontal = _distance_squared_horizontal(player_pos, position)
        local ignore_range = _ignore_radar_range_for_kind(kind)

        if distance_sq_horizontal > max_range_sq and not ignore_range then
            return
        end

        local vertical_delta = nil
        local vertical_state = nil

        if _supports_vertical_item_marker(kind) then
            vertical_delta = _vertical_delta(player_pos, position)

            if vertical_delta ~= nil then
                local abs_vertical_delta = math_abs(vertical_delta)

                if abs_vertical_delta >= item_vertical_hide_threshold then
                    return
                end

                if abs_vertical_delta >= ITEM_VERTICAL_ARROW_Z_DEADZONE
                    and distance_sq_horizontal <= item_vertical_arrow_threshold_sq then
                    if vertical_delta > 0 then
                        vertical_state = "up"
                    elseif vertical_delta < 0 then
                        vertical_state = "down"
                    end
                end
            end
        end

        target_count = target_count + 1
        targets[target_count] = {
            unit = unit,
            kind = kind,
            position = position,
            source = data.source,
            meta = data.meta,
            distance_sq = distance_sq_horizontal,
            distance_sq_3d = _distance_squared(player_pos, position),
            vertical_delta = vertical_delta,
            vertical_state = vertical_state,
            ignore_radar_range = ignore_range,
        }
    end

    for unit, data in pairs(tracked_units) do
        if _is_trackable_unit_alive(unit, data and data.kind) then
            append_target(unit, data)
        end
    end

    for id, data in pairs(tracked_points) do
        append_target(id, data)
    end

    mod._unclustered_radar_targets = targets
    mod._highlight_source_radar_targets = _copy_target_list(targets)

    targets = _cluster_expedition_loot_targets(targets, player_pos, item_vertical_arrow_threshold_sq,
        item_vertical_hide_threshold)

    if mod:get_boss_marker_range_mode() == "infinite" then
        table_sort(targets, _compare_radar_targets_boss_first)
    else
        table_sort(targets, _compare_radar_targets_by_distance)
    end

    local target_total = #targets

    if target_total > max_markers then
        for i = target_total, max_markers + 1, -1 do
            targets[i] = nil
        end
    end

    return targets
end

local function _collect_radar_snapshot()
    local player_unit = _player_unit()
    if not _safe_unit_alive(player_unit) then
        return nil
    end

    local player_pos = _safe_unit_position(player_unit)
    if not player_pos then
        return nil
    end

    local local_player = _local_player()

    return {
        player_unit = player_unit,
        player_position = player_pos,
        player_rotation = _safe_player_rotation(player_unit),
        player_slot = _safe_player_slot(local_player),
        targets = mod._radar_targets,
        screen_highlights = mod._screen_highlight_targets,
    }
end

local function _debug_log_scan()
    if mod:get("debug_mode") ~= true then
        return
    end

    local counts = {
        enemies = 0,
        players = 0,
        ammo = 0,
        crates = 0,
        pocketables = 0,
        materials = 0,
        generic = 0,
    }

    for unit, data in pairs(mod._tracked_units) do
        if _safe_unit_alive(unit) and data.kind then
            local kind = data.kind

            if _string_starts_with(kind, "enemy_") then
                counts.enemies = counts.enemies + 1
            elseif kind == "player_teammate" then
                counts.players = counts.players + 1
            elseif kind == "crate_unknown" then
                counts.crates = counts.crates + 1
            elseif _string_starts_with(kind, "pocketable_") then
                counts.pocketables = counts.pocketables + 1
            elseif _string_starts_with(kind, "material_") then
                counts.materials = counts.materials + 1
            elseif string_find(kind, "ammo", 1, true) then
                counts.ammo = counts.ammo + 1
            else
                counts.generic = counts.generic + 1
            end
        end
    end

    local signature = table_concat({
        tostring(counts.enemies),
        tostring(counts.players),
        tostring(counts.ammo),
        tostring(counts.crates),
        tostring(counts.pocketables),
        tostring(counts.materials),
        tostring(counts.generic),
        tostring(#mod._radar_targets),
        tostring(_safe_mission_name()),
        tostring(_safe_presence_activity()),
        tostring(_safe_mechanism_name()),
    }, "|")

    if signature == mod._last_scan_signature then
        return
    end

    mod._last_scan_signature = signature

    mod:echo(string_format(
        "Radar scan | enemies=%d players=%d ammo=%d crates=%d pocketables=%d materials=%d generic=%d tracked=%d radar_targets=%d mission=%s activity=%s mechanism=%s",
        counts.enemies,
        counts.players,
        counts.ammo,
        counts.crates,
        counts.pocketables,
        counts.materials,
        counts.generic,
        _table_size(mod._tracked_units),
        #mod._radar_targets,
        tostring(_safe_mission_name()),
        tostring(_safe_presence_activity()),
        tostring(_safe_mechanism_name())
    ))
end

local function _reset_runtime_state()
    mod._screen_highlight_targets = {}
    mod._unclustered_radar_targets = {}
    mod._highlight_source_radar_targets = {}
    mod._next_scan_t = 0
    mod._tracked_units = {}
    mod._tracked_points = {}
    mod._logged_units = {}
    mod._radar_targets = {}
    mod._radar_snapshot = nil
    mod._last_update_t = nil
    mod._last_scan_signature = nil
    mod._last_block_signature = nil
    mod._last_state_gameplay = nil
    mod._idol_destroyed_collectible_keys = {}
    mod._idol_destroyed_units = {}
end

local function _debug_log_block(reason, gameplay_t, mission_name, activity, mechanism_name)
    if mod:get("debug_mode") ~= true then
        return
    end

    local signature = table_concat({
        tostring(reason),
        tostring(mission_name),
        tostring(activity),
        tostring(mechanism_name),
        tostring(gameplay_t),
    }, "|")

    if signature == mod._last_block_signature then
        return
    end

    mod._last_block_signature = signature
    mod:echo(string_format(
        "Radar blocked | reason=%s mission=%s activity=%s mechanism=%s gameplay_t=%s",
        tostring(reason),
        tostring(mission_name),
        tostring(activity),
        tostring(mechanism_name),
        tostring(gameplay_t)
    ))
end

local function _update_internal(dt, t)
    if mod:get("enable_radar") == false then
        mod._tracked_points = {}
        mod._radar_targets = {}
        mod._screen_highlight_targets = {}
        mod._unclustered_radar_targets = {}
        mod._highlight_source_radar_targets = {}
        mod._radar_snapshot = nil
        return
    end

    local allowed, reason, gameplay_t, mission_name, activity, mechanism_name, player_unit, player_pos =
        _get_runtime_state()
    local scan_clock = gameplay_t or t or 0

    if mod._last_update_t and scan_clock and scan_clock == mod._last_update_t then
        return
    end
    mod._last_update_t = scan_clock

    if not allowed then
        if reason == "player_not_alive" or reason == "player_captured" or reason == "no_player_unit" then
            mod._tracked_units = {}
        end

        mod._tracked_points = {}
        mod._radar_targets = {}
        mod._screen_highlight_targets = {}
        mod._unclustered_radar_targets = {}
        mod._highlight_source_radar_targets = {}
        mod._radar_snapshot = nil
        _debug_log_block(reason, gameplay_t, mission_name, activity, mechanism_name)
        return
    end

    mod._radar_snapshot = {
        player_unit = player_unit,
        player_position = player_pos,
        player_rotation = _safe_player_rotation(player_unit),
        player_slot = _safe_player_slot(_local_player()),
        targets = mod._radar_targets,
        screen_highlights = mod._screen_highlight_targets,
    }

    if scan_clock < (mod._next_scan_t or 0) then
        return
    end

    mod._next_scan_t = scan_clock + SCAN_INTERVAL

    _scan_interactees()
    _scan_chests()
    _scan_minions()
    _scan_destructibles()
    _scan_smart_tag_targets()
    _refresh_player_units()
    _scan_expedition_objectives()
    _prune_units()

    mod._radar_targets = _collect_radar_targets()
    mod._screen_highlight_targets = _collect_screen_highlight_targets()
    mod._radar_snapshot = _collect_radar_snapshot()

    _debug_log_scan()
end

mod.on_game_state_changed = function(status, state_name)
    if status == "enter" and state_name == "GameplayStateRun" then
        mod._gameplay_run = true
        mod._next_scan_t = 0
        mod._last_update_t = nil
        return
    end

    if status == "exit" and state_name == "GameplayStateRun" then
        mod._gameplay_run = false
        _reset_runtime_state()
        return
    end

    if status == "enter" and (
            state_name == "StateLoading" or
            state_name == "StateMainMenu" or
            state_name == "StateTitle" or
            state_name == "StateGameplay" or
            state_name == "GameplayStateInit"
        ) then
        mod._gameplay_run = false
        _reset_runtime_state()
    end
end

mod:register_hud_element({
    class_name = "HudElementRadar",
    filename = "Radar/scripts/mods/Radar/ui/hud_element_radar",
    visibility_groups = { "alive" },
    use_hud_scale = true,
})

mod:hook_safe("StateGameplay", "update", function(self, dt, t, ...)
    mod._last_state_gameplay = self
    _update_internal(dt, t)
end)

mod:hook_safe("CollectiblesManager", "rpc_player_destroyed_destructible_collectible",
    function(self, channel_id, peer_id, local_player_id, section_id, id)
        _clear_tracked_idol_by_collectible(section_id, id)
    end)

mod:hook_safe("CollectiblesManager", "collectible_destroyed", function(self, data, attacking_unit)
    if data then
        _clear_tracked_idol_by_collectible(data.section_id, data.id)
    end
end)

mod:hook_safe("DestructibleExtension", "rpc_destructible_last_destruction", function(self)
    _mark_idol_unit_destroyed(self and self._unit or nil, self)
end)

mod:hook_safe("DestructibleExtension", "rpc_sync_destructible",
    function(self, current_stage, visible, from_hot_join_sync)
        if current_stage == 0 then
            _mark_idol_unit_destroyed(self and self._unit or nil, self)
        end
    end)

mod.update = function(dt)
    if not mod._gameplay_run then
        return
    end

    _update_internal(dt, _safe_gameplay_time())
end

function mod:get_player_display_style()
    local value = tostring(self:get("player_display_style") or "marked_icon")

    if value ~= "icon_only"
        and value ~= "marked_icon"
        and value ~= "dot_only"
        and value ~= "marked_dot" then
        value = "marked_icon"
    end

    return value
end

function mod:get_radar_snapshot()
    return self._radar_snapshot
end

function mod:get_screen_highlight_targets()
    return self._screen_highlight_targets or {}
end

function mod:should_draw_radar()
    if self:get("enable_radar") == false then
        return false
    end

    if not _is_local_player_alive() then
        return false
    end

    if _is_local_player_captured() then
        return false
    end

    return _is_allowed_runtime()
end

function mod:get_radar_size()
    return self:get("radar_size") or 220
end

function mod:get_radar_range()
    local value = tonumber(self:get("radar_range")) or 40

    if value < 25 then
        value = 25
    elseif value > 100 then
        value = 100
    end

    return value
end

function mod:get_max_radar_markers()
    local value = tonumber(self:get("max_radar_markers")) or 64

    if value < 10 then
        value = 10
    elseif value > 100 then
        value = 100
    end

    return math_floor(value)
end

function mod:get_background_opacity()
    local value = tonumber(self:get("background_opacity")) or 90

    if value < 0 then
        value = 0
    elseif value > 255 then
        value = 255
    end

    return math_floor(value)
end

function mod:get_boss_marker_range_mode()
    local value = tostring(self:get("boss_marker_range_mode") or "normal")

    if value ~= "infinite" then
        value = "normal"
    end

    return value
end

function mod:get_expedition_loot_marker_mode()
    local value = tostring(self:get("expedition_loot_marker_mode") or "default")

    if value ~= "scaled" and value ~= "clustered" then
        value = "default"
    end

    return value
end

function mod:get_show_expedition_loot_cluster_value()
    return self:get("show_expedition_loot_cluster_value") == true
end

function mod:get_show_expedition_loot_value_text()
    return self:get_show_expedition_loot_cluster_value()
end

function mod:get_expedition_loot_cluster_horizontal_radius()
    local value = tonumber(self:get("expedition_loot_cluster_horizontal_radius")) or 5

    if value < 1 then
        value = 1
    elseif value > 10 then
        value = 10
    end

    return value
end

function mod:get_expedition_loot_cluster_vertical_radius()
    local value = tonumber(self:get("expedition_loot_cluster_vertical_radius")) or 3

    if value < 1 then
        value = 1
    elseif value > 5 then
        value = 5
    end

    return value
end

function mod:get_item_vertical_arrow_threshold()
    local value = tonumber(self:get("item_vertical_arrow_threshold")) or 25

    if value < 25 then
        value = 25
    elseif value > 100 then
        value = 100
    end

    return value
end

function mod:get_item_vertical_hide_threshold()
    local value = tonumber(self:get("item_vertical_hide_threshold")) or 12

    if value < 8 then
        value = 8
    elseif value > 50 then
        value = 50
    end

    return value
end

function mod:get_radar_style()
    local value = tostring(self:get("radar_style") or "square")

    if value ~= "circle" then
        value = "square"
    end

    return value
end

function mod:get_radar_outline()
    local value = tostring(self:get("radar_outline") or "solid")

    if value ~= "solid" and value ~= "dotted" and value ~= "off" then
        value = "solid"
    end

    return value
end

function mod:get_radar_guides()
    local value = tostring(self:get("radar_guides") or "crosshair")

    if value ~= "crosshair" and value ~= "view_guides" and value ~= "range_rings" and value ~= "off" then
        value = "crosshair"
    end

    return value
end

function mod:get_radar_move_step()
    local value = tonumber(self:get("radar_move_step")) or DEFAULT_RADAR_MOVE_STEP

    if value < 1 then
        value = 1
    elseif value > 200 then
        value = 200
    end

    return math_floor(value)
end

function mod:get_radar_anchor()
    return _normalize_radar_anchor(self:get("radar_anchor"))
end

function mod:is_radar_position_unrestricted()
    return self:get("unrestricted_radar_position") == true
end

function mod:get_radar_offset_x(size)
    local radar_size = tonumber(size) or self:get_radar_size()
    local max_x = _get_radar_position_bounds(radar_size)
    local value = self:get("radar_pos_x")

    return _resolve_radar_position_value(
        value,
        DEFAULT_RADAR_POS_X,
        0,
        max_x,
        self:is_radar_position_unrestricted()
    )
end

function mod:get_radar_offset_y(size)
    local radar_size = tonumber(size) or self:get_radar_size()
    local _, max_y = _get_radar_position_bounds(radar_size)
    local value = self:get("radar_pos_y")

    return _resolve_radar_position_value(
        value,
        DEFAULT_RADAR_POS_Y,
        0,
        max_y,
        self:is_radar_position_unrestricted()
    )
end

function mod:get_radar_pos_x(size)
    local radar_size = tonumber(size) or self:get_radar_size()
    local anchor = self:get_radar_anchor()
    local offset_x = self:get_radar_offset_x(radar_size)
    local offset_y = self:get_radar_offset_y(radar_size)
    local x = _get_radar_origin_from_offsets(anchor, offset_x, offset_y, radar_size)

    return math_floor(x + 0.5)
end

function mod:get_radar_pos_y(size)
    local radar_size = tonumber(size) or self:get_radar_size()
    local anchor = self:get_radar_anchor()
    local offset_x = self:get_radar_offset_x(radar_size)
    local offset_y = self:get_radar_offset_y(radar_size)
    local _, y = _get_radar_origin_from_offsets(anchor, offset_x, offset_y, radar_size)

    return math_floor(y + 0.5)
end

function mod:has_any_nearby_highlight_enabled()
    for _, setting_id in pairs(NEARBY_HIGHLIGHT_SETTING_BY_GROUP) do
        if self:get(setting_id) == true then
            return true
        end
    end

    return false
end

function mod:get_nearby_highlight_range()
    local value = tonumber(self:get("highlight_distance")) or 10

    if value < 5 then
        value = 5
    elseif value > 20 then
        value = 20
    end

    return value
end

function mod:is_nearby_highlight_enabled_for_kind(kind)
    if not kind or not _kind_enabled(kind) then
        return false
    end

    local group_name = self:get_marker_scale_group(kind)
    local setting_id = group_name and NEARBY_HIGHLIGHT_SETTING_BY_GROUP[group_name] or nil

    if not setting_id then
        return false
    end

    return self:get(setting_id) == true
end

function mod:set_radar_position(x, y)
    local radar_size = self:get_radar_size()
    local max_x, max_y = _get_radar_position_bounds(radar_size)
    local unrestricted = self:is_radar_position_unrestricted()
    local offset_x = self:get_radar_offset_x(radar_size)
    local offset_y = self:get_radar_offset_y(radar_size)

    if x ~= nil then
        offset_x = _resolve_radar_position_value(x, DEFAULT_RADAR_POS_X, 0, max_x, unrestricted)
        self:set("radar_pos_x", offset_x)
    end

    if y ~= nil then
        offset_y = _resolve_radar_position_value(y, DEFAULT_RADAR_POS_Y, 0, max_y, unrestricted)
        self:set("radar_pos_y", offset_y)
    end

    local anchor = self:get_radar_anchor()
    local resolved_x, resolved_y = _get_radar_origin_from_offsets(anchor, offset_x, offset_y, radar_size)

    if mod:get("debug_mode") == true then
        self:notify(
            "Radar anchor %s | offset X %d | offset Y %d | origin X %d | origin Y %d",
            anchor,
            offset_x,
            offset_y,
            resolved_x,
            resolved_y
        )
    end

    return resolved_x, resolved_y
end

function mod:set_radar_origin(x, y)
    local radar_size = self:get_radar_size()
    local anchor = self:get_radar_anchor()
    local max_x, max_y = _get_radar_position_bounds(radar_size)
    local unrestricted = self:is_radar_position_unrestricted()

    local resolved_x = _resolve_radar_position_value(x, DEFAULT_RADAR_POS_X, 0, max_x, unrestricted)
    local resolved_y = _resolve_radar_position_value(y, DEFAULT_RADAR_POS_Y, 0, max_y, unrestricted)
    local offset_x, offset_y = _get_radar_offsets_from_origin(anchor, resolved_x, resolved_y, radar_size)

    offset_x = _resolve_radar_position_value(offset_x, DEFAULT_RADAR_POS_X, 0, max_x, unrestricted)
    offset_y = _resolve_radar_position_value(offset_y, DEFAULT_RADAR_POS_Y, 0, max_y, unrestricted)

    self:set("radar_pos_x", offset_x)
    self:set("radar_pos_y", offset_y)

    if mod:get("debug_mode") == true then
        self:notify(
            "Radar anchor %s | offset X %d | offset Y %d | origin X %d | origin Y %d",
            anchor,
            self:get_radar_offset_x(radar_size),
            self:get_radar_offset_y(radar_size),
            resolved_x,
            resolved_y
        )
    end

    return resolved_x, resolved_y
end

function mod:set_radar_anchor(anchor, preserve_visual_position)
    local radar_size = self:get_radar_size()
    local current_x = self:get_radar_pos_x(radar_size)
    local current_y = self:get_radar_pos_y(radar_size)
    local normalized_anchor = _normalize_radar_anchor(anchor)

    self:set("radar_anchor", normalized_anchor)

    if preserve_visual_position then
        return self:set_radar_origin(current_x, current_y)
    end

    return self:set_radar_position(self:get("radar_pos_x"), self:get("radar_pos_y"))
end

function mod:nudge_radar(dx, dy)
    local x = self:get_radar_pos_x()
    local y = self:get_radar_pos_y()

    return self:set_radar_origin(x + (tonumber(dx) or 0), y + (tonumber(dy) or 0))
end

function mod:set_radar_enabled(enabled)
    local is_enabled = enabled == true

    self:set("enable_radar", is_enabled)

    if not is_enabled then
        self._radar_targets = {}
        self._screen_highlight_targets = {}
        self._highlight_source_radar_targets = {}
        self._unclustered_radar_targets = {}
        self._radar_snapshot = nil
    end

    if mod:get("debug_mode") == true then
        self:notify("Radar %s", is_enabled and "enabled" or "disabled")
    end

    return is_enabled
end

function mod.toggle_radar_keybind(_)
    local current_value = mod:get("enable_radar") ~= false

    return mod:set_radar_enabled(not current_value)
end

function mod.move_radar_left(_)
    return mod:nudge_radar(-mod:get_radar_move_step(), 0)
end

function mod.move_radar_right(_)
    return mod:nudge_radar(mod:get_radar_move_step(), 0)
end

function mod.move_radar_up(_)
    return mod:nudge_radar(0, -mod:get_radar_move_step())
end

function mod.move_radar_down(_)
    return mod:nudge_radar(0, mod:get_radar_move_step())
end

function mod:get_radar_origin(size)
    local radar_size = tonumber(size) or self:get_radar_size()
    local x = self:get_radar_pos_x(radar_size)
    local y = self:get_radar_pos_y(radar_size)
    local z = 200
    local radius = radar_size / 2

    return x, y, z, radius
end

function mod:project_target_to_radar(player_pos, player_rot, target_pos, max_radius, range, ignore_radar_range)
    if not player_pos or not target_pos then
        return nil, nil
    end

    range = tonumber(range) or 40
    max_radius = tonumber(max_radius) or 0
    if range <= 0 or max_radius <= 0 then
        return nil, nil
    end

    local dx = target_pos.x - player_pos.x
    local dy = target_pos.y - player_pos.y
    if not _is_finite_number(dx) or not _is_finite_number(dy) then
        return nil, nil
    end

    local distance_sq_horizontal = dx * dx + dy * dy
    if not _is_finite_number(distance_sq_horizontal) then
        return nil, nil
    end

    local outside_range = distance_sq_horizontal > range * range
    if outside_range and not ignore_radar_range then
        return nil, nil
    end

    local local_x = dx
    local local_y = dy

    local forward_x, forward_y = _safe_forward_xy(player_rot)

    if forward_x and forward_y then
        -- Derive a flattened right vector from forward instead of relying on
        -- Quaternion.right. This matches the compass math more closely and keeps
        -- the radar in the same 2D basis as the live camera facing.
        local right_x = forward_y
        local right_y = -forward_x

        local_x = dx * right_x + dy * right_y
        local_y = dx * forward_x + dy * forward_y
    end

    local radar_scale = max_radius / range
    local px = local_x * radar_scale
    local py = -local_y * radar_scale
    if not _is_finite_number(px) or not _is_finite_number(py) then
        return nil, nil
    end

    if outside_range then
        local radar_style = self.get_radar_style and self:get_radar_style() or "square"

        if radar_style == "circle" then
            local projected_distance = math_sqrt(px * px + py * py)
            if projected_distance > 0 then
                local circle_scale = max_radius / projected_distance
                px = px * circle_scale
                py = py * circle_scale
            end
        else
            local max_component = math_max(math_abs(px), math_abs(py))
            if max_component > 0 then
                local square_scale = max_radius / max_component
                px = px * square_scale
                py = py * square_scale
            end
        end
    end

    return px, py
end

return mod
