-- Where the screen highlight bracket is placed when the game is not drawing its
-- own interaction marker for a unit. Installs the real runtime helpers module
-- against a fake engine, so the placement is tested as it ships rather than as
-- a copy of its arithmetic.
local HELPERS_PATH = "Radar/scripts/mods/Radar/Radar_runtime_helpers.lua"

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
-- unit out means the engine has no box for it.
local function new_harness(options)
    options = options or {}

    local boxes = {}
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
        has_node = function()
            return false
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
