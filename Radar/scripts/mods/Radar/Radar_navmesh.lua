local mod = get_mod("Radar")

-- Live map-geometry (navmesh) source
-- Author: dreams
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

    local NAVMESH_REGEN_COOLDOWN = 0.5
    local NAVMESH_BUCKET_CELL_SIZE = 16
    local BUCKET_KEY_OFFSET = 32768
    local BUCKET_KEY_STRIDE = 65536
    local MAX_VALID_COORDINATE = 100000
    local MAX_QUERY_CELL_REACH = 64

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
        revision = 0,
        tile_count = nil,
        build_ms = nil,
    }

    local dirty = true
    local last_gen_t = nil
    local last_nav_world = nil
    local last_logged_failure = nil

    local function _is_valid_coordinate(v)
        return type(v) == "number" and v > -MAX_VALID_COORDINATE and v < MAX_VALID_COORDINATE
    end

    local function _current_nav_world()
        local state_manager = Managers and Managers.state
        local nav_mesh = state_manager and state_manager.nav_mesh

        return nav_mesh and nav_mesh._nav_world or nil
    end

    local function _reset_geometry()
        if geometry.count == 0 and next(geometry.buckets) == nil then
            return
        end

        geometry.count = 0
        geometry.max_radius = 0
        geometry.buckets = {}
        geometry.revision = geometry.revision + 1
    end

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

    function mod:mark_navmesh_dirty()
        dirty = true
    end

    function mod:clear_navmesh_geometry()
        _reset_geometry()
        last_nav_world = nil
        last_gen_t = nil
        dirty = true
    end

    function mod:ensure_navmesh_geometry(t)
        local nav_world = _current_nav_world()

        if not nav_world then
            _reset_geometry()
            last_nav_world = nil
            last_gen_t = nil
            dirty = true

            return geometry
        end

        if nav_world ~= last_nav_world then
            _reset_geometry()
            last_nav_world = nav_world
            last_gen_t = nil
            dirty = true
        end

        if dirty then
            t = tonumber(t) or 0

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
