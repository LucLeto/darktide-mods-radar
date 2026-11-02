-- Where a marker lands on the radar. Installs the real runtime helpers and tracking modules into a
-- fake shared environment and projects targets through `mod:radar_projection_forward` and
-- `mod:project_target_to_radar`, the way the HUD does once per draw and once per marker.

local HELPERS_PATH = "Radar/scripts/mods/Radar/Radar_runtime_helpers.lua"
local TRACKING_PATH = "Radar/scripts/mods/Radar/Radar_tracking.lua"

local RADIUS = 142
local RANGE = 25

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

local function assert_near(expected, actual, message)
    if type(actual) ~= "number" or math.abs(expected - actual) > 1e-9 then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
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

local function new_harness()
    local settings = {
        enable_radar = true,
        debug_mode = false,
        debug_profiling = false,
        radar_style = "square",
        overview_zoom_in_key = { "wheel_down" },
        overview_zoom_out_key = { "wheel_up" },
        radar_zoom_modifier_key = {},
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

    mod.hook = noop
    mod.hook_safe = noop
    mod.register_hud_element = noop
    mod.info = noop
    mod.error = noop
    mod.notify = noop

    local env = {
        mod = mod,
        POSITION_LOOKUP = {},
        SCAN_INTERVAL = 0.25,
        KIND_TO_SETTING = {},
        RESPAWN_MARKER_KINDS = {},
        SAFEROUTE_MARKER_KINDS = {},
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

    local harness = {
        mod = mod,
        settings = settings,
    }

    --- Projects a target the way the HUD does, from the player at `player` facing `rot`.
    function harness:project(player, rot, target, ignore_radar_range, range, radius)
        local forward_x, forward_y = mod:radar_projection_forward(rot)

        return mod:project_target_to_radar(player, forward_x, forward_y, target, radius or RADIUS, range or RANGE,
            ignore_radar_range)
    end

    return harness
end

local function point(x, y, z)
    return { x = x, y = y, z = z or 0 }
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local SCALE = RADIUS / RANGE
local NORTH = rotation(0, 1)
local EAST = rotation(1, 0)

test("a target ahead is drawn straight up from the centre", function()
    local harness = new_harness()
    local px, py = harness:project(point(0, 0), NORTH, point(0, 10))

    assert_near(0, px, "ahead drifted sideways")
    assert_near(-10 * SCALE, py, "ahead is not up")

    px, py = harness:project(point(5, 5), EAST, point(15, 5))

    assert_near(0, px, "ahead drifted sideways")
    assert_near(-10 * SCALE, py, "ahead is not up")
end)

test("the radar turns with the view", function()
    local harness = new_harness()

    -- Facing east, a target to the north is on the left and one to the south on the right.
    local px, py = harness:project(point(0, 0), EAST, point(0, 10))

    assert_near(-10 * SCALE, px, "north is not left when facing east")
    assert_near(0, py, "north moved off the horizontal")

    px, py = harness:project(point(0, 0), EAST, point(0, -10))

    assert_near(10 * SCALE, px, "south is not right when facing east")
    assert_near(0, py, "south moved off the horizontal")

    -- Facing north, a target behind is drawn straight down.
    px, py = harness:project(point(0, 0), NORTH, point(0, -10))

    assert_near(0, px, "behind drifted sideways")
    assert_near(10 * SCALE, py, "behind is not down")
end)

test("height and look pitch do not move a marker", function()
    local harness = new_harness()
    local level_x, level_y = harness:project(point(0, 0, 0), rotation(0.6, 0.8, 0), point(3, 7, 0))
    local px, py = harness:project(point(0, 0, 4), rotation(3, 4, 5), point(3, 7, -9))

    assert_near(level_x, px, "pitch or height moved the marker")
    assert_near(level_y, py, "pitch or height moved the marker")

    local forward_x, forward_y = harness.mod:radar_projection_forward(rotation(3, 4, 5))

    assert_near(0.6, forward_x, "the direction is not flattened and normalised")
    assert_near(0.8, forward_y, "the direction is not flattened and normalised")
end)

test("without a usable direction the radar is north-up", function()
    local harness = new_harness()
    local broken = rotation(1, 0)

    broken.broken = true

    for _, rot in ipairs({ false, rotation(0, 0, 1), broken, rotation(0 / 0, 1) }) do
        local forward_x, forward_y = harness.mod:radar_projection_forward(rot or nil)

        assert_nil(forward_x, "a direction was read from an unusable rotation")
        assert_nil(forward_y, "a direction was read from an unusable rotation")

        local px, py = harness:project(point(1, 2), rot or nil, point(4, 6))

        assert_near(3 * SCALE, px, "not north-up")
        assert_near(-4 * SCALE, py, "not north-up")
    end
end)

test("a target beyond the range is dropped", function()
    local harness = new_harness()
    local px, py = harness:project(point(0, 0), NORTH, point(0, RANGE + 0.01))

    assert_nil(px, "an out-of-range target was drawn")
    assert_nil(py, "an out-of-range target was drawn")

    px, py = harness:project(point(0, 0), NORTH, point(0, RANGE))

    assert_near(-RADIUS, py, "a target on the range was not drawn on the edge")
end)

test("a pinned target sits on the edge in its direction", function()
    local harness = new_harness()
    local player = point(2, 1)
    local target = point(2 + 30, 1 + 40)

    for _, style in ipairs({ "square", "auspex", "circle" }) do
        harness.settings.radar_style = style

        local px, py = harness:project(player, EAST, target, true)

        if style == "circle" then
            assert_near(RADIUS, math.sqrt(px * px + py * py), style .. " pin is not on the circle")
        else
            assert_near(RADIUS, math.max(math.abs(px), math.abs(py)), style .. " pin is not on the square")
        end

        -- Facing east, the target is ahead and to the left: 30 m ahead, 40 m left.
        assert_near(-40 / 30, px / -py, style .. " pin left its direction")
    end

    -- An open overview pins every target beyond the range, not only range-exempt ones.
    harness.settings.radar_style = "square"
    harness.mod._overview_mode_active = true

    local px, py = harness:project(player, EAST, target)

    assert_near(-RADIUS, px, "the overview did not pin the target")
    assert_near(-RADIUS * 30 / 40, py, "the overview did not pin the target")
end)

test("unusable input draws nothing", function()
    local harness = new_harness()
    local origin = point(0, 0)
    local cases = {
        { nil, point(1, 1) },
        { origin, nil },
        { origin, point(1, 1), RANGE, 0 },
        { origin, point(1, 1), 0, RADIUS },
        { origin, point(1, 1), -5, RADIUS },
        { origin, point(0 / 0, 1) },
        { origin, point(math.huge, 1) },
        -- Pixels per metre beyond what a number holds.
        { origin, point(1, 1), 1e-300, 1e10 },
    }

    for i = 1, #cases do
        local case = cases[i]
        local px, py = harness:project(case[1], NORTH, case[2], true, case[3], case[4])

        assert_nil(px, "case " .. i .. " was drawn")
        assert_nil(py, "case " .. i .. " was drawn")
    end

    -- Without a range the projection uses 40 m.
    local px, py = harness.mod:project_target_to_radar(origin, 0, 1, point(0, 20), RADIUS, nil, false)

    assert_near(0, px, "the default range moved the marker sideways")
    assert_near(-20 * RADIUS / 40, py, "the default range is not 40 m")
end)

-- The radar's rule, written out: turn the offset into the view, scale metres to pixels, then
-- drop or pin what lies beyond the range.
local function expected_position(player, forward, target, radius, range, ignore_radar_range, overview, style)
    local dx, dy = target.x - player.x, target.y - player.y
    local local_x, local_y = dx, dy

    if forward then
        local length = math.sqrt(forward.x * forward.x + forward.y * forward.y)

        if length > 0 then
            local fx, fy = forward.x / length, forward.y / length

            local_x = dx * fy - dy * fx
            local_y = dx * fx + dy * fy
        end
    end

    local px, py = local_x * radius / range, -local_y * radius / range

    if dx * dx + dy * dy <= range * range then
        return px, py
    end

    if not ignore_radar_range and not overview then
        return nil, nil
    end

    local scale = style == "circle" and radius / math.sqrt(px * px + py * py)
        or radius / math.max(math.abs(px), math.abs(py))

    return px * scale, py * scale
end

test("random targets land where the rule puts them", function()
    local harness = new_harness()
    local seed = 4242

    local function random()
        seed = (seed * 1103515245 + 12345) % 2147483648

        return seed / 2147483648
    end

    local function spread(size)
        return (random() * 2 - 1) * size
    end

    local styles = { "square", "circle", "auspex" }

    for i = 1, 2000 do
        local player = point(spread(500), spread(500), spread(50))
        local forward = random() < 0.1 and { x = 0, y = 0, z = 1 } or { x = spread(1), y = spread(1), z = spread(1) }
        local target = point(player.x + spread(60), player.y + spread(60), spread(50))
        local radius = 50 + random() * 200
        local range = 5 + random() * 100
        local ignore_radar_range = random() < 0.3
        local overview = random() < 0.3
        local style = styles[i % 3 + 1]

        harness.settings.radar_style = style
        harness.mod._overview_mode_active = overview

        local px, py = harness:project(player, rotation(forward.x, forward.y, forward.z), target, ignore_radar_range,
            range, radius)
        local want_x, want_y = expected_position(player, forward, target, radius, range, ignore_radar_range, overview,
            style)

        if want_x == nil then
            assert_nil(px, "case " .. i .. " was drawn")
        else
            assert_near(want_x, px, "case " .. i .. " x")
            assert_near(want_y, py, "case " .. i .. " y")
        end
    end
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
