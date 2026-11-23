-- The Strikemap floor plan: draw order, floor reference, vector filtering and failure isolation.
-- Installs the real Strikemap geometry renderer, compatibility module and triangle clipper
-- against a fake GUI, a fake Strikemap compatibility API and a fake Radar mod. Floors below and
-- their details must sit beneath the current floor's fill whatever order the spatial grid lists
-- them in, the bands must be measured from the deck underfoot and eased, optional vector fields
-- and live revisions must be honoured, a failing step must not take the rest down, and dashes
-- must stay put in the world.

local GEOMETRY_PATH = "Radar/scripts/mods/Radar/ui/Radar_strikemap_geometry.lua"
local CLIPPER_PATH = "Radar/scripts/mods/Radar/ui/Radar_triangle_clipper.lua"
local CENTER_X, CENTER_Y = 110, 310
local UI_SCALE = 4 / 3
local PROJECTION_RADIUS = 142
local START_LAYER = 100
local Z = 3
local LAYER = START_LAYER + Z
local RANGE = 25
local TOLERANCE = 1e-6

local function color_key(a, r, g, b)
    return a .. "," .. r .. "," .. g .. "," .. b
end

local CURRENT_FILL = color_key(80, 101, 133, 96)
local ABOVE_FILL = color_key(32, 120, 150, 185)
local BELOW_FILL = color_key(55, 120, 98, 76)
local FILLS = { [CURRENT_FILL] = "current", [ABOVE_FILL] = "above", [BELOW_FILL] = "below" }

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

--- Returns the upvalue `name` of a function, so a spec can reach module internals.
local function upvalue(fn, name)
    local i = 1

    while true do
        local upname, value = debug.getupvalue(fn, i)

        if upname == nil then
            error("missing upvalue " .. name, 2)
        end

        if upname == name then
            return value
        end

        i = i + 1
    end
end

--- A small deterministic generator, so shuffles and random scenes repeat run to run.
local function new_rng(seed)
    local state = seed

    return function(lo, hi)
        state = (state * 1103515245 + 12345) % 2147483648

        return lo + (hi - lo) * state / 2147483648
    end
end

local function shuffle(list, rng)
    for i = #list, 2, -1 do
        local j = math.floor(rng(1, i + 1))

        if j > i then
            j = i
        end

        list[i], list[j] = list[j], list[i]
    end
end

--- Two triangles covering the rectangle from (x0, y0) to (x1, y1) at height z, appended to `out`.
local function rect(out, x0, y0, x1, y1, z)
    out[#out + 1] = { x0, y0, x1, y0, x1, y1, z }
    out[#out + 1] = { x0, y0, x1, y1, x0, y1, z }

    return out
end

--- Packs triangles into Strikemap's spatial index, each listed in every 16 m cell its bounds touch.
local function pack_index(flat, tri_count, rng)
    local lists, keys = {}, {}

    for i = 1, tri_count do
        local base = (i - 1) * 7
        local min_x = math.min(flat[base + 1], flat[base + 3], flat[base + 5])
        local max_x = math.max(flat[base + 1], flat[base + 3], flat[base + 5])
        local min_y = math.min(flat[base + 2], flat[base + 4], flat[base + 6])
        local max_y = math.max(flat[base + 2], flat[base + 4], flat[base + 6])

        for gx = math.floor(min_x / 16), math.floor(max_x / 16) do
            for gy = math.floor(min_y / 16), math.floor(max_y / 16) do
                local key = gx .. ":" .. gy
                local list = lists[key]

                if not list then
                    list = {}
                    lists[key] = list
                    keys[#keys + 1] = key
                end

                list[#list + 1] = i
            end
        end
    end

    local index = {}

    for k = 1, #keys do
        local list = lists[keys[k]]

        if rng then
            shuffle(list, rng)
        end

        index[keys[k]] = table.concat(list, ",")
    end

    return index
end

--- A map context in Strikemap's layout. `rng`, when given, shuffles the triangle and cell orders.
local function make_context(tris, revision, rng)
    local order = {}

    for i = 1, #tris do
        order[i] = tris[i]
    end

    if rng then
        shuffle(order, rng)
    end

    local flat = {}

    for i = 1, #order do
        for k = 1, 7 do
            flat[(i - 1) * 7 + k] = order[i][k]
        end
    end

    return {
        api_version = 1,
        map_id = "test_map",
        mission_name = "test_map",
        revision = revision,
        triangles = flat,
        tri_count = #order,
        triangle_stride = 7,
        grid_cell = 16,
        spatial_index = pack_index(flat, #order, rng),
    }
end

local function flatten(records, stride)
    local out = {}

    for i = 1, #records do
        for k = 1, stride do
            out[(i - 1) * stride + k] = records[i][k]
        end
    end

    return out, #records
end

--- A vector context in Strikemap's layout from per-layer record lists.
local function make_vectors(revision, layers)
    local vector_context = {
        api_version = 1,
        map_id = "test_map",
        mission_name = "test_map",
        revision = revision,
        contour_stride = 5,
        stair_stride = 6,
        hatch_stride = 5,
        hatch_spacing = 2,
        slope_stride = 5,
        transition_stride = 4,
        transition_chain = layers.transition_chain or {},
        chains = layers.chains or {},
        dead_contours = layers.dead,
    }

    vector_context.contours, vector_context.contour_count = flatten(layers.contours or {}, 5)
    vector_context.stairs, vector_context.stair_count = flatten(layers.stairs or {}, 6)
    vector_context.hatches, vector_context.hatch_count = flatten(layers.hatches or {}, 5)
    vector_context.slopes, vector_context.slope_count = flatten(layers.slopes or {}, 5)
    vector_context.transitions, vector_context.transition_count = flatten(layers.transitions or {}, 4)

    return vector_context
end

--- Loads a fresh renderer, compatibility module and clipper against fakes and returns the harness.
-- `options.vectors == false` leaves `get_vector_context` out of the fake API.
local function new_harness(options)
    options = options or {}

    local harness = {
        emitted = {},
        values = {},
        errors = {},
        infos = {},
        settings = { strikemap_vector_details = true },
        overview = false,
        player_revision = 1,
        status = { available = true, status = "map_loaded", map_loaded = true, geometry_revision = nil },
        context = nil,
        vector_context = nil,
        gui_fail_layer = nil,
    }
    local mod = {}
    local previous = {
        get_mod = rawget(_G, "get_mod"),
        Gui = rawget(_G, "Gui"),
        Vector3 = rawget(_G, "Vector3"),
        Color = rawget(_G, "Color"),
        Quaternion = rawget(_G, "Quaternion"),
    }

    function mod:get(id)
        return harness.settings[id]
    end

    function mod:info(message)
        harness.infos[#harness.infos + 1] = tostring(message)
    end

    function mod:error(format, ...)
        harness.errors[#harness.errors + 1] = string.format(format, ...)
    end

    function mod:is_overview_mode_active()
        return harness.overview
    end

    function mod:get_map_geometry_source()
        return "strikemap"
    end

    function mod:get_radar_color(_, fallback)
        return fallback
    end

    function mod:radar_profiler_value(name, value)
        harness.values[name] = value
    end

    function mod:io_dofile(path)
        return assert(loadfile(path .. ".lua"))()
    end

    local api = {
        api_version = 1,
        get_status = function()
            return harness.status
        end,
        get_map_context = function()
            return harness.context
        end,
        register_consumer = function()
            return true
        end,
        unregister_consumer = function()
            return true
        end,
    }

    if options.vectors ~= false then
        api.get_vector_context = function()
            return harness.vector_context
        end
    end

    local strikemap_mod = {
        is_enabled = function()
            return true
        end,
        get_compatibility_api = function()
            return api
        end,
    }

    rawset(_G, "get_mod", function(name)
        if name == "Radar" then
            return mod
        elseif name == "strikemap" then
            return strikemap_mod
        end

        return nil
    end)
    rawset(_G, "Vector3", setmetatable({
        x = function(v)
            return v[1]
        end,
        y = function(v)
            return v[2]
        end,
    }, {
        __call = function(_, x, y, z)
            return { x, y, z }
        end,
    }))
    rawset(_G, "Color", color_key)
    rawset(_G, "Quaternion", {
        forward = function(rotation)
            return rotation
        end,
    })
    rawset(_G, "Gui", {
        triangle = function(_, a, b, c, layer, color)
            if harness.gui_fail_layer == layer then
                error("gui failure on layer " .. tostring(layer))
            end

            if harness.gui_fail_lower_lines and layer == LAYER and not FILLS[color] then
                error("gui failure on a lower line")
            end

            harness.emitted[#harness.emitted + 1] = { a[1], a[3], b[1], b[3], c[1], c[3], layer = layer, color = color }
        end,
    })

    harness.mod = mod
    harness.geometry = assert(loadfile(GEOMETRY_PATH))()
    harness.clip_and_emit = assert(loadfile(CLIPPER_PATH))()
    harness.compat = mod._strikemap_compatibility

    local draw = harness.geometry.draw
    local select_geometry = upvalue(draw, "_select_geometry")
    local update_floor = upvalue(select_geometry, "_update_floor_reference")

    harness.floor = upvalue(update_floor, "_floor_state")
    harness.sample = upvalue(update_floor, "_sample_floor_height")
    harness.vectors = upvalue(draw, "_vectors")
    harness.bins = upvalue(select_geometry, "_bins")
    harness.pieces = upvalue(select_geometry, "_pieces")
    harness.build_budget = upvalue(upvalue(upvalue(select_geometry, "_ensure_pieces"), "_build_pieces_step"),
        "PIECE_BUILD_BUDGET")

    --- Publishes contexts the way Strikemap does: the status names the context's revision.
    function harness.publish(context, vector_context)
        harness.context = context
        harness.vector_context = vector_context
        harness.status.geometry_revision = context and context.revision or nil
    end

    --- Draws one frame from a player position and returns what was drawn, without the triangle probe.
    function harness.draw(t, player, draw_options)
        draw_options = draw_options or {}
        harness.emitted = {}
        draw({ gui = {}, scale = UI_SCALE, render_settings = { start_layer = START_LAYER } },
            { player_position = player, player_revision = harness.player_revision },
            CENTER_X, CENTER_Y, Z, PROJECTION_RADIUS, draw_options.range or RANGE, draw_options.rotation,
            draw_options.style or "circle", t)

        local out = {}

        for i = 1, #harness.emitted do
            local entry = harness.emitted[i]

            if entry.layer ~= 0 then
                out[#out + 1] = entry
            end
        end

        return out
    end

    function harness.close()
        for name, value in pairs(previous) do
            rawset(_G, name, value)
        end
    end

    return harness
end

--- Converts a screen point back to world coordinates, for the radar basis of `forward` (north-up when nil).
local function to_world(sx, sy, player, forward, range)
    local s = PROJECTION_RADIUS / (range or RANGE)
    local ox = sx / UI_SCALE - CENTER_X
    local oy = sy / UI_SCALE - CENTER_Y
    local fx, fy = 0, 1

    if forward then
        fx, fy = forward[1], forward[2]
    end

    return player.x + (fy * ox - fx * oy) / s, player.y + (-fx * ox - fy * oy) / s
end

local function centroid_world(entry, player, forward, range)
    return to_world((entry[1] + entry[3] + entry[5]) / 3, (entry[2] + entry[4] + entry[6]) / 3, player, forward, range)
end

local function distance_to_segment(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local length_sq = dx * dx + dy * dy
    local t = length_sq > 0 and ((px - x1) * dx + (py - y1) * dy) / length_sq or 0

    t = math.max(0, math.min(1, t))

    local cx, cy = x1 + dx * t, y1 + dy * t

    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
end

--- Names the drawn line triangles by the nearest of the named world segments.
local function classify_lines(emitted, segments, player, forward, range)
    local classes = {}

    for i = 1, #emitted do
        local entry = emitted[i]

        if not FILLS[entry.color] then
            local x, y = centroid_world(entry, player, forward, range)
            local best, best_distance = nil, math.huge

            for name, segment in pairs(segments) do
                local distance = distance_to_segment(x, y, segment[1], segment[2], segment[3], segment[4])

                if distance < best_distance then
                    best, best_distance = name, distance
                end
            end

            classes[i] = best_distance < 1 and best or "unknown"
        else
            classes[i] = FILLS[entry.color] .. "_fill"
        end
    end

    return classes
end

local function count_class(emitted, classes, name, layer)
    local n = 0

    for i = 1, #emitted do
        if classes[i] == name and (layer == nil or emitted[i].layer == layer) then
            n = n + 1
        end
    end

    return n
end

local function count_layer(emitted, layer)
    local n = 0

    for i = 1, #emitted do
        if emitted[i].layer == layer then
            n = n + 1
        end
    end

    return n
end

local function count_fill(emitted, color)
    local n = 0

    for i = 1, #emitted do
        if emitted[i].color == color then
            n = n + 1
        end
    end

    return n
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

-- ----------------------------------------------------------------------------
-- Draw order
-- ----------------------------------------------------------------------------

--- Three stacked decks over the same ground, with one segment of every vector class.
local STACKED_SEGMENTS = {
    below_hatch = { -8, -5, -2, -5, -4 },
    below_contour = { -8, 5, -2, 5, -4 },
    above_hatch = { 2, -5, 8, -5, 4 },
    above_contour = { 2, 5, 8, 5, 4 },
    slope = { -5, 8, 5, 8, 0 },
    wall = { -5, -8, 5, -8, 0 },
    stair = { 0, 3, 3, 3, -0.4, 0.4 },
}

local function stacked_scene()
    local tris = {}

    rect(tris, -10, -10, 10, 10, -4)
    rect(tris, -10, -10, 10, 10, 0)
    rect(tris, -10, -10, 10, 10, 4)

    local s = STACKED_SEGMENTS
    local layers = {
        contours = { s.below_contour, s.above_contour, s.wall },
        hatches = { s.below_hatch, s.above_hatch },
        slopes = { s.slope },
        stairs = { s.stair },
        transitions = { { 1.5, 3, -0.5, 0.5 } },
        transition_chain = { 1 },
        chains = { { zlo = -0.5, zhi = 0.5, steep = true } },
    }

    return tris, layers
end

--- Returns the first and last position of a class on a layer, or nil when it is absent.
local function span(emitted, classes, name, layer)
    local first, last

    for i = 1, #emitted do
        if classes[i] == name and emitted[i].layer == layer then
            first = first or i
            last = i
        end
    end

    return first, last
end

--- A canonical, order-free description of what a layer received.
local function layer_signature(emitted, layer)
    local items = {}

    for i = 1, #emitted do
        local entry = emitted[i]

        if entry.layer == layer then
            items[#items + 1] = string.format("%s|%.4f,%.4f|%.4f,%.4f|%.4f,%.4f", tostring(entry.color),
                entry[1], entry[2], entry[3], entry[4], entry[5], entry[6])
        end
    end

    table.sort(items)

    return table.concat(items, ";")
end

for _, style in ipairs({ "circle", "square" }) do
    test(style .. ": floors and their details draw in a fixed order on fixed layers, whatever the grid order",
        function()
            local player = { x = 1, y = 1, z = 0.1 }
            local reference = nil

            for seed = 1, 5 do
                local harness = new_harness()
                local tris, layers = stacked_scene()
                local rng = seed > 1 and new_rng(seed * 7919) or nil

                harness.settings.strikemap_hatch_above = true
                harness.publish(make_context(tris, 1, rng), make_vectors(1, layers))

                local emitted = harness.draw(1, player, { style = style })
                local classes = classify_lines(emitted, STACKED_SEGMENTS, player)

                harness.close()

                for i = 1, #classes do
                    assert_true(classes[i] ~= "unknown", "an unexpected line was drawn")
                end

                local expected_layers = {
                    below_fill = LAYER, current_fill = LAYER, above_fill = LAYER, below_hatch = LAYER,
                    below_contour = LAYER, above_hatch = LAYER + 1, slope = LAYER + 1, above_contour = LAYER + 2,
                    wall = LAYER + 2,
                }

                for name, layer in pairs(expected_layers) do
                    assert_true(count_class(emitted, classes, name, layer) > 0, name .. " was not drawn on its layer")
                    assert_equal(count_class(emitted, classes, name), count_class(emitted, classes, name, layer),
                        name .. " landed on another layer")
                end

                assert_equal(0, count_class(emitted, classes, "stair"), "a stair record was drawn")

                local _, below_fill_last = span(emitted, classes, "below_fill", LAYER)
                local below_hatch_first, below_hatch_last = span(emitted, classes, "below_hatch", LAYER)
                local below_contour_first, below_contour_last = span(emitted, classes, "below_contour", LAYER)
                local current_first, current_last = span(emitted, classes, "current_fill", LAYER)
                local above_first = span(emitted, classes, "above_fill", LAYER)

                assert_true(below_fill_last < below_hatch_first, "lower hatching was drawn under the lower fill")
                assert_true(below_hatch_last < below_contour_first, "lower outlines were drawn under lower hatching")
                assert_true(below_contour_last < current_first, "lower details were drawn over the current floor")
                assert_true(current_last < above_first, "the floor above was drawn under the current floor")

                local _, above_hatch_last = span(emitted, classes, "above_hatch", LAYER + 1)
                local slope_first = span(emitted, classes, "slope", LAYER + 1)
                local _, above_contour_last = span(emitted, classes, "above_contour", LAYER + 2)
                local wall_first = span(emitted, classes, "wall", LAYER + 2)

                assert_true(above_hatch_last < slope_first, "upper hatching was drawn over the slope marks")
                assert_true(above_contour_last < wall_first, "upper outlines were drawn over the walls")

                local signature = layer_signature(emitted, LAYER) .. "#" .. layer_signature(emitted, LAYER + 1)
                    .. "#" .. layer_signature(emitted, LAYER + 2)

                if reference == nil then
                    reference = signature
                else
                    assert_equal(reference, signature, "the grid order changed what a layer received")
                end
            end
        end)
end

--- What the renderer must draw with vectors off: every band's triangles, clipped, in band order.
local function expected_fills(harness, context, player, ref_z, forward, style, range)
    local emitted = {}
    local recorder = {
        triangle = function(_, a, b, c, layer, color)
            emitted[#emitted + 1] = { a[1], a[3], b[1], b[3], c[1], c[3], layer = layer, color = color }
        end,
    }
    local previous_gui = rawget(_G, "Gui")

    rawset(_G, "Gui", recorder)

    local clip_and_emit = assert(loadfile(CLIPPER_PATH))()

    rawset(_G, "Gui", previous_gui)

    local triangles = context.triangles
    local s = PROJECTION_RADIUS / range
    local ax, ay, bx, by = s, 0, 0, -s

    if forward then
        ax, ay, bx, by = forward[2] * s, -forward[1] * s, -forward[1] * s, -forward[2] * s
    end

    local cull = range * 1.4143
    local seen = {}
    local bands = { {}, {}, {} }

    for cx = math.floor((player.x - cull) / 16), math.floor((player.x + cull) / 16) do
        for cy = math.floor((player.y - cull) / 16), math.floor((player.y + cull) / 16) do
            local packed = context.spatial_index[cx .. ":" .. cy]

            if packed then
                for token in packed:gmatch("[^,]+") do
                    local i = tonumber(token)

                    if not seen[i] then
                        seen[i] = true

                        local dz = triangles[i * 7] - ref_z

                        if dz <= 7 and dz >= -7 then
                            local band = dz > 2.5 and 3 or (dz < -2.5 and 1 or 2)

                            bands[band][#bands[band] + 1] = i
                        end
                    end
                end
            end
        end
    end

    local colors = { BELOW_FILL, CURRENT_FILL, ABOVE_FILL }
    local limit = PROJECTION_RADIUS

    for band = 1, 3 do
        for k = 1, #bands[band] do
            local base = (bands[band][k] - 1) * 7
            local p = {}

            for v = 0, 2 do
                local dx = triangles[base + v * 2 + 1] - player.x
                local dy = triangles[base + v * 2 + 2] - player.y

                p[v * 2 + 1] = dx * ax + dy * ay
                p[v * 2 + 2] = dx * bx + dy * by
            end

            if not ((p[1] > limit and p[3] > limit and p[5] > limit) or (p[1] < -limit and p[3] < -limit and p[5] < -limit)
                    or (p[2] > limit and p[4] > limit and p[6] > limit)
                    or (p[2] < -limit and p[4] < -limit and p[6] < -limit)) then
                clip_and_emit({}, LAYER, colors[band], style == "circle", limit, limit * limit, UI_SCALE, CENTER_X,
                    CENTER_Y, p[1], p[2], p[3], p[4], p[5], p[6])
            end
        end
    end

    return emitted
end

for _, style in ipairs({ "circle", "square", "auspex" }) do
    test(style .. ": the fills are the shared clipper's output for each band in band order", function()
        for seed = 1, 3 do
            for _, forward in ipairs({ false, { 0.6, 0.8 } }) do
                local rng = new_rng(seed * 104729)
                local tris = {}

                rect(tris, 0, -6, 7, 1, 0)

                for _ = 1, 60 do
                    local x, y = rng(-40, 40), rng(-40, 40)
                    local z = math.floor(rng(-9, 9))

                    tris[#tris + 1] = { x, y, x + rng(-6, 6), y + rng(-6, 6), x + rng(-6, 6), y + rng(-6, 6), z }
                end

                local harness = new_harness()
                local context = make_context(tris, 1, rng)
                local player = { x = 3.5, y = -2.25, z = 0.3 }

                harness.settings.strikemap_vector_details = false
                harness.publish(context, nil)

                local actual = harness.draw(1, player, { style = style, rotation = forward or nil })
                local ref_z = harness.floor.display_z

                harness.close()

                assert_near(0, ref_z, TOLERANCE, "the deck underfoot is not the reference")

                local expected = expected_fills(harness, context, player, ref_z, forward or nil, style, RANGE)

                assert_equal(#expected, #actual, "triangle count")

                for i = 1, #expected do
                    assert_equal(expected[i].layer, actual[i].layer, "layer of triangle " .. i)
                    assert_equal(expected[i].color, actual[i].color, "colour of triangle " .. i)

                    for k = 1, 6 do
                        assert_near(expected[i][k], actual[i][k], 1e-9, "vertex of triangle " .. i)
                    end
                end
            end
        end
    end)
end

-- ----------------------------------------------------------------------------
-- Floor reference
-- ----------------------------------------------------------------------------

test("the floor reference is the deck underfoot, not an overhang, a pit floor or the raw height", function()
    local tris = {}

    rect(tris, 0, 0, 10, 10, 0)
    rect(tris, 0, 0, 10, 10, 6)
    rect(tris, 20, 0, 30, 10, 0)
    rect(tris, 20, 0, 30, 10, 2)
    rect(tris, 40, 0, 44, 10, 0)
    rect(tris, 36, -10, 60, 20, -6)

    local harness = new_harness()

    harness.publish(make_context(tris, 1), nil)
    harness.draw(1, { x = 5, y = 5, z = 0.1 })

    local sample = harness.sample

    assert_near(0, sample(5, 5, 0.1), TOLERANCE, "standing on the lower of two stacked decks")
    assert_near(6, sample(5, 5, 6.1), TOLERANCE, "standing on the upper of two stacked decks")
    assert_near(0, sample(5, 5, 0.4), TOLERANCE, "a player origin above the floor plan")
    assert_near(0, sample(25, 5, 1.1), TOLERANCE, "jumping under an overhang that is nearer than the floor")
    assert_near(2, sample(25, 5, 2.1), TOLERANCE, "standing on the overhang")
    assert_near(0, sample(44.5, 5, 0.1), TOLERANCE, "at a pit's edge, the pit floor took over")
    assert_near(-6, sample(44.5, 5, -5.9), TOLERANCE, "at the bottom of the pit")
    assert_equal(nil, sample(500, 500, 0), "a point with no triangles anywhere near")
    assert_equal(nil, sample(5, 5, 20), "a floor far below a flying player")

    harness.close()
end)

test("the floor reference re-samples after the player moved a quarter metre and eases towards a new floor", function()
    local tris = {}

    rect(tris, 0, 0, 10, 10, 0)
    rect(tris, 10, 0, 20, 10, 3)

    local harness = new_harness()
    local floor = harness.floor

    harness.publish(make_context(tris, 1), nil)
    harness.draw(1, { x = 5, y = 5, z = 0.1 })
    assert_near(0, floor.display_z, TOLERANCE, "the first draw takes the pick at once")
    assert_near(5, floor.sample_x, TOLERANCE, "sample position")

    harness.draw(1.1, { x = 5.2, y = 5, z = 0.1 })
    assert_near(5, floor.sample_x, TOLERANCE, "a 0.2 m step picked again")

    harness.draw(1.2, { x = 5.3, y = 5, z = 0.1 })
    assert_near(5.3, floor.sample_x, TOLERANCE, "a 0.3 m step did not pick again")

    harness.draw(1.3, { x = 5.3, y = 5, z = 0.45 })
    assert_near(0.45, floor.sample_z, TOLERANCE, "a 0.35 m jump did not pick again")
    assert_near(0, floor.target_z, TOLERANCE, "a jump moved the floor")

    harness.draw(1.4, { x = 15, y = 5, z = 3.1 })
    assert_near(3, floor.target_z, TOLERANCE, "the raised floor")
    assert_near(3 * (1 - math.exp(-0.1 / 0.24)), floor.display_z, 1e-9, "one 0.1 s easing step")

    local before = floor.display_z

    harness.draw(1.8, { x = 15, y = 5, z = 3.1 })
    assert_near(before + (3 - before) * (1 - math.exp(-0.1 / 0.24)), floor.display_z, 1e-9,
        "a 0.4 s gap eased by more than one 0.1 s step")

    for step = 1, 12 do
        harness.draw(1.8 + step * 0.1, { x = 15, y = 5, z = 3.1 })
    end

    assert_near(3, floor.display_z, 0.05, "the reference did not converge")

    harness.close()
end)

test("the floor reference snaps for a new Radar player, a new source, a shrinking map or a pause, and eases across a live revision",
    function()
        local tris = {}

        rect(tris, 0, 0, 10, 10, 0)
        rect(tris, 10, 0, 20, 10, 3)

        local harness = new_harness()
        local floor = harness.floor
        local context = make_context(tris, 1)

        harness.publish(context, nil)
        harness.draw(1, { x = 5, y = 5, z = 0.1 })
        harness.draw(1.1, { x = 15, y = 5, z = 3.1 })
        assert_true(floor.display_z < 2, "the reference jumped to the raised floor")

        harness.player_revision = 2
        harness.draw(1.2, { x = 15, y = 5, z = 3.1 })
        assert_near(3, floor.display_z, TOLERANCE, "a new Radar player eased")

        harness.draw(1.3, { x = 5, y = 5, z = 0.1 })
        assert_true(floor.display_z > 1, "a same-player move snapped")

        local fresh = make_context(tris, 2)

        harness.publish(fresh, nil)
        harness.draw(1.6, { x = 5, y = 5, z = 0.1 })
        assert_near(0, floor.display_z, TOLERANCE, "a new triangle array eased")

        harness.draw(1.7, { x = 15, y = 5, z = 3.1 })

        local shrunk = {}

        for key, value in pairs(fresh) do
            shrunk[key] = value
        end

        shrunk.tri_count = 2
        shrunk.revision = 3
        shrunk.spatial_index = pack_index(fresh.triangles, 2)
        harness.publish(shrunk, nil)
        harness.draw(1.95, { x = 5, y = 5, z = 0.1 })
        assert_near(0, floor.display_z, TOLERANCE, "a map with fewer triangles eased")

        harness.draw(2.0, { x = 15, y = 5, z = 3.1 })
        assert_true(math.abs(floor.display_z - floor.target_z) > 1, "the move to the raised spot snapped")
        harness.draw(2.6, { x = 15, y = 5, z = 3.1 })
        assert_near(floor.target_z, floor.display_z, TOLERANCE, "a pause of more than half a second eased")

        local grown = {}

        for key, value in pairs(shrunk) do
            grown[key] = value
        end

        grown.tri_count = 4
        grown.revision = 4
        grown.spatial_index = pack_index(fresh.triangles, 4)
        harness.draw(2.7, { x = 15, y = 5, z = 3.4 })
        assert_near(3.4, floor.target_z, TOLERANCE, "with no floor under the player, the raw height")
        harness.publish(grown, nil)

        local before = floor.display_z

        harness.draw(2.9, { x = 15, y = 5, z = 3.4 })
        assert_near(3, floor.target_z, TOLERANCE, "a live revision did not pick again from the new grid")
        assert_true(math.abs(floor.display_z - floor.target_z) > 0.05, "a live revision of the same map snapped")
        assert_true(floor.display_z < before, "a live revision of the same map stopped easing")

        harness.close()
    end)

-- ----------------------------------------------------------------------------
-- Optional vector fields
-- ----------------------------------------------------------------------------

local function wall_scene(revision, layers)
    local tris = {}

    rect(tris, -12, -12, 12, 12, 0)

    return make_context(tris, revision), make_vectors(revision, layers)
end

test("vectors are optional, and dead contours are skipped, also when the set grows in place", function()
    local player = { x = 0, y = 0, z = 0.1 }
    local walls = { { -6, -6, 6, -6, 0 }, { -6, 0, 6, 0, 0 }, { -6, 6, 6, 6, 0 } }
    local segments = { a = walls[1], b = walls[2], c = walls[3] }

    local harness = new_harness({ vectors = false })
    local context = wall_scene(1, { contours = walls })

    harness.publish(context, nil)

    local emitted = harness.draw(1, player)

    assert_true(count_fill(emitted, CURRENT_FILL) > 0, "no fill without a vector API")
    assert_equal(0, count_layer(emitted, LAYER + 2), "lines without a vector API")
    harness.close()

    harness = new_harness()
    context = wall_scene(1, { contours = walls })

    local _, vector_context = wall_scene(1, { contours = walls })

    harness.publish(context, vector_context)
    harness.settings.strikemap_vector_details = false
    emitted = harness.draw(1, player)
    assert_true(count_fill(emitted, CURRENT_FILL) > 0, "no fill with details off")
    assert_equal(0, count_layer(emitted, LAYER + 2), "lines with details off")

    harness.settings.strikemap_vector_details = true
    emitted = harness.draw(1.1, player)

    local classes = classify_lines(emitted, segments, player)

    assert_true(count_class(emitted, classes, "a") > 0 and count_class(emitted, classes, "b") > 0
        and count_class(emitted, classes, "c") > 0, "a wall is missing without dead contours")
    harness.close()

    harness = new_harness()

    local dead = { [2] = true }

    context, vector_context = wall_scene(1, { contours = walls, dead = dead })
    harness.publish(context, vector_context)
    emitted = harness.draw(1, player)
    classes = classify_lines(emitted, segments, player)
    assert_true(count_class(emitted, classes, "a") > 0, "a live wall was skipped")
    assert_equal(0, count_class(emitted, classes, "b"), "a dead contour was drawn")

    dead[3] = true
    emitted = harness.draw(1.1, player)
    classes = classify_lines(emitted, segments, player)
    assert_true(count_class(emitted, classes, "a") > 0, "a live wall was skipped after the set grew")
    assert_equal(0, count_class(emitted, classes, "c"), "a contour that died in place was still drawn")
    harness.close()

    harness = new_harness()
    context, vector_context = wall_scene(1, { contours = walls })
    vector_context.dead_contours = 5
    harness.publish(context, vector_context)
    emitted = harness.draw(1, player)
    assert_true(count_fill(emitted, CURRENT_FILL) > 0, "a malformed dead contour set hid the floor")
    assert_equal(0, count_layer(emitted, LAYER + 2), "a malformed dead contour set still drew vectors")

    local logged = false

    for i = 1, #harness.infos do
        if harness.infos[i]:find("dead_contours field is not a table", 1, true) then
            logged = true
        end
    end

    assert_true(logged, "the malformed dead contour set was not named in the log")
    harness.close()
end)

test("stair records are never drawn, not even at a steep chain's anchor on the current floor", function()
    local player = { x = 0, y = 0, z = 0.1 }
    local ticks = {
        near = { 1, -0.5, 3, -0.5, -0.3, 0.3 },
        across = { -1, 2, 1, 4, -0.2, 0.6 },
        deep = { 7, -7, 9, -7, -5.5, -4.5 },
    }

    for _, with_anchors in ipairs({ true, false }) do
        local layers = { stairs = { ticks.near, ticks.across, ticks.deep } }

        if with_anchors then
            layers.transitions = { { 0, 0, 0.5, -0.5 }, { 0, 3, -0.5, 0.5 }, { 8, -7, -5.5, -4.5 } }
            layers.transition_chain = { 1, 1, 1 }
            layers.chains = { { zlo = -6, zhi = 6, steep = true } }
        end

        local harness = new_harness()
        local context, vector_context = wall_scene(1, layers)

        harness.settings.navmesh_range_below = 10
        harness.publish(context, vector_context)

        local emitted = harness.draw(1, player)
        local classes = classify_lines(emitted, ticks, player)

        for name in pairs(ticks) do
            assert_equal(0, count_class(emitted, classes, name), "the " .. name .. " stair record was drawn")
        end

        assert_equal(0, count_layer(emitted, LAYER + 2), "a line was drawn on the top layer without walls")
        assert_equal(nil, harness.vectors.stairs, "the stair records got an index")
        assert_true(harness.vectors.contours ~= nil, "the vector layers were not built")
        harness.close()
    end
end)

test("slope marks stay on the current floor and upper decks are hatched only with the toggle", function()
    local player = { x = 0, y = 0, z = 0.1 }
    local tris = {}

    rect(tris, -12, -12, 12, 12, 0)
    rect(tris, -12, -12, 12, 12, -4)
    rect(tris, -12, -12, 12, 12, 4)

    local segments = {
        slope_current = { -8, 8, 8, 8, 0 },
        slope_below = { -8, 4, 8, 4, -4 },
        slope_above = { -8, 0, 8, 0, 4 },
        hatch_current = { -8, -2, 8, -2, 0 },
        hatch_below = { -8, -5, 8, -5, -4 },
        hatch_above = { -8, -9, 8, -9, 4 },
    }
    local layers = {
        slopes = { segments.slope_current, segments.slope_below, segments.slope_above },
        hatches = { segments.hatch_current, segments.hatch_below, segments.hatch_above },
    }

    local harness = new_harness()

    harness.publish(make_context(tris, 1), make_vectors(1, layers))

    local emitted = harness.draw(1, player)
    local classes = classify_lines(emitted, segments, player)

    assert_true(count_class(emitted, classes, "slope_current", LAYER + 1) >= 4,
        "the current floor's slope marks are not dashed on the marks layer")
    assert_equal(0, count_class(emitted, classes, "slope_below"), "a lower floor got slope marks")
    assert_equal(0, count_class(emitted, classes, "slope_above"), "an upper floor got slope marks")
    assert_equal(0, count_class(emitted, classes, "hatch_current"), "the current floor got hatched")
    assert_true(count_class(emitted, classes, "hatch_below", LAYER) > 0, "the floor below lost its hatching")
    assert_equal(0, count_class(emitted, classes, "hatch_above"), "an upper deck was hatched with the toggle off")

    harness.settings.strikemap_hatch_above = true
    emitted = harness.draw(1.1, player)
    classes = classify_lines(emitted, segments, player)
    assert_true(count_class(emitted, classes, "hatch_above", LAYER + 1) > 0, "the toggle did not hatch upper decks")
    harness.close()
end)

-- ----------------------------------------------------------------------------
-- Live revisions and failures
-- ----------------------------------------------------------------------------

test("live revisions draw triangles and segments added in place, and a reset clears the floor reference", function()
    local player = { x = 0, y = 0, z = 0.1 }
    local tris = rect({}, -4, -4, 4, 4, 0)
    local harness = new_harness()
    local context = make_context(tris, 1)
    local vector_context = make_vectors(1, { contours = { { -3, -3, 3, -3, 0 } } })

    harness.publish(context, vector_context)

    local emitted = harness.draw(1, player)

    assert_equal(2, harness.values.draw_geometry_in_shape, "triangles before the revision")

    local added = rect({}, 6, 6, 12, 12, 0)

    for i = 1, #added do
        for k = 1, 7 do
            context.triangles[(2 + i - 1) * 7 + k] = added[i][k]
        end
    end

    context.tri_count = 4
    context.revision = 2
    context.spatial_index = pack_index(context.triangles, 4)

    local contours = vector_context.contours

    for k, value in ipairs({ 7, 9, 11, 9, 0 }) do
        contours[5 + k] = value
    end

    vector_context.contour_count = 2
    vector_context.revision = 2
    harness.publish(context, vector_context)
    emitted = harness.draw(1.1, player)
    assert_equal(2, harness.values.draw_geometry_in_shape, "the cached revision changed before the poll")

    emitted = harness.draw(1.3, player)
    assert_equal(4, harness.values.draw_geometry_in_shape, "triangles added in place were not drawn")

    local classes = classify_lines(emitted, { old = { -3, -3, 3, -3 }, new = { 7, 9, 11, 9 } }, player)

    assert_true(count_class(emitted, classes, "new", LAYER + 2) > 0, "a contour added in place was not drawn")
    assert_true(count_class(emitted, classes, "old", LAYER + 2) > 0, "the old contour was lost")

    harness.mod:reset_strikemap_integration()
    assert_equal(nil, harness.floor.display_z, "the reset kept the floor reference")
    assert_equal(nil, harness.floor.triangles, "the reset kept the source map")
    harness.close()
end)

test("a failing vector step leaves the fills drawing, and a failing geometry step stops the layer", function()
    local player = { x = 0, y = 0, z = 0.1 }
    local tris = {}

    rect(tris, -8, -8, 8, 8, 0)
    rect(tris, -8, -8, 8, 8, 4)

    local harness = new_harness()
    local vector_context = make_vectors(1, { contours = { { -3, -3, 3, -3, 0 }, { -3, 0, 3, 0, 0 },
        { -3, 3, 3, 3, 0 } } })

    vector_context.contours[6] = nil
    harness.publish(make_context(tris, 1), vector_context)

    local emitted = harness.draw(1, player)

    assert_true(count_fill(emitted, CURRENT_FILL) > 0, "a vector selection error hid the current floor")
    assert_true(count_fill(emitted, ABOVE_FILL) > 0, "a vector selection error hid the floor above")
    assert_equal(0, count_layer(emitted, LAYER + 1) + count_layer(emitted, LAYER + 2),
        "details were drawn after the vector selection failed")
    assert_equal(nil, harness.compat._vector_context, "the failed vector context was kept")

    emitted = harness.draw(1.1, player)
    assert_true(count_fill(emitted, CURRENT_FILL) > 0, "the floor was lost after a vector error")
    harness.close()

    harness = new_harness()
    harness.publish(make_context(tris, 1), make_vectors(1, { contours = { { -3, -3, 3, -3, 0 } } }))
    harness.gui_fail_layer = LAYER + 2
    emitted = harness.draw(1, player)
    assert_true(count_fill(emitted, CURRENT_FILL) > 0 and count_fill(emitted, ABOVE_FILL) > 0,
        "a vector draw error hid the fills")
    assert_equal(nil, harness.compat._vector_context, "a vector draw error kept the vector context")
    assert_equal(nil, harness.vectors.context, "a vector draw error kept the vector indices")

    harness.gui_fail_layer = nil
    emitted = harness.draw(1.1, player)
    assert_true(count_fill(emitted, CURRENT_FILL) > 0, "the floor was lost after a vector draw error")
    assert_equal(0, count_layer(emitted, LAYER + 2), "vectors came back in the failed revision")
    harness.close()

    harness = new_harness()

    local below = {}

    rect(below, -8, -8, 8, 8, -4)

    for i = 1, #below do
        tris[#tris + 1] = below[i]
    end

    harness.publish(make_context(tris, 1), make_vectors(1, { contours = { { -3, -3, 3, -3, 0 },
        { -3, 3, 3, 3, -4 } } }))
    harness.gui_fail_lower_lines = true
    emitted = harness.draw(1, player)
    assert_true(count_fill(emitted, CURRENT_FILL) > 0 and count_fill(emitted, ABOVE_FILL) > 0,
        "a lower vector draw error hid the fills")
    assert_equal(0, count_layer(emitted, LAYER + 2), "the upper vectors were drawn after the lower vectors failed")
    assert_equal(nil, harness.compat._vector_context, "a lower vector draw error kept the vector context")

    local disabled = 0

    for i = 1, #harness.infos do
        if harness.infos[i]:find("vector details disabled", 1, true) then
            disabled = disabled + 1
        end
    end

    assert_equal(1, disabled, "the upper vector step ran after the lower one failed")
    harness.close()

    harness = new_harness()

    local broken = make_context(tris, 1)

    broken.triangles[7] = nil
    harness.publish(broken, nil)
    emitted = harness.draw(1, player)
    assert_equal("error", harness.compat._status, "a geometry error did not stop the layer")
    assert_true(#harness.errors > 0, "the geometry error was not logged")

    emitted = harness.draw(1.5, player)
    assert_equal(0, #emitted, "the layer kept drawing after a geometry error")
    harness.close()
end)

-- ----------------------------------------------------------------------------
-- Dashes and shapes
-- ----------------------------------------------------------------------------

--- Returns the world intervals, along a line's canonical direction, of the dashes drawn for it.
-- Dashes touching a clip end are left out, since clipping legitimately shortens them.
local function dash_intervals(emitted, line, player, forward, range)
    local x1, y1, x2, y2 = line[1], line[2], line[3], line[4]

    if x2 < x1 or (x2 == x1 and y2 < y1) then
        x1, y1, x2, y2 = x2, y2, x1, y1
    end

    local length = math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
    local ux, uy = (x2 - x1) / length, (y2 - y1) / length
    local quads = {}

    for i = 1, #emitted do
        if not FILLS[emitted[i].color] then
            quads[#quads + 1] = emitted[i]
        end
    end

    local intervals = {}
    local limit = PROJECTION_RADIUS - 1

    for q = 1, #quads - 1, 2 do
        local first, second = quads[q], quads[q + 1]
        local ax, ay = (second[1] + second[5]) / 2, (second[2] + second[6]) / 2
        local bx, by = (first[3] + first[5]) / 2, (first[4] + first[6]) / 2
        local inside = true

        for _, p in ipairs({ { ax, ay }, { bx, by } }) do
            local ox, oy = p[1] / UI_SCALE - CENTER_X, p[2] / UI_SCALE - CENTER_Y

            if ox * ox + oy * oy > limit * limit then
                inside = false
            end
        end

        if inside then
            local wax, way = to_world(ax, ay, player, forward, range)
            local wbx, wby = to_world(bx, by, player, forward, range)
            local s1 = wax * ux + way * uy
            local s2 = wbx * ux + wby * uy

            if s1 > s2 then
                s1, s2 = s2, s1
            end

            intervals[string.format("%d:%d", math.floor(s1 * 1e5 + 0.5), math.floor(s2 * 1e5 + 0.5))] = true
        end
    end

    return intervals
end

local function common_intervals(a, b)
    local n = 0

    for key in pairs(a) do
        if b[key] then
            n = n + 1
        end
    end

    return n
end

local function interval_count(set)
    local n = 0

    for _ in pairs(set) do
        n = n + 1
    end

    return n
end

test("dashes stay on the same world positions under clipping, rotation, direction and zoom within one period step",
    function()
        local tris = {}

        rect(tris, -60, -60, 60, 60, -4)
        rect(tris, -60, -60, 60, 60, 0)

        local line = { -40, 3, 40, 7, -4 }
        local reversed = { 40, 7, -40, 3, -4 }

        local function draw_dashes(segment, player, forward, range)
            local harness = new_harness()

            harness.settings.navmesh_range_below = 10
            harness.publish(make_context(tris, 1), make_vectors(1, { contours = { segment } }))

            local emitted = harness.draw(1, player, { rotation = forward, range = range })

            harness.close()

            local lines = {}

            for i = 1, #emitted do
                if emitted[i].layer == LAYER and not FILLS[emitted[i].color] then
                    lines[#lines + 1] = emitted[i]
                end
            end

            return dash_intervals(lines, segment, player, forward, range)
        end

        local base = draw_dashes(line, { x = 0, y = 0, z = 0.1 })

        assert_true(interval_count(base) >= 6, "too few dashes to compare")

        local shifted = draw_dashes(line, { x = 6, y = 2, z = 0.1 })
        local shared = common_intervals(base, shifted)

        assert_true(shared >= 4, "dashes moved when the clipping changed (" .. shared .. " shared)")

        local turned = draw_dashes(line, { x = 0, y = 0, z = 0.1 }, { 0.6, 0.8 })

        assert_equal(interval_count(base), common_intervals(base, turned), "dashes moved when the radar turned")

        local flipped = draw_dashes(reversed, { x = 0, y = 0, z = 0.1 })

        assert_equal(interval_count(base), common_intervals(base, flipped), "dashes depend on the segment direction")

        local zoomed = draw_dashes(line, { x = 0, y = 0, z = 0.1 }, nil, 30)

        assert_true(interval_count(zoomed) > interval_count(base), "zooming out showed no more dashes")
        assert_equal(interval_count(base), common_intervals(base, zoomed), "dashes moved within one period step of zoom")

        local harness = new_harness()
        local player = { x = 0, y = 0, z = 0.1 }

        harness.settings.navmesh_range_below = 10
        harness.publish(make_context(tris, 1), make_vectors(1, { contours = { { -40, 3, 1, 5.05, -4 },
            { 1, 5.05, 40, 7, -4 } } }))

        local emitted = harness.draw(1, player)

        harness.close()

        local lines = {}

        for i = 1, #emitted do
            if emitted[i].layer == LAYER and not FILLS[emitted[i].color] then
                lines[#lines + 1] = emitted[i]
            end
        end

        local split = dash_intervals(lines, line, player)
        local length = math.sqrt(80 * 80 + 4 * 4)
        local split_at = (1 * 80 + 5.05 * 4) / length
        local whole = 0

        for key in pairs(base) do
            local s1, s2 = key:match("^(-?%d+):(-?%d+)$")

            s1, s2 = tonumber(s1) / 1e5, tonumber(s2) / 1e5

            if not (s1 < split_at and s2 > split_at) then
                whole = whole + 1
                assert_true(split[key] == true, "a collinear piece did not continue the dash pattern")
            end
        end

        assert_true(whole >= 6, "too few dashes away from the split point")
    end)

test("dashes never need more quads than the old screen-space pattern", function()
    local rng = new_rng(424242)
    local tris = {}

    rect(tris, -60, -60, 60, 60, -4)
    rect(tris, -60, -60, 60, 60, 0)

    local segments = {}
    local old_quads = 0
    local s = PROJECTION_RADIUS / RANGE

    for _ = 1, 150 do
        local cx, cy = rng(-12, 12), rng(-12, 12)
        local angle = rng(0, math.pi * 2)
        local half = rng(0.3, 4)
        local x1, y1 = cx - math.cos(angle) * half, cy - math.sin(angle) * half
        local x2, y2 = cx + math.cos(angle) * half, cy + math.sin(angle) * half

        segments[#segments + 1] = { x1, y1, x2, y2, -4 }

        local length = 2 * half * s * UI_SCALE
        local period, on = 7 * UI_SCALE, 4 * UI_SCALE
        local pos = 0

        while pos < length do
            if math.min(pos + on, length) - pos >= 0.5 then
                old_quads = old_quads + 1
            end

            pos = pos + period
        end
    end

    local harness = new_harness()

    harness.publish(make_context(tris, 1), make_vectors(1, { contours = segments }))

    local emitted = harness.draw(1, { x = 0, y = 0, z = 0.1 })
    local line_triangles = 0

    for i = 1, #emitted do
        if emitted[i].layer == LAYER and not FILLS[emitted[i].color] then
            line_triangles = line_triangles + 1
        end
    end

    harness.close()
    assert_true(line_triangles > 0, "no dashes drawn")
    assert_true(line_triangles / 2 <= old_quads, "more dash quads (" .. line_triangles / 2 .. ") than the old pattern ("
        .. old_quads .. ")")
end)

for _, style in ipairs({ "circle", "square", "auspex" }) do
    test(style .. ": fills and lines stay inside the radar shape, walls included", function()
        for _, forward in ipairs({ false, { 0.28, 0.96 }, { -0.8, -0.6 } }) do
            local rng = new_rng(99991)
            local tris = {}
            local contours = {}

            rect(tris, -2, -2, 2, 2, 0)

            for _ = 1, 40 do
                local x, y = rng(-45, 45), rng(-45, 45)

                tris[#tris + 1] = { x, y, x + rng(-9, 9), y + rng(-9, 9), x + rng(-9, 9), y + rng(-9, 9),
                    math.floor(rng(-6, 6)) }
                contours[#contours + 1] = { x, y, x + rng(-30, 30), y + rng(-30, 30), math.floor(rng(-6, 6)) }
            end

            local harness = new_harness()

            harness.settings.strikemap_hatch_above = true
            harness.publish(make_context(tris, 1), make_vectors(1, { contours = contours }))

            local emitted = harness.draw(1, { x = 0, y = 0, z = 0.1 }, { style = style, rotation = forward or nil })

            harness.close()
            assert_true(#emitted > 0, "nothing drawn")

            for i = 1, #emitted do
                local entry = emitted[i]
                local slack = FILLS[entry.color] and 1e-6 or 1.0 + 1e-6

                for v = 0, 2 do
                    local ox = entry[v * 2 + 1] / UI_SCALE - CENTER_X
                    local oy = entry[v * 2 + 2] / UI_SCALE - CENTER_Y

                    if style == "circle" then
                        assert_true(math.sqrt(ox * ox + oy * oy) <= PROJECTION_RADIUS + slack,
                            "a vertex left the circle")
                    else
                        assert_true(math.abs(ox) <= PROJECTION_RADIUS + slack and math.abs(oy) <= PROJECTION_RADIUS + slack,
                            "a vertex left the square")
                    end
                end
            end
        end
    end)
end

test("walls reach half their width past their ends, so corners join, and other lines do not", function()
    local tris = {}

    rect(tris, -12, -12, 12, 12, 0)
    rect(tris, -12, -12, 12, 12, 4)

    local wall = { -4, -2, 4, -2, 0 }
    local outline = { -4, 6, 4, 6, 4 }
    local harness = new_harness()
    local player = { x = 0, y = 0, z = 0.1 }

    harness.publish(make_context(tris, 1), make_vectors(1, { contours = { wall, outline } }))

    local emitted = harness.draw(1, player)

    harness.close()

    local s = PROJECTION_RADIUS / RANGE
    local checked = 0

    for _, case in ipairs({ { wall, 1.0 }, { outline, 0 } }) do
        local segment, overhang = case[1], case[2]
        local quad = {}

        for i = 1, #emitted do
            local entry = emitted[i]

            if entry.layer == LAYER + 2 then
                local x, y = centroid_world(entry, player)

                if distance_to_segment(x, y, segment[1], segment[2], segment[3], segment[4]) < 0.5 then
                    quad[#quad + 1] = entry
                end
            end
        end

        assert_equal(2, #quad, "one quad per line")

        local first, second = quad[1], quad[2]
        local ax = (second[1] + second[5]) / 2 / UI_SCALE
        local bx = (first[3] + first[5]) / 2 / UI_SCALE
        local drawn_length = math.abs(bx - ax)
        local world_length = math.abs(segment[3] - segment[1]) * s

        assert_near(world_length + 2 * overhang, drawn_length, 1e-6, "line length on the radar")
        checked = checked + 1
    end

    assert_equal(2, checked, "lines checked")
end)

test("without a rotation the map stays north-up", function()
    local tris = rect({}, -2, 8, 2, 12, 0)
    local harness = new_harness()

    harness.publish(make_context(tris, 1), nil)

    local emitted = harness.draw(1, { x = 0, y = 0, z = 0.1 })

    harness.close()
    assert_true(#emitted > 0, "nothing drawn")

    for i = 1, #emitted do
        local _, oy = 0, (emitted[i][2] + emitted[i][4] + emitted[i][6]) / 3 / UI_SCALE - CENTER_Y

        assert_true(oy < 0, "a floor north of the player was drawn below the centre")
    end
end)

-- ----------------------------------------------------------------------------
-- Floor pieces
-- ----------------------------------------------------------------------------

--- Baked maps export stair transitions and no hatching; this far-away anchor makes a map one.
local BAKED_TRANSITIONS = { { 500, 500, 0, 1 } }

--- A walkway climbing 1 m per 2 m step from z 0 to 9 along x (triangles 1 to 20), a deck 4 m over
-- its start with corners of its own (21, 22) and a room at the walkway's start height, apart
-- from it (23, 24).
local function piece_scene()
    local tris = {}

    for step = 0, 9 do
        rect(tris, -2 + step * 2, 0, step * 2, 4, step)
    end

    rect(tris, -1.9, 0.1, -0.1, 3.9, 4)
    rect(tris, -2, 10, 2, 14, 0)

    return tris
end

local PIECE_WALLS = {
    top = { 14, 0, 16, 0, 8 },
    room = { -2, 10, 2, 10, 0 },
    deck = { -1.9, 0.1, -0.1, 0.1, 4 },
    loose = { 5, 20, 7, 20, 0 },
    span = { -2, 4, 2, 4, 0.5 },
    part = { -1.5, 0, -0.5, 0, 0 },
}
local PIECE_WALL_ORDER = { "top", "room", "deck", "loose", "span", "part" }

local function piece_walls()
    local list = {}

    for i = 1, #PIECE_WALL_ORDER do
        list[i] = PIECE_WALLS[PIECE_WALL_ORDER[i]]
    end

    return list
end

--- The sorted entries of a selection list, as a string.
local function listed(list, count)
    local items = {}

    for k = 1, count do
        items[k] = list[k]
    end

    table.sort(items)

    return table.concat(items, ",")
end

local function range_list(first, last, extra)
    local items = {}

    for i = first, last do
        items[#items + 1] = i
    end

    for i = 1, #(extra or {}) do
        items[#items + 1] = extra[i]
    end

    table.sort(items)

    return table.concat(items, ",")
end

test("on a baked map the connected floor under the player is the current floor, beyond the band and the floor range",
    function()
        local player = { x = -1, y = 1, z = 0.1 }
        local harness = new_harness()

        harness.settings.debug_mode = true
        harness.publish(make_context(piece_scene(), 1), make_vectors(1, { transitions = BAKED_TRANSITIONS }))
        harness.draw(1, player)

        local bins = harness.bins
        local pieces = harness.pieces

        assert_equal(2, pieces.status, "the pieces of a small baked map were not ready on the first frame")
        assert_equal(3, pieces.count, "piece count")
        assert_equal(range_list(1, 20), listed(bins.current, bins.current_n),
            "the whole walkway, 9 m up and past the 7 m floor range, is not the current floor")
        assert_equal(range_list(21, 24), listed(bins.above, bins.above_n),
            "the deck above and the room apart at the same height are not floors above")
        assert_equal(0, bins.below_n, "a floor below was listed")
        assert_true(pieces.vertex_ids == nil and pieces.edge_last == nil and pieces.slot_next == nil
            and pieces.corner == nil, "the build tables outlived the build")

        local logged = false

        for i = 1, #harness.infos do
            if harness.infos[i]:find("floor pieces ready", 1, true) and harness.infos[i]:find("pieces=3", 1, true) then
                logged = true
            end
        end

        assert_true(logged, "the finished build was not logged in debug mode")

        harness.draw(1.1, { x = -1, y = 7, z = 0.1 })
        assert_equal(range_list(1, 20), listed(bins.current, bins.current_n),
            "a step off the floor plan, with no triangle in reach, lost the floor shown")
        harness.close()

        -- Expedition layers hatch their triangles and Strikemap bands them by height, so Radar does too.
        harness = new_harness()
        harness.settings.debug_mode = true
        harness.publish(make_context(piece_scene(), 1), make_vectors(1, {
            transitions = BAKED_TRANSITIONS,
            hatches = { { 300, 300, 302, 300, 0 } },
        }))
        harness.draw(1, player)
        bins = harness.bins
        assert_equal(0, harness.pieces.status, "pieces were built for a hatched map")
        assert_equal(range_list(1, 6, { 23, 24 }), listed(bins.current, bins.current_n),
            "the hatched map's current floor is not the height band")
        assert_equal(range_list(7, 16, { 21, 22 }), listed(bins.above, bins.above_n),
            "the hatched map's floors above are not the height band")

        logged = false

        for i = 1, #harness.infos do
            if harness.infos[i]:find("floor pieces off", 1, true) then
                logged = true
            end
        end

        assert_true(logged, "the band fallback was not logged in debug mode")
        harness.close()

        for _, layers in ipairs({ {}, false }) do
            harness = new_harness()
            harness.publish(make_context(piece_scene(), 1), layers and make_vectors(1, layers) or nil)
            harness.draw(1, player)
            bins = harness.bins
            assert_equal(0, harness.pieces.status, "pieces were built without transitions or vectors")
            assert_equal(range_list(1, 6, { 23, 24 }), listed(bins.current, bins.current_n),
                "a map without transitions or vectors lost the height band")
            harness.close()
        end
    end)

test("steps over 3 m and decks stacked on the same corners stay apart, and the floor shown wins near a landing",
    function()
        local function pieces_of(tris, contours)
            local harness = new_harness()

            harness.publish(make_context(tris, 1),
                make_vectors(1, { transitions = BAKED_TRANSITIONS, contours = contours }))
            harness.draw(1, { x = tris[1][1] + 0.3, y = tris[1][2] + 0.2, z = tris[1][7] })

            local piece, wall_piece = harness.pieces.piece, harness.pieces.wall_piece

            harness.close()

            return piece, wall_piece
        end

        local piece = pieces_of(rect(rect({}, 0, 0, 2, 4, 0), 2, 0, 4, 4, 3))

        assert_true(piece[1] == piece[3], "a 3 m step split a floor")
        piece = pieces_of(rect(rect({}, 0, 0, 2, 4, 0), 2, 0, 4, 4, 3.5))
        assert_true(piece[1] ~= piece[3], "a 3.5 m step joined two floors")

        local stacked = rect(rect(rect({}, 0, 0, 4, 4, 0), 0, 0, 4, 4, 4), 4, 0, 8, 4, 0)
        local wall_piece

        piece, wall_piece = pieces_of(stacked, {
            { 0, 0, 4, 0, 4 },
            { 0, 0, 4, 0, 0 },
            { 0, 0, 8, 0, 0 },
            { 0, 4, 8, 4, 4 },
        })
        assert_true(piece[1] == piece[2] and piece[1] == piece[5] and piece[1] == piece[6],
            "the lower deck and its neighbour are not one floor")
        assert_true(piece[3] == piece[4], "the upper deck, on the same corners as the lower one, fell apart")
        assert_true(piece[3] ~= piece[1], "decks 4 m apart on the same corners were joined")
        assert_equal(piece[3], wall_piece[1], "an upper deck edge went to the deck below it")
        assert_equal(piece[1], wall_piece[2], "a lower deck edge went to the deck above it")
        assert_equal(piece[1], wall_piece[3], "a contour over two lower edges lost its deck")
        assert_equal(piece[3], wall_piece[4], "an upper contour took its end points' lower triangles")

        -- This contour crosses a triangle, so only its end points name its floor.
        piece, wall_piece = pieces_of({ { 0, 0, 8, 0, 0, 6, 0 }, { 8, 0, 4, 6, 0, 6, 0 } }, { { 0, 0, 4, 6, 0 } })
        assert_true(piece[1] == piece[2], "two triangles sharing an edge are not one floor")
        assert_equal(piece[1], wall_piece[1], "a contour between two corners of one floor lost its floor")

        -- A low landing at 0.8 m overlaps the floor's end without sharing an edge with it.
        local tris = rect(rect({}, 0, 0, 6, 4, 0), 4, 0.1, 10, 3.9, 0.8)
        local harness = new_harness()
        local t = 1

        harness.publish(make_context(tris, 1), make_vectors(1, { transitions = BAKED_TRANSITIONS }))

        local function stand(x, z)
            t = t + 0.1
            harness.draw(t, { x = x, y = 2, z = z })

            return harness.pieces.piece[harness.floor.triangle]
        end

        local floor_piece = stand(1, 0)
        local landing_piece = harness.pieces.piece[3]

        assert_true(floor_piece ~= landing_piece, "the landing joined the floor")
        assert_equal(floor_piece, stand(5, 0.5), "walking onto the overlap left the floor shown")
        assert_equal(landing_piece, stand(8, 0.8), "the landing past the overlap was not picked")
        assert_equal(landing_piece, stand(5, 0.5), "walking back onto the overlap left the landing")
        harness.close()

        harness = new_harness()
        harness.publish(make_context(tris, 1), make_vectors(1, { transitions = BAKED_TRANSITIONS }))
        harness.draw(1, { x = 5, y = 2, z = 0.5 })
        assert_equal(landing_piece, harness.pieces.piece[harness.floor.triangle],
            "without a floor shown so far the nearer landing did not win")
        harness.close()
    end)

test("walls follow the lit piece by edge, end points or midpoint, and other pieces' outlines go by height", function()
    local player = { x = -1, y = 1, z = 0.1 }

    for _, baked in ipairs({ true, false }) do
        local harness = new_harness()

        harness.publish(make_context(piece_scene(), 1), make_vectors(1, {
            contours = piece_walls(),
            transitions = baked and BAKED_TRANSITIONS or nil,
        }))

        local emitted = harness.draw(1, player)
        local classes = classify_lines(emitted, PIECE_WALLS, player)
        local bins = harness.bins

        if baked then
            local piece = harness.pieces.piece
            local wall_piece = harness.pieces.wall_piece
            local expected = { piece[1], piece[23], piece[21], 0, piece[1], piece[1] }

            for j = 1, #PIECE_WALL_ORDER do
                assert_equal(expected[j], wall_piece[j], PIECE_WALL_ORDER[j] .. " contour piece")
            end

            assert_equal("1,4,5,6", listed(bins.walls, bins.walls_n),
                "the lit piece's contours and the one without a piece are not the walls")
            assert_equal("2,3", listed(bins.above_contours, bins.above_contours_n),
                "the room's and the deck's outlines are not outlines of floors above")
            assert_true(count_class(emitted, classes, "top", LAYER + 2) > 0,
                "the walkway's top wall, 8 m up, was not drawn")
        else
            assert_equal("2,4,5,6", listed(bins.walls, bins.walls_n), "the band walls changed without pieces")
            assert_equal("3", listed(bins.above_contours, bins.above_contours_n),
                "the band outlines above changed without pieces")
            assert_equal(0, count_class(emitted, classes, "top"), "a wall past the floor range was drawn")
        end

        harness.close()
    end
end)

test("the pieces build a budget of triangles per frame, the band rules until they are ready, and a new map starts over",
    function()
        local harness = new_harness()
        local budget = harness.build_budget
        local tris = piece_scene()

        for k = 0, math.ceil(budget * 1.1) - 1 do
            rect(tris, 200 + k, 0, 201 + k, 1, 0)
        end

        local tri_count = #tris
        local player = { x = -1, y = 1, z = 0.1 }
        local vectors = make_vectors(1, { transitions = BAKED_TRANSITIONS })

        harness.publish(make_context(tris, 1), vectors)

        local frames = 0
        local done = 0

        repeat
            frames = frames + 1
            harness.draw(frames * 0.1, player)

            local pieces = harness.pieces
            local now_done = pieces.status == 2 and tri_count * 3
                or math.min(3, pieces.phase - 1) * tri_count + (pieces.phase <= 3 and pieces.cursor or 0)

            assert_true(now_done - done <= budget, "a frame handled more than the budget")
            done = now_done

            if harness.pieces.status ~= 2 then
                assert_equal(range_list(1, 6, { 23, 24 }), listed(harness.bins.current, harness.bins.current_n),
                    "the floor was not the height band while the pieces were building")
            end
        until harness.pieces.status ~= 1 or frames > 50

        assert_equal(2, harness.pieces.status, "the build did not finish")
        assert_equal(math.ceil(tri_count * 3 / budget), frames, "frames the build took")
        assert_equal(range_list(1, 20), listed(harness.bins.current, harness.bins.current_n),
            "the walkway was not lit once the pieces were ready")

        local first_piece = harness.pieces.piece
        local vectors_2 = make_vectors(2, { transitions = BAKED_TRANSITIONS })

        harness.publish(make_context(piece_scene(), 2), vectors_2)
        harness.draw(frames * 0.1 + 0.3, player)
        assert_equal(2, harness.pieces.status, "the new map's pieces were not built")
        assert_true(harness.pieces.piece ~= first_piece, "the old map's pieces were kept")
        assert_equal(24, harness.pieces.tri_count, "the pieces belong to the old map")

        local same_size = make_context(piece_scene(), 3)
        local vectors_3 = make_vectors(3, { transitions = BAKED_TRANSITIONS })

        vectors_3.contours = vectors_2.contours
        first_piece = harness.pieces.piece
        harness.publish(same_size, vectors_3)
        harness.draw(frames * 0.1 + 0.6, player)
        assert_true(harness.pieces.triangles == same_size.triangles and harness.pieces.piece ~= first_piece,
            "a new map of the same size kept the old map's pieces")

        harness.mod._strikemap_geometry_renderer_reset()
        assert_equal(0, harness.pieces.status, "the integration reset kept the pieces")
        assert_true(harness.pieces.piece == nil and harness.pieces.triangles == nil, "the reset kept piece data")
        assert_true(harness.floor.triangle == nil, "the reset kept the floor triangle")
        harness.close()
    end)

-- ----------------------------------------------------------------------------
-- Runner
-- ----------------------------------------------------------------------------

local failures = 0

for i = 1, #tests do
    local entry = tests[i]
    local ok, err = xpcall(entry.fn, debug.traceback)

    if ok then
        print("PASS " .. entry.name)
    else
        failures = failures + 1
        print("FAIL " .. entry.name .. "\n" .. tostring(err))
    end
end

print(string.format("%d of %d Strikemap geometry tests passed", #tests - failures, #tests))

if failures > 0 then
    os.exit(1)
end
