-- Building the live navmesh as a mission starts instead of on the first radar draw.
-- Installs the real navmesh module against a fake GwNav database and sends it the game state
-- changes DMF sends. The build must run once, only when the first draw would have built the same
-- thing, and every case it skips or that fails must still build on a radar draw as before. In an
-- Expedition, each section's navmesh replaces the previous one inside the same nav world, and the
-- floor must follow it.

local NAVMESH_PATH = "Radar/scripts/mods/Radar/Radar_navmesh.lua"

local function assert_true(value, message)
    if value ~= true then
        error(message or "expected true", 2)
    end
end

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assert_contains(text, fragment, message)
    if type(text) ~= "string" or text:find(fragment, 1, true) == nil then
        error((message or "fragment missing") .. ": `" .. fragment .. "` not in `" .. tostring(text) .. "`", 2)
    end
end

local function triangle(x, y, z)
    return {
        { x = x, y = y, z = z },
        { x = x + 3, y = y, z = z },
        { x = x, y = y + 3, z = z },
    }
end

--- Two valid triangles in two bucket cells, and one with a corrupt vertex that is skipped.
local function new_nav_world()
    return {
        tiles = {
            { triangle(0, 0, 0), triangle(20, 20, 1) },
            { triangle(1000000, 0, 0) },
        },
    }
end

local function new_harness(options)
    options = options or {}

    local harness = {
        calls = { visual = 0, previous = {}, game_mode = 0 },
        info = {},
        spawner = options.spawner,
        alive = nil,
        nav_mesh = {
            _nav_world = options.nav_world or new_nav_world(),
            _dynamic_mesh_spawning = options.dynamic_mesh_spawning == true,
        },
        settings = { debug_mode = options.debug_mode == true },
        source = options.source or "live",
        enabled = options.enabled ~= false,
        allowed = options.allowed ~= false,
        profiling = options.profiling == true,
        visual_failure = options.visual_failure,
        allowed_failure = options.allowed_failure,
    }
    local calls = harness.calls
    local mod = {}

    harness.mod = mod

    function mod:get(id)
        return harness.settings[id]
    end

    function mod:info(text)
        harness.info[#harness.info + 1] = text
    end

    function mod:is_enabled()
        return harness.enabled
    end

    function mod:get_map_geometry_source()
        return harness.source
    end

    function mod:is_radar_runtime_game_mode_allowed()
        if harness.allowed_failure then
            error(harness.allowed_failure)
        end

        return harness.allowed
    end

    function mod:radar_profiler_mark()
        return harness.profiling and {} or nil
    end

    function mod:radar_profiler_elapsed_ms(since)
        return harness.profiling and since and 2 or nil
    end

    if not options.no_previous_handler then
        mod.on_game_state_changed = function(status, state_name)
            calls.previous[#calls.previous + 1] = {
                status = status,
                state_name = state_name,
                visual_before = calls.visual,
            }
        end
    end

    local env = setmetatable({
        GwNavWorld = {
            build_database_visual_representation = function()
                calls.visual = calls.visual + 1

                if harness.visual_failure then
                    error(harness.visual_failure)
                end
            end,
            database_tile_count = function(nav_world)
                return #nav_world.tiles
            end,
            database_tile_triangle_count = function(nav_world, tile)
                return #nav_world.tiles[tile]
            end,
            database_triangle = function(nav_world, tile, index)
                local entry = nav_world.tiles[tile][index]

                return entry[1], entry[2], entry[3]
            end,
        },
        -- A section's navmesh is in the database unless the test lists which ones are.
        GwNavData = {
            is_alive_in_database = function(nav_data)
                return harness.alive == nil or harness.alive[nav_data] == true
            end,
        },
        Managers = { state = { nav_mesh = harness.nav_mesh } },
        Script = {
            temp_byte_count = function()
                return 0
            end,
            set_temp_byte_count = function()
            end,
        },
    }, { __index = _G })

    -- The Expedition game mode keeps its level spawner on its logic; `false` stands for one without.
    if options.spawner ~= nil then
        env._safe_game_mode = function()
            calls.game_mode = calls.game_mode + 1

            return { _game_mode_logic = harness.spawner and { _levels_spawner = harness.spawner } or {} }
        end
    end

    local previous_get_mod = rawget(_G, "get_mod")

    rawset(_G, "get_mod", function()
        return mod
    end)

    local chunk, load_error = loadfile(NAVMESH_PATH)

    assert(chunk, load_error)
    chunk()(env)
    rawset(_G, "get_mod", previous_get_mod)

    function harness.enter_mission()
        mod.on_game_state_changed("enter", "GameplayStateRun")
    end

    function harness.draw(t)
        return mod:ensure_navmesh_geometry(t)
    end

    return harness
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("entering a mission builds the navmesh once, before any draw", function()
    local harness = new_harness()

    harness.enter_mission()
    assert_equal(1, harness.calls.visual, "build on entering")

    local geometry = harness.draw(5)

    assert_equal(1, harness.calls.visual, "the first draw must not build again")
    assert_equal(2, geometry.count, "the corrupt triangle is skipped")
    assert_equal(2, harness.mod:get_navmesh_nearby_buckets(0, 0, 16, {}), "both cells are in the bucket grid")

    harness.draw(6)
    assert_equal(1, harness.calls.visual, "later draws must not build again")
end)

test("the previous handler runs first and receives the arguments", function()
    local harness = new_harness()

    harness.enter_mission()

    local previous = harness.calls.previous[1]

    assert_equal(1, #harness.calls.previous, "called once")
    assert_equal("enter", previous.status)
    assert_equal("GameplayStateRun", previous.state_name)
    assert_equal(0, previous.visual_before, "tracking resets its state before the build")
end)

test("it works without a previous handler", function()
    local harness = new_harness({ no_previous_handler = true })

    harness.enter_mission()
    assert_equal(1, harness.calls.visual)
end)

test("other state changes do not build", function()
    local harness = new_harness()

    harness.mod.on_game_state_changed("exit", "GameplayStateRun")
    harness.mod.on_game_state_changed("enter", "GameplayStateInit")
    harness.mod.on_game_state_changed("enter", "StateGameplay")
    harness.mod.on_game_state_changed("enter", "StateLoading")

    assert_equal(0, harness.calls.visual)
    assert_equal(4, #harness.calls.previous, "still forwarded")
end)

for _, source in ipairs({ "off", "strikemap", "auto" }) do
    test("the " .. source .. " source does not build on entering, a draw still can", function()
        local harness = new_harness({ source = source })

        harness.enter_mission()
        assert_equal(0, harness.calls.visual, "no build on entering")

        harness.draw(5)
        assert_equal(1, harness.calls.visual, "the draw path is unchanged")
    end)
end

test("a disabled mod does not build on entering", function()
    local harness = new_harness({ enabled = false })

    harness.enter_mission()
    assert_equal(0, harness.calls.visual)
end)

test("a game mode the radar does not run in does not build on entering", function()
    local harness = new_harness({ allowed = false })

    harness.enter_mission()
    assert_equal(0, harness.calls.visual)
end)

test("a game mode that spawns its navmesh later builds on the first draw", function()
    local harness = new_harness({ dynamic_mesh_spawning = true })

    harness.enter_mission()
    assert_equal(0, harness.calls.visual, "its data may still be incomplete")

    harness.draw(5)
    assert_equal(1, harness.calls.visual)
end)

test("no nav mesh manager means no build and no error", function()
    local harness = new_harness()

    harness.nav_mesh._nav_world = nil
    harness.enter_mission()
    assert_equal(0, harness.calls.visual)

    local geometry = harness.draw(5)

    assert_equal(0, geometry.count)
end)

test("an engine failure stays inside the callback and a draw retries after the cooldown", function()
    local harness = new_harness({ visual_failure = "engine failure" })

    harness.enter_mission()
    assert_equal(1, harness.calls.visual, "attempted")

    harness.visual_failure = nil
    harness.draw(0.1)
    assert_equal(1, harness.calls.visual, "inside the cooldown")

    local geometry = harness.draw(0.6)

    assert_equal(2, harness.calls.visual, "retried by the draw")
    assert_equal(2, geometry.count)
end)

test("an empty database at the start is retried by a draw", function()
    local nav_world = { tiles = {} }
    local harness = new_harness({ nav_world = nav_world })

    harness.enter_mission()
    assert_equal(0, harness.draw(0.1).count, "nothing yet")

    nav_world.tiles = new_nav_world().tiles

    assert_equal(2, harness.draw(0.6).count, "built once the data is there")
end)

test("a failing gate stays inside the callback and is logged in debug mode", function()
    local harness = new_harness({ allowed_failure = "gate failure", debug_mode = true })

    harness.enter_mission()
    assert_equal(0, harness.calls.visual)
    assert_contains(harness.info[1], "gate failure")
end)

test("the next mission replaces the previous mission's geometry on entering", function()
    local harness = new_harness()

    harness.enter_mission()

    local revision = harness.draw(5).revision
    local next_nav_world = { tiles = { { triangle(100, 100, 5) } } }

    harness.nav_mesh._nav_world = next_nav_world
    harness.enter_mission()

    assert_equal(2, harness.calls.visual, "built for the new nav world")

    local geometry = harness.draw(1)

    assert_equal(2, harness.calls.visual, "and not again on its first draw")
    assert_equal(1, geometry.count, "only the new mission's triangle")
    assert_equal(100, geometry.ax[1], "the new mission's vertex")
    assert_equal(0, harness.mod:get_navmesh_nearby_buckets(0, 0, 16, {}), "no old cells left")
    assert_true(geometry.revision > revision, "consumers see the change")
end)

test("an Expedition section's new navmesh replaces the old floor on the next draw", function()
    local nav_world = new_nav_world()
    local harness = new_harness({
        nav_world = nav_world,
        dynamic_mesh_spawning = true,
        spawner = { _nav_data_created = "section 1" },
    })

    local geometry = harness.draw(5)
    local revision = geometry.revision

    assert_equal(1, harness.calls.visual, "the first section is built on the first draw")
    assert_equal(2, geometry.count)

    harness.draw(5.1)
    assert_equal(1, harness.calls.visual, "the same section is not built again")

    -- The game removes the old section's navmesh and bakes the next one in the same nav world.
    nav_world.tiles = { { triangle(300, 300, 9) } }
    harness.spawner._nav_data_created = "section 2"
    geometry = harness.draw(5.2)

    assert_equal(2, harness.calls.visual, "built at once, inside the retry cooldown")
    assert_equal(1, geometry.count, "only the new section's triangle")
    assert_equal(300, geometry.ax[1], "the new section's vertex")
    assert_equal(0, harness.mod:get_navmesh_nearby_buckets(0, 0, 16, {}), "no old cells left")
    assert_true(geometry.revision > revision, "consumers see the change")

    harness.draw(6)
    assert_equal(2, harness.calls.visual, "the new section is not built again")

    harness.mod:clear_navmesh_geometry()
    assert_equal(1, harness.draw(7).count, "a cleared layer builds the current section again")
    assert_equal(3, harness.calls.visual)
end)

test("nothing is built while an Expedition section's navmesh is missing, baking or not in the database", function()
    local nav_world = new_nav_world()
    local harness = new_harness({
        nav_world = nav_world,
        dynamic_mesh_spawning = true,
        spawner = { _nav_data_created = "section 1" },
    })

    assert_equal(2, harness.draw(5).count)

    harness.spawner._nav_data_created = nil

    local geometry = harness.draw(6)

    assert_equal(0, geometry.count, "the removed section's floor is dropped")
    assert_equal(1, harness.calls.visual, "and its triangles are not read again")

    nav_world.tiles = { { triangle(300, 300, 9) } }
    harness.spawner._nav_data_created = "section 2"
    harness.spawner._async_navmesh_generation_job_id = 4
    assert_equal(0, harness.draw(7).count, "nothing while the next section bakes")

    harness.spawner._async_navmesh_generation_job_id = nil
    harness.alive = {}
    assert_equal(0, harness.draw(8).count, "nothing before the database has the new navmesh")
    assert_equal(1, harness.calls.visual)

    harness.alive["section 2"] = true
    geometry = harness.draw(8.1)

    assert_equal(2, harness.calls.visual, "built as soon as the game would use it")
    assert_equal(1, geometry.count)
    assert_equal(300, geometry.ax[1])
end)

test("a normal mission never reads the game mode, an unreadable level spawner builds as before", function()
    local harness = new_harness({ spawner = { _nav_data_created = "unused" } })

    harness.enter_mission()
    harness.draw(5)
    harness.draw(6)
    assert_equal(1, harness.calls.visual, "built once on entering")
    assert_equal(0, harness.calls.game_mode, "a static navmesh needs no section check")

    local without_spawner = new_harness({ dynamic_mesh_spawning = true, spawner = false })

    assert_equal(2, without_spawner.draw(5).count, "built on the first draw")
    without_spawner.draw(6)
    assert_equal(1, without_spawner.calls.visual, "and only once")
    assert_true(without_spawner.calls.game_mode > 0, "the section check ran")
end)

test("while profiling a build logs where it ran and its parts", function()
    local harness = new_harness({ profiling = true })

    harness.enter_mission()
    assert_equal(1, #harness.info, "one line per build")

    local line = harness.info[1]

    assert_contains(line, "[Radar] profile build | when=state_entry")
    assert_contains(line, "total_ms=4.00")
    assert_contains(line, "visual_ms=2.00")
    assert_contains(line, "triangles_ms=0.00")
    assert_contains(line, "buckets_ms=2.00")
    assert_contains(line, "tiles=2")
    assert_contains(line, "triangles=2")

    harness.draw(5)
    assert_equal(1, #harness.info, "a draw with nothing to build logs nothing")
end)

test("a build on a draw is logged as such", function()
    local harness = new_harness({ profiling = true, source = "auto" })

    harness.enter_mission()
    assert_equal(0, #harness.info)

    harness.draw(5)
    assert_contains(harness.info[1], "when=draw")
end)

test("nothing is logged while not profiling, and a failed build logs no parts", function()
    local harness = new_harness()

    harness.enter_mission()
    assert_equal(0, #harness.info)

    local failing = new_harness({ profiling = true, visual_failure = "engine failure" })

    failing.enter_mission()
    assert_equal(0, #failing.info)
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
