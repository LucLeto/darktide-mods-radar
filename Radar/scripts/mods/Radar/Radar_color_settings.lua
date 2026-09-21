--- Single source of truth for every configurable Radar colour.
-- Declares each colour's setting prefix and default ARGB value, which marker kinds,
-- backgrounds, highlights and enemy icons resolve to which prefix, and under which settings
-- widget (the anchor) its colour widget appears. A colour with prefix `p` is stored as one
-- native DMF colour setting `p_color` holding `{ a, r, g, b }`. Older versions stored it in
-- the four settings `p_opacity`, `p_red`, `p_green` and `p_blue`, which
-- `ColorSettings.migrate_channel_settings` folds into the native setting.
--
-- Explicit module loaded through `mod:io_dofile`; the chunk returns `ColorSettings`. It is
-- loaded separately by `Radar_data.lua` (settings widgets, dropdown icon colours and the
-- channel migration), `Radar_enemy_definitions.lua` (runtime) and `ui/Radar_hud_element.lua`
-- (fallback colours); each load builds its own identical registry. `ColorSettings.install_runtime`
-- adds the cached colour getters to `mod` once, from the first caller (the enemy definitions).
-- module: Radar_color_settings
-- alias: ColorSettings
-- author: LucLeto
local ColorSettings = {}

local math_floor = math.floor
local tonumber = tonumber

--- Builds an ARGB colour array.
-- treturn: tab `{ a, r, g, b }`
local function _color(a, r, g, b)
    return { a, r, g, b }
end

local WHITE = _color(255, 255, 255, 255)

--- Returns the tint of the game's own on-screen objective marker.
-- Mission objective markers use it so they read as the same family as the vanilla HUD
-- marker. Read from the game's HUD settings when available, with the shipped value as a
-- fallback so a moved settings path cannot break marker colours.
-- treturn: tab ARGB colour array
local function _vanilla_objective_color()
    local ok, hud_settings = pcall(require, "scripts/settings/ui/ui_hud_settings")
    local tint = ok and type(hud_settings) == "table" and hud_settings.color_tint_main_1 or nil

    if type(tint) == "table" and tonumber(tint[1]) and tonumber(tint[4]) then
        return _color(tint[1], tint[2], tint[3], tint[4])
    end

    return _color(255, 223, 229, 219)
end

--- Shared default colours referenced by several registrations.
local VANILLA_OBJECTIVE = _vanilla_objective_color()
local RADAR_OUTLINE = _color(255, 213, 226, 206)
local AUSPEX_GREEN = _color(255, 0, 255, 0)

--- Colour registry filled by the registration calls below and exported on `ColorSettings`.
-- `marker_prefix_by_kind`, `marker_background_prefix_by_kind`,
-- `marker_highlight_prefix_by_kind` and `enemy_icon_prefix_by_kind` map a marker kind to a
-- colour prefix. `default_by_prefix` holds each prefix's default colour and
-- `color_setting_id_by_prefix` its native colour setting id, `highlight_prefixes` lists every
-- highlight prefix, the opacity maps name legacy opacity settings that did not follow the
-- `p_opacity` pattern (and their pre-migration names), and `anchored_color_settings` lists the
-- colour widget descriptors to insert under each settings widget id.
local marker_prefix_by_kind = {}
local marker_background_prefix_by_kind = {}
local marker_highlight_prefix_by_kind = {}
local enemy_icon_prefix_by_kind = {}
local default_by_prefix = {}
local color_setting_id_by_prefix = {}
local highlight_prefixes = {}
local opacity_setting_by_prefix = {
    radar_background = "radar_background_opacity",
}
local legacy_opacity_setting_by_prefix = {
    radar_background = "background_opacity",
}
local anchored_color_settings = {}

--- Returns a copy of an ARGB colour array with missing channels set to 255.
-- tab: color colour array
-- treturn: tab
local function _copy_color(color)
    return {
        color[1] or 255,
        color[2] or 255,
        color[3] or 255,
        color[4] or 255,
    }
end

--- Registers a prefix's default colour and its native colour setting id; the first registration of a prefix wins.
local function _add_default(prefix, color)
    if prefix and color and default_by_prefix[prefix] == nil then
        default_by_prefix[prefix] = _copy_color(color)
        color_setting_id_by_prefix[prefix] = prefix .. "_color"
    end
end

--- Adds a colour widget descriptor under a settings widget id.
-- A checkbox or dropdown anchor owns the colour widget as a sub widget, so it is hidden while
-- the anchor is off; any other anchor, or a descriptor with `shared`, gets it as the next sibling.
-- ?string: anchor setting id the colour widget belongs to; nothing is added when nil
-- tab: descriptor colour widget descriptor (`prefix`, `default`, `title_prefix`, `tooltip`, labels, `shared`)
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

--- Registers the colours of one marker kind.
-- Always registers the marker colour, named `<kind>_marker` unless `prefix` or
-- `icon_prefix` is given (an icon prefix takes `icon_default` as its default). Optionally
-- registers a background colour (`background_prefix`) and a nearby highlight colour
-- (`supports_highlight`, named `<kind>_highlight` by default). `aliases` resolve to the
-- same marker and highlight prefixes. Each registered colour gets its colour widget under
-- `anchor`; `shared` marks colours that other settings' markers use too, so they stay visible
-- while the anchor is off.
-- tab: descriptor marker colour descriptor
local function _add_marker(descriptor)
    local kind = descriptor.kind
    local prefix = descriptor.prefix or descriptor.icon_prefix or (kind and kind .. "_marker")
    local default = descriptor.icon_prefix and (descriptor.icon_default or descriptor.default or WHITE) or
        (descriptor.default or WHITE)
    local aliases = descriptor.aliases
    local shared = descriptor.shared == true

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
        label_role = descriptor.label_role or "icon",
        label_prefix = descriptor.label_prefix,
        label_suffix = descriptor.label_suffix,
        shared = shared,
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
            shared = shared,
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
            shared = shared,
        })
    end
end

--- Registers a colour that belongs to no marker kind, such as the radar frame or map geometry bands.
-- string: anchor setting id the colour widget belongs to
-- string: prefix colour setting prefix
-- tab: default default ARGB colour
-- string: title_prefix localization id of the colour widget title
-- ?string: tooltip colour widget tooltip localization id
local function _add_radar_color(anchor, prefix, default, title_prefix, tooltip)
    _add_default(prefix, default)
    _add_anchor(anchor, {
        prefix = prefix,
        default = default,
        title_prefix = title_prefix,
        tooltip = tooltip or "radar_color_slider_tooltip",
    })
end

--- Maps an enemy marker kind to the colour prefix of its radar icon.
local function _add_enemy_kind(kind, icon_prefix)
    enemy_icon_prefix_by_kind[kind] = icon_prefix
end

--- Maps several enemy marker kinds to one icon colour prefix.
local function _add_enemy_kinds(icon_prefix, kinds)
    for i = 1, #kinds do
        _add_enemy_kind(kinds[i], icon_prefix)
    end
end

-- Radar frame, Auspex, text and map geometry band colours.
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
_add_radar_color("map_geometry_source", "radar_navmesh", _color(80, 101, 133, 96), "radar_navmesh_color")
_add_radar_color("map_geometry_source", "radar_navmesh_above", _color(32, 120, 150, 185), "radar_navmesh_above_color")
_add_radar_color("map_geometry_source", "radar_navmesh_below", _color(55, 120, 98, 76), "radar_navmesh_below_color")

-- Enemy icon, background and bracket colours, shared by many enemy kinds and anchored below.
-- The boss background colour only tints the brackets of boss markers, which draw no background.
-- Brackets of the other enemies used the background colour at a fixed opacity of 180 before they
-- got a colour of their own, so that is the bracket default. The boss colours serve all three
-- boss toggles, so they are `shared` and stay visible whichever boss is switched off.
_add_default("enemy_boss_marker", _color(255, 255, 64, 64))
_add_default("enemy_boss_background", _color(220, 255, 0, 0))
_add_default("enemy_background_marker", _color(220, 255, 0, 0))
_add_default("enemy_bracket_marker", _color(180, 255, 0, 0))
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
    shared = true,
})
_add_anchor("show_enemy_boss_vertical_arrows", {
    prefix = "enemy_boss_background",
    default = default_by_prefix.enemy_boss_background,
    title_prefix = "enemy_boss_background_color",
    tooltip = "enemy_boss_bracket_color_slider_tooltip",
    shared = true,
})
_add_anchor("enemies_icon_scale", {
    prefix = "enemy_background_marker",
    default = default_by_prefix.enemy_background_marker,
    title_prefix = "enemy_marked_background_color",
    tooltip = "enemy_background_color_slider_tooltip",
})
_add_anchor("enemies_icon_scale", {
    prefix = "enemy_bracket_marker",
    default = default_by_prefix.enemy_bracket_marker,
    title_prefix = "enemy_bracket_color",
    tooltip = "enemy_bracket_color_slider_tooltip",
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
_add_anchor("show_enemy_horde", {
    prefix = "enemy_horde_marker",
    default = default_by_prefix.enemy_horde_marker,
    title_prefix = "enemy_horde_color",
    tooltip = "enemy_marker_color_slider_tooltip",
})

-- Which enemy kinds use which enemy icon colour.
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
    "enemy_renegade_melee",
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

-- Marker kind colours, each anchored under the settings widget of its category.
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
    tooltip = "expedition_location_color_slider_tooltip",
    default = _color(255, 192, 160, 0),
})
_add_marker({
    kind = "expedition_objective_opportunity",
    anchor = "show_expedition_objective_opportunity",
    tooltip = "expedition_location_color_slider_tooltip",
    default = _color(255, 54, 198, 49),
})
_add_marker({
    kind = "expedition_objective_transition",
    anchor = "show_expedition_objective_transition",
    tooltip = "expedition_location_color_slider_tooltip",
    default = _color(255, 54, 198, 49),
})
_add_marker({
    kind = "expedition_objective_main_objective",
    anchor = "show_expedition_objective_main_objective",
    tooltip = "expedition_location_color_slider_tooltip",
    default = _color(255, 54, 198, 49),
})
_add_marker({
    kind = "expedition_objective_extraction",
    anchor = "show_expedition_objective_extraction",
    tooltip = "expedition_location_color_slider_tooltip",
    default = _color(255, 54, 198, 49),
})
_add_marker({
    kind = "expedition_objective_arrival",
    anchor = "show_expedition_objective_arrival",
    tooltip = "expedition_location_color_slider_tooltip",
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
    kind = "mission_objective_scanner",
    anchor = "show_mission_objective_scanner",
    default = VANILLA_OBJECTIVE,
    supports_highlight = true,
})
_add_marker({
    kind = "mission_objective_hacking",
    anchor = "show_mission_objective_hacking",
    default = VANILLA_OBJECTIVE,
    supports_highlight = true,
})
-- Puzzle devices keep the objective icon but say, in colour, whether they still
-- need somebody. Registered as colour kinds only: nothing ever tracks a marker
-- under these names, they are just the key `get_marker_color` is looked up by,
-- so no icon, dropdown or scale group changes with the state. Both sit under the
-- hacking terminal option because that is where every puzzle device is
-- configured, whichever objective category it belongs to; that is also why they
-- are `shared` and stay visible while the hacking terminal marker is off.
_add_marker({
    kind = "mission_objective_minigame_waiting",
    anchor = "show_mission_objective_hacking",
    default = _color(255, 235, 70, 70),
    label_prefix = "mission_objective_minigame_waiting_color_title",
    label_suffix = "",
    label_role = "minigame_state",
    tooltip = "mission_objective_minigame_color_slider_tooltip",
    shared = true,
})
_add_marker({
    kind = "mission_objective_minigame_active",
    anchor = "show_mission_objective_hacking",
    default = _color(255, 255, 205, 60),
    label_prefix = "mission_objective_minigame_active_color_title",
    label_suffix = "",
    label_role = "minigame_state",
    tooltip = "mission_objective_minigame_color_slider_tooltip",
    shared = true,
})
-- The plate behind the objective frame. One colour for the whole family, since
-- they share the frame, anchored to the group's icon size slider so it appears
-- once inside Mission Objective Interactables. Defaults to the near-black the
-- game uses behind its own objective markers rather than to white.
local MISSION_OBJECTIVE_BACKGROUND = _color(235, 16, 18, 20)

_add_radar_color("mission_objective_icon_scale", "mission_objective_background_marker", MISSION_OBJECTIVE_BACKGROUND,
    "marker_background_color", "mission_objective_background_color_slider_tooltip")

-- The frame itself, separate from the icon inside it. One colour for the whole
-- family, so the frame stays the family's identity while each icon keeps its own
-- colour and its own state colours.
_add_radar_color("mission_objective_icon_scale", "mission_objective_frame_marker", VANILLA_OBJECTIVE,
    "mission_objective_frame_color", "mission_objective_frame_color_slider_tooltip")

local MISSION_OBJECTIVE_GROWTH = _color(255, 186, 124, 0)

_add_marker({
    kind = "mission_objective_growth",
    anchor = "show_mission_objective_growth",
    default = MISSION_OBJECTIVE_GROWTH,
    supports_highlight = true,
})
-- Targets to destroy: the generic objective tint by default, like the category
-- they were split from, but a colour of their own.
_add_marker({
    kind = "mission_objective_destroy",
    anchor = "show_mission_objective_destroy",
    default = VANILLA_OBJECTIVE,
    supports_highlight = true,
})
_add_marker({
    kind = "mission_objective_servo_skull",
    anchor = "show_mission_objective_servo_skull",
    default = VANILLA_OBJECTIVE,
})
_add_marker({
    kind = "mission_objective_other",
    anchor = "show_mission_objective_other",
    default = VANILLA_OBJECTIVE,
    supports_highlight = true,
})

-- The riddle interactables have a toggle of their own but wear the skull's colours, so the
-- colours are `shared` and stay visible while the skull marker itself is off.
_add_marker({
    kind = "pickup_martyr_skull",
    aliases = { "martyr_skull_riddle_interactable" },
    anchor = "show_martyr_skull",
    default = _color(255, 255, 215, 0),
    supports_highlight = true,
    shared = true,
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
    tooltip = "icon_marker_color_slider_tooltip",
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
    tooltip = "icon_marker_color_slider_tooltip",
    default = _color(255, 192, 160, 0),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_leftover",
    anchor = "show_leftover",
    tooltip = "icon_marker_color_slider_tooltip",
    default = _color(255, 150, 190, 60),
    supports_highlight = true,
})
_add_marker({
    kind = "pickup_stolen_rations",
    anchor = "show_stolen_rations",
    default = _color(255, 150, 190, 60),
    supports_highlight = true,
})

-- Respawn awareness. The defaults start from the colours Respawn Rewind draws its own markers
-- in, so a player who turns the radar markers on recognises them, and they are Radar settings
-- from that point on: nothing here reads or writes anything that belongs to the other mod.
-- No highlight colours, since the respawn kinds have no nearby highlight of their own.
_add_marker({
    kind = "respawn_active",
    anchor = "show_respawn_active",
    default = _color(255, 120, 200, 255),
})
_add_marker({
    kind = "respawn_runback",
    anchor = "show_respawn_runback",
    default = _color(255, 120, 220, 120),
})
_add_marker({
    kind = "respawn_practice_beacon",
    anchor = "show_respawn_practice_beacon",
    default = _color(255, 130, 170, 200),
})
_add_marker({
    kind = "respawn_practice_line",
    anchor = "show_respawn_practice_line",
    default = _color(255, 175, 175, 175),
})
--- Converts a setting value into a colour channel, rounded and clamped to 0 to 255.
-- param: value setting value
-- ?number: fallback channel used when the value is not a number, 255 when nil
-- treturn: int
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

--- Returns the native colour setting id of a colour prefix.
-- string: prefix colour prefix
-- treturn: string `<prefix>_color`
local function _color_setting_id(prefix)
    return color_setting_id_by_prefix[prefix] or (prefix .. "_color")
end

--- Returns the legacy setting id of one channel of a colour prefix, from before native colour settings.
-- string: prefix colour prefix
-- string: suffix `opacity`, `red`, `green` or `blue`
-- treturn: string
local function _channel_setting_id(prefix, suffix)
    if suffix == "opacity" then
        return opacity_setting_by_prefix[prefix] or (prefix .. "_opacity")
    end

    return prefix .. "_" .. suffix
end

--- Reads a prefix's native colour setting as a new, clamped ARGB array; missing channels use the default.
-- For settings migrations only, since `mod:get` copies table settings on every call.
-- tab: mod Radar mod object
-- string: prefix colour prefix
-- treturn: tab `{ a, r, g, b }`, owned by the caller
local function _read_color_setting(mod, prefix)
    local defaults = default_by_prefix[prefix] or WHITE
    local value = mod:get(_color_setting_id(prefix))

    if type(value) ~= "table" then
        return _copy_color(defaults)
    end

    for i = 1, 4 do
        value[i] = _clamp_channel(value[i], defaults[i] or 255)
    end

    return value
end

--- Installs the colour runtime on the mod object, once per mod lifetime.
-- Adds the colour getters and the settings migration as `mod` methods and chains
-- `mod.on_setting_changed` to invalidate the colour cache. Colours are cached per prefix
-- and refreshed lazily when the cache generation changes, so reading a colour every frame
-- costs a table lookup; the returned colour tables are shared and must not be modified.
-- tab: mod Radar mod object
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

    --- DMF callback, chained after any previously installed handler; any setting change invalidates the colour cache.
    -- string: setting_id changed setting
    -- param: ... further DMF arguments, forwarded to the previous handler
    mod.on_setting_changed = function(setting_id, ...)
        if previous_on_setting_changed then
            previous_on_setting_changed(setting_id, ...)
        end

        mod._radar_color_cache_generation = (mod._radar_color_cache_generation or 0) + 1
    end

    --- Forces every cached colour to be read from the settings again.
    function mod:invalidate_radar_color_cache()
        self._radar_color_cache_generation = (self._radar_color_cache_generation or 0) + 1
    end

    --- Returns the configured ARGB colour of a colour prefix.
    -- Reads the prefix's native colour setting once per cache generation. A missing setting or
    -- channel falls back to the registered default, then to `fallback`, then to white.
    -- ?string: prefix colour prefix; `fallback` is returned when nil
    -- ?tab: fallback colour used for an unregistered prefix
    -- treturn: ?tab cached ARGB colour array, shared between callers
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
            local value = self:get(_color_setting_id(prefix))

            if type(value) ~= "table" then
                value = defaults
            end

            color[1] = _clamp_channel(value[1], defaults[1] or 255)
            color[2] = _clamp_channel(value[2], defaults[2] or 255)
            color[3] = _clamp_channel(value[3], defaults[3] or 255)
            color[4] = _clamp_channel(value[4], defaults[4] or 255)
            entry.generation = generation
        end

        return entry.color
    end

    --- Returns the configured radar marker colour of a marker kind.
    -- ?string: kind marker kind, or a colour kind from `get_marker_color_kind`
    -- ?tab: fallback colour for a kind without a registered colour
    -- treturn: ?tab ARGB colour array
    function mod:get_marker_color(kind, fallback)
        local prefix = kind and marker_prefix_by_kind[kind] or nil
        return self:get_configurable_color(prefix, fallback)
    end

    --- Colour kinds for the two live states of a puzzle device.
    -- Puzzle devices keep their category's icon, dropdown and scale group and change only which
    -- colour they are looked up under, so the marker says whether the puzzle still needs a
    -- player (`waiting`) or already has one (`active`). The colour kinds are registered for
    -- colours only; no marker is ever tracked under them.
    local MINIGAME_COLOR_KIND_BY_STATE = {
        waiting = "mission_objective_minigame_waiting",
        active = "mission_objective_minigame_active",
    }

    --- Returns the kind a target's marker colour is looked up under.
    -- A puzzle device in a live minigame state is coloured by its state; every other target,
    -- including a device without a puzzle or in an unknown state, keeps its own kind.
    -- ?string: kind marker kind
    -- ?tab: meta target meta; its `minigame_state` selects the state colour
    -- treturn: ?string colour kind
    function mod:get_marker_color_kind(kind, meta)
        local state = meta and meta.minigame_state or nil

        return (state and MINIGAME_COLOR_KIND_BY_STATE[state]) or kind
    end

    --- Returns the colour of the frame shared by every mission objective marker.
    -- The frame carries the family's identity, so it has one colour of its own while each icon
    -- keeps its marker and state colours.
    -- treturn: tab ARGB colour array
    function mod:get_mission_objective_frame_color()
        return self:get_configurable_color("mission_objective_frame_marker")
    end

    --- Returns the colour of the backplate drawn behind mission objective frames.
    -- treturn: tab ARGB colour array
    function mod:get_mission_objective_background_color()
        return self:get_configurable_color("mission_objective_background_marker")
    end

    --- Returns the configured background colour of a marker kind, or `fallback` when it has none.
    -- treturn: ?tab ARGB colour array
    function mod:get_marker_background_color(kind, fallback)
        local prefix = kind and marker_background_prefix_by_kind[kind] or nil
        return self:get_configurable_color(prefix, fallback)
    end

    --- Returns the configured icon colour of an enemy marker kind, or `fallback` when it has none.
    -- treturn: ?tab ARGB colour array
    function mod:get_enemy_radar_icon_color(kind, fallback)
        local prefix = kind and enemy_icon_prefix_by_kind[kind] or nil
        return self:get_configurable_color(prefix, fallback)
    end

    --- Returns the configured enemy background colour, shared by all enemy kinds.
    -- Enemy definitions without a background pass no fallback and keep having none.
    -- param: _kind unused, kept for a uniform getter signature
    -- ?tab: fallback the definition's own background colour
    -- treturn: ?tab ARGB colour array, nil when `fallback` is nil
    function mod:get_enemy_radar_background_color(_kind, fallback)
        if fallback == nil then
            return nil
        end

        return self:get_configurable_color("enemy_background_marker", fallback)
    end

    --- Returns the nearby highlight colour of a marker kind.
    -- A kind without a highlight colour of its own is highlighted in its marker colour.
    -- ?string: kind marker kind
    -- treturn: tab ARGB colour array
    function mod:get_highlight_color(kind)
        local prefix = kind and marker_highlight_prefix_by_kind[kind] or nil

        if prefix ~= nil then
            return self:get_configurable_color(prefix)
        end

        return self:get_marker_color(kind, WHITE)
    end

    --- Returns a kind's highlight colour with its RGB channels scaled, for highlights behind geometry.
    -- Cached per kind and multiplier and refreshed with the colour cache.
    -- ?string: kind marker kind
    -- ?number: multiplier RGB multiplier, 1 when not a number
    -- treturn: ?tab ARGB colour array
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

    --- Returns a configured colour by prefix; the entry point for the renderers.
    -- string: prefix colour prefix
    -- ?tab: fallback colour for an unregistered prefix
    -- treturn: ?tab ARGB colour array
    function mod:get_radar_color(prefix, fallback)
        return self:get_configurable_color(prefix, fallback)
    end

    --- Migrates colour settings saved by versions before configurable colours.
    -- Runs on every start from `mod.on_all_mods_loaded`, after DMF saved the default of every
    -- native colour setting. Copies the old global nearby highlight opacity and custom colour into
    -- every highlight colour still at its default. The old opacity is only copied when it differs
    -- from its old default of 255. The old highlight opacity and custom colour switch are then
    -- deleted, so later starts do not migrate again. Once per profile, enemy brackets also take the
    -- RGB of a customised enemy background colour, which they were drawn in before they had a
    -- colour of their own. The old background opacity is folded in earlier, by
    -- `ColorSettings.migrate_channel_settings`.
    function mod:migrate_radar_color_settings()
        local mod_get = self.get
        local mod_set = self.set
        local migrated = false

        -- A saved flag rather than the bracket colour marks this as done, so brackets a player sets
        -- back to their default later are not recoloured on the next start.
        if mod_get(self, "enemy_bracket_color_migrated") ~= true then
            local background_defaults = default_by_prefix.enemy_background_marker
            local background = _read_color_setting(self, "enemy_background_marker")

            if background[2] ~= background_defaults[2] or background[3] ~= background_defaults[3]
                or background[4] ~= background_defaults[4] then
                local bracket = _read_color_setting(self, "enemy_bracket_marker")

                bracket[2] = background[2]
                bracket[3] = background[3]
                bracket[4] = background[4]
                mod_set(self, _color_setting_id("enemy_bracket_marker"), bracket)
                migrated = true
            end

            mod_set(self, "enemy_bracket_color_migrated", true)
        end

        local legacy_opacity = mod_get(self, "nearby_highlight_opacity")
        local legacy_custom_color_setting = mod_get(self, "nearby_highlight_use_custom_color")
        local legacy_custom_color = legacy_custom_color_setting == true
        -- The old slider defaulted to 255 and DMF saves option defaults, so 255 is an opacity the
        -- player never changed. Copying it would only raise the highlights whose default is lower.
        local copy_legacy_opacity = legacy_opacity ~= nil and _clamp_channel(legacy_opacity, 255) ~= 255

        -- Deleting the old keys, rather than resetting them, keeps later starts from migrating
        -- again and overriding highlight opacities the player set back to their default.
        if legacy_opacity ~= nil then
            mod_set(self, "nearby_highlight_opacity", nil)
        end

        if legacy_custom_color_setting ~= nil then
            mod_set(self, "nearby_highlight_use_custom_color", nil)
        end

        if not copy_legacy_opacity and not legacy_custom_color then
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
            local color = _read_color_setting(self, prefix)
            local changed = false

            if copy_legacy_opacity and color[1] == _clamp_channel(defaults[1], 255) then
                color[1] = _clamp_channel(legacy_opacity, defaults[1] or 255)
                changed = true
            end

            if legacy_custom_color and color[2] == _clamp_channel(defaults[2], 255)
                and color[3] == _clamp_channel(defaults[3], 255)
                and color[4] == _clamp_channel(defaults[4], 255) then
                color[2] = legacy_red
                color[3] = legacy_green
                color[4] = legacy_blue
                changed = true
            end

            if changed then
                mod_set(self, _color_setting_id(prefix), color)
                migrated = true
            end
        end

        if migrated then
            self:invalidate_radar_color_cache()
        end
    end
end

--- Returns a copy of a prefix's default colour, for code outside the runtime.
-- Used by the settings menu and the fallback tables.
-- ?string: prefix colour prefix
-- treturn: ?tab ARGB colour array, nil for an unknown prefix
function ColorSettings.default_color(prefix)
    local color = prefix and default_by_prefix[prefix] or nil

    return color and _copy_color(color) or nil
end

--- Returns a copy of a marker kind's default marker colour.
-- ?string: kind marker kind
-- treturn: ?tab ARGB colour array
function ColorSettings.default_marker_color(kind)
    return ColorSettings.default_color(kind and marker_prefix_by_kind[kind] or nil)
end

--- Returns a copy of a marker kind's default highlight colour.
-- Mirrors `mod:get_highlight_color`; a kind without a highlight colour of its own falls
-- back to its marker colour.
-- ?string: kind marker kind
-- treturn: ?tab ARGB colour array
function ColorSettings.default_highlight_color(kind)
    local prefix = kind and marker_highlight_prefix_by_kind[kind] or nil

    if prefix ~= nil then
        return ColorSettings.default_color(prefix)
    end

    return ColorSettings.default_marker_color(kind)
end

--- Returns the native colour setting id of a colour prefix, for the settings menu.
-- ?string: prefix colour prefix
-- treturn: ?string `<prefix>_color`, nil when `prefix` is nil
function ColorSettings.setting_id(prefix)
    return prefix and _color_setting_id(prefix) or nil
end

--- Folds colours saved as four channel settings into their native colour settings.
-- Must run before DMF initialises the options, which saves the default of every native colour
-- setting that is still unset, so `Radar_data.lua` calls it while it builds the settings menu.
-- A prefix with any saved legacy channel gets its native setting built from those channels, the
-- missing ones taken from the default, unless the native setting already exists; the legacy
-- channels are deleted either way. The radar background takes its opacity from the
-- `background_opacity` setting of versions before configurable colours when it has no opacity
-- channel. Prefixes without legacy settings are left alone, so running it again changes nothing.
-- tab: mod Radar mod object
-- treturn: bool whether any setting changed
function ColorSettings.migrate_channel_settings(mod)
    local mod_get = mod.get
    local mod_set = mod.set
    local changed = false

    for prefix, defaults in pairs(default_by_prefix) do
        local opacity_setting_id = _channel_setting_id(prefix, "opacity")
        local red_setting_id = _channel_setting_id(prefix, "red")
        local green_setting_id = _channel_setting_id(prefix, "green")
        local blue_setting_id = _channel_setting_id(prefix, "blue")
        local legacy_opacity_setting_id = legacy_opacity_setting_by_prefix[prefix]
        local opacity = mod_get(mod, opacity_setting_id)
        local red = mod_get(mod, red_setting_id)
        local green = mod_get(mod, green_setting_id)
        local blue = mod_get(mod, blue_setting_id)
        local legacy_opacity = legacy_opacity_setting_id and mod_get(mod, legacy_opacity_setting_id) or nil

        if opacity ~= nil or red ~= nil or green ~= nil or blue ~= nil or legacy_opacity ~= nil then
            local setting_id = _color_setting_id(prefix)

            if mod_get(mod, setting_id) == nil then
                if opacity == nil then
                    opacity = legacy_opacity
                end

                mod_set(mod, setting_id, {
                    _clamp_channel(opacity, defaults[1] or 255),
                    _clamp_channel(red, defaults[2] or 255),
                    _clamp_channel(green, defaults[3] or 255),
                    _clamp_channel(blue, defaults[4] or 255),
                })
            end

            -- Deleted only now that the native setting holds the colour, never before.
            mod_set(mod, opacity_setting_id, nil)
            mod_set(mod, red_setting_id, nil)
            mod_set(mod, green_setting_id, nil)
            mod_set(mod, blue_setting_id, nil)

            if legacy_opacity_setting_id then
                mod_set(mod, legacy_opacity_setting_id, nil)
            end

            changed = true
        end
    end

    return changed
end

-- The registry and shared defaults, read by the settings menu, the HUD element and the specs.
ColorSettings.default_by_prefix = default_by_prefix
ColorSettings.anchored_color_settings = anchored_color_settings
ColorSettings.highlight_prefixes = highlight_prefixes
ColorSettings.marker_prefix_by_kind = marker_prefix_by_kind
ColorSettings.marker_background_prefix_by_kind = marker_background_prefix_by_kind
ColorSettings.marker_highlight_prefix_by_kind = marker_highlight_prefix_by_kind
ColorSettings.enemy_icon_prefix_by_kind = enemy_icon_prefix_by_kind
ColorSettings.vanilla_objective_color = VANILLA_OBJECTIVE
ColorSettings.mission_objective_growth_color = MISSION_OBJECTIVE_GROWTH

return ColorSettings
