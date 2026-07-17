local mod = get_mod("Radar")

-- Map-geometry (navigation mesh) source for the radar.
--
-- Reads the engine navigation world into a flat, world-space triangle buffer plus a fixed-size 2D
-- spatial grid, so the renderer can query nearby walkable geometry without touching the full
-- mission mesh every frame. Projection and drawing live in ui/Radar_navmesh_renderer.lua.
--
-- The GwNav database functions are private debugging APIs, so every access is treated as
-- optional: calls run under pcall, returned coordinates are validated, and any failure just
-- leaves the buffer empty (retried on a cooldown). Geometry from a previous nav world is dropped
-- the moment the world changes, so a stale mission layout can never be drawn while a rebuild for
-- the new mission is still pending or failing.

return function(env)
    setfenv(1, env)

    local next = next
    local pcall = pcall
    local tonumber = tonumber
    local tostring = tostring
    local type = type
    local math_floor = math.floor
    local math_sqrt = math.sqrt
    local string_format = string.format
    local os_clock = os and os.clock or nil

    -- Retry cadence while a rebuild is pending. The nav world is often not readable on the exact
    -- frame a mission starts, so a failed build retries on this interval rather than every frame.
    local NAVMESH_REGEN_COOLDOWN = 0.5

    -- Edge length of one spatial bucket in metres. Triangles are bucketed by centroid; the
    -- renderer queries only the buckets intersecting the radar range.
    local NAVMESH_BUCKET_CELL_SIZE = 16

    -- Bucket key packing: key = (cell_x + OFFSET) * STRIDE + (cell_y + OFFSET). Supports world
    -- coordinates up to +-(OFFSET * cell size) metres and stays exact within double precision.
    local BUCKET_KEY_OFFSET = 32768
    local BUCKET_KEY_STRIDE = 65536

    -- Coordinates beyond this are treated as corrupt engine data and the triangle is discarded.
    local MAX_VALID_COORDINATE = 100000

    -- Hard ceiling on the bucket rings walked per query, regardless of the requested range.
    local MAX_QUERY_CELL_REACH = 64

    -- Structure-of-arrays triangle buffer, reused across rebuilds to avoid per-build allocation.
    -- Index i describes one walkable triangle by its three world-space corners (full 3D -- Z is
    -- kept for height filtering) plus the precomputed centroid and a horizontal bounding radius
    -- used for cheap range and screen-size culling. `buckets` maps packed cell keys to arrays of
    -- triangle indices. Only indices 1..count are ever valid; stale entries beyond `count` are
    -- left in place and never read.
    local geometry = {
        ax = {}, ay = {}, az = {},
        bx = {}, by = {}, bz = {},
        cx = {}, cy = {}, cz = {},
        mid_x = {}, mid_y = {}, mid_z = {},
        radius = {},
        count = 0,
        max_radius = 0,
        cell_size = NAVMESH_BUCKET_CELL_SIZE,
        buckets = {},
        -- bumped whenever the published triangle set changes, so renderers can invalidate caches
        revision = 0,
        -- development metrics (see mod:get_navmesh_geometry)
        tile_count = nil,
        build_ms = nil,
    }

    local dirty = true
    local last_gen_t = nil
    local last_nav_world = nil
    local last_logged_failure = nil

    local function _is_valid_coordinate(v)
        -- also rejects NaN (v ~= v) and infinities via the range comparison
        return type(v) == "number" and v > -MAX_VALID_COORDINATE and v < MAX_VALID_COORDINATE
    end

    local function _current_nav_world()
        local state_manager = Managers and Managers.state
        local nav_mesh = state_manager and state_manager.nav_mesh

        return nav_mesh and nav_mesh._nav_world or nil
    end

    -- Drop all published geometry immediately and bump the revision so renderers invalidate
    -- their cached selections. Cheap no-op when already empty.
    local function _reset_geometry()
        if geometry.count == 0 and next(geometry.buckets) == nil then
            return
        end

        geometry.count = 0
        geometry.max_radius = 0
        geometry.buckets = {}
        geometry.revision = geometry.revision + 1
    end

    -- Walk every triangle in the nav database into the SoA buffer. Runs inside pcall: the GwNav
    -- debug API can change between game versions, so any error here just means "unavailable".
    -- Writes past geometry.count only, so a mid-loop failure never publishes partial data.
    local function _extract(nav_world)
        GwNavWorld.build_database_visual_representation(nav_world)

        local tile_count = GwNavWorld.database_tile_count(nav_world)

        if type(tile_count) ~= "number" or tile_count ~= tile_count or tile_count < 0 then
            error("invalid nav database tile count: " .. tostring(tile_count))
        end

        local database_tile_triangle_count = GwNavWorld.database_tile_triangle_count
        local database_triangle = GwNavWorld.database_triangle
        local script = Script
        local temp_byte_count = script and script.temp_byte_count
        local set_temp_byte_count = script and script.set_temp_byte_count

        if not set_temp_byte_count then
            temp_byte_count = nil
        end
        local ax, ay, az = geometry.ax, geometry.ay, geometry.az
        local bx, by, bz = geometry.bx, geometry.by, geometry.bz
        local cx, cy, cz = geometry.cx, geometry.cy, geometry.cz
        local mid_x, mid_y, mid_z = geometry.mid_x, geometry.mid_y, geometry.mid_z
        local radius = geometry.radius
        local is_valid = _is_valid_coordinate
        local count = 0
        local max_radius = 0

        for tile_index = 1, tile_count do
            local triangle_count = tonumber(database_tile_triangle_count(nav_world, tile_index)) or 0

            for triangle_index = 1, triangle_count do
                -- database_triangle allocates temp Vector3s; release them per triangle like the
                -- game's own extraction loops do, or a large mission exhausts the temp allocator.
                local temp_size = temp_byte_count and temp_byte_count()
                local a, b, c = database_triangle(nav_world, tile_index, triangle_index)

                if a and b and c then
                    local x1, y1, z1 = a.x, a.y, a.z
                    local x2, y2, z2 = b.x, b.y, b.z
                    local x3, y3, z3 = c.x, c.y, c.z

                    if is_valid(x1) and is_valid(y1) and is_valid(z1)
                        and is_valid(x2) and is_valid(y2) and is_valid(z2)
                        and is_valid(x3) and is_valid(y3) and is_valid(z3) then
                        count = count + 1
                        ax[count], ay[count], az[count] = x1, y1, z1
                        bx[count], by[count], bz[count] = x2, y2, z2
                        cx[count], cy[count], cz[count] = x3, y3, z3

                        local center_x = (x1 + x2 + x3) / 3
                        local center_y = (y1 + y2 + y3) / 3

                        mid_x[count] = center_x
                        mid_y[count] = center_y
                        mid_z[count] = (z1 + z2 + z3) / 3

                        local dx = x1 - center_x
                        local dy = y1 - center_y
                        local radius_sq = dx * dx + dy * dy

                        dx = x2 - center_x
                        dy = y2 - center_y
                        local candidate_sq = dx * dx + dy * dy

                        if candidate_sq > radius_sq then
                            radius_sq = candidate_sq
                        end

                        dx = x3 - center_x
                        dy = y3 - center_y
                        candidate_sq = dx * dx + dy * dy

                        if candidate_sq > radius_sq then
                            radius_sq = candidate_sq
                        end

                        local triangle_radius = math_sqrt(radius_sq)

                        radius[count] = triangle_radius

                        if triangle_radius > max_radius then
                            max_radius = triangle_radius
                        end
                    end
                end

                if temp_size then
                    set_temp_byte_count(temp_size)
                end
            end
        end

        return count, max_radius, tile_count
    end

    local function _log_build_failure(reason)
        if mod:get("debug_mode") ~= true then
            return
        end

        reason = tostring(reason)

        if reason == last_logged_failure then
            return
        end

        last_logged_failure = reason
        mod:info(string_format("[Radar] navmesh build unavailable: %s", reason))
    end

    -- Flatten the engine navigation database into the SoA buffer and publish the spatial
    -- buckets. Returns true on a successful (re)build, false when the nav world cannot be read.
    local function _build(nav_world)
        local gw_nav_world = GwNavWorld

        if not gw_nav_world
            or type(gw_nav_world.build_database_visual_representation) ~= "function"
            or type(gw_nav_world.database_tile_count) ~= "function"
            or type(gw_nav_world.database_tile_triangle_count) ~= "function"
            or type(gw_nav_world.database_triangle) ~= "function" then
            _log_build_failure("GwNavWorld database API not available")

            return false
        end

        local build_start = os_clock and os_clock() or nil
        local ok, count, max_radius, tile_count = pcall(_extract, nav_world)

        if not ok then
            _log_build_failure(count)

            return false
        end

        if not count or count <= 0 then
            _log_build_failure("nav database returned no triangles")

            return false
        end

        -- Publish: bucket every triangle by its centroid cell. A fresh bucket map guarantees no
        -- leftovers from a previous mission survive. Each bucket also carries its cell
        -- coordinates and the z-range of its triangles, so the renderer's coarse fill mode can
        -- place and height-filter whole cells without touching the triangle data.
        local buckets = {}
        local cell_size = NAVMESH_BUCKET_CELL_SIZE
        local mid_x, mid_y, mid_z = geometry.mid_x, geometry.mid_y, geometry.mid_z

        for i = 1, count do
            local cell_x = math_floor(mid_x[i] / cell_size)
            local cell_y = math_floor(mid_y[i] / cell_size)
            local key = (cell_x + BUCKET_KEY_OFFSET) * BUCKET_KEY_STRIDE + (cell_y + BUCKET_KEY_OFFSET)
            local bucket = buckets[key]
            local z = mid_z[i]

            if bucket then
                bucket[#bucket + 1] = i

                if z < bucket.min_z then
                    bucket.min_z = z
                elseif z > bucket.max_z then
                    bucket.max_z = z
                end
            else
                bucket = { i }
                bucket.cell_x = cell_x
                bucket.cell_y = cell_y
                bucket.min_z = z
                bucket.max_z = z
                buckets[key] = bucket
            end
        end

        geometry.count = count
        geometry.max_radius = max_radius
        geometry.buckets = buckets
        geometry.tile_count = tile_count
        geometry.build_ms = build_start and (os_clock() - build_start) * 1000 or nil
        geometry.revision = geometry.revision + 1
        last_logged_failure = nil

        if mod:get("debug_mode") == true then
            mod:info(string_format(
                "[Radar] navmesh build | tiles=%d triangles=%d max_radius=%.1f build_ms=%.2f",
                tile_count,
                count,
                max_radius,
                tonumber(geometry.build_ms) or -1
            ))
        end

        return true
    end

    -- Force a rebuild on the next `ensure`. Hook for callers that learn the navigation database
    -- changed mid-mission (the nav-world identity check below already covers level transitions).
    -- The current geometry keeps drawing until the rebuild succeeds, which is safe because a
    -- dirty flag within one mission never references another mission's layout.
    function mod:mark_navmesh_dirty()
        dirty = true
    end

    -- Drop the cached geometry outright (used when the geometry layer is switched off) and
    -- rebuild lazily on the next `ensure`.
    function mod:clear_navmesh_geometry()
        _reset_geometry()
        last_nav_world = nil
        last_gen_t = nil
        dirty = true
    end

    -- Lazily (re)build the geometry as needed and return the shared buffer. Cheap on the common
    -- path: rebuilds only when the nav world changed (new mission) or a build is still pending,
    -- and never more often than NAVMESH_REGEN_COOLDOWN.
    function mod:ensure_navmesh_geometry(t)
        local nav_world = _current_nav_world()

        if not nav_world then
            -- No mission / between levels: drop stale geometry immediately and arm a rebuild.
            _reset_geometry()
            last_nav_world = nil
            last_gen_t = nil
            dirty = true

            return geometry
        end

        if nav_world ~= last_nav_world then
            -- New nav world: never keep the previous mission's layout visible while the new
            -- cache is still being built (or failing to build).
            _reset_geometry()
            last_nav_world = nav_world
            last_gen_t = nil
            dirty = true
        end

        if dirty then
            t = tonumber(t) or 0

            -- Gameplay time restarts per mission; a stamp from a longer previous session would
            -- otherwise block rebuilds forever.
            if last_gen_t and t < last_gen_t then
                last_gen_t = nil
            end

            if not last_gen_t or (t - last_gen_t) >= NAVMESH_REGEN_COOLDOWN then
                if _build(nav_world) then
                    dirty = false
                end

                last_gen_t = t
            end
        end

        return geometry
    end

    -- Append every spatial bucket whose cell intersects the horizontal square of `range` metres
    -- around (origin_x, origin_y) to out_buckets (a caller-owned scratch array that is reused
    -- across calls; only indices 1..return-value are valid). Buckets are visited centre-first in
    -- expanding cell rings, so capped consumers naturally keep the geometry closest to the
    -- player. Returns the number of buckets written.
    function mod:get_navmesh_nearby_buckets(origin_x, origin_y, range, out_buckets)
        local buckets = geometry.buckets
        local cell_size = geometry.cell_size
        local center_cell_x = math_floor(origin_x / cell_size)
        local center_cell_y = math_floor(origin_y / cell_size)
        local cell_reach = math_floor((tonumber(range) or 0) / cell_size) + 1
        local n = 0

        if cell_reach > MAX_QUERY_CELL_REACH then
            cell_reach = MAX_QUERY_CELL_REACH
        end

        local bucket = buckets[(center_cell_x + BUCKET_KEY_OFFSET) * BUCKET_KEY_STRIDE
            + (center_cell_y + BUCKET_KEY_OFFSET)]

        if bucket then
            n = n + 1
            out_buckets[n] = bucket
        end

        for ring = 1, cell_reach do
            local min_x = center_cell_x - ring
            local max_x = center_cell_x + ring
            local min_y = center_cell_y - ring
            local max_y = center_cell_y + ring
            local min_y_key = min_y + BUCKET_KEY_OFFSET
            local max_y_key = max_y + BUCKET_KEY_OFFSET

            for cell_x = min_x, max_x do
                local column = (cell_x + BUCKET_KEY_OFFSET) * BUCKET_KEY_STRIDE

                bucket = buckets[column + min_y_key]

                if bucket then
                    n = n + 1
                    out_buckets[n] = bucket
                end

                bucket = buckets[column + max_y_key]

                if bucket then
                    n = n + 1
                    out_buckets[n] = bucket
                end
            end

            local min_x_column = (min_x + BUCKET_KEY_OFFSET) * BUCKET_KEY_STRIDE
            local max_x_column = (max_x + BUCKET_KEY_OFFSET) * BUCKET_KEY_STRIDE

            for cell_y = min_y + 1, max_y - 1 do
                local row = cell_y + BUCKET_KEY_OFFSET

                bucket = buckets[min_x_column + row]

                if bucket then
                    n = n + 1
                    out_buckets[n] = bucket
                end

                bucket = buckets[max_x_column + row]

                if bucket then
                    n = n + 1
                    out_buckets[n] = bucket
                end
            end
        end

        return n
    end

    function mod:get_navmesh_geometry()
        return geometry
    end
end
