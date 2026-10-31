-- How nearby highlights become outlines on their units. Installs the real outline module, and
-- for the collection test the real runtime helpers too, against a fake engine that records
-- every material layer, colour and culling call, so the lifecycle is tested as it ships.
local OUTLINES_PATH = "Radar/scripts/mods/Radar/Radar_highlight_outlines.lua"
local HELPERS_PATH = "Radar/scripts/mods/Radar/Radar_runtime_helpers.lua"
local OUTLINE_MATERIAL = "content/characters/materials/minion_outline"

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

local function same_mesh_list(first, second)
    if first == nil or second == nil then
        return first == second
    end

    if #first ~= #second then
        return false
    end

    for i = 1, #first do
        if first[i] ~= second[i] then
            return false
        end
    end

    return true
end

-- `engine` is the fake engine state shared by every module installed into one harness, so a
-- second install of the outline module into a new environment behaves like a Radar reload.
local function new_engine()
    return {
        alive = {},
        data = {},
        layers = {},
        culling = {},
        occluded = {},
        game_outlines = {},
        calls = 0,
        color_writes = 0,
        crashes = 0,
        cinematic = false,
        occlusion_queries = {},
        raycasts = {},
        infos = {},
        t = 0,
    }
end

local function new_harness(options)
    options = options or {}

    local engine = options.engine or new_engine()
    local settings = options.settings or {}
    local mod = { _logged_units = {}, hooks = {} }

    function mod:get(setting_id)
        return settings[setting_id]
    end

    function mod:hook(object, method, handler)
        self.hooks[object .. "." .. method] = handler
    end

    function mod:info(message, ...)
        engine.infos[#engine.infos + 1] = string.format(message, ...)
    end

    function mod:is_nearby_highlight_visible_only()
        return settings.nearby_highlight_visible_only == true
    end

    if options.previous_on_disabled then
        mod.on_disabled = options.previous_on_disabled
    end

    if options.previous_on_unload then
        mod.on_unload = options.previous_on_unload
    end

    local env = { mod = mod, ALIVE = engine.alive, POSITION_LOOKUP = {} }

    setmetatable(env, { __index = _G })

    local function count()
        engine.calls = engine.calls + 1
    end

    -- As the engine does with the fourth argument of add_material_layer: child units take the
    -- layer too, each with its own count.
    local function add_layer(unit, layer, material, meshes)
        local entry = engine.layers[unit] or { added = 0 }

        entry.added = entry.added + 1
        entry.layer = layer
        entry.material = material
        entry.meshes = meshes
        -- On straight away, so the spec sees the module switch it off itself.
        entry.on = true
        engine.layers[unit] = entry

        for _, child in ipairs(unit.children or {}) do
            add_layer(child, layer, material, meshes)
        end
    end

    env.Unit = {
        alive = function(unit)
            count()
            return engine.alive[unit] == true
        end,
        get_data = function(unit, key)
            count()
            return engine.data[unit] and engine.data[unit][key]
        end,
        set_data = function(unit, key, value)
            count()
            engine.data[unit] = engine.data[unit] or {}
            engine.data[unit][key] = value
        end,
        num_meshes = function(unit)
            count()
            return unit.meshes or 1
        end,
        has_node = function(unit, node)
            count()
            return unit.root_node == node
        end,
        add_material_layer = function(unit, layer, material, _, _, meshes)
            count()

            if unit.refuse then
                error("the engine refused the layer")
            end

            if meshes ~= nil and engine.reject_mesh_whitelist then
                error("bad argument #6")
            end

            add_layer(unit, layer, material, meshes)
        end,
        -- The real call crashes the game on a dead unit and on any mesh it walks that lacks the
        -- layer, which pcall does not catch, so those count as crashes instead of raising.
        remove_material_layer = function(unit, layer, walk_child_units, meshes)
            count()

            if engine.remove_error then
                error("the engine refused the removal")
            end

            local entry = engine.layers[unit]
            local removed = entry and entry.removed or 0

            if engine.alive[unit] ~= true or not entry or removed >= entry.added or walk_child_units
                or not same_mesh_list(meshes, entry.meshes) or layer ~= entry.layer then
                engine.crashes = engine.crashes + 1
                return
            end

            entry.removed = removed + 1
        end,
        set_material_layer = function(unit, layer, on)
            count()
            engine.layers[unit].on = on
        end,
        set_vector3_for_material = function(unit, layer, variable, value)
            count()
            engine.color_writes = engine.color_writes + 1
            -- Child units take the layer with their parent, so a child has an entry of its own.
            engine.layers[unit] = engine.layers[unit] or { added = 0 }
            engine.layers[unit].color = value
            engine.layers[unit].color_variable = variable
        end,
        get_child_units = function(unit)
            count()
            return unit.children or {}
        end,
        set_unit_culling = function(unit, enabled)
            count()
            engine.culling[unit] = enabled
        end,
    }
    env.ScriptUnit = {
        has_extension = function(unit, system_name)
            if system_name == "locomotion_system" then
                return unit.locomotion
            end

            return nil
        end,
    }
    env.Vector3 = function(x, y, z)
        return { x = x, y = y, z = z }
    end
    env.Managers = {
        state = {
            cinematic = {
                cinematic_active = function()
                    return engine.cinematic
                end,
            },
            physics = {
                physics_world = function()
                    return "physics_world"
                end,
            },
        },
    }
    -- Read by the runtime helpers while they install, so it has to exist before.
    env.PhysicsWorld = {
        immediate_raycast = function(physics_world, origin, direction, distance, mode, types_key, types, filter_key,
                                     filter)
            if engine.raycast_error then
                error("the engine refused the raycast")
            end

            engine.raycasts[#engine.raycasts + 1] = {
                physics_world = physics_world,
                distance = distance,
                mode = mode,
                types = types_key == "types" and types or nil,
                filter = filter_key == "collision_filter" and filter or nil,
            }

            return engine.hits
        end,
    }
    env.Actor = {
        unit = function(actor)
            return actor.unit
        end,
    }

    if options.with_helpers then
        assert(loadfile(HELPERS_PATH))()(env)
    else
        env._safe_unit_alive = function(unit)
            return unit ~= nil and engine.alive[unit] == true
        end
        env._safe_extension_system = function()
            return nil
        end
        env._safe_gameplay_time = function()
            return engine.t
        end
        -- As in the runtime helpers: only in debug mode, once per key.
        env._log_once = function(key, text)
            if settings.debug_mode ~= true or mod._logged_units[key] then
                return
            end

            mod._logged_units[key] = true
            mod:info(text)
        end
    end

    env._safe_unit_outline_extension = function(unit)
        return engine.game_outlines[unit]
    end

    function mod:get_hud_player_camera_position()
        return { x = 0, y = 0, z = 1.7 }
    end

    if not options.with_helpers then
        function mod:is_hud_target_hidden_by_geometry(camera_position, world_position, unit)
            engine.occlusion_queries[#engine.occlusion_queries + 1] = {
                camera_position = camera_position,
                world_position = world_position,
                unit = unit,
            }

            return engine.occluded[unit] == true
        end
    end

    assert(loadfile(OUTLINES_PATH))()(env)

    return {
        env = env,
        mod = mod,
        engine = engine,
        settings = settings,
    }
end

local function new_unit(engine, fields)
    local unit = fields or {}

    engine.alive[unit] = true

    return unit
end

local COLOR = { 255, 51, 102, 204 }
local ANCHOR = { x = 1, y = 2, z = 3 }

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("an outlined unit gets the minion outline layer, switched off until the sync shows it", function()
    local harness = new_harness()
    local unit = new_unit(harness.engine)

    assert_equal(true, harness.env._mark_highlight_outline(unit, COLOR, ANCHOR), "the unit was not outlined")

    local layer = harness.engine.layers[unit]

    assert_equal(1, layer.added, "the layer was not added once")
    assert_equal(OUTLINE_MATERIAL, layer.material, "the layer is not built from the minion outline material")
    assert_equal(false, layer.on, "the new layer shows before the sync")
    assert_equal(true, harness.engine.data[unit][layer.layer], "the unit is not marked as carrying the layer")

    harness.env._sync_highlight_outlines()

    assert_equal(true, layer.on, "the sync did not show the outline")
    assert_equal(false, harness.engine.culling[unit], "the outlined unit is still culled")
    assert_equal(true, layer.color ~= nil, "the shown outline did not get its colour")
end)

test("the layer is added once per unit, also after Radar is reloaded", function()
    local harness = new_harness()
    local unit = new_unit(harness.engine)

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()
    harness.env._sync_highlight_outlines()
    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)

    local reloaded = new_harness({ engine = harness.engine })

    assert_equal(true, reloaded.env._mark_highlight_outline(unit, COLOR, ANCHOR), "the reloaded module refused the unit")
    assert_equal(1, harness.engine.layers[unit].added, "the layer was added again")
end)

-- In game, a colour written only while the layer was off showed the material's default colour
-- once the outline was switched on, and the parts of a multi-part prop kept it too.
test("the colour is written as RGB from 0 to 1 when the outline shows, also to child units", function()
    local harness = new_harness()
    local grandchild = new_unit(harness.engine)
    local child = new_unit(harness.engine, { children = { grandchild } })
    local unit = new_unit(harness.engine, { children = { child } })

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)

    assert_equal(0, harness.engine.color_writes, "the colour was written while the outline was off")

    harness.env._sync_highlight_outlines()

    local color = harness.engine.layers[unit].color

    assert_equal("outline_color", harness.engine.layers[unit].color_variable, "the wrong material variable was set")
    assert_equal(0.2, color.x, "red is not scaled to 0..1")
    assert_equal(0.4, color.y, "green is not scaled to 0..1")
    assert_equal(0.8, color.z, "blue is not scaled to 0..1")
    assert_equal(color, harness.engine.layers[child].color, "a child unit kept the material's default colour")
    assert_equal(color, harness.engine.layers[grandchild].color, "a grandchild unit kept the material's default colour")

    local writes = harness.engine.color_writes

    harness.env._mark_highlight_outline(unit, { 128, 51, 102, 204 }, ANCHOR)
    harness.env._sync_highlight_outlines()

    assert_equal(writes, harness.engine.color_writes,
        "an unchanged colour was written again; alpha is not an outline channel")

    harness.env._mark_highlight_outline(unit, { 255, 0, 102, 204 }, ANCHOR)

    assert_equal(writes + 3, harness.engine.color_writes, "a changed colour of a shown outline was not written at once")
    assert_equal(0, harness.engine.layers[child].color.x, "the changed colour did not reach the child units")
end)

test("culling is switched off again twice a second while an outline shows", function()
    local harness = new_harness()
    local unit = new_unit(harness.engine)

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()
    -- Another mod removing its own outline from the unit switches culling back on.
    harness.engine.culling[unit] = true
    harness.engine.t = 0.25
    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()

    assert_equal(true, harness.engine.culling[unit], "culling was refreshed before half a second passed")

    harness.engine.t = 0.5
    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()

    assert_equal(false, harness.engine.culling[unit], "culling switched back on by other code stayed on")
end)

test("a unit a player carries is not outlined and gets no bracket", function()
    local harness = new_harness()
    local locomotion = { state = "sleep" }
    local unit = new_unit(harness.engine, { locomotion = locomotion })

    function locomotion:current_state()
        return self.state
    end

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()

    assert_equal(true, harness.engine.layers[unit].on, "the luggable on the floor was not outlined")

    locomotion.state = "carried"

    assert_equal(true, harness.env._mark_highlight_outline(unit, COLOR, ANCHOR), "the carried unit fell back to a bracket")

    harness.env._sync_highlight_outlines()

    assert_equal(false, harness.engine.layers[unit].on, "the carried unit kept its outline in the player's hands")

    locomotion.state = "engine_physics"
    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()

    assert_equal(true, harness.engine.layers[unit].on, "the dropped unit did not get its outline back")
    assert_equal(1, harness.engine.layers[unit].added, "the dropped unit got a second layer")
end)

test("a unit the collection no longer marks is switched off, culled again and forgotten", function()
    local harness = new_harness()
    local kept = new_unit(harness.engine)
    local dropped = new_unit(harness.engine)

    harness.env._mark_highlight_outline(kept, COLOR, ANCHOR)
    harness.env._mark_highlight_outline(dropped, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()
    harness.env._mark_highlight_outline(kept, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()

    assert_equal(true, harness.engine.layers[kept].on, "the marked unit lost its outline")
    assert_equal(false, harness.engine.layers[dropped].on, "the unmarked unit kept its outline")
    assert_equal(true, harness.engine.culling[dropped], "the unmarked unit is no longer culled")

    harness.env._mark_highlight_outline(dropped, COLOR, ANCHOR)

    assert_equal(1, harness.engine.layers[dropped].added, "a returning unit got a second layer")
end)

test("a unit that cannot carry the outline keeps its bracket", function()
    local harness = new_harness()
    local mark = harness.env._mark_highlight_outline
    local meshless = new_unit(harness.engine, { meshes = 0 })
    local refused = new_unit(harness.engine, { refuse = true })
    local dead = {}

    assert_equal(false, mark(nil, COLOR, ANCHOR), "a target without a unit was outlined")
    assert_equal(false, mark(meshless, COLOR, ANCHOR), "a unit without meshes was outlined")
    assert_equal(false, mark(refused, COLOR, ANCHOR), "a unit the engine refused was outlined")

    local calls = harness.engine.calls

    assert_equal(false, mark(dead, COLOR, ANCHOR), "a dead unit was outlined")
    assert_equal(false, mark(refused, COLOR, ANCHOR), "a refused unit was outlined on the second try")
    assert_equal(calls, harness.engine.calls, "a dead or already refused unit reached the engine")

    harness.env._reset_highlight_outlines()
    refused.refuse = nil

    assert_equal(true, mark(refused, COLOR, ANCHOR), "the mission reset did not forget the refused units")
end)

local function listed_meshes(layer)
    local meshes = layer and layer.meshes or {}
    local listed = {}

    for i = 1, #meshes do
        listed[meshes[i]] = true
    end

    return listed
end

-- add_material_layer's sixth argument limits the layer to a list of mesh names. A layer on every
-- mesh drew a hanging barrel's hidden broken fragments as arcs, and a Heretic Idol's glow mesh and
-- collision hull as a box of planes.
test("hanging barrels and idols are outlined on their visible meshes only, other units on every mesh", function()
    local harness = new_harness()
    local hanging = new_unit(harness.engine, { root_node = "rp_hazard_sphere_01" })
    local idol = new_unit(harness.engine, { root_node = "rp_collectible_destructible_01" })
    local hanging_idol = new_unit(harness.engine, { root_node = "rp_collectible_destructible_01_hanging" })
    local other_prop = new_unit(harness.engine, { root_node = "rp_other_prop_01" })
    local pickup = new_unit(harness.engine)

    for _, unit in ipairs({ hanging, idol, hanging_idol, other_prop, pickup }) do
        assert_equal(true, harness.env._mark_highlight_outline(unit, COLOR, ANCHOR), "a unit was refused")
    end

    harness.env._sync_highlight_outlines()

    local barrel_meshes = listed_meshes(harness.engine.layers[hanging])
    local idol_meshes = listed_meshes(harness.engine.layers[idol])
    local hanging_idol_meshes = listed_meshes(harness.engine.layers[hanging_idol])

    assert_equal(true, barrel_meshes.g_hazard_sphere_01 and barrel_meshes.g_top and barrel_meshes.g_hazard_sphere_cables_01
        and barrel_meshes.g_hazard_sphere_dynamic_cable_01, "the hanging barrel's intact meshes are not all listed")
    assert_equal(nil, barrel_meshes.g_hazard_sphere_01_broken, "a broken fragment was listed")
    assert_equal(true, idol_meshes.g_collectible_destructible_01_body and idol_meshes.g_collectible_destructible_01_body_LOD1
        and idol_meshes.g_collectible_destructible_01_body_LOD2 and idol_meshes.g_collectible_destructible_01_body_LOD3,
        "the idol's body levels of detail are not all listed")
    assert_equal(nil, idol_meshes.g_collectible_destructible_01_glow, "the idol's glow mesh was listed")
    assert_equal(nil, idol_meshes.c_collectible_destructible_01_convex, "the idol's collision hull was listed")
    assert_equal(true, hanging_idol_meshes.g_collectible_destructible_01_hanging_body
        and hanging_idol_meshes.g_collectible_destructible_01_hanging_body_LOD1
        and hanging_idol_meshes.g_collectible_destructible_01_hanging_body_LOD2
        and hanging_idol_meshes.g_collectible_destructible_01_hanging_body_LOD3,
        "the hanging idol's body levels of detail are not all listed")
    assert_equal(nil, hanging_idol_meshes.g_collectible_destructible_01_hanging_glow, "the hanging idol's glow mesh was listed")
    assert_equal(nil, hanging_idol_meshes.c_collectible_destructible_01_hanging_convex,
        "the hanging idol's collision hull was listed")

    for _, unit in ipairs({ hanging, idol, hanging_idol }) do
        assert_equal(1, harness.engine.layers[unit].added, "a limited layer was added twice")
        assert_equal(true, harness.engine.layers[unit].on, "a unit with a limited layer is not outlined")
    end

    assert_equal(nil, harness.engine.layers[other_prop].meshes, "another prop's layer was limited")
    assert_equal(nil, harness.engine.layers[pickup].meshes, "the pickup's layer was limited")
    assert_equal(0, #harness.engine.infos, "an accepted mesh list was logged")
end)

test("a rejected mesh list falls back to a layer on every mesh, logged once and only in debug mode", function()
    local harness = new_harness({ settings = { debug_mode = true } })
    local first = new_unit(harness.engine, { root_node = "rp_hazard_sphere_01" })
    local second = new_unit(harness.engine, { root_node = "rp_hazard_sphere_01" })

    harness.engine.reject_mesh_whitelist = true

    assert_equal(true, harness.env._mark_highlight_outline(first, COLOR, ANCHOR), "the barrel was refused")
    assert_equal(true, harness.env._mark_highlight_outline(second, COLOR, ANCHOR), "the barrel was refused")

    harness.env._sync_highlight_outlines()

    assert_equal(1, harness.engine.layers[first].added, "the fallback did not add the layer once")
    assert_equal(nil, harness.engine.layers[first].meshes, "the fallback still passed the mesh list")
    assert_equal(true, harness.engine.layers[first].on, "the barrel lost its outline")
    assert_equal(1, #harness.engine.infos, "the rejection was logged more than once")
    assert_equal(true, harness.engine.infos[1]:find("rp_hazard_sphere_01", 1, true) ~= nil
        and harness.engine.infos[1]:find("bad argument #6", 1, true) ~= nil,
        "the log does not name the unit and carry the engine's error")

    local quiet = new_harness()
    local barrel = new_unit(quiet.engine, { root_node = "rp_hazard_sphere_01" })

    quiet.engine.reject_mesh_whitelist = true

    assert_equal(true, quiet.env._mark_highlight_outline(barrel, COLOR, ANCHOR), "the barrel was refused")
    assert_equal(0, #quiet.engine.infos, "the rejection was logged outside debug mode")
end)

test("culling stays off while the game's own outline shows on the unit", function()
    local harness = new_harness()
    local unit = new_unit(harness.engine)

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()
    harness.engine.game_outlines[unit] = { visible_material_layers = { "scanning" } }
    harness.env._sync_highlight_outlines()

    assert_equal(false, harness.engine.layers[unit].on, "the outline did not switch off")
    assert_equal(false, harness.engine.culling[unit], "Radar culled a unit the game is outlining")
end)

test("a unit that died while outlined is forgotten without an engine call", function()
    local harness = new_harness()
    local unit = new_unit(harness.engine)

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()
    harness.engine.alive[unit] = nil

    local calls = harness.engine.calls

    harness.env._sync_highlight_outlines()

    assert_equal(calls, harness.engine.calls, "a dead unit reached the engine")
    harness.engine.alive[unit] = true
    harness.env._sync_highlight_outlines()
    assert_equal(calls, harness.engine.calls, "the dead unit was not forgotten")
end)

test("with only visible targets highlighted, an outline waits for line of sight and follows it", function()
    local harness = new_harness({ settings = { nearby_highlight_visible_only = true } })
    local unit = new_unit(harness.engine)
    local hud_element = {}

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()

    assert_equal(false, harness.engine.layers[unit].on, "the outline showed before its line of sight was tested")

    harness.mod:update_highlight_outline_visibility(hud_element, nil)

    local query = harness.engine.occlusion_queries[1]

    assert_equal(true, harness.engine.layers[unit].on, "the visible unit did not get its outline")
    assert_equal(ANCHOR, query.world_position, "the occlusion test does not aim at the anchor")
    assert_equal(unit, query.unit, "the line-of-sight test does not know whose collider to ignore")

    harness.engine.occluded[unit] = true
    harness.mod:update_highlight_outline_visibility(hud_element, nil)

    assert_equal(false, harness.engine.layers[unit].on, "the outline shows through a wall")

    local writes = harness.engine.color_writes

    harness.engine.occluded[unit] = nil
    harness.mod:update_highlight_outline_visibility(hud_element, nil)

    assert_equal(true, harness.engine.layers[unit].on, "the outline did not come back in view")
    assert_equal(writes + 1, harness.engine.color_writes, "the outline came back in view without its colour")

    harness.engine.occluded[unit] = true
    harness.mod:update_highlight_outline_visibility(hud_element, nil)
    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()

    assert_equal(false, harness.engine.layers[unit].on, "the sync showed an occluded outline")

    harness.settings.nearby_highlight_visible_only = false
    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()

    assert_equal(true, harness.engine.layers[unit].on, "switching the option off did not show the outline again")
end)

test("with only visible targets highlighted, a tagged unit is outlined through walls without a test", function()
    local harness = new_harness({ settings = { nearby_highlight_visible_only = true } })
    local unit = new_unit(harness.engine)

    harness.engine.occluded[unit] = true
    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR, true)
    harness.env._sync_highlight_outlines()

    assert_equal(true, harness.engine.layers[unit].on, "the tagged unit waited for line of sight")

    harness.mod:update_highlight_outline_visibility({}, nil)

    assert_equal(true, harness.engine.layers[unit].on, "the tagged unit is hidden behind a wall")
    assert_equal(0, #harness.engine.occlusion_queries, "the tagged unit was tested for line of sight")

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR, false)
    harness.env._sync_highlight_outlines()
    harness.mod:update_highlight_outline_visibility({}, nil)

    assert_equal(false, harness.engine.layers[unit].on, "the untagged unit shows through a wall")
end)

-- In game, every untagged target counted as hidden: three of the four filters of the dimming
-- test do not exist, and the fourth is the one enemy shots use, which the ray from inside the
-- player's own character hits at once. The game's world markers test their line of sight with
-- their own filter instead, and ignore only the marked unit.
test("the line-of-sight test hides a target behind another unit only, as the game's markers do", function()
    local harness = new_harness({ with_helpers = true })
    local engine = harness.engine
    local mod = harness.mod
    local target = new_unit(engine)
    local wall = new_unit(engine)
    local camera = { x = 0, y = 0, z = 1.7 }
    local position = { x = 4, y = 0, z = 1.7 }

    assert_equal(false, mod:is_hud_target_hidden_by_geometry(camera, position, target), "nothing in the way hid it")

    local cast = engine.raycasts[1]

    assert_equal("physics_world", cast.physics_world, "the ray was not cast into the level's physics world")
    assert_equal("all", cast.mode, "the ray does not collect every hit")
    assert_equal("both", cast.types, "the ray does not hit statics and dynamics")
    assert_equal("filter_interactable_line_of_sight_marker_check", cast.filter,
        "the ray does not use the game's marker line-of-sight filter")
    assert_equal(4, cast.distance, "the ray does not end at the target")

    engine.hits = { { {}, 3.9, {}, { unit = target } } }
    assert_equal(false, mod:is_hud_target_hidden_by_geometry(camera, position, target), "its own collider hid it")

    engine.hits = { { {}, 3.9, {}, { unit = target } }, { {}, 2, {}, { unit = wall } } }
    assert_equal(true, mod:is_hud_target_hidden_by_geometry(camera, position, target), "a wall in front did not hide it")

    engine.hits = "not a hit list"
    assert_equal(false, mod:is_hud_target_hidden_by_geometry(camera, position, target), "a malformed result hid it")

    engine.hits = nil
    engine.raycast_error = true
    assert_equal(false, mod:is_hud_target_hidden_by_geometry(camera, position, target), "a failing raycast hid it")
end)

test("a cinematic hides every outline", function()
    local harness = new_harness({ settings = { nearby_highlight_visible_only = true } })
    local unit = new_unit(harness.engine)

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()
    harness.mod:update_highlight_outline_visibility({}, nil)
    assert_equal(true, harness.engine.layers[unit].on, "the outline did not show")

    harness.engine.cinematic = true
    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()
    harness.mod:update_highlight_outline_visibility({}, nil)

    assert_equal(false, harness.engine.layers[unit].on, "the outline shows during a cinematic")

    harness.engine.cinematic = false
    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()

    assert_equal(true, harness.engine.layers[unit].on, "the outline did not come back after the cinematic")
end)

test("clearing, a mission reset, disabling and unloading Radar switch every outline off", function()
    local chained = {}
    local harness = new_harness({
        previous_on_disabled = function()
            chained.disabled = true
        end,
        previous_on_unload = function()
            chained.unload = true
        end,
    })
    local env = harness.env

    for _, switch_off in ipairs({
        env._clear_highlight_outlines,
        env._reset_highlight_outlines,
        harness.mod.on_disabled,
        harness.mod.on_unload,
    }) do
        local unit = new_unit(harness.engine)

        env._mark_highlight_outline(unit, COLOR, ANCHOR)
        env._sync_highlight_outlines()
        switch_off()

        assert_equal(false, harness.engine.layers[unit].on, "an outline stayed on")

        local calls = harness.engine.calls

        env._sync_highlight_outlines()
        assert_equal(calls, harness.engine.calls, "the switched off unit was not forgotten")
    end

    assert_equal(true, chained.disabled, "the previous on_disabled handler was not chained")
    assert_equal(true, chained.unload, "the previous on_unload handler was not chained")
end)

-- What the game does to units leaving it: the extension manager unregisters them, and then they are destroyed.
local function unregister_units(harness, units, original)
    return harness.mod.hooks["ExtensionManager.unregister_units"](original or function() end, {}, units, #units, true)
end

local function layer_count(harness, unit)
    local layer = harness.engine.layers[unit]

    return layer and layer.added - (layer.removed or 0) or 0
end

test("a unit leaving the game loses its layer before the game unregisters it", function()
    local harness = new_harness()
    local engine = harness.engine
    local outlined = new_unit(engine)
    local other = new_unit(engine)
    local manager = {}
    local received = {}

    harness.env._mark_highlight_outline(outlined, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()

    local result = harness.mod.hooks["ExtensionManager.unregister_units"](function(self, units, num_units, flag)
        received.self = self
        received.units = units
        received.num_units = num_units
        received.flag = flag
        received.layers_left = layer_count(harness, outlined)

        return "result"
    end, manager, { other, outlined }, 2, true)

    assert_equal(0, received.layers_left, "the layer was still on when the game unregistered the unit")
    assert_equal(manager, received.self, "the manager was not passed on")
    assert_equal(other, received.units[1], "the unit list was not passed on")
    assert_equal(2, received.num_units, "the unit count was not passed on")
    assert_equal(true, received.flag, "the further arguments were not passed on")
    assert_equal("result", result, "the game's return value was lost")
    assert_equal(nil, engine.layers[other], "a unit never outlined reached the engine")
    assert_equal(0, engine.crashes, "the removal would have crashed the game")
    assert_equal(false, engine.data[outlined].radar_highlight_outline, "the unit is still marked as carrying the layer")

    unregister_units(harness, { outlined })

    assert_equal(0, engine.crashes, "a second removal would have crashed the game")

    local calls = engine.calls

    engine.alive[outlined] = nil
    harness.env._sync_highlight_outlines()

    assert_equal(calls, engine.calls, "the unit was not forgotten")
end)

test("a mission reset takes the layer off every unit carrying one, also units no longer outlined", function()
    local harness = new_harness()
    local engine = harness.engine
    local env = harness.env
    local outlined = new_unit(engine)
    local out_of_range = new_unit(engine)
    local never_outlined = new_unit(engine)
    local refused = new_unit(engine, { refuse = true })
    local destroyed = new_unit(engine)

    env._mark_highlight_outline(out_of_range, COLOR, ANCHOR)
    env._mark_highlight_outline(destroyed, COLOR, ANCHOR)
    env._mark_highlight_outline(refused, COLOR, ANCHOR)
    env._sync_highlight_outlines()
    env._mark_highlight_outline(outlined, COLOR, ANCHOR)
    env._mark_highlight_outline(destroyed, COLOR, ANCHOR)
    env._sync_highlight_outlines()
    engine.alive[destroyed] = nil

    assert_equal(1, layer_count(harness, out_of_range), "a unit out of range lost its layer before the reset")

    env._reset_highlight_outlines()

    assert_equal(0, layer_count(harness, outlined), "an outlined unit kept its layer")
    assert_equal(0, layer_count(harness, out_of_range), "a unit no longer outlined kept its layer")
    assert_equal(nil, engine.layers[never_outlined], "a unit never outlined reached the engine")
    assert_equal(nil, engine.layers[refused], "a refused unit reached the engine")
    assert_equal(nil, engine.layers[destroyed].removed, "a dead unit reached the engine")
    assert_equal(0, engine.crashes, "the removal would have crashed the game")

    local calls = engine.calls

    env._reset_highlight_outlines()

    assert_equal(calls, engine.calls, "a second reset reached the engine")
end)

test("clearing only switches outlines off, and the layer is kept for when they come back", function()
    local harness = new_harness()
    local unit = new_unit(harness.engine)

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()
    harness.env._clear_highlight_outlines()

    assert_equal(1, layer_count(harness, unit), "clearing took the layer off")

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.env._sync_highlight_outlines()

    assert_equal(1, harness.engine.layers[unit].added, "the returning unit got a second layer")
    assert_equal(true, harness.engine.layers[unit].on, "the returning unit has no outline")
end)

test("disabling and unloading Radar take every layer off", function()
    local harness = new_harness()

    for _, switch_off in ipairs({ harness.mod.on_disabled, harness.mod.on_unload }) do
        local outlined = new_unit(harness.engine)
        local out_of_range = new_unit(harness.engine)

        harness.env._mark_highlight_outline(out_of_range, COLOR, ANCHOR)
        harness.env._sync_highlight_outlines()
        harness.env._mark_highlight_outline(outlined, COLOR, ANCHOR)
        harness.env._sync_highlight_outlines()
        switch_off()

        assert_equal(0, layer_count(harness, outlined), "an outlined unit kept its layer")
        assert_equal(0, layer_count(harness, out_of_range), "a unit no longer outlined kept its layer")
    end

    assert_equal(0, harness.engine.crashes, "the removal would have crashed the game")
end)

test("a unit outlined again after its layer came off gets a new one and its outline back", function()
    local harness = new_harness()
    local engine = harness.engine
    local env = harness.env

    for _, remove in ipairs({
        function(unit)
            unregister_units(harness, { unit })
        end,
        env._reset_highlight_outlines,
        harness.mod.on_disabled,
    }) do
        local unit = new_unit(engine)

        env._mark_highlight_outline(unit, COLOR, ANCHOR)
        env._sync_highlight_outlines()
        remove(unit)

        assert_equal(0, layer_count(harness, unit), "the layer did not come off")

        engine.layers[unit].color = nil

        assert_equal(true, env._mark_highlight_outline(unit, COLOR, ANCHOR), "the unit was refused")

        env._sync_highlight_outlines()

        assert_equal(2, engine.layers[unit].added, "the unit did not get a new layer")
        assert_equal(1, layer_count(harness, unit), "the unit does not carry one layer")
        assert_equal(true, engine.layers[unit].on, "the unit has no outline")
        assert_equal(true, engine.layers[unit].color ~= nil, "the new layer did not get its colour")
        assert_equal(false, engine.culling[unit], "the unit is culled again")
        assert_equal(true, engine.data[unit].radar_highlight_outline, "the unit is not marked as carrying the layer")

        env._reset_highlight_outlines()
    end

    assert_equal(0, engine.crashes, "the removal would have crashed the game")
end)

-- remove_material_layer walks every mesh unless it is given a list, and the real call crashes on one without the layer.
test("a layer limited to a mesh list comes off those meshes, a rejected list off every mesh", function()
    local harness = new_harness()
    local barrel = new_unit(harness.engine, { root_node = "rp_hazard_sphere_01" })
    local prop = new_unit(harness.engine, { root_node = "rp_other_prop_01" })

    harness.env._mark_highlight_outline(barrel, COLOR, ANCHOR)
    harness.env._mark_highlight_outline(prop, COLOR, ANCHOR)
    harness.env._reset_highlight_outlines()

    assert_equal(true, harness.engine.layers[barrel].meshes ~= nil, "the barrel's layer was not limited")
    assert_equal(0, layer_count(harness, barrel), "the barrel kept its layer")
    assert_equal(0, layer_count(harness, prop), "the prop kept its layer")
    assert_equal(0, harness.engine.crashes, "the removal did not name the meshes the layer is on")

    local rejected = new_harness()
    local fallback = new_unit(rejected.engine, { root_node = "rp_hazard_sphere_01" })

    rejected.engine.reject_mesh_whitelist = true
    rejected.env._mark_highlight_outline(fallback, COLOR, ANCHOR)
    rejected.env._reset_highlight_outlines()

    assert_equal(0, layer_count(rejected, fallback), "the barrel on the fallback layer kept it")
    assert_equal(0, rejected.engine.crashes, "the removal named meshes although the list was rejected")
end)

-- Passing true to remove_material_layer would walk every current child, and the real call
-- crashes on one linked after the layer was added.
test("the layer comes off the child units it reached, and only those", function()
    local harness = new_harness()
    local engine = harness.engine
    local grandchild = new_unit(engine)
    local gone_child = new_unit(engine)
    local child = new_unit(engine, { children = { grandchild } })
    local unit = new_unit(engine, { children = { child, gone_child } })
    local linked_later = new_unit(engine)

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)

    assert_equal(1, layer_count(harness, grandchild), "the fake engine did not give the grandchild the layer")

    unit.children[3] = linked_later
    engine.alive[gone_child] = nil
    unregister_units(harness, { unit })

    assert_equal(0, layer_count(harness, unit), "the unit kept its layer")
    assert_equal(0, layer_count(harness, child), "a child unit kept its layer")
    assert_equal(0, layer_count(harness, grandchild), "a grandchild unit kept its layer")
    assert_equal(nil, engine.layers[gone_child].removed, "a dead child unit reached the engine")
    assert_equal(nil, engine.layers[linked_later], "a child linked later reached the engine")
    assert_equal(0, engine.crashes, "the removal would have crashed the game")
end)

test("a reloaded Radar takes off a layer it found on a unit, with a limited one's meshes", function()
    local harness = new_harness()
    local barrel = new_unit(harness.engine, { root_node = "rp_hazard_sphere_01" })

    harness.env._mark_highlight_outline(barrel, COLOR, ANCHOR)

    local reloaded = new_harness({ engine = harness.engine })

    reloaded.env._mark_highlight_outline(barrel, COLOR, ANCHOR)

    assert_equal(1, harness.engine.layers[barrel].added, "the reloaded module added a second layer")

    reloaded.env._reset_highlight_outlines()

    assert_equal(0, layer_count(reloaded, barrel), "the reloaded module did not take the layer off")
    assert_equal(0, harness.engine.crashes, "the removal would have crashed the game")
end)

test("a unit unloaded with its layer taken off gets a new one from the reloaded Radar", function()
    local harness = new_harness()
    local unit = new_unit(harness.engine)

    harness.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    harness.mod.on_unload()

    local reloaded = new_harness({ engine = harness.engine })

    assert_equal(true, reloaded.env._mark_highlight_outline(unit, COLOR, ANCHOR), "the unit was refused")
    assert_equal(2, harness.engine.layers[unit].added, "the unit did not get a new layer")
    assert_equal(1, layer_count(reloaded, unit), "the unit does not carry one layer")
end)

test("a missing or refusing removal call is tolerated, keeps the marker and logs once in debug mode", function()
    local function remove_with(setup)
        local harness = new_harness({ settings = { debug_mode = true } })
        local first = new_unit(harness.engine)
        local second = new_unit(harness.engine)
        local reached = false

        setup(harness)
        harness.env._mark_highlight_outline(first, COLOR, ANCHOR)
        harness.env._mark_highlight_outline(second, COLOR, ANCHOR)
        unregister_units(harness, { first }, function()
            reached = true
        end)
        harness.env._reset_highlight_outlines()

        assert_equal(true, reached, "the game did not get to unregister the unit")
        assert_equal(1, #harness.engine.infos, "the failure was not logged once")
        assert_equal(true, harness.engine.data[first].radar_highlight_outline, "the marker was cleared")

        harness.env._mark_highlight_outline(first, COLOR, ANCHOR)

        assert_equal(1, harness.engine.layers[first].added, "the unit got a second layer")

        return harness.engine.infos[1]
    end

    local refused = remove_with(function(harness)
        harness.engine.remove_error = true
    end)

    assert_equal(true, refused:find("the engine refused the removal", 1, true) ~= nil, "the log does not carry the engine's error")

    remove_with(function(harness)
        harness.env.Unit.remove_material_layer = nil
    end)

    local quiet = new_harness()
    local unit = new_unit(quiet.engine)

    quiet.engine.remove_error = true
    quiet.env._mark_highlight_outline(unit, COLOR, ANCHOR)
    quiet.env._reset_highlight_outlines()

    assert_equal(0, #quiet.engine.infos, "the failure was logged outside debug mode")
end)

test("nothing reaches the engine or the camera while nothing is outlined", function()
    local harness = new_harness({ settings = { nearby_highlight_visible_only = true } })
    local camera_reads = 0

    function harness.mod:get_hud_player_camera_position()
        camera_reads = camera_reads + 1
        return { x = 0, y = 0, z = 0 }
    end

    harness.env._sync_highlight_outlines()
    harness.env._clear_highlight_outlines()
    harness.env._reset_highlight_outlines()
    unregister_units(harness, { {} })
    harness.mod:update_highlight_outline_visibility({}, nil)

    assert_equal(0, harness.engine.calls, "an idle outline module called the engine")
    assert_equal(0, camera_reads, "an idle outline module read the camera")
end)

test("a group set to outlines outlines its units, and a target without a unit keeps its bracket", function()
    local harness = new_harness({
        with_helpers = true,
        settings = {
            nearby_highlight_common_pickups = "outline",
            nearby_highlight_materials = "highlight",
            nearby_highlight_environment = "outline",
            nearby_highlight_deployables = "off",
            nearby_highlight_mission_objective = "outline",
        },
    })
    local env = harness.env
    local mod = harness.mod
    local engine = harness.engine
    local player = new_unit(engine, { position = { x = 0, y = 0, z = 0 } })
    local ammo = new_unit(engine, { position = { x = 1, y = 0, z = 0 } })
    local plasteel = new_unit(engine, { position = { x = 2, y = 0, z = 0 } })
    local barrel = new_unit(engine, { position = { x = 3, y = 0, z = 0 } })
    local standing_barrel = new_unit(engine, { position = { x = 3, y = 1, z = 0 } })
    local medical_crate = new_unit(engine, { position = { x = 0, y = 3, z = 0 } })
    local train_control = new_unit(engine, { position = { x = 4, y = 0, z = 0 } })
    local cogitator = new_unit(engine, { position = { x = 4.5, y = 0, z = 0 } })
    local carrier_eye = new_unit(engine, { position = { x = 0, y = 5, z = 0 } })
    local second_eye = new_unit(engine, { position = { x = 0.3, y = 5, z = 0 } })
    local third_eye = new_unit(engine, { position = { x = 0, y = 5.3, z = 0 } })
    local group_by_kind = {
        pickup_ammo_small = "common_pickups_group",
        pickup_ammo_big = "common_pickups_group",
        material_plasteel = "materials_group",
        hazard_explosive_barrel = "environment_group",
        medical_crate_deployable = "deployables_group",
        mission_objective_growth = "mission_objective_group",
        mission_objective_destroy = "mission_objective_group",
    }

    env.NEARBY_HIGHLIGHT_SETTING_BY_GROUP = {
        common_pickups_group = "nearby_highlight_common_pickups",
        materials_group = "nearby_highlight_materials",
        environment_group = "nearby_highlight_environment",
        deployables_group = "nearby_highlight_deployables",
        mission_objective_group = "nearby_highlight_mission_objective",
    }
    -- From the mission objectives module: the eyes of the tentacle whose marker an eye carries.
    env._growth_tentacle_eyes = function(unit, out)
        if unit ~= carrier_eye then
            return 0
        end

        out[1] = carrier_eye
        out[2] = second_eye
        out[3] = third_eye

        return 3
    end
    -- From the mission objectives module: the objective prop a destroy target stands for.
    env._destroy_objective_prop = function(unit)
        return unit == train_control and cogitator or nil
    end
    env.NEARBY_HIGHLIGHT_EXCLUDED_KINDS = {}
    env.NEARBY_OUTLINE_OCCLUDED_MULTIPLIER = 0.6
    env._player_unit = function()
        return player
    end
    env._safe_unit_position = function(unit)
        return unit and unit.position or nil
    end
    env._safe_unit_to_extension_map = function()
        return nil
    end

    function mod:has_any_nearby_highlight_enabled()
        return true
    end

    function mod:get_marker_scale_group(kind)
        return group_by_kind[kind]
    end

    function mod:get_nearby_highlight_range()
        return 10
    end

    function mod:get_nearby_highlight_color()
        return { 255, 51, 102, 204 }
    end

    function mod:get_occluded_highlight_color()
        return { 255, 1, 1, 1 }
    end

    mod._highlight_source_radar_targets = {
        { unit = ammo, kind = "pickup_ammo_small", position = ammo.position, distance_sq_3d = 1 },
        { kind = "pickup_ammo_big", position = { x = 1, y = 1, z = 0 }, distance_sq_3d = 2, source = "smart_tag_system" },
        { unit = plasteel, kind = "material_plasteel", position = plasteel.position, distance_sq_3d = 4 },
        { unit = barrel, kind = "hazard_explosive_barrel", position = barrel.position, distance_sq_3d = 9 },
        { unit = standing_barrel, kind = "hazard_explosive_barrel", position = standing_barrel.position,
            distance_sq_3d = 10 },
        { unit = medical_crate, kind = "medical_crate_deployable", position = medical_crate.position, distance_sq_3d = 9 },
        { unit = carrier_eye, kind = "mission_objective_growth", position = carrier_eye.position, distance_sq_3d = 25 },
        { unit = train_control, kind = "mission_objective_destroy", position = train_control.position, distance_sq_3d = 16 },
    }

    local highlights = env._collect_screen_highlight_targets()

    env._sync_highlight_outlines()

    assert_equal(2, #highlights, "the wrong targets got brackets")
    assert_equal("pickup_ammo_big", highlights[1].kind, "the target without a unit lost its bracket")
    assert_equal("material_plasteel", highlights[2].kind, "a group set to highlight markers lost its bracket")
    assert_equal(true, highlights[1].tagged, "a tagged target's bracket is not marked as tagged")
    assert_equal(false, highlights[2].tagged, "an untagged target's bracket is marked as tagged")
    assert_equal(true, engine.layers[ammo] and engine.layers[ammo].on, "the outlined pickup has no outline")
    assert_equal(nil, engine.layers[plasteel], "a group set to highlight markers was outlined")
    assert_equal(true, engine.layers[barrel] and engine.layers[barrel].on, "a barrel fell back to a bracket")
    assert_equal(true, engine.layers[standing_barrel] and engine.layers[standing_barrel].on,
        "the second barrel fell back to a bracket")
    assert_equal(nil, engine.layers[medical_crate], "a group that is off was outlined")

    for _, eye in ipairs({ carrier_eye, second_eye, third_eye }) do
        assert_equal(true, engine.layers[eye] and engine.layers[eye].on, "an eye of the growth tentacle has no outline")
    end

    assert_equal(true, engine.layers[cogitator] and engine.layers[cogitator].on, "the cogitator behind a destroy target has no outline")
    assert_equal(nil, engine.layers[train_control], "the destroy target's helper was outlined")

    harness.settings.nearby_highlight_common_pickups = "off"
    env._collect_screen_highlight_targets()
    env._sync_highlight_outlines()

    assert_equal(false, engine.layers[ammo].on, "switching the group off kept the outline")
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
