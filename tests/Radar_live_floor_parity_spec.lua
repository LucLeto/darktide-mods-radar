-- Where a marker and the live scan floor land on the radar, and what the live floor probe reports.
-- Installs the real runtime helpers and tracking modules, which place the markers, and loads the
-- real navmesh renderer and triangle clipper against the same fake mod, a recording GUI and
-- generated meshes. One world point must land on the same pixel through both projections at every
-- zoom, heading and radar style, so a marker can only sit off the floor where the navmesh has no
-- triangle under it, such as a pickup lying on a barrel (issue 191).

local HELPERS_PATH = "Radar/scripts/mods/Radar/Radar_runtime_helpers.lua"
local TRACKING_PATH = "Radar/scripts/mods/Radar/Radar_tracking.lua"
local RENDERER_PATH = "Radar/scripts/mods/Radar/ui/Radar_navmesh_renderer.lua"

local CENTER_X, CENTER_Y = 147, 333
local UI_SCALE = 4 / 3
local PROJECTION_RADIUS = 132
local ZOOM_STEPS = { 10, 25, 50, 75, 100, 150, 200 }
local OVERVIEW_RANGES = { 25, 137.5, 500 }
local CURRENT_COLOR = 80 * 16777216 + 101 * 65536 + 133 * 256 + 96
local ABOVE_COLOR = 32 * 16777216 + 120 * 65536 + 150 * 256 + 185
--- The navmesh agent's clearance around obstacles, and a barrel's radius.
local AGENT_RADIUS = 0.38
local BARREL_RADIUS = 0.3

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

local function assert_true(value, message)
    if value ~= true then
        error(message or "expected true", 2)
    end
end

local function assert_near(expected, actual, tolerance, message)
    if type(actual) ~= "number" or math.abs(expected - actual) > tolerance then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function noop()
end

-- A rotation is a table holding its forward vector.
local function rotation(x, y, z)
    return { forward = { x = x, y = y, z = z or 0 } }
end

local NORTH = rotation(0, 1, 0)

local function point(x, y, z)
    return { x = x, y = y, z = z or 0 }
end

-- Fake units for the probe's anchor check: positions by node index, node indices by name.
local fake_units = {}

ALIVE = {}
Unit = {
    world_position = function(unit, index)
        return fake_units[unit].positions[index]
    end,
    has_node = function(unit, name)
        return fake_units[unit].nodes[name] ~= nil
    end,
    node = function(unit, name)
        return fake_units[unit].nodes[name]
    end,
}

local function new_unit(name, position, interaction_node_offset_z)
    local unit = { name = name }
    local entry = { positions = { position }, nodes = {} }

    if interaction_node_offset_z then
        entry.nodes.ui_interaction_marker = 2
        entry.positions[2] = point(position.x, position.y, position.z + interaction_node_offset_z)
    end

    fake_units[unit] = entry
    ALIVE[unit] = true

    return unit
end

local next_revision = 0

--- Geometry in the shape `Radar_navmesh.lua` builds, with one bucket per 16 m cell and a new revision.
local function new_geometry(triangles)
    next_revision = next_revision + 1

    local geometry = {
        ax = {}, ay = {}, az = {},
        bx = {}, by = {}, bz = {},
        cx = {}, cy = {}, cz = {},
        mid_x = {}, mid_y = {}, mid_z = {},
        radius = {},
        count = #triangles,
        max_radius = 0,
        cell_size = 16,
        buckets = {},
        revision = next_revision,
    }

    for i = 1, #triangles do
        local t = triangles[i]
        local mid_x = (t[1] + t[4] + t[7]) / 3
        local mid_y = (t[2] + t[5] + t[8]) / 3
        local radius = 0

        geometry.ax[i], geometry.ay[i], geometry.az[i] = t[1], t[2], t[3]
        geometry.bx[i], geometry.by[i], geometry.bz[i] = t[4], t[5], t[6]
        geometry.cx[i], geometry.cy[i], geometry.cz[i] = t[7], t[8], t[9]
        geometry.mid_x[i], geometry.mid_y[i] = mid_x, mid_y
        geometry.mid_z[i] = (t[3] + t[6] + t[9]) / 3

        for v = 0, 2 do
            local dx, dy = t[v * 3 + 1] - mid_x, t[v * 3 + 2] - mid_y

            radius = math.max(radius, math.sqrt(dx * dx + dy * dy))
        end

        geometry.radius[i] = radius
        geometry.max_radius = math.max(geometry.max_radius, radius)

        local key = math.floor(mid_x / 16) .. ":" .. math.floor(mid_y / 16)
        local bucket = geometry.buckets[key]

        if not bucket then
            bucket = {}
            geometry.buckets[key] = bucket
        end

        bucket[#bucket + 1] = i
    end

    return geometry
end

--- Adds the two triangles of a level rectangle.
local function add_rectangle(triangles, x1, y1, x2, y2, z)
    triangles[#triangles + 1] = { x1, y1, z, x2, y1, z, x2, y2, z }
    triangles[#triangles + 1] = { x1, y1, z, x2, y2, z, x1, y2, z }
end

--- A 16 m floor around the origin with the hole a barrel at `barrel` leaves in the navmesh.
local function barrel_floor(barrel)
    local half = BARREL_RADIUS + AGENT_RADIUS
    local left, right = barrel.x - half, barrel.x + half
    local bottom, top = barrel.y - half, barrel.y + half
    local triangles = {}

    add_rectangle(triangles, -8, -8, left, 8, 0)
    add_rectangle(triangles, right, -8, 8, 8, 0)
    add_rectangle(triangles, left, -8, right, bottom, 0)
    add_rectangle(triangles, left, top, right, 8, 0)

    return triangles
end

local function install(path, env)
    local chunk, load_error = loadfile(path)

    assert(chunk, load_error)
    chunk()(env)
end

--- Installs tracking for the marker projection and loads the renderer against the same mod.
local function new_harness(style)
    local settings = {
        enable_radar = true,
        debug_mode = false,
        debug_profiling = false,
        radar_style = style or "circle",
        overview_zoom_in_key = { "wheel_down" },
        overview_zoom_out_key = { "wheel_up" },
        radar_zoom_modifier_key = {},
    }
    local mod = {
        _tracked_units = {},
        _tracked_points = {},
    }
    local harness = { mod = mod, settings = settings, emitted = {}, info = {}, selections = 0 }
    local quaternion = {
        forward = function(rot)
            return rot.forward
        end,
    }

    function mod:get(setting_id)
        return settings[setting_id]
    end

    function mod:set(setting_id, value)
        settings[setting_id] = value
    end

    function mod:info(text)
        harness.info[#harness.info + 1] = text
    end

    mod.hook = noop
    mod.hook_safe = noop
    mod.register_hud_element = noop
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
        Quaternion = quaternion,
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

    function mod:get_radar_color(_, fallback)
        return fallback
    end

    function mod:ensure_navmesh_geometry()
        return harness.geometry
    end

    -- Every bucket; the renderer filters by distance itself. The probe asks for `max_radius` only.
    function mod:get_navmesh_nearby_buckets(_, _, range, out_buckets)
        local n = 0

        if range > harness.geometry.max_radius then
            harness.selections = harness.selections + 1
        end

        for _, bucket in pairs(harness.geometry.buckets) do
            n = n + 1
            out_buckets[n] = bucket
        end

        return n
    end

    function mod:io_dofile(path)
        return assert(loadfile(path .. ".lua"))()
    end

    local previous = {
        get_mod = rawget(_G, "get_mod"),
        Gui = rawget(_G, "Gui"),
        Vector3 = rawget(_G, "Vector3"),
        Color = rawget(_G, "Color"),
        Quaternion = rawget(_G, "Quaternion"),
    }

    rawset(_G, "get_mod", function()
        return mod
    end)
    rawset(_G, "Vector3", function(x, _, z)
        return { x, z }
    end)
    rawset(_G, "Color", function(a, r, g, b)
        return a * 16777216 + r * 65536 + g * 256 + b
    end)
    rawset(_G, "Quaternion", quaternion)
    rawset(_G, "Gui", {
        triangle = function(_, a, b, c, layer, color)
            harness.emitted[#harness.emitted + 1] = { a[1], a[2], b[1], b[2], c[1], c[2], layer, color }
        end,
    })

    harness.renderer = assert(loadfile(RENDERER_PATH))()

    for name, value in pairs(previous) do
        rawset(_G, name, value)
    end

    --- Draws the live floor the way the HUD does and returns the triangles it submitted.
    function harness.draw(t, player, rot, range, radius)
        harness.emitted = {}
        harness.renderer.draw({ gui = {}, scale = UI_SCALE, render_settings = { start_layer = 100 } }, t, player, rot,
            CENTER_X, CENTER_Y, radius or PROJECTION_RADIUS, range, 2, 1)

        return harness.emitted
    end

    --- Places a marker the way the HUD does and returns its screen position, nil when it is not drawn.
    function harness.marker(player, rot, target, range)
        local forward_x, forward_y = mod:radar_projection_forward(rot)
        local px, py = mod:project_target_to_radar(player, forward_x, forward_y, target, PROJECTION_RADIUS, range,
            false)

        if not px then
            return nil, nil, nil, nil
        end

        return (CENTER_X + px) * UI_SCALE, (CENTER_Y + py) * UI_SCALE, px, py
    end

    --- Gives the probe a radar snapshot with these targets.
    function harness.set_targets(targets)
        mod._radar_snapshot = { targets = targets }
    end

    return harness
end

--- Returns whether a submitted triangle of the given colour, or of any colour, covers a screen point.
local function covers(emitted, x, y, color)
    for i = 1, #emitted do
        local tri = emitted[i]

        if color == nil or tri[8] == color then
            local x1, y1, x2, y2, x3, y3 = tri[1], tri[2], tri[3], tri[4], tri[5], tri[6]
            local d1 = (x2 - x1) * (y - y1) - (y2 - y1) * (x - x1)
            local d2 = (x3 - x2) * (y - y2) - (y3 - y2) * (x - x2)
            local d3 = (x1 - x3) * (y - y3) - (y1 - y3) * (x - x3)
            local has_neg = d1 < 0 or d2 < 0 or d3 < 0
            local has_pos = d1 > 0 or d2 > 0 or d3 > 0

            if not (has_neg and has_pos) then
                return true
            end
        end
    end

    return false
end

--- Splits a log line into its `key=value` fields.
local function fields(line)
    local result = {}

    for key, value in line:gmatch("([%w_%(%)/]+)=(%S+)") do
        result[key] = value
    end

    return result
end

--- Returns the probe's header and target lines logged from `from` on, as field tables.
local function probe_lines(harness, from)
    local headers, targets = {}, {}

    for i = from or 1, #harness.info do
        local line = harness.info[i]

        if line:find("[Radar] live floor probe | ", 1, true) then
            headers[#headers + 1] = fields(line)
        elseif line:find("[Radar] live floor probe target | ", 1, true) then
            targets[#targets + 1] = fields(line)
        end
    end

    return headers, targets
end

local function target_line(targets, kind)
    for i = 1, #targets do
        if targets[i].kind == kind then
            return targets[i]
        end
    end

    error("no probe line for " .. kind, 2)
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local STYLES = { "circle", "square", "auspex" }

test("a world point lands on the same pixel through the marker and the floor projection", function()
    for _, style in ipairs(STYLES) do
        local harness = new_harness(style)
        local player = point(12.3, -7.9, 0.4)
        local t = 0

        for heading = 0, 23 do
            local yaw = heading * math.pi / 12
            local pitch = (heading % 5 - 2) * 0.5
            local rot = rotation(math.cos(pitch) * math.sin(yaw), math.cos(pitch) * math.cos(yaw), math.sin(pitch))

            for pass = 1, 2 do
                local overview = pass == 2

                harness.mod._overview_mode_active = overview

                for _, range in ipairs(overview and OVERVIEW_RANGES or ZOOM_STEPS) do
                    local points, triangles = {}, {}
                    local size = range * 0.002

                    for k = 1, 12 do
                        local angle = k * 2.399 + heading
                        local distance = range * (0.05 + 0.07 * k)
                        local x = player.x + math.cos(angle) * distance
                        local y = player.y + math.sin(angle) * distance

                        points[k] = point(x, y, player.z)
                        triangles[k] = { x, y, player.z, x + size, y, player.z, x, y + size, player.z }
                    end

                    harness.geometry = new_geometry(triangles)
                    t = t + 1

                    local emitted = harness.draw(t, player, rot, range)
                    local label = string.format("%s heading %d range %s", style, heading, tostring(range))

                    assert_equal(#points, #emitted, label .. " every point's triangle is drawn whole")

                    for k = 1, #points do
                        local screen_x, screen_y, px, py = harness.marker(player, rot, points[k], range)
                        local found = false

                        assert_true(screen_x ~= nil, label .. " marker " .. k .. " is drawn")

                        for e = 1, #emitted do
                            local tri = emitted[e]

                            if math.abs(tri[1] - screen_x) <= 1e-6 and math.abs(tri[2] - screen_y) <= 1e-6 then
                                found = true

                                break
                            end
                        end

                        assert_true(found, label .. " point " .. k .. " landed on different pixels")
                        assert_true(math.abs(math.floor(CENTER_X + px + 0.5) - (CENTER_X + px)) <= 0.5
                            and math.abs(math.floor(CENTER_Y + py + 0.5) - (CENTER_Y + py)) <= 0.5,
                            label .. " the HUD's rounded centre is more than half a pixel off")
                    end
                end
            end
        end
    end
end)

test("zooming only scales the gap between a marker and a floor corner", function()
    local harness = new_harness("circle")
    local player = point(3, 4, 0)
    local rot = rotation(0.6, 0.8, -0.2)
    local corner = point(3.5, 5, 0)
    local pickup = point(3.4, 5.9, 1)

    harness.geometry = new_geometry({
        { corner.x, corner.y, 0, corner.x - 0.8, corner.y - 0.3, 0, corner.x - 0.2, corner.y - 0.9, 0 },
    })

    -- The world offset turned into the view and scaled to the projection radius at 1 m range.
    local dx, dy = pickup.x - corner.x, pickup.y - corner.y
    local expected_x = (dx * 0.8 - dy * 0.6) * PROJECTION_RADIUS
    local expected_y = -(dx * 0.6 + dy * 0.8) * PROJECTION_RADIUS
    local t = 0

    for _, overview in ipairs({ false, true }) do
        harness.mod._overview_mode_active = overview

        for _, range in ipairs(overview and OVERVIEW_RANGES or ZOOM_STEPS) do
            t = t + 1

            local emitted = harness.draw(t, player, rot, range)
            local corner_x = emitted[1][1] / UI_SCALE - CENTER_X
            local corner_y = emitted[1][2] / UI_SCALE - CENTER_Y
            local _, _, px, py = harness.marker(player, rot, pickup, range)

            assert_near(expected_x, (px - corner_x) * range, 1e-6, "range " .. range .. " moved the marker sideways")
            assert_near(expected_y, (py - corner_y) * range, 1e-6, "range " .. range .. " moved the marker along")
        end
    end
end)

test("a pickup on a barrel sits in the barrel's hole at every zoom, floor pickups and teammates on drawn floor", function()
    local harness = new_harness("circle")
    local player = point(0, 0, 0)
    local barrel = point(0, 1.9, 0)
    local stash = point(barrel.x, barrel.y, 1)
    local floor_pickup = point(-3, 2, 0.05)
    local teammate = point(1.5, -0.5, 0)
    local stash_unit = new_unit("stash", stash, 0.1)
    local teammate_unit = new_unit("teammate", teammate)

    harness.geometry = new_geometry(barrel_floor(barrel))
    harness.settings.debug_mode = true
    harness.set_targets({
        { kind = "enemy_poxwalker", position = point(0.5, 3.5, 0), unit = {} },
        { kind = "material_plasteel", position = stash, unit = stash_unit },
        { kind = "material_diamantine", position = floor_pickup, unit = {} },
        { kind = "player_teammate", position = teammate, unit = teammate_unit },
    })

    local steps = {
        { 1, 25, "start" }, { 2, 10, "zoom" }, { 2.6, 10, "settled" }, { 3, 50, "zoom" }, { 3.6, 50, "settled" },
        { 4, 200, "zoom" }, { 4.6, 200, "settled" }, { 5, 10, "zoom" }, { 5.6, 10, "settled" },
    }

    for s = 1, #steps do
        local t, range, phase = steps[s][1], steps[s][2], steps[s][3]
        local from = #harness.info + 1
        local emitted = harness.draw(t, player, NORTH, range)
        local headers, targets = probe_lines(harness, from)
        local label = phase .. " at " .. range .. " m"

        assert_equal(1, #headers, label .. " header")
        assert_equal(phase, headers[1].phase, label)
        assert_equal(4, #targets, label .. " every target within 4 m")
        assert_equal("player_teammate", targets[1].kind, "nearest other kinds first")
        assert_equal("material_plasteel", targets[2].kind, "nearest other kinds first")
        assert_equal("material_diamantine", targets[3].kind, "nearest other kinds first")
        assert_equal("enemy_poxwalker", targets[4].kind, "enemies last")

        for k = 1, #targets do
            assert_equal("0.0000", targets[k].delta, label .. " " .. targets[k].kind .. " marker and floor disagree")
        end

        local on_barrel = target_line(targets, "material_plasteel")

        assert_equal("outside", on_barrel.under, label .. " the barrel has no floor")
        assert_equal("0.68", on_barrel.dist_m, label .. " the hole's edge is the barrel plus the agent's clearance")
        assert_equal("-1.00", on_barrel.floor_dz, label .. " the floor beside it is a metre down")
        assert_equal("0", on_barrel.stack, label)
        assert_equal("true", on_barrel.drawn, label .. " the floor beside it is drawn")
        assert_equal("0.00,0.00,0.00", on_barrel.root, label .. " the tracked position is the unit's")
        assert_equal("0.00,0.00,0.10", on_barrel.node, label .. " the interaction node")

        for _, kind in ipairs({ "material_diamantine", "player_teammate" }) do
            local on_floor = target_line(targets, kind)

            assert_equal("inside", on_floor.under, label .. " " .. kind)
            assert_equal("1", on_floor.stack, label .. " " .. kind)
            assert_equal("true", on_floor.selected, label .. " " .. kind)
            assert_equal("true", on_floor.window, label .. " " .. kind)
            assert_equal("true", on_floor.shape, label .. " " .. kind)
            assert_equal("current", on_floor.band, label .. " " .. kind)
            assert_equal("true", on_floor.drawn, label .. " " .. kind)
        end

        assert_equal("-0.05", target_line(targets, "material_diamantine").floor_dz, label)
        assert_equal("-", target_line(targets, "player_teammate").node, label .. " a teammate has no interaction node")
        assert_equal("-", target_line(targets, "enemy_poxwalker").root, label .. " not a live unit")

        local stash_x, stash_y = harness.marker(player, NORTH, stash, range)
        local pickup_x, pickup_y = harness.marker(player, NORTH, floor_pickup, range)
        local mate_x, mate_y = harness.marker(player, NORTH, teammate, range)

        assert_true(not covers(emitted, stash_x, stash_y), label .. " floor drawn under the barrel")
        assert_true(covers(emitted, pickup_x, pickup_y, CURRENT_COLOR), label .. " no floor under the floor pickup")
        assert_true(covers(emitted, mate_x, mate_y, CURRENT_COLOR), label .. " no floor under the teammate")
    end
end)

test("the floor under a nearby target is drawn on the first frame after every zoom", function()
    local harness = new_harness("circle")
    local player = point(0, 0, 0)
    local floor_pickup = point(-3, 2, 0.05)
    local teammate = point(1.5, -0.5, 0)
    local t = 1

    harness.geometry = new_geometry(barrel_floor(point(0, 1.9, 0)))

    for _, overview in ipairs({ false, true }) do
        harness.mod._overview_mode_active = overview

        local ranges = overview and { 25, 137.5, 500, 25, 137.5 } or { 25, 10, 50, 10, 200, 75, 10 }

        for _, range in ipairs(ranges) do
            -- Each zoom comes inside the 0.1 s refresh interval of the one before.
            t = t + 0.03

            local emitted = harness.draw(t, player, NORTH, range)
            local label = (overview and "overview " or "") .. range .. " m"

            for _, target in ipairs({ floor_pickup, teammate }) do
                local x, y = harness.marker(player, NORTH, target, range)

                assert_true(covers(emitted, x, y, CURRENT_COLOR), label .. " a nearby target lost its floor")
            end
        end

        t = t + 1
    end
end)

test("stacked decks and ramps: the floor at the target's own height", function()
    local harness = new_harness("square")
    local player = point(0, 0, 0)
    local triangles = {}

    add_rectangle(triangles, -4, -4, 4, 4, 0)
    add_rectangle(triangles, -2, 0, 2, 4, 4)
    harness.geometry = new_geometry(triangles)
    harness.settings.debug_mode = true
    harness.set_targets({
        { kind = "ammo_crate", position = point(0.5, 1.5, 0.1) },
        { kind = "medical_crate", position = point(-1, 2, 4.05) },
    })

    local emitted = harness.draw(1, player, NORTH, 25)
    local _, targets = probe_lines(harness)
    local below = target_line(targets, "ammo_crate")
    local deck = target_line(targets, "medical_crate")

    assert_equal("inside", below.under, "the lower floor is under the lower target")
    assert_equal("-0.10", below.floor_dz, "its own floor, not the deck above")
    assert_equal("2", below.stack, "both decks lie over the point")
    assert_equal("current", below.band)
    assert_equal("inside", deck.under, "the deck is under the upper target")
    assert_equal("-0.05", deck.floor_dz)
    assert_equal("2", deck.stack)
    assert_equal("above", deck.band, "the deck is a floor above")
    assert_equal("true", deck.drawn, "and drawn as one")

    local deck_x, deck_y = harness.marker(player, NORTH, point(-1, 2), 25)

    assert_true(covers(emitted, deck_x, deck_y, ABOVE_COLOR), "the deck is drawn in the above band")
    assert_true(covers(emitted, deck_x, deck_y, CURRENT_COLOR), "with the lower floor beneath it")

    local ramp_harness = new_harness("circle")

    ramp_harness.geometry = new_geometry({ { -2, 5, 0, 2, 5, 0, 0, 9, 2 } })
    ramp_harness.settings.debug_mode = true
    ramp_harness.set_targets({ { kind = "ammo_crate", position = point(0, 7, 1.05) } })
    ramp_harness.draw(1, point(0, 4.5, 0), NORTH, 25)

    local _, ramp_targets = probe_lines(ramp_harness)
    local on_ramp = target_line(ramp_targets, "ammo_crate")

    assert_equal("inside", on_ramp.under, "the ramp is under the target")
    assert_equal("-0.05", on_ramp.floor_dz, "the ramp's height under the target, not its centre's")
    assert_equal("0.00..2.00", on_ramp.span, "its height span from the player")
end)

test("the probe logs only in debug mode, on a change and once settled, and never changes the draw", function()
    local geometry = new_geometry(barrel_floor(point(0, 1.9, 0)))
    local quiet = new_harness("circle")
    local probed = new_harness("circle")
    local player = point(0, 0, 0)
    local targets = {
        { kind = "material_plasteel", position = point(0, 1.9, 1) },
        { kind = "player_teammate", position = point(1.5, -0.5, 0) },
    }
    local steps = {
        { 1, 25 }, { 1.2, 25 }, { 1.5, 25 }, { 2, 25 },
        { 3, 10 }, { 3.1, 25 }, { 3.2, 50 }, { 3.5, 50 }, { 3.71, 50 }, { 4, 50 }, { 5, 50 },
    }

    quiet.geometry = geometry
    probed.geometry = geometry
    probed.settings.debug_mode = true
    quiet.set_targets(targets)
    probed.set_targets(targets)

    local phases = {}

    for s = 1, #steps do
        local t, range = steps[s][1], steps[s][2]
        local from = #probed.info + 1
        local expected = quiet.draw(t, player, NORTH, range)
        local actual = probed.draw(t, player, NORTH, range)
        local headers, lines = probe_lines(probed, from)

        assert_equal(#expected, #actual, "the probe changed the triangle count")

        for i = 1, #expected do
            for j = 1, 8 do
                assert_equal(expected[i][j], actual[i][j], "the probe changed triangle " .. i)
            end
        end

        if headers[1] then
            phases[#phases + 1] = headers[1].phase .. "@" .. t .. " from=" .. headers[1].from
            assert_equal(2, #lines, "one line per target")
        else
            assert_equal(0, #lines, "target lines without a header")
        end
    end

    assert_equal(0, #quiet.info, "debug mode off logs nothing")
    assert_equal("start@1 from=-|zoom@3 from=25.00|settled@3.71 from=25.00", table.concat(phases, "|"))

    local from = #probed.info + 1

    probed.settings.radar_style = "square"
    probed.draw(6, player, NORTH, 50)
    probed.draw(6.2, player, NORTH, 50, PROJECTION_RADIUS + 40)
    probed.draw(6.5, player, NORTH, 50, PROJECTION_RADIUS + 40)
    probed.draw(6.7, player, NORTH, 50, PROJECTION_RADIUS + 40)

    local headers = probe_lines(probed, from)

    assert_equal(2, #headers, "a new style starts a change, a new radar size while it settles logs nothing more")
    assert_equal("zoom", headers[1].phase)
    assert_equal("square", headers[1].style)
    assert_equal("settled", headers[2].phase, "settled half a second after the latest change")
    assert_equal("172.0", headers[2].radius_px, "on the latest radar size")
end)

test("the probe header carries the draw, the Radar player and the visible set", function()
    local harness = new_harness("circle")

    harness.geometry = new_geometry(barrel_floor(point(0, 1.9, 0)))
    harness.settings.debug_mode = true
    harness.set_targets({})
    harness.draw(1, point(0, 0, 0), NORTH, 25)

    local headers, targets = probe_lines(harness)
    local header = headers[1]

    assert_equal(1, #headers)
    assert_equal(0, #targets, "no targets near")
    assert_equal("start", header.phase)
    assert_equal("25.00", header.range)
    assert_equal("132.0", header.radius_px)
    assert_equal("5.280", header.px_per_m)
    assert_equal("1.333", header.ui_scale)
    assert_equal("circle", header.style)
    assert_equal("false", header.overview)
    assert_equal("+7.0/-7.0", header.floors)
    assert_equal("0.00,0.00,0.00", header.origin)
    assert_equal("0.0000,1.0000", header.forward)
    assert_equal("1", header.player_revision)
    assert_equal(tostring(harness.geometry.revision), header.geometry_revision)
    assert_equal("8", header.triangles)
    assert_equal("true", header.selected_now)
    assert_equal("0", header.selection_age_ms)
    assert_equal("29.00", header.selection_radius)
    assert_equal("8", header.visible)
    assert_equal("0/8/0", header["bands(b/c/a)"])
end)

test("an error inside the probe is logged once and the floor keeps drawing", function()
    local harness = new_harness("circle")
    local player = point(0, 0, 0)

    harness.geometry = new_geometry(barrel_floor(point(0, 1.9, 0)))
    harness.settings.debug_mode = true
    harness.set_targets({ { kind = "broken", position = { x = "not a number", y = 0, z = 0 } } })

    assert_true(#harness.draw(1, player, NORTH, 25) > 0, "the floor is drawn")
    assert_true(#harness.draw(1.1, player, NORTH, 25) > 0, "and keeps drawing")
    assert_true(#harness.draw(2, player, NORTH, 10) > 0, "after the next failing probe too")

    local failures = 0

    for i = 1, #harness.info do
        if harness.info[i]:find("[Radar] live floor probe failed: ", 1, true) then
            failures = failures + 1
        end
    end

    assert_equal(1, failures, "one line per distinct failure")
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
