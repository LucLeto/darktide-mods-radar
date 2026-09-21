-- Where the screen highlight bracket is placed when the game is not drawing its
-- own interaction marker for a unit. Installs the real runtime helpers module
-- against a fake engine, so the placement is tested as it ships rather than as
-- a copy of its arithmetic.
local HELPERS_PATH = "Radar/scripts/mods/Radar/Radar_runtime_helpers.lua"

table.clear = table.clear or function(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assert_near(expected, actual, message)
    if actual == nil or math.abs(expected - actual) > 1e-6 then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- `boxes[unit]` is the box centre the engine reports for that unit. Leaving a
-- unit out means the engine has no box for it. `nodes[unit][name]` is the world
-- position of that unit's named node; a node left out does not exist.
local function new_harness(options)
    options = options or {}

    local boxes = {}
    local nodes = {}
    local mod = { _logged_units = {} }

    function mod:get()
        return nil
    end

    function mod:info()
    end

    local env = { mod = mod, POSITION_LOOKUP = {} }

    setmetatable(env, { __index = _G })

    env.Unit = {
        alive = function()
            return true
        end,
        has_node = options.has_node or function(unit, name)
            local unit_nodes = nodes[unit]

            return unit_nodes ~= nil and unit_nodes[name] ~= nil
        end,
        node = options.node or function(_, name)
            return name
        end,
        world_position = options.world_position or function(unit, index)
            local unit_nodes = nodes[unit]

            return unit_nodes and unit_nodes[index] or nil
        end,
        box = options.box or function(unit)
            local center = boxes[unit]

            if center == nil then
                return nil
            end

            return { center = center }, { x = 0.5, y = 0.5, z = 0.5 }
        end,
    }

    if options.no_matrix ~= true then
        env.Matrix4x4 = {
            translation = options.translation or function(pose)
                return pose.center
            end,
        }
    end

    local chunk = assert(loadfile(HELPERS_PATH))

    chunk()(env)

    env._safe_unit_position = function(unit)
        return unit and unit.position or nil
    end

    env._safe_unit_alive = function(unit)
        return unit ~= nil
    end

    return {
        env = env,
        boxes = boxes,
        nodes = nodes,
        place = function(target)
            return env._screen_highlight_projection_fallback_position(target)
        end,
    }
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

-- Archivum Sycorax: every scan target had neither the game's own marker nor a
-- `ui_interaction_marker` node, so the bracket fell to the prefab root, which on
-- a wall terminal is its mounting point. Screenshots showed it above and beside
-- the panel the auspex had to be aimed at.
test("a scan target is framed on the middle of its box", function()
    local harness = new_harness()
    local terminal = { position = { x = 10, y = 20, z = 0 } }

    harness.boxes[terminal] = { x = 10.4, y = 19.1, z = -1.2 }

    local placed = harness.place({ unit = terminal, kind = "mission_objective_scanner" })

    assert_near(10.4, placed.x, "the bracket is not on the box centre")
    assert_near(19.1, placed.y, "the bracket is not on the box centre")
    -- The same small lift every objective has always had, on top of the centre.
    assert_near(-1.2 + 0.12, placed.z, "the bracket lost its objective lift")
end)

test("every objective category is framed on its box", function()
    for _, kind in ipairs({
        "mission_objective_scanner",
        "mission_objective_hacking",
        "mission_objective_servo_skull",
        "mission_objective_growth",
        "mission_objective_destroy",
        "mission_objective_other",
    }) do
        local harness = new_harness()
        local prop = { position = { x = 0, y = 0, z = 0 } }

        harness.boxes[prop] = { x = 3, y = 4, z = 5 }

        local placed = harness.place({ unit = prop, kind = kind })

        assert_near(3, placed.x, kind .. " is not framed on its box")
    end
end)

-- #103 lowered the pickup bracket to the item's origin on purpose: the node sits
-- above a pickup where the prompt floats, and with no prompt a bracket up there
-- looks detached. A box centre would move it again, so pickups must not get it.
test("a pickup keeps its origin, as #103 intended", function()
    local harness = new_harness()
    local ammo = { position = { x = 7, y = 8, z = 9 } }

    harness.boxes[ammo] = { x = 7, y = 8, z = 10 }

    local placed = harness.place({ unit = ammo, kind = "pickup_ammo_big" })

    assert_near(9 + 0.08, placed.z, "a pickup's bracket moved off its origin")
end)

test("a non-objective kind is never given the box", function()
    for _, kind in ipairs({ "crate_unknown", "hazard_explosive_barrel", "material_plasteel", "medicae_station" }) do
        local harness = new_harness()
        local prop = { position = { x = 1, y = 1, z = 1 } }

        harness.boxes[prop] = { x = 50, y = 50, z = 50 }

        local placed = harness.place({ unit = prop, kind = kind })

        assert_near(1, placed.x, kind .. " was moved onto its box")
    end
end)

-- Every way the engine can fail to give a box has to leave the bracket exactly
-- where it would have been before, and none of them may raise.
test("an objective with no box keeps its origin", function()
    local harness = new_harness()
    local prop = { position = { x = 2, y = 3, z = 4 } }
    local placed = harness.place({ unit = prop, kind = "mission_objective_scanner" })

    assert_near(2, placed.x, "an objective with no box moved")
    assert_near(4 + 0.12, placed.z, "an objective with no box moved")
end)

test("a box call that raises keeps the origin and does not raise", function()
    local harness = new_harness({
        box = function()
            error("engine refused")
        end,
    })
    local prop = { position = { x = 2, y = 3, z = 4 } }
    local ok, placed = pcall(harness.place, { unit = prop, kind = "mission_objective_scanner" })

    assert_equal(true, ok, "a raising box call took the placement down")
    assert_near(2, placed.x, "a raising box call moved the bracket")
end)

test("no Matrix4x4 keeps the origin", function()
    local harness = new_harness({ no_matrix = true })
    local prop = { position = { x = 2, y = 3, z = 4 } }

    harness.boxes[prop] = { x = 99, y = 99, z = 99 }

    local placed = harness.place({ unit = prop, kind = "mission_objective_scanner" })

    assert_near(2, placed.x, "without Matrix4x4 the bracket still moved")
end)

test("a translation that raises or returns nonsense keeps the origin", function()
    for label, translation in pairs({
        raises = function()
            error("bad pose")
        end,
        nonsense = function()
            return "not a vector"
        end,
        empty = function()
            return nil
        end,
    }) do
        local harness = new_harness({ translation = translation })
        local prop = { position = { x = 2, y = 3, z = 4 } }

        harness.boxes[prop] = { x = 99, y = 99, z = 99 }

        local ok, placed = pcall(harness.place, { unit = prop, kind = "mission_objective_scanner" })

        assert_equal(true, ok, label .. ": the placement raised")
        assert_near(2, placed.x, label .. ": the bracket moved without a usable centre")
    end
end)

-- Unchanged: with no unit at all there is nothing to measure and the scan's own
-- position is used.
test("a target with no unit still uses its recorded position", function()
    local harness = new_harness()
    local placed = harness.place({ kind = "mission_objective_scanner", position = { x = 5, y = 6, z = 7 } })

    assert_near(5, placed.x, "a unitless target lost its position")
end)

-- #170: a hanging barrel's origin is its ceiling mount, so the bracket floated
-- at the ceiling. The game detonates both barrel kinds from `c_explosion`, and
-- tracking already records that node, so the barrel body wins over the origin.
local BARREL_KINDS = { "hazard_explosive_barrel", "hazard_fire_barrel" }

local function hanging_barrel()
    return { position = { x = 1, y = 2, z = 8 } }
end

test("a hanging barrel is framed on its explosion node, not its mounting point", function()
    for _, kind in ipairs(BARREL_KINDS) do
        local harness = new_harness()
        local barrel = hanging_barrel()

        harness.nodes[barrel] = { c_explosion = { x = 1.3, y = 2.4, z = 5 } }

        local placed = harness.place({ unit = barrel, kind = kind, position = { x = 1.3, y = 2.4, z = 5 } })

        assert_near(1.3, placed.x, kind .. " is not on its explosion node")
        assert_near(2.4, placed.y, kind .. " is not on its explosion node")
        assert_near(5 + 0.12, placed.z, kind .. " is not on its explosion node")
    end
end)

test("a barrel's bracket follows its explosion node as it moves", function()
    for _, kind in ipairs(BARREL_KINDS) do
        local harness = new_harness()
        local barrel = hanging_barrel()
        local target = { unit = barrel, kind = kind, position = { x = 1, y = 2, z = 5 } }

        harness.nodes[barrel] = { c_explosion = { x = 1, y = 2, z = 5 } }
        assert_near(5 + 0.12, harness.place(target).z, kind .. " is not on its explosion node")

        harness.nodes[barrel].c_explosion = { x = 1.2, y = 2, z = 4.5 }

        local moved = harness.place(target)

        assert_near(1.2, moved.x, kind .. " stayed on a stale position")
        assert_near(4.5 + 0.12, moved.z, kind .. " stayed on a stale position")
    end
end)

test("a barrel with no explosion node uses its recorded position, not its origin", function()
    for _, kind in ipairs(BARREL_KINDS) do
        local harness = new_harness()
        local placed = harness.place({ unit = hanging_barrel(), kind = kind, position = { x = 1, y = 2, z = 5 } })

        assert_near(5 + 0.12, placed.z, kind .. " fell to its origin despite a recorded position")
    end
end)

-- Every way the node lookup can fail has to degrade to the recorded position,
-- and none of them may raise.
test("a failing explosion node lookup falls back and does not raise", function()
    local function raises()
        error("engine refused")
    end

    for label, options in pairs({
        has_node_raises = { has_node = raises },
        node_raises = { has_node = function() return true end, node = raises },
        world_position_raises = { has_node = function() return true end, world_position = raises },
        world_position_empty = { has_node = function() return true end, world_position = function() return nil end },
        world_position_nonsense = {
            has_node = function() return true end,
            world_position = function() return "not a vector" end,
        },
    }) do
        for _, kind in ipairs(BARREL_KINDS) do
            local harness = new_harness(options)
            local target = { unit = hanging_barrel(), kind = kind, position = { x = 1, y = 2, z = 5 } }
            local ok, placed = pcall(harness.place, target)

            assert_equal(true, ok, label .. ": " .. kind .. " placement raised")
            assert_near(5 + 0.12, placed.z, label .. ": " .. kind .. " did not fall back to its recorded position")
        end
    end
end)

test("a barrel with neither node nor recorded position keeps its origin", function()
    for _, kind in ipairs(BARREL_KINDS) do
        local harness = new_harness()
        local placed = harness.place({ unit = hanging_barrel(), kind = kind })

        assert_near(1, placed.x, kind .. " lost its origin")
        assert_near(8 + 0.12, placed.z, kind .. " lost its origin")
    end
end)

test("a barrel target with no unit uses its recorded position", function()
    for _, kind in ipairs(BARREL_KINDS) do
        local harness = new_harness()
        local placed = harness.place({ kind = kind, position = { x = 3, y = 4, z = 5 } })

        assert_near(3, placed.x, kind .. " lost its recorded position")
        assert_near(5 + 0.12, placed.z, kind .. " lost its recorded position")
    end
end)

test("only barrels are placed on an explosion node", function()
    local harness = new_harness()
    local ammo = { position = { x = 7, y = 8, z = 9 } }
    local terminal = { position = { x = 10, y = 20, z = 0 } }

    harness.nodes[ammo] = { c_explosion = { x = 70, y = 80, z = 90 } }
    harness.nodes[terminal] = { c_explosion = { x = 70, y = 80, z = 90 } }
    harness.boxes[terminal] = { x = 10.4, y = 19.1, z = -1.2 }

    local pickup = harness.place({ unit = ammo, kind = "pickup_ammo_big", position = { x = 60, y = 60, z = 60 } })
    local objective = harness.place({ unit = terminal, kind = "mission_objective_scanner" })

    assert_near(7, pickup.x, "a pickup moved off its origin")
    assert_near(9 + 0.08, pickup.z, "a pickup moved off its origin")
    assert_near(10.4, objective.x, "an objective moved off its box centre")
    assert_near(-1.2 + 0.12, objective.z, "an objective moved off its box centre")
end)

-- The marker list says "the game shows something here" for every marker type.
-- Only an `objective` marker is the game pointing at a step; the prompt a player
-- gets standing next to something is not.
test("only an objective marker counts as the game marking an objective", function()
    local harness = new_harness()
    local step = {}
    local locker = {}

    harness.env._safe_world_markers_list = function()
        return { { unit = step, type = "objective" }, { unit = locker, type = "interaction" } }
    end

    local out = {}

    assert_equal(true, harness.env._refresh_world_marker_units(out), "the marker list was not read")
    assert_equal(true, out[step] == true and out[locker] == true, "a marked unit is missing from the set")
    assert_equal(true, harness.env._game_marks_as_objective(step), "an objective marker is not counted")
    assert_equal(false, harness.env._game_marks_as_objective(locker), "a prompt was counted as an objective marker")
end)

-- The game's own reach test: a marker past its template's `max_distance` is
-- not drawn, unless the marker lifts the limit; one not measured yet counts as
-- drawn. Presence in the set is unaffected. Mortis Trials marks arenas 550 to
-- 650 metres off against an objective marker's 300.
test("a marker the game holds out of reach is not counted as drawn", function()
    local harness = new_harness()
    local template = { max_distance = 300 }
    local near = {}
    local far = {}
    local lifted = {}
    local unmeasured = {}

    harness.env._safe_world_markers_list = function()
        return {
            { unit = near, type = "objective", template = template, distance = 55 },
            { unit = far, type = "objective", template = template, distance = 600 },
            { unit = lifted, type = "objective", template = template, distance = 600, block_max_distance = true },
            { unit = unmeasured, type = "objective", template = template },
        }
    end

    local out = {}

    harness.env._refresh_world_marker_units(out)

    assert_equal(true, out[far] == true, "a marker out of reach dropped out of the presence set")
    assert_equal(true, harness.env._game_draws_marker_on(near), "a marker in reach is not counted as drawn")
    assert_equal(false, harness.env._game_draws_marker_on(far), "a marker past its reach is counted as drawn")
    assert_equal(true, harness.env._game_draws_marker_on(lifted), "a marker with its limit lifted is not counted")
    assert_equal(true, harness.env._game_draws_marker_on(unmeasured), "a marker not measured yet is not counted")
end)

local failures = {}

for i = 1, #tests do
    local current = tests[i]
    local ok, failure = xpcall(current.fn, debug.traceback)

    if ok then
        io.write("PASS ", current.name, "\n")
    else
        failures[#failures + 1] = current.name .. "\n" .. tostring(failure)
        io.write("FAIL ", current.name, "\n")
    end
end

io.write("\n")

if #failures > 0 then
    for i = 1, #failures do
        io.write(failures[i], "\n\n")
    end

    io.write(tostring(#failures), " of ", tostring(#tests), " tests failed\n")
    os.exit(1)
end

io.write(tostring(#tests), " tests passed\n")
