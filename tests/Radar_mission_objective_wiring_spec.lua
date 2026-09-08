-- Installs the real definition modules and asserts every mission objective kind
-- is registered everywhere a marker kind has to be registered, and that the
-- shared presentation rules hold.
local KINDS = {
    "mission_objective_growth",
    "mission_objective_scanner",
    "mission_objective_hacking",
    "mission_objective_servo_skull",
    "mission_objective_other",
}

local SETTING_BY_KIND = {
    mission_objective_growth = "show_mission_objective_growth",
    mission_objective_scanner = "show_mission_objective_scanner",
    mission_objective_hacking = "show_mission_objective_hacking",
    mission_objective_servo_skull = "show_mission_objective_servo_skull",
    mission_objective_other = "show_mission_objective_other",
}

local settings_store = {
    show_mission_objective_growth = "icon_only",
    show_mission_objective_scanner = "icon_only",
    show_mission_objective_hacking = "icon_distance",
    show_mission_objective_servo_skull = "off",
    show_mission_objective_other = "icon_only",
    nearby_highlight_mission_objective = true,
    nearby_highlight_distance_text_mission_objective = true,
    mission_objective_icon_scale = 150,
}

local mod = {}

function mod:get(setting_id)
    return settings_store[setting_id]
end

function mod:set(setting_id, value)
    settings_store[setting_id] = value
end

function mod:localize(key)
    return tostring(key)
end

function mod:io_dofile(path)
    return assert(loadfile(path .. ".lua"))()
end

function mod:hook_safe() end
function mod:hook() end
function mod:info() end
function mod:error() end
function mod:notify() end

_G.get_mod = function()
    return mod
end
_G.Localize = function(key)
    return tostring(key)
end
table.clear = table.clear or function(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local env = { mod = mod, Pickups = { by_name = {} } }
setmetatable(env, { __index = _G })

assert(loadfile("Radar/scripts/mods/Radar/Radar_enemy_definitions.lua"))()(env)
assert(loadfile("Radar/scripts/mods/Radar/Radar_runtime_helpers.lua"))()(env)

local color_settings = assert(loadfile("Radar/scripts/mods/Radar/Radar_color_settings.lua"))()
local hud_source = assert(io.open("Radar/scripts/mods/Radar/ui/Radar_hud_element.lua")):read("*a")
local data_source = assert(io.open("Radar/scripts/mods/Radar/Radar_data.lua")):read("*a")
local tracking_source = assert(io.open("Radar/scripts/mods/Radar/Radar_tracking.lua")):read("*a")
local expeditions_source = assert(io.open("Radar/scripts/mods/Radar/Radar_expeditions.lua")):read("*a")

local problems = {}

local function check(condition, message)
    if not condition then
        problems[#problems + 1] = message
    end
end

for i = 1, #KINDS do
    local kind = KINDS[i]
    local setting_id = SETTING_BY_KIND[kind]

    -- Reported rather than crashed on: a kind swept here without a setting is a
    -- half-registered kind, which is the defect, not a broken spec.
    if setting_id == nil then
        check(false, kind .. ": swept as a marker kind but has no setting")
        setting_id = "<missing>"
    end

    check(env.NEARBY_OUTLINE_COLOR_BY_KIND[kind] ~= nil,
        kind .. ": missing NEARBY_OUTLINE_COLOR_BY_KIND entry")

    check(env.SCREEN_HIGHLIGHT_Z_OFFSET_BY_KIND[kind] ~= nil,
        kind .. ": missing SCREEN_HIGHLIGHT_Z_OFFSET_BY_KIND entry")

    local group = mod:get_marker_scale_group(kind)
    check(group == "mission_objective_group", kind .. ": marker scale group is " .. tostring(group))

    check(mod:get_icon_distance_marker_display_mode(kind) == settings_store[setting_id],
        kind .. ": display mode does not follow its dropdown setting")

    check(env.NEARBY_HIGHLIGHT_SETTING_BY_GROUP[group] == "nearby_highlight_mission_objective",
        kind .. ": nearby highlight setting not mapped")

    check(env.NEARBY_HIGHLIGHT_DISTANCE_TEXT_SETTING_BY_GROUP[group]
        == "nearby_highlight_distance_text_mission_objective",
        kind .. ": nearby highlight distance text setting not mapped")

    check(mod:get_marker_scale_factor(group) == 1.5, kind .. ": icon scale slider not wired")

    local color = mod:get_marker_color(kind)
    check(type(color) == "table" and #color == 4, kind .. ": marker color not resolvable")

    check(hud_source:find("    " .. kind .. " = {", 1, true) ~= nil,
        kind .. ": missing PRESENTATIONS entry")

    check(data_source:find("    " .. setting_id .. " = {", 1, true) ~= nil,
        kind .. ": missing MARKER_DROPDOWN_PRESENTATIONS entry")

    check(data_source:find('_icon_distance_off_dropdown("' .. setting_id .. '"', 1, true) ~= nil,
        kind .. ": missing settings dropdown widget")

    check(mod:is_event_marker_kind(kind) ~= true, kind .. ": must not be treated as an event marker")

    -- The family shares the vanilla objective tint so the radar reads as the same
    -- family as the on-screen HUD marker. Daemonic growth is the exception: it is
    -- its own configurable category with a colour of its own.
    local expected = kind == "mission_objective_growth"
        and color_settings.mission_objective_growth_color
        or color_settings.vanilla_objective_color
    local outline = env.NEARBY_OUTLINE_COLOR_BY_KIND[kind]

    check(type(expected) == "table", kind .. ": expected color is not exported")

    if type(expected) == "table" and type(outline) == "table" then
        for channel = 1, 4 do
            check(outline[channel] == expected[channel],
                kind .. ": outline color channel " .. channel .. " is not the vanilla tint")
        end

        for channel = 1, 4 do
            check(color[channel] == expected[channel],
                kind .. ": marker color channel " .. channel .. " is not the vanilla tint")
        end
    end
end

-- Its own configurable category: dropdown, colour and defaults of its own,
-- rather than borrowing the generic objective category's.
local growth_default = color_settings.mission_objective_growth_color

check(type(growth_default) == "table"
    and growth_default[2] == 186 and growth_default[3] == 124 and growth_default[4] == 0,
    "the daemonic growth default colour is not the requested one")
check(data_source:find('_icon_distance_off_dropdown("show_mission_objective_growth"', 1, true) ~= nil,
    "daemonic growth has no display mode dropdown")
check(color_settings.anchored_color_settings
    and color_settings.anchored_color_settings.show_mission_objective_growth ~= nil,
    "daemonic growth has no colour sliders of its own")

-- Puzzle devices change only which colour they are looked up under. These two
-- are colour kinds and nothing else: no presentation, no dropdown, no scale
-- group, so a puzzle keeps its category's icon and settings.
local MINIGAME_COLOR_KINDS = {
    mission_objective_minigame_waiting = "waiting",
    mission_objective_minigame_active = "active",
}

local runtime_source = assert(io.open("Radar/scripts/mods/Radar/Radar_runtime_helpers.lua")):read("*a")
local minigame_colors = {}

for color_kind, state in pairs(MINIGAME_COLOR_KINDS) do
    local color = mod:get_marker_color(color_kind)

    check(type(color) == "table" and #color == 4, color_kind .. ": colour is not configurable")
    check(mod:get_marker_color_kind("mission_objective_hacking", { minigame_state = state }) == color_kind,
        state .. ": does not map to its colour kind")
    check(hud_source:find("    " .. color_kind .. " = {", 1, true) == nil,
        color_kind .. ": must not have a presentation, it is a colour key only")

    if type(color) == "table" then
        minigame_colors[state] = color
    end
end

-- A device with no puzzle, and one whose state is unknown, keep their own kind.
check(mod:get_marker_color_kind("mission_objective_hacking", nil) == "mission_objective_hacking",
    "a marker without a puzzle must keep its own colour")
check(mod:get_marker_color_kind("mission_objective_other", { minigame_state = "complete" })
    == "mission_objective_other",
    "an unknown puzzle state must fall back to the marker's own colour")

-- Red for wanting a player, yellow for having one: they have to be told apart at
-- a glance, and neither may be the shared objective tint.
local waiting_color = minigame_colors.waiting
local active_color = minigame_colors.active
local vanilla = color_settings.vanilla_objective_color

if type(waiting_color) == "table" and type(active_color) == "table" then
    local same_as_each_other = true
    local waiting_is_vanilla = true

    for channel = 1, 4 do
        if waiting_color[channel] ~= active_color[channel] then
            same_as_each_other = false
        end

        if type(vanilla) == "table" and waiting_color[channel] ~= vanilla[channel] then
            waiting_is_vanilla = false
        end
    end

    check(not same_as_each_other, "the two puzzle states default to the same colour")
    check(not waiting_is_vanilla, "a waiting puzzle is not distinguishable from a plain objective marker")
    check(waiting_color[2] > waiting_color[3] and waiting_color[2] > waiting_color[4],
        "a waiting puzzle should default to red")
    check(active_color[2] > 200 and active_color[3] > 150 and active_color[4] < 150,
        "a puzzle being solved should default to yellow")
end

-- Both sit under the hacking terminal option, where every puzzle device is
-- configured, so the sliders are reachable in the settings menu.
local anchored = color_settings.anchored_color_settings
    and color_settings.anchored_color_settings.show_mission_objective_hacking or nil
local anchored_prefixes = {}

for i = 1, (anchored and #anchored or 0) do
    anchored_prefixes[anchored[i].prefix] = true
end

check(anchored_prefixes.mission_objective_minigame_waiting_marker == true,
    "the waiting colour has no sliders under the hacking terminal option")
check(anchored_prefixes.mission_objective_minigame_active_marker == true,
    "the in-progress colour has no sliders under the hacking terminal option")

-- Both the radar marker and its screen bracket have to follow the state, or a
-- puzzle's dot and its outline disagree.
check(hud_source:find("_marker_color_kind(target_kind, meta)", 1, true) ~= nil,
    "the radar marker does not follow the puzzle state")
check(runtime_source:find("marker_color_kind(mod, kind, target.meta)", 1, true) ~= nil,
    "the screen highlight does not follow the puzzle state")

-- Every objective kind wears the frame the game draws around its own objective
-- markers, at one shared size, so the family reads as one group. The icon rides
-- the overlay layer and is sized as a ratio of the frame, which is what keeps
-- the fit through the icon-scale slider.
local LF = string.char(10)
local OBJECTIVE_FRAME_SIZE = tonumber(hud_source:match("local OBJECTIVE_FRAME_SIZE = (%d+)"))
-- Read out of the table the renderer uses, not repeated here: the point of the
-- table is that a category can be retuned on its own, so the spec has to check
-- the properties every entry must hold rather than the numbers themselves.
local ICON_SIZE_BLOCK = hud_source:match("local OBJECTIVE_ICON_SIZE_BY_KIND = {(.-)" .. LF .. "}")
local ICON_SIZE_BY_KIND = {}

if ICON_SIZE_BLOCK ~= nil then
    for kind, size in ICON_SIZE_BLOCK:gmatch("(mission_objective_[%a_]+) = (%d+),") do
        ICON_SIZE_BY_KIND[kind] = tonumber(size)
    end
end

check(ICON_SIZE_BLOCK ~= nil, "the per-category icon sizes are missing")

-- These numbers are tuned by eye against the game's own marker and are expected
-- to change. Pinning them here would turn every deliberate adjustment into a
-- test failure, which is the opposite of what the table is for, so what is
-- checked is that each category has a size of its own and that the size is one
-- the renderer can actually draw.
--
-- Parity is deliberately not checked. The renderer moves the icon to the nearer
-- integer of the frame's parity at every scale, so an odd nominal size is
-- centred exactly like an even one -- verified across sizes 10 to 72 below. An
-- earlier version of this spec required even sizes, which was left over from
-- before that correction existed and rejected a perfectly good hand-tuned value.
for _, kind in ipairs(KINDS) do
    local icon_size = ICON_SIZE_BY_KIND[kind]

    check(icon_size ~= nil, kind .. " has no icon size of its own")

    -- Guarded, so a missing entry is one reported defect rather than a crash
    -- that hides every check after it.
    if icon_size ~= nil then
        check(icon_size >= 4, kind .. " has an icon size of " .. icon_size
            .. ", below the minimum the renderer will draw")
        -- Inside the frame, or it is not an icon in a diamond any more.
        check(icon_size < OBJECTIVE_FRAME_SIZE,
            kind .. " fills its whole frame, which draws it larger than the game's marker")
    end
end

-- Independently tunable is the whole point: sharing one number is what made
-- tuning the scanner move the servo skull.
check(ICON_SIZE_BLOCK ~= nil and ICON_SIZE_BLOCK:find("OBJECTIVE_ICON_SIZE", 1, true) == nil,
    "the categories share a size symbol again, so one cannot be tuned alone")

check(hud_source:find('local OBJECTIVE_FRAME_ICON = "content/ui/materials/hud/interactions/frames/point_of_interest_top"',
    1, true) ~= nil, "the objective frame material is missing")
check(OBJECTIVE_FRAME_SIZE ~= nil, "the shared objective frame size is missing")

for i = 1, #KINDS do
    local kind = KINDS[i]
    local block = hud_source:match(LF .. "    " .. kind .. " = {(.-)" .. LF .. "    },")

    check(block ~= nil, kind .. ": presentation block not found")

    if block then
        check(block:find("icon = OBJECTIVE_FRAME_ICON", 1, true) ~= nil,
            kind .. ": does not wear the objective frame")
        check(block:find('overlay_icon = "content/ui/materials/', 1, true) ~= nil,
            kind .. ": has no icon on the overlay layer")
        check(block:find("size = OBJECTIVE_FRAME_SIZE", 1, true) ~= nil,
            kind .. ": does not share the family frame size")
        check(block:find("background_base_size = OBJECTIVE_FRAME_SIZE", 1, true) ~= nil,
            kind .. ": has no frame size to scale its icon against")
        -- The arrow derives from the final rendered marker size, so it scales
        -- with the frame and sits against it the way every other marker's does.
        -- An override would pin it to a fixed size and detach it.
        check(block:find("arrow_base_size", 1, true) == nil,
            kind .. ": pins its arrow to a fixed size instead of the rendered frame")

        -- The renderer sizes the icon as `size * (overlay_base / background_base)`,
        -- and both bases are the frame size here, so the nominal size is what
        -- gets drawn: each icon must keep the size it had before the frame was
        -- added, so adding the frame changes nothing but the frame. Retuning the
        -- frame size deliberately does not fail this -- it is the knob for how
        -- much room the diamond leaves.
        -- The sizes are named constants now, so the symbol is resolved rather
        -- than read as a literal.
        -- Each presentation names its own entry in the size table, so the
        -- symbol is resolved through it rather than read as a literal.
        local overlay_kind = block:match("overlay_base_size = OBJECTIVE_ICON_SIZE_BY_KIND%.([%a_]+)")
        local overlay_base = overlay_kind and ICON_SIZE_BY_KIND[overlay_kind]
            or tonumber(block:match("overlay_base_size = (%d+)"))

        check(overlay_kind == kind,
            kind .. ": takes its icon size from " .. tostring(overlay_kind) .. " rather than its own entry")
        check(overlay_base ~= nil, kind .. ": its icon size does not resolve to a number")

    end
end

-- The backplate is an opt-in layer drawn before the base icon. Enemy markers
-- compose their own coloured background into the base layer and must keep doing
-- so, since the radar background is itself configurable and they need contrast.
local widgets_source = assert(io.open("Radar/scripts/mods/Radar/ui/Radar_hud_widgets.lua")):read("*a")
local plate_pass_at = widgets_source:find('value_id = "plate_icon"', 1, true)
local icon_pass_at = widgets_source:find('value_id = "icon"', 1, true)

check(plate_pass_at ~= nil, "the backplate pass is missing")
check(plate_pass_at ~= nil and icon_pass_at ~= nil and plate_pass_at < icon_pass_at,
    "the backplate is not drawn before the base icon")
-- The gate has to be on the pass itself, not merely defined somewhere: without
-- it the plate would draw behind every marker in the game.
-- A window after the pass starts, rather than a non-greedy match: the pass
-- contains a nested `style = { ... },` that any lazy pattern stops at first.
local plate_pass_block = plate_pass_at and widgets_source:sub(plate_pass_at, plate_pass_at + 600) or nil

check(plate_pass_block ~= nil
    and plate_pass_block:find("visibility_function = WidgetVisibility.has_plate_icon", 1, true) ~= nil,
    "the backplate pass has no visibility gate, so it would draw on every marker")
check(widgets_source:find("has_plate_icon = function(content)", 1, true) ~= nil,
    "the backplate visibility function is missing")
check(widgets_source:find("widget.content.plate_icon = nil", 1, true) ~= nil,
    "the backplate is not cleared when a pooled widget is reused")
check(hud_source:find("widget.content.plate_icon = visual and visual.plate_icon or nil", 1, true) ~= nil,
    "the backplate is not driven by an explicit marker property")

-- Enemy markers must not gain the layer: they never name a plate.
local enemy_visual_block = hud_source:match("local function _enemy_visual(.-)" .. LF .. "local function ")

check(enemy_visual_block == nil or enemy_visual_block:find("plate_icon", 1, true) == nil,
    "enemy markers must not use the backplate layer")

for i = 1, #KINDS do
    local kind = KINDS[i]
    local block = hud_source:match(LF .. "    " .. kind .. " = {(.-)" .. LF .. "    },")

    check(block ~= nil and block:find("plate_icon = OBJECTIVE_PLATE_ICON", 1, true) ~= nil,
        kind .. ": does not opt into the backplate")
end

-- Only the icon changes for a daemonic growth step, and the shared presentation
-- table means an override has to be reset on every marker or it leaks.
check(expeditions_source:find("MISSION_OBJECTIVE_GROWTH_NAME_SUFFIXES", 1, true) ~= nil,
    "the growth objective name list is missing")
-- Anchored to the end of the name. Objective names are `objective_<mission>_<event>`,
-- so a suffix covers every mission running the event while matching strictly
-- less than a loose substring search would.
check(expeditions_source:find("string_sub(objective_name, -#suffix) == suffix", 1, true) ~= nil,
    "growth objectives are not matched on the name suffix")
-- Growth is a marker kind of its own, so its icon, size and position live in its
-- own presentation. Carried as an override on another kind's presentation, any
-- per-icon property set for that kind reached the growth marker too.
check(hud_source:find('overlay_icon = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_parasite"',
    1, true) ~= nil,
    "the growth icon is missing from its own presentation")
check(expeditions_source:find('return "mission_objective_growth"', 1, true) ~= nil,
    "growth units are not classified as their own kind")
check(hud_source:find("objective_overlay_icon", 1, true) == nil
    and expeditions_source:find("objective_overlay_icon", 1, true) == nil,
    "the icon override machinery is still present alongside the growth kind")

-- Its own kind purely for its visuals: it shares the generic category's
-- dropdown, colour and scale group, so it needs no settings of its own.
check(mod:get_marker_scale_group("mission_objective_growth") == "mission_objective_group",
    "the growth kind is not in the mission objective scale group")
check(mod:get_icon_distance_marker_display_mode("mission_objective_growth")
    == settings_store.show_mission_objective_other,
    "the growth kind does not follow the generic objective dropdown")

local growth_color = mod:get_marker_color("mission_objective_growth")

check(type(growth_color) == "table" and #growth_color == 4,
    "the growth kind has no resolvable colour")
check(env.NEARBY_OUTLINE_COLOR_BY_KIND.mission_objective_growth ~= nil,
    "the growth kind has no outline colour")
check(env.SCREEN_HIGHLIGHT_Z_OFFSET_BY_KIND.mission_objective_growth ~= nil,
    "the growth kind has no screen highlight offset")

-- The plate defaults to the near-black the game uses behind its own objective
-- markers, and is configurable. One colour for the family, since they share the
-- frame.
local background_color = mod:get_configurable_color("mission_objective_background_marker")

check(type(background_color) == "table" and #background_color == 4,
    "the objective background colour is not configurable")

if type(background_color) == "table" then
    check(background_color[2] < 60 and background_color[3] < 60 and background_color[4] < 60,
        "the objective background does not default to near-black")
end

check(color_settings.anchored_color_settings
    and color_settings.anchored_color_settings.mission_objective_icon_scale ~= nil,
    "the objective background colour has no sliders in the mission objective group")
check(hud_source:find("presentation.plate_color = _configured_objective_background_color", 1, true) ~= nil,
    "the backplate does not use the configured colour")

-- Keyed on the objective and its stage: a timed objective's progression changes
-- every tick, and keying on the whole field text let two of them consume the
-- probe budget before the objective under investigation was reached.
check(expeditions_source:find('"active_objective:" .. name .. "|" .. tostring(rawget(objective, "_stage"))',
    1, true) ~= nil,
    "the active objective probe can be starved by a timed objective")

-- This module body sits near LuaJIT's ceiling of 200 locals in one function, and
-- the debug scaffolding is what pushed it there. Crossing it is a load-time
-- error, not a subtle one, but it is worth catching here rather than in game.
local expeditions_locals = 0

for _ in expeditions_source:gmatch(LF .. "    local [_%a]") do
    expeditions_locals = expeditions_locals + 1
end

check(expeditions_locals < 200,
    "Radar_expeditions.lua declares " .. expeditions_locals .. " top level locals; LuaJIT allows 200")

-- The same ceiling applies to a file's main chunk, and the HUD element declares
-- its constants there. It has less room left than the line count suggests.
local hud_locals = 0

for _ in hud_source:gmatch(LF .. "local [_%a]") do
    hud_locals = hud_locals + 1
end

check(hud_locals < 200,
    "Radar_hud_element.lua declares " .. hud_locals .. " file level locals; LuaJIT allows 200")

-- The probe walks the game's markers for units the mod does not track, which is
-- the only way a unit in no objective system can be found at all.
check(expeditions_source:find("function _debug_probe_untracked_world_markers", 1, true) ~= nil,
    "the untracked world marker probe is missing")

-- The frame is the base layer and carries the family's identity, so it has a
-- colour of its own; the marker colour, and any puzzle state colour, belongs to
-- the icon drawn on top of it.
check(hud_source:find("presentation.overlay_color = marker_color", 1, true) ~= nil,
    "the icon does not follow the marker colour")
check(hud_source:find("presentation.color = _configured_objective_frame_color(marker_color)", 1, true) ~= nil,
    "the frame does not take its own colour")

local frame_color = mod:get_configurable_color("mission_objective_frame_marker")
local vanilla = color_settings.vanilla_objective_color

check(type(frame_color) == "table" and #frame_color == 4, "the frame colour is not configurable")

if type(frame_color) == "table" and type(vanilla) == "table" then
    for channel = 1, 4 do
        check(frame_color[channel] == vanilla[channel],
            "the frame colour does not default to the vanilla objective tint")
    end
end

-- The servo skull already carries a vanilla on-screen objective marker, so a
-- second screen-space highlight bracket around the same object is redundant.
check(env.NEARBY_HIGHLIGHT_EXCLUDED_KINDS ~= nil, "NEARBY_HIGHLIGHT_EXCLUDED_KINDS is missing")
check(env.NEARBY_HIGHLIGHT_EXCLUDED_KINDS
    and env.NEARBY_HIGHLIGHT_EXCLUDED_KINDS.mission_objective_servo_skull == true,
    "the servo skull is not excluded from nearby highlights")
check(env.NEARBY_HIGHLIGHT_EXCLUDED_KINDS
    and env.NEARBY_HIGHLIGHT_EXCLUDED_KINDS.mission_objective_scanner == nil,
    "only the servo skull should be excluded from nearby highlights")
check(tracking_source:find("NEARBY_HIGHLIGHT_EXCLUDED_KINDS[kind]", 1, true) ~= nil,
    "the highlight exclusion set is never consulted")
-- The radar highlight and the screen-space bracket are two separate gates, and
-- the bracket one used to skip the exclusion list, so an excluded kind still got
-- a bracket drawn around it in the world.
check(runtime_source:find("NEARBY_HIGHLIGHT_EXCLUDED_KINDS[kind]", 1, true) ~= nil,
    "the screen highlight bracket does not honour the exclusion set")

-- The flying skull bobs constantly, so the shared deadzone reads it as a floor
-- change, and it must never be hidden for being above or below the player.
check(tracking_source:find("VERTICAL_ARROW_Z_DEADZONE_BY_KIND", 1, true) ~= nil,
    "per-kind vertical arrow deadzone is missing")
check(tracking_source:find("mission_objective_servo_skull = 6", 1, true) ~= nil,
    "the servo skull has no raised vertical arrow deadzone")
check(tracking_source:find("_is_vertical_hide_exempt(kind)", 1, true) ~= nil,
    "the vertical hide exemption is never consulted")
-- Every objective kind is exempt, matched by predicate rather than listed.
check(tracking_source:find("_is_mission_objective_marker_kind(kind)", 1, true) ~= nil
    and tracking_source:find("VERTICAL_HIDE_EXEMPT_KINDS[kind] == true or _is_mission_objective_marker_kind(kind)",
        1, true) ~= nil,
    "objective kinds are not covered by the vertical hide exemption")
check(tracking_source:find("MOVING_TRACK_KINDS", 1, true) ~= nil,
    "the servo skull position refresh is missing")

-- Presence, not visibility: filtering bare objective steps on whether the game
-- is currently drawing their marker would make them blink with distance.
check(runtime_source:find("function _refresh_world_marker_units", 1, true) ~= nil,
    "the world marker unit set is missing")
check(runtime_source:find("marker.draw", 1, true) ~= nil
    and expeditions_source:find("_refresh_world_marker_units(_scratch_world_marker_units)", 1, true) ~= nil,
    "the objective scan does not build the world marker set")
check(expeditions_source:find("_objective_world_marker_seen[objective_name] == true", 1, true) ~= nil,
    "the world marker filter is not guarded by whether the list covers the objective")
-- The guard is a mission-long latch: rebuilt per scan, an objective whose last
-- unit is finished looks the same as one the list never described, and the
-- filter switches itself off exactly when it is needed.
check(expeditions_source:find("table_clear(_objective_world_marker_seen)", 1, true) ~= nil
    and select(2, expeditions_source:gsub("table_clear%(_objective_world_marker_seen%)", "")) == 1,
    "the world marker coverage latch must be cleared once per mission, not once per scan")

-- No positional offsets: the sizes above are even and the renderer corrects the
-- parity everywhere else, so nothing is nudged by hand.
check(OBJECTIVE_FRAME_SIZE ~= nil and OBJECTIVE_FRAME_SIZE % 2 == 0,
    "an odd frame size needs a parity correction at 100%, where none should be needed")
check(hud_source:find("overlay_offset_x", 1, true) == nil
    and hud_source:find("overlay_offset_base_size", 1, true) == nil,
    "per-icon positional offsets are back; link the icon to the frame size instead")

-- The vertical arrow. Where it sits and how big it is are two separate
-- proportions of the marker, so that its size can be tuned without walking it
-- across the marker -- which is what an overlap-based placement did, because
-- shrinking the arrow shrank the overlap and pushed the arrow outwards.
--
-- The constants are read out of the source rather than repeated here: a mirror
-- of the formula written from memory compares the spec against itself and
-- passes whatever the code does.
local ARROW_CENTRE_RATIO = tonumber(hud_source:match("local VERTICAL_ARROW_CENTRE_RATIO = ([%d.]+)"))
local ARROW_SIZE_RATIO = tonumber(hud_source:match("local VERTICAL_ARROW_SIZE_RATIO = ([%d.]+)"))
local ARROW_MIN_SIZE = tonumber(hud_source:match("local VERTICAL_ARROW_MIN_SIZE = (%d+)"))

check(ARROW_CENTRE_RATIO ~= nil and ARROW_SIZE_RATIO ~= nil and ARROW_MIN_SIZE ~= nil,
    "the arrow proportions are missing")

-- Both halves of the geometry must actually use them, or the constants are
-- decoration and the formula is still whatever it was.
check(hud_source:find("math_floor(arrow_base * VERTICAL_ARROW_SIZE_RATIO + 0.5)", 1, true) ~= nil,
    "the arrow size is not derived from its ratio")
check(hud_source:find("local arrow_centre = arrow_base * VERTICAL_ARROW_CENTRE_RATIO", 1, true) ~= nil,
    "the arrow placement is not derived from its centre ratio")
check(hud_source:find("arrow_centre - arrow_size * 0.5", 1, true) ~= nil,
    "the arrow is not centred on its anchor")
-- What this replaced, in both of its forms. The pixel sums held only at the
-- default size; the overlap tied placement to size.
check(hud_source:find("arrow_base * 0.45 + 1", 1, true) == nil
    and hud_source:find("math_floor(arrow_size * 0.5 + 1) + 2", 1, true) == nil
    and hud_source:find("VERTICAL_ARROW_OVERLAP_RATIO", 1, true) == nil,
    "the arrow placement is tied to its size again")

check(hud_source:find("local arrow_base = arrow_size_base or base_size", 1, true) ~= nil,
    "the arrow no longer sizes off the override")
check(hud_source:find("arrow_base_size", 1, true) ~= nil, "the arrow size override is missing")

local function arrow_geometry(base_size, arrow_base_size, size_ratio)
    local arrow_base = arrow_base_size or base_size
    local arrow_size = math.max(ARROW_MIN_SIZE,
        math.floor(arrow_base * (size_ratio or ARROW_SIZE_RATIO) + 0.5))
    local inset = (base_size - arrow_base) * 0.5
    local offset = math.floor(inset + arrow_base * ARROW_CENTRE_RATIO - arrow_size * 0.5 + 0.5)

    return arrow_size, offset - base_size * 0.5, offset + arrow_size - base_size, offset + arrow_size * 0.5
end

-- The point of splitting the two proportions: resizing the arrow must leave it
-- where it was. Under the old overlap this was false by construction -- a
-- quarter of the size change moved the arrow every time.
for _, base in ipairs({ OBJECTIVE_FRAME_SIZE, 25, 14 }) do
    for percent = 50, 200, 10 do
        local size = math.floor(base * percent / 100 + 0.5)
        local _, _, _, small_centre = arrow_geometry(size, nil, ARROW_SIZE_RATIO * 0.6)
        local _, _, _, large_centre = arrow_geometry(size, nil, ARROW_SIZE_RATIO * 1.4)

        check(math.abs(small_centre - large_centre) <= 1,
            "resizing the arrow moves it by " .. (large_centre - small_centre)
                .. "px on a " .. size .. "px marker, so size and placement are still coupled")
    end
end

-- The arrow is a secondary indicator. It reading as a second marker beside the
-- first is the thing being guarded against here.
-- What the user sees as the arrow drifting away is the part of it hanging past
-- the marker's corner. Under the old pixel sums that ran from nothing at half
-- scale to a sixth of the marker at double; it has to stay inside a narrow band.
for _, base in ipairs({ OBJECTIVE_FRAME_SIZE, 25, 14 }) do
    local lowest_ratio, highest_ratio = math.huge, -math.huge

    for percent = 50, 200 do
        local size = math.floor(base * percent / 100 + 0.5)
        local arrow_size, _, overhang, centre = arrow_geometry(size, nil)

        -- The placement guarantee, stated exactly: the arrow's centre never
        -- lands more than a pixel from its nominal anchor, at any scale. This is
        -- what the old pixel sums broke -- they put the centre at a fraction of
        -- the marker that moved with the marker's size.
        check(math.abs(centre - size * ARROW_CENTRE_RATIO) <= 1,
            "the arrow centre on a " .. size .. "px marker sits "
                .. string.format("%.1f", centre - size * ARROW_CENTRE_RATIO)
                .. "px from its anchor")
        -- And it stays attached: at least half of it overlaps the marker.
        check(overhang <= arrow_size * 0.5,
            "the arrow hangs " .. overhang .. "px past a " .. size
                .. "px marker, which is more than half of its own " .. arrow_size .. "px")

        -- Below the legibility floor the arrow stops being a proportion of
        -- anything on purpose, so those sizes are not part of the band. The
        -- floor only ever makes the arrow larger, never smaller, which is what
        -- keeps a tiny marker's arrow readable.
        if size * ARROW_SIZE_RATIO >= ARROW_MIN_SIZE then
            lowest_ratio = math.min(lowest_ratio, arrow_size / size)
            highest_ratio = math.max(highest_ratio, arrow_size / size)
        else
            check(arrow_size == ARROW_MIN_SIZE,
                "a " .. size .. "px marker's arrow is not held at the legibility floor")
        end
    end

    check(highest_ratio - lowest_ratio < 0.1,
        "the arrow size on a " .. base .. "px marker swings from "
            .. string.format("%.2f to %.2f", lowest_ratio, highest_ratio)
            .. " of the marker across the scale range")
    check(highest_ratio <= 0.4,
        "the arrow reaches " .. string.format("%.2f", highest_ratio) .. " of a " .. base
            .. "px marker, which reads as a second marker rather than an elevation hint")
end

-- The placement was calibrated by eye and is being kept; only the size changed.
-- The frame is 26px with a 12px icon inside it, so an arrow larger than the icon
-- is the complaint this is guarding against.
local default_arrow_size, _, _, default_centre = arrow_geometry(OBJECTIVE_FRAME_SIZE, nil)

-- Bounded against the frame, which is shared and fixed, rather than against the
-- icon sizes, which are hand-tuned per category: an arrow the size of the whole
-- marker is a defect, an arrow larger than one deliberately small icon is a
-- judgement call and not this spec's to make.
check(default_arrow_size < OBJECTIVE_FRAME_SIZE * 0.5,
    "the arrow is " .. default_arrow_size .. "px on a " .. OBJECTIVE_FRAME_SIZE
        .. "px frame, so it reads as a second marker rather than an elevation hint")
check(math.abs(default_centre - 23.5) <= 1,
    "the arrow centre on the default objective frame moved to " .. default_centre
        .. "px; the calibrated placement is 23px from the marker's corner")

-- One arrow formula for every marker type: the frame is the objective marker's
-- box, so the standard placement already anchors the arrow to it and scales with
-- it. A special case here would be a second thing to keep in step.
check(hud_source:find("local inset = (base_size - arrow_base) * 0.5", 1, true) ~= nil,
    "the arrow placement has diverged from the shared formula")

-- The oversized objective marker must end up with the same arrow as the others.
local nominal_size, nominal_from_centre = arrow_geometry(16, nil)
local override_size, override_from_centre = arrow_geometry(28, 16)

check(override_size == nominal_size, "the overridden arrow is not the size of a nominal marker arrow")
check(override_from_centre == nominal_from_centre, "the overridden arrow does not sit where a nominal one does")

-- Centring. The frame's centre and the icon's half size are floored
-- independently, so they cancel only when the two sizes share a parity. Both
-- nominal sizes are even, but the icon scale is applied to each separately and
-- about half the scale values break the match -- 120% did while 125% did not,
-- which is why no static offset could ever have fixed it. The renderer moves the
-- icon to the nearer integer of the frame's parity instead.
check(hud_source:find("if (overlay_size - size) % 2 ~= 0 then", 1, true) ~= nil,
    "the overlay parity correction is missing, so the icon sits half a pixel off at some scales")
check(hud_source:find("local exact_overlay_size = nil", 1, true) ~= nil,
    "the unrounded overlay size is gone, so the correction cannot pick the nearer candidate")
-- Which way it corrects matters as much as that it corrects: always shrinking
-- would centre the icon and quietly bias it a pixel small at every scale that
-- needs a correction. Checked against the source, because a mirror of the rule
-- written here would only ever agree with itself.
check(hud_source:find("if exact_overlay_size > overlay_size or overlay_size <= 4 then", 1, true) ~= nil,
    "the parity correction no longer picks the nearer of the two candidates")

local function overlay_geometry(size, overlay_base, frame_base)
    local exact = size * (overlay_base / frame_base)
    local overlay_size = math.max(4, math.floor(exact + 0.5))

    if (overlay_size - size) % 2 ~= 0 then
        if exact > overlay_size or overlay_size <= 4 then
            overlay_size = overlay_size + 1
        else
            overlay_size = overlay_size - 1
        end
    end

    return overlay_size
end

-- Exact centring at every size the scale slider can produce, for every objective
-- icon, and at a size cost of no more than a pixel.
local grew = 0
local shrank = 0

-- Over the sizes actually in the source, so a hand-tuned value is verified
-- rather than assumed: this is what says an odd nominal size is centred too.
for kind, icon_base in pairs(ICON_SIZE_BY_KIND) do
    for size = 10, 72 do
        local overlay_size = overlay_geometry(size, icon_base, OBJECTIVE_FRAME_SIZE)
        local drawn_left = math.floor(size * 0.5) - math.floor(overlay_size * 0.5)
        local centred_left = (size - overlay_size) / 2
        local uncorrected = math.max(4, math.floor(size * (icon_base / OBJECTIVE_FRAME_SIZE) + 0.5))

        check(drawn_left == centred_left,
            kind .. " sits " .. (drawn_left - centred_left) .. "px off centre in a " .. size .. "px frame")
        check(math.abs(overlay_size - uncorrected) <= 1,
            kind .. " changes size by more than a pixel to stay centred in a " .. size .. "px frame")

        if overlay_size > uncorrected then
            grew = grew + 1
        elseif overlay_size < uncorrected then
            shrank = shrank + 1
        end
    end
end

-- Both directions have to occur. A rule that only ever shrinks is centred but
-- biased, and would leave every corrected icon a pixel smaller than intended.
check(grew > 0 and shrank > 0,
    "the parity correction only ever " .. (grew > 0 and "grows" or "shrinks")
        .. " the icon, so it is biased rather than choosing the nearer size")

-- The corner-anchored overlay is not centred on anything, so it must be left
-- exactly as it was.
local bottom_right_block = hud_source:match('if visual and visual%.overlay_anchor == "bottom_right" then(.-)else')

check(bottom_right_block ~= nil and bottom_right_block:find("overlay_size", 1, true) ~= nil
    and bottom_right_block:find("% 2", 1, true) == nil,
    "the parity correction has leaked into the corner-anchored overlay")


-- Lua locals are invisible above their declaration, so a function written
-- earlier in the file that touches one silently reads nil and writes a global.
-- This has shipped a runtime error once and two dead resets, so it is checked
-- mechanically rather than by eye.
local NEWLINE = string.char(10)
local LINE_PATTERN = "([^" .. NEWLINE .. "]*)" .. NEWLINE .. "?"

local function check_local_use_before_declaration(source, label)
    local declared_at = {}
    local line_number = 0

    for line in source:gmatch(LINE_PATTERN) do
        line_number = line_number + 1

        local name = line:match("^%s*local%s+([_%a][_%w]*)%s*=")
            or line:match("^%s*local%s+function%s+([_%a][_%w]*)")

        if name and declared_at[name] == nil then
            declared_at[name] = line_number
        end
    end

    line_number = 0

    for line in source:gmatch(LINE_PATTERN) do
        line_number = line_number + 1

        -- Only underscore-prefixed file locals; those are the ones this codebase
        -- uses for module state.
        for name in line:gmatch("([_][_%w]*)") do
            local declared = declared_at[name]

            if declared and declared > line_number and not line:match("^%s*%-%-") then
                check(false, label .. ": `" .. name .. "` used on line " .. line_number
                    .. " but declared as a local on line " .. declared)
            end
        end
    end
end

-- The growth tentacles are the one marker the mod finds by shape rather than by
-- name, so the numbers that shape is measured against are checked here: they
-- came off a run and a comfortable guess would quietly widen or narrow them.
local growth_eye_link = expeditions_source:match("link_squared = ([%d.]+),")

check(growth_eye_link ~= nil, "the tentacle shape has no link distance")

if growth_eye_link ~= nil then
    local link = tonumber(growth_eye_link)

    -- The prefab's widest pair measured 0.407 m, so the link must clear it.
    check(link > 0.407 * 0.407,
        "the tentacle link distance of " .. growth_eye_link .. " m^2 is under the prefab's own 0.407 m pair")
    -- The level's own breakables near an event stood metres apart. A link this
    -- wide would start joining them.
    check(link < 1, "the tentacle link distance of " .. growth_eye_link .. " m^2 is wide enough to join scenery")
end

check(expeditions_source:find("cluster_size = 3,", 1, true) ~= nil,
    "a tentacle carries three eyes")

-- A tentacle outlives its own eyes. The shape can only be matched while all
-- three are standing, because a destroyed one leaves the destructible system
-- entirely, so the tentacle has to be remembered by the units it was made of
-- instead of re-derived every scan from whatever is left.
check(expeditions_source:find("group_of[units[i]] == nil", 1, true) ~= nil
    and expeditions_source:find("group_of[member] = group", 1, true) ~= nil,
    "tentacle eyes are not registered to a tentacle, so the marker dies with the first eye")
-- Both ends of the match, or a new tentacle at a cleared spawn point could
-- absorb the remains of its predecessor.
check(expeditions_source:find("if j ~= i and group_of[units[j]] == nil then", 1, true) ~= nil,
    "an eye already belonging to a tentacle can be matched into another one")
-- Presence in the destructible system is the liveness signal, since that is how
-- the game retires an eye.
check(expeditions_source:find("if extension_map[member] ~= nil", 1, true) ~= nil,
    "a tentacle's eyes are not checked against the destructible system itself")
-- The marker rides the first eye still standing in registration order, so it
-- moves only when the eye carrying it is destroyed. Checked against the source:
-- registration order is hash order, so a rule taking the last standing eye
-- instead agrees with this one whenever the carrier happens to be last, and a
-- behavioural test cannot be relied on to tell them apart.
check(expeditions_source:find("if carrier[group] == nil then", 1, true) ~= nil,
    "the tentacle marker hops to another eye whenever any of them is destroyed")

-- Through the shared claim, so the retirement, liveness and health gates that
-- every other objective marker passes apply to these too.
check(expeditions_source:find('_claim_mission_objective_unit(member, "mission_objective_growth"', 1, true) ~= nil,
    "tentacle eyes must be claimed through the shared choke point, not tracked directly")

-- Last of the passes: these units are in no objective system, so they must not
-- take a classification away from one that is.
local tentacle_call = expeditions_source:find(LF .. "            _track_growth_tentacle_units(", 1, true)
local target_pass_call = expeditions_source:find("_track_mission_objective_units(MISSION_OBJECTIVE_TARGET_SYSTEM", 1, true)

check(tentacle_call ~= nil, "the objective scan never looks for growth tentacles")
check(tentacle_call ~= nil and target_pass_call ~= nil and tentacle_call > target_pass_call,
    "the tentacle pass must run after the objective system's own passes")

-- Quadratic in what the range test lets through, so it needs a ceiling.
check(expeditions_source:find("candidate_limit", 1, true) ~= nil,
    "the tentacle pairwise pass is unbounded")

-- An objective the game is itself marking is drawn however far away it is. The
-- signal is the vanilla marker list, which is where the HUD gets its own
-- markers, so the exemption lasts exactly as long as the marker the player can
-- see and no approximation of it has to be maintained alongside.
check(expeditions_source:find("function _objective_ignores_radar_range(unit)", 1, true) ~= nil,
    "the range exemption has no accessor")
-- One decision. Each objective system answers "is the HUD showing this" its own
-- way and writes what it knows into one set, so a new objective type adds an
-- answer rather than another branch here.
check(select(2, expeditions_source:gsub("function _objective_ignores_radar_range", "")) == 1,
    "the range exemption is decided in more than one place")
-- Without the availability guard, a mission where the list cannot be read would
-- fall back on a stale table from the previous one.
check(expeditions_source:find(
    "if _world_marker_units_available and _scratch_world_marker_units[unit] == true then", 1, true) ~= nil,
    "the exemption does not check that the marker list was readable")
-- Neither a tentacle nor a scan target reaches the game's marker list, so both
-- need their own system to answer for them, into the shared set.
check(expeditions_source:find("return _scratch_objective_range_exempt[unit] == true", 1, true) ~= nil,
    "the systems that never reach the marker list have no way to exempt anything")
check(expeditions_source:find("if growth_marked then", 1, true) ~= nil
    and expeditions_source:find("_scratch_objective_range_exempt[member] = true", 1, true) ~= nil,
    "tentacles are exempted without checking that the game is marking their growth")
-- A scan target the zone has selected and not yet had scanned is what the
-- vanilla HUD draws its own marker from. Both claim paths, since the fallback
-- one runs whenever the selection cannot be read.
check(select(2, expeditions_source:gsub("_scratch_objective_range_exempt%[unit%] = true", "")) == 2,
    "only one of the two scan target paths exempts what it claims")
-- Rebuilt from nothing every scan and before any pass can write to it, so an
-- exemption cannot outlive the state that earned it.
check(expeditions_source:find("table_clear(_scratch_inactive_objective_units)", 1, true) ~= nil
    and expeditions_source:find("table_clear(_scratch_objective_range_exempt)", 1, true)
        < expeditions_source:find(LF .. "            _track_mission_objective_scan_zones(", 1, true),
    "the range exemption set is not cleared ahead of the passes that fill it")

local bypass = tracking_source:find("_objective_ignores_radar_range(unit) then", 1, true)
local range_test = tracking_source:find("if distance_sq_horizontal > max_range_sq and not ignore_range then", 1, true)

check(bypass ~= nil, "the radar target build never consults the game's own markers")
check(bypass ~= nil and range_test ~= nil and bypass < range_test,
    "the exemption is decided after the range test, where it can no longer let anything through")

-- Objectives only. Enemies, pickups and luggables keep their own range rules.
local bypass_block = tracking_source:match("if not ignore_range" .. LF .. "(.-)ignore_range = true")

check(bypass_block ~= nil and bypass_block:find("_is_mission_objective_marker_kind(kind)", 1, true) ~= nil,
    "the range exemption is not restricted to mission objective markers")

-- A kind that is registered everywhere but that no detection path can ever
-- assign costs a settings dropdown, a colour picker and a tooltip in twelve
-- languages for a marker that cannot appear. `mission_objective_console` was
-- exactly that from the first commit of this feature until it was removed, so
-- registration alone is no longer taken as evidence that a kind is real.
--
-- Every kind the scan can produce names itself as a quoted string somewhere in
-- the detection module -- a claim, a dedicated system's kind, an interaction
-- type's mapping, or the resolver's own fallback. The registry uses bare table
-- keys, so being registered does not satisfy this.
for _, kind in ipairs(KINDS) do
    check(expeditions_source:find('"' .. kind .. '"', 1, true) ~= nil,
        kind .. " is registered as a marker kind but no detection path can produce it")
end

-- And the reverse: nothing may be registered that is not in this spec's list,
-- so a new kind cannot be added to the settings without being swept here.
local registry = expeditions_source:match("local MISSION_OBJECTIVE_MARKER_KINDS = {(.-)" .. LF .. "    }")

check(registry ~= nil, "the marker kind registry is missing")

if registry ~= nil then
    local registered = 0

    for _ in registry:gmatch("mission_objective_[%a_]+ = true") do
        registered = registered + 1
    end

    check(registered == #KINDS,
        "the detection module registers " .. registered .. " marker kinds but this spec sweeps " .. #KINDS)
end

check_local_use_before_declaration(expeditions_source, "Radar_expeditions.lua")
check_local_use_before_declaration(tracking_source, "Radar_tracking.lua")

if #problems > 0 then
    for i = 1, #problems do
        io.write("FAIL ", problems[i], "\n")
    end

    io.write("\n", tostring(#problems), " problems\n")
    os.exit(1)
end

io.write("all wiring checks passed for ", tostring(#KINDS), " kinds\n")
