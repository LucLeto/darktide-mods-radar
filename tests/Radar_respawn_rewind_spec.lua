local RESPAWN_REWIND_PATH = "Radar/scripts/mods/Radar/compatibility/Radar_respawn_rewind.lua"

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

-- The colours Respawn Rewind gives each of its markers. Duplicated from its own marker module,
-- which is exactly what the classifier reads, so a spec that invented its own would prove nothing.
local ACTIVE_COLOR = { 255, 120, 200, 255 }
local RUNBACK_COLOR = { 255, 120, 220, 120 }
local PRACTICE_BEACON_COLOR = { 255, 130, 170, 200 }
local PRACTICE_LINE_COLOR = { 255, 175, 175, 175 }

-- ------------------------------------------------------------------------------------------
-- Harness
-- ------------------------------------------------------------------------------------------

--- Builds a fake shared environment with the module installed and a world marker list to feed it.
-- Only the helpers the module actually reaches are stubbed; everything else would be dead weight.
-- ?tab: options `settings`, `respawn_rewind_mod` (false for none), `overview` and `gameplay_t`
local function new_harness(options)
    options = options or {}

    local settings = options.settings or {}
    local world_markers = nil
    local tracked_points = {}
    local unit_positions = {}
    local mod = {}

    function mod:get(setting_id)
        return settings[setting_id]
    end

    function mod:set(setting_id, value)
        settings[setting_id] = value
    end

    function mod:is_overview_mode_active()
        return options.overview == true
    end

    local env = { mod = mod }

    setmetatable(env, { __index = _G })

    env._safe_gameplay_time = function()
        return options.gameplay_t or 0
    end

    env._safe_unit_position = function(unit)
        local position = unit and unit_positions[unit] or nil

        if position == nil then
            return nil
        end

        return { x = position.x, y = position.y, z = position.z }
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

    -- Every respawn kind is on unless the test says otherwise, so a test about classification
    -- never has to set four settings first.
    env._kind_enabled = function(kind)
        local enabled = settings["enabled_" .. tostring(kind)]

        return enabled ~= false
    end

    env._track_point = function(id, kind, position, source, meta)
        tracked_points[id] = {
            kind = kind,
            position = position,
            source = source,
            meta = meta,
        }
    end

    local chunk = assert(loadfile(RESPAWN_REWIND_PATH))

    chunk()(env)

    -- Respawn Rewind is installed and switched on unless a test replaces it.
    if options.respawn_rewind_mod ~= false then
        _G.get_mod = function(name)
            if name == "RespawnRewind" then
                return options.respawn_rewind_mod or {}
            end

            return nil
        end
    else
        _G.get_mod = function()
            return nil
        end
    end

    return {
        env = env,
        mod = mod,
        settings = settings,
        tracked_points = tracked_points,

        --- Places a unit at a position and returns the unit handle.
        place_unit = function(position)
            local unit = {}

            unit_positions[unit] = position

            return unit
        end,

        --- Replaces the world marker list the HUD would hand back.
        set_markers = function(markers)
            world_markers = markers
        end,

        --- Runs one droppable scan, after the wipe the real update loop does first.
        scan = function()
            for id in pairs(tracked_points) do
                tracked_points[id] = nil
            end

            env._scan_respawn_rewind_markers()
        end,

        --- Returns the single tracked point of a kind, or nil, failing when there are several.
        point_of_kind = function(kind)
            local found = nil

            for id, point in pairs(tracked_points) do
                if point.kind == kind then
                    if found ~= nil then
                        error("more than one " .. kind .. " point was tracked", 2)
                    end

                    found = point
                    found.id = id
                end
            end

            return found
        end,

        --- Returns how many points of a kind were tracked.
        count_of_kind = function(kind)
            local count = 0

            for _, point in pairs(tracked_points) do
                if point.kind == kind then
                    count = count + 1
                end
            end

            return count
        end,
    }
end

--- Builds a position marker the way `HudElementWorldMarkers` stores one, `Vector3Box` and all.
local function position_marker(id, position, data)
    return {
        id = id,
        type = "respawn_rewind",
        data = data,
        world_position = {
            unbox = function()
                return { x = position.x, y = position.y, z = position.z }
            end,
        },
    }
end

--- Builds a unit marker the way `HudElementWorldMarkers` stores one.
local function unit_marker(id, unit, data)
    return {
        id = id,
        type = "respawn_rewind",
        unit = unit,
        data = data,
    }
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

-- ------------------------------------------------------------------------------------------
-- Classification
-- ------------------------------------------------------------------------------------------

test("the live respawn and run-back markers are classified and positioned", function()
    local harness = new_harness()
    local beacon = harness.place_unit({ x = 10, y = 20, z = -3 })

    harness.set_markers({
        unit_marker(1, beacon, { text = "Respawn | 41m", color = ACTIVE_COLOR }),
        position_marker(2, { x = 55, y = 60, z = 4 }, { text = "Run back | 29m", color = RUNBACK_COLOR }),
    })
    harness.scan()

    local active = harness.point_of_kind("respawn_active")
    local runback = harness.point_of_kind("respawn_runback")

    assert_equal("respawn_rewind", active.source, "the active respawn has the wrong scan source")
    assert_near(10, active.position.x, "the active respawn is not on its beacon")
    assert_near(-3, active.position.z, "the active respawn is not on its beacon")
    assert_near(55, runback.position.x, "the run-back line is not at its world position")
    assert_near(60, runback.position.y, "the run-back line is not at its world position")
    assert_near(4, runback.position.z, "the run-back line is not at its world position")
end)

test("the practice set is classified apart from the live markers", function()
    local harness = new_harness()
    local beacon = harness.place_unit({ x = 1, y = 2, z = 3 })

    harness.set_markers({
        unit_marker(7, beacon, { text = "Respawn 3", color = PRACTICE_BEACON_COLOR }),
        position_marker(8, { x = 4, y = 5, z = 6 }, { text = "3 ends", color = PRACTICE_LINE_COLOR }),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("respawn_practice_beacon"), "the practice beacon was not tracked")
    assert_equal(1, harness.count_of_kind("respawn_practice_line"), "the practice line was not tracked")
    assert_equal(0, harness.count_of_kind("respawn_active"), "a practice beacon was drawn as the active respawn")
    assert_equal(0, harness.count_of_kind("respawn_runback"), "a practice line was drawn as the run-back line")
end)

-- With Respawn Rewind's practice numbering off, a practice beacon's label is exactly `Respawn`,
-- which is also the active marker's label once its distance text is off. Nothing but the colour
-- separates them, and reading the set as twenty active respawns would push every real marker off
-- the radar, since the active respawn outranks the marker limit.
test("a numberless practice beacon is not mistaken for the active respawn", function()
    local harness = new_harness()
    local beacon = harness.place_unit({ x = 0, y = 0, z = 0 })

    harness.set_markers({
        unit_marker(11, beacon, { text = "Respawn", color = PRACTICE_BEACON_COLOR }),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("respawn_practice_beacon"), "the practice beacon was not tracked")
    assert_equal(0, harness.count_of_kind("respawn_active"), "the practice beacon was drawn as the active respawn")
end)

test("a numberless practice line is classified from its label", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(12, { x = 1, y = 1, z = 1 }, { text = "Line" }),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("respawn_practice_line"), "the `Line` label was not recognised")
end)

-- Respawn Rewind falls back to `Hold back` where no main path line exists to be in front of.
test("the hold-back fallback is still a run-back marker", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(13, { x = 2, y = 2, z = 2 }, { text = "Hold back | 41m" }),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("respawn_runback"), "the `Hold back` label was not recognised")
end)

test("the labels alone classify every marker once the colours are gone", function()
    local harness = new_harness()
    local beacon = harness.place_unit({ x = 0, y = 0, z = 0 })

    harness.set_markers({
        unit_marker(21, beacon, { text = "Respawn | 12m" }),
        position_marker(22, { x = 1, y = 1, z = 1 }, { text = "Stay behind | -12m" }),
        unit_marker(23, harness.place_unit({ x = 2, y = 2, z = 2 }), { text = "Respawn 2" }),
        position_marker(24, { x = 3, y = 3, z = 3 }, { text = "2 ends" }),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("respawn_active"), "the active respawn label was not recognised")
    assert_equal(1, harness.count_of_kind("respawn_runback"), "the stay-behind label was not recognised")
    assert_equal(1, harness.count_of_kind("respawn_practice_beacon"), "the numbered respawn label was not recognised")
    assert_equal(1, harness.count_of_kind("respawn_practice_line"), "the ends label was not recognised")
end)

test("an explicit data role wins over the colour and the label", function()
    local harness = new_harness()
    local beacon = harness.place_unit({ x = 0, y = 0, z = 0 })

    harness.set_markers({
        unit_marker(31, beacon, { role = "practice_beacon", text = "Respawn | 5m", color = ACTIVE_COLOR }),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("respawn_practice_beacon"), "`data.role` did not win over the colour")
    assert_equal(0, harness.count_of_kind("respawn_active"), "`data.role` did not win over the colour")
end)

test("an unknown role, colour and label is left alone", function()
    local harness = new_harness()

    harness.set_markers({
        unit_marker(41, harness.place_unit({ x = 0, y = 0, z = 0 }), { text = "Something else" }),
        position_marker(42, { x = 1, y = 1, z = 1 }, { text = "Something else", color = { 255, 1, 2, 3 } }),
        unit_marker(43, harness.place_unit({ x = 2, y = 2, z = 2 }), { role = "not_a_role" }),
    })
    harness.scan()

    assert_nil(next(harness.tracked_points), "an unrecognised marker was tracked anyway")
end)

-- A role can never swap which of the two kinds of world marker it is added as, so a colour that
-- disagrees with the shape is a colour Respawn Rewind has reused, not a role.
test("a colour that disagrees with the marker shape is not trusted", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(51, { x = 0, y = 0, z = 0 }, { color = ACTIVE_COLOR }),
    })
    harness.scan()

    assert_nil(next(harness.tracked_points), "a position marker was read as the active respawn")
end)

test("markers of another type are ignored", function()
    local harness = new_harness()
    local marker = unit_marker(61, harness.place_unit({ x = 0, y = 0, z = 0 }),
        { text = "Respawn", color = ACTIVE_COLOR })

    marker.type = "interaction"
    harness.set_markers({ marker })
    harness.scan()

    assert_nil(next(harness.tracked_points), "a marker of another type was imported")
end)

-- ------------------------------------------------------------------------------------------
-- Position extraction
-- ------------------------------------------------------------------------------------------

-- Position markers hold a `Vector3Box`, and an engine vector must never outlive the frame it
-- was unboxed in.
test("a position marker's vector is copied rather than kept", function()
    local harness = new_harness()
    local unboxed = nil
    local marker = position_marker(71, { x = 7, y = 8, z = 9 }, { text = "Run back | 3m" })
    local inner_unbox = marker.world_position.unbox

    marker.world_position.unbox = function(self)
        unboxed = inner_unbox(self)

        return unboxed
    end

    harness.set_markers({ marker })
    harness.scan()

    local runback = harness.point_of_kind("respawn_runback")

    assert_equal(false, runback.position == unboxed, "the unboxed engine vector was stored directly")
    assert_near(7, runback.position.x, "the copied position is wrong")
    assert_near(9, runback.position.z, "the copied position is wrong")
end)

test("a marker whose position cannot be read is skipped", function()
    local harness = new_harness()
    local no_unbox = position_marker(81, { x = 0, y = 0, z = 0 }, { text = "Run back" })
    local raising = position_marker(82, { x = 0, y = 0, z = 0 }, { text = "Stay behind" })

    no_unbox.world_position = {}
    raising.world_position = {
        unbox = function()
            error("the marker is being torn down")
        end,
    }

    harness.set_markers({
        no_unbox,
        raising,
        -- A unit marker whose unit has no position at all.
        unit_marker(83, {}, { text = "Respawn", color = ACTIVE_COLOR }),
    })
    harness.scan()

    assert_nil(next(harness.tracked_points), "a marker without a readable position was tracked")
end)

test("malformed marker data never stops the scan", function()
    local harness = new_harness()
    local beacon = harness.place_unit({ x = 5, y = 5, z = 5 })
    local no_data = unit_marker(91, harness.place_unit({ x = 0, y = 0, z = 0 }), nil)
    local bad_colour = position_marker(92, { x = 1, y = 1, z = 1 }, { color = "green" })

    harness.set_markers({
        no_data,
        bad_colour,
        -- A marker whose data table carries neither a role, a colour nor a label.
        position_marker(93, { x = 2, y = 2, z = 2 }, {}),
        unit_marker(94, beacon, { text = "Respawn | 1m", color = ACTIVE_COLOR }),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("respawn_active"), "the good marker after the malformed ones was lost")
end)

-- ------------------------------------------------------------------------------------------
-- Run-back offset
-- ------------------------------------------------------------------------------------------

-- The run-back number is the team's offset from the threshold, not anybody's distance to the
-- marker, so it is kept apart from every Radar distance.
test("the run-back offset and status are taken from the label", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(101, { x = 0, y = 0, z = 0 }, { text = "Run back | 29m" }),
    })
    harness.scan()

    local meta = harness.point_of_kind("respawn_runback").meta

    assert_equal("run_back", meta.respawn_status, "the run-back status is wrong")
    assert_equal("29m", meta.respawn_offset_text, "the run-back offset is wrong")
    assert_equal("Run back | 29m", meta.respawn_source_text, "the original label was not preserved")
end)

test("a negative stay-behind offset keeps its sign", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(102, { x = 0, y = 0, z = 0 }, { text = "Stay behind | -12m" }),
    })
    harness.scan()

    local meta = harness.point_of_kind("respawn_runback").meta

    assert_equal("stay_behind", meta.respawn_status, "the stay-behind status is wrong")
    assert_equal("-12m", meta.respawn_offset_text, "the stay-behind offset lost its sign")
end)

-- `Hold back` is the fallback where no offset exists, and its number is a plain distance to the
-- marker. Taking it as an offset would put a distance where the display promises an offset.
test("the hold-back fallback contributes no offset", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(103, { x = 0, y = 0, z = 0 }, { text = "Hold back | 41m" }),
    })
    harness.scan()

    local meta = harness.point_of_kind("respawn_runback").meta

    assert_equal("hold_back", meta.respawn_status, "the hold-back status is wrong")
    assert_nil(meta.respawn_offset_text, "a plain distance was taken as the team's offset")
end)

test("a run-back label without a number has a status but no offset", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(104, { x = 0, y = 0, z = 0 }, { text = "Run back" }),
    })
    harness.scan()

    local meta = harness.point_of_kind("respawn_runback").meta

    assert_equal("run_back", meta.respawn_status, "the run-back status is wrong")
    assert_nil(meta.respawn_offset_text, "an offset was invented for a label that has none")
end)

-- The meta table is reused per point id, so a stale offset from an earlier tick must not survive
-- into a tick whose label no longer carries one.
test("a stale offset does not survive into the next scan", function()
    local harness = new_harness()

    harness.set_markers({
        position_marker(105, { x = 0, y = 0, z = 0 }, { text = "Run back | 29m" }),
    })
    harness.scan()
    assert_equal("29m", harness.point_of_kind("respawn_runback").meta.respawn_offset_text,
        "the first offset was not read")

    harness.set_markers({
        position_marker(105, { x = 0, y = 0, z = 0 }, { text = "Hold back | 41m" }),
    })
    harness.scan()

    assert_nil(harness.point_of_kind("respawn_runback").meta.respawn_offset_text,
        "the offset of the previous scan was left on the reused meta table")
end)

-- ------------------------------------------------------------------------------------------
-- Removal and availability
-- ------------------------------------------------------------------------------------------

test("a marker Respawn Rewind removes stops being tracked", function()
    local harness = new_harness()
    local beacon = harness.place_unit({ x = 0, y = 0, z = 0 })

    harness.set_markers({
        unit_marker(111, beacon, { text = "Respawn", color = ACTIVE_COLOR }),
        position_marker(112, { x = 1, y = 1, z = 1 }, { text = "Run back | 9m" }),
    })
    harness.scan()
    assert_equal(1, harness.count_of_kind("respawn_active"), "the active respawn was not tracked")

    -- Respawn Rewind removed both markers; its entries leave the HUD's list.
    harness.set_markers({})
    harness.scan()

    assert_nil(next(harness.tracked_points), "a removed marker is still on the radar")
end)

test("nothing is tracked while Respawn Rewind is not installed", function()
    local harness = new_harness({ respawn_rewind_mod = false })

    harness.set_markers({
        unit_marker(121, harness.place_unit({ x = 0, y = 0, z = 0 }), { text = "Respawn", color = ACTIVE_COLOR }),
    })
    harness.scan()

    assert_nil(next(harness.tracked_points), "markers were imported without Respawn Rewind")
end)

test("nothing is tracked while Respawn Rewind is switched off", function()
    local harness = new_harness({
        respawn_rewind_mod = {
            is_enabled = function()
                return false
            end,
        },
    })

    harness.set_markers({
        unit_marker(131, harness.place_unit({ x = 0, y = 0, z = 0 }), { text = "Respawn", color = ACTIVE_COLOR }),
    })
    harness.scan()

    assert_nil(next(harness.tracked_points), "markers were imported from a disabled Respawn Rewind")
end)

test("no world marker list is requested while every respawn kind is off", function()
    local harness = new_harness({
        settings = {
            enabled_respawn_active = false,
            enabled_respawn_runback = false,
            enabled_respawn_practice_beacon = false,
            enabled_respawn_practice_line = false,
        },
    })
    local requested = false

    harness.env._safe_world_markers_list = function()
        requested = true

        return {}
    end

    harness.scan()

    assert_equal(false, requested, "the world marker list was requested with every respawn kind off")
end)

test("a kind that is switched off is not tracked while the others still are", function()
    local harness = new_harness({ settings = { enabled_respawn_runback = false } })
    local beacon = harness.place_unit({ x = 0, y = 0, z = 0 })

    harness.set_markers({
        unit_marker(141, beacon, { text = "Respawn", color = ACTIVE_COLOR }),
        position_marker(142, { x = 1, y = 1, z = 1 }, { text = "Run back | 9m" }),
    })
    harness.scan()

    assert_equal(1, harness.count_of_kind("respawn_active"), "the active respawn was lost")
    assert_equal(0, harness.count_of_kind("respawn_runback"), "the run-back line was tracked while switched off")
end)

test("a missing world marker list is not an error", function()
    local harness = new_harness()

    harness.set_markers(nil)
    harness.scan()

    assert_nil(next(harness.tracked_points), "points appeared without a world marker list")
end)

-- ------------------------------------------------------------------------------------------
-- Practice markers in the overview
-- ------------------------------------------------------------------------------------------

local function practice_markers(harness)
    return {
        unit_marker(151, harness.place_unit({ x = 0, y = 0, z = 0 }),
            { text = "Respawn 1", color = PRACTICE_BEACON_COLOR }),
        position_marker(152, { x = 1, y = 1, z = 1 }, { text = "1 ends", color = PRACTICE_LINE_COLOR }),
        unit_marker(153, harness.place_unit({ x = 2, y = 2, z = 2 }),
            { text = "Respawn | 4m", color = ACTIVE_COLOR }),
    }
end

test("the practice set stays out of the normal radar when it is set to the overview", function()
    local harness = new_harness({ settings = { respawn_practice_overview_only = true }, overview = false })

    harness.set_markers(practice_markers(harness))
    harness.scan()

    assert_equal(0, harness.count_of_kind("respawn_practice_beacon"), "a practice beacon reached the normal radar")
    assert_equal(0, harness.count_of_kind("respawn_practice_line"), "a practice line reached the normal radar")
    assert_equal(1, harness.count_of_kind("respawn_active"), "the live marker was filtered with the practice set")
end)

test("the practice set appears in the overview", function()
    local harness = new_harness({ settings = { respawn_practice_overview_only = true }, overview = true })

    harness.set_markers(practice_markers(harness))
    harness.scan()

    assert_equal(1, harness.count_of_kind("respawn_practice_beacon"), "the practice beacon is missing in the overview")
    assert_equal(1, harness.count_of_kind("respawn_practice_line"), "the practice line is missing in the overview")
end)

test("the practice set appears on the normal radar once the overview rule is off", function()
    local harness = new_harness({ settings = { respawn_practice_overview_only = false }, overview = false })

    harness.set_markers(practice_markers(harness))
    harness.scan()

    assert_equal(1, harness.count_of_kind("respawn_practice_beacon"), "the practice beacon is missing")
    assert_equal(1, harness.count_of_kind("respawn_practice_line"), "the practice line is missing")
end)

-- ------------------------------------------------------------------------------------------
-- Mission reset
-- ------------------------------------------------------------------------------------------

test("the mission reset drops the resolved mod so it is looked up again", function()
    local harness = new_harness()

    harness.set_markers({
        unit_marker(161, harness.place_unit({ x = 0, y = 0, z = 0 }), { text = "Respawn", color = ACTIVE_COLOR }),
    })
    harness.scan()
    assert_equal(1, harness.count_of_kind("respawn_active"), "the active respawn was not tracked")

    harness.env._reset_respawn_rewind_state()

    -- Respawn Rewind was switched off in the menu between missions.
    _G.get_mod = function()
        return nil
    end

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
