--- Marks the stairs and ramps of the live navmesh as lines, stripes or shading.
-- The marks are built once per navmesh revision, a budget of work per frame. Triangles that rise at
-- least `MIN_SLOPE` metres per metre are sloped. Sloped triangles that share an edge join one facet
-- while their uphill direction stays within `FACET_MAX_TURN_SINE` of the facet's mean and their
-- steepness within `FACET_MAX_STEEPNESS_RATIO` of it, so a facet is one surface climbing one way,
-- also where a flight's navmesh steepens and flattens a little, while uneven ground or rubble breaks
-- up into many small ones. A facet is
-- marked when it climbs at least `MIN_FACET_RISE` metres and leads somewhere, with floor of another
-- triangle just past its top edge and just below its bottom edge (`PROBE_REACH`), so a flight of
-- stairs or a ramp between two floors is marked while the curved side of a tunnel or a berm is not.
-- Each marked triangle gets a line at every multiple of `TREAD_RISE` metres of height, the pieces of
-- one height joining into one line, and is cut into the bands between those heights. Lines and bands
-- are filed in 16 m grids by their midpoints.
--
-- Each frame draws one style on the geometry layer after the fills, for the marks within
-- `MARK_FLOOR_RANGE` metres of the player's height. The lines style draws the lines thin, in a lighter
-- shade of the current floor colour; the stripes style fills every other band a little lighter; the
-- shading style tints every band from the current floor colour towards the floor-above or floor-below
-- colour by its height difference, alternating two opacities so the steps show. Lines and stripes fade
-- with the height difference. At long range only every second, fourth or eighth line is drawn, and the
-- stripes and shading steps widen alike, so they never crowd closer than `MIN_MARK_SPACING_PX`. The
-- marks near the player are listed again only when the navmesh layer selects its triangles again, the
-- marks change or the zoom changes the stride.
--
-- Explicit module loaded by `ui/Radar_navmesh_renderer.lua` through `mod:io_dofile`; the chunk returns
-- `RadarStairTreads`. It keeps one build, tied to the geometry table and its revision, reads the
-- navmesh buckets through `mod:get_navmesh_nearby_buckets` for the probes, draws filled marks through
-- `ui/Radar_triangle_clipper.lua`, and draws without allocating once the marks are built.
-- module: Radar_stair_treads
-- alias: RadarStairTreads
-- author: LucLeto
local mod = get_mod("Radar")
local _clip_and_emit = mod:io_dofile("Radar/scripts/mods/Radar/ui/Radar_triangle_clipper")

local Color = Color
local Vector3 = Vector3
local tostring = tostring
local tonumber = tonumber
local math_ceil = math.ceil
local math_floor = math.floor
local math_huge = math.huge
local math_sqrt = math.sqrt
local string_format = string.format
local Gui_triangle = Gui and Gui.triangle

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

--- Which surfaces are marked.
-- A triangle is sloped when its plane rises at least `MIN_SLOPE` metres per metre (about 8.5 degrees).
-- A sloped triangle joins a facet through a shared edge while its uphill gradient (rise per metre east
-- and north) turns from the facet's mean by at most 30 degrees (`FACET_MAX_TURN_SINE`, the sine) and
-- is at most `FACET_MAX_STEEPNESS_RATIO` times as steep or as flat, and a facet must climb
-- `MIN_FACET_RISE` metres. Corners are matched at 1 cm, packed as `(x + OFFSET) * STRIDE + y + OFFSET`
-- in centimetres; an edge key packs its two corner ids as `low * EDGE_KEY_STRIDE + high`.
local MIN_SLOPE = 0.15
local FACET_MAX_TURN_SINE = 0.5
local FACET_MAX_STEEPNESS_RATIO = 2.5
local MIN_FACET_RISE = 1.5
local CORNER_KEY_SCALE = 100
local CORNER_KEY_OFFSET = 1048576
local CORNER_KEY_STRIDE = 4194304
local EDGE_KEY_STRIDE = 16777216
--- How a facet's ends are probed.
-- The corners within `PROBE_EDGE_BAND` metres of a facet's top or bottom, along its climb, are probe
-- points, at most `PROBES_PER_EDGE` per end. Each looks `PROBE_REACH` metres further up or down the
-- climb for floor of a triangle outside the facet, from `PROBE_BELOW` metres below to `PROBE_ABOVE`
-- metres above the corner at the top, and the other way round at the bottom. A facet leads somewhere
-- when at least `PROBE_SHARE` of the points at each end find floor. The band stays narrower than the
-- reach, so a probe always looks past its own facet. A facet climbing at least `TALL_FACET_RISE` metres
-- needs only one point at each end to find floor, as a slope that tall and even is a flight whose
-- landing may lie past only part of its head.
local PROBE_EDGE_BAND = 0.5
local PROBES_PER_EDGE = 8
local PROBE_REACH = 0.6
local PROBE_BELOW = 0.4
local PROBE_ABOVE = 0.8
local PROBE_SHARE = 0.3
local TALL_FACET_RISE = 3
local POINT_IN_TRIANGLE_EPSILON = 1e-9
--- Where the marks go.
-- Lines and band edges run at every multiple of `TREAD_RISE` metres of height. Line pieces shorter
-- than 1 cm are dropped, and a piece that carries on a line of the same height from one of its end
-- points, turning by no more than `JOIN_MAX_SINE` (the sine of the angle), lengthens that line. End
-- points are matched at 1 mm, packed like corners. A band piece under `MIN_BAND_AREA` square metres
-- is dropped.
local TREAD_RISE = 0.5
local MIN_LINE_LENGTH_SQ = 0.01 * 0.01
local JOIN_MAX_SINE = 0.002
local END_KEY_SCALE = 1000
local END_KEY_OFFSET = 16777216
local END_KEY_STRIDE = 33554432
local MIN_BAND_AREA = 0.0001
--- How the marks are drawn.
-- `TYPICAL_TREAD_RUN` is the gap between the lines of a typical navmesh flight in metres. It picks the
-- stride, the smallest of 1, 2, 4 and 8 (`MAX_MARK_STRIDE`) that keeps marks `MIN_MARK_SPACING_PX`
-- unscaled pixels apart; beyond that nothing is drawn. Marks more than `MARK_FLOOR_RANGE` metres above
-- or below the player are hidden. Lines and stripes keep `MARK_FADE[n]` of their opacity in the nth
-- metre of height difference. Every colour starts from the current floor colour. Lines are
-- `LINE_ALPHA_MULT` times as opaque, `LINE_BRIGHTEN` of the way to white and `LINE_HALF_WIDTH`
-- unscaled pixels either side of their centre. Stripes are `STRIPE_ALPHA_MULT` times as opaque and
-- `STRIPE_BRIGHTEN` of the way to white. Shading moves towards the floor-above or floor-below colour
-- in `SHADE_STEPS` steps either way, all the way at `SHADE_FULL_DZ` metres of height difference, then
-- `SHADE_BRIGHTEN` of the way to white, at `SHADE_ALPHA_EVEN` or `SHADE_ALPHA_ODD` times the floor's
-- opacity by step.
local TYPICAL_TREAD_RUN = 1.1
local MIN_MARK_SPACING_PX = 3.5
local MAX_MARK_STRIDE = 8
local MARK_FLOOR_RANGE = 4
local MARK_FADE = { 1, 0.8, 0.6, 0.4 }
local MARK_FADE_STEPS = 4
local LINE_ALPHA_MULT = 1.6
local LINE_BRIGHTEN = 0.3
local LINE_HALF_WIDTH = 0.5
local STRIPE_ALPHA_MULT = 0.7
local STRIPE_BRIGHTEN = 0.5
local SHADE_STEPS = 3
local SHADE_FULL_DZ = 3
local SHADE_BRIGHTEN = 0.2
local SHADE_ALPHA_EVEN = 0.6
local SHADE_ALPHA_ODD = 1
local MIN_SCREEN_LENGTH_SQ = 1e-12
--- The styles `RadarStairTreads.draw` takes.
local STYLE_LINES = "lines"
local STYLE_STRIPES = "stripes"
local STYLE_SHADING = "shading"
--- Build budgets per frame, and the mark grids with their packed keys `(cx + OFFSET) * STRIDE + cy + OFFSET`.
-- Per frame the build tests `SCAN_BUDGET` navmesh triangles, grows facets by `FACET_BUDGET` sloped
-- triangles, measures `MEASURE_BUDGET` of them, runs `PROBE_BUDGET` probes, marks `OUTPUT_BUDGET`
-- sloped triangles (up to 16 lines and bands each on a tall flight) and files `INDEX_BUDGET` marks.
local SCAN_BUDGET = 2048
local FACET_BUDGET = 1024
local MEASURE_BUDGET = 1024
local PROBE_BUDGET = 32
local OUTPUT_BUDGET = 256
local INDEX_BUDGET = 2048
local INVERSE_CELL_SIZE = 1 / 16
local CELL_HASH_OFFSET = 4096
local CELL_HASH_STRIDE = 8192
--- How far the listed marks reach past the radar.
-- The list covers the radar's range (its diagonal for square radars) plus `SELECTION_SLACK` metres,
-- and `SELECTION_HEIGHT_SLACK` metres above and below the drawn height range, so the player can move
-- between two listings.
local SQUARE_REACH_MULT = 1.4143
local SELECTION_SLACK = 4
local SELECTION_HEIGHT_SLACK = 2
--- Build states, phases and facet states.
local STATUS_IDLE = 0
local STATUS_BUILDING = 1
local STATUS_READY = 2
local STATUS_FAILED = 3
local PHASE_SCAN = 1
local PHASE_FACETS = 2
local PHASE_MEASURE = 3
local PHASE_PROBE = 4
local PHASE_OUTPUT = 5
local PHASE_INDEX = 6
local FACET_DROPPED = 0
local FACET_CANDIDATE = 1
local FACET_KEPT = 2

-- ----------------------------------------------------------------------------
-- Mutable state
-- ----------------------------------------------------------------------------

--- The build of one geometry table and revision.
-- `status` is `STATUS_IDLE` without a build, `STATUS_BUILDING` while `_build_step` works through
-- `phase` from `cursor`, `STATUS_READY` once the marks are built, and `STATUS_FAILED` after an error,
-- until the geometry changes. The scan lists the sloped triangles in `sloped` with their gradients
-- `grad_x` and `grad_y`, their corner ids in `corners` (three per sloped triangle) and their edges
-- chained through `edge_last` and `slot_next` by slot `(position - 1) * 3 + edge`. Facet growing
-- fills `facet_of`, lists the sloped triangles facet by facet in `order` (facet f spans
-- `facet_first[f]` to `facet_last[f]`), keeps the open facet's queue and gradient sums, and records
-- each facet's mean gradient. Measuring sets `facet_state`, the uphill direction `facet_ux` and
-- `facet_uy` and the probe points; probing counts their hits. While the marks are made, `ends` maps
-- each height step's line end points to their lines and `steps` keeps each line's height step. The
-- counts are logged in debug mode.
local _build = {
    geometry = nil,
    revision = nil,
    status = STATUS_IDLE,
    phase = 0,
    cursor = 0,
    frames = 0,
    sloped = nil,
    sloped_n = 0,
    grad_x = nil,
    grad_y = nil,
    corner_ids = nil,
    corner_count = 0,
    corners = nil,
    edge_last = nil,
    slot_next = nil,
    facet_of = nil,
    order = nil,
    order_n = 0,
    facet_first = nil,
    facet_last = nil,
    facet_count = 0,
    facet_gx = nil,
    facet_gy = nil,
    queue = nil,
    queue_head = 1,
    queue_tail = 0,
    sum_gx = 0,
    sum_gy = 0,
    sum_n = 0,
    facet_state = nil,
    facet_ux = nil,
    facet_uy = nil,
    corner_stamp = nil,
    probe_x = nil,
    probe_y = nil,
    probe_z = nil,
    probe_side = nil,
    probe_facet = nil,
    probe_n = 0,
    top_n = nil,
    top_hits = nil,
    bottom_n = nil,
    bottom_hits = nil,
    ends = nil,
    steps = nil,
    joined = 0,
    candidates = 0,
    kept = 0,
    marked = 0,
}
--- The built lines; line `i` runs from `x1[i], y1[i]` to `x2[i], y2[i]` at height `z[i]`.
-- `rank[i]` is the largest stride up to `MAX_MARK_STRIDE` that the line's height step is a multiple
-- of, so a frame drawing every second line keeps those of rank 2 or more. `cells` lists line indices
-- by the packed grid cell of their midpoints and `cell_n` their counts; the cell bounds and
-- `max_half_length` let a query find a long line centred outside the radar. `revision` changes
-- whenever the marks do.
local _lines = {
    x1 = {},
    y1 = {},
    x2 = {},
    y2 = {},
    z = {},
    rank = {},
    count = 0,
    cells = {},
    cell_n = {},
    max_half_length = 0,
    min_cx = 0,
    max_cx = -1,
    min_cy = 0,
    max_cy = -1,
    revision = 0,
}
--- The built band pieces; piece `i` is the triangle `x1[i], y1[i]`, `x2[i], y2[i]`, `x3[i], y3[i]`.
-- It lies in the band of height step `step[i]`, between `step[i] * TREAD_RISE` and the next step, whose
-- middle height is `z[i]`. The grid and bounds work as for the lines, with `max_radius` the farthest
-- corner from a piece's centre.
local _bands = {
    x1 = {},
    y1 = {},
    x2 = {},
    y2 = {},
    x3 = {},
    y3 = {},
    z = {},
    step = {},
    count = 0,
    cells = {},
    cell_n = {},
    max_radius = 0,
    min_cx = 0,
    max_cx = -1,
    min_cy = 0,
    max_cy = -1,
}
--- The marks listed around the player, and what they were listed for.
-- Entries of `lines` and `bands` past their counts are stale. `refreshes` counts the listings.
local _selection = {
    lines = {},
    line_count = 0,
    bands = {},
    band_count = 0,
    revision = -1,
    stride = 0,
    refreshes = 0,
}
--- The mark colours derived from the floor colours last seen.
-- The channels are kept as numbers; `line_a` and `stripe_a` hold one opacity per fade step, `shade_r`,
-- `shade_g` and `shade_b` one channel per shading step, from the floor-below end (1) through the
-- current floor (`SHADE_STEPS + 1`) to the floor-above end. `Color` returns a temporary engine value
-- that only lives for the frame it was made in, so `line`, `stripe`, `shade_even` and `shade_odd` are
-- filled again every frame from those numbers and never read in a later frame.
local _colors = {
    a = -1,
    r = -1,
    g = -1,
    b = -1,
    above_r = -1,
    above_g = -1,
    above_b = -1,
    below_r = -1,
    below_g = -1,
    below_b = -1,
    visible = false,
    line_a = { 0, 0, 0, 0 },
    line_r = 0,
    line_g = 0,
    line_b = 0,
    stripe_a = { 0, 0, 0, 0 },
    stripe_r = 0,
    stripe_g = 0,
    stripe_b = 0,
    shade_r = { 0, 0, 0, 0, 0, 0, 0 },
    shade_g = { 0, 0, 0, 0, 0, 0, 0 },
    shade_b = { 0, 0, 0, 0, 0, 0, 0 },
    shade_even_a = 0,
    shade_odd_a = 0,
    line = { false, false, false, false },
    stripe = { false, false, false, false },
    shade_even = { false, false, false, false, false, false, false },
    shade_odd = { false, false, false, false, false, false, false },
}
--- Scratch lists reused by the build; polygon buffers for band clipping and buckets for the probes.
local _poly_ax, _poly_ay, _poly_az = {}, {}, {}
local _poly_bx, _poly_by, _poly_bz = {}, {}, {}
local _probe_buckets = {}

-- ----------------------------------------------------------------------------
-- Build
-- ----------------------------------------------------------------------------

--- Empties the lines, the bands and the listing, so nothing is drawn until a build finishes.
local function _clear_marks()
    local lines = _lines
    local bands = _bands

    lines.x1 = {}
    lines.y1 = {}
    lines.x2 = {}
    lines.y2 = {}
    lines.z = {}
    lines.rank = {}
    lines.count = 0
    lines.cells = {}
    lines.cell_n = {}
    lines.max_half_length = 0
    lines.min_cx = 0
    lines.max_cx = -1
    lines.min_cy = 0
    lines.max_cy = -1
    lines.revision = lines.revision + 1
    bands.x1 = {}
    bands.y1 = {}
    bands.x2 = {}
    bands.y2 = {}
    bands.x3 = {}
    bands.y3 = {}
    bands.z = {}
    bands.step = {}
    bands.count = 0
    bands.cells = {}
    bands.cell_n = {}
    bands.max_radius = 0
    bands.min_cx = 0
    bands.max_cx = -1
    bands.min_cy = 0
    bands.max_cy = -1
    _selection.line_count = 0
    _selection.band_count = 0
end

--- Drops the tables the scan and facet growing need, once every facet is grown.
local function _release_edge_tables(build)
    build.corner_ids = nil
    build.edge_last = nil
    build.slot_next = nil
    build.queue = nil
end

--- Drops the build's working tables.
local function _release_build_tables(build)
    _release_edge_tables(build)
    build.sloped = nil
    build.grad_x = nil
    build.grad_y = nil
    build.corners = nil
    build.facet_of = nil
    build.order = nil
    build.facet_first = nil
    build.facet_last = nil
    build.facet_gx = nil
    build.facet_gy = nil
    build.facet_state = nil
    build.facet_ux = nil
    build.facet_uy = nil
    build.facet_rise = nil
    build.corner_stamp = nil
    build.probe_x = nil
    build.probe_y = nil
    build.probe_z = nil
    build.probe_side = nil
    build.probe_facet = nil
    build.top_n = nil
    build.top_hits = nil
    build.bottom_n = nil
    build.bottom_hits = nil
    build.ends = nil
    build.steps = nil
end

--- Starts a new build for a geometry table at its current revision.
-- tab: build `_build`
-- tab: geometry navmesh geometry
local function _start_build(build, geometry)
    _clear_marks()

    build.geometry = geometry
    build.revision = geometry.revision
    build.status = STATUS_BUILDING
    build.phase = PHASE_SCAN
    build.cursor = 0
    build.frames = 0
    build.sloped = {}
    build.sloped_n = 0
    build.grad_x = {}
    build.grad_y = {}
    build.corner_ids = {}
    build.corner_count = 0
    build.corners = {}
    build.edge_last = {}
    build.slot_next = {}
    build.facet_of = {}
    build.order = {}
    build.order_n = 0
    build.facet_first = {}
    build.facet_last = {}
    build.facet_count = 0
    build.facet_gx = {}
    build.facet_gy = {}
    build.queue = {}
    build.queue_head = 1
    build.queue_tail = 0
    build.sum_gx = 0
    build.sum_gy = 0
    build.sum_n = 0
    build.facet_state = {}
    build.facet_ux = {}
    build.facet_uy = {}
    build.facet_rise = {}
    build.corner_stamp = {}
    build.probe_x = {}
    build.probe_y = {}
    build.probe_z = {}
    build.probe_side = {}
    build.probe_facet = {}
    build.probe_n = 0
    build.top_n = {}
    build.top_hits = {}
    build.bottom_n = {}
    build.bottom_hits = {}
    build.ends = {}
    build.steps = {}
    build.joined = 0
    build.candidates = 0
    build.kept = 0
    build.marked = 0
end

--- Returns the id of a corner position, giving it the next free id when it is new.
-- tab: build `_build`
-- number: x corner x in world space
-- number: y corner y in world space
-- treturn: int corner id
local function _corner_id(build, x, y)
    local key = (math_floor(x * CORNER_KEY_SCALE + 0.5) + CORNER_KEY_OFFSET) * CORNER_KEY_STRIDE
        + math_floor(y * CORNER_KEY_SCALE + 0.5) + CORNER_KEY_OFFSET
    local corner_ids = build.corner_ids
    local id = corner_ids[key]

    if id == nil then
        id = build.corner_count + 1
        build.corner_count = id
        corner_ids[key] = id
    end

    return id
end

--- Chains an edge slot of a sloped triangle onto the other slots with the same two corners.
-- tab: build `_build`
-- int: a first corner id
-- int: b second corner id
-- int: slot `(position - 1) * 3 + edge`
local function _link_edge(build, a, b, slot)
    if a > b then
        a, b = b, a
    end

    local key = a * EDGE_KEY_STRIDE + b

    build.slot_next[slot] = build.edge_last[key] or 0
    build.edge_last[key] = slot
end

--- Returns one corner of a navmesh triangle.
-- tab: geometry navmesh geometry
-- int: i triangle index
-- int: c corner, 1 to 3
-- treturn: number x
-- treturn: number y
-- treturn: number z
local function _corner_of(geometry, i, c)
    if c == 1 then
        return geometry.ax[i], geometry.ay[i], geometry.az[i]
    elseif c == 2 then
        return geometry.bx[i], geometry.by[i], geometry.bz[i]
    end

    return geometry.cx[i], geometry.cy[i], geometry.cz[i]
end

--- Tests the next `SCAN_BUDGET` triangles for their slope and records the sloped ones with their edges.
-- tab: build `_build`
-- tab: geometry navmesh geometry
local function _scan_step(build, geometry)
    local count = geometry.count
    local first = build.cursor + 1
    local last = build.cursor + SCAN_BUDGET

    if last > count then
        last = count
    end

    local ax, ay, az = geometry.ax, geometry.ay, geometry.az
    local bx, by, bz = geometry.bx, geometry.by, geometry.bz
    local cx, cy, cz = geometry.cx, geometry.cy, geometry.cz
    local sloped = build.sloped
    local grad_x = build.grad_x
    local grad_y = build.grad_y
    local corners = build.corners
    local n = build.sloped_n
    local min_slope_sq = MIN_SLOPE * MIN_SLOPE

    for i = first, last do
        local x1, y1, z1 = ax[i], ay[i], az[i]
        local x2, y2 = bx[i], by[i]
        local x3, y3 = cx[i], cy[i]
        local e1x, e1y, e1z = x2 - x1, y2 - y1, bz[i] - z1
        local e2x, e2y, e2z = x3 - x1, y3 - y1, cz[i] - z1
        local nz = e1x * e2y - e1y * e2x
        local nx = e1y * e2z - e1z * e2y
        local ny = e1z * e2x - e1x * e2z

        if nz ~= 0 and nx * nx + ny * ny >= min_slope_sq * nz * nz then
            n = n + 1
            sloped[n] = i
            grad_x[n] = -nx / nz
            grad_y[n] = -ny / nz

            local base = (n - 1) * 3
            local id1 = _corner_id(build, x1, y1)
            local id2 = _corner_id(build, x2, y2)
            local id3 = _corner_id(build, x3, y3)

            corners[base + 1] = id1
            corners[base + 2] = id2
            corners[base + 3] = id3
            _link_edge(build, id1, id2, base + 1)
            _link_edge(build, id2, id3, base + 2)
            _link_edge(build, id3, id1, base + 3)
        end
    end

    build.sloped_n = n
    build.cursor = last

    if last >= count then
        build.phase = PHASE_FACETS
        build.cursor = 0
    end
end

--- Grows facets by the next `FACET_BUDGET` sloped triangles taken from the open facet's queue.
-- A sloped triangle on an edge of a queued one joins the open facet while its gradient turns from
-- the facet's mean by at most the angle whose sine is `FACET_MAX_TURN_SINE` and its steepness stays
-- within `FACET_MAX_STEEPNESS_RATIO` of the mean's, compared as squares without a square root. When
-- the queue runs dry the facet is closed and the next sloped triangle without a facet starts one.
-- tab: build `_build`
local function _facets_step(build)
    local n = build.sloped_n
    local facet_of = build.facet_of
    local order = build.order
    local queue = build.queue
    local grad_x = build.grad_x
    local grad_y = build.grad_y
    local corners = build.corners
    local edge_last = build.edge_last
    local slot_next = build.slot_next
    local turn_sine_sq = FACET_MAX_TURN_SINE * FACET_MAX_TURN_SINE
    local ratio_sq = FACET_MAX_STEEPNESS_RATIO * FACET_MAX_STEEPNESS_RATIO
    local head = build.queue_head
    local tail = build.queue_tail
    local facet = build.facet_count
    local order_n = build.order_n
    local sum_x = build.sum_gx
    local sum_y = build.sum_gy
    local sum_n = build.sum_n
    local budget = FACET_BUDGET
    local done = false

    while budget > 0 do
        if head > tail then
            if sum_n > 0 then
                build.facet_gx[facet] = sum_x / sum_n
                build.facet_gy[facet] = sum_y / sum_n
                build.facet_last[facet] = order_n
                sum_n = 0
            end

            local k = build.cursor + 1

            while k <= n and facet_of[k] do
                k = k + 1
            end

            build.cursor = k

            if k > n then
                done = true

                break
            end

            facet = facet + 1
            facet_of[k] = facet
            build.facet_first[facet] = order_n + 1
            order_n = order_n + 1
            order[order_n] = k
            head = 1
            tail = 1
            queue[1] = k
            sum_x = grad_x[k]
            sum_y = grad_y[k]
            sum_n = 1
        else
            local k = queue[head]
            local base = (k - 1) * 3

            head = head + 1
            budget = budget - 1

            for e = 1, 3 do
                local a = corners[base + e]
                local b = corners[base + (e == 3 and 1 or e + 1)]

                if a > b then
                    a, b = b, a
                end

                local slot = edge_last[a * EDGE_KEY_STRIDE + b] or 0

                while slot ~= 0 do
                    local other = math_floor((slot - 1) / 3) + 1

                    if not facet_of[other] then
                        local mean_x = sum_x / sum_n
                        local mean_y = sum_y / sum_n
                        local gx = grad_x[other]
                        local gy = grad_y[other]
                        local dot = gx * mean_x + gy * mean_y
                        local cross = gx * mean_y - gy * mean_x
                        local mean_sq = mean_x * mean_x + mean_y * mean_y
                        local steepness_sq = gx * gx + gy * gy

                        if dot > 0 and cross * cross <= turn_sine_sq * steepness_sq * mean_sq
                            and steepness_sq <= ratio_sq * mean_sq and mean_sq <= ratio_sq * steepness_sq then
                            facet_of[other] = facet
                            tail = tail + 1
                            queue[tail] = other
                            order_n = order_n + 1
                            order[order_n] = other
                            sum_x = sum_x + grad_x[other]
                            sum_y = sum_y + grad_y[other]
                            sum_n = sum_n + 1
                        end
                    end

                    slot = slot_next[slot]
                end
            end
        end
    end

    build.queue_head = head
    build.queue_tail = tail
    build.facet_count = facet
    build.order_n = order_n
    build.sum_gx = sum_x
    build.sum_gy = sum_y
    build.sum_n = sum_n

    if done then
        build.phase = PHASE_MEASURE
        build.cursor = 0
        _release_edge_tables(build)
    end
end

--- Adds one probe point of a facet end.
-- tab: build `_build`
-- int: facet facet
-- number: x corner x
-- number: y corner y
-- number: z corner height
-- int: side 1 at the top, -1 at the bottom
local function _add_probe(build, facet, x, y, z, side)
    local n = build.probe_n + 1

    build.probe_n = n
    build.probe_x[n] = x
    build.probe_y[n] = y
    build.probe_z[n] = z
    build.probe_side[n] = side
    build.probe_facet[n] = facet
end

--- Measures the next facets, about `MEASURE_BUDGET` sloped triangles, and lists the probe points of those that climb enough.
-- tab: build `_build`
-- tab: geometry navmesh geometry
local function _measure_step(build, geometry)
    local sloped = build.sloped
    local order = build.order
    local corners = build.corners
    local corner_stamp = build.corner_stamp
    local facet_count = build.facet_count
    local facet = build.cursor
    local budget = MEASURE_BUDGET

    while budget > 0 and facet < facet_count do
        facet = facet + 1

        local first = build.facet_first[facet]
        local last = build.facet_last[facet]
        local low, high = math_huge, -math_huge
        local sum_x, sum_y = 0, 0

        budget = budget - (last - first + 1)

        for p = first, last do
            local i = sloped[order[p]]

            for c = 1, 3 do
                local x, y, z = _corner_of(geometry, i, c)

                sum_x = sum_x + x
                sum_y = sum_y + y

                if z < low then
                    low = z
                end

                if z > high then
                    high = z
                end
            end
        end

        build.top_n[facet] = 0
        build.bottom_n[facet] = 0
        build.top_hits[facet] = 0
        build.bottom_hits[facet] = 0

        if high - low < MIN_FACET_RISE then
            build.facet_state[facet] = FACET_DROPPED
        else
            local gx = build.facet_gx[facet]
            local gy = build.facet_gy[facet]
            local slope = math_sqrt(gx * gx + gy * gy)
            local ux = gx / slope
            local uy = gy / slope
            local count = (last - first + 1) * 3
            local mean_x = sum_x / count
            local mean_y = sum_y / count
            local run_low, run_high = math_huge, -math_huge

            for p = first, last do
                local i = sloped[order[p]]

                for c = 1, 3 do
                    local x, y = _corner_of(geometry, i, c)
                    local along = (x - mean_x) * ux + (y - mean_y) * uy

                    if along < run_low then
                        run_low = along
                    end

                    if along > run_high then
                        run_high = along
                    end
                end
            end

            local top, bottom = 0, 0

            for p = first, last do
                local k = order[p]
                local i = sloped[k]
                local base = (k - 1) * 3

                for c = 1, 3 do
                    local id = corners[base + c]

                    if corner_stamp[id] ~= facet then
                        corner_stamp[id] = facet

                        local x, y, z = _corner_of(geometry, i, c)
                        local along = (x - mean_x) * ux + (y - mean_y) * uy

                        if along >= run_high - PROBE_EDGE_BAND then
                            if top < PROBES_PER_EDGE then
                                top = top + 1
                                _add_probe(build, facet, x, y, z, 1)
                            end
                        elseif along <= run_low + PROBE_EDGE_BAND then
                            if bottom < PROBES_PER_EDGE then
                                bottom = bottom + 1
                                _add_probe(build, facet, x, y, z, -1)
                            end
                        end
                    end
                end
            end

            build.facet_state[facet] = FACET_CANDIDATE
            build.facet_ux[facet] = ux
            build.facet_uy[facet] = uy
            build.facet_rise[facet] = high - low
            build.top_n[facet] = top
            build.bottom_n[facet] = bottom
            build.candidates = build.candidates + 1
        end
    end

    build.cursor = facet

    if facet >= facet_count then
        build.phase = PHASE_PROBE
        build.cursor = 0
        build.corner_stamp = nil
    end
end

--- Returns whether the navmesh has floor at a point, between two heights.
-- A probe point lies past its facet's own triangles, so any floor found belongs to another
-- surface. A triangle holding the point has its centre within `geometry.max_radius` of it, so the
-- buckets are queried that far and a bucket whose cell lies farther away is skipped.
-- tab: geometry navmesh geometry
-- number: x point x
-- number: y point y
-- number: low lowest floor height that counts
-- number: high highest floor height that counts
-- treturn: bool
local function _floor_at(geometry, x, y, low, high)
    local buckets = _probe_buckets
    local reach = geometry.max_radius
    local bucket_count = mod:get_navmesh_nearby_buckets(x, y, reach, buckets)
    local ax, ay, az = geometry.ax, geometry.ay, geometry.az
    local bx, by, bz = geometry.bx, geometry.by, geometry.bz
    local cx, cy, cz = geometry.cx, geometry.cy, geometry.cz
    local mid_x, mid_y, radius = geometry.mid_x, geometry.mid_y, geometry.radius
    local cell_size = geometry.cell_size
    local reach_sq = reach * reach
    local epsilon = -POINT_IN_TRIANGLE_EPSILON

    for b = 1, bucket_count do
        local bucket = buckets[b]
        local cell_x = bucket.cell_x
        local near = true

        if cell_x and cell_size then
            local left = cell_x * cell_size
            local bottom = bucket.cell_y * cell_size
            local gap_x = left - x
            local gap_y = bottom - y

            if gap_x < 0 then
                gap_x = x - left - cell_size

                if gap_x < 0 then
                    gap_x = 0
                end
            end

            if gap_y < 0 then
                gap_y = y - bottom - cell_size

                if gap_y < 0 then
                    gap_y = 0
                end
            end

            near = gap_x * gap_x + gap_y * gap_y <= reach_sq
        end

        if near then
            for j = 1, #bucket do
                local i = bucket[j]
                local dx = x - mid_x[i]
                local dy = y - mid_y[i]
                local r = radius[i]

                if dx * dx + dy * dy <= r * r then
                    local x1, y1 = ax[i], ay[i]
                    local x2, y2 = bx[i], by[i]
                    local x3, y3 = cx[i], cy[i]
                    local d = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)

                    if d ~= 0 then
                        local w1 = ((y2 - y3) * (x - x3) + (x3 - x2) * (y - y3)) / d
                        local w2 = ((y3 - y1) * (x - x3) + (x1 - x3) * (y - y3)) / d
                        local w3 = 1 - w1 - w2

                        if w1 >= epsilon and w2 >= epsilon and w3 >= epsilon then
                            local z = w1 * az[i] + w2 * bz[i] + w3 * cz[i]

                            if z >= low and z <= high then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    return false
end

--- Runs the next `PROBE_BUDGET` probes, then keeps the candidate facets that lead somewhere.
-- tab: build `_build`
-- tab: geometry navmesh geometry
local function _probe_step(build, geometry)
    local probe_n = build.probe_n
    local first = build.cursor + 1
    local last = build.cursor + PROBE_BUDGET

    if last > probe_n then
        last = probe_n
    end

    for p = first, last do
        local facet = build.probe_facet[p]
        local side = build.probe_side[p]
        local reach = PROBE_REACH * side
        local x = build.probe_x[p] + build.facet_ux[facet] * reach
        local y = build.probe_y[p] + build.facet_uy[facet] * reach
        local z = build.probe_z[p]

        if side > 0 then
            if _floor_at(geometry, x, y, z - PROBE_BELOW, z + PROBE_ABOVE) then
                build.top_hits[facet] = build.top_hits[facet] + 1
            end
        elseif _floor_at(geometry, x, y, z - PROBE_ABOVE, z + PROBE_BELOW) then
            build.bottom_hits[facet] = build.bottom_hits[facet] + 1
        end
    end

    build.cursor = last

    if last < probe_n then
        return
    end

    local facet_state = build.facet_state
    local kept = 0

    for facet = 1, build.facet_count do
        if facet_state[facet] == FACET_CANDIDATE then
            local top_hits = build.top_hits[facet]
            local bottom_hits = build.bottom_hits[facet]
            local share = build.facet_rise[facet] >= TALL_FACET_RISE and 0 or PROBE_SHARE

            if top_hits > 0 and bottom_hits > 0 and top_hits >= share * build.top_n[facet]
                and bottom_hits >= share * build.bottom_n[facet] then
                facet_state[facet] = FACET_KEPT
                kept = kept + 1
            else
                facet_state[facet] = FACET_DROPPED
            end
        end
    end

    build.kept = kept
    build.phase = PHASE_OUTPUT
    build.cursor = 0
end

--- Returns the packed key of a line end point.
-- number: x end x in world space
-- number: y end y in world space
-- treturn: number end point key
local function _end_key(x, y)
    return (math_floor(x * END_KEY_SCALE + 0.5) + END_KEY_OFFSET) * END_KEY_STRIDE
        + math_floor(y * END_KEY_SCALE + 0.5) + END_KEY_OFFSET
end

--- Lengthens the line that ends at a piece's start point when the piece carries it on straight ahead.
-- The piece runs from `px, py`, the point `key` stands for, to `qx, qy`; the line's end there moves
-- to `qx, qy` and `ends` follows it.
-- tab: ends end point keys of one height step, mapped to their lines
-- number: key end point key of the piece's start
-- number: px piece start x
-- number: py piece start y
-- number: qx piece end x
-- number: qy piece end y
-- treturn: bool true when the piece lengthened a line
local function _extend_line(ends, key, px, py, qx, qy)
    local line = ends[key]

    if line == nil then
        return false
    end

    local lines = _lines
    local at_start = _end_key(lines.x1[line], lines.y1[line]) == key
    local far_x = at_start and lines.x2[line] or lines.x1[line]
    local far_y = at_start and lines.y2[line] or lines.y1[line]
    local dx = px - far_x
    local dy = py - far_y
    local ex = qx - px
    local ey = qy - py

    if dx * ex + dy * ey <= 0 then
        return false
    end

    local cross = dx * ey - dy * ex

    if cross * cross > JOIN_MAX_SINE * JOIN_MAX_SINE * (dx * dx + dy * dy) * (ex * ex + ey * ey) then
        return false
    end

    if at_start then
        lines.x1[line] = qx
        lines.y1[line] = qy
    else
        lines.x2[line] = qx
        lines.y2[line] = qy
    end

    ends[key] = nil
    ends[_end_key(qx, qy)] = line

    return true
end

--- Adds one piece of a line, lengthening a line of the same height it carries on, or storing a new one.
-- tab: build `_build`
-- number: x1 start x in world space
-- number: y1 start y in world space
-- number: x2 end x in world space
-- number: y2 end y in world space
-- int: step height step of the piece, its height divided by `TREAD_RISE`
local function _add_piece(build, x1, y1, x2, y2, step)
    local ends = build.ends[step]

    if ends == nil then
        ends = {}
        build.ends[step] = ends
    end

    local key_a = _end_key(x1, y1)
    local key_b = _end_key(x2, y2)

    if _extend_line(ends, key_a, x1, y1, x2, y2) or _extend_line(ends, key_b, x2, y2, x1, y1) then
        build.joined = build.joined + 1

        return
    end

    local lines = _lines
    local n = lines.count + 1

    lines.count = n
    lines.x1[n] = x1
    lines.y1[n] = y1
    lines.x2[n] = x2
    lines.y2[n] = y2
    lines.z[n] = step * TREAD_RISE
    build.steps[n] = step
    ends[key_a] = n
    ends[key_b] = n
end

--- Adds the lines of one marked triangle, one at each multiple of `TREAD_RISE` its corners span.
-- A corner at or above a height counts as above it, so a line along an edge at exactly that height
-- belongs to the triangle below the edge and is stored once.
-- tab: build `_build`
-- tab: geometry navmesh geometry
-- int: i triangle index
local function _add_triangle_lines(build, geometry, i)
    local x1, y1, h1 = geometry.ax[i], geometry.ay[i], geometry.az[i]
    local x2, y2, h2 = geometry.bx[i], geometry.by[i], geometry.bz[i]
    local x3, y3, h3 = geometry.cx[i], geometry.cy[i], geometry.cz[i]
    local low, high = h1, h1

    if h2 < low then
        low = h2
    elseif h2 > high then
        high = h2
    end

    if h3 < low then
        low = h3
    elseif h3 > high then
        high = h3
    end

    for step = math_ceil(low / TREAD_RISE), math_floor(high / TREAD_RISE) do
        local level = step * TREAD_RISE
        local above1 = h1 >= level
        local above2 = h2 >= level
        local above3 = h3 >= level
        local found = 0
        local px1, py1, px2, py2

        if above1 ~= above2 then
            local u = (level - h1) / (h2 - h1)

            px1 = x1 + (x2 - x1) * u
            py1 = y1 + (y2 - y1) * u
            found = 1
        end

        if above2 ~= above3 then
            local u = (level - h2) / (h3 - h2)

            if found == 0 then
                px1 = x2 + (x3 - x2) * u
                py1 = y2 + (y3 - y2) * u
                found = 1
            else
                px2 = x2 + (x3 - x2) * u
                py2 = y2 + (y3 - y2) * u
                found = 2
            end
        end

        if found == 1 and above3 ~= above1 then
            local u = (level - h3) / (h1 - h3)

            px2 = x3 + (x1 - x3) * u
            py2 = y3 + (y1 - y3) * u
            found = 2
        end

        if found == 2 then
            local dx = px2 - px1
            local dy = py2 - py1

            if dx * dx + dy * dy > MIN_LINE_LENGTH_SQ then
                _add_piece(build, px1, py1, px2, py2, step)
            end
        end
    end
end

--- Clips a polygon to the heights at or above (or at or below) a level, Sutherland-Hodgman style.
-- tab: in_x input x coordinates
-- tab: in_y input y coordinates
-- tab: in_z input heights
-- int: count number of input corners
-- number: level clipping height
-- bool: keep_above true to keep the part at or above the level, false for the part at or below it
-- tab: out_x receives the clipped x coordinates
-- tab: out_y receives the clipped y coordinates
-- tab: out_z receives the clipped heights
-- treturn: int number of corners written
local function _clip_height(in_x, in_y, in_z, count, level, keep_above, out_x, out_y, out_z)
    local out_count = 0
    local prev_x = in_x[count]
    local prev_y = in_y[count]
    local prev_z = in_z[count]
    local prev_in = (keep_above and prev_z >= level) or (not keep_above and prev_z <= level)

    for v = 1, count do
        local cur_x = in_x[v]
        local cur_y = in_y[v]
        local cur_z = in_z[v]
        local cur_in = (keep_above and cur_z >= level) or (not keep_above and cur_z <= level)

        if cur_in ~= prev_in then
            local u = (level - prev_z) / (cur_z - prev_z)

            out_count = out_count + 1
            out_x[out_count] = prev_x + (cur_x - prev_x) * u
            out_y[out_count] = prev_y + (cur_y - prev_y) * u
            out_z[out_count] = level
        end

        if cur_in then
            out_count = out_count + 1
            out_x[out_count] = cur_x
            out_y[out_count] = cur_y
            out_z[out_count] = cur_z
        end

        prev_x, prev_y, prev_z, prev_in = cur_x, cur_y, cur_z, cur_in
    end

    return out_count
end

--- Stores one band piece.
-- number: x1 first corner x
-- number: y1 first corner y
-- number: x2 second corner x
-- number: y2 second corner y
-- number: x3 third corner x
-- number: y3 third corner y
-- int: step height step of the band
local function _add_band_piece(x1, y1, x2, y2, x3, y3, step)
    local area = (x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)

    if area < 0 then
        area = -area
    end

    if area * 0.5 < MIN_BAND_AREA then
        return
    end

    local bands = _bands
    local n = bands.count + 1

    bands.count = n
    bands.x1[n] = x1
    bands.y1[n] = y1
    bands.x2[n] = x2
    bands.y2[n] = y2
    bands.x3[n] = x3
    bands.y3[n] = y3
    bands.z[n] = (step + 0.5) * TREAD_RISE
    bands.step[n] = step
end

--- Cuts one marked triangle into the bands between the multiples of `TREAD_RISE` its corners span.
-- tab: geometry navmesh geometry
-- int: i triangle index
local function _add_triangle_bands(geometry, i)
    local h1, h2, h3 = geometry.az[i], geometry.bz[i], geometry.cz[i]
    local low, high = h1, h1

    if h2 < low then
        low = h2
    elseif h2 > high then
        high = h2
    end

    if h3 < low then
        low = h3
    elseif h3 > high then
        high = h3
    end

    local ax, ay, az = _poly_ax, _poly_ay, _poly_az
    local bx, by, bz = _poly_bx, _poly_by, _poly_bz

    for step = math_floor(low / TREAD_RISE), math_floor(high / TREAD_RISE) do
        local bottom = step * TREAD_RISE

        ax[1], ay[1], az[1] = geometry.ax[i], geometry.ay[i], h1
        ax[2], ay[2], az[2] = geometry.bx[i], geometry.by[i], h2
        ax[3], ay[3], az[3] = geometry.cx[i], geometry.cy[i], h3

        local count = _clip_height(ax, ay, az, 3, bottom, true, bx, by, bz)

        if count >= 3 then
            count = _clip_height(bx, by, bz, count, bottom + TREAD_RISE, false, ax, ay, az)

            for v = 3, count do
                _add_band_piece(ax[1], ay[1], ax[v - 1], ay[v - 1], ax[v], ay[v], step)
            end
        end
    end
end

--- Marks the next `OUTPUT_BUDGET` sloped triangles of kept facets with lines and bands.
-- tab: build `_build`
-- tab: geometry navmesh geometry
local function _output_step(build, geometry)
    local order_n = build.order_n
    local first = build.cursor + 1
    local last = build.cursor + OUTPUT_BUDGET

    if last > order_n then
        last = order_n
    end

    local order = build.order
    local sloped = build.sloped
    local facet_of = build.facet_of
    local facet_state = build.facet_state
    local marked = build.marked

    for p = first, last do
        local k = order[p]

        if facet_state[facet_of[k]] == FACET_KEPT then
            local i = sloped[k]

            marked = marked + 1
            _add_triangle_lines(build, geometry, i)
            _add_triangle_bands(geometry, i)
        end
    end

    build.marked = marked
    build.cursor = last

    if last >= order_n then
        build.phase = PHASE_INDEX
        build.cursor = 0
        build.ends = nil
    end
end

--- Files a grid cell under a packed key, widening the grid bounds.
-- tab: grid `_lines` or `_bands`
-- number: x point x the cell is taken from
-- number: y point y the cell is taken from
-- int: index mark index
local function _file_mark(grid, x, y, index)
    local cell_x = math_floor(x * INVERSE_CELL_SIZE)
    local cell_y = math_floor(y * INVERSE_CELL_SIZE)

    if grid.max_cx < grid.min_cx then
        grid.min_cx = cell_x
        grid.max_cx = cell_x
        grid.min_cy = cell_y
        grid.max_cy = cell_y
    else
        if cell_x < grid.min_cx then
            grid.min_cx = cell_x
        elseif cell_x > grid.max_cx then
            grid.max_cx = cell_x
        end

        if cell_y < grid.min_cy then
            grid.min_cy = cell_y
        elseif cell_y > grid.max_cy then
            grid.max_cy = cell_y
        end
    end

    local key = (cell_x + CELL_HASH_OFFSET) * CELL_HASH_STRIDE + cell_y + CELL_HASH_OFFSET
    local list = grid.cells[key]
    local size = 0

    if list == nil then
        list = {}
        grid.cells[key] = list
    else
        size = grid.cell_n[key]
    end

    size = size + 1
    list[size] = index
    grid.cell_n[key] = size
end

--- Gives a finished line its rank and files it under the grid cell of its midpoint.
-- tab: lines `_lines`
-- int: i line index
-- int: step height step of the line
local function _index_line(lines, i, step)
    local rank = MAX_MARK_STRIDE

    if step ~= 0 then
        rank = 1

        while rank < MAX_MARK_STRIDE and step % (rank + rank) == 0 do
            rank = rank + rank
        end
    end

    lines.rank[i] = rank

    local x1, y1, x2, y2 = lines.x1[i], lines.y1[i], lines.x2[i], lines.y2[i]
    local dx = x2 - x1
    local dy = y2 - y1
    local half_length = math_sqrt(dx * dx + dy * dy) * 0.5

    if half_length > lines.max_half_length then
        lines.max_half_length = half_length
    end

    _file_mark(lines, (x1 + x2) * 0.5, (y1 + y2) * 0.5, i)
end

--- Files a band piece under the grid cell of its centre, widening the farthest corner distance.
-- tab: bands `_bands`
-- int: i band piece index
local function _index_band(bands, i)
    local x1, y1, x2, y2, x3, y3 = bands.x1[i], bands.y1[i], bands.x2[i], bands.y2[i], bands.x3[i], bands.y3[i]
    local mx = (x1 + x2 + x3) / 3
    local my = (y1 + y2 + y3) / 3
    local radius_sq = (x1 - mx) * (x1 - mx) + (y1 - my) * (y1 - my)
    local candidate = (x2 - mx) * (x2 - mx) + (y2 - my) * (y2 - my)

    if candidate > radius_sq then
        radius_sq = candidate
    end

    candidate = (x3 - mx) * (x3 - mx) + (y3 - my) * (y3 - my)

    if candidate > radius_sq then
        radius_sq = candidate
    end

    local radius = math_sqrt(radius_sq)

    if radius > bands.max_radius then
        bands.max_radius = radius
    end

    _file_mark(bands, mx, my, i)
end

--- Files the next `INDEX_BUDGET` lines and band pieces in their grids, and finishes the build after the last one.
-- Logs the build's counts in debug mode.
-- tab: build `_build`
-- tab: geometry navmesh geometry
local function _index_step(build, geometry)
    local lines = _lines
    local bands = _bands
    local line_count = lines.count
    local total = line_count + bands.count
    local first = build.cursor + 1
    local last = build.cursor + INDEX_BUDGET

    if last > total then
        last = total
    end

    local steps = build.steps

    for item = first, last do
        if item <= line_count then
            _index_line(lines, item, steps[item])
        else
            _index_band(bands, item - line_count)
        end
    end

    build.cursor = last

    if last < total then
        return
    end

    build.status = STATUS_READY
    lines.revision = lines.revision + 1

    if mod:get("debug_mode") == true then
        mod:info(string_format(
            "[Radar] navmesh stair marks ready | triangles=%d sloped=%d facets=%d candidates=%d kept=%d marked=%d"
                .. " probes=%d lines=%d joined=%d bands=%d frames=%d",
            geometry.count,
            build.sloped_n,
            build.facet_count,
            build.candidates,
            build.kept,
            build.marked,
            build.probe_n,
            line_count,
            build.joined,
            bands.count,
            build.frames))
    end

    _release_build_tables(build)
end

--- Runs one frame's budget of the build, in its current phase.
-- tab: build `_build`
-- tab: geometry navmesh geometry
local function _build_step(build, geometry)
    local phase = build.phase

    build.frames = build.frames + 1

    if phase == PHASE_SCAN then
        _scan_step(build, geometry)
    elseif phase == PHASE_FACETS then
        _facets_step(build)
    elseif phase == PHASE_MEASURE then
        _measure_step(build, geometry)
    elseif phase == PHASE_PROBE then
        _probe_step(build, geometry)
    elseif phase == PHASE_OUTPUT then
        _output_step(build, geometry)
    else
        _index_step(build, geometry)
    end
end

-- ----------------------------------------------------------------------------
-- Draw
-- ----------------------------------------------------------------------------

--- Returns a channel moved part of the way to white, rounded.
-- number: channel colour channel
-- number: amount fraction of the way to white
-- treturn: int
local function _brighten(channel, amount)
    return math_floor(channel + (255 - channel) * amount + 0.5)
end

--- Returns an opacity scaled and capped at 255.
-- number: alpha opacity
-- number: mult multiplier
-- treturn: int
local function _scaled_alpha(alpha, mult)
    local scaled = math_floor(alpha * mult + 0.5)

    if scaled > 255 then
        scaled = 255
    end

    return scaled
end

--- Derives the mark colour channels from the floor colours, again only when one of them changed.
-- tab: current current floor colour as an ARGB array
-- tab: above floor-above colour as an ARGB array
-- tab: below floor-below colour as an ARGB array
-- treturn: bool false when the current floor colour is fully transparent
local function _update_colors(current, above, below)
    local colors = _colors
    local a = tonumber(current[1]) or 0
    local r = current[2] or 255
    local g = current[3] or 255
    local b = current[4] or 255
    local above_r = above[2] or 255
    local above_g = above[3] or 255
    local above_b = above[4] or 255
    local below_r = below[2] or 255
    local below_g = below[3] or 255
    local below_b = below[4] or 255

    if colors.a == a and colors.r == r and colors.g == g and colors.b == b and colors.above_r == above_r
        and colors.above_g == above_g and colors.above_b == above_b and colors.below_r == below_r
        and colors.below_g == below_g and colors.below_b == below_b then
        return colors.visible
    end

    colors.a = a
    colors.r = r
    colors.g = g
    colors.b = b
    colors.above_r = above_r
    colors.above_g = above_g
    colors.above_b = above_b
    colors.below_r = below_r
    colors.below_g = below_g
    colors.below_b = below_b
    colors.visible = a > 0

    if a <= 0 then
        return false
    end

    local line_alpha = _scaled_alpha(a, LINE_ALPHA_MULT)
    local stripe_alpha = _scaled_alpha(a, STRIPE_ALPHA_MULT)
    local line_a = colors.line_a
    local stripe_a = colors.stripe_a

    colors.line_r = _brighten(r, LINE_BRIGHTEN)
    colors.line_g = _brighten(g, LINE_BRIGHTEN)
    colors.line_b = _brighten(b, LINE_BRIGHTEN)
    colors.stripe_r = _brighten(r, STRIPE_BRIGHTEN)
    colors.stripe_g = _brighten(g, STRIPE_BRIGHTEN)
    colors.stripe_b = _brighten(b, STRIPE_BRIGHTEN)

    for fade = 1, MARK_FADE_STEPS do
        line_a[fade] = math_floor(line_alpha * MARK_FADE[fade] + 0.5)
        stripe_a[fade] = math_floor(stripe_alpha * MARK_FADE[fade] + 0.5)
    end

    local shade_r = colors.shade_r
    local shade_g = colors.shade_g
    local shade_b = colors.shade_b

    colors.shade_even_a = _scaled_alpha(a, SHADE_ALPHA_EVEN)
    colors.shade_odd_a = _scaled_alpha(a, SHADE_ALPHA_ODD)

    for level = -SHADE_STEPS, SHADE_STEPS do
        local weight = (level < 0 and -level or level) / SHADE_STEPS
        local target_r = level < 0 and below_r or above_r
        local target_g = level < 0 and below_g or above_g
        local target_b = level < 0 and below_b or above_b
        local index = level + SHADE_STEPS + 1

        shade_r[index] = _brighten(r + (target_r - r) * weight, SHADE_BRIGHTEN)
        shade_g[index] = _brighten(g + (target_g - g) * weight, SHADE_BRIGHTEN)
        shade_b[index] = _brighten(b + (target_b - b) * weight, SHADE_BRIGHTEN)
    end

    return true
end

--- Makes this frame's engine colours for one style from the stored channels.
-- `Color` values are temporary and only valid in the frame they were made in, so this runs every
-- frame the marks draw, 4 colours for lines or stripes and 14 for shading.
-- string: style `lines`, `stripes` or `shading`; anything else makes the line colours
local function _make_frame_colors(style)
    local colors = _colors

    if style == STYLE_SHADING then
        local shade_r = colors.shade_r
        local shade_g = colors.shade_g
        local shade_b = colors.shade_b
        local shade_even = colors.shade_even
        local shade_odd = colors.shade_odd
        local even_alpha = colors.shade_even_a
        local odd_alpha = colors.shade_odd_a

        for index = 1, SHADE_STEPS + SHADE_STEPS + 1 do
            shade_even[index] = Color(even_alpha, shade_r[index], shade_g[index], shade_b[index])
            shade_odd[index] = Color(odd_alpha, shade_r[index], shade_g[index], shade_b[index])
        end
    elseif style == STYLE_STRIPES then
        local stripe = colors.stripe
        local stripe_a = colors.stripe_a
        local stripe_r = colors.stripe_r
        local stripe_g = colors.stripe_g
        local stripe_b = colors.stripe_b

        for fade = 1, MARK_FADE_STEPS do
            stripe[fade] = Color(stripe_a[fade], stripe_r, stripe_g, stripe_b)
        end
    else
        local line = colors.line
        local line_a = colors.line_a
        local line_r = colors.line_r
        local line_g = colors.line_g
        local line_b = colors.line_b

        for fade = 1, MARK_FADE_STEPS do
            line[fade] = Color(line_a[fade], line_r, line_g, line_b)
        end
    end
end

--- Lists the lines of at least `stride` rank and the band pieces within reach of the player and near their height.
-- number: origin_x player x
-- number: origin_y player y
-- number: origin_z player z
-- number: line_reach horizontal reach for lines in metres
-- number: band_reach horizontal reach for band pieces in metres
-- int: stride smallest line rank to list
local function _select_marks(origin_x, origin_y, origin_z, line_reach, band_reach, stride)
    local selection = _selection
    local height_reach = MARK_FLOOR_RANGE + SELECTION_HEIGHT_SLACK

    for grid_index = 1, 2 do
        local grid = grid_index == 1 and _lines or _bands
        local list = grid_index == 1 and selection.lines or selection.bands
        local reach = grid_index == 1 and line_reach or band_reach
        local rank = grid_index == 1 and _lines.rank or nil
        local n = 0
        local min_cx = math_floor((origin_x - reach) * INVERSE_CELL_SIZE)
        local max_cx = math_floor((origin_x + reach) * INVERSE_CELL_SIZE)
        local min_cy = math_floor((origin_y - reach) * INVERSE_CELL_SIZE)
        local max_cy = math_floor((origin_y + reach) * INVERSE_CELL_SIZE)

        if min_cx < grid.min_cx then
            min_cx = grid.min_cx
        end

        if max_cx > grid.max_cx then
            max_cx = grid.max_cx
        end

        if min_cy < grid.min_cy then
            min_cy = grid.min_cy
        end

        if max_cy > grid.max_cy then
            max_cy = grid.max_cy
        end

        local cells = grid.cells
        local cell_n = grid.cell_n
        local z = grid.z

        for cell_x = min_cx, max_cx do
            local row_key = (cell_x + CELL_HASH_OFFSET) * CELL_HASH_STRIDE + CELL_HASH_OFFSET

            for cell_y = min_cy, max_cy do
                local key = row_key + cell_y
                local cell = cells[key]

                if cell then
                    for j = 1, cell_n[key] do
                        local i = cell[j]
                        local dz = z[i] - origin_z

                        if dz <= height_reach and dz >= -height_reach and (rank == nil or rank[i] >= stride) then
                            n = n + 1
                            list[n] = i
                        end
                    end
                end
            end
        end

        if grid_index == 1 then
            selection.line_count = n
        else
            selection.band_count = n
        end
    end

    selection.revision = _lines.revision
    selection.stride = stride
    selection.refreshes = selection.refreshes + 1
end

--- Draws the listed lines thin, in the line colours.
-- Takes the frame's projection; see `RadarStairTreads.draw`.
-- treturn: int number of lines drawn
local function _draw_lines(gui, layer, origin_x, origin_y, origin_z, right_x, right_y, down_x, down_y, is_circle, limit,
                           ui_scale, center_x, center_y)
    local lines = _lines
    local selection = _selection
    local list = selection.lines
    local x1, y1, x2, y2, z = lines.x1, lines.y1, lines.x2, lines.y2, lines.z
    local by_fade = _colors.line
    local limit_sq = limit * limit
    local half_width = LINE_HALF_WIDTH * ui_scale
    local floor_range = MARK_FLOOR_RANGE
    local drawn = 0

    for k = 1, selection.line_count do
        local i = list[k]
        local dz = z[i] - origin_z

        if dz < 0 then
            dz = -dz
        end

        if dz <= floor_range then
            local dx = x1[i] - origin_x
            local dy = y1[i] - origin_y
            local sx1 = dx * right_x + dy * right_y
            local sy1 = dx * down_x + dy * down_y

            dx = x2[i] - origin_x
            dy = y2[i] - origin_y

            local sx2 = dx * right_x + dy * right_y
            local sy2 = dx * down_x + dy * down_y

            if not ((sx1 > limit and sx2 > limit) or (sx1 < -limit and sx2 < -limit)
                    or (sy1 > limit and sy2 > limit) or (sy1 < -limit and sy2 < -limit)) then
                local ddx = sx2 - sx1
                local ddy = sy2 - sy1
                local t0 = 0
                local t1 = 1

                if is_circle then
                    if sx1 * sx1 + sy1 * sy1 > limit_sq or sx2 * sx2 + sy2 * sy2 > limit_sq then
                        local a = ddx * ddx + ddy * ddy
                        local b = sx1 * ddx + sy1 * ddy
                        local disc = b * b - a * (sx1 * sx1 + sy1 * sy1 - limit_sq)

                        if a > 1e-9 and disc > 0 then
                            local root = math_sqrt(disc)

                            t0 = (-b - root) / a
                            t1 = (-b + root) / a

                            if t0 < 0 then
                                t0 = 0
                            end

                            if t1 > 1 then
                                t1 = 1
                            end
                        else
                            t1 = -1
                        end
                    end
                else
                    if ddx ~= 0 then
                        local ta = (-limit - sx1) / ddx
                        local tb = (limit - sx1) / ddx

                        if ta > tb then
                            ta, tb = tb, ta
                        end

                        if ta > t0 then
                            t0 = ta
                        end

                        if tb < t1 then
                            t1 = tb
                        end
                    end

                    if ddy ~= 0 then
                        local ta = (-limit - sy1) / ddy
                        local tb = (limit - sy1) / ddy

                        if ta > tb then
                            ta, tb = tb, ta
                        end

                        if ta > t0 then
                            t0 = ta
                        end

                        if tb < t1 then
                            t1 = tb
                        end
                    end
                end

                if t0 < t1 then
                    local qx1 = (center_x + sx1 + ddx * t0) * ui_scale
                    local qy1 = (center_y + sy1 + ddy * t0) * ui_scale
                    local qx2 = (center_x + sx1 + ddx * t1) * ui_scale
                    local qy2 = (center_y + sy1 + ddy * t1) * ui_scale
                    local sdx = qx2 - qx1
                    local sdy = qy2 - qy1
                    local length_sq = sdx * sdx + sdy * sdy

                    if length_sq > MIN_SCREEN_LENGTH_SQ then
                        local offset = half_width / math_sqrt(length_sq)
                        local nx = -sdy * offset
                        local ny = sdx * offset
                        local fade = math_floor(dz) + 1

                        if fade > MARK_FADE_STEPS then
                            fade = MARK_FADE_STEPS
                        end

                        local color = by_fade[fade]
                        local start_corner = Vector3(qx1 + nx, 0, qy1 + ny)
                        local end_corner = Vector3(qx2 - nx, 0, qy2 - ny)

                        Gui_triangle(gui, start_corner, Vector3(qx2 + nx, 0, qy2 + ny), end_corner, layer, color)
                        Gui_triangle(gui, start_corner, end_corner, Vector3(qx1 - nx, 0, qy1 - ny), layer, color)
                        drawn = drawn + 1
                    end
                end
            end
        end
    end

    return drawn
end

--- Draws the listed band pieces as stripes or shading.
-- Stripes fill the bands of even steps (counted in strides) in the stripe colours, faded by height
-- difference. Shading fills every band in the shading colour of its height difference, at the even
-- or odd opacity of its step. Takes the frame's projection; see `RadarStairTreads.draw`.
-- bool: shading true for shading, false for stripes
-- int: stride how many bands make one stripe or shading step
-- treturn: int number of band pieces drawn
local function _draw_bands(gui, layer, shading, stride, origin_x, origin_y, origin_z, right_x, right_y, down_x, down_y,
                           is_circle, limit, ui_scale, center_x, center_y)
    local bands = _bands
    local selection = _selection
    local list = selection.bands
    local x1, y1, x2, y2, x3, y3 = bands.x1, bands.y1, bands.x2, bands.y2, bands.x3, bands.y3
    local z = bands.z
    local step = bands.step
    local colors = _colors
    local stripe = colors.stripe
    local shade_even = colors.shade_even
    local shade_odd = colors.shade_odd
    local limit_sq = limit * limit
    local floor_range = MARK_FLOOR_RANGE
    local clip_and_emit = _clip_and_emit
    local drawn = 0

    for k = 1, selection.band_count do
        local i = list[k]
        local dz = z[i] - origin_z
        local distance = dz < 0 and -dz or dz

        if distance <= floor_range then
            local even = math_floor(step[i] / stride) % 2 == 0
            local color = nil

            if shading then
                local level = math_floor(dz / SHADE_FULL_DZ * SHADE_STEPS + 0.5)

                if level > SHADE_STEPS then
                    level = SHADE_STEPS
                elseif level < -SHADE_STEPS then
                    level = -SHADE_STEPS
                end

                color = even and shade_even[level + SHADE_STEPS + 1] or shade_odd[level + SHADE_STEPS + 1]
            elseif even then
                local fade = math_floor(distance) + 1

                if fade > MARK_FADE_STEPS then
                    fade = MARK_FADE_STEPS
                end

                color = stripe[fade]
            end

            if color then
                local dx = x1[i] - origin_x
                local dy = y1[i] - origin_y
                local sx1 = dx * right_x + dy * right_y
                local sy1 = dx * down_x + dy * down_y

                dx = x2[i] - origin_x
                dy = y2[i] - origin_y

                local sx2 = dx * right_x + dy * right_y
                local sy2 = dx * down_x + dy * down_y

                dx = x3[i] - origin_x
                dy = y3[i] - origin_y

                local sx3 = dx * right_x + dy * right_y
                local sy3 = dx * down_x + dy * down_y

                drawn = drawn + clip_and_emit(gui, layer, color, is_circle, limit, limit_sq, ui_scale, center_x,
                    center_y, sx1, sy1, sx2, sy2, sx3, sy3)
            end
        end
    end

    return drawn
end

-- ----------------------------------------------------------------------------
-- Interface
-- ----------------------------------------------------------------------------

--- Module interface consumed by `ui/Radar_navmesh_renderer.lua`.
local RadarStairTreads = {}

--- Starts or continues the build of the marks for a navmesh geometry, one budget step per call.
-- A new geometry table or revision starts over; a finished or failed build is left as it is.
-- tab: geometry navmesh geometry of `Radar_navmesh.lua`
-- treturn: bool true once the marks are ready
function RadarStairTreads.update(geometry)
    local build = _build

    if build.geometry ~= geometry or build.revision ~= geometry.revision then
        _start_build(build, geometry)
    end

    if build.status == STATUS_BUILDING then
        _build_step(build, geometry)
    end

    return build.status == STATUS_READY
end

--- Runs the whole build for a navmesh geometry at once, for a frame whose stall goes unseen.
-- Starts over like `update` for a new geometry table or revision, and leaves a finished or failed build
-- as it is.
-- tab: geometry navmesh geometry of `Radar_navmesh.lua`
-- treturn: bool true once the marks are ready
function RadarStairTreads.build_now(geometry)
    local build = _build

    if build.geometry ~= geometry or build.revision ~= geometry.revision then
        _start_build(build, geometry)
    end

    while build.status == STATUS_BUILDING do
        _build_step(build, geometry)
    end

    return build.status == STATUS_READY
end

--- Drops the build and the marks, so the next update starts over.
function RadarStairTreads.reset()
    local build = _build

    if build.status == STATUS_IDLE and build.geometry == nil then
        return
    end

    _release_build_tables(build)
    _clear_marks()
    build.geometry = nil
    build.revision = nil
    build.status = STATUS_IDLE
    build.phase = 0
    build.cursor = 0
    build.frames = 0
    build.sloped_n = 0
    build.facet_count = 0
    build.order_n = 0
    build.probe_n = 0
    build.joined = 0
    build.candidates = 0
    build.kept = 0
    build.marked = 0
end

--- Stops the marks of the current geometry after an error, until the geometry changes.
-- param: err error value, logged in debug mode
function RadarStairTreads.fail(err)
    local build = _build

    _release_build_tables(build)
    _clear_marks()
    build.status = STATUS_FAILED

    if mod:get("debug_mode") == true then
        mod:info(string_format("[Radar] navmesh stair marks stopped until the navmesh changes: %s", tostring(err)))
    end
end

--- Draws the marks around the player for one frame, in one style.
-- The points are projected like the fills, `sx = dx * right_x + dy * right_y` and
-- `sy = dx * down_x + dy * down_y` in unscaled pixels from the radar centre, and clipped to the radar
-- circle or square. The marks are listed again when `reselect` is set, the marks changed or the zoom
-- changed the stride. The style's colours are made again every frame.
-- param: gui GUI to draw into
-- int: layer GUI draw layer
-- string: style `lines`, `stripes` or `shading`; anything else draws lines
-- tab: current current floor colour as an ARGB array
-- tab: above floor-above colour as an ARGB array
-- tab: below floor-below colour as an ARGB array
-- bool: reselect true when the navmesh layer selected its triangles again this frame
-- number: origin_x player x
-- number: origin_y player y
-- number: origin_z player z
-- number: right_x screen x per metre of world x
-- number: right_y screen x per metre of world y
-- number: down_x screen y per metre of world x
-- number: down_y screen y per metre of world y
-- number: radar_scale unscaled pixels per metre
-- bool: is_circle clip to the radar circle rather than the square
-- number: limit circle radius or square half size in unscaled pixels
-- number: ui_scale UI scale applied to the final screen positions
-- number: center_x radar centre x in unscaled UI pixels
-- number: center_y radar centre y in unscaled UI pixels
-- number: range radar range in metres
-- treturn: int number of lines or band pieces drawn
function RadarStairTreads.draw(gui, layer, style, current, above, below, reselect, origin_x, origin_y, origin_z, right_x,
                               right_y, down_x, down_y, radar_scale, is_circle, limit, ui_scale, center_x, center_y, range)
    local lines = _lines

    if _build.status ~= STATUS_READY or (lines.count == 0 and _bands.count == 0) or not Gui_triangle then
        return 0
    end

    local spacing = TYPICAL_TREAD_RUN * radar_scale
    local stride = 1

    while spacing * stride < MIN_MARK_SPACING_PX do
        stride = stride + stride

        if stride > MAX_MARK_STRIDE then
            return 0
        end
    end

    if not _update_colors(current, above, below) then
        return 0
    end

    local selection = _selection

    if reselect or selection.revision ~= lines.revision or selection.stride ~= stride then
        local reach = (is_circle and range or range * SQUARE_REACH_MULT) + SELECTION_SLACK

        _select_marks(origin_x, origin_y, origin_z, reach + lines.max_half_length, reach + _bands.max_radius, stride)
    end

    _make_frame_colors(style)

    if style == STYLE_STRIPES or style == STYLE_SHADING then
        return _draw_bands(gui, layer, style == STYLE_SHADING, stride, origin_x, origin_y, origin_z, right_x, right_y,
            down_x, down_y, is_circle, limit, ui_scale, center_x, center_y)
    end

    return _draw_lines(gui, layer, origin_x, origin_y, origin_z, right_x, right_y, down_x, down_y, is_circle, limit,
        ui_scale, center_x, center_y)
end

return RadarStairTreads
