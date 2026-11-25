-- The Radar player: whose point of view the radar shows, and what follows it.
-- Installs the real runtime helpers, tracking and players modules into a fake shared environment
-- with a fake player manager, camera handler, owner map, units and clock. In play the Radar player
-- is the local player, downed too; while the local player is dead or captured it is the teammate
-- the game's spectator camera follows, never one picked by where the camera is. A dead or captured
-- unit, a unit no player owns, someone else's unit nobody spectates and the game state outside the
-- player leave the radar without one, and nothing of an earlier source stays published. The
-- revision counts every change of player, unit or mode. Through the update the
-- `StateGameplay.update` hook runs, a source change drops the tracked units and runs every scan
-- tier at once while overview stays open, the snapshot, distances, heights, teammates and the
-- interactee prompt follow the Radar player, and nothing is drawn without one. Also the HUD
-- registration, the synced ability name of a spectated teammate, the mission reset, and the HUD
-- element starting its coherency state over and handing the revision to the navmesh layer.

local HELPERS_PATH = "Radar/scripts/mods/Radar/Radar_runtime_helpers.lua"
local TRACKING_PATH = "Radar/scripts/mods/Radar/Radar_tracking.lua"
local PLAYERS_PATH = "Radar/scripts/mods/Radar/Radar_players.lua"
local HUD_PATH = "Radar/scripts/mods/Radar/ui/Radar_hud_element.lua"

table.clear = table.clear or function(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

local function assert_true(value, message)
    if value ~= true then
        error((message or "expected true") .. ": got " .. tostring(value), 2)
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

local function named_upvalue(fn, expected_name)
    for index = 1, 255 do
        local name, value = debug.getupvalue(fn, index)

        if name == nil then
            error("missing upvalue `" .. expected_name .. "`", 2)
        end

        if name == expected_name then
            return value
        end
    end
end

local function upvalue_index(fn, expected_name)
    for index = 1, 255 do
        local name = debug.getupvalue(fn, index)

        if name == nil then
            error("missing upvalue `" .. expected_name .. "`", 2)
        elseif name == expected_name then
            return index
        end
    end
end

local function install(path, env)
    local chunk, load_error = loadfile(path)

    assert(chunk, load_error)
    chunk()(env)
end

local function noop()
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

local CAMERA_ROTATION = { name = "the local camera's rotation" }

-- --------------------------------------------------------------------------------------------
-- The runtime against a fake game
-- --------------------------------------------------------------------------------------------

--- A player unit at a position, walking, alive and healthy; `state` and `healthy` can be changed.
local function new_unit(world, name, position, owner)
    local unit = { name = name, state = "walking", healthy = true }

    unit.extensions = {
        unit_data_system = {
            read_component = function(_, component)
                if component == "character_state" then
                    return { state_name = unit.state }
                elseif component == "inventory" then
                    return { wielded_slot = "slot_primary" }
                elseif component == "disabled_character_state" then
                    return { is_disabled = false }
                end

                return nil
            end,
        },
        health_system = {
            is_alive = function()
                return unit.healthy
            end,
        },
    }
    world.alive[unit] = true
    world.positions[unit] = position
    world.owners[unit] = owner

    return unit
end

local function new_player(slot)
    local player = { owned_units = {}, viewport_name = "player" .. slot }

    function player:slot()
        return slot
    end

    function player:name()
        return "player " .. slot
    end

    function player:profile()
        return { archetype = { name = "veteran" } }
    end

    return player
end

--- Installs the runtime into a squad of three, the local player (slot 1) and two teammates, all
-- walking; nobody is spectated and the game state lets the radar run.
local function new_harness()
    local captured = { hud_elements = {} }
    local settings = {
        enable_radar = true,
        debug_mode = false,
        debug_profiling = false,
        radar_style = "square",
        max_radar_markers = 64,
        overview_zoom_in_key = { "wheel_down" },
        overview_zoom_out_key = { "wheel_up" },
        radar_zoom_modifier_key = {},
    }
    local world = {
        t = 10,
        alive = {},
        positions = {},
        owners = {},
        players = {},
        local_player = nil,
        observing = false,
        follow_unit = nil,
        observing_reads = 0,
        camera_reads = 0,
        camera_position_reads = 0,
        mission = "cm_habs",
        activity = "mission",
        mechanism = "adventure",
        game_mode_allowed = true,
        scans = { moving = 0, droppable = 0, static = 0 },
    }
    local mod = {}

    function mod:get(setting_id)
        return settings[setting_id]
    end

    function mod:set(setting_id, value)
        settings[setting_id] = value
    end

    function mod:get_target_render_layer()
        return 0
    end

    function mod:get_target_selection_priority()
        return 0
    end

    function mod:hook_safe(class_or_name, method_name, callback)
        if class_or_name == "StateGameplay" and method_name == "update" then
            captured.state_gameplay_update = callback
        end
    end

    function mod:register_hud_element(element_settings)
        captured.hud_elements[#captured.hud_elements + 1] = element_settings
    end

    mod.hook = noop
    mod.info = noop
    mod.error = noop
    mod.notify = noop

    local camera_handler = {
        is_observing = function()
            world.observing_reads = world.observing_reads + 1

            return world.observing
        end,
        camera_follow_unit = function()
            return world.follow_unit
        end,
    }
    local managers = {
        player = {
            _num_players = 3,
            local_player_safe = function()
                return world.local_player
            end,
            players = function()
                return world.players
            end,
        },
        state = {
            player_unit_spawn = {
                owner = function(_, unit)
                    return world.owners[unit]
                end,
            },
            -- The old heuristic picked whoever stood nearest to this; nothing may ask for it now.
            camera = {
                has_camera = function()
                    return true
                end,
                camera_rotation = function()
                    world.camera_reads = world.camera_reads + 1

                    return CAMERA_ROTATION
                end,
                camera_position = function()
                    world.camera_position_reads = world.camera_position_reads + 1

                    return world.positions[world.camera_near]
                end,
            },
        },
        time = {
            _timers = { gameplay = true },
            time = function()
                return world.t
            end,
        },
    }
    local env = {
        mod = mod,
        Managers = managers,
        ALIVE = world.alive,
        POSITION_LOOKUP = world.positions,
        SCAN_INTERVAL = 0.25,
        KIND_TO_SETTING = {},
        RESPAWN_MARKER_KINDS = {},
        SAFEROUTE_MARKER_KINDS = {},
        ENEMY_RADAR_DEFINITION_BY_KIND = {},
        NEARBY_HIGHLIGHT_SETTING_BY_GROUP = {},
        CLASS = { InputService = {} },
        CompanionServoSkullSettings = { STATES = {} },
        ScriptUnit = {
            has_extension = function(unit, system_name)
                return type(unit) == "table" and unit.extensions and unit.extensions[system_name] or nil
            end,
        },
    }

    -- Shared functions from modules this harness does not install only need to exist.
    setmetatable(env, {
        __index = function(_, key)
            local value = _G[key]

            if value ~= nil then
                return value
            end

            if type(key) == "string" and key:sub(1, 1) == "_" then
                return noop
            end

            return nil
        end,
    })

    install(HELPERS_PATH, env)
    install(TRACKING_PATH, env)
    install(PLAYERS_PATH, env)

    -- The game state outside the player, which lets the radar run unless a test says otherwise.
    env._safe_mission_name = function()
        return world.mission
    end
    env._safe_presence_activity = function()
        return world.activity
    end
    env._safe_mechanism_name = function()
        return world.mechanism
    end
    mod.is_radar_runtime_game_mode_allowed = function()
        return world.game_mode_allowed
    end
    -- What the modules this harness does not install would decide, and one scan per tier counted.
    env._kind_enabled = function()
        return true
    end
    env._is_valid_expedition_item_for_current_section = function()
        return true
    end
    env._cluster_expedition_loot_targets = function(targets)
        return targets
    end
    env._scan_minions = function()
        world.scans.moving = world.scans.moving + 1
    end
    env._sync_expedition_item_state = function()
        world.scans.droppable = world.scans.droppable + 1
    end
    env._scan_chests = function()
        world.scans.static = world.scans.static + 1
    end

    local update_internal = named_upvalue(captured.state_gameplay_update, "_update_internal")
    local harness = {
        env = env,
        mod = mod,
        world = world,
        settings = settings,
        managers = managers,
        captured = captured,
        scan_interactees = named_upvalue(update_internal, "_scan_interactees"),
        collect_radar_targets = named_upvalue(update_internal, "_collect_radar_targets"),
    }

    harness.local_player = new_player(1)
    harness.teammate = new_player(2)
    harness.other = new_player(3)
    harness.local_unit = new_unit(world, "local", { x = 0, y = 0, z = 0 }, harness.local_player)
    harness.teammate_unit = new_unit(world, "teammate", { x = 40, y = 0, z = 6 }, harness.teammate)
    harness.other_unit = new_unit(world, "other", { x = -30, y = 10, z = 0 }, harness.other)
    harness.local_player.player_unit = harness.local_unit
    harness.local_player.camera_handler = camera_handler
    harness.teammate.player_unit = harness.teammate_unit
    harness.other.player_unit = harness.other_unit
    world.local_player = harness.local_player
    world.players = { harness.local_player, harness.teammate, harness.other }

    --- Evaluates the runtime state at the next gameplay time and returns the Radar player.
    function harness:resolve()
        world.t = world.t + 0.01
        env._get_runtime_state()

        return env._radar_player()
    end

    --- Runs the gameplay state's update after `dt` seconds.
    function harness:update(dt)
        world.t = world.t + (dt or 0.01)
        captured.state_gameplay_update({}, dt or 0.01, world.t)
    end

    --- The local player died and their unit is gone; the game's camera follows `player`.
    function harness:spectate(player)
        world.alive[self.local_unit] = nil
        self.local_player.player_unit = nil
        world.observing = true
        world.follow_unit = player and player.player_unit or nil
    end

    return harness
end

--- Asserts that the Radar player is unusable for `reason` and publishes nothing of a source.
local function assert_unavailable(radar_player, reason, label)
    assert_equal(false, radar_player.usable, label .. " usable")
    assert_equal(reason, radar_player.reason, label .. " reason")
    assert_equal("unavailable", radar_player.mode, label .. " mode")
    assert_nil(radar_player.player, label .. " player")
    assert_nil(radar_player.unit, label .. " unit")
    assert_nil(radar_player.position, label .. " position")
    assert_nil(radar_player.view_rotation, label .. " camera basis")
    assert_nil(radar_player.slot, label .. " slot")
end

local function assert_position(x, y, z, position, label)
    assert_true(type(position) == "table", label .. " has no position")
    assert_equal(x, position.x, label .. " x")
    assert_equal(y, position.y, label .. " y")
    assert_equal(z, position.z, label .. " z")
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("in play the local player is the Radar player, downed or disabled too", function()
    local harness = new_harness()
    local radar_player = harness:resolve()

    assert_true(radar_player.usable, "usable")
    assert_equal("ok", radar_player.reason, "reason")
    assert_equal("local", radar_player.mode, "mode")
    assert_equal(harness.local_player, radar_player.player, "player")
    assert_equal(harness.local_unit, radar_player.unit, "unit")
    assert_position(0, 0, 0, radar_player.position, "the local player")
    assert_true(radar_player.position ~= harness.world.positions[harness.local_unit],
        "the position is the engine's own")
    assert_equal(1, radar_player.slot, "slot")
    assert_equal(CAMERA_ROTATION, radar_player.view_rotation, "the camera basis is the local camera")

    local revision = radar_player.revision

    for _, state in ipairs({ "knocked_down", "ledge_hanging", "netted", "pounced" }) do
        harness.local_unit.state = state
        radar_player = harness:resolve()

        assert_true(radar_player.usable, state)
        assert_equal(revision, radar_player.revision, state .. " changed the source")
    end
end)

test("a dead or captured local player gives the radar no source, and nothing of it stays published", function()
    local cases = {
        { "dead", "player_not_alive", function(harness)
            harness.local_unit.state = "dead"
        end },
        { "health gone", "player_not_alive", function(harness)
            harness.local_unit.healthy = false
        end },
        { "unit destroyed", "player_not_alive", function(harness)
            harness.world.alive[harness.local_unit] = nil
        end },
        { "hogtied", "player_captured", function(harness)
            harness.local_unit.state = "hogtied"
        end },
        { "hogtied and watching themself", "player_captured", function(harness)
            harness.local_unit.state = "hogtied"
            harness.world.observing = true
            harness.world.follow_unit = harness.local_unit
        end },
        { "no unit", "no_player_unit", function(harness)
            harness.local_player.player_unit = nil
        end },
        { "no local player", "no_local_player", function(harness)
            harness.world.local_player = nil
        end },
        { "no position", "no_player_position", function(harness)
            harness.world.positions[harness.local_unit] = nil
        end },
    }

    for i = 1, #cases do
        local name, reason, setup = cases[i][1], cases[i][2], cases[i][3]
        local harness = new_harness()

        assert_true(harness:resolve().usable, name .. " before")
        setup(harness)
        assert_unavailable(harness:resolve(), reason, name)
    end
end)

test("while the local player spectates, the teammate the game's camera follows is the Radar player", function()
    local harness = new_harness()

    harness:resolve()
    harness:spectate(harness.teammate)

    local radar_player = harness:resolve()

    assert_true(radar_player.usable, "usable")
    assert_equal("spectating", radar_player.mode, "mode")
    assert_equal(harness.teammate, radar_player.player, "player")
    assert_equal(harness.teammate_unit, radar_player.unit, "unit")
    assert_position(40, 0, 6, radar_player.position, "the teammate")
    assert_equal(2, radar_player.slot, "the teammate's slot")
    assert_equal(CAMERA_ROTATION, radar_player.view_rotation, "the camera basis is still the local camera")

    local revision = radar_player.revision

    harness.teammate_unit.state = "knocked_down"
    radar_player = harness:resolve()
    assert_true(radar_player.usable, "a downed teammate")
    assert_equal(revision, radar_player.revision, "a downed teammate changed the source")

    harness.teammate_unit.state = "hogtied"
    assert_unavailable(harness:resolve(), "player_captured", "a captured teammate")

    harness.teammate_unit.state = "dead"
    assert_unavailable(harness:resolve(), "player_not_alive", "a dead teammate")

    harness.teammate_unit.state = "walking"
    harness.teammate_unit.healthy = false
    assert_unavailable(harness:resolve(), "player_not_alive", "a teammate without health")

    harness.teammate_unit.healthy = true
    harness.world.alive[harness.teammate_unit] = nil
    assert_unavailable(harness:resolve(), "player_not_alive", "a teammate whose unit is gone")
end)

test("the source is the followed unit, never the one nearest the camera, and a unit nobody plays is none", function()
    local harness = new_harness()
    local world = harness.world

    harness:spectate(harness.teammate)
    world.camera_near = harness.other_unit

    assert_equal(harness.teammate, harness:resolve().player, "the camera picked the source")
    assert_equal(0, world.camera_position_reads, "the camera position was read")

    local prop = new_unit(world, "prop", { x = 5, y = 5, z = 0 }, nil)

    world.follow_unit = prop
    assert_unavailable(harness:resolve(), "no_spectator_target", "a followed unit nobody owns")

    local companion = new_unit(world, "companion", { x = 1, y = 1, z = 0 }, harness.local_player)

    world.follow_unit = companion
    assert_unavailable(harness:resolve(), "no_spectator_target", "a followed unit of the local player's own")

    local replaced = harness.other_unit

    harness.other.player_unit = new_unit(world, "other again", { x = -31, y = 10, z = 0 }, harness.other)
    world.follow_unit = replaced
    assert_unavailable(harness:resolve(), "no_spectator_target", "a followed unit its owner no longer plays")

    world.follow_unit = harness.teammate_unit
    harness.managers.state.player_unit_spawn = nil
    assert_unavailable(harness:resolve(), "no_spectator_target", "without the owner lookup")

    harness.managers.state.player_unit_spawn = { owner = function(_, unit) return world.owners[unit] end }
    world.follow_unit = nil
    assert_unavailable(harness:resolve(), "no_player_unit", "observing nobody without a unit of one's own")
end)

test("someone else's unit is no source unless the game spectates it", function()
    local harness = new_harness()
    local world = harness.world

    harness.local_player.player_unit = harness.teammate_unit
    assert_unavailable(harness:resolve(), "foreign_player_unit", "a foreign unit with nobody watched")

    world.observing = true
    world.follow_unit = harness.teammate_unit

    local radar_player = harness:resolve()

    assert_equal("spectating", radar_player.mode, "the spectated foreign unit")
    assert_equal(harness.teammate, radar_player.player, "the spectated foreign unit's player")
end)

test("the revision counts every change of player, unit or mode, and nothing else", function()
    local harness = new_harness()
    local world = harness.world
    local revision = harness:resolve().revision

    local function expect(change, label)
        local radar_player = harness:resolve()

        revision = revision + change
        assert_equal(revision, radar_player.revision, label)
    end

    expect(0, "the next gameplay time")
    world.positions[harness.local_unit].x = 5
    expect(0, "moving")
    harness.local_unit.state = "knocked_down"
    expect(0, "downed")
    harness.local_unit.state = "hogtied"
    expect(1, "captured")
    world.observing = true
    world.follow_unit = harness.local_unit
    expect(0, "watching the own captured unit")
    world.follow_unit = harness.teammate_unit
    expect(1, "spectating the teammate")
    expect(0, "still spectating")
    world.follow_unit = harness.other_unit
    expect(1, "spectating another teammate")
    world.follow_unit = harness.teammate_unit
    expect(1, "back to the first teammate")
    harness.local_unit.state = "walking"
    world.observing = false
    world.follow_unit = harness.local_unit
    expect(1, "rescued")

    local respawned = new_unit(world, "respawned", { x = 2, y = 2, z = 0 }, harness.local_player)

    harness.local_player.player_unit = respawned
    expect(1, "a new unit of one's own")

    harness.env._reset_radar_player()

    local radar_player = harness.env._radar_player()

    assert_equal(revision + 1, radar_player.revision, "the reset")
    assert_unavailable(radar_player, "unresolved", "after the reset")
end)

test("it is resolved once per gameplay time, and not at all while the game state stops the radar", function()
    local harness = new_harness()
    local world = harness.world

    harness:resolve()

    local reads = world.observing_reads + world.camera_reads

    harness.env._get_runtime_state()
    harness.env._get_runtime_state()
    assert_equal(reads, world.observing_reads + world.camera_reads, "resolved again within one gameplay time")

    local gates = {
        { "loading", function()
            world.activity = "loading"
        end },
        { "hub_mission", function()
            world.mission = "hub_ship"
        end },
        { "no_mission", function()
            world.mission = nil
        end },
        { "game_mode_disabled", function()
            world.game_mode_allowed = false
        end },
    }

    for i = 1, #gates do
        local reason, setup = gates[i][1], gates[i][2]

        harness = new_harness()
        world = harness.world
        harness:resolve()
        setup()
        world.t = world.t + 0.01
        reads = world.observing_reads + world.camera_reads

        local allowed, runtime_reason = harness.env._get_runtime_state()

        assert_equal(false, allowed, reason .. " allowed")
        assert_equal(reason, runtime_reason, reason)
        assert_unavailable(harness.env._radar_player(), reason, reason)
        assert_equal(reads, world.observing_reads + world.camera_reads, reason .. " read the player")
    end
end)

test("a source change drops what was tracked and runs every scan tier at once, with overview left open", function()
    local harness = new_harness()
    local mod = harness.mod
    local world = harness.world
    local scans = world.scans

    harness:update()
    assert_equal(1, scans.static, "the first update ran no static scan")
    assert_true(mod:set_overview_mode_active(true), "overview did not open")
    harness:update(0.3)
    harness:update(0.3)

    local leftover = new_unit(world, "ammo", { x = 3, y = 0, z = 0 }, nil)

    mod._tracked_units[leftover] = {
        kind = "pickup_ammo_small",
        source = "interactee_system",
        position = { x = 3, y = 0, z = 0 },
        last_seen_t = world.t,
    }

    local moving, droppable, static = scans.moving, scans.droppable, scans.static

    harness:update()
    assert_equal(moving, scans.moving, "a moving scan ran before it was due")
    assert_true(mod._tracked_units[leftover] ~= nil, "a tracked unit was dropped without a source change")

    -- Dead in an Expedition sanctuary, the game follows a teammate at once.
    harness.local_unit.state = "dead"
    world.observing = true
    world.follow_unit = harness.teammate_unit
    harness:update()

    assert_equal(moving + 1, scans.moving, "the moving tier did not run at once")
    assert_equal(droppable + 1, scans.droppable, "the droppable tier did not run at once")
    assert_equal(static + 1, scans.static, "the static tier did not run at once")
    assert_nil(mod._tracked_units[leftover], "a unit found around the previous source was kept")
    assert_true(mod:is_overview_mode_active(), "the source change closed overview")

    local snapshot = mod:get_radar_snapshot()

    assert_equal(harness.teammate_unit, snapshot.player_unit, "snapshot unit")
    assert_position(40, 0, 6, snapshot.player_position, "snapshot")
    assert_equal(2, snapshot.player_slot, "the centre dot's slot")
    assert_equal(CAMERA_ROTATION, snapshot.player_rotation, "snapshot camera basis")
    assert_equal(harness.env._radar_player().revision, snapshot.player_revision, "snapshot revision")
    assert_nil(mod._tracked_units[harness.teammate_unit], "the spectated teammate has a teammate marker too")
    assert_equal("player_teammate", mod._tracked_units[harness.local_unit].kind, "the local player's body")
    assert_equal("dead", mod._tracked_units[harness.local_unit].meta.player_radar_state, "the local player's state")
    assert_equal("player_teammate", mod._tracked_units[harness.other_unit].kind, "the other teammate")

    -- Without a usable source the radar stops, overview closes and nothing is left.
    harness.teammate_unit.state = "hogtied"
    harness:update()

    assert_equal(false, mod:is_overview_mode_active(), "overview stayed open without a source")
    assert_nil(mod:get_radar_snapshot(), "a snapshot was kept without a source")
    assert_nil(next(mod._tracked_units), "tracked units were kept without a source")
end)

test("targets, heights and the interactee prompt are measured from the Radar player", function()
    local harness = new_harness()
    local mod = harness.mod
    local world = harness.world

    harness:spectate(harness.teammate)
    harness:update()

    local crate = new_unit(world, "crate", { x = 43, y = 4, z = 9 }, nil)

    mod._tracked_units[crate] = {
        kind = "pickup_ammo_small",
        source = "test",
        position = { x = 43, y = 4, z = 9 },
        meta = {},
        last_seen_t = world.t,
    }

    local targets = harness.collect_radar_targets()
    local found = nil

    for i = 1, #targets do
        if targets[i].unit == crate then
            found = targets[i]
        end
    end

    assert_true(found ~= nil, "the crate is no target")
    assert_equal(25, found.distance_sq, "the distance on the floor plan")
    assert_equal(34, found.distance_sq_3d, "the distance")
    assert_equal(3, found.vertical_delta, "the height difference")

    local asked = {}
    local door = new_unit(world, "door", { x = 41, y = 1, z = 6 }, nil)
    local extension = {
        active = function()
            return true
        end,
        used = function()
            return false
        end,
        show_marker = function(_, interactor_unit)
            asked[#asked + 1] = interactor_unit

            return true
        end,
    }

    harness.env._safe_unit_to_extension_map = function(system_name)
        if system_name == "interactee_system" then
            return { [door] = extension }
        end

        return nil
    end
    harness.scan_interactees()

    assert_equal(1, #asked, "the prompt was not asked")
    assert_equal(harness.teammate_unit, asked[1], "the prompt was asked for another unit")
end)

test("a usable spectated teammate is drawn, and nothing is without a Radar player", function()
    local harness = new_harness()
    local mod = harness.mod

    harness:spectate(harness.teammate)
    harness:update()
    assert_true(mod:should_draw_radar(), "the spectated teammate")

    harness.teammate_unit.state = "hogtied"
    harness:update()
    assert_equal(false, mod:should_draw_radar(), "a captured spectated teammate")

    harness.teammate_unit.state = "walking"
    harness:update()
    assert_true(mod:should_draw_radar(), "recovered when the teammate is free")

    harness.settings.enable_radar = false
    harness:update()
    assert_equal(false, mod:should_draw_radar(), "the radar switched off")
end)

test("back with the local player, nothing of the spectated teammate is kept", function()
    local harness = new_harness()
    local mod = harness.mod
    local world = harness.world

    harness:spectate(harness.teammate)
    harness:update()
    assert_equal(2, mod:get_radar_snapshot().player_slot, "spectating")

    -- Respawned captured, then rescued.
    local respawned = new_unit(world, "respawned", { x = 1, y = 2, z = 0 }, harness.local_player)

    harness.local_player.player_unit = respawned
    respawned.state = "hogtied"
    world.follow_unit = respawned
    harness:update()
    assert_equal(false, mod:should_draw_radar(), "captured after the respawn")

    respawned.state = "walking"
    world.observing = false
    harness:update()

    local snapshot = mod:get_radar_snapshot()

    assert_equal(respawned, snapshot.player_unit, "snapshot unit")
    assert_position(1, 2, 0, snapshot.player_position, "back home")
    assert_equal(1, snapshot.player_slot, "the centre dot kept the teammate's slot")
    assert_nil(mod._tracked_units[respawned], "the local player has a teammate marker")
    assert_equal("player_teammate", mod._tracked_units[harness.teammate_unit].kind, "the teammate is no teammate")
end)

test("the HUD element is registered for the alive group, which spectator HUDs check on the spectated player", function()
    local harness = new_harness()
    local element = harness.captured.hud_elements[1]
    local groups = {}

    assert_equal("HudElementRadar", element and element.class_name, "the HUD element")

    for i = 1, #element.visibility_groups do
        groups[element.visibility_groups[i]] = true
    end

    assert_true(groups.alive, "the alive group")
    assert_nil(groups.dead, "the dead group")
end)

test("a spectated teammate's ability name comes from their synced equipped abilities", function()
    local harness = new_harness()
    local raised = 0
    local abilities = { combat_ability = { name = "ogryn_taunt_shout" } }
    local teammate = {
        extensions = {
            ability_system = {
                equipped_abilities = function()
                    return abilities
                end,
                ability_name = function()
                    raised = raised + 1
                    error("not allowed to call on husk")
                end,
                get_current_ability_name = function()
                    raised = raised + 1
                    error("not allowed to call on husk")
                end,
            },
        },
    }

    assert_equal("ogryn_taunt_shout", harness.env._safe_unit_ability_name(teammate, "combat_ability"), "equipped")

    abilities = {}
    assert_nil(harness.env._safe_unit_ability_name(teammate, "combat_ability"), "nothing equipped")
    assert_equal(0, raised, "a getter that raises on a teammate's unit was called")

    local own = {
        extensions = {
            ability_system = {
                ability_name = function()
                    return "veteran_combat_ability_stance"
                end,
            },
        },
    }

    assert_equal("veteran_combat_ability_stance", harness.env._safe_unit_ability_name(own, "combat_ability"),
        "without the equipped list")
end)

test("a mission reset clears the Radar player and what tracking knew of it", function()
    local harness = new_harness()
    local mod = harness.mod

    harness:update()

    local revision = harness.env._radar_player().revision

    assert_equal(revision, mod._radar_player_revision, "tracking did not take the revision")

    mod.on_game_state_changed("exit", "GameplayStateRun")

    local radar_player = harness.env._radar_player()

    assert_equal(revision + 1, radar_player.revision, "the reset kept the revision")
    assert_unavailable(radar_player, "unresolved", "after the reset")
    assert_nil(mod._radar_player_revision, "tracking kept the revision")
end)

-- --------------------------------------------------------------------------------------------
-- The HUD element against a fake UI stack
-- --------------------------------------------------------------------------------------------

--- Loads the HUD element and returns a draw that runs its marker loop with the renderer, widget
-- pool and Strikemap layer swapped out, and the navmesh layer recording what it is handed.
local function new_hud_harness()
    local harness = { navmesh_draws = {} }
    local mod = { _radar_color_cache_generation = 1 }
    local env

    function mod:get()
        return nil
    end

    function mod:info()
    end

    function mod:get_radar_color(_, fallback)
        return fallback
    end

    function mod:get_configured_radar_size()
        return 300
    end

    function mod:get_marker_scale_group()
        return nil
    end

    function mod:get_marker_scale_factor()
        return 1
    end

    function mod:get_enemy_category_scale_factor()
        return 1
    end

    function mod:get_enemy_radar_definition()
        return nil
    end

    function mod:get_enemy_marker_mode()
        return "marked_icon"
    end

    function mod:get_radar_size()
        return 300
    end

    function mod:get_radar_range()
        return 25
    end

    function mod:get_radar_origin()
        return 100, 40, 10, 150
    end

    function mod:get_max_radar_markers()
        return 200
    end

    function mod:radar_projection_forward()
        return nil, nil
    end

    function mod:project_target_to_radar(_, _, _, position)
        return position[1], position[2]
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

    local function replace(name, value)
        debug.setupvalue(draw_internal, upvalue_index(draw_internal, name), value)
    end

    replace("RadarHudWidgets", {
        ensure_overview_scale_widget = noop,
        ensure_marker_widgets = noop,
        draw_marker_widget = noop,
        clear_marker_widget = noop,
        clear_overview_scale_widget = noop,
    })
    replace("RadarHudRenderer", {
        draw_radar_frame = noop,
        draw_radar_frame_background = noop,
        draw_radar_frame_foreground = noop,
        draw_box = noop,
        draw_marker_brackets = noop,
        begin_facing_outline = noop,
        add_facing_outline_box = noop,
        add_facing_outline_frame = noop,
        draw_marker_facing_chevron = noop,
    })
    replace("RadarStrikemapGeometry", {
        is_active = function()
            return false
        end,
    })
    replace("RadarNavmesh", {
        is_active = function()
            return true
        end,
        draw = function(...)
            harness.navmesh_draws[#harness.navmesh_draws + 1] = { n = select("#", ...), ... }
        end,
    })
    replace("_apply_marker_widget", noop)
    replace("_draw_overview_scale_overlay", noop)
    replace("_draw_screen_highlights", noop)

    local element = { _marker_widgets = {} }

    for i = 1, 301 do
        element._marker_widgets[i] = { content = {}, style = {} }
    end

    harness.element = element

    --- Draws one frame of a snapshot with no targets, from the Radar player of a revision.
    function harness.draw(revision, t)
        draw_internal(element, {}, { player_position = { x = 0, y = 0, z = 0 }, player_revision = revision,
            targets = {} }, t, nil)
    end

    return harness
end

test("the HUD element starts its coherency state over and selects new map geometry for a new Radar player", function()
    local harness = new_hud_harness()
    local element = harness.element

    harness.draw(4, 1)

    local state = element._radar_coherency_state_by_unit

    assert_true(type(state) == "table", "no coherency state")

    state.teammate = { in_coherency = true, seen_t = 1 }
    harness.draw(4, 1.02)
    assert_equal(state, element._radar_coherency_state_by_unit, "the state was replaced for the same Radar player")
    assert_true(state.teammate ~= nil, "the state was emptied for the same Radar player")

    harness.draw(5, 1.04)
    assert_true(state ~= element._radar_coherency_state_by_unit, "a new Radar player kept the old state")
    assert_nil(next(element._radar_coherency_state_by_unit), "a new Radar player started with old states")

    local draws = harness.navmesh_draws

    assert_equal(3, #draws, "navmesh draws")
    assert_equal(10, draws[1].n, "the navmesh draw got no revision")
    assert_equal(4, draws[1][10], "the first revision")
    assert_equal(5, draws[3][10], "the new revision")
end)

test("the HUD element starts its enemy threat state over for a new Radar player and forgets enemies it no longer draws",
    function()
        local harness = new_hud_harness()
        local element = harness.element

        harness.draw(4, 1)

        local state = element._radar_threat_state_by_unit
        local recent, stale = {}, {}

        assert_true(type(state) == "table", "no threat state")

        state[recent] = { seen_t = 1.5 }
        state[stale] = { seen_t = 0.2 }

        -- Between draw cache refreshes nothing is swept.
        harness.draw(4, 1.6)
        assert_true(state[stale] ~= nil, "a state was swept before the draw cache refreshed")

        -- At the refresh, an enemy not drawn for over a second goes and the others stay.
        harness.draw(4, 2.1)
        assert_equal(state, element._radar_threat_state_by_unit, "the threat state was replaced for the same Radar player")
        assert_nil(state[stale], "an enemy not drawn for over a second was kept")
        assert_true(state[recent] ~= nil, "an enemy drawn within the last second was forgotten")

        harness.draw(5, 2.2)
        assert_true(state ~= element._radar_threat_state_by_unit, "a new Radar player kept the old threat state")
        assert_nil(next(element._radar_threat_state_by_unit), "a new Radar player started with old threat states")
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

io.write(tostring(#tests), " tests passed\n")
