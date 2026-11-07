-- Whether a teammate is in coherency with the local player, from the scan to the marker.
-- Installs the players module alone against a fake player manager, extensions and owner map,
-- runs `_refresh_player_units` and reads the meta each teammate is tracked with. The team panel's
-- rule decides; the teammate's coherency extension lists a unit the local player owns while the
-- teammate is alive, not hogtied and has unit data, and anything unreadable counts as out of
-- coherency, reported as `false`, and an annotation that is off reports nil. Then loads the HUD
-- element against a fake UI stack and checks the coherency look `_target_visual` gives every
-- teammate style; the game's interaction marker backplate in its configured colour, the ring in
-- the teammate's colour while in coherency, a flash when that changes between frames, and a
-- player colour lightened where it would not read on the backplate.

local PLAYERS_PATH = "Radar/scripts/mods/Radar/Radar_players.lua"
local HUD_PATH = "Radar/scripts/mods/Radar/ui/Radar_hud_element.lua"
local LOCALIZATION_PATH = "Radar/scripts/mods/Radar/Radar_localization.lua"
local COLOR_SETTINGS_PATH = "Radar/scripts/mods/Radar/Radar_color_settings.lua"
local BACKPLATE = "content/ui/materials/hud/interactions/frames/mission_back"
local RING = "content/ui/materials/hud/interactions/frames/mission_top"
local FLASH = "content/ui/materials/hud/interactions/frames/mission_tag"
local BACKPLATE_COLOR = { 200, 10, 11, 12 }
local FRAME_COLOR = { 230, 223, 229, 219 }
local GAINED_FLASH_COLOR = { 190, 70, 200, 60 }
local LOST_FLASH_COLOR = { 180, 250, 50, 40 }
local SETTING_ID = "show_player_coherency_annotation"

local function assert_true(value, message)
    if value ~= true then
        error(message or "expected true", 2)
    end
end

local function assert_nil(value, message)
    if value ~= nil then
        error((message or "expected nil") .. ": got " .. tostring(value), 2)
    end
end

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function clone(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}

    for key, field in pairs(value) do
        copy[key] = clone(field)
    end

    return copy
end

local function same_values(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end

    for key, value in pairs(a) do
        if not same_values(value, b[key]) then
            return false
        end
    end

    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end

    return true
end

local function named_upvalue(fn, expected_name)
    for index = 1, 255 do
        local name, value = debug.getupvalue(fn, index)

        if name == nil then
            error("missing upvalue `" .. expected_name .. "`", 2)
        elseif name == expected_name then
            return value
        end
    end
end

-- --------------------------------------------------------------------------------------------
-- The players module against a fake game
-- --------------------------------------------------------------------------------------------

--- A unit data extension whose character state, disabling and wielded slot the test sets.
local function new_unit_data(character_state, disabling_type)
    return {
        read_component = function(_, name)
            if name == "character_state" then
                return { state_name = character_state or "walking" }
            elseif name == "disabled_character_state" then
                return { is_disabled = disabling_type ~= nil, disabling_type = disabling_type }
            elseif name == "inventory" then
                return { wielded_slot = "slot_primary" }
            end

            return nil
        end,
    }
end

local function new_player(slot, archetype)
    local player = { owned_units = {} }

    function player:slot()
        return slot
    end

    function player:name()
        return "player " .. slot
    end

    function player:profile()
        return { archetype = { name = archetype } }
    end

    return player
end

--- Installs the players module into a world with the local player, their companion and two
-- teammates, all alive and healthy, and nobody in coherency yet.
local function new_players_harness()
    local settings = { show_players = "marked_icon" }
    local world = {
        alive = {},
        health = {},
        extensions = {},
        owners = {},
        coherency_reads = 0,
    }
    local harness = { settings = settings, world = world }
    local players = {}
    local mod = {}
    local tracked
    local cleared = {}

    function mod:get(setting_id)
        return settings[setting_id]
    end

    local player_unit_spawn = {
        owner = function(_, unit)
            return world.owners[unit]
        end,
    }
    local managers = { state = { player_unit_spawn = player_unit_spawn } }
    local env = setmetatable({
        mod = mod,
        Managers = managers,
        CompanionServoSkullSettings = { STATES = {} },
        ScriptUnit = {
            has_extension = function(unit, system_name)
                local extensions = world.extensions[unit]

                return extensions and extensions[system_name] or nil
            end,
        },
        _player_manager = function()
            return {
                players = function()
                    return players
                end,
            }
        end,
        _local_player = function()
            return harness.local_player
        end,
        _safe_unit_alive = function(unit)
            return unit ~= nil and world.alive[unit] == true
        end,
        _safe_health_alive = function(unit)
            return world.health[unit]
        end,
        _track_unit = function(unit, kind, source, meta)
            tracked[unit] = { kind = kind, source = source, meta = meta }
        end,
        _clear_tracked_unit_from_source = function(unit, source)
            cleared[#cleared + 1] = { unit = unit, source = source }
        end,
    }, { __index = _G })
    local installer = assert(loadfile(PLAYERS_PATH))()

    installer(env)

    --- Adds a unit to the world, alive and healthy, with unit data in a character state.
    function harness.add_unit(name, owner, character_state)
        local unit = { name = name }

        world.alive[unit] = true
        world.health[unit] = true
        world.owners[unit] = owner
        world.extensions[unit] = { unit_data_system = new_unit_data(character_state) }

        return unit
    end

    --- Gives a unit a coherency extension that lists these units.
    function harness.set_coherency(unit, units)
        local in_coherence_units = {}

        for i = 1, #units do
            in_coherence_units[units[i]] = true
        end

        world.extensions[unit].coherency_system = {
            in_coherence_units = function()
                world.coherency_reads = world.coherency_reads + 1

                return in_coherence_units
            end,
        }
    end

    function harness.add_player(player)
        players[#players + 1] = player
    end

    function harness.remove_player(player)
        for i = #players, 1, -1 do
            if players[i] == player then
                table.remove(players, i)
            end
        end
    end

    function harness.set_player_unit_spawn(value)
        managers.state.player_unit_spawn = value
    end

    --- Runs one player scan and returns the tracked entries by unit, and the units cleared since.
    function harness.scan()
        tracked = {}
        cleared = {}
        world.coherency_reads = 0
        env._refresh_player_units()

        return tracked, cleared
    end

    harness.local_player = new_player(1, "veteran")
    harness.teammate = new_player(2, "zealot")
    harness.other = new_player(3, "psyker")
    harness.local_unit = harness.add_unit("local", harness.local_player)
    harness.companion_unit = harness.add_unit("local companion", harness.local_player)
    harness.teammate_unit = harness.add_unit("teammate", harness.teammate)
    harness.other_unit = harness.add_unit("other", harness.other)
    harness.local_player.player_unit = harness.local_unit
    harness.teammate.player_unit = harness.teammate_unit
    harness.other.player_unit = harness.other_unit
    harness.add_player(harness.local_player)
    harness.add_player(harness.teammate)
    harness.add_player(harness.other)

    return harness
end

--- The meta a teammate unit was tracked with, which must be a teammate entry.
local function teammate_meta(tracked, unit)
    local entry = tracked[unit]

    assert_true(entry ~= nil, "the teammate was not tracked")
    assert_equal("player_teammate", entry.kind, "kind")
    assert_equal("player_manager", entry.source, "source")

    return entry.meta
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("a teammate in coherency with the local player is marked, one in coherency only with others is not", function()
    local harness = new_players_harness()

    harness.set_coherency(harness.teammate_unit, { harness.teammate_unit, harness.local_unit, harness.other_unit })
    harness.set_coherency(harness.other_unit, { harness.other_unit, harness.teammate_unit })

    local tracked = harness.scan()
    local meta = teammate_meta(tracked, harness.teammate_unit)

    assert_true(meta.player_in_coherency, "the teammate in coherency with the local player")
    assert_equal(2, meta.player_slot, "the teammate keeps its slot")
    assert_equal("zealot", meta.archetype_name, "the teammate keeps its archetype")
    assert_nil(meta.player_radar_state, "the teammate has no state")
    assert_equal(false, teammate_meta(tracked, harness.other_unit).player_in_coherency,
        "a teammate in coherency only with another teammate")
    assert_nil(tracked[harness.local_unit], "the local player is tracked as a teammate")
end)

test("coherency with the local player's companion counts, as on the team panel", function()
    local harness = new_players_harness()

    harness.set_coherency(harness.teammate_unit, { harness.teammate_unit, harness.companion_unit })

    assert_true(teammate_meta(harness.scan(), harness.teammate_unit).player_in_coherency,
        "the teammate in coherency with the local player's companion")
end)

test("coherency that cannot be read counts as out of coherency", function()
    local cases = {
        ["no coherency extension"] = function()
        end,
        ["the coherency read fails"] = function(harness)
            harness.world.extensions[harness.teammate_unit].coherency_system = {
                in_coherence_units = function()
                    error("not ready")
                end,
            }
        end,
        ["the coherency read is not a set"] = function(harness)
            harness.world.extensions[harness.teammate_unit].coherency_system = {
                in_coherence_units = function()
                    return "units"
                end,
            }
        end,
        ["no player unit spawn manager"] = function(harness)
            harness.set_coherency(harness.teammate_unit, { harness.local_unit })
            harness.set_player_unit_spawn(nil)
        end,
        ["the owner lookup fails"] = function(harness)
            harness.set_coherency(harness.teammate_unit, { harness.local_unit })
            harness.set_player_unit_spawn({
                owner = function()
                    error("no owners")
                end,
            })
        end,
        ["the health is unknown"] = function(harness)
            harness.set_coherency(harness.teammate_unit, { harness.local_unit })
            harness.world.health[harness.teammate_unit] = nil
        end,
        ["no unit data"] = function(harness)
            harness.set_coherency(harness.teammate_unit, { harness.local_unit })
            harness.world.extensions[harness.teammate_unit].unit_data_system = nil
        end,
        ["the character state cannot be read"] = function(harness)
            harness.set_coherency(harness.teammate_unit, { harness.local_unit })
            harness.world.extensions[harness.teammate_unit].unit_data_system = {
                read_component = function()
                    error("no component")
                end,
            }
        end,
    }

    for name, setup in pairs(cases) do
        local harness = new_players_harness()

        setup(harness)

        local meta = teammate_meta(harness.scan(), harness.teammate_unit)

        assert_equal(false, meta.player_in_coherency, name)
    end

    -- Without a local player, an unowned unit would match a missing owner.
    local harness = new_players_harness()
    local unowned = harness.add_unit("unowned", nil)

    harness.set_coherency(harness.teammate_unit, { unowned })
    harness.local_player = nil

    local tracked = harness.scan()

    for unit, entry in pairs(tracked) do
        if entry.kind == "player_teammate" then
            assert_nil(entry.meta.player_in_coherency, "no local player, " .. unit.name)
        end
    end

    assert_equal(0, harness.world.coherency_reads, "coherency was read without a local player")
end)

test("dead and hogtied teammates show no coherency, other states keep it beside their icon", function()
    local cases = {
        { name = "dead", health = false, radar_state = "dead", in_coherency = false },
        { name = "hogtied", character_state = "hogtied", radar_state = "rescue", in_coherency = false },
        { name = "knocked down", character_state = "knocked_down", radar_state = "rescue", in_coherency = true },
        { name = "ledge hanging", character_state = "ledge_hanging", radar_state = "rescue", in_coherency = true },
        { name = "netted", disabling_type = "netted", radar_state = "captured", in_coherency = true },
    }

    for i = 1, #cases do
        local case = cases[i]
        local harness = new_players_harness()
        local unit = harness.teammate_unit

        harness.world.extensions[unit].unit_data_system = new_unit_data(case.character_state, case.disabling_type)
        harness.set_coherency(unit, { harness.local_unit })

        if case.health ~= nil then
            harness.world.health[unit] = case.health
        end

        local meta = teammate_meta(harness.scan(), unit)

        assert_equal(case.radar_state, meta.player_radar_state, case.name .. " state icon")
        assert_equal(case.in_coherency, meta.player_in_coherency, case.name .. " coherency")
    end
end)

test("the setting is on unless turned off, and off or hidden teammates read no coherency", function()
    local harness = new_players_harness()

    harness.set_coherency(harness.teammate_unit, { harness.local_unit })

    for _, value in ipairs({ "unsaved", true }) do
        harness.settings[SETTING_ID] = value ~= "unsaved" and value or nil
        assert_true(teammate_meta(harness.scan(), harness.teammate_unit).player_in_coherency,
            "the setting " .. tostring(value))
    end

    harness.settings[SETTING_ID] = false
    assert_nil(teammate_meta(harness.scan(), harness.teammate_unit).player_in_coherency, "the setting off")
    assert_equal(0, harness.world.coherency_reads, "coherency was read with the setting off")

    harness.settings[SETTING_ID] = nil
    harness.settings.show_players = "off"
    assert_nil(teammate_meta(harness.scan(), harness.teammate_unit).player_in_coherency, "teammates off")
    assert_equal(0, harness.world.coherency_reads, "coherency was read with teammates off")

    -- The coherency setting does not touch the state icons, nor they it.
    harness.settings.show_players = "dot_only"
    harness.settings.show_player_state_icons = false
    harness.world.extensions[harness.teammate_unit].unit_data_system = new_unit_data("knocked_down")
    harness.set_coherency(harness.teammate_unit, { harness.local_unit })

    local meta = teammate_meta(harness.scan(), harness.teammate_unit)

    assert_true(meta.player_in_coherency, "coherency with the state icons off")
    assert_nil(meta.player_radar_state, "a state icon with the state icons off")

    harness.settings.show_player_state_icons = nil
    harness.settings[SETTING_ID] = false
    meta = teammate_meta(harness.scan(), harness.teammate_unit)

    assert_nil(meta.player_in_coherency, "coherency with the setting off")
    assert_equal("rescue", meta.player_radar_state, "the state icon with the coherency setting off")
end)

test("a teammate who leaves coherency loses the mark on the next scan", function()
    local harness = new_players_harness()

    harness.set_coherency(harness.teammate_unit, { harness.teammate_unit, harness.local_unit })

    local first = teammate_meta(harness.scan(), harness.teammate_unit)

    assert_true(first.player_in_coherency, "in coherency")

    harness.set_coherency(harness.teammate_unit, { harness.teammate_unit })

    local second = teammate_meta(harness.scan(), harness.teammate_unit)

    assert_equal(false, second.player_in_coherency, "after leaving coherency")
    assert_true(first ~= second, "a scan reused the previous meta")

    harness.set_coherency(harness.teammate_unit, { harness.teammate_unit, harness.local_unit })
    assert_true(teammate_meta(harness.scan(), harness.teammate_unit).player_in_coherency, "after coming back")
end)

test("a replaced unit or a departed teammate leaves nothing behind", function()
    local harness = new_players_harness()
    local old_unit = harness.teammate_unit

    harness.set_coherency(old_unit, { harness.local_unit })
    assert_true(teammate_meta(harness.scan(), old_unit).player_in_coherency, "before the unit changes")

    local new_unit = harness.add_unit("respawned teammate", harness.teammate)

    harness.teammate.player_unit = new_unit

    local tracked, cleared = harness.scan()

    assert_equal(1, #cleared, "cleared units after the unit changed")
    assert_true(cleared[1].unit == old_unit and cleared[1].source == "player_manager", "the old unit was not cleared")
    assert_nil(tracked[old_unit], "the old unit was tracked again")
    assert_equal(false, teammate_meta(tracked, new_unit).player_in_coherency, "the new unit inherited coherency")

    harness.remove_player(harness.teammate)
    tracked, cleared = harness.scan()

    assert_equal(1, #cleared, "cleared units after the teammate left")
    assert_true(cleared[1].unit == new_unit, "the departed teammate's unit was not cleared")
    assert_nil(tracked[new_unit], "the departed teammate was tracked")
end)

-- --------------------------------------------------------------------------------------------
-- The teammate visual
-- --------------------------------------------------------------------------------------------

--- Loads the HUD element against a fake UI stack and returns its `_target_visual`.
local function load_target_visual()
    local mod = {}
    local env

    function mod:get()
        return nil
    end

    function mod:info()
    end

    -- The coherency colours are configured ones; every other colour keeps its fallback.
    function mod:get_radar_color(prefix, fallback)
        if prefix == "player_teammate_backplate" then
            return BACKPLATE_COLOR
        elseif prefix == "player_teammate_frame" then
            return FRAME_COLOR
        elseif prefix == "player_coherency_gained_flash" then
            return GAINED_FLASH_COLOR
        elseif prefix == "player_coherency_lost_flash" then
            return LOST_FLASH_COLOR
        end

        return fallback
    end

    function mod:io_dofile(path)
        local chunk = assert(loadfile(path .. ".lua"))

        setfenv(chunk, env)

        return chunk()
    end

    local modules = {
        ["scripts/managers/ui/ui_font_settings"] = { body_small = {}, hud_body = {} },
        ["scripts/managers/ui/ui_fonts"] = {},
        ["scripts/managers/ui/ui_renderer"] = {},
        ["scripts/managers/ui/ui_scenegraph"] = {},
        ["scripts/managers/ui/ui_widget"] = {
            create_definition = function(passes)
                return { passes = passes, content = {}, style = {} }
            end,
            init = function(_, definition)
                return clone(definition)
            end,
        },
        ["scripts/settings/ui/ui_hud_settings"] = {},
        ["scripts/settings/ui/ui_settings"] = { player_bright_slot_colors = {} },
    }

    env = setmetatable({
        get_mod = function()
            return mod
        end,
        class = function(name)
            return { __class_name = name }
        end,
        require = function(name)
            return assert(modules[name], "unexpected require of " .. name)
        end,
        table = setmetatable({
            clone = clone,
            merge_recursive = function(destination, source)
                for key, value in pairs(source) do
                    destination[key] = value
                end

                return destination
            end,
        }, { __index = table }),
        Color = setmetatable({}, {
            __call = function(_, a, r, g, b)
                return { a, r, g, b }
            end,
        }),
        Gui = {},
        Quaternion = {},
        Vector2 = setmetatable({}, {
            __call = function(_, x, y)
                return { x, y, 0 }
            end,
        }),
        Vector3 = setmetatable({}, {
            __call = function(_, x, y, z)
                return { x, y, z }
            end,
        }),
    }, { __index = _G })

    local chunk = assert(loadfile(HUD_PATH))

    setfenv(chunk, env)

    local HudElementRadar = chunk()
    local draw_internal = named_upvalue(HudElementRadar.draw, "_draw_internal")

    return named_upvalue(draw_internal, "_target_visual")
end

local SLOT_COLORS = { { 255, 226, 210, 117 }, { 255, 180, 88, 162 }, { 255, 209, 136, 88 }, { 255, 126, 153, 230 } }
local COHERENCY_FIELDS = {
    "plate_icon", "plate_color", "plate_base_size",
    "ring_icon", "ring_color", "ring_base_size",
    "flash_icon", "flash_color", "flash_base_size",
}

--- A draw cache as `_build_draw_cache` leaves it, with the frame's time and flash state.
local function new_draw_cache(style, slot_colors, draw_t)
    return {
        slot_colors = slot_colors or SLOT_COLORS,
        player_display_style = style or "marked_icon",
        debug_mode = false,
        enemy_visual_by_kind = {},
        teammate_color_by_slot = {},
        teammate_backplate_color = BACKPLATE_COLOR,
        teammate_frame_color = FRAME_COLOR,
        coherency_gained_flash_color = GAINED_FLASH_COLOR,
        coherency_lost_flash_color = LOST_FLASH_COLOR,
        coherency_state_by_unit = {},
        draw_t = draw_t,
    }
end

local function teammate(in_coherency, unit, player_slot, radar_state)
    return {
        kind = "player_teammate",
        unit = unit,
        meta = {
            player_slot = player_slot or 2,
            archetype_name = "veteran",
            player_radar_state = radar_state,
            player_in_coherency = in_coherency,
        },
    }
end

test("with the coherency annotation off, a teammate marker looks as before", function()
    local target_visual = load_target_visual()

    for _, style in ipairs({ "icon_only", "marked_icon", "dot_only", "marked_dot" }) do
        local visual = target_visual(teammate(nil, {}), new_draw_cache(style, nil, 10))

        assert_true(same_values({ 255, 180, 88, 162 }, visual.color), style .. " lost the slot colour")
        assert_true(same_values({ 180, 180, 88, 162 }, visual.accent_color), style .. " bracket colour")

        for f = 1, #COHERENCY_FIELDS do
            assert_nil(visual[COHERENCY_FIELDS[f]], style .. " has " .. COHERENCY_FIELDS[f])
        end
    end
end)

test("every teammate style sits on the backplate in a frame, in its colour only while in coherency", function()
    local target_visual = load_target_visual()
    local styles = { "icon_only", "marked_icon", "dot_only", "marked_dot" }
    local states = { false, "rescue", "captured", "luggable" }

    for s = 1, #styles do
        for r = 1, #states do
            local label = styles[s] .. " / " .. tostring(states[r])
            local before = target_visual(teammate(nil, {}, 2, states[r] or nil), new_draw_cache(styles[s]))
            local outside = target_visual(teammate(false, {}, 2, states[r] or nil), new_draw_cache(styles[s]))
            local inside = target_visual(teammate(true, {}, 2, states[r] or nil), new_draw_cache(styles[s]))

            for _, visual in ipairs({ outside, inside }) do
                for _, field in ipairs({ "icon", "color", "accent_color", "size" }) do
                    assert_true(same_values(before[field], visual[field]), label .. " coherency changed the marker's " .. field)
                end

                assert_equal(BACKPLATE, visual.plate_icon, label .. " backplate")
                assert_true(same_values(BACKPLATE_COLOR, visual.plate_color), label .. " backplate colour")
                assert_equal(before.size * 2, visual.plate_base_size, label .. " backplate size")
                assert_nil(visual.flash_icon, label .. " flashed without a change")
            end

            for _, visual in ipairs({ outside, inside }) do
                assert_equal(RING, visual.ring_icon, label .. " frame")
                assert_equal(before.size * 2, visual.ring_base_size, label .. " frame size")
            end

            assert_true(same_values(FRAME_COLOR, outside.ring_color), label .. " frame is not in the frame colour")
            assert_true(same_values(inside.color, inside.ring_color), label .. " frame is not in the marker colour")
        end
    end
end)

test("a player colour too dark for the backplate is lightened, every other colour is kept", function()
    local target_visual = load_target_visual()
    local ColorSettings = dofile(COLOR_SETTINGS_PATH)
    local slot_colors = { { 255, 0, 0, 0 }, { 255, 255, 255, 255 }, { 128, 40, 0, 80 }, { 255, 128, 128, 128 } }
    local draw_cache = new_draw_cache("marked_icon", slot_colors)

    local function luminance(color)
        local function channel(value)
            local c = value / 255

            return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
        end

        return 0.2126 * channel(color[2]) + 0.7152 * channel(color[3]) + 0.0722 * channel(color[4])
    end

    local function contrast(a, b)
        local la, lb = luminance(a), luminance(b)

        return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
    end

    for slot = 1, 4 do
        local visual = target_visual(teammate(true, {}, slot), draw_cache)
        local label = "slot " .. slot

        assert_true(contrast(visual.color, BACKPLATE_COLOR) >= 3, label .. " does not read on the backplate")
        assert_equal(slot_colors[slot][1], visual.color[1], label .. " lost its opacity")
        assert_true(visual.color == visual.ring_color, label .. " ring and icon differ")
        assert_true(target_visual(teammate(false, {}, slot), draw_cache).color == visual.color,
            label .. " readable colour is not cached per slot")
    end

    assert_true(same_values({ 255, 255, 255, 255 }, target_visual(teammate(true, {}, 2), draw_cache).color),
        "white was changed")
    assert_true(same_values({ 255, 128, 128, 128 }, target_visual(teammate(true, {}, 4), draw_cache).color),
        "a bot grey was changed")
    assert_true(target_visual(teammate(true, {}, 1), draw_cache).color[2] > 0, "black was not lightened")

    -- Every vanilla slot colour already reads on black.
    for slot = 1, 4 do
        assert_true(same_values(SLOT_COLORS[slot], ColorSettings.readable_on(SLOT_COLORS[slot], { 200, 0, 0, 0 }, 3)),
            "vanilla slot " .. slot .. " colour was changed")
    end

    -- A light backplate darkens a colour instead.
    local darkened = ColorSettings.readable_on({ 255, 255, 255, 255 }, { 255, 240, 240, 240 }, 3)

    assert_true(contrast(darkened, { 255, 240, 240, 240 }) >= 3 and darkened[2] < 255, "white was not darkened")
end)

test("gaining coherency flashes in the gained colour growing outward, losing it in the lost colour shrinking", function()
    local target_visual = load_target_visual()
    local draw_cache = new_draw_cache("marked_icon")
    local unit = {}

    local function frame(t, in_coherency, frame_unit)
        draw_cache.draw_t = t

        return target_visual(teammate(in_coherency, frame_unit or unit), draw_cache)
    end

    assert_nil(frame(10, false).flash_icon, "a teammate flashed when first seen")
    assert_nil(frame(10.016, false).flash_icon, "a teammate flashed without a change")

    local start = frame(10.032, true)

    assert_equal(FLASH, start.flash_icon, "entering coherency did not flash")
    assert_equal(0, start.flash_color[1], "the flash does not start faded out")

    local start_size = start.flash_base_size
    local middle = frame(10.432, true)

    assert_equal(GAINED_FLASH_COLOR[1], middle.flash_color[1], "the gained flash is not at full opacity half way")
    assert_true(middle.flash_color[2] == GAINED_FLASH_COLOR[2] and middle.flash_color[3] == GAINED_FLASH_COLOR[3]
        and middle.flash_color[4] == GAINED_FLASH_COLOR[4], "the gained flash is not in the gained colour")
    assert_true(middle.flash_base_size > start_size, "the gained flash does not grow outward")
    assert_true(start_size >= start.plate_base_size, "the gained flash starts inside the backplate")
    assert_nil(frame(10.84, true).flash_icon, "the gained flash outlasted 0.8 seconds")

    local lost_start = frame(10.856, false)

    assert_equal(FLASH, lost_start.flash_icon, "leaving coherency did not flash")
    assert_equal(0, lost_start.flash_color[1], "the lost flash does not start faded out")

    local lost_start_size = lost_start.flash_base_size
    local lost_middle = frame(11.256, false)

    assert_equal(LOST_FLASH_COLOR[1], lost_middle.flash_color[1], "the lost flash is not at full opacity half way")
    assert_true(lost_middle.flash_color[2] == LOST_FLASH_COLOR[2] and lost_middle.flash_color[3] == LOST_FLASH_COLOR[3]
        and lost_middle.flash_color[4] == LOST_FLASH_COLOR[4], "the lost flash is not in the lost colour")
    assert_true(lost_middle.flash_base_size < lost_start_size, "the lost flash does not shrink inward")
    assert_true(frame(11.6, false).flash_base_size >= lost_start.plate_base_size,
        "the lost flash shrinks inside the backplate")
    assert_nil(frame(11.7, false).flash_icon, "the lost flash outlasted 0.8 seconds")

    -- Off the radar for a while, a teammate that comes back changed does not flash.
    assert_nil(frame(20, true).flash_icon, "a teammate flashed when back on the radar")

    -- A replaced unit starts over.
    assert_nil(frame(20.016, false, {}).flash_icon, "a new unit flashed when first seen")

    -- With the annotation off nothing flashes, and turning it on again later does not either.
    assert_nil(frame(20.032, nil).flash_icon, "a teammate flashed with the annotation off")
    assert_nil(frame(30, false).flash_icon, "a teammate flashed when the annotation came back on")
end)

test("a teammate's coherency visual is reused from frame to frame and allocates nothing", function()
    local target_visual = load_target_visual()
    local draw_cache = new_draw_cache("marked_icon", nil, 10)
    local target = teammate(true, {})
    local first = target_visual(target, draw_cache)

    draw_cache.draw_t = 10.016

    assert_true(target_visual(target, draw_cache) == first, "the visual was built anew for the same teammate")
    assert_true(target_visual(teammate(true, {}), draw_cache) ~= first, "two teammates share one visual")

    -- The game runs with the JIT off; compiled traces would count as garbage here.
    local jit_api = rawget(_G, "jit")

    if jit_api then
        jit_api.off()
        jit_api.flush()
    end

    collectgarbage("collect")
    collectgarbage("stop")

    local before = collectgarbage("count")

    for frame = 1, 1000 do
        draw_cache.draw_t = 10.016 + frame * 0.016
        target.meta.player_in_coherency = frame % 120 < 60
        target_visual(target, draw_cache)
    end

    local kilobytes = collectgarbage("count") - before

    collectgarbage("restart")

    if jit_api then
        jit_api.on()
    end

    assert_true(kilobytes < 0.5, string.format("1000 frames, flashes included, allocated %.2f KB", kilobytes))
end)

test("a changed player colour is picked up in place at the next draw cache refresh", function()
    local target_visual = load_target_visual()
    local slot_colors = { SLOT_COLORS[1], { 255, 0, 0, 0 }, SLOT_COLORS[3], SLOT_COLORS[4] }
    local draw_cache = new_draw_cache("marked_icon", slot_colors, 10)

    draw_cache.teammate_color_generation = 1

    local target = teammate(true, {}, 2)
    local color = target_visual(target, draw_cache).color

    assert_true(color[2] > 0, "black was not lightened")

    -- ColorSelection rewrites the slot colours in place; the draw cache refreshes every second.
    slot_colors[2] = { 255, 30, 180, 90 }
    draw_cache.draw_t = 10.5

    assert_true(target_visual(target, draw_cache).color[2] == color[2], "the colour changed before the refresh")

    draw_cache.teammate_color_generation = 2
    draw_cache.draw_t = 11

    local refreshed = target_visual(target, draw_cache)

    assert_true(refreshed.color == color, "the refresh built a new colour table")
    assert_true(same_values({ 255, 30, 180, 90 }, refreshed.color), "the new player colour was not picked up")
    assert_true(refreshed.ring_color == refreshed.color, "the frame did not follow the new player colour")
end)

test("the setting and its colours are named in every language the state icons have", function()
    local chunk = assert(loadfile(LOCALIZATION_PATH))

    setfenv(chunk, setmetatable({
        Localize = function(key)
            return key
        end,
    }, { __index = _G }))

    local localization = chunk()
    local reference = localization.show_player_state_icons

    for _, key in ipairs({
        SETTING_ID,
        SETTING_ID .. "_tooltip",
        "player_teammate_backplate_color",
        "player_teammate_backplate_color_slider_tooltip",
        "player_teammate_frame_color",
        "player_teammate_frame_color_slider_tooltip",
        "player_coherency_gained_flash_color",
        "player_coherency_gained_flash_color_slider_tooltip",
        "player_coherency_lost_flash_color",
        "player_coherency_lost_flash_color_slider_tooltip",
    }) do
        local entry = localization[key]

        assert_true(type(entry) == "table", key .. " is missing")

        for language in pairs(reference) do
            assert_true(type(entry[language]) == "string" and entry[language] ~= "", key .. " has no " .. language)
        end
    end

    assert_equal("Teammate coherency", localization[SETTING_ID].en, "English label")
end)

local failures = {}

for i = 1, #tests do
    local current = tests[i]
    local ok, failure = xpcall(current.fn, debug.traceback)

    if ok then
        io.write("PASS ", current.name, "\n")
    else
        failures[#failures + 1] = current.name .. "\n" .. failure
        io.write("FAIL ", current.name, "\n")
    end
end

if #failures > 0 then
    io.write("\n")

    for i = 1, #failures do
        io.write(failures[i], "\n")
    end

    io.write("\n", tostring(#failures), " of ", tostring(#tests), " tests failed\n")
    os.exit(1)
end

io.write("\n", tostring(#tests), " tests passed\n")
