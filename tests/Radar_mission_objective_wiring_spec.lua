-- Installs the real definition modules and asserts every mission objective kind
-- is registered everywhere a marker kind has to be registered, and that the
-- shared presentation rules hold.
local KINDS = {
    "mission_objective_scanner",
    "mission_objective_hacking",
    "mission_objective_console",
    "mission_objective_servo_skull",
    "mission_objective_other",
}

local SETTING_BY_KIND = {
    mission_objective_scanner = "show_mission_objective_scanner",
    mission_objective_hacking = "show_mission_objective_hacking",
    mission_objective_console = "show_mission_objective_console",
    mission_objective_servo_skull = "show_mission_objective_servo_skull",
    mission_objective_other = "show_mission_objective_other",
}

local settings_store = {
    show_mission_objective_scanner = "icon_only",
    show_mission_objective_hacking = "icon_distance",
    show_mission_objective_console = "off",
    show_mission_objective_servo_skull = "icon_only",
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

    -- All five share the vanilla objective tint so the radar reads as the same
    -- family as the on-screen HUD marker.
    local expected = color_settings.vanilla_objective_color
    local outline = env.NEARBY_OUTLINE_COLOR_BY_KIND[kind]

    check(type(expected) == "table", "vanilla objective color is not exported")

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
local OBJECTIVE_ICON_SIZE = tonumber(hud_source:match("local OBJECTIVE_ICON_SIZE = (%d+)"))
local OBJECTIVE_ICON_SIZE_PADDED = tonumber(hud_source:match("local OBJECTIVE_ICON_SIZE_PADDED = (%d+)"))
local EXPECTED_ICON_SIZE_BY_KIND = {
    mission_objective_scanner = OBJECTIVE_ICON_SIZE,
    mission_objective_hacking = OBJECTIVE_ICON_SIZE,
    mission_objective_console = OBJECTIVE_ICON_SIZE,
    mission_objective_servo_skull = OBJECTIVE_ICON_SIZE,
    -- Its art sits small inside its own box, so it needs a larger nominal size
    -- to carry the same visual weight.
    mission_objective_other = OBJECTIVE_ICON_SIZE_PADDED,
}

-- Calibrated against the game's own marker, whose icon sits well inside the
-- diamond rather than filling it. The scale multiplies the frame afterwards, so
-- this ratio is what holds at every scale.
check(OBJECTIVE_ICON_SIZE ~= nil and OBJECTIVE_FRAME_SIZE ~= nil
    and OBJECTIVE_ICON_SIZE / OBJECTIVE_FRAME_SIZE < 0.55,
    "the objective icon fills too much of its frame to match the game's marker")

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
        local overlay_symbol = block:match("overlay_base_size = ([%u_]+)")
        local overlay_base = overlay_symbol == "OBJECTIVE_ICON_SIZE" and OBJECTIVE_ICON_SIZE
            or overlay_symbol == "OBJECTIVE_ICON_SIZE_PADDED" and OBJECTIVE_ICON_SIZE_PADDED
            or tonumber(block:match("overlay_base_size = (%d+)"))

        check(overlay_base == EXPECTED_ICON_SIZE_BY_KIND[kind],
            kind .. ": icon draws at " .. tostring(overlay_base) .. ", not its established size")
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
check(expeditions_source:find('"content/ui/materials/icons/circumstances/havoc/havoc_mutator_parasite"', 1, true) ~= nil,
    "the growth icon is missing")
check(hud_source:find("presentation.overlay_icon = (meta and meta.objective_overlay_icon) or default_overlay_icon",
    1, true) ~= nil,
    "the icon override does not reset for markers that do not carry one")
-- The game's icons are not normalised, so a replaced icon carries its own fit.
-- The frame is never touched: the family keeps one footprint.
check(hud_source:find("presentation.overlay_base_size = (meta and meta.objective_overlay_size)", 1, true) ~= nil,
    "a replaced icon cannot carry its own size")
check(hud_source:find("or DEFAULT_OVERLAY_BASE_SIZE_BY_KIND[target_kind]", 1, true) ~= nil,
    "the icon size override does not reset for markers that do not carry one")
check(expeditions_source:find("meta.objective_overlay_size = MISSION_OBJECTIVE_GROWTH_ICON_SIZE", 1, true) ~= nil,
    "the growth icon carries no size of its own")

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

-- The probe walks the game's markers for units the mod does not track, which is
-- the only way a unit in no objective system can be found at all.
check(expeditions_source:find("function _debug_probe_untracked_world_markers", 1, true) ~= nil,
    "the untracked world marker probe is missing")

-- The frame is the base layer, so the configured colour reaches the icon only if
-- it is passed on; otherwise the icon stays white while the frame turns red.
check(hud_source:find("presentation.overlay_color = presentation.color", 1, true) ~= nil,
    "the icon does not follow the marker colour")

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

-- The objective_main art sits small inside its box, so that presentation raises
-- `size` and decouples the vertical arrow from it. Mirrors the geometry in
-- _apply_marker_widget.
check(hud_source:find("arrow_base_size", 1, true) ~= nil, "the arrow size override is missing")
check(hud_source:find("local arrow_base = arrow_size_base or base_size", 1, true) ~= nil,
    "the arrow no longer sizes off the override")

local function arrow_geometry(base_size, arrow_base_size)
    local arrow_base = arrow_base_size or base_size
    local arrow_size = math.max(6, math.floor(arrow_base * 0.45 + 1))
    local overlap = math.floor(arrow_size * 0.5 + 1) + 2
    local inset = (base_size - arrow_base) * 0.5
    local offset = math.floor(inset + arrow_base - overlap + 0.5)

    return arrow_size, offset - base_size * 0.5
end

-- Without an override the geometry must equal the original formula exactly, so
-- no existing marker moves.
for _, size in ipairs({ 12, 14, 16, 20, 28, 40 }) do
    local legacy_size = math.max(6, math.floor(size * 0.45 + 1))
    local legacy_offset = size - (math.floor(legacy_size * 0.5 + 1) + 2)
    local actual_size, actual_from_centre = arrow_geometry(size, nil)

    check(actual_size == legacy_size, "arrow size changed at marker size " .. size)
    check(actual_from_centre == legacy_offset - size * 0.5, "arrow position changed at marker size " .. size)
end

-- A per-icon nudge for art that is not centred in its own texture, scaled with
-- the marker so it holds at any icon scale. Only the icon that needs it carries
-- one; every other marker is centred as before.
check(hud_source:find("local nudge_base = visual and tonumber(visual.overlay_offset_base_size) or nil",
    1, true) ~= nil,
    "there is no per-icon offset for art that is not centred in its texture")

local nudged_kinds = 0

for i = 1, #KINDS do
    local block = hud_source:match(LF .. "    " .. KINDS[i] .. " = {(.-)" .. LF .. "    },")

    if block and block:find("overlay_offset_x", 1, true) ~= nil then
        nudged_kinds = nudged_kinds + 1

        check(block:find("overlay_offset_base_size = OBJECTIVE_FRAME_SIZE", 1, true) ~= nil,
            KINDS[i] .. ": has an offset with no base size, so it would not scale")
    end
end

check(nudged_kinds == 1, "expected exactly one icon to need a nudge, found " .. nudged_kinds)

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
