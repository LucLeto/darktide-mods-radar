-- Input capture behind mouse wheel zoom, and the opt-in profiler around it.
-- Installs the real tracking module into a fake shared environment, takes the handler it hooks
-- onto `InputService._get` and `_get_simulate`, and reads actions through it the way the game
-- does. Every capture case runs with profiling off and on, since profiling must not change
-- which actions are swallowed.

local TRACKING_PATH = "Radar/scripts/mods/Radar/Radar_tracking.lua"

local SCROLL_ACTIONS = {
    "wield_scroll_up",
    "wield_scroll_down",
    "tactical_overlay_scroll_up",
    "tactical_overlay_scroll_down",
}

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

local function assert_contains(text, fragment, message)
    if type(text) ~= "string" or text:find(fragment, 1, true) == nil then
        error((message or "fragment missing") .. ": `" .. fragment .. "` not in `" .. tostring(text) .. "`", 2)
    end
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}

    for key, entry in pairs(value) do
        result[key] = copy(entry)
    end

    return result
end

local function table_size(values)
    local count = 0

    for _ in pairs(values or {}) do
        count = count + 1
    end

    return count
end

local function install(path, env)
    local chunk, load_error = loadfile(path)

    assert(chunk, load_error)

    local installer = chunk()

    assert_equal("function", type(installer), path .. " must return an installer")
    installer(env)
end

local function noop()
end

local function new_harness(options)
    options = options or {}

    local captured = {
        hooks = {},
        info = {},
    }
    local settings = {
        enable_radar = true,
        debug_mode = false,
        debug_profiling = options.profiling == true,
        overview_zoom_in_key = { "wheel_down" },
        overview_zoom_out_key = { "wheel_up" },
        radar_zoom_modifier_key = {},
        radar_scan_rate = "low",
    }
    local state = {
        gameplay_t = 100,
        clock_ms = 1000,
        ui_input_active = false,
        game_mode_allowed = true,
        held_keys = {},
    }
    local mod = {
        _tracked_units = {},
        _tracked_points = {},
    }

    -- DMF clones table settings on every read.
    function mod:get(setting_id)
        return copy(settings[setting_id])
    end

    function mod:set(setting_id, value)
        settings[setting_id] = copy(value)
    end

    function mod:hook(obj, method_name, handler)
        captured.hooks[#captured.hooks + 1] = {
            obj = obj,
            method_name = method_name,
            handler = handler,
        }
    end

    function mod:hook_safe(class_or_name, method_name, callback)
        if class_or_name == "StateGameplay" and method_name == "update" then
            captured.state_gameplay_update = callback
        end
    end

    function mod:register_hud_element()
    end

    function mod:info(message)
        captured.info[#captured.info + 1] = message
    end

    function mod:error()
    end

    function mod:notify()
    end

    -- From the runtime helpers, which this harness does not install.
    function mod:is_radar_runtime_game_mode_allowed()
        return state.game_mode_allowed
    end

    local key_index_by_name = {
        ["left alt"] = 1,
    }
    local env = {
        mod = mod,
        SCAN_INTERVAL = 0.25,
        KIND_TO_SETTING = {},
        RESPAWN_MARKER_KINDS = {},
        SAFEROUTE_MARKER_KINDS = {},
        NEARBY_HIGHLIGHT_SETTING_BY_GROUP = {},
        CLASS = { InputService = {} },
        Managers = {
            ui = {
                using_input = function()
                    return state.ui_input_active
                end,
            },
        },
        Keyboard = {
            button_index = function(name)
                return key_index_by_name[name]
            end,
            button = function(index)
                return state.held_keys[index] and 1 or 0
            end,
        },
        Mouse = {
            button_index = function()
                return nil
            end,
            button = function()
                return 0
            end,
        },
        Vector3 = function(x, y, z)
            return { x = x, y = y, z = z }
        end,
        Application = {
            query_performance_counter = function()
                return "counter"
            end,
            time_since_query = function(handle)
                assert_equal("counter", handle, "the profiler read the clock without its counter handle")

                return state.clock_ms
            end,
        },
    }

    env._safe_gameplay_time = function()
        return state.gameplay_t
    end

    env._table_size = table_size

    env._get_runtime_state = function()
        return true, "ok", state.gameplay_t, "cm_habs", "mission", "adventure", { name = "player" },
            { x = 0, y = 0, z = 0 }
    end

    -- Every other shared function belongs to a module this harness does not install. The update
    -- loop only needs them to exist; the capture path calls none of them.
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

    install(TRACKING_PATH, env)

    local service = {}
    local harness = {
        captured = captured,
        env = env,
        mod = mod,
        settings = settings,
        state = state,
        service = service,
    }

    for i = 1, #captured.hooks do
        local hook = captured.hooks[i]

        if hook.method_name == "_get" then
            harness.get_handler = hook.handler
        elseif hook.method_name == "_get_simulate" then
            harness.simulate_handler = hook.handler
        end
    end

    --- Reads an action through the hook, as if the original method returned `value`.
    function harness:read(action_name, value, method_name)
        local handler = method_name == "_get_simulate" and self.simulate_handler or self.get_handler

        return handler(function(_, name)
            assert_equal(action_name, name, "the hook passed another action to the original method")

            return value
        end, self.service, action_name)
    end

    function harness:change_setting(setting_id, value)
        settings[setting_id] = copy(value)
        mod.on_setting_changed(setting_id)
    end

    function harness:set_overview(active)
        mod._overview_mode_active = active == true
    end

    return harness
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local PROFILING_MODES = {
    { label = "profiling off", profiling = false },
    { label = "profiling on", profiling = true },
}

for m = 1, #PROFILING_MODES do
    local mode = PROFILING_MODES[m]

    local function harness_for_mode()
        return new_harness({ profiling = mode.profiling })
    end

    test(mode.label .. ": both action read paths share one hook handler", function()
        local harness = harness_for_mode()

        assert_equal(2, #harness.captured.hooks, "unexpected number of input hooks")

        for i = 1, #harness.captured.hooks do
            assert_true(harness.captured.hooks[i].obj == harness.env.CLASS.InputService,
                "a hook is not on InputService")
        end

        assert_true(harness.get_handler ~= nil and harness.get_handler == harness.simulate_handler,
            "_get and _get_simulate are not hooked with the same handler")
    end)

    test(mode.label .. ": the capture map is built lazily from the default wheel zoom keys", function()
        local harness = harness_for_mode()

        assert_nil(harness.mod._overview_capture_actions, "the capture map was built before the first read")
        harness:set_overview(true)
        assert_equal(false, harness:read("wield_scroll_up", true), "the first scroll read was not captured")

        local capture_actions = harness.mod._overview_capture_actions

        assert_equal(#SCROLL_ACTIONS, table_size(capture_actions), "unexpected captured action count")

        for i = 1, #SCROLL_ACTIONS do
            assert_true(capture_actions[SCROLL_ACTIONS[i]] == true, SCROLL_ACTIONS[i] .. " is not captured")
        end
    end)

    test(mode.label .. ": unrelated actions pass through unchanged", function()
        local harness = harness_for_mode()

        harness:set_overview(true)
        harness:read("wield_scroll_up", true)

        local axis = newproxy()

        assert_equal(true, harness:read("jump", true), "jump was changed")
        assert_equal(0.75, harness:read("move_forward", 0.75), "move_forward was changed")
        assert_equal(axis, harness:read("look_raw", axis), "an unrelated axis was changed")
        assert_equal(true, harness:read("wield_scroll_up_typo", true), "a similar action name was captured")
        assert_equal(true, harness:read(nil, true), "a nil action name was captured")
        assert_equal(true, harness:read("jump", true, "_get_simulate"), "a simulated jump was changed")
    end)

    test(mode.label .. ": captured actions read as their neutral value on both read paths", function()
        local harness = harness_for_mode()

        harness:set_overview(true)

        local methods = { "_get", "_get_simulate" }

        for i = 1, #methods do
            local method_name = methods[i]
            local zero = harness:read("wield_scroll_down", newproxy(), method_name)

            assert_equal(false, harness:read("wield_scroll_up", true, method_name), method_name .. " boolean")
            assert_equal(0, harness:read("tactical_overlay_scroll_up", 1, method_name), method_name .. " number")
            assert_true(type(zero) == "table" and zero.x == 0 and zero.y == 0 and zero.z == 0,
                method_name .. " axis was not zeroed")
            assert_equal("value", harness:read("tactical_overlay_scroll_down", "value", method_name),
                method_name .. " string was changed")
            assert_nil(harness:read("wield_scroll_down", nil, method_name), method_name .. " nil was changed")
        end
    end)

    test(mode.label .. ": capture follows overview, modifier, grace and runtime state exactly", function()
        local harness = harness_for_mode()
        local state = harness.state
        local mod = harness.mod
        local grace_offsets = { none = false, within = 0.05, expired = 0.5 }
        local grace_names = { "none", "within", "expired" }
        local bools = { false, true }

        harness:change_setting("radar_zoom_modifier_key", { "left alt" })

        for _, overview in ipairs(bools) do
            for _, held in ipairs(bools) do
                for g = 1, #grace_names do
                    local grace = grace_names[g]

                    for _, ui_input_active in ipairs(bools) do
                        for _, game_mode_allowed in ipairs(bools) do
                            local label = string.format("overview=%s held=%s grace=%s ui=%s allowed=%s",
                                tostring(overview), tostring(held), grace, tostring(ui_input_active),
                                tostring(game_mode_allowed))
                            local allowed = not ui_input_active and game_mode_allowed
                            local key_active = held or grace == "within"
                            local expected_modifier = not overview and allowed and key_active
                            local expected_capture = allowed and (overview or key_active)

                            harness:set_overview(overview)
                            state.held_keys[1] = held
                            state.ui_input_active = ui_input_active
                            state.game_mode_allowed = game_mode_allowed
                            mod._normal_radar_zoom_modifier_t = grace_offsets[grace]
                                and state.gameplay_t - grace_offsets[grace] or nil

                            assert_equal(expected_modifier, mod:is_normal_radar_zoom_modifier_active(),
                                "modifier state for " .. label)
                            assert_equal(expected_capture, mod:should_capture_overview_input_action("wield_scroll_up"),
                                "capture decision for " .. label)
                            assert_equal(not expected_capture, harness:read("wield_scroll_up", true),
                                "hook result for " .. label)
                            assert_equal(true, harness:read("jump", true), "jump was changed for " .. label)
                        end
                    end
                end
            end
        end
    end)

    test(mode.label .. ": rebinding the zoom keys changes which scrolls are captured", function()
        local harness = harness_for_mode()

        harness:set_overview(true)
        harness:change_setting("overview_zoom_in_key", { "page_up" })
        harness:change_setting("overview_zoom_out_key", { "page_down" })

        for i = 1, #SCROLL_ACTIONS do
            assert_equal(true, harness:read(SCROLL_ACTIONS[i], true), SCROLL_ACTIONS[i] .. " was captured without a wheel key")
        end

        harness:change_setting("overview_zoom_in_key", { "wheel_up" })

        assert_equal(false, harness:read("wield_scroll_up", true), "wheel up was not captured after rebinding")
        assert_equal(false, harness:read("tactical_overlay_scroll_up", true), "overlay up was not captured")
        assert_equal(true, harness:read("wield_scroll_down", true), "wheel down was captured without a key")
        assert_equal(true, harness:read("tactical_overlay_scroll_down", true), "overlay down was captured")
    end)

    test(mode.label .. ": opening and closing overview through its keybind switches capture", function()
        local harness = harness_for_mode()

        assert_equal(true, harness:read("wield_scroll_down", true), "a scroll was captured before overview opened")
        assert_true(harness.mod.toggle_overview_keybind() == true, "overview did not open")
        assert_equal(false, harness:read("wield_scroll_down", true), "a scroll was not captured in overview")
        assert_equal(false, harness.mod.toggle_overview_keybind(), "overview did not close")
        assert_equal(true, harness:read("wield_scroll_down", true), "a scroll was captured after overview closed")
    end)

    test(mode.label .. ": a modifier press keeps capturing scrolls for its grace period", function()
        local harness = harness_for_mode()

        harness:change_setting("radar_zoom_modifier_key", { "left alt" })
        assert_true(harness.mod.radar_zoom_modifier_keybind() == true, "the modifier press was refused")
        assert_equal(false, harness:read("wield_scroll_up", true), "a scroll right after the press was not captured")

        harness.state.gameplay_t = harness.state.gameplay_t + 0.2
        assert_equal(true, harness:read("wield_scroll_up", true), "a scroll after the grace period was captured")
    end)
end

test("profiling is off by default and logs nothing", function()
    local harness = new_harness()

    assert_nil(harness.mod:radar_profiler_now(), "the profiler clock is readable while profiling is off")
    assert_nil(harness.mod:radar_profiler_lap("draw_total", 0), "a lap was recorded while profiling is off")

    harness:set_overview(true)

    for _ = 1, 10 do
        harness:read("wield_scroll_up", true)
        harness:read("jump", true)
    end

    harness.state.clock_ms = harness.state.clock_ms + 6000
    harness.mod.update(0.016)

    assert_equal(0, #harness.captured.info, "a profile line was logged while profiling is off")
end)

test("profiling counts reads and suppressions and reports one summary per window", function()
    local harness = new_harness({ profiling = true })
    local mod = harness.mod
    local state = harness.state
    local info = harness.captured.info

    assert_equal(state.clock_ms, mod:radar_profiler_now(), "the profiler does not read the engine counter")

    harness:set_overview(true)

    for _ = 1, 8 do
        harness:read("jump", true)
    end

    harness:read("wield_scroll_up", true)
    harness:read("wield_scroll_down", true)

    local mark = mod:radar_profiler_now()

    state.clock_ms = state.clock_ms + 2
    mod:radar_profiler_lap("draw_total", mark)
    mod:radar_profiler_value("draw_markers_drawn", 12)
    mod:radar_profiler_count("draw_cache_refreshes", 1)
    mod:radar_profiler_lap("not_a_metric", mark)
    mod:radar_profiler_value("not_a_metric", 1)
    mod:radar_profiler_count("not_a_counter", 1)

    state.clock_ms = state.clock_ms + 4997
    mod.update(0.016)
    assert_equal(0, #info, "a summary was written before the window closed")

    state.clock_ms = state.clock_ms + 1
    mod.update(0.016)
    assert_equal(5, #info, "unexpected number of summary lines")
    assert_contains(info[1], "[Radar] profile | window_s=5.00 timer=performance_counter", "header line")
    assert_contains(info[1], "fps=0.4 frame_ms=16.00", "frame rate")
    assert_contains(info[1], "overview=true scan_rate=low", "settings context")
    assert_contains(info[2], "[Radar] profile input | calls/s=2 candidates/s=0.4 suppressed/s=0.4", "input rates")
    assert_contains(info[2], "other_us=0.000/0.000/0.000 candidate_us=0.000/0.000/0.000", "input timings")
    assert_contains(info[3], "[Radar] profile update | updates/s=0.0", "update line")
    assert_contains(info[4], "[Radar] profile scan | moving_ms=- ", "scan line without scans")
    assert_contains(info[5], "[Radar] profile draw | draws/s=0.2 total_ms=2.000/2.000/2.000", "draw total")
    assert_contains(info[5], "cache_refreshes/s=0.20", "cache refreshes")
    assert_contains(info[5], "drawn=12.0/12", "drawn markers")

    state.clock_ms = state.clock_ms + 5000
    mod.update(0.016)
    assert_equal(5, #info, "an empty window was reported")
end)

test("turning profiling off stops the reports and the clock", function()
    local harness = new_harness({ profiling = true })
    local mod = harness.mod

    harness:change_setting("debug_profiling", false)
    assert_nil(mod:radar_profiler_now(), "the profiler clock is readable after profiling was turned off")

    harness:read("jump", true)
    harness.state.clock_ms = harness.state.clock_ms + 6000
    mod.update(0.016)
    assert_equal(0, #harness.captured.info, "a summary was written after profiling was turned off")

    harness:change_setting("debug_profiling", true)
    harness:read("jump", true)
    harness.state.clock_ms = harness.state.clock_ms + 5000
    mod.update(0.016)
    assert_equal(5, #harness.captured.info, "profiling did not restart")
    assert_contains(harness.captured.info[2], "calls/s=0 ", "the restarted window kept old reads")
end)

test("a profiled update counts every scan tier at its configured rate", function()
    local harness = new_harness({ profiling = true })
    local mod = harness.mod
    local state = harness.state
    local info = harness.captured.info
    local state_gameplay = {}

    mod._gameplay_run = true

    -- 40 frames of 0.125 s, five seconds of gameplay and of profiler clock. The low rate scans
    -- every 0.25 s, the droppable tier runs with it and the static tier every 0.5 s.
    for _ = 1, 40 do
        state.gameplay_t = state.gameplay_t + 0.125
        state.clock_ms = state.clock_ms + 125
        harness.captured.state_gameplay_update(state_gameplay, 0.125, state.gameplay_t)
        mod.update(0.125)
    end

    -- `mod.update` repeats the update of the gameplay state's own hook, which is skipped as a
    -- duplicate, but it reports first; the last frame's duplicate belongs to the next window.
    assert_equal(5, #info, "unexpected number of summary lines")
    assert_contains(info[3], "updates/s=8.0 duplicates/s=7.8 blocked/s=0.0 disabled/s=0.0", "update rates")
    assert_contains(info[3], "scans/s=4.00 droppable/s=4.00 static/s=2.00", "scan tier rates")
    assert_contains(info[4], "moving_ms=0.000/0.000/0.000 droppable_ms=0.000/0.000/0.000", "scan tier timings")
    assert_contains(info[4], "targets=0.0/0 active=0.0/0 highlights=0.0/0 tracked=0.0/0", "scan counts")
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
