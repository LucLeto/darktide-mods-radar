-- Which way a teammate, Cyber Mastiff or enemy looks, from the unit to the radar target.
-- Installs the real runtime helpers and tracking modules into a fake shared environment, reads
-- headings through `_safe_target_heading_xy` against fake units, extensions and rotations, and
-- builds radar targets through `_collect_radar_targets`, reached through the upvalues of the
-- update the `StateGameplay.update` hook runs. A teammate looks where its first person rotation
-- points, and a mastiff or an enemy faces where its root points; a target only takes a heading
-- while its facing direction setting is on (teammates and the mastiff unless switched off,
-- enemies per category once switched on), a teammate who is dead, waiting for rescue or captured
-- takes none, nor does an enemy a Cyber Mastiff pins, and a pooled target table never keeps the
-- heading of the target it held before.

local HELPERS_PATH = "Radar/scripts/mods/Radar/Radar_runtime_helpers.lua"
local TRACKING_PATH = "Radar/scripts/mods/Radar/Radar_tracking.lua"

table.clear = table.clear or function(t)
    for key in pairs(t) do
        t[key] = nil
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

local function assert_near(expected, actual, message)
    if type(actual) ~= "number" or math.abs(expected - actual) > 1e-9 then
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

local function install(path, env)
    local chunk, load_error = loadfile(path)

    assert(chunk, load_error)
    chunk()(env)
end

local function noop()
end

-- A rotation is a table holding its forward vector; `broken` makes the engine getter throw.
local function rotation(x, y, z)
    return { forward = { x = x, y = y, z = z or 0 } }
end

local NORTH = rotation(0, 1)
local EAST = rotation(1, 0)

local function new_harness()
    local captured = {}
    local alive = {}
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
        enemy_facing = {},
        pinned = {},
    }
    local mod = {
        _tracked_units = {},
        _tracked_points = {},
    }

    function mod:get(setting_id)
        return settings[setting_id]
    end

    function mod:set(setting_id, value)
        settings[setting_id] = value
    end

    function mod:show_enemy_facing(kind)
        return world.enemy_facing[kind] == true
    end

    function mod:get_player_marker_range_mode()
        return "default"
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

    mod.hook = noop
    mod.register_hud_element = noop
    mod.info = noop
    mod.error = noop
    mod.notify = noop

    local env = {
        mod = mod,
        ALIVE = alive,
        POSITION_LOOKUP = {},
        SCAN_INTERVAL = 0.25,
        KIND_TO_SETTING = {},
        RESPAWN_MARKER_KINDS = {},
        SAFEROUTE_MARKER_KINDS = {},
        ENEMY_RADAR_DEFINITION_BY_KIND = {},
        NEARBY_HIGHLIGHT_SETTING_BY_GROUP = {},
        CLASS = { InputService = {} },
        Quaternion = {
            forward = function(rot)
                if rot.broken then
                    error("not a rotation")
                end

                return rot.forward
            end,
        },
        Unit = {
            world_rotation = function(unit)
                if unit.root_rotation == nil then
                    error("no root rotation")
                end

                return unit.root_rotation
            end,
        },
        ScriptUnit = {
            has_extension = function(unit, system_name)
                return unit.extensions and unit.extensions[system_name] or nil
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

    local player_unit = { position = { x = 0, y = 0, z = 0 } }
    local radar_player = {
        unit = player_unit,
        position = player_unit.position,
        mode = "local",
        usable = true,
        reason = "ok",
        revision = 1,
    }

    alive[player_unit] = true

    -- What the scans around the collection would decide; here every kind is enabled, every
    -- unit still alive is trackable, and the player scan found a mastiff pinning each `pinned` unit.
    env._radar_player = function()
        return radar_player
    end
    env._safe_unit_position = function(unit)
        return type(unit) == "table" and unit.position or nil
    end
    env._is_trackable_unit_alive = function(unit)
        return alive[unit] == true
    end
    env._kind_enabled = function()
        return true
    end
    env._mastiff_disabled_enemy_units = function()
        return world.pinned
    end
    env._cluster_expedition_loot_targets = function(targets)
        return targets
    end

    local update_internal = named_upvalue(captured.state_gameplay_update, "_update_internal")
    local collect_radar_targets = named_upvalue(update_internal, "_collect_radar_targets")
    local harness = {
        env = env,
        mod = mod,
        settings = settings,
        world = world,
    }

    --- Makes a unit with a root rotation and, for a teammate, a first person rotation.
    function harness:unit(options)
        local unit = {
            position = options.position or { x = 1, y = 1, z = 0 },
            root_rotation = options.root,
        }

        if options.first_person ~= nil or options.unit_data then
            local component = options.first_person ~= false and { rotation = options.first_person } or nil
            local extension = options.unit_data or {
                read_component = function(_, component_name)
                    if component_name == "first_person" then
                        return component
                    end

                    return nil
                end,
            }

            unit.extensions = { unit_data_system = extension }
        end

        if options.alive ~= false then
            alive[unit] = true
        end

        return unit
    end

    --- Tracks a unit as a radar target of a kind.
    function harness:track(unit, kind, meta)
        mod._tracked_units[unit] = {
            kind = kind,
            source = "test",
            position = unit.position,
            meta = meta,
            last_seen_t = 0,
        }
    end

    --- Builds the radar targets and returns them by unit.
    function harness:collect()
        local targets = collect_radar_targets()
        local by_unit = {}

        for i = 1, #targets do
            by_unit[targets[i].unit] = targets[i]
        end

        return targets, by_unit
    end

    function harness:forget()
        for unit in pairs(mod._tracked_units) do
            mod._tracked_units[unit] = nil
        end
    end

    return harness
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("a teammate looks where its first person rotation points, never where its body faces", function()
    local harness = new_harness()
    local heading = harness.env._safe_target_heading_xy
    local teammate = harness:unit({ root = EAST, first_person = rotation(0, 3, 4) })
    local x, y = heading(teammate, "player_teammate")

    assert_near(0, x, "look x")
    assert_near(1, y, "look y, flattened and normalised")

    local broken = rotation(1, 0)

    broken.broken = true

    local unreadable = {
        harness:unit({ root = EAST }),
        harness:unit({ root = EAST, first_person = false }),
        harness:unit({ root = EAST, first_person = rotation(math.huge, math.huge, math.huge) }),
        harness:unit({ root = EAST, first_person = rotation(0, 0, 1) }),
        harness:unit({ root = EAST, first_person = broken }),
        harness:unit({ root = EAST, unit_data = {} }),
        harness:unit({
            root = EAST,
            unit_data = {
                read_component = function()
                    error("no such component")
                end,
            },
        }),
        harness:unit({ root = EAST, first_person = NORTH, alive = false }),
    }

    for i = 1, #unreadable do
        x, y = heading(unreadable[i], "player_teammate")

        assert_nil(x, "case " .. i .. " has a look direction")
        assert_nil(y, "case " .. i .. " has a look direction")
    end
end)

test("an enemy faces where its root points", function()
    local harness = new_harness()
    local heading = harness.env._safe_target_heading_xy
    local x, y = heading(harness:unit({ root = rotation(-3, 4, 2), first_person = NORTH }), "enemy_renegade_gunner")

    assert_near(-0.6, x, "facing x")
    assert_near(0.8, y, "facing y")

    local broken = rotation(1, 0)

    broken.broken = true

    for i, unit in ipairs({
        harness:unit({}),
        harness:unit({ root = broken }),
        harness:unit({ root = rotation(0 / 0, 1) }),
        harness:unit({ root = EAST, alive = false }),
    }) do
        x, y = heading(unit, "enemy_renegade_gunner")

        assert_nil(x, "case " .. i .. " has a facing")
        assert_nil(y, "case " .. i .. " has a facing")
    end

    x, y = heading(nil, "enemy_renegade_gunner")

    assert_nil(x, "no unit has a facing")
    assert_nil(y, "no unit has a facing")
end)

test("only targets whose facing setting is on take a heading", function()
    local harness = new_harness()
    local world = harness.world
    local settings = harness.settings

    world.enemy_facing.enemy_renegade_gunner = true
    world.enemy_facing.enemy_captain = true

    local looking = rotation(0, 1)
    local facing = rotation(1, 0)
    local teammate = harness:unit({ root = facing, first_person = looking })
    local carrying = harness:unit({ root = facing, first_person = looking })
    local mastiff = harness:unit({ root = rotation(0, -1) })
    local skull = harness:unit({ root = facing })
    local gunner = harness:unit({ root = facing })
    local poxwalker = harness:unit({ root = facing })
    local outlined = harness:unit({ root = facing })
    local captain = harness:unit({ root = facing })
    local daemonhost = harness:unit({ root = facing })
    local pickup = harness:unit({ root = facing })
    local states = {}

    settings.show_ability_marked_enemies = true

    harness:track(teammate, "player_teammate", {})
    harness:track(carrying, "player_teammate", { player_radar_state = "luggable" })
    harness:track(mastiff, "player_companion_dog", {})
    harness:track(skull, "player_companion_servo_skull", {})
    harness:track(gunner, "enemy_renegade_gunner", {})
    harness:track(poxwalker, "enemy_poxwalker", {})
    harness:track(outlined, "enemy_poxwalker", { ability_marked = true })
    harness:track(captain, "enemy_captain", {})
    harness:track(daemonhost, "enemy_daemonhost", {})
    harness:track(pickup, "pickup_ammo_small", {})

    for _, state in ipairs({ "dead", "rescue", "captured" }) do
        states[state] = harness:unit({ root = facing, first_person = looking })
        harness:track(states[state], "player_teammate", { player_radar_state = state })
    end

    local _, by_unit = harness:collect()

    local function check(unit, x, y, label)
        local target = by_unit[unit]

        assert(target, label .. " is not a target")

        if x == nil then
            assert_nil(target.heading_x, label .. " has a heading")
            assert_nil(target.heading_y, label .. " has a heading")
        else
            assert_near(x, target.heading_x, label .. " heading x")
            assert_near(y, target.heading_y, label .. " heading y")
        end
    end

    check(teammate, 0, 1, "a teammate by default")
    check(carrying, 0, 1, "a teammate carrying a luggable")
    check(mastiff, 0, -1, "a Cyber Mastiff by default, by its root")
    check(skull, nil, nil, "a servo skull")
    check(gunner, 1, 0, "an enemy whose category shows its facing")
    check(poxwalker, nil, nil, "an enemy whose category does not")
    check(outlined, nil, nil, "an enemy outlined by an ability whose category does not")
    check(captain, 1, 0, "a boss while the boss setting is on")
    check(daemonhost, nil, nil, "a boss kind its category leaves off")
    check(pickup, nil, nil, "a pickup")

    for state, unit in pairs(states) do
        check(unit, nil, nil, "a teammate in the " .. state .. " state")
    end

    settings.show_player_facing = false
    settings.show_cyber_mastiff_facing = false
    world.enemy_facing.enemy_poxwalker = true
    world.enemy_facing.enemy_renegade_gunner = false
    _, by_unit = harness:collect()

    check(teammate, nil, nil, "a teammate with the setting off")
    check(mastiff, nil, nil, "a Cyber Mastiff with the setting off")
    check(poxwalker, 1, 0, "an enemy once its category shows its facing")
    check(outlined, 1, 0, "an outlined enemy once its category shows its facing")
    check(gunner, nil, nil, "an enemy once its category stops")

    settings.show_player_facing = true
    _, by_unit = harness:collect()

    check(teammate, 0, 1, "a teammate with the setting back on")
end)

test("an enemy a Cyber Mastiff pins takes no heading while it is pinned", function()
    local harness = new_harness()

    harness.world.enemy_facing.enemy_renegade_gunner = true

    local gunner = harness:unit({ root = NORTH })

    harness:track(gunner, "enemy_renegade_gunner", {})
    harness.world.pinned[gunner] = true

    local _, by_unit = harness:collect()

    assert_equal(true, by_unit[gunner].disabled_by_mastiff, "the gunner is not pinned")
    assert_nil(by_unit[gunner].heading_x, "a pinned enemy took a heading")
    assert_nil(by_unit[gunner].heading_y, "a pinned enemy took a heading")

    harness.world.pinned[gunner] = nil
    _, by_unit = harness:collect()

    assert_near(1, by_unit[gunner].heading_y, "a freed enemy took no heading")
end)

test("a pooled target never keeps the heading of the target it held before", function()
    local harness = new_harness()

    harness.world.enemy_facing.enemy_renegade_gunner = true

    local gunner = harness:unit({ root = rotation(0, -1) })
    local pickup = harness:unit({ root = rotation(1, 0) })

    harness:track(gunner, "enemy_renegade_gunner", {})

    local targets = harness:collect()
    local pooled = targets[1]

    assert_equal(gunner, pooled.unit, "the first target")
    assert_near(-1, pooled.heading_y, "the gunner's heading")

    harness:forget()
    harness:track(pickup, "pickup_ammo_small", {})
    targets = harness:collect()

    assert_equal(pooled, targets[1], "the pool did not hand out the same table")
    assert_equal(pickup, targets[1].unit, "the second target")
    assert_nil(targets[1].heading_x, "the pickup kept the gunner's heading")
    assert_nil(targets[1].heading_y, "the pickup kept the gunner's heading")

    -- The same enemy, turned and then unreadable, follows its unit rather than the last scan.
    harness:forget()
    harness:track(gunner, "enemy_renegade_gunner", {})
    gunner.root_rotation = rotation(-1, 0)
    targets = harness:collect()

    assert_near(-1, targets[1].heading_x, "the turned gunner's heading")

    gunner.root_rotation = nil
    targets = harness:collect()

    assert_nil(targets[1].heading_x, "an unreadable gunner kept its last heading")
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
