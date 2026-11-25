-- A Cyber Mastiff on its target and the companions' marker range, from the companion rules to
-- the radar targets. Installs the real runtime helpers, players and tracking modules into a fake
-- shared environment and builds radar targets through `_collect_radar_targets`, reached through
-- the upvalues of the update the `StateGameplay.update` hook runs. A mastiff within 2 m of its
-- target is drawn above it and stays on the radar however far away, so the enemy it pins, kept at
-- the edge by a tag, never shows its cleared marker there without the mastiff; a mastiff away from
-- its target or without one, and a servo skull at work, keep to the radar range. A mastiff
-- pinning its target takes no heading until it lets go, while one on an enemy it does not pin,
-- or still running to one another mastiff pins, keeps its own. The companion marker range, Normal
-- unless set, keeps every companion on the radar however far away once Infinite, apart from the
-- teammates' own range, and is named in every language the teammate one is.

local HELPERS_PATH = "Radar/scripts/mods/Radar/Radar_runtime_helpers.lua"
local PLAYERS_PATH = "Radar/scripts/mods/Radar/Radar_players.lua"
local TRACKING_PATH = "Radar/scripts/mods/Radar/Radar_tracking.lua"
local LOCALIZATION_PATH = "Radar/scripts/mods/Radar/Radar_localization.lua"
local RANGE = 40
local MASTIFF = "player_companion_dog"
local SERVO_SKULL = "player_companion_servo_skull"
local TEAMMATE = "player_teammate"
local GUNNER = "enemy_renegade_gunner"

table.clear = table.clear or function(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

local function assert_true(value, message)
    if not value then
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

-- A rotation is a table holding its forward vector, which the fake `Quaternion.forward` reads back.
local NORTH = { forward = { x = 0, y = 1, z = 0 } }
local EAST = { forward = { x = 1, y = 0, z = 0 } }

local function new_harness()
    local captured = {}
    local alive = {}
    local pinned = {}
    local settings = {
        enable_radar = true,
        debug_mode = false,
        debug_profiling = false,
        radar_style = "square",
        radar_range = RANGE,
        max_radar_markers = 64,
        show_cyber_mastiff_facing = false,
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
        CompanionServoSkullSettings = { STATES = {} },
        Quaternion = {
            forward = function(rotation)
                return rotation.forward
            end,
        },
        Unit = {
            world_rotation = function(unit)
                return unit.root_rotation
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
    install(PLAYERS_PATH, env)
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

    -- What the scans around the collection would decide; every kind is enabled, every unit
    -- still alive is trackable, and the player scan found the mastiffs pinning `pinned`.
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
        return pinned
    end
    env._cluster_expedition_loot_targets = function(targets)
        return targets
    end

    local update_internal = named_upvalue(captured.state_gameplay_update, "_update_internal")
    local collect_radar_targets = named_upvalue(update_internal, "_collect_radar_targets")
    local harness = {
        env = env,
        mod = mod,
        pinned = pinned,
    }

    --- Makes a live unit on the Radar player's floor, `x` metres east and `y` north of them, facing along `root`.
    function harness:unit(x, y, root)
        local unit = { position = { x = x, y = y or 0, z = 0 }, root_rotation = root }

        alive[unit] = true

        return unit
    end

    --- Tracks a unit as a radar target of a kind, from a scan source with its meta.
    function harness:track(unit, kind, source, meta)
        mod._tracked_units[unit] = {
            kind = kind,
            source = source,
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

        return by_unit
    end

    function harness:forget()
        for unit in pairs(mod._tracked_units) do
            mod._tracked_units[unit] = nil
        end

        table.clear(pinned)
    end

    return harness
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("a mastiff on its target stays on the radar over the tagged enemy it pins at the edge", function()
    local harness = new_harness()

    assert_equal(RANGE, harness.mod:get_radar_collection_range(), "the harness range")

    local enemy = harness:unit(RANGE + 60, 0)
    local mastiff = harness:unit(RANGE + 60.5, 0.5)

    harness:track(enemy, GUNNER, "unit_data_system", { marked_by_player_slot = 1 })
    harness:track(mastiff, MASTIFF, "player_companion", { player_slot = 1, companion_action_target = enemy })
    harness.pinned[enemy] = true

    local by_unit = harness:collect()
    local pinned = by_unit[enemy]
    local on_target = by_unit[mastiff]

    assert_true(pinned ~= nil, "the tagged enemy left the radar")
    assert_equal(true, pinned.ignore_radar_range, "the tagged enemy is not kept at the edge")
    assert_equal(true, pinned.disabled_by_mastiff, "the enemy is not pinned")
    assert_true(on_target ~= nil, "the mastiff on its target left the radar")
    assert_equal(true, on_target.ignore_radar_range, "the mastiff is not kept at the edge with its enemy")
    assert_true(on_target.render_layer > pinned.render_layer, "the mastiff is not drawn above the enemy it pins")

    -- An untagged enemy just inside the range keeps the mastiff on it just outside.
    harness:forget()

    local inside = harness:unit(RANGE - 0.5, 0)
    local outside = harness:unit(RANGE + 1, 0)

    harness:track(inside, GUNNER, "unit_data_system", {})
    harness:track(outside, MASTIFF, "player_companion", { player_slot = 1, companion_action_target = inside })
    harness.pinned[inside] = true
    by_unit = harness:collect()

    assert_true(by_unit[inside] ~= nil, "the enemy inside the range left the radar")
    assert_true(not by_unit[inside].ignore_radar_range, "an untagged enemy is kept beyond the range")
    assert_true(by_unit[outside] ~= nil, "the mastiff just outside the range left the enemy it pins")
end)

test("a mastiff away from its target or without one keeps to the radar range", function()
    local harness = new_harness()
    local enemy = harness:unit(RANGE + 60, 0)
    local chasing = harness:unit(RANGE + 55, 0)
    local idle = harness:unit(RANGE + 10, 0)
    local near = harness:unit(5, 0)

    harness:track(enemy, GUNNER, "unit_data_system", { marked_by_player_slot = 1 })
    harness:track(chasing, MASTIFF, "player_companion", { player_slot = 1, companion_action_target = enemy })
    harness:track(idle, MASTIFF, "player_companion", { player_slot = 2 })
    harness:track(near, MASTIFF, "player_companion", { player_slot = 3 })

    local by_unit = harness:collect()

    assert_true(by_unit[enemy] ~= nil, "the tagged enemy left the radar")
    assert_nil(by_unit[chasing], "a mastiff 5 m from its target was kept beyond the range")
    assert_nil(by_unit[idle], "a mastiff without a target was kept beyond the range")
    assert_true(by_unit[near] ~= nil, "a mastiff within the range left the radar")
    assert_true(not by_unit[near].ignore_radar_range, "a mastiff without a target ignores the range")
    assert_equal(0, by_unit[near].render_layer, "a mastiff without a target is drawn on the companion layer")
end)

test("a servo skull at work keeps to the radar range", function()
    local harness = new_harness()
    local far = harness:unit(RANGE + 10, 0)
    local near = harness:unit(3, 0)

    harness:track(far, SERVO_SKULL, "player_companion", { player_slot = 1, companion_action = "hacking" })
    harness:track(near, SERVO_SKULL, "player_companion", { player_slot = 2, companion_action = "hacking" })

    local by_unit = harness:collect()

    assert_nil(by_unit[far], "a hacking servo skull was kept beyond the range")
    assert_true(by_unit[near] ~= nil, "a hacking servo skull within the range left the radar")
    assert_true(not by_unit[near].ignore_radar_range, "a hacking servo skull ignores the range")
    assert_true(by_unit[near].render_layer > 0, "a hacking servo skull is not drawn on the companion layer")
end)

test("a mastiff pinning its target takes no heading until it lets go, unlike one on an enemy it does not pin", function()
    local harness = new_harness()

    harness.mod:set("show_cyber_mastiff_facing", true)

    local enemy = harness:unit(10, 0, EAST)
    local mastiff = harness:unit(10.5, 0.5, NORTH)
    local running = harness:unit(20, 0, NORTH)

    harness:track(enemy, GUNNER, "unit_data_system", {})
    harness:track(mastiff, MASTIFF, "player_companion", { player_slot = 1, companion_action_target = enemy })
    harness:track(running, MASTIFF, "player_companion", { player_slot = 2, companion_action_target = enemy })
    harness.pinned[enemy] = true

    local by_unit = harness:collect()

    assert_equal(true, by_unit[enemy].disabled_by_mastiff, "the enemy is not pinned")
    assert_nil(by_unit[mastiff].heading_x, "a mastiff pinning its target took a heading")
    assert_nil(by_unit[mastiff].heading_y, "a mastiff pinning its target took a heading")
    assert_near(1, by_unit[running].heading_y, "a mastiff running to an enemy another one pins lost its heading")

    -- Let go, or on an enemy it staggers and leaps away from, which the player scan never counts as pinned.
    harness.pinned[enemy] = nil
    by_unit = harness:collect()

    assert_near(0, by_unit[mastiff].heading_x, "a mastiff on an enemy it does not pin took no heading")
    assert_near(1, by_unit[mastiff].heading_y, "a mastiff on an enemy it does not pin took no heading")
end)

test("companion marker range on Infinite keeps every companion on the radar however far away, and no teammate", function()
    local harness = new_harness()
    local mastiff = harness:unit(RANGE + 25, 0)
    local servo_skull = harness:unit(0, RANGE + 30)
    local teammate = harness:unit(-(RANGE + 20), 0)

    harness:track(mastiff, MASTIFF, "player_companion", { player_slot = 1 })
    harness:track(servo_skull, SERVO_SKULL, "player_companion", { player_slot = 2 })
    harness:track(teammate, TEAMMATE, "player_manager", { player_slot = 3 })

    assert_equal("normal", harness.mod:get_companion_marker_range_mode(), "the unset companion marker range")

    local by_unit = harness:collect()

    assert_nil(by_unit[mastiff], "a far mastiff stayed on the radar with the range unset")
    assert_nil(by_unit[servo_skull], "a far servo skull stayed on the radar with the range unset")

    harness.mod:set("companion_marker_range_mode", "infinite")
    by_unit = harness:collect()

    assert_true(by_unit[mastiff] ~= nil and by_unit[mastiff].ignore_radar_range == true,
        "a far mastiff is not kept at the edge on Infinite")
    assert_true(by_unit[servo_skull] ~= nil and by_unit[servo_skull].ignore_radar_range == true,
        "a far servo skull is not kept at the edge on Infinite")
    assert_nil(by_unit[teammate], "the companion marker range kept a far teammate")

    -- The teammates' own range keeps them and leaves the companions to theirs.
    harness.mod:set("companion_marker_range_mode", "normal")
    harness.mod:set("player_marker_range_mode", "infinite")
    by_unit = harness:collect()

    assert_true(by_unit[teammate] ~= nil, "a far teammate is not kept with the teammate range on Infinite")
    assert_nil(by_unit[mastiff], "the teammate range kept a far mastiff")
    assert_nil(by_unit[servo_skull], "the teammate range kept a far servo skull")
end)

test("the companion marker range is named in every language the teammate one is", function()
    local chunk = assert(loadfile(LOCALIZATION_PATH))

    setfenv(chunk, setmetatable({
        Localize = function(key)
            return key
        end,
    }, { __index = _G }))

    local localization = chunk()
    local reference = localization.player_marker_range_mode

    for _, key in ipairs({
        "companion_marker_range_mode",
        "companion_marker_range_mode_tooltip",
        "companion_marker_range_mode_normal",
        "companion_marker_range_mode_infinite",
    }) do
        local entry = localization[key]

        assert_true(type(entry) == "table", key .. " is missing")

        for language in pairs(reference) do
            assert_true(type(entry[language]) == "string" and entry[language] ~= "", key .. " has no " .. language)
        end
    end

    assert_equal("Companion marker range", localization.companion_marker_range_mode.en, "English label")
    assert_true(localization.companion_marker_range_mode_normal == localization.player_marker_range_mode_normal
        and localization.companion_marker_range_mode_infinite == localization.player_marker_range_mode_infinite,
        "the companion range options are not named like the teammate ones")
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
