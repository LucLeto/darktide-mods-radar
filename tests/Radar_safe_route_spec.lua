local SAFE_ROUTE_PATH = "Radar/scripts/mods/Radar/compatibility/Radar_safe_route.lua"

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

local function assert_nil(actual, message)
    if actual ~= nil then
        error((message or "value is not nil") .. ": got " .. tostring(actual), 2)
    end
end

-- The icons and colours SafeRoute 1.2.0 gives its markers. Duplicated from its own SafeRoute.lua,
-- which is exactly what the classifier reads, so a spec that invented its own would prove nothing.
local SAFE_ICON = "content/ui/materials/hud/interactions/icons/location"
local WRONG_ICON = "content/ui/materials/hud/interactions/icons/attention"
local SAFE_COLOR = { 90, 230, 110 }
local WRONG_COLOR = { 235, 80, 60 }
local DOT_SIZE = 26

-- ------------------------------------------------------------------------------------------
-- Harness
-- ------------------------------------------------------------------------------------------

--- The game's `MainPathManager` class, reduced to its crossroad lookup.
-- The method is copied from main_path_manager.lua, which is exactly what the module asks, so a
-- spec that invented its own would prove nothing. It sits on the class, as in the game, so it is
-- reached through the metatable while the road picks are instance fields.
local MainPathManager = {}

MainPathManager.__index = MainPathManager

MainPathManager.is_crossroad_segment_available = function(self, crossroads_id, road_id)
    local chosen_crossroads = self._chosen_crossroads
    local is_available = chosen_crossroads and chosen_crossroads[crossroads_id] == road_id

    return is_available
end

--- Builds the game's main path manager the way the module sees it.
-- The game keeps `_chosen_crossroads` only on a mission whose main path has crossroads.
-- ?tab: chosen_crossroads road picked per crossroad id, nil for a mission without forks
local function main_path_manager(chosen_crossroads)
    return setmetatable({ _chosen_crossroads = chosen_crossroads }, MainPathManager)
end

--- Builds a main path manager from a game update that keeps its road picks under another name.
-- Its own crossroad lookup follows the new name, as the game's would.
-- ?tab: picks road picked per crossroad id, nil for a mission without forks
local function moved_main_path_manager(picks)
    return {
        _road_picks = picks,
        is_crossroad_segment_available = function(self, crossroads_id, road_id)
            local road_picks = self._road_picks

            return road_picks and road_picks[crossroads_id] == road_id
        end,
    }
end

--- Builds a fake shared environment with the module installed and a world marker list to feed it.
-- Only the helpers the module actually reaches are stubbed; everything else would be dead weight.
-- ?tab: options `settings`, `safe_route_mod` (false for none), `gameplay_t` and `main_path`
-- (false for none; a mission with two forks, like Spillway, by default)
local function new_harness(options)
    options = options or {}

    local settings = options.settings or {}
    local world_markers = nil
    local tracked_points = {}
    local mod = {}
    local clock = { t = options.gameplay_t or 0 }
    local state_managers = {}

    if options.main_path ~= false then
        state_managers.main_path = options.main_path or main_path_manager({ [1] = 2, [2] = 1 })
    end

    function mod:get(setting_id)
        return settings[setting_id]
    end

    function mod:set(setting_id, value)
        settings[setting_id] = value
    end

    local env = { mod = mod, Managers = { state = state_managers } }

    setmetatable(env, { __index = _G })

    env._safe_gameplay_time = function()
        return clock.t
    end

    env._copy_vector3 = function(vec)
        if type(vec) ~= "table" then
            return nil
        end

        if type(vec.x) ~= "number" or type(vec.y) ~= "number" or type(vec.z) ~= "number" then
            return nil
        end

        return { x = vec.x, y = vec.y, z = vec.z }
    end

    env._safe_world_markers_list = function()
        return world_markers
    end

    -- Both SafeRoute kinds are on unless the test says otherwise.
    env._kind_enabled = function(kind)
        local mode = settings["show_" .. tostring(kind)]

        return mode ~= "off"
    end

    env._track_point = function(id, kind, position, source, meta)
        tracked_points[id] = {
            kind = kind,
            position = position,
            source = source,
            meta = meta,
        }
    end

    local chunk = assert(loadfile(SAFE_ROUTE_PATH))

    chunk()(env)

    local harness = {
        env = env,
        mod = mod,
        settings = settings,
        tracked_points = tracked_points,
        clock = clock,
        state_managers = state_managers,
    }

    --- Installs SafeRoute under its DMF name, or removes it with `false`.
    function harness.set_safe_route_mod(safe_route_mod)
        if safe_route_mod == false then
            _G.get_mod = function()
                return nil
            end

            return
        end

        _G.get_mod = function(name)
            if name == "SafeRoute" then
                return safe_route_mod or {}
            end

            return nil
        end
    end

    -- SafeRoute is installed and switched on unless a test replaces it.
    harness.set_safe_route_mod(options.safe_route_mod)

    --- Replaces the world marker list the HUD would hand back.
    function harness.set_markers(markers)
        world_markers = markers
    end

    --- Runs one droppable scan, after the wipe the real update loop does first.
    function harness.scan()
        for id in pairs(tracked_points) do
            tracked_points[id] = nil
        end

        env._scan_safe_route_markers()
    end

    --- Returns how many points of a kind were tracked.
    function harness.count_of_kind(kind)
        local count = 0

        for _, point in pairs(tracked_points) do
            if point.kind == kind then
                count = count + 1
            end
        end

        return count
    end

    return harness
end

--- Builds a position marker the way `HudElementWorldMarkers` stores one, `Vector3Box` and all.
local function position_marker(id, position, data, marker_type)
    return {
        id = id,
        type = marker_type or "SafeRoute_marker",
        data = data,
        world_position = {
            unbox = function()
                return { x = position.x, y = position.y, z = position.z }
            end,
        },
    }
end

--- The data SafeRoute 1.2.0 gives a SAFE ROUTE marker, label and range included.
local function safe_data(label)
    return { color = SAFE_COLOR, icon = SAFE_ICON, label = label or "SAFE ROUTE", max_distance = 60 }
end

--- The data SafeRoute 1.2.0 gives a WRONG WAY marker, label and range included.
local function wrong_data(label)
    return { color = WRONG_COLOR, icon = WRONG_ICON, label = label or "WRONG WAY", max_distance = 60 }
end

--- The data SafeRoute 1.2.0 gives a guide dot; no label, a small size and a line of sight check.
local function dot_data(icon, color)
    return { color = color, icon = icon, size = DOT_SIZE, check_line_of_sight = true, max_distance = 60 }
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

-- ------------------------------------------------------------------------------------------
-- Classification
-- ------------------------------------------------------------------------------------------

test("the main SAFE ROUTE and WRONG WAY markers are imported as their own kinds", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(1, { x = 10, y = 20, z = -3 }, safe_data()),
        position_marker(2, { x = 55, y = 60, z = 4 }, wrong_data()),
    })
    harness.scan()

    local safe = harness.tracked_points["safe_route:1"]
    local wrong = harness.tracked_points["safe_route:2"]

    assert_equal("saferoute_safe", safe and safe.kind, "the SAFE ROUTE marker has the wrong kind")
    assert_equal("saferoute_wrong", wrong and wrong.kind, "the WRONG WAY marker has the wrong kind")
    assert_equal("safe_route", safe.source, "the SAFE ROUTE marker has the wrong scan source")
    assert_equal("safe_route", wrong.source, "the WRONG WAY marker has the wrong scan source")
    assert_near(10, safe.position.x, "the SAFE ROUTE marker is not at its world position")
    assert_near(20, safe.position.y, "the SAFE ROUTE marker is not at its world position")
    assert_near(-3, safe.position.z, "the SAFE ROUTE marker is not at its world position")
    assert_near(55, wrong.position.x, "the WRONG WAY marker is not at its world position")
    assert_near(4, wrong.position.z, "the WRONG WAY marker is not at its world position")
end)

test("every fork's markers are imported together", function()
    local harness = new_harness()

    -- Spillway as SafeRoute 1.2.0 marks it; two forks, five roads.
    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()),
        position_marker(2, { x = 1, y = 0, z = 0 }, wrong_data()),
        position_marker(3, { x = 2, y = 0, z = 0 }, safe_data()),
        position_marker(4, { x = 3, y = 0, z = 0 }, wrong_data()),
        position_marker(5, { x = 4, y = 0, z = 0 }, wrong_data()),
    })
    harness.scan()

    assert_equal(2, harness.count_of_kind("saferoute_safe"), "a SAFE ROUTE marker was lost")
    assert_equal(3, harness.count_of_kind("saferoute_wrong"), "a WRONG WAY marker was lost")
end)

-- SafeRoute localizes its labels, so a translated or unexpected label must not change the result.
test("the label never decides the kind", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, safe_data("SÄKER VÄG")),
        position_marker(2, { x = 1, y = 1, z = 1 }, wrong_data("FEL VÄG")),
        position_marker(3, { x = 2, y = 2, z = 2 }, safe_data("WRONG WAY")),
    })
    harness.scan()

    assert_equal(2, harness.count_of_kind("saferoute_safe"), "a localized or mismatched label changed the kind")
    assert_equal(1, harness.count_of_kind("saferoute_wrong"), "a localized label changed the kind")
end)

test("an explicit SafeRoute role wins over the icon", function()
    local harness = new_harness()
    local data = safe_data()

    data.safe_route_role = "wrong"
    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, data),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("saferoute_wrong"), "`safe_route_role` did not win over the icon")
    assert_equal(0, harness.count_of_kind("saferoute_safe"), "`safe_route_role` did not win over the icon")
end)

test("an explicit role alone classifies a marker without a known icon", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, { safe_route_role = "safe", icon = "some/other/icon" }),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("saferoute_safe"), "the explicit role was not read")
end)

test("an unknown explicit role falls back to the icon", function()
    local harness = new_harness()
    local data = wrong_data()

    data.safe_route_role = "detour"
    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, data),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("saferoute_wrong"), "an unknown role stopped the icon fallback")
end)

test("a SafeRoute marker with an unknown icon is left alone", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, { icon = "some/other/icon", label = "SAFE ROUTE" }),
    })
    harness.scan()

    assert_nil(next(harness.tracked_points), "an unrecognised SafeRoute marker was tracked anyway")
end)

test("markers of another type are ignored, even with SafeRoute's icons", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, safe_data(), "interaction"),
        position_marker(2, { x = 1, y = 1, z = 1 }, wrong_data(), "respawn_rewind"),
    })
    harness.scan()

    assert_nil(next(harness.tracked_points), "a marker of another type was imported")
end)

-- ------------------------------------------------------------------------------------------
-- Guide dots
-- ------------------------------------------------------------------------------------------

-- The dots stand about every 2 m along SafeRoute's recorded routes; importing them would fill the
-- marker limit around every fork.
test("guide dots are not imported", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, dot_data(SAFE_ICON, SAFE_COLOR)),
        position_marker(2, { x = 2, y = 0, z = 0 }, dot_data(SAFE_ICON, SAFE_COLOR)),
        position_marker(3, { x = 0, y = 2, z = 0 }, dot_data(WRONG_ICON, WRONG_COLOR)),
        position_marker(4, { x = 8, y = 0, z = 0 }, safe_data()),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("saferoute_safe"), "a green guide dot was imported")
    assert_equal(0, harness.count_of_kind("saferoute_wrong"), "a red guide dot was imported")
end)

test("an explicit guide flag wins over the line of sight fallback", function()
    local harness = new_harness()
    local explicit_dot = safe_data()
    local explicit_main = dot_data(WRONG_ICON, WRONG_COLOR)

    explicit_dot.safe_route_guide = true
    explicit_main.safe_route_guide = false
    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, explicit_dot),
        position_marker(2, { x = 1, y = 1, z = 1 }, explicit_main),
    })
    harness.scan()

    assert_equal(0, harness.count_of_kind("saferoute_safe"), "a marker flagged as a guide dot was imported")
    assert_equal(1, harness.count_of_kind("saferoute_wrong"), "a marker flagged as a main marker was dropped")
end)

-- ------------------------------------------------------------------------------------------
-- Position extraction
-- ------------------------------------------------------------------------------------------

-- Position markers hold a `Vector3Box`, and an engine vector must never outlive the frame it
-- was unboxed in.
test("a marker's vector is copied rather than kept", function()
    local harness = new_harness()
    local unboxed = nil
    local marker = position_marker(1, { x = 7, y = 8, z = 9 }, safe_data())
    local inner_unbox = marker.world_position.unbox

    marker.world_position.unbox = function(self)
        unboxed = inner_unbox(self)

        return unboxed
    end

    harness.set_markers({ marker })
    harness.scan()

    local safe = harness.tracked_points["safe_route:1"]

    assert_equal(false, safe.position == unboxed, "the unboxed engine vector was stored directly")
    assert_near(7, safe.position.x, "the copied position is wrong")
    assert_near(8, safe.position.y, "the copied position is wrong")
    assert_near(9, safe.position.z, "the copied position is wrong")
end)

test("malformed markers never stop the scan", function()
    local harness = new_harness()
    local no_world_position = position_marker(3, { x = 0, y = 0, z = 0 }, safe_data())
    local no_unbox = position_marker(4, { x = 0, y = 0, z = 0 }, safe_data())
    local raising = position_marker(5, { x = 0, y = 0, z = 0 }, wrong_data())
    local garbage = position_marker(6, { x = 0, y = 0, z = 0 }, wrong_data())

    no_world_position.world_position = nil
    no_unbox.world_position = {}
    raising.world_position = {
        unbox = function()
            error("the marker is being torn down")
        end,
    }
    garbage.world_position = {
        unbox = function()
            return "not a vector"
        end,
    }

    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, nil),
        position_marker(2, { x = 0, y = 0, z = 0 }, "SAFE ROUTE"),
        no_world_position,
        no_unbox,
        raising,
        garbage,
        position_marker(7, { x = 0, y = 0, z = 0 }, {}),
        position_marker(8, { x = 0, y = 0, z = 0 }, { icon = 42 }),
        position_marker(9, { x = 5, y = 5, z = 5 }, safe_data()),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("saferoute_safe"), "the good marker after the malformed ones was lost")
    assert_equal(0, harness.count_of_kind("saferoute_wrong"), "a marker without a readable position was tracked")
end)

test("a missing world marker list is not an error", function()
    local harness = new_harness()

    harness.set_markers(nil)
    harness.scan()

    assert_nil(next(harness.tracked_points), "points appeared without a world marker list")
end)

-- ------------------------------------------------------------------------------------------
-- Settings
-- ------------------------------------------------------------------------------------------

test("a kind that is switched off is not tracked while the other still is", function()
    local harness = new_harness({ settings = { show_saferoute_wrong = "off" } })

    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()),
        position_marker(2, { x = 1, y = 1, z = 1 }, wrong_data()),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("saferoute_safe"), "the SAFE ROUTE marker was lost")
    assert_equal(0, harness.count_of_kind("saferoute_wrong"), "the WRONG WAY marker was tracked while switched off")
end)

test("no world marker list is requested while both kinds are off", function()
    local harness = new_harness({ settings = { show_saferoute_safe = "off", show_saferoute_wrong = "off" } })
    local requested = false

    harness.env._safe_world_markers_list = function()
        requested = true

        return {}
    end

    harness.scan()

    assert_equal(false, requested, "the world marker list was requested with both SafeRoute kinds off")
end)

-- ------------------------------------------------------------------------------------------
-- Mission gate
-- ------------------------------------------------------------------------------------------

--- Counts the world marker list requests of a harness, still handing back the markers.
local function count_list_requests(harness, markers)
    local counter = { requests = 0 }

    harness.env._safe_world_markers_list = function()
        counter.requests = counter.requests + 1

        return markers
    end

    return counter
end

test("no world marker list is requested on a mission without branching roads", function()
    local harness = new_harness({ main_path = main_path_manager(nil) })
    local counter = count_list_requests(harness, { position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()) })

    harness.scan()
    harness.scan()

    assert_equal(0, counter.requests, "the world marker list was requested on a mission without forks")
    assert_nil(next(harness.tracked_points), "a marker was imported on a mission without forks")
end)

test("an empty crossroad table is a mission without branching roads", function()
    local harness = new_harness({ main_path = main_path_manager({}) })
    local counter = count_list_requests(harness, {})

    harness.scan()

    assert_equal(0, counter.requests, "an empty crossroad table was taken for a mission with forks")
end)

-- A scan can run before the mission has built its main path manager. That must not decide the
-- answer for the whole mission.
test("nothing is decided before the mission's main path exists", function()
    local harness = new_harness({ main_path = false })
    local counter = count_list_requests(harness, { position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()) })

    harness.scan()
    assert_equal(0, counter.requests, "the world marker list was requested without a main path")

    harness.state_managers.main_path = main_path_manager({ [1] = 1 })
    harness.scan()

    assert_equal(1, counter.requests, "the missing main path was cached as a mission without forks")
    assert_equal(1, harness.count_of_kind("saferoute_safe"), "the marker was not imported once the main path existed")
end)

test("the branching road check is read once per mission", function()
    local main_path = main_path_manager({ [1] = 2 })
    local harness = new_harness({ main_path = main_path })

    harness.set_markers({ position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()) })
    harness.scan()
    assert_equal(1, harness.count_of_kind("saferoute_safe"), "the marker was not imported on a mission with forks")

    -- The same manager is not read again, so a change to it goes unseen until the next mission.
    main_path._chosen_crossroads = nil
    harness.scan()
    assert_equal(1, harness.count_of_kind("saferoute_safe"), "the check was read again for the same mission")

    -- The next mission builds a new manager, which is read afresh.
    harness.state_managers.main_path = main_path_manager(nil)
    harness.scan()
    assert_nil(next(harness.tracked_points), "the answer of the previous mission was kept for a new one")
end)

-- A game update that keeps the road picks under another name must not silently take the markers
-- off the radar while SafeRoute, which asks the game's own lookup, still places them.
test("road picks the game keeps under another name still count as forks", function()
    local harness = new_harness({ main_path = moved_main_path_manager({ [1] = 2 }) })

    harness.set_markers({ position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()) })
    harness.scan()

    assert_equal(1, harness.count_of_kind("saferoute_safe"), "moved road picks were read as a mission without forks")
end)

test("a mission without forks is still told apart after the picks moved", function()
    local harness = new_harness({ main_path = moved_main_path_manager(nil) })
    local counter = count_list_requests(harness, {})

    harness.scan()

    assert_equal(0, counter.requests, "a mission without forks was scanned once the picks moved")
end)

test("a crossroad field of an unknown type keeps the scan running", function()
    local harness = new_harness({ main_path = main_path_manager(true) })

    harness.set_markers({ position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()) })
    harness.scan()

    assert_equal(1, harness.count_of_kind("saferoute_safe"), "an unrecognised crossroad field stopped the scan")
end)

test("a manager without the crossroad lookup keeps the scan running", function()
    local harness = new_harness({ main_path = {} })

    harness.set_markers({ position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()) })
    harness.scan()

    assert_equal(1, harness.count_of_kind("saferoute_safe"), "a manager without the crossroad lookup stopped the scan")
end)

test("a crossroad lookup that raises keeps the scan running", function()
    local harness = new_harness({
        main_path = {
            is_crossroad_segment_available = function()
                error("the crossroad lookup changed its arguments")
            end,
        },
    })

    harness.set_markers({ position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()) })
    harness.scan()

    assert_equal(1, harness.count_of_kind("saferoute_safe"), "a raising crossroad lookup stopped the scan")
end)

test("the mission reset drops the branching road answer", function()
    local main_path = main_path_manager({ [1] = 2 })
    local harness = new_harness({ main_path = main_path })

    harness.set_markers({ position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()) })
    harness.scan()
    assert_equal(1, harness.count_of_kind("saferoute_safe"), "the marker was not imported on a mission with forks")

    main_path._chosen_crossroads = nil
    harness.env._reset_safe_route_state()
    harness.scan()

    assert_nil(next(harness.tracked_points), "the branching road answer survived the mission reset")
end)

-- ------------------------------------------------------------------------------------------
-- Removal, availability and the mission reset
-- ------------------------------------------------------------------------------------------

test("a marker SafeRoute removes stops being tracked", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()),
        position_marker(2, { x = 1, y = 1, z = 1 }, wrong_data()),
    })
    harness.scan()
    assert_equal(1, harness.count_of_kind("saferoute_safe"), "the SAFE ROUTE marker was not tracked")

    -- SafeRoute removed its markers, for example on a settings change; they leave the HUD's list.
    harness.set_markers({})
    harness.scan()

    assert_nil(next(harness.tracked_points), "a removed marker is still on the radar")
end)

test("nothing is tracked or requested while SafeRoute is not installed", function()
    local harness = new_harness({ safe_route_mod = false })
    local requested = false

    harness.env._safe_world_markers_list = function()
        requested = true

        return { position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()) }
    end

    harness.scan()

    assert_nil(next(harness.tracked_points), "markers were imported without SafeRoute")
    assert_equal(false, requested, "the world marker list was requested without SafeRoute")
end)

test("nothing is tracked while SafeRoute is switched off", function()
    local harness = new_harness({
        safe_route_mod = {
            is_enabled = function()
                return false
            end,
        },
    })

    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()),
    })
    harness.scan()

    assert_nil(next(harness.tracked_points), "markers were imported from a disabled SafeRoute")
end)

test("a SafeRoute that becomes available is picked up after the retry interval", function()
    local harness = new_harness({ safe_route_mod = false, gameplay_t = 100 })

    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()),
    })
    harness.scan()
    assert_nil(next(harness.tracked_points), "markers were imported without SafeRoute")

    harness.set_safe_route_mod()
    harness.clock.t = 102
    harness.scan()
    assert_nil(next(harness.tracked_points), "SafeRoute was looked up again before the retry interval")

    harness.clock.t = 105
    harness.scan()
    assert_equal(1, harness.count_of_kind("saferoute_safe"), "SafeRoute was not picked up after the retry interval")
end)

test("the mission reset drops the resolved mod so it is looked up again", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(1, { x = 0, y = 0, z = 0 }, safe_data()),
    })
    harness.scan()
    assert_equal(1, harness.count_of_kind("saferoute_safe"), "the SAFE ROUTE marker was not tracked")

    harness.env._reset_safe_route_state()
    assert_nil(harness.mod._safe_route_mod, "the resolved mod survived the mission reset")
    assert_equal(0, harness.mod._safe_route_next_resolve_t, "the retry time survived the mission reset")

    -- SafeRoute was switched off in the menu between missions.
    harness.set_safe_route_mod(false)
    harness.scan()

    assert_nil(next(harness.tracked_points), "the resolved mod survived the mission reset")
end)

-- ------------------------------------------------------------------------------------------
-- Runner
-- ------------------------------------------------------------------------------------------

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
