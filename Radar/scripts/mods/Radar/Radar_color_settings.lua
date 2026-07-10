local ColorSettings = {}

local math_floor = math.floor
local tonumber = tonumber

local function _color(a, r, g, b)
    return { a, r, g, b }
end

local WHITE = _color(255, 255, 255, 255)
local RADAR_OUTLINE = _color(255, 213, 226, 206)
local AUSPEX_GREEN = _color(255, 0, 255, 0)

local marker_prefix_by_kind = {}
local marker_background_prefix_by_kind = {}
local marker_highlight_prefix_by_kind = {}
local enemy_icon_prefix_by_kind = {}
local default_by_prefix = {}
local highlight_prefixes = {}
local opacity_setting_by_prefix = {
    radar_background = "radar_background_opacity",
}
local legacy_opacity_setting_by_prefix = {
    radar_background = "background_opacity",
}
local anchored_color_settings = {}

local function _copy_color(color)
    return {
        color[1] or 255,
        color[2] or 255,
        color[3] or 255,
        color[4] or 255,
    }
end

local function _add_default(prefix, color)
    if prefix and color and default_by_prefix[prefix] == nil then
        default_by_prefix[prefix] = _copy_color(color)
    end
end

local function _add_anchor(anchor, descriptor)
    if not anchor then
        return
    end

    local anchored = anchored_color_settings[anchor]

    if anchored == nil then
        anchored = {}
        anchored_color_settings[anchor] = anchored
    end

    anchored[#anchored + 1] = descriptor
end

local function _add_marker(descriptor)
    local kind = descriptor.kind
    local prefix = descriptor.prefix or descriptor.icon_prefix or (kind and kind .. "_marker")
    local default = descriptor.icon_prefix and (descriptor.icon_default or descriptor.default or WHITE) or
        (descriptor.default or WHITE)
    local aliases = descriptor.aliases

    _add_default(prefix, default)

    if kind then
        marker_prefix_by_kind[kind] = prefix
    end

    if aliases then
        for i = 1, #aliases do
            marker_prefix_by_kind[aliases[i]] = prefix
        end
    end

    _add_anchor(descriptor.anchor, {
        prefix = prefix,
        default = default,
        title_prefix = descriptor.title_prefix or "marker_color",
        tooltip = descriptor.tooltip or (descriptor.icon_prefix and "icon_marker_color_slider_tooltip" or
            "marker_color_slider_tooltip"),
        channels = descriptor.channels,
        label_role = descriptor.label_role or "icon",
        label_prefix = descriptor.label_prefix,
        label_suffix = descriptor.label_suffix,
    })

    if descriptor.background_prefix then
        _add_default(descriptor.background_prefix, descriptor.background_default or default)
        marker_background_prefix_by_kind[kind] = descriptor.background_prefix

        _add_anchor(descriptor.anchor, {
            prefix = descriptor.background_prefix,
            default = descriptor.background_default or default,
            title_prefix = "marker_background_color",
            tooltip = "marker_background_color_slider_tooltip",
            label_role = "background",
            label_prefix = descriptor.label_prefix,
        })
    end

    if descriptor.supports_highlight then
        local highlight_prefix = descriptor.highlight_prefix or (kind and kind .. "_highlight")
        local highlight_default = descriptor.highlight_default or default

        _add_default(highlight_prefix, highlight_default)
        highlight_prefixes[#highlight_prefixes + 1] = highlight_prefix
        marker_highlight_prefix_by_kind[kind] = highlight_prefix

        if aliases then
            for i = 1, #aliases do
                marker_highlight_prefix_by_kind[aliases[i]] = highlight_prefix
            end
        end

        _add_anchor(descriptor.anchor, {
            prefix = highlight_prefix,
            default = highlight_default,
            title_prefix = "highlight_color",
            tooltip = "highlight_color_slider_tooltip",
            label_role = "highlight",
            label_prefix = descriptor.label_prefix,
        })
    end
end

local function _add_radar_color(anchor, prefix, default, title_prefix, tooltip, channels)
    _add_default(prefix, default)
    _add_anchor(anchor, {
        prefix = prefix,
        default = default,
        title_prefix = title_prefix,
        tooltip = tooltip or "radar_color_slider_tooltip",
        channels = channels,
    })
end

local function _add_enemy_kind(kind, icon_prefix)
    enemy_icon_prefix_by_kind[kind] = icon_prefix
end

local function _add_enemy_kinds(icon_prefix, kinds)
    for i = 1, #kinds do
        _add_enemy_kind(kinds[i], icon_prefix)
    end
end

_add_radar_color("radar_colors_group", "radar_background", _color(90, 0, 0, 0), "radar_background_color",
    "radar_background_color_slider_tooltip")
_add_radar_color("radar_colors_group", "radar_outline", RADAR_OUTLINE, "radar_outline_color")
_add_radar_color("radar_colors_group", "radar_guides", _color(90, 255, 255, 255), "radar_guides_color")
_add_radar_color("radar_colors_group", "auspex_background", AUSPEX_GREEN, "auspex_background_color")
_add_radar_color("radar_colors_group", "auspex_noise", AUSPEX_GREEN, "auspex_noise_color")
_add_radar_color("radar_colors_group", "auspex_scan_noise", _color(90, 0, 255, 0), "auspex_scan_noise_color")
_add_radar_color("radar_colors_group", "auspex_sweep", _color(128, 0, 255, 0), "auspex_sweep_color")
_add_radar_color("radar_colors_group", "auspex_frame", _color(210, 0, 255, 0), "auspex_frame_color")
_add_radar_color("radar_colors_group", "auspex_frame_dotted", _color(190, 0, 255, 0), "auspex_dotted_frame_color")
_add_radar_color("radar_colors_group", "auspex_inner_glow", _color(80, 0, 255, 0), "auspex_inner_glow_color")
_add_radar_color("radar_colors_group", "marker_value_text", _color(255, 255, 225, 0), "marker_value_text_color")
_add_radar_color("radar_colors_group", "marker_distance_text", _color(255, 255, 225, 0), "marker_distance_text_color")
_add_radar_color("radar_colors_group", "vertical_arrow", WHITE, "vertical_arrow_color")
_add_radar_color("radar_colors_group", "radar_legend_indicator", RADAR_OUTLINE, "radar_legend_indicator_color")
_add_radar_color("radar_colors_group", "radar_zoom_indicator", _color(210, 0, 255, 0),
    "radar_zoom_indicator_color")

_add_default("enemy_boss_marker", _color(255, 255, 64, 64))
_add_default("enemy_boss_background", _color(220, 255, 0, 0))
_add_default("enemy_background_marker", _color(220, 255, 0, 0))
_add_default("enemy_scab_marker", WHITE)
_add_default("enemy_dreg_marker", _color(255, 255, 255, 0))
_add_default("enemy_tox_marker", _color(255, 0, 255, 0))
_add_default("enemy_mutator_marker", _color(255, 150, 190, 60))
_add_default("enemy_armored_hound_marker", _color(255, 150, 150, 150))
_add_default("enemy_renegade_flamer_marker", _color(255, 255, 102, 0))
_add_default("enemy_horde_marker", _color(220, 255, 0, 0))

_add_anchor("show_enemy_boss_vertical_arrows", {
    prefix = "enemy_boss_marker",
    default = default_by_prefix.enemy_boss_marker,
    title_prefix = "enemy_boss_marker_color",
    tooltip = "enemy_marker_color_slider_tooltip",
})
_add_anchor("show_enemy_boss_vertical_arrows", {
    prefix = "enemy_boss_background",
    default = default_by_prefix.enemy_boss_background,
    title_prefix = "enemy_boss_background_color",
    tooltip = "enemy_background_color_slider_tooltip",
})
_add_anchor("enemies_icon_scale", {
    prefix = "enemy_background_marker",
    default = default_by_prefix.enemy_background_marker,
    title_prefix = "enemy_marked_background_color",
    tooltip = "enemy_background_color_slider_tooltip",
})
_add_anchor("enemies_icon_scale", {
    prefix = "enemy_scab_marker",
    default = default_by_prefix.enemy_scab_marker,
    title_prefix = "enemy_scab_color",
    tooltip = "enemy_marker_color_slider_tooltip",
})
_add_anchor("enemies_icon_scale", {
    prefix = "enemy_dreg_marker",
    default = default_by_prefix.enemy_dreg_marker,
    title_prefix = "enemy_dreg_color",
    tooltip = "enemy_marker_color_slider_tooltip",
})
_add_anchor("enemies_icon_scale", {
    prefix = "enemy_tox_marker",
    default = default_by_prefix.enemy_tox_marker,
    title_prefix = "enemy_tox_color",
    tooltip = "enemy_marker_color_slider_tooltip",
})
_add_anchor("enemies_icon_scale", {
    prefix = "enemy_mutator_marker",
    default = default_by_prefix.enemy_mutator_marker,
    title_prefix = "enemy_mutator_color",
    tooltip = "enemy_marker_color_slider_tooltip",
})
_add_anchor("show_enemy_chaos_armored_hound", {
    prefix = "enemy_armored_hound_marker",
    default = default_by_prefix.enemy_armored_hound_marker,
    title_prefix = "enemy_armored_hound_color",
    tooltip = "enemy_marker_color_slider_tooltip",
})
_add_anchor("show_enemy_renegade_flamer", {
    prefix = "enemy_renegade_flamer_marker",
    default = default_by_prefix.enemy_renegade_flamer_marker,
    title_prefix = "enemy_renegade_flamer_color",
    tooltip = "enemy_marker_color_slider_tooltip",
})
_add_anchor("show_enemy_horde_vertical_arrows", {
    prefix = "enemy_horde_marker",
    default = default_by_prefix.enemy_horde_marker,
    title_prefix = "enemy_horde_color",
    tooltip = "enemy_marker_color_slider_tooltip",
})

_add_enemy_kinds("enemy_scab_marker", {
    "enemy_renegade_grenadier",
    "enemy_renegade_gunner",
    "enemy_renegade_plasma_gunner",
    "enemy_chaos_ogryn_gunner",
    "enemy_renegade_executor",
    "enemy_renegade_berzerker",
    "enemy_renegade_assault",
    "enemy_renegade_vanguard",
    "enemy_renegade_rifleman",
    "enemy_renegade_shocktrooper",
    "enemy_renegade_sniper",
    "enemy_chaos_ogryn_executor",
    "enemy_chaos_ogryn_bulwark",
    "enemy_renegade_netgunner",
    "enemy_chaos_mutator_ritualist",
    "enemy_cultist_ritualist",
})
_add_enemy_kinds("enemy_dreg_marker", {
    "enemy_cultist_gunner",
    "enemy_chaos_hound",
    "enemy_cultist_berzerker",
    "enemy_cultist_assault",
    "enemy_cultist_shocktrooper",
    "enemy_cultist_mutant",
    "enemy_cultist_melee",
    "enemy_cultist_vanguard",
})
_add_enemy_kinds("enemy_tox_marker", {
    "enemy_cultist_grenadier",
    "enemy_chaos_poxwalker_bomber",
    "enemy_cultist_flamer",
})
_add_enemy_kinds("enemy_mutator_marker", {
    "enemy_renegade_radio_operator",
    "enemy_chaos_hound_mutator",
    "enemy_renegade_executor_gibbing_rotten_armor",
    "enemy_renegade_berzerker_gibbing_rotten_armor",
    "enemy_renegade_flamer_mutator",
    "enemy_cultist_mutant_mutator",
    "enemy_chaos_ogryn_executor_gibbing_rotten_armor",
})
_add_enemy_kind("enemy_chaos_armored_hound", "enemy_armored_hound_marker")
_add_enemy_kind("enemy_renegade_flamer", "enemy_renegade_flamer_marker")
_add_enemy_kinds("enemy_horde_marker", {
    "enemy_chaos_lesser_mutated_poxwalker",
    "enemy_chaos_mutated_poxwalker",
    "enemy_chaos_newly_infected",
    "enemy_chaos_poxwalker",
    "enemy_chaos_armored_infected",
})

_add_marker({
    kind = "enemy_daemonhost",
    prefix = "enemy_boss_marker",
    default = default_by_prefix.enemy_boss_marker,
    background_prefix = "enemy_boss_background",
    background_default = default_by_prefix.enemy_boss_background,
})
_add_marker({
    kind = "enemy_monstrosity",
    prefix = "enemy_boss_marker",
    default = default_by_prefix.enemy_boss_marker,
    background_prefix = "enemy_boss_background",
    background_default = default_by_prefix.enemy_boss_background,
})
_add_marker({
    kind = "enemy_captain",
    prefix = "enemy_boss_marker",
    default = default_by_prefix.enemy_boss_marker,
    background_prefix = "enemy_boss_background",
    background_default = default_by_prefix.enemy_boss_background,
})
_add_marker({
    kind = "enemy_karnak_twin",
    prefix = "enemy_boss_marker",
    default = default_by_prefix.enemy_boss_marker,
    background_prefix = "enemy_boss_background",
    background_default = default_by_prefix.enemy_boss_background,
})
_add_marker({
    kind = "crate_unknown",
    anchor = "show_crates",
    default = WHITE,
    icon_prefix = "crate_unknown_icon_marker",
    icon_default = _color(255, 225, 200, 136),
    supports_highlight = true,
    highlight_default = _color(255, 225, 200, 136),
})
_add_marker({
    kind = "material_diamantine",
    anchor = "show_diamantine",
    default = WHITE,
    icon_prefix = "material_diamantine_icon_marker",
    icon_default = _color(255, 70, 130, 220),
    supports_highlight = true,
    highlight_default = _color(255, 70, 130, 220),
})
_add_marker({
    kind = "material_plasteel",
    anchor = "show_plasteel",
    default = WHITE,
    icon_prefix = "material_plasteel_icon_marker",
    icon_default = _color(255, 130, 135, 140),
    supports_highlight = true,
    highlight_default = _color(255, 130, 135, 140),
})
_add_marker({
    kind = "material_expeditions_currency",
    anchor = "show_expeditions_currency",
    default = WHITE,
    icon_prefix = "material_expeditions_currency_icon_marker",
    icon_default = _color(255, 120, 160, 140),
    supports_highlight = true,
    highlight_default = _color(255, 120, 160, 140),
})
_add_marker({
    kind = "material_expeditions_loot",
    anchor = "show_expeditions_loot",
    default = WHITE,
    icon_prefix = "material_expeditions_loot_icon_marker",
    icon_default = _color(255, 192, 160, 0),
    supports_highlight = true,
    highlight_default = _color(255, 192, 160, 0),
})
_add_marker({
    kind = "material_expeditions_loot_player_drop",
    anchor = "show_expeditions_dropped_loot",
    default = WHITE,
    icon_prefix = "material_expeditions_loot_player_drop_icon_marker",
    icon_default = _color(220, 255, 0, 0),
    supports_highlight = true,
    highlight_default = _color(220, 255, 0, 0),
})

_add_marker({
    kind = "pickup_ammo_small",
    aliases = { "pickup_ammo" },
    anchor = "show_ammo_small",
    default = _color(255, 240, 210, 80),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_ammo_big",
    anchor = "show_ammo_big",
    default = _color(255, 240, 210, 80),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_grenade",
    anchor = "show_grenades",
    default = _color(255, 205, 156, 77),
    supports_highlight = true,
})
_add_marker({
    kind = "pocketable_ammo_crate",
    anchor = "show_pocketable_ammo_crate",
    default = _color(255, 240, 210, 80),
    supports_highlight = true,
})
_add_marker({
    kind = "pocketable_medical_crate",
    anchor = "show_pocketable_medical_crate",
    default = _color(255, 38, 205, 26),
    supports_highlight = true,
})
_add_marker({
    kind = "pocketable_syringe_ability",
    anchor = "show_pocketable_syringe_ability",
    default = _color(255, 230, 192, 13),
    supports_highlight = true,
})
_add_marker({
    kind = "pocketable_syringe_corruption",
    anchor = "show_pocketable_syringe_corruption",
    default = _color(255, 38, 205, 26),
    supports_highlight = true,
})
_add_marker({
    kind = "pocketable_syringe_power",
    anchor = "show_pocketable_syringe_power",
    default = _color(255, 205, 51, 26),
    supports_highlight = true,
})
_add_marker({
    kind = "pocketable_syringe_speed",
    anchor = "show_pocketable_syringe_speed",
    default = _color(255, 0, 127, 218),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_medkit",
    anchor = "show_medkits",
    default = _color(255, 38, 205, 26),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_stimm",
    anchor = "show_stimms",
    default = WHITE,
    supports_highlight = true,
})

_add_marker({
    kind = "luggable_power_cell_teal",
    anchor = "show_power_cell_teal",
    default = _color(255, 0, 200, 200),
    supports_highlight = true,
})
_add_marker({
    kind = "luggable_cryonic_rod",
    anchor = "show_cryonic_rod",
    default = _color(255, 180, 220, 255),
    supports_highlight = true,
})
_add_marker({
    kind = "luggable_moebian_pox_zetaphyte_13_sample",
    anchor = "show_moebian_pox_zetaphyte_13_sample",
    default = _color(255, 150, 190, 60),
    supports_highlight = true,
})
_add_marker({
    kind = "luggable_vacuum_capsule",
    anchor = "show_vacuum_capsule",
    default = _color(255, 80, 85, 90),
    supports_highlight = true,
})
_add_marker({
    kind = "luggable_special_issue_ammo",
    anchor = "show_special_issue_ammo",
    default = _color(255, 95, 125, 70),
    supports_highlight = true,
})
_add_marker({
    kind = "luggable_prismata_crystal_repository",
    anchor = "show_prismata_crystal_repository",
    default = _color(255, 255, 70, 90),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_mortis_relic",
    anchor = "show_mortis_relic",
    default = _color(255, 110, 95, 125),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_coordinates_paper",
    anchor = "show_coordinates_paper",
    default = WHITE,
    supports_highlight = true,
})

_add_marker({
    kind = "pocketable_grimoire",
    anchor = "show_pocketable_grimoire",
    default = _color(255, 150, 190, 60),
    supports_highlight = true,
})
_add_marker({
    kind = "pocketable_scripture",
    anchor = "show_pocketable_scripture",
    default = _color(255, 192, 160, 0),
    supports_highlight = true,
})

_add_marker({
    kind = "expedition_loot_converter",
    anchor = "show_expedition_loot_converter",
    default = _color(255, 192, 160, 0),
})
_add_marker({
    kind = "expedition_objective_opportunity",
    anchor = "show_expedition_objective_opportunity",
    default = _color(255, 54, 198, 49),
})
_add_marker({
    kind = "expedition_objective_transition",
    anchor = "show_expedition_objective_transition",
    default = _color(255, 54, 198, 49),
})
_add_marker({
    kind = "expedition_objective_main_objective",
    anchor = "show_expedition_objective_main_objective",
    default = _color(255, 54, 198, 49),
})
_add_marker({
    kind = "expedition_objective_extraction",
    anchor = "show_expedition_objective_extraction",
    default = _color(255, 54, 198, 49),
})
_add_marker({
    kind = "expedition_objective_arrival",
    anchor = "show_expedition_objective_arrival",
    default = _color(255, 54, 198, 49),
})

_add_marker({
    kind = "luggable_data_reliquary",
    anchor = "show_data_reliquaries",
    default = _color(255, 192, 160, 0),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_large_ammunition_crate",
    anchor = "show_large_ammunition_crate",
    default = _color(255, 240, 210, 80),
    supports_highlight = true,
})
_add_marker({
    kind = "luggable_promethium_barrel",
    anchor = "show_promethium_barrel",
    default = _color(255, 255, 110, 0),
    supports_highlight = true,
})
_add_marker({
    kind = "hazard_explosive_barrel",
    anchor = "show_explosive_barrels",
    default = _color(255, 205, 156, 77),
    supports_highlight = true,
})
_add_marker({
    kind = "hazard_fire_barrel",
    anchor = "show_fire_barrels",
    default = _color(255, 255, 110, 0),
    supports_highlight = true,
})
_add_marker({
    kind = "pocketable_anti_rad_stimm",
    anchor = "show_anti_rad_stimm",
    default = WHITE,
    supports_highlight = true,
})

_add_marker({
    kind = "pocketable_airstrike",
    anchor = "show_pocketable_airstrike",
    default = WHITE,
    icon_prefix = "pocketable_airstrike_icon_marker",
    icon_default = _color(255, 95, 125, 70),
    supports_highlight = true,
    highlight_default = _color(255, 95, 125, 70),
})
_add_marker({
    kind = "pocketable_artillery_strike",
    anchor = "show_pocketable_artillery_strike",
    default = WHITE,
    icon_prefix = "pocketable_artillery_strike_icon_marker",
    icon_default = _color(255, 95, 125, 70),
    supports_highlight = true,
    highlight_default = _color(255, 95, 125, 70),
})
_add_marker({
    kind = "pocketable_big_grenade",
    anchor = "show_pocketable_big_grenade",
    default = WHITE,
    icon_prefix = "pocketable_big_grenade_icon_marker",
    icon_default = _color(255, 205, 156, 77),
    supports_highlight = true,
    highlight_default = _color(255, 205, 156, 77),
})
_add_marker({
    kind = "pocketable_landmine_explosive",
    anchor = "show_pocketable_landmine_explosive",
    default = WHITE,
    icon_prefix = "pocketable_landmine_explosive_icon_marker",
    icon_default = _color(255, 205, 156, 77),
    supports_highlight = true,
    highlight_default = _color(255, 205, 156, 77),
})
_add_marker({
    kind = "pocketable_landmine_fire",
    anchor = "show_pocketable_landmine_fire",
    default = WHITE,
    icon_prefix = "pocketable_landmine_fire_icon_marker",
    icon_default = _color(255, 255, 110, 0),
    supports_highlight = true,
    highlight_default = _color(255, 255, 110, 0),
})
_add_marker({
    kind = "pocketable_landmine_shock",
    anchor = "show_pocketable_landmine_shock",
    default = WHITE,
    icon_prefix = "pocketable_landmine_shock_icon_marker",
    icon_default = _color(255, 80, 160, 255),
    supports_highlight = true,
    highlight_default = _color(255, 80, 160, 255),
})
_add_marker({
    kind = "pocketable_valkyrie_hover",
    anchor = "show_pocketable_valkyrie_hover",
    default = WHITE,
    icon_prefix = "pocketable_valkyrie_hover_icon_marker",
    icon_default = _color(255, 95, 125, 70),
    supports_highlight = true,
    highlight_default = _color(255, 95, 125, 70),
})
_add_marker({
    kind = "pocketable_void_shield",
    anchor = "show_pocketable_void_shield",
    default = WHITE,
    icon_prefix = "pocketable_void_shield_icon_marker",
    icon_default = _color(255, 181, 166, 66),
    supports_highlight = true,
    highlight_default = _color(255, 181, 166, 66),
})
_add_marker({
    kind = "pocketable_breach_charge",
    anchor = "show_pocketable_breach_charge",
    default = WHITE,
})

_add_marker({
    kind = "pickup_martyr_skull",
    anchor = "show_martyr_skull",
    default = _color(255, 255, 215, 0),
    supports_highlight = true,
})
_add_marker({
    kind = "luggable_power_cell_orange",
    anchor = "show_power_cell_orange",
    default = _color(255, 255, 140, 0),
    supports_highlight = true,
})
_add_marker({
    kind = "medicae_station",
    anchor = "show_medicae_station",
    default = _color(255, 38, 205, 26),
    supports_highlight = true,
})
_add_marker({
    kind = "luggable_socket",
    anchor = "show_luggable_socket",
    default = _color(255, 255, 245, 80),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_heretic_idol",
    anchor = "show_heretic_idol",
    default = _color(255, 150, 190, 60),
    supports_highlight = true,
})

_add_marker({
    kind = "pickup_ammo_cache_deployable",
    anchor = "show_ammo_crate_deployable",
    default = _color(255, 240, 210, 80),
})
_add_marker({
    kind = "medical_crate_deployable",
    anchor = "show_medical_crate_deployable",
    default = _color(255, 38, 205, 26),
})

_add_marker({
    kind = "pickup_tainted_skull",
    anchor = "show_tainted_skull",
    default = _color(255, 150, 190, 60),
    supports_highlight = true,
})
_add_marker({
    kind = "dark_rites_totem",
    anchor = "show_dark_rites_totem",
    default = _color(255, 150, 190, 60),
    supports_highlight = true,
})
_add_marker({
    kind = "dark_rites_servo_skull",
    anchor = "show_dark_rites_servo_skull",
    default = _color(255, 150, 190, 60),
    supports_highlight = true,
})
_add_marker({
    kind = "pocketable_corrupted_auspex_scanner",
    anchor = "show_pocketable_corrupted_auspex_scanner",
    default = _color(255, 255, 120, 0),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_saints",
    anchor = "show_saints",
    default = _color(255, 192, 160, 0),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_leftover",
    anchor = "show_leftover",
    default = _color(255, 150, 190, 60),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_stolen_rations",
    anchor = "show_stolen_rations",
    default = _color(255, 150, 190, 60),
    supports_highlight = true,
})
local function _clamp_channel(value, fallback)
    value = tonumber(value)

    if value == nil then
        value = fallback or 255
    end

    if value < 0 then
        value = 0
    elseif value > 255 then
        value = 255
    end

    return math_floor(value + 0.5)
end

local function _setting_id(prefix, suffix)
    if suffix == "opacity" then
        return opacity_setting_by_prefix[prefix] or (prefix .. "_opacity")
    end

    return prefix .. "_" .. suffix
end

function ColorSettings.install_runtime(mod)
    if not mod or mod._radar_color_settings_installed == true then
        return
    end

    mod._radar_color_settings_installed = true
    mod._radar_color_cache_generation = 0
    mod._radar_color_cache_by_prefix = mod._radar_color_cache_by_prefix or {}
    mod._radar_derived_color_cache = mod._radar_derived_color_cache or {}
    mod._radar_color_settings = ColorSettings

    local previous_on_setting_changed = mod.on_setting_changed

    mod.on_setting_changed = function(setting_id, ...)
        if previous_on_setting_changed then
            previous_on_setting_changed(setting_id, ...)
        end

        mod._radar_color_cache_generation = (mod._radar_color_cache_generation or 0) + 1
    end

    function mod:invalidate_radar_color_cache()
        self._radar_color_cache_generation = (self._radar_color_cache_generation or 0) + 1
    end

    function mod:get_configurable_color(prefix, fallback)
        if not prefix then
            return fallback
        end

        local defaults = default_by_prefix[prefix] or fallback or WHITE
        local cache = self._radar_color_cache_by_prefix

        if cache == nil then
            cache = {}
            self._radar_color_cache_by_prefix = cache
        end

        local entry = cache[prefix]

        if entry == nil then
            entry = {
                generation = -1,
                color = _copy_color(defaults),
            }
            cache[prefix] = entry
        end

        local generation = self._radar_color_cache_generation or 0

        if entry.generation ~= generation then
            local color = entry.color

            local opacity = self:get(_setting_id(prefix, "opacity"))
            local legacy_opacity_setting_id = opacity == nil and legacy_opacity_setting_by_prefix[prefix] or nil

            if legacy_opacity_setting_id then
                opacity = self:get(legacy_opacity_setting_id)
            end

            color[1] = _clamp_channel(opacity, defaults[1] or 255)
            color[2] = _clamp_channel(self:get(_setting_id(prefix, "red")), defaults[2] or 255)
            color[3] = _clamp_channel(self:get(_setting_id(prefix, "green")), defaults[3] or 255)
            color[4] = _clamp_channel(self:get(_setting_id(prefix, "blue")), defaults[4] or 255)
            entry.generation = generation
        end

        return entry.color
    end

    function mod:get_marker_color(kind, fallback)
        local prefix = kind and marker_prefix_by_kind[kind] or nil
        return self:get_configurable_color(prefix, fallback)
    end

    function mod:get_marker_background_color(kind, fallback)
        local prefix = kind and marker_background_prefix_by_kind[kind] or nil
        return self:get_configurable_color(prefix, fallback)
    end

    function mod:get_enemy_radar_icon_color(kind, fallback)
        local prefix = kind and enemy_icon_prefix_by_kind[kind] or nil
        return self:get_configurable_color(prefix, fallback)
    end

    function mod:get_enemy_radar_background_color(_kind, fallback)
        if fallback == nil then
            return nil
        end

        return self:get_configurable_color("enemy_background_marker", fallback)
    end

    function mod:get_highlight_color(kind)
        local prefix = kind and marker_highlight_prefix_by_kind[kind] or nil

        if prefix ~= nil then
            return self:get_configurable_color(prefix)
        end

        return self:get_marker_color(kind, WHITE)
    end

    function mod:get_occluded_highlight_color(kind, multiplier)
        local source = self:get_highlight_color(kind)

        if source == nil then
            return nil
        end

        local mul = tonumber(multiplier) or 1
        local cache = self._radar_derived_color_cache

        if cache == nil then
            cache = {}
            self._radar_derived_color_cache = cache
        end

        local key = "highlight_occluded:" .. tostring(kind) .. ":" .. tostring(mul)
        local entry = cache[key]

        if entry == nil then
            entry = {
                generation = -1,
                color = _copy_color(source),
            }
            cache[key] = entry
        end

        local generation = self._radar_color_cache_generation or 0

        if entry.generation ~= generation then
            local color = entry.color

            color[1] = source[1] or 255
            color[2] = _clamp_channel((source[2] or 255) * mul, source[2] or 255)
            color[3] = _clamp_channel((source[3] or 255) * mul, source[3] or 255)
            color[4] = _clamp_channel((source[4] or 255) * mul, source[4] or 255)
            entry.generation = generation
        end

        return entry.color
    end

    function mod:get_radar_color(prefix, fallback)
        return self:get_configurable_color(prefix, fallback)
    end

    function mod:migrate_radar_color_settings()
        local mod_get = self.get
        local mod_set = self.set
        local migrated = false
        local legacy_background_opacity = mod_get(self, "background_opacity")
        local background_opacity_setting_id = _setting_id("radar_background", "opacity")

        if legacy_background_opacity ~= nil and mod_get(self, background_opacity_setting_id) == nil then
            mod_set(self, background_opacity_setting_id,
                _clamp_channel(legacy_background_opacity, default_by_prefix.radar_background[1] or 90))
            migrated = true
        end

        local legacy_opacity = mod_get(self, "nearby_highlight_opacity")
        local legacy_custom_color = mod_get(self, "nearby_highlight_use_custom_color") == true

        if legacy_opacity == nil and not legacy_custom_color then
            if migrated then
                self:invalidate_radar_color_cache()
            end

            return
        end

        local legacy_red = legacy_custom_color and _clamp_channel(mod_get(self, "nearby_highlight_color_red"), 255) or nil
        local legacy_green = legacy_custom_color and _clamp_channel(mod_get(self, "nearby_highlight_color_green"), 255) or nil
        local legacy_blue = legacy_custom_color and _clamp_channel(mod_get(self, "nearby_highlight_color_blue"), 255) or nil

        for i = 1, #highlight_prefixes do
            local prefix = highlight_prefixes[i]
            local defaults = default_by_prefix[prefix] or WHITE

            if legacy_opacity ~= nil then
                local opacity_setting_id = _setting_id(prefix, "opacity")
                local default_opacity = defaults[1] or 255
                local current_opacity = mod_get(self, opacity_setting_id)

                if current_opacity == nil or
                    _clamp_channel(current_opacity, default_opacity) == _clamp_channel(default_opacity, 255) then
                    mod_set(self, opacity_setting_id, _clamp_channel(legacy_opacity, default_opacity))
                    migrated = true
                end
            end

            if legacy_custom_color then
                local red_setting_id = _setting_id(prefix, "red")
                local green_setting_id = _setting_id(prefix, "green")
                local blue_setting_id = _setting_id(prefix, "blue")
                local default_red = defaults[2] or 255
                local default_green = defaults[3] or 255
                local default_blue = defaults[4] or 255
                local current_red = mod_get(self, red_setting_id)
                local current_green = mod_get(self, green_setting_id)
                local current_blue = mod_get(self, blue_setting_id)
                local rgb_is_default =
                    (current_red == nil or _clamp_channel(current_red, default_red) == _clamp_channel(default_red, 255))
                    and (current_green == nil or
                        _clamp_channel(current_green, default_green) == _clamp_channel(default_green, 255))
                    and (current_blue == nil or
                        _clamp_channel(current_blue, default_blue) == _clamp_channel(default_blue, 255))

                if rgb_is_default then
                    mod_set(self, red_setting_id, legacy_red)
                    mod_set(self, green_setting_id, legacy_green)
                    mod_set(self, blue_setting_id, legacy_blue)
                    migrated = true
                end
            end
        end

        if legacy_opacity ~= nil then
            mod_set(self, "nearby_highlight_opacity", 255)
        end

        if legacy_custom_color then
            mod_set(self, "nearby_highlight_use_custom_color", false)
        end

        if migrated then
            self:invalidate_radar_color_cache()
        end
    end
end

ColorSettings.default_by_prefix = default_by_prefix
ColorSettings.opacity_setting_by_prefix = opacity_setting_by_prefix
ColorSettings.anchored_color_settings = anchored_color_settings
ColorSettings.highlight_prefixes = highlight_prefixes
ColorSettings.marker_prefix_by_kind = marker_prefix_by_kind
ColorSettings.marker_background_prefix_by_kind = marker_background_prefix_by_kind
ColorSettings.marker_highlight_prefix_by_kind = marker_highlight_prefix_by_kind
ColorSettings.enemy_icon_prefix_by_kind = enemy_icon_prefix_by_kind

return ColorSettings
