-- Enemy threat awareness, from an enemy's replicated target to its marker.
-- First checks which checkbox every enemy kind follows, with the real enemy definitions. Then
-- installs the real runtime helpers and tracking modules into a fake shared environment, over a
-- fake game session whose minions carry the `target_unit_id` game object field the server's
-- perception writes, and checks the read (the Radar player's id, another one, none, or nothing
-- readable, and never a guess), that only drawn enemies of a category with threat awareness are
-- read, once per pass and never when the marker limit cuts them, that a new Radar player is read
-- against at once, that every category off costs nothing, that a pooled target never keeps a
-- state, and that the states go when the radar stops or the mission ends. Last, loads the HUD
-- element against a fake UI stack and checks the look `_target_visual` gives an enemy; the
-- backplate and the frame in the four shared colours, the frame in the targeting colour only while
-- the enemy targets the Radar player, a flash only on a confirmed acquisition, the layers below
-- every icon, one visual per unit with no garbage per frame, and the texts in every language.

local HELPERS_PATH = "Radar/scripts/mods/Radar/Radar_runtime_helpers.lua"
local TRACKING_PATH = "Radar/scripts/mods/Radar/Radar_tracking.lua"
local DEFINITIONS_PATH = "Radar/scripts/mods/Radar/Radar_enemy_definitions.lua"
local HUD_PATH = "Radar/scripts/mods/Radar/ui/Radar_hud_element.lua"
local LOCALIZATION_PATH = "Radar/scripts/mods/Radar/Radar_localization.lua"
local BACKPLATE = "content/ui/materials/hud/interactions/frames/pickup_back"
local FRAME = "content/ui/materials/hud/interactions/frames/pickup_top"
local FLASH = "content/ui/materials/hud/interactions/frames/critical_tag"
local NEUTRAL_FRAME_COLOR = { 255, 216, 229, 207 }
local TARGETING_FRAME_COLOR = { 230, 250, 10, 20 }
local BACKPLATE_COLOR = { 200, 120, 5, 6 }
local FLASH_COLOR = { 190, 255, 40, 30 }
local GUNNER = "enemy_renegade_gunner"
local POXWALKER = "enemy_chaos_poxwalker"
local MONSTROSITY = "enemy_monstrosity"
local PLAYER_ID = 7
local TEAMMATE_ID = 8
local INVALID_ID = 0
local THREAT_SETTING_IDS = {
    "show_enemy_boss_threat",
    "show_enemy_horde_threat",
    "show_enemy_common_threat",
    "show_enemy_shooter_threat",
    "show_enemy_elite_threat",
    "show_enemy_special_threat",
}
--- The checkbox of each enemy category; Misc has none, as its Ritualists never target a player.
local THREAT_SETTING_BY_CATEGORY = {
    horde = "show_enemy_horde_threat",
    common = "show_enemy_common_threat",
    shooter = "show_enemy_shooter_threat",
    elite = "show_enemy_elite_threat",
    special = "show_enemy_special_threat",
}
local BOSS_KINDS = { "enemy_daemonhost", "enemy_monstrosity", "enemy_captain", "enemy_karnak_twin" }
--- The kinds the harnesses below know, with their category checkbox and render layer.
local THREAT_SETTING_BY_KIND = {
    [GUNNER] = "show_enemy_elite_threat",
    [POXWALKER] = "show_enemy_horde_threat",
    [MONSTROSITY] = "show_enemy_boss_threat",
}
local RENDER_LAYER_BY_KIND = {
    [GUNNER] = 4,
    [POXWALKER] = 0,
    [MONSTROSITY] = 5,
}
--- Radar definitions of a composed elite (background and icon) and a horde enemy drawn as one icon.
local DEFINITIONS = {
    [GUNNER] = {
        kind = GUNNER,
        category = "elite",
        icon = "content/ui/materials/icons/gunner",
        icon_color = { 255, 1, 2, 3 },
        background_icon = "content/ui/materials/hud/interactions/icons/default",
        background_color = { 220, 255, 0, 0 },
        size = 12,
        background_size = 12,
        icon_size = 8,
    },
    [POXWALKER] = {
        kind = POXWALKER,
        category = "horde",
        icon = "content/ui/materials/icons/poxwalker",
        icon_color = { 220, 255, 0, 0 },
        background_icon = "content/ui/materials/hud/interactions/icons/default",
        background_color = { 220, 255, 0, 0 },
        size = 8,
    },
}
--- Fields of an enemy's own visual the threat look keeps as they are.
local BASE_FIELDS = {
    "icon", "color", "overlay_icon", "overlay_color", "background_base_size", "overlay_base_size",
    "bracket_base_size", "accent_color", "size", "value_text", "value_text_color", "value_text_anchor",
    "value_text_offset_x", "value_text_offset_y",
}
local THREAT_FIELDS = {
    "plate_icon", "plate_color", "plate_base_size", "ring_icon", "ring_color", "ring_base_size",
    "flash_icon", "flash_color", "flash_base_size", "decoration_layer_drop", "icon_scale",
}

table.clear = table.clear or function(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

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

local function same_values(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end

    for key, value in pairs(a) do
        if not same_values(value, b[key]) then
            return false
        end
    end

    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end

    return true
end

local function named_upvalue(fn, expected_name)
    for index = 1, 255 do
        local name, value = debug.getupvalue(fn, index)

        if name == nil then
            error("missing upvalue `" .. expected_name .. "`", 2)
        elseif name == expected_name then
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

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

-- --------------------------------------------------------------------------------------------
-- Which checkbox an enemy follows
-- --------------------------------------------------------------------------------------------

--- Installs the real enemy definitions against a fake mod reading the given settings.
local function load_definitions(settings)
    local mod = {}

    function mod:get(setting_id)
        return settings[setting_id]
    end

    function mod:set(setting_id, value)
        settings[setting_id] = value
    end

    function mod:localize(key)
        return tostring(key)
    end

    function mod:io_dofile(path)
        return assert(loadfile(path .. ".lua"))()
    end

    mod.hook_safe = noop
    mod.hook = noop
    mod.info = noop
    mod.error = noop
    mod.notify = noop

    _G.get_mod = function()
        return mod
    end
    _G.Localize = function(key)
        return tostring(key)
    end

    local env = setmetatable({ mod = mod, Pickups = { by_name = {} } }, { __index = _G })

    install(DEFINITIONS_PATH, env)

    return mod, env
end

test("each enemy kind follows its category's checkbox, bosses the boss one, Misc enemies none; all off at first", function()
    local settings = {}
    local mod, env = load_definitions(settings)
    local definitions = env.ENEMY_RADAR_DEFINITION_BY_KIND
    local kind_count = 0
    local misc_count = 0

    for kind, definition in pairs(definitions) do
        kind_count = kind_count + 1

        if definition.category == "misc" then
            misc_count = misc_count + 1
        else
            assert_true(THREAT_SETTING_BY_CATEGORY[definition.category] ~= nil, kind .. " is in no threat category")
        end

        assert_equal(false, mod:show_enemy_threat(kind), kind .. " shows threat awareness by default")
    end

    assert_true(misc_count > 0, "no Misc enemy kind to check")

    assert_true(kind_count > 20, "too few enemy kinds to check")

    for i = 1, #BOSS_KINDS do
        assert_equal(false, mod:show_enemy_threat(BOSS_KINDS[i]), BOSS_KINDS[i] .. " shows threat awareness by default")
    end

    for i = 1, #THREAT_SETTING_IDS do
        local setting_id = THREAT_SETTING_IDS[i]

        for j = 1, #THREAT_SETTING_IDS do
            settings[THREAT_SETTING_IDS[j]] = nil
        end

        settings[setting_id] = true

        for kind, definition in pairs(definitions) do
            assert_equal(THREAT_SETTING_BY_CATEGORY[definition.category] == setting_id, mod:show_enemy_threat(kind),
                kind .. " with only " .. setting_id .. " on")
        end

        for j = 1, #BOSS_KINDS do
            assert_equal(setting_id == "show_enemy_boss_threat", mod:show_enemy_threat(BOSS_KINDS[j]),
                BOSS_KINDS[j] .. " with only " .. setting_id .. " on")
        end
    end

    -- A breed name resolves through its definition, as a kind does.
    settings.show_enemy_elite_threat = true
    assert_equal(true, mod:show_enemy_threat("renegade_gunner"), "a gunner's breed does not follow the elite checkbox")
    assert_equal(false, mod:show_enemy_threat("pickup_ammo_small"), "a pickup shows threat awareness")

    -- With every checkbox on, and a Misc value left from an earlier build, Misc enemies still show none.
    for i = 1, #THREAT_SETTING_IDS do
        settings[THREAT_SETTING_IDS[i]] = true
    end

    settings.show_enemy_misc_threat = true

    for kind, definition in pairs(definitions) do
        assert_equal(definition.category ~= "misc", mod:show_enemy_threat(kind), kind .. " with every checkbox on")
    end

    assert_equal(false, mod:show_enemy_threat("cultist_ritualist"), "a Ritualist's breed shows threat awareness")
end)

-- --------------------------------------------------------------------------------------------
-- Reading the replicated target and the threat pass
-- --------------------------------------------------------------------------------------------

--- Installs the real runtime helpers and tracking over a fake game session and Radar player.
-- Every minion is a game object whose `target_unit_id` the test sets; reads, id lookups and
-- extension lookups are counted.
local function new_harness(options)
    options = options or {}

    local captured = {}
    local alive = {}
    local state = { t = 100 }
    local settings = {
        enable_radar = true,
        debug_mode = false,
        debug_profiling = false,
        radar_style = "square",
        max_radar_markers = options.max_markers or 64,
        overview_zoom_in_key = { "wheel_down" },
        overview_zoom_out_key = { "wheel_up" },
        radar_zoom_modifier_key = {},
    }
    local world = {
        ids = {},
        objects = {},
        session = { "game session" },
        has_session = true,
        reads = 0,
        id_lookups = 0,
        extension_lookups = {},
        enemies = {},
        next_id = 100,
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

    function mod:show_enemy_threat(kind)
        local setting_id = THREAT_SETTING_BY_KIND[kind]

        return setting_id ~= nil and settings[setting_id] == true
    end

    function mod:get_player_marker_range_mode()
        return "default"
    end

    function mod:get_target_render_layer(kind)
        return RENDER_LAYER_BY_KIND[kind] or 0
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

    local game_session_api = {
        game_object_exists = function(game_session, game_object_id)
            assert(game_session == world.session, "a field was read through another game session")

            return world.objects[game_object_id] ~= nil
        end,
        game_object_field = function(game_session, game_object_id, field_name)
            assert(game_session == world.session, "a field was read through another game session")

            local object = world.objects[game_object_id]

            world.reads = world.reads + 1

            if object.raises then
                error("the game object has no field " .. field_name)
            end

            local value = object[field_name]

            if value == nil then
                error("the game object has no field " .. field_name)
            end

            return value
        end,
    }
    local managers = {
        state = {
            game_session = {
                game_session = function()
                    return world.has_session and world.session or nil
                end,
            },
            unit_spawner = {
                game_object_id = function(_, unit)
                    world.id_lookups = world.id_lookups + 1

                    return world.ids[unit]
                end,
            },
        },
    }
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
        GameSession = game_session_api,
        Managers = managers,
        -- A client has no perception extension or blackboard for a minion; any lookup is recorded.
        BLACKBOARDS = {},
        ScriptUnit = {
            has_extension = function(_, system_name)
                world.extension_lookups[#world.extension_lookups + 1] = system_name

                return nil
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
    local teammate_unit = { position = { x = 3, y = 0, z = 0 } }
    local radar_player = {
        unit = player_unit,
        position = player_unit.position,
        mode = "local",
        usable = true,
        reason = "ok",
        revision = 1,
    }

    world.ids[player_unit] = PLAYER_ID
    world.ids[teammate_unit] = TEAMMATE_ID
    alive[player_unit] = true
    alive[teammate_unit] = true

    -- What the runtime gate and the scans around the collection would decide.
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
        return {}
    end
    env._cluster_expedition_loot_targets = function(targets)
        return targets
    end
    env._safe_gameplay_time = function()
        return state.t
    end
    env._get_runtime_state = function()
        return true, "ok", state.t, "cm_habs", "mission", "adventure"
    end
    env._collect_screen_highlight_targets = function()
        return {}
    end
    env._scan_minions = function()
        for i = 1, #world.enemies do
            local unit = world.enemies[i].unit

            if alive[unit] then
                mod._tracked_units[unit] = {
                    kind = world.enemies[i].kind,
                    source = "unit_data_system",
                    position = unit.position,
                    meta = {},
                    last_seen_t = state.t,
                }
            end
        end
    end

    local update_internal = named_upvalue(captured.state_gameplay_update, "_update_internal")
    local collect_radar_targets = named_upvalue(update_internal, "_collect_radar_targets")
    local refresh_enemy_threat_states = named_upvalue(update_internal, "_refresh_enemy_threat_states")
    local harness = {
        env = env,
        mod = mod,
        settings = settings,
        world = world,
        state = state,
        alive = alive,
        player_unit = player_unit,
        teammate_unit = teammate_unit,
        radar_player = radar_player,
        threat_state_by_unit = named_upvalue(refresh_enemy_threat_states, "_enemy_threat_state_by_unit"),
    }

    --- Spawns an enemy of a kind, a minion game object targeting a game object id, tracked as the minion scan does.
    function harness:enemy(kind, target_id, distance)
        world.next_id = world.next_id + 1

        local unit = { position = { x = distance or 1, y = 1, z = 0 } }

        world.ids[unit] = world.next_id
        world.objects[world.next_id] = { target_unit_id = target_id }
        world.enemies[#world.enemies + 1] = { unit = unit, kind = kind }
        alive[unit] = true
        mod._tracked_units[unit] = {
            kind = kind,
            source = "unit_data_system",
            position = unit.position,
            meta = {},
            last_seen_t = state.t,
        }

        return unit
    end

    --- Tracks a unit of a kind that is no minion, such as a pickup.
    function harness:item(kind)
        local unit = { position = { x = 2, y = 2, z = 0 } }

        alive[unit] = true
        mod._tracked_units[unit] = {
            kind = kind,
            source = "interactee_system",
            position = unit.position,
            meta = {},
            last_seen_t = state.t,
        }

        return unit
    end

    function harness:retarget(unit, target_id)
        world.objects[world.ids[unit]].target_unit_id = target_id
    end

    --- Builds the radar targets as a scan does and returns them, and by unit.
    function harness:collect()
        local targets = collect_radar_targets()
        local by_unit = {}

        mod._radar_targets = targets

        for i = 1, #targets do
            by_unit[targets[i].unit] = targets[i]
        end

        return targets, by_unit
    end

    --- Runs the threat pass between scans.
    function harness:pass()
        refresh_enemy_threat_states()
    end

    --- Runs one radar update a time step later and returns the published targets by unit.
    function harness:update(dt)
        state.t = state.t + dt
        update_internal(state.t)

        local by_unit = {}
        local targets = mod._radar_targets

        for i = 1, #targets do
            by_unit[targets[i].unit] = targets[i]
        end

        return by_unit
    end

    function harness:forget()
        for unit in pairs(mod._tracked_units) do
            mod._tracked_units[unit] = nil
        end

        for i = #world.enemies, 1, -1 do
            world.enemies[i] = nil
        end
    end

    return harness
end

test("a minion targeting the Radar player reads as targeting it, any other target or none as not", function()
    local harness = new_harness()
    local env = harness.env
    local world = harness.world
    local enemy = harness:enemy(GUNNER, PLAYER_ID)
    local game_session, unit_spawner_manager = env._safe_game_object_access()
    local targets = env._safe_minion_targets_game_object_id

    assert_true(game_session == world.session, "the game session was not read")
    assert_equal(PLAYER_ID, env._safe_unit_game_object_id(harness.player_unit), "the Radar player's game object id")
    assert_equal(true, targets(enemy, PLAYER_ID, game_session, unit_spawner_manager), "the Radar player")
    assert_equal(false, targets(enemy, TEAMMATE_ID, game_session, unit_spawner_manager), "another unit")

    harness:retarget(enemy, INVALID_ID)
    assert_equal(false, targets(enemy, PLAYER_ID, game_session, unit_spawner_manager), "no target")

    -- An id whose unit is gone is still not the Radar player's.
    harness:retarget(enemy, 999)
    assert_equal(false, targets(enemy, PLAYER_ID, game_session, unit_spawner_manager), "a despawned unit's id")
end)

test("a target that cannot be read is unknown, never a guess", function()
    local harness = new_harness()
    local env = harness.env
    local world = harness.world
    local enemy = harness:enemy(GUNNER, PLAYER_ID)
    local game_session, unit_spawner_manager = env._safe_game_object_access()
    local targets = env._safe_minion_targets_game_object_id
    local id = world.ids[enemy]

    assert_nil(targets(enemy, nil, game_session, unit_spawner_manager), "without the Radar player's id")
    assert_nil(targets(enemy, PLAYER_ID, nil, unit_spawner_manager), "without a game session")

    world.objects[id].raises = true
    assert_nil(targets(enemy, PLAYER_ID, game_session, unit_spawner_manager), "a field that cannot be read")

    world.objects[id] = { target_unit_id = "not an id" }
    assert_nil(targets(enemy, PLAYER_ID, game_session, unit_spawner_manager), "a value that is no id")

    world.objects[id] = nil
    assert_nil(targets(enemy, PLAYER_ID, game_session, unit_spawner_manager), "a game object already gone")

    world.ids[enemy] = nil
    assert_nil(targets(enemy, PLAYER_ID, game_session, unit_spawner_manager), "a unit without a game object")
    assert_nil(env._safe_unit_game_object_id(nil), "no unit")

    world.has_session = false
    assert_nil(env._safe_game_object_access(), "a game session while there is none")

    env.Managers.state.unit_spawner = nil
    world.has_session = true
    assert_nil(env._safe_game_object_access(), "a game session without a unit spawner")
end)

test("the read needs nothing but the replicated field, which a client has too", function()
    local harness = new_harness()
    local env = harness.env
    local enemy = harness:enemy(GUNNER, PLAYER_ID)
    local game_session, unit_spawner_manager = env._safe_game_object_access()

    -- Server-side data saying otherwise is never consulted.
    env.BLACKBOARDS[enemy] = { perception = { target_unit = harness.teammate_unit } }

    assert_equal(true, env._safe_minion_targets_game_object_id(enemy, PLAYER_ID, game_session, unit_spawner_manager),
        "the replicated target")
    assert_equal(0, #harness.world.extension_lookups, "an extension was looked up for the read")
end)

test("the players module's field reader keeps what it returns", function()
    local harness = new_harness()
    local env = harness.env
    local world = harness.world
    local unit = harness:enemy(GUNNER, PLAYER_ID)
    local id = world.ids[unit]

    world.objects[id].state = 3
    assert_equal(3, env._safe_unit_game_object_field(unit, "state"), "a field")
    assert_equal(PLAYER_ID, env._safe_unit_game_object_field(unit, "target_unit_id"), "the target field")
    assert_nil(env._safe_unit_game_object_field(unit, "charges"), "a field the object lacks")

    world.has_session = false
    assert_nil(env._safe_unit_game_object_field(unit, "state"), "without a game session")

    world.has_session = true
    world.ids[unit] = nil
    assert_nil(env._safe_unit_game_object_field(unit, "state"), "a unit without a game object")
end)

test("only drawn enemies of a category with threat awareness are read, once per pass", function()
    local harness = new_harness()
    local world = harness.world

    harness.settings.show_enemy_elite_threat = true

    local on_player = harness:enemy(GUNNER, PLAYER_ID)
    local on_teammate = harness:enemy(GUNNER, TEAMMATE_ID)
    local on_nobody = harness:enemy(GUNNER, INVALID_ID)
    local poxwalker = harness:enemy(POXWALKER, PLAYER_ID)
    local pickup = harness:item("pickup_ammo_small")
    local _, by_unit = harness:collect()

    assert_equal("targeting_source", by_unit[on_player].threat_state, "a gunner targeting the Radar player")
    assert_equal("not_targeting_source", by_unit[on_teammate].threat_state, "a gunner targeting a teammate")
    assert_equal("not_targeting_source", by_unit[on_nobody].threat_state, "a gunner targeting nobody")
    assert_nil(by_unit[poxwalker].threat_state, "a horde enemy while horde threat awareness is off")
    assert_nil(by_unit[pickup].threat_state, "a pickup")
    assert_equal(3, world.reads, "reads when the gunners were first drawn")

    -- The next scan takes the states it has, and the pass between scans reads each gunner once.
    harness:collect()
    assert_equal(3, world.reads, "a scan read again what it already had")

    world.reads = 0
    harness:pass()
    assert_equal(3, world.reads, "reads in one pass")
end)

test("the threat pass reads again between scans and keeps only the drawn enemies", function()
    local harness = new_harness()

    harness.settings.show_enemy_elite_threat = true

    local first = harness:enemy(GUNNER, TEAMMATE_ID)
    local second = harness:enemy(GUNNER, PLAYER_ID)
    local _, by_unit = harness:collect()

    assert_equal("not_targeting_source", by_unit[first].threat_state, "before the switch")

    harness:retarget(first, PLAYER_ID)
    harness:pass()
    assert_equal("targeting_source", by_unit[first].threat_state, "the pass did not update the drawn target")

    harness.world.objects[harness.world.ids[second]].raises = true
    harness:pass()
    assert_equal("unknown", by_unit[second].threat_state, "a read that failed kept the last state")

    -- A dead enemy leaves the targets at the next scan and its state at the next pass.
    harness.alive[second] = false
    harness:collect()
    harness:pass()
    assert_nil(harness.threat_state_by_unit[second], "a dead enemy's state was kept")
    assert_equal("targeting_source", harness.threat_state_by_unit[first], "a drawn enemy's state was dropped")
end)

test("an enemy the marker limit cuts is never read", function()
    local harness = new_harness({ max_markers = 10 })

    harness.settings.show_enemy_elite_threat = true

    for distance = 1, 30 do
        harness:enemy(GUNNER, PLAYER_ID, distance)
    end

    local targets = harness:collect()

    assert_equal(10, #targets, "the marker limit")
    assert_equal(10, harness.world.reads, "reads when the limit keeps ten of thirty gunners")

    harness:collect()
    harness:pass()
    assert_equal(20, harness.world.reads, "a scan or pass read a gunner the limit cuts")
end)

test("a new Radar player is read against at once, and nothing of the old one is kept", function()
    local harness = new_harness()
    local radar_player = harness.radar_player

    harness.settings.show_enemy_elite_threat = true

    local on_player = harness:enemy(GUNNER, PLAYER_ID)
    local on_teammate = harness:enemy(GUNNER, TEAMMATE_ID)
    local by_unit = harness:update(0.3)

    assert_equal("targeting_source", by_unit[on_player].threat_state, "the local player")
    assert_equal("not_targeting_source", by_unit[on_teammate].threat_state, "a teammate")

    -- The local player dies and spectates the teammate.
    harness.world.reads = 0
    radar_player.unit = harness.teammate_unit
    radar_player.position = harness.teammate_unit.position
    radar_player.mode = "spectating"
    radar_player.revision = 2
    by_unit = harness:update(0.016)

    assert_equal("not_targeting_source", by_unit[on_player].threat_state, "the local player while spectating")
    assert_equal("targeting_source", by_unit[on_teammate].threat_state, "the spectated teammate")
    assert_equal(2, harness.world.reads, "reads for the new Radar player")

    local count = 0

    for unit, threat_state in pairs(harness.threat_state_by_unit) do
        count = count + 1
        assert_equal(by_unit[unit].threat_state, threat_state, "a state of the old Radar player was kept")
    end

    assert_equal(2, count, "states kept")

    -- A Radar player without a game object leaves every enemy unknown.
    harness.world.ids[harness.teammate_unit] = nil
    radar_player.revision = 3
    by_unit = harness:update(0.016)

    assert_equal("unknown", by_unit[on_teammate].threat_state, "a Radar player without a game object")
end)

test("with every category off nothing is read, and turning one on reads at once", function()
    local harness = new_harness()
    local mod = harness.mod
    local world = harness.world
    local gunner = harness:enemy(GUNNER, PLAYER_ID)
    local by_unit = harness:update(0.3)

    assert_nil(by_unit[gunner].threat_state, "a gunner with every category off")
    assert_equal(0, world.reads, "reads with every category off")

    world.id_lookups = 0
    harness:pass()
    assert_equal(0, world.id_lookups, "the pass looked the Radar player up with every category off")

    harness.settings.show_enemy_elite_threat = true
    mod.on_setting_changed("show_enemy_elite_threat")
    assert_equal(0, mod._next_enemy_threat_t, "the threat pass is not due at once")
    assert_equal(0, mod._next_scan_t, "the scan is not due at once")

    by_unit = harness:update(0.016)
    assert_equal("targeting_source", by_unit[gunner].threat_state, "the gunner once elites show threat awareness")

    harness.settings.show_enemy_elite_threat = false
    mod.on_setting_changed("show_enemy_elite_threat")
    by_unit = harness:update(0.016)
    assert_nil(by_unit[gunner].threat_state, "the gunner kept its state once elites stopped showing it")
    assert_nil(next(harness.threat_state_by_unit), "states were kept with every category off")
end)

test("a pooled target never keeps the threat state of the target it held before", function()
    local harness = new_harness()

    harness.settings.show_enemy_elite_threat = true

    local gunner = harness:enemy(GUNNER, PLAYER_ID)
    local targets = harness:collect()
    local pooled = targets[1]

    assert_equal(gunner, pooled.unit, "the first target")
    assert_equal("targeting_source", pooled.threat_state, "the gunner's state")

    harness:forget()

    local pickup = harness:item("pickup_ammo_small")

    targets = harness:collect()

    assert_equal(pooled, targets[1], "the pool did not hand out the same table")
    assert_equal(pickup, targets[1].unit, "the second target")
    assert_nil(targets[1].threat_state, "the pickup kept the gunner's threat state")
end)

test("the states go when the radar stops and when the mission ends", function()
    local harness = new_harness()
    local mod = harness.mod

    harness.settings.show_enemy_elite_threat = true

    local gunner = harness:enemy(GUNNER, PLAYER_ID)

    harness:update(0.3)
    assert_equal("targeting_source", harness.threat_state_by_unit[gunner], "the state while drawn")

    harness.settings.enable_radar = false
    harness:update(0.016)
    assert_nil(next(harness.threat_state_by_unit), "states were kept while the radar is off")

    harness.settings.enable_radar = true
    harness:update(0.3)
    assert_equal("targeting_source", harness.threat_state_by_unit[gunner], "the state once the radar is back")

    mod.on_game_state_changed("exit", "GameplayStateRun")
    assert_nil(next(harness.threat_state_by_unit), "states were kept past the mission")
end)

-- --------------------------------------------------------------------------------------------
-- The enemy's look
-- --------------------------------------------------------------------------------------------

local CONFIGURED_COLORS = {
    enemy_threat_neutral_frame = NEUTRAL_FRAME_COLOR,
    enemy_threat_targeting_frame = TARGETING_FRAME_COLOR,
    enemy_threat_backplate = BACKPLATE_COLOR,
    enemy_threat_acquisition_flash = FLASH_COLOR,
}

--- Loads the HUD element against a fake UI stack and returns its `_target_visual`, `_build_draw_cache`
-- and the helpers that size a drawn marker, reading the given enemy definitions or the fake ones above.
local function load_hud(settings, definitions)
    local mod = {}
    local env

    definitions = definitions or DEFINITIONS

    function mod:get(setting_id)
        return settings and settings[setting_id] or nil
    end

    function mod:info()
    end

    function mod:get_radar_color(prefix, fallback)
        return CONFIGURED_COLORS[prefix] or fallback
    end

    function mod:get_enemy_radar_definition(kind)
        return definitions[kind]
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
        ["scripts/settings/ui/ui_settings"] = {},
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

    return {
        target_visual = named_upvalue(draw_internal, "_target_visual"),
        build_draw_cache = named_upvalue(draw_internal, "_build_draw_cache"),
        presentations = named_upvalue(named_upvalue(draw_internal, "_target_visual"), "PRESENTATIONS"),
        target_marker_sizes = named_upvalue(draw_internal, "_target_marker_sizes"),
        centre_marker_layer = named_upvalue(named_upvalue(draw_internal, "_apply_marker_widget"),
            "RadarHudWidgets").centre_marker_layer,
    }
end

--- A draw cache as `_draw_internal` leaves it, with an empty threat state table and the frame's time.
local function new_draw_cache(hud, draw_t)
    local draw_cache = hud.build_draw_cache(draw_t)

    draw_cache.coherency_state_by_unit = {}
    draw_cache.threat_state_by_unit = {}
    draw_cache.draw_t = draw_t

    return draw_cache
end

local function enemy_target(kind, unit, threat_state)
    return {
        kind = kind,
        unit = unit or {},
        threat_state = threat_state,
        render_layer = RENDER_LAYER_BY_KIND[kind] or 0,
        distance_sq_3d = 144,
        meta = {},
    }
end

test("with threat awareness off, an enemy marker looks exactly as before", function()
    local hud = load_hud()
    local draw_cache = new_draw_cache(hud, 10)

    for _, kind in ipairs({ GUNNER, POXWALKER, MONSTROSITY }) do
        local visual = hud.target_visual(enemy_target(kind, {}, nil), draw_cache)

        for f = 1, #THREAT_FIELDS do
            assert_nil(visual[THREAT_FIELDS[f]], kind .. " has " .. THREAT_FIELDS[f])
        end
    end

    assert_true(hud.target_visual(enemy_target(GUNNER, {}, nil), draw_cache) == draw_cache.enemy_visual_by_kind[GUNNER],
        "an enemy without threat awareness no longer draws its kind's shared visual")
    assert_nil(next(draw_cache.threat_state_by_unit), "an enemy without threat awareness kept a threat state")
end)

test("an enemy sits on the backplate inside the frame, in the targeting colour only while it targets the Radar player",
    function()
        local hud = load_hud()
        local draw_cache = new_draw_cache(hud, 10)

        for _, kind in ipairs({ GUNNER, POXWALKER, MONSTROSITY }) do
            local before = clone(hud.target_visual(enemy_target(kind, {}, nil), draw_cache))
            local extent = before.bracket_base_size or before.size

            for _, threat_state in ipairs({ "targeting_source", "not_targeting_source", "unknown" }) do
                local label = kind .. " / " .. threat_state
                local visual = hud.target_visual(enemy_target(kind, {}, threat_state), draw_cache)

                for f = 1, #BASE_FIELDS do
                    local field = BASE_FIELDS[f]

                    assert_true(same_values(before[field], visual[field]), label .. " changed the marker's " .. field)
                end

                assert_equal(BACKPLATE, visual.plate_icon, label .. " backplate")
                assert_true(visual.plate_color == draw_cache.enemy_threat_backplate_color
                    and same_values(BACKPLATE_COLOR, visual.plate_color), label .. " backplate colour")
                assert_equal(extent * 2, visual.plate_base_size, label .. " backplate size")
                assert_equal(FRAME, visual.ring_icon, label .. " frame")
                assert_equal(extent * 2, visual.ring_base_size, label .. " frame size")
                assert_true(same_values(threat_state == "targeting_source" and TARGETING_FRAME_COLOR
                    or NEUTRAL_FRAME_COLOR, visual.ring_color), label .. " frame colour")
                assert_nil(visual.flash_icon, label .. " flashed when first seen")
            end
        end

        -- Each kind's shared visual and the boss presentation stay as they were.
        for _, kind in ipairs({ GUNNER, POXWALKER }) do
            local shared = draw_cache.enemy_visual_by_kind[kind]

            for f = 1, #THREAT_FIELDS do
                assert_nil(shared[THREAT_FIELDS[f]], kind .. "'s shared visual took " .. THREAT_FIELDS[f])
            end
        end

        for f = 1, #THREAT_FIELDS do
            assert_nil(hud.presentations[MONSTROSITY][THREAT_FIELDS[f]],
                "the monstrosity presentation took " .. THREAT_FIELDS[f])
        end
    end)

test("the frame and backplate are drawn twice the brackets, the marker's visible size, not twice its background box",
    function()
        local _, definition_env = load_definitions({})
        local hud = load_hud(nil, definition_env.ENEMY_RADAR_DEFINITION_BY_KIND)
        local draw_cache = new_draw_cache(hud, 10)
        local layer_style = { offset = { 0, 0, 0 }, size = { 0, 0 } }
        local kinds = {
            "enemy_cultist_flamer", "enemy_renegade_gunner", "enemy_renegade_assault", "enemy_cultist_melee",
            "enemy_chaos_poxwalker", MONSTROSITY,
        }

        for _, kind in ipairs(kinds) do
            for _, scale in ipairs({ 0.6, 1, 1.5, 2 }) do
                local label = kind .. " at scale " .. scale
                local target = enemy_target(kind, {}, "not_targeting_source")

                draw_cache.icon_scale_by_kind[kind] = scale

                local visual = hud.target_visual(target, draw_cache)
                local marker_size, bracket_size = hud.target_marker_sizes(target, visual, draw_cache)
                local icon_base_size = visual.background_base_size or visual.size

                hud.centre_marker_layer(layer_style, 0, 0, marker_size, visual.ring_base_size, icon_base_size, 0)
                local frame_size = layer_style.size[1]

                hud.centre_marker_layer(layer_style, 0, 0, marker_size, visual.plate_base_size, icon_base_size, 0)
                assert_equal(frame_size, layer_style.size[1], label .. " backplate does not fill the frame")
                assert_true(frame_size <= bracket_size * 2 + 1, label .. " frame of " .. frame_size
                    .. " is more than twice the brackets of " .. bracket_size)

                -- Below scale 1 a category's minimum size can hold the brackets above the marker's proportions.
                if scale >= 1 then
                    assert_true(frame_size >= bracket_size * 2 - 1, label .. " frame of " .. frame_size
                        .. " is less than twice the brackets of " .. bracket_size)
                end
            end
        end
    end)

test("acquiring the Radar player flashes once, growing outward; continuing, losing it or a first sight does not", function()
    local hud = load_hud()
    local draw_cache = new_draw_cache(hud, 10)
    local unit = {}

    local function frame(t, threat_state)
        draw_cache.draw_t = t

        return hud.target_visual(enemy_target(GUNNER, unit, threat_state), draw_cache)
    end

    assert_nil(frame(10, "not_targeting_source").flash_icon, "an enemy flashed when first seen")

    local start = frame(10.016, "targeting_source")

    assert_equal(FLASH, start.flash_icon, "acquiring the Radar player did not flash")
    assert_equal(0, start.flash_color[1], "the flash does not start faded out")
    assert_equal(start.ring_base_size, start.flash_base_size, "the flash does not start at the frame")

    local middle = frame(10.416, "targeting_source")

    assert_equal(FLASH_COLOR[1], middle.flash_color[1], "the flash is not at full opacity half way")
    assert_true(middle.flash_color[2] == FLASH_COLOR[2] and middle.flash_color[3] == FLASH_COLOR[3]
        and middle.flash_color[4] == FLASH_COLOR[4], "the flash is not in the acquisition colour")
    assert_true(middle.flash_base_size > start.ring_base_size, "the flash does not grow outward")
    assert_nil(frame(10.82, "targeting_source").flash_icon, "the flash outlasted 0.8 seconds")
    assert_nil(frame(10.836, "targeting_source").flash_icon, "targeting on started the flash again")

    local lost = frame(10.852, "not_targeting_source")

    assert_nil(lost.flash_icon, "losing the Radar player flashed")
    assert_true(same_values(NEUTRAL_FRAME_COLOR, lost.ring_color), "the frame kept the targeting colour")

    -- Turning back flashes again, and turning away ends that flash at once.
    assert_equal(FLASH, frame(10.868, "targeting_source").flash_icon, "reacquiring the Radar player did not flash")
    assert_nil(frame(10.884, "not_targeting_source").flash_icon, "a flash outlasted the targeting")

    -- First seen while it already targets the Radar player, an enemy shows the frame at once and no flash.
    local fresh = hud.target_visual(enemy_target(GUNNER, {}, "targeting_source"), draw_cache)

    assert_nil(fresh.flash_icon, "an enemy first seen targeting the Radar player flashed")
    assert_true(same_values(TARGETING_FRAME_COLOR, fresh.ring_color), "it did not show the targeting frame at once")
end)

test("a target that could not be read never starts a flash, either way round", function()
    local hud = load_hud()
    local draw_cache = new_draw_cache(hud, 10)
    local unit = {}

    local function frame(t, threat_state)
        draw_cache.draw_t = t

        return hud.target_visual(enemy_target(GUNNER, unit, threat_state), draw_cache)
    end

    frame(10, "not_targeting_source")
    assert_true(same_values(NEUTRAL_FRAME_COLOR, frame(10.016, "unknown").ring_color), "an unknown target's frame")
    assert_nil(frame(10.032, "targeting_source").flash_icon, "an unknown target turning into the Radar player flashed")
    assert_true(same_values(NEUTRAL_FRAME_COLOR, frame(10.048, "unknown").ring_color),
        "an unknown target kept the targeting frame")
    assert_nil(frame(10.064, "targeting_source").flash_icon, "targeting through an unknown target flashed")
end)

test("an enemy back on the radar after a while, or seen for a new Radar player, does not flash", function()
    local hud = load_hud()
    local draw_cache = new_draw_cache(hud, 10)
    local unit = {}

    local function frame(t, threat_state)
        draw_cache.draw_t = t

        return hud.target_visual(enemy_target(GUNNER, unit, threat_state), draw_cache)
    end

    frame(10, "not_targeting_source")
    assert_nil(frame(11, "targeting_source").flash_icon, "an enemy back on the radar after a second flashed")

    -- A new Radar player starts a new state table, as `_draw_internal` does for a new revision.
    frame(11.016, "not_targeting_source")
    draw_cache.threat_state_by_unit = {}
    assert_nil(frame(11.032, "targeting_source").flash_icon, "an enemy flashed for a new Radar player")
end)

test("two enemies of one kind keep their own look and flash", function()
    local hud = load_hud()
    local draw_cache = new_draw_cache(hud, 10)
    local first, second = {}, {}

    hud.target_visual(enemy_target(GUNNER, first, "not_targeting_source"), draw_cache)
    hud.target_visual(enemy_target(GUNNER, second, "not_targeting_source"), draw_cache)
    draw_cache.draw_t = 10.016

    local acquiring = hud.target_visual(enemy_target(GUNNER, first, "targeting_source"), draw_cache)
    local other = hud.target_visual(enemy_target(GUNNER, second, "not_targeting_source"), draw_cache)

    assert_true(acquiring ~= other, "two enemies share one visual")
    assert_equal(FLASH, acquiring.flash_icon, "the acquiring enemy did not flash")
    assert_nil(other.flash_icon, "the other enemy flashed")
    assert_true(same_values(TARGETING_FRAME_COLOR, acquiring.ring_color), "the acquiring enemy's frame")
    assert_true(same_values(NEUTRAL_FRAME_COLOR, other.ring_color), "the other enemy's frame")
end)

test("the flash runs on every frame between threat reads, and a colour change does not restart it", function()
    local hud = load_hud()
    local draw_cache = new_draw_cache(hud, 10)
    local unit = {}
    local target = enemy_target(GUNNER, unit, "not_targeting_source")

    hud.target_visual(target, draw_cache)
    target.threat_state = "targeting_source"

    local previous = -1

    for frame = 1, 24 do
        draw_cache.draw_t = 10 + frame * 0.016

        local alpha = hud.target_visual(target, draw_cache).flash_color[1]

        assert_true(alpha > previous, "the flash did not fade in smoothly at frame " .. frame)
        previous = alpha
    end

    -- A colour change reaches the running flash without starting it over.
    draw_cache.enemy_threat_acquisition_flash_color = { 100, 1, 2, 3 }
    draw_cache.draw_t = 10 + 25 * 0.016

    local recoloured = hud.target_visual(target, draw_cache)

    assert_equal(FLASH, recoloured.flash_icon, "a colour change ended the flash")
    assert_true(recoloured.flash_color[1] <= 100 and recoloured.flash_color[1] > 90,
        "a colour change started the flash over")
    assert_equal(1, recoloured.flash_color[2], "the flash did not take the new colour")

    previous = 256

    for frame = 26, 49 do
        draw_cache.draw_t = 10 + frame * 0.016

        local visual = hud.target_visual(target, draw_cache)

        if visual.flash_icon == nil then
            break
        end

        assert_true(visual.flash_color[1] <= previous, "the flash did not fade out smoothly at frame " .. frame)
        previous = visual.flash_color[1]
    end
end)

test("an enemy a Cyber Mastiff pins keeps its fill suppressed: the frame stays, the backplate goes", function()
    local hud = load_hud()
    local draw_cache = new_draw_cache(hud, 10)
    local target = enemy_target(GUNNER, {}, "targeting_source")

    target.disabled_by_mastiff = true

    local visual = hud.target_visual(target, draw_cache)

    assert_nil(visual.plate_icon, "a pinned enemy shows a backplate")
    assert_equal(FRAME, visual.ring_icon, "a pinned enemy lost its frame")

    target.disabled_by_mastiff = false
    assert_equal(BACKPLATE, hud.target_visual(target, draw_cache).plate_icon, "a freed enemy got no backplate back")
end)

test("the threat layers drop by the enemy's render layer, below every marker's icon", function()
    local hud = load_hud()
    local draw_cache = new_draw_cache(hud, 10)

    for _, kind in ipairs({ GUNNER, POXWALKER, MONSTROSITY }) do
        local visual = hud.target_visual(enemy_target(kind, {}, "not_targeting_source"), draw_cache)

        assert_equal(RENDER_LAYER_BY_KIND[kind], visual.decoration_layer_drop, kind .. " layer drop")
    end
end)

test("a boss keeps its distance text inside the threat look", function()
    local hud = load_hud({ show_boss_distance_text = true })
    local draw_cache = new_draw_cache(hud, 10)
    local before = hud.target_visual(enemy_target(MONSTROSITY, {}, nil), draw_cache)
    local visual = hud.target_visual(enemy_target(MONSTROSITY, {}, "targeting_source"), draw_cache)

    assert_true(before.value_text ~= nil, "the boss has no distance text to keep")
    assert_equal(before.value_text, visual.value_text, "the distance text")
    assert_true(same_values(before.value_text_color, visual.value_text_color), "the distance text colour")
    assert_equal(before.value_text_anchor, visual.value_text_anchor, "the distance text anchor")
    assert_equal(FRAME, visual.ring_icon, "the boss frame")
end)

test("the bosses whose Havoc emblem fills its box draw it smaller inside the frame, and only there", function()
    local hud = load_hud({ show_boss_distance_text = true })
    local draw_cache = new_draw_cache(hud, 10)

    for _, kind in ipairs({ "enemy_daemonhost", "enemy_captain", "enemy_karnak_twin" }) do
        local before = hud.target_visual(enemy_target(kind, {}, nil), draw_cache)
        local visual = hud.target_visual(enemy_target(kind, {}, "not_targeting_source"), draw_cache)

        assert_nil(before.icon_scale, kind .. " draws its icon smaller without threat awareness")
        assert_equal(0.75, visual.icon_scale, kind .. " icon scale inside the frame")
        assert_equal(before.size * 2, visual.ring_base_size, kind .. " frame size changed with the icon")
        assert_nil(hud.presentations[kind].icon_scale, kind .. "'s presentation took the icon scale")
    end

    -- The Monstrosity's skull and every enemy with a definition keep their icon at full size.
    for _, kind in ipairs({ MONSTROSITY, GUNNER, POXWALKER }) do
        assert_nil(hud.target_visual(enemy_target(kind, {}, "targeting_source"), draw_cache).icon_scale,
            kind .. " draws its icon smaller inside the frame")
    end
end)

test("an enemy's threat visual is reused from frame to frame and allocates nothing", function()
    local hud = load_hud()
    local draw_cache = new_draw_cache(hud, 10)
    local target = enemy_target(GUNNER, {}, "not_targeting_source")
    local first = hud.target_visual(target, draw_cache)

    draw_cache.draw_t = 10.016

    assert_true(hud.target_visual(target, draw_cache) == first, "the visual was built anew for the same enemy")

    -- The game runs with the JIT off; compiled traces would count as garbage here.
    local jit_api = rawget(_G, "jit")

    if jit_api then
        jit_api.off()
        jit_api.flush()
    end

    collectgarbage("collect")
    collectgarbage("stop")

    local before = collectgarbage("count")

    for frame = 1, 1000 do
        draw_cache.draw_t = 10.016 + frame * 0.016
        target.threat_state = frame % 120 < 60 and "targeting_source" or "not_targeting_source"
        hud.target_visual(target, draw_cache)
    end

    local kilobytes = collectgarbage("count") - before

    collectgarbage("restart")

    if jit_api then
        jit_api.on()
    end

    assert_true(kilobytes < 0.5, string.format("1000 frames, flashes included, allocated %.2f KB", kilobytes))
end)

test("the settings and colours are named in every language the facing settings have", function()
    local chunk = assert(loadfile(LOCALIZATION_PATH))

    setfenv(chunk, setmetatable({
        Localize = function(key)
            return key
        end,
    }, { __index = _G }))

    local localization = chunk()
    local reference = localization.show_enemy_boss_facing
    local keys = {
        "show_enemy_threat_tooltip",
        "enemy_threat_colors_group",
    }

    for i = 1, #THREAT_SETTING_IDS do
        keys[#keys + 1] = THREAT_SETTING_IDS[i]
    end

    for prefix in pairs(CONFIGURED_COLORS) do
        keys[#keys + 1] = prefix .. "_color"
        keys[#keys + 1] = prefix .. "_color_slider_tooltip"
    end

    for _, key in ipairs(keys) do
        local entry = localization[key]

        assert_true(type(entry) == "table", key .. " is missing")

        for language in pairs(reference) do
            assert_true(type(entry[language]) == "string" and entry[language] ~= "" and entry[language] ~= key,
                key .. " has no " .. language)
        end
    end

    assert_equal("Boss threat awareness", localization.show_enemy_boss_threat.en, "English label")
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
