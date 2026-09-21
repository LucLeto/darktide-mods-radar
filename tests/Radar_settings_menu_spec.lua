-- Builds Radar's settings menu the way DMF loads it and checks it against what the native DMF
-- options need: one top-level group per tab, native colour widgets instead of channel sliders,
-- dropdown `show_widgets` that hide a marker's settings while it is off, no Alf-only fields, and
-- colours saved by older versions surviving the move to native colour settings.
local DATA_PATH = "Radar/scripts/mods/Radar/Radar_data.lua"
local COLOR_SETTINGS_PATH = "Radar/scripts/mods/Radar/Radar_color_settings.lua"

local problems = {}

local function check(condition, message)
    if not condition then
        problems[#problems + 1] = message
    end
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}

    for key, entry in pairs(value) do
        result[key] = copy(entry)
    end

    return result
end

local function same_color(a, b)
    return type(a) == "table" and type(b) == "table"
        and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

local function color_text(color)
    if type(color) ~= "table" then
        return tostring(color)
    end

    return "{" .. tostring(color[1]) .. ", " .. tostring(color[2]) .. ", " .. tostring(color[3]) .. ", "
        .. tostring(color[4]) .. "}"
end

-- A mod object that stores settings like DMF does: tables are copied on the way in and out, and
-- `set` only notifies the mod when asked to.
local function new_mod(store)
    local mod = {}

    function mod:get(setting_id)
        return copy(store[setting_id])
    end

    function mod:set(setting_id, value, notify)
        store[setting_id] = copy(value)

        if notify and self.on_setting_changed then
            self.on_setting_changed(setting_id)
        end
    end

    function mod:localize(key)
        return tostring(key)
    end

    function mod:io_dofile(path)
        return assert(loadfile(path .. ".lua"))()
    end

    return mod
end

local function load_data(store)
    local mod = new_mod(store)

    _G.get_mod = function()
        return mod
    end

    return assert(loadfile(DATA_PATH))(), mod
end

-- --------------------------------------------------------------------------------------------
-- Radar.mod declares its packages natively and no longer loads after Alf's extensions.
-- --------------------------------------------------------------------------------------------

local mod_file = assert(loadfile("Radar/Radar.mod"))()
local load_after = {}

-- `load_after` is optional; the mod loader always loads dmf first, and Radar resolves Strikemap
-- lazily. What must not come back is a dependency on Alf's extensions.
for i = 1, #(mod_file.load_after or {}) do
    load_after[mod_file.load_after[i]] = true
end

check(load_after.Alfs_DMF_Extensions == nil, "Radar.mod still loads after Alf's DMF Extensions")

local packages = mod_file.packages
local seen_packages = {}

check(type(packages) == "table" and #packages > 0, "Radar.mod declares no icon packages")

for i = 1, #(packages or {}) do
    local package_name = packages[i]

    check(type(package_name) == "string" and package_name:sub(1, 9) == "packages/",
        "Radar.mod package " .. i .. " is not a package path")
    check(seen_packages[package_name] == nil, "Radar.mod lists " .. tostring(package_name) .. " twice")
    seen_packages[package_name] = true
end

-- A few the settings menu's own dropdown icons come from, so a truncated list is noticed.
local REQUIRED_PACKAGES = {
    "packages/ui/views/inventory_view/inventory_view",
    "packages/ui/material_sets/circumstances",
    "packages/ui/views/expedition_view/expedition_view",
    "packages/content/live_events/saints/live_event_saints_ui_assets",
}

for i = 1, #REQUIRED_PACKAGES do
    check(seen_packages[REQUIRED_PACKAGES[i]] == true, "Radar.mod no longer declares " .. REQUIRED_PACKAGES[i])
end

-- --------------------------------------------------------------------------------------------
-- A fresh profile.
-- --------------------------------------------------------------------------------------------

local fresh_store = {}
local data = load_data(fresh_store)
local ColorSettings = assert(loadfile(COLOR_SETTINGS_PATH))()

check(type(ColorSettings.setting_id) == "function" and type(ColorSettings.migrate_channel_settings) == "function",
    "the colour settings module does not name or migrate native colour settings")

if type(ColorSettings.setting_id) ~= "function" then
    ColorSettings.setting_id = function(prefix)
        return prefix .. "_color"
    end
end

check(data.required_icon_packages == nil, "the mod data still exposes required_icon_packages")
check(next(fresh_store) == nil, "building the menu for a fresh profile saved settings")

local widgets = data.options and data.options.widgets or {}
local EXPECTED_TABS = {
    { "general_group", "tab_general" },
    { "layout_group", "tab_layout" },
    { "pickups_group", "tab_pickups" },
    { "objectives_group", "tab_objectives" },
    { "expeditions_group", "tab_expeditions" },
    { "enemies_group", "tab_enemies" },
    { "players_group", "tab_players" },
    { "respawn_group", "tab_respawn" },
    { "debug_group", "tab_debug" },
}

check(#widgets == #EXPECTED_TABS, "the menu has " .. #widgets .. " top-level widgets instead of one per tab")

for i = 1, #EXPECTED_TABS do
    local widget = widgets[i] or {}

    check(widget.setting_id == EXPECTED_TABS[i][1] and widget.title == EXPECTED_TABS[i][2]
        and widget.type == "group",
        "top-level widget " .. i .. " is not the " .. EXPECTED_TABS[i][1] .. " tab")
end

-- Every widget by setting id, with the widget whose sub_widgets hold it.
local widget_by_id = {}
local parent_by_id = {}
local PARENT_TYPES = { group = true, checkbox = true, dropdown = true }
local CHANNEL_SUFFIXES = { "_opacity", "_red", "_green", "_blue" }

local function walk(list, parent)
    for i = 1, #list do
        local widget = list[i]
        local setting_id = widget.setting_id
        local label = tostring(setting_id)

        check(type(setting_id) == "string", "a widget under " .. tostring(parent and parent.setting_id) .. " has no setting id")
        check(widget_by_id[setting_id] == nil, label .. " is declared twice")
        widget_by_id[setting_id] = widget
        parent_by_id[setting_id] = parent

        for _, field in ipairs({ "tab", "tab_overrides", "get", "change", "icon_colour" }) do
            check(widget[field] == nil, label .. " still has the Alf-only field " .. field)
        end

        if widget.localize == false then
            check(type(widget.title) == "string", label .. " turns localization off without a title")
        end

        if widget.sub_widgets then
            check(PARENT_TYPES[widget.type] == true, label .. " is a " .. tostring(widget.type) .. " with sub widgets")
        end

        if widget.type == "group" then
            check(widget.sub_widgets and #widget.sub_widgets > 0, label .. " is an empty group")
        elseif widget.type == "checkbox" then
            check(type(widget.default_value) == "boolean", label .. " has no boolean default")
        elseif widget.type == "numeric" then
            local range = widget.range or {}

            check(type(widget.default_value) == "number" and widget.default_value >= range[1]
                and widget.default_value <= range[2], label .. " has a default outside its range")
            check(widget.step_size_value == nil or widget.step_size_value > 0, label .. " has a bad step size")

            for s = 1, #CHANNEL_SUFFIXES do
                local suffix = CHANNEL_SUFFIXES[s]

                check(setting_id:sub(-#suffix) ~= suffix or setting_id == "radar_move_step",
                    label .. " looks like a leftover colour channel slider")
            end
        elseif widget.type == "color" then
            local prefix = setting_id:match("^(.-)_color$")

            check(prefix ~= nil and ColorSettings.default_by_prefix[prefix] ~= nil,
                label .. " is a colour widget without a registered colour")
            check(widget.has_alpha == true, label .. " hides the alpha channel")
            check(same_color(widget.default_value, ColorSettings.default_color(prefix)),
                label .. " defaults to " .. color_text(widget.default_value) .. " instead of the registered colour")
            check(widget.localize == false and type(widget.tooltip) == "string", label .. " has no localized tooltip")
        elseif widget.type == "dropdown" then
            local options = widget.options or {}
            local values = {}
            local has_default = false
            local sub_count = widget.sub_widgets and #widget.sub_widgets or 0

            check(#options >= 2, label .. " has fewer than two options")

            for o = 1, #options do
                local option = options[o]

                check(values[option.value] == nil, label .. " repeats option " .. tostring(option.value))
                values[option.value] = true
                has_default = has_default or option.value == widget.default_value

                if option.icon then
                    local style = option.icon_style

                    check(type(style) == "table" and style.color ~= nil and style.default_color ~= nil
                        and style.hover_color ~= nil and style.selected_color ~= nil,
                        label .. " option " .. tostring(option.value) .. " has an icon without a tint style")
                end

                if sub_count == 0 then
                    check(option.show_widgets == nil, label .. " lists show_widgets without sub widgets")
                elseif option.value == "off" then
                    check(option.show_widgets == nil, label .. " shows sub widgets while off")
                else
                    local show_widgets = option.show_widgets

                    check(type(show_widgets) == "table", label .. " option " .. tostring(option.value)
                        .. " hides every sub widget")

                    for s = 1, #(show_widgets or {}) do
                        local index = show_widgets[s]

                        check(type(index) == "number" and index >= 1 and index <= sub_count,
                            label .. " option " .. tostring(option.value) .. " shows a missing sub widget")
                    end
                end
            end

            check(has_default, label .. " defaults to a value it does not offer")
        end

        if widget.sub_widgets then
            walk(widget.sub_widgets, widget)
        end
    end
end

walk(widgets, nil)

local function option_of(setting_id, value)
    local widget = widget_by_id[setting_id]

    for i = 1, #(widget and widget.options or {}) do
        if widget.options[i].value == value then
            return widget.options[i]
        end
    end
end

local function shows(setting_id, value, child_id)
    local widget = widget_by_id[setting_id]
    local option = option_of(setting_id, value)

    for i = 1, #(option and option.show_widgets or {}) do
        local child = widget.sub_widgets[option.show_widgets[i]]

        if child and child.setting_id == child_id then
            return true
        end
    end

    return false
end

local function parent_id(setting_id)
    local parent = parent_by_id[setting_id]

    return parent and parent.setting_id or nil
end

-- Every registered colour appears once, owned by its marker unless it serves other markers too.
for anchor, descriptors in pairs(ColorSettings.anchored_color_settings) do
    local anchor_widget = widget_by_id[anchor]

    check(anchor_widget ~= nil, "colours are anchored to the missing widget " .. anchor)

    for i = 1, #descriptors do
        local descriptor = descriptors[i]
        local color_id = ColorSettings.setting_id(descriptor.prefix)
        local owner = parent_id(color_id)

        check(widget_by_id[color_id] ~= nil, color_id .. " has no colour widget")

        if anchor_widget and anchor_widget.type == "group" then
            check(owner == anchor, color_id .. " is not inside the group " .. anchor)
        elseif anchor_widget and (anchor_widget.type == "checkbox" or anchor_widget.type == "dropdown")
            and not descriptor.shared then
            check(owner == anchor, color_id .. " is not hidden with its marker " .. anchor)
        else
            check(owner == parent_id(anchor), color_id .. " is not placed next to " .. anchor)
        end
    end
end

-- Marker colours disappear with their marker; artwork is never tinted, so only its highlight shows.
check(parent_id("pickup_ammo_small_marker_color") == "show_ammo_small", "the ammo tin colour is not under its marker")
check(shows("show_ammo_small", "icon", "pickup_ammo_small_marker_color")
    and shows("show_ammo_small", "icon", "pickup_ammo_small_highlight_color"),
    "the ammo tin colours are hidden while its marker is on")
check(shows("show_crates", "icon", "crate_unknown_icon_marker_color")
    and shows("show_crates", "icon", "crate_unknown_highlight_color"),
    "the crate colours are hidden in icon mode")
check(not shows("show_crates", "artwork", "crate_unknown_icon_marker_color")
    and shows("show_crates", "artwork", "crate_unknown_highlight_color"),
    "artwork mode shows the icon tint, or hides the highlight colour")
check(shows("show_enemy_chaos_armored_hound", "marked_icon", "enemy_armored_hound_marker_color")
    and shows("show_enemy_chaos_armored_hound", "icon_only", "enemy_armored_hound_marker_color"),
    "the armoured hound colour is hidden while the hound is shown")
check(parent_id("enemy_horde_marker_color") == "show_enemy_horde", "the horde colour is not under the horde marker")
check(shows("show_mission_objective_hacking", "icon_distance", "mission_objective_hacking_marker_color"),
    "the hacking terminal colour is hidden in icon and distance mode")
check(shows("show_expedition_objective_arrival", "icon_only", "expedition_objective_arrival_marker_color"),
    "the Expedition arrival colour is hidden while its marker is on")
check(shows("map_geometry_source", "live", "radar_navmesh_color")
    and option_of("map_geometry_source", "off").show_widgets == nil,
    "the map geometry colours do not follow the geometry source")

-- Colours serving several toggles, and category-wide settings, stay where every marker sees them.
check(parent_id("pickup_martyr_skull_marker_color") == "martyr_s_skull_group",
    "the Martyr's Skull colour hides with the skull although the riddle interactables use it")
check(parent_id("mission_objective_minigame_waiting_marker_color") == "mission_objective_group",
    "the puzzle state colours hide with the hacking terminal")
check(parent_id("enemy_boss_marker_color") == "enemy_bosses_group", "the boss colours hide with one boss toggle")
check(parent_id("enemy_scab_marker_color") == "enemy_global_settings_group", "the shared enemy colours moved")
check(parent_id("common_pickups_icon_scale") == "common_pickups_group", "an icon scale hides with a marker")
check(parent_id("nearby_highlight_common_pickups") == "common_pickups_group",
    "the nearby highlight toggle hides with a marker")
check(parent_id("nearby_highlight_distance_text_common_pickups") == "common_pickups_group",
    "the radar distance text works without highlights but is nested under them")
check(parent_id("mission_objective_background_marker_color") == "mission_objective_group",
    "the objective frame colours hide with one objective marker")

-- Settings that only affect one marker disappear with it.
check(parent_id("show_medicae_station_charges") == "show_medicae_station"
    and shows("show_medicae_station", "icon", "show_medicae_station_charges"),
    "the Medicae charges setting does not follow the Medicae marker")
check(parent_id("show_ammo_crate_deployable_charges") == "show_ammo_crate_deployable",
    "the ammo crate charges setting does not follow the ammo crate marker")
check(shows("show_players", "dot_only", "show_player_state_icons")
    and shows("show_players", "marked_icon", "player_marker_range_mode")
    and option_of("show_players", "off").show_widgets == nil,
    "the teammate settings do not follow the teammate marker")
check(parent_id("show_player_tag_distance_text") == "show_player_tags"
    and parent_id("player_tag_display_style") == "show_player_tags",
    "the player tag settings do not follow the player tag toggle")

-- Layout keeps the order the tabs had.
local ORDER = {
    layout_group = { "position_group", "radar_frame_group", "radar_colors_group", "radar_map_geometry_group", "nearby_highlight_group" },
    pickups_group = { "common_pickups_group", "materials_group", "environment_group", "deployables_group" },
    objectives_group = { "mission_objective_group", "primary_objective_group", "secondary_objective_group", "martyr_s_skull_group", "event_group" },
    expeditions_group = { "expeditions_location_group", "expeditions_specific_group" },
}

for tab_id, expected in pairs(ORDER) do
    local tab = widget_by_id[tab_id]

    for i = 1, #expected do
        check(tab and tab.sub_widgets[i] and tab.sub_widgets[i].setting_id == expected[i],
            tab_id .. " does not hold " .. expected[i] .. " at position " .. i)
    end
end

-- --------------------------------------------------------------------------------------------
-- A profile saved by the previous release.
-- --------------------------------------------------------------------------------------------

local legacy_store = {
    crate_unknown_icon_marker_opacity = 200,
    crate_unknown_icon_marker_red = 10,
    crate_unknown_icon_marker_green = 20,
    crate_unknown_icon_marker_blue = 300,
    pickup_ammo_small_highlight_red = 1,
    background_opacity = 77,
    radar_outline_opacity = 12,
    radar_outline_color = { 1, 2, 3, 4 },
    show_teammates = false,
    use_strikemap_geometry = true,
    show_crates = false,
    show_explosive_barrels = true,
    unrelated_setting = "kept",
}
local legacy_data, legacy_mod = load_data(legacy_store)
local crate_default = ColorSettings.default_by_prefix.crate_unknown_icon_marker
local ammo_highlight_default = ColorSettings.default_by_prefix.pickup_ammo_small_highlight
local background_default = ColorSettings.default_by_prefix.radar_background

check(same_color(legacy_store.crate_unknown_icon_marker_color, { 200, 10, 20, 255 }),
    "the crate colour became " .. color_text(legacy_store.crate_unknown_icon_marker_color))
check(legacy_store.crate_unknown_icon_marker_opacity == nil and legacy_store.crate_unknown_icon_marker_red == nil
    and legacy_store.crate_unknown_icon_marker_green == nil and legacy_store.crate_unknown_icon_marker_blue == nil,
    "the crate colour channels were kept after migrating")
check(same_color(legacy_store.pickup_ammo_small_highlight_color,
    { ammo_highlight_default[1], 1, ammo_highlight_default[3], ammo_highlight_default[4] }),
    "a partly saved colour did not keep its defaults")
check(same_color(legacy_store.radar_background_color,
    { 77, background_default[2], background_default[3], background_default[4] }),
    "the old background opacity was lost")
check(legacy_store.background_opacity == nil, "the old background opacity was kept after migrating")
check(same_color(legacy_store.radar_outline_color, { 1, 2, 3, 4 }) and legacy_store.radar_outline_opacity == nil,
    "an existing native colour was overwritten by leftover channels")
check(legacy_store.pickup_ammo_small_marker_color == nil, "a colour without saved channels was written")
check(legacy_store.show_players == "off", "the old hidden teammates setting was lost")
check(legacy_store.map_geometry_source == "strikemap", "the old Strikemap geometry toggle was lost")
check(legacy_store.show_crates == "off" and legacy_store.show_explosive_barrels == "icon_only",
    "display mode dropdowns kept checkbox values")
check(legacy_store.unrelated_setting == "kept", "an unrelated setting was touched")

local before_reload = copy(legacy_store)

load_data(legacy_store)

for key, value in pairs(before_reload) do
    local unchanged = type(value) == "table" and same_color(value, legacy_store[key]) or legacy_store[key] == value

    check(unchanged, "building the menu again changed " .. key)
end

for key in pairs(legacy_store) do
    check(before_reload[key] ~= nil, "building the menu again saved " .. key)
end

-- Dropdown icons follow a colour change without the menu being rebuilt.
local function find_widget(list, setting_id)
    for i = 1, #list do
        local widget = list[i]

        if widget.setting_id == setting_id then
            return widget
        end

        local found = widget.sub_widgets and find_widget(widget.sub_widgets, setting_id)

        if found then
            return found
        end
    end
end

local legacy_crates = find_widget(legacy_data.options.widgets, "show_crates")

local icon_option = legacy_crates and legacy_crates.options[2] or {}
local artwork_option = legacy_crates and legacy_crates.options[1] or {}
local icon_style = icon_option.icon_style
local artwork_style = artwork_option.icon_style

check(icon_style and same_color(icon_style.default_color, { 200, 10, 20, 255 }),
    "the crate icon is not tinted with the saved colour")

legacy_mod:set("unrelated_setting", "changed", true)
check(icon_option.icon_style == icon_style, "an unrelated setting replaced the crate icon style")

legacy_mod:set("crate_unknown_icon_marker_color", { 255, 1, 2, 3 }, true)
check(icon_option.icon_style ~= icon_style and same_color(icon_option.icon_style.color, { 255, 1, 2, 3 }),
    "the crate icon tint does not follow its colour setting")
check(artwork_option.icon_style == artwork_style, "the untinted artwork icon changed with the icon colour")

-- --------------------------------------------------------------------------------------------
-- The runtime reads native colours and migrates old highlight and bracket settings on them.
-- --------------------------------------------------------------------------------------------

local runtime_store = {
    pickup_ammo_small_marker_color = { 10, 300, -5, "x" },
    enemy_background_marker_color = { 220, 0, 128, 255 },
    nearby_highlight_opacity = 100,
    nearby_highlight_use_custom_color = true,
    nearby_highlight_color_red = 1,
    nearby_highlight_color_green = 2,
    nearby_highlight_color_blue = 3,
    pickup_grenade_highlight_color = { 5, 6, 7, 8 },
}
local runtime_mod = new_mod(runtime_store)
local ammo_default = ColorSettings.default_by_prefix.pickup_ammo_small_marker
local bracket_default = ColorSettings.default_by_prefix.enemy_bracket_marker
local ammo_highlight = ColorSettings.default_by_prefix.pickup_ammo_small_highlight

ColorSettings.install_runtime(runtime_mod)

check(same_color(runtime_mod:get_marker_color("pickup_ammo_small"), { 10, 255, 0, ammo_default[4] }),
    "the runtime colour is " .. color_text(runtime_mod:get_marker_color("pickup_ammo_small")))
check(same_color(runtime_mod:get_marker_color("pickup_ammo_big"), ColorSettings.default_by_prefix.pickup_ammo_big_marker),
    "an unsaved colour does not use its default")

runtime_mod:set("pickup_ammo_small_marker_color", { 1, 2, 3, 4 }, true)
check(same_color(runtime_mod:get_marker_color("pickup_ammo_small"), { 1, 2, 3, 4 }),
    "the runtime colour does not follow a changed setting")

runtime_mod:migrate_radar_color_settings()

check(same_color(runtime_store.enemy_bracket_marker_color, { bracket_default[1], 0, 128, 255 }),
    "the brackets did not take the customised background colour: " .. color_text(runtime_store.enemy_bracket_marker_color))
check(runtime_store.enemy_bracket_color_migrated == true, "the bracket migration is not marked done")
check(ammo_highlight[1] ~= 100 and same_color(runtime_store.pickup_ammo_small_highlight_color, { 100, 1, 2, 3 }),
    "a default highlight colour did not take the old highlight settings: "
        .. color_text(runtime_store.pickup_ammo_small_highlight_color))
check(same_color(runtime_store.pickup_grenade_highlight_color, { 5, 6, 7, 8 }),
    "a customised highlight colour was overwritten by the old highlight settings")
check(runtime_store.nearby_highlight_opacity == nil and runtime_store.nearby_highlight_use_custom_color == nil,
    "the old highlight settings were kept after migrating")

if #problems > 0 then
    for i = 1, #problems do
        io.write("FAIL ", problems[i], "\n")
    end

    io.write("\n", tostring(#problems), " problems\n")
    os.exit(1)
end

local color_widget_count = 0

for _, widget in pairs(widget_by_id) do
    if widget.type == "color" then
        color_widget_count = color_widget_count + 1
    end
end

io.write("all settings menu checks passed for ", tostring(color_widget_count), " colour widgets\n")
