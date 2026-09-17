--- Optional integration with the Strikemap mod's public compatibility API.
-- Resolves Strikemap and its versioned API lazily (so no fixed load order is needed),
-- registers Radar as a geometry consumer, fetches and validates the map context (the
-- walkable triangles and their spatial index) and the optional vector context (contours,
-- stairs, hatches, slopes, transitions), and caches both per geometry revision.
--
-- The integration runs as a small status machine. `waiting` and `map_unavailable` retry
-- after an interval, `active` polls Strikemap's status for new geometry revisions, and
-- `incompatible` and `error` are sticky until `reset` (a map geometry source change or a
-- mod reload). Each status change is logged once; a failure never affects the rest of
-- Radar, which falls back to its own background or the live navmesh layer.
--
-- Explicit module. `Radar.lua` and `ui/Radar_strikemap_geometry.lua` both load it through
-- `mod:io_dofile`, which runs the file again each time, so the singleton is cached on
-- `mod._strikemap_compatibility` and returned by every later load. Loading it also adds
-- `mod:reset_strikemap_integration` and chains `mod.on_setting_changed` and `mod.on_disabled`.
-- module: Radar_strikemap
-- alias: StrikemapCompatibility
-- author: LucLeto
local mod = get_mod("Radar")

-- `mod:io_dofile` runs the file again on every load; reuse the first instance so its state and
-- callbacks exist only once.
if mod._strikemap_compatibility then
    return mod._strikemap_compatibility
end

local pcall = pcall
local rawget = rawget
local tonumber = tonumber
local tostring = tostring
local type = type
local math_floor = math.floor
local string_format = string.format

--- Strikemap API contract Radar understands.
-- Map triangles are flat records of `TRIANGLE_STRIDE` numbers; each vector layer names its
-- array, count and stride fields and the stride Radar can read.
local SUPPORTED_STRIKEMAP_API_VERSION = 1
local TRIANGLE_STRIDE = 7
local VECTOR_LAYER_SPECS = {
    { array_field = "contours", count_field = "contour_count", stride_field = "contour_stride", stride = 5 },
    { array_field = "stairs", count_field = "stair_count", stride_field = "stair_stride", stride = 6 },
    { array_field = "hatches", count_field = "hatch_count", stride_field = "hatch_stride", stride = 5 },
    { array_field = "slopes", count_field = "slope_count", stride_field = "slope_stride", stride = 5 },
    { array_field = "transitions", count_field = "transition_count", stride_field = "transition_stride", stride = 4 },
}
--- Consumer id Radar registers with Strikemap, and the retry intervals in seconds while no map is usable.
local CONSUMER_ID = "Radar"
local RETRY_WAITING_INTERVAL = 2
local RETRY_MAP_UNAVAILABLE_INTERVAL = 5
--- Interval at which Strikemap's status is polled while a map is active.
-- Short, so newly scanned floor appears on the radar almost immediately after Strikemap
-- publishes a new geometry revision; the full context is only refetched when the revision
-- actually changes.
local STATUS_POLL_INTERVAL = 0.25
--- Slow fallback refresh for API variants whose status reports no geometry revision.
-- Every refresh then refetches and revalidates the full map context.
local CONTEXT_REFRESH_INTERVAL = 3
--- Mod names Strikemap may be registered under with DMF, tried in order.
local STRIKEMAP_MOD_NAME_CANDIDATES = {
    "strikemap",
    "Strikemap",
    "StrikeMap",
    "strike_map",
    "Strike_Map",
}

--- Statuses that stop all further attempts and unregister the consumer until the integration is reset.
local STICKY_STATUSES = {
    incompatible = true,
    error = true,
}

--- Integration singleton and its cached state.
-- `_vector_failed_revision` starts as `false` rather than nil so it can never match a map
-- context without a revision.
local StrikemapCompatibility = {
    _status = "disabled",
    _status_detail = nil,
    _context = nil,
    _context_revision = nil,
    _vector_context = nil,
    _vector_counts = nil,
    _vector_failed_revision = false,
    _api = nil,
    _consumer_registered = false,
    _next_attempt_t = 0,
    _next_refresh_t = 0,
}

--- Moves the integration to a status and logs the transition once.
-- Repeating the current status and detail is a no-op, so polling never spams the log. A
-- sticky status also unregisters the consumer.
-- string: status `disabled`, `waiting`, `active`, `map_unavailable`, `incompatible` or `error`
-- ?string: detail map id for `active`, otherwise a reason
function StrikemapCompatibility:_set_status(status, detail)
    if self._status == status and self._status_detail == detail then
        return
    end

    self._status = status
    self._status_detail = detail

    if status == "active" then
        mod:info(string_format("[Radar] Strikemap geometry integration active | map=%s", tostring(detail)))
    elseif status == "map_unavailable" then
        if detail ~= nil then
            mod:info(string_format("[Radar] Strikemap geometry unavailable: %s Using the standard Radar background.",
                tostring(detail)))
        else
            mod:info("[Radar] No Strikemap map is available for this mission. Using the standard Radar background.")
        end
    elseif status == "incompatible" then
        mod:info(string_format("[Radar] Strikemap geometry integration disabled: %s", tostring(detail)))
    elseif status == "error" then
        mod:error("[Radar] Strikemap geometry integration failed: %s", tostring(detail))
    elseif status == "waiting" and mod:get("debug_mode") == true then
        mod:info("[Radar] Waiting for the Strikemap compatibility API.")
    end

    if STICKY_STATUSES[status] then
        self:_unregister_consumer()
    end
end

--- Returns whether the map geometry source setting asks for Strikemap geometry (`strikemap` or `auto`).
-- treturn: bool
function StrikemapCompatibility:is_integration_enabled()
    local get_map_geometry_source = mod.get_map_geometry_source

    if not get_map_geometry_source then
        return false
    end

    local source = get_map_geometry_source(mod)

    return source == "strikemap" or source == "auto"
end

--- Finds the Strikemap mod object under any of its known names.
-- A mod that reports itself disabled is skipped; one without `is_enabled` is accepted.
-- treturn: ?tab Strikemap mod, or nil when it is not installed or not enabled
local function _resolve_strikemap_mod()
    local get_mod_fn = rawget(_G, "get_mod")

    if type(get_mod_fn) ~= "function" then
        return nil
    end

    for i = 1, #STRIKEMAP_MOD_NAME_CANDIDATES do
        local ok, other_mod = pcall(get_mod_fn, STRIKEMAP_MOD_NAME_CANDIDATES[i])

        if ok and type(other_mod) == "table" then
            local is_enabled = other_mod.is_enabled

            if type(is_enabled) ~= "function" then
                return other_mod
            end

            local ok_enabled, enabled = pcall(is_enabled, other_mod)

            if ok_enabled and enabled == true then
                return other_mod
            end
        end
    end

    return nil
end

--- Returns Strikemap's compatibility API from `get_compatibility_api` or the `compatibility_api` field.
-- An API is only accepted when it provides `get_map_context`.
-- tab: strikemap_mod Strikemap mod object
-- treturn: ?tab compatibility API
local function _resolve_strikemap_api(strikemap_mod)
    local get_api = strikemap_mod.get_compatibility_api

    if type(get_api) == "function" then
        local ok, api = pcall(get_api, strikemap_mod)

        if ok and type(api) == "table" and type(api.get_map_context) == "function" then
            return api
        end
    end

    local api = strikemap_mod.compatibility_api

    if type(api) == "table" and type(api.get_map_context) == "function" then
        return api
    end

    return nil
end

--- Registers Radar as a Strikemap geometry consumer once.
-- tab: api compatibility API
function StrikemapCompatibility:_register_consumer(api)
    if self._consumer_registered then
        return
    end

    self._consumer_registered = true

    local register = api and api.register_consumer

    if type(register) == "function" then
        pcall(register, CONSUMER_ID)
    end
end

--- Unregisters Radar as a Strikemap consumer if it is registered.
function StrikemapCompatibility:_unregister_consumer()
    if not self._consumer_registered then
        return
    end

    self._consumer_registered = false

    local api = self._api
    local unregister = api and api.unregister_consumer

    if type(unregister) == "function" then
        pcall(unregister, CONSUMER_ID)
    end
end

--- Validates a Strikemap map context before any renderer touches it.
-- Checks the API version, a map identifier, the triangle array, stride and format (the
-- first and last record must be numbers), the spatial index and the optional bounds.
-- param: context value returned by `get_map_context`
-- treturn: ?tab the context when it is usable
-- treturn: ?string failure kind, `map_unavailable`, `incompatible_version` or `invalid_geometry`
-- treturn: ?string failure detail
local function _validate_map_context(context)
    if type(context) ~= "table" then
        return nil, "map_unavailable"
    end

    local api_version = tonumber(context.api_version)

    if api_version ~= SUPPORTED_STRIKEMAP_API_VERSION then
        return nil, "incompatible_version", tostring(context.api_version)
    end

    if context.map_id == nil and context.mission_name == nil then
        return nil, "invalid_geometry", "the Strikemap map context is missing a map identifier"
    end

    local triangles = context.triangles

    if type(triangles) ~= "table" then
        return nil, "invalid_geometry", "the Strikemap map context is missing triangle data"
    end

    local stride = context.triangle_stride

    if stride ~= nil and stride ~= TRIANGLE_STRIDE then
        return nil, "invalid_geometry",
            string_format("the Strikemap map context uses an unsupported triangle stride (%s)", tostring(stride))
    end

    local tri_count = tonumber(context.tri_count) or math_floor(#triangles / TRIANGLE_STRIDE)

    if tri_count <= 0 then
        return nil, "map_unavailable"
    end

    if type(triangles[1]) ~= "number" or type(triangles[tri_count * TRIANGLE_STRIDE]) ~= "number" then
        return nil, "invalid_geometry", "the Strikemap map context uses an unsupported triangle format"
    end

    local grid_cell = tonumber(context.grid_cell)

    if type(context.spatial_index) ~= "table" or not grid_cell or grid_cell <= 0 then
        return nil, "invalid_geometry", "the Strikemap map context is missing a usable spatial index"
    end

    local bounds = context.bounds

    if bounds ~= nil and type(bounds) ~= "table" then
        return nil, "invalid_geometry", "the Strikemap map context has invalid bounds"
    end

    return context
end

--- Validates a Strikemap vector context against the map revision and the known layer specs.
-- Checks each layer's stride and that its array is at least as long as its count, and that
-- every transition chain reference exists.
-- param: vector_context value returned by `get_vector_context`
-- param: map_revision revision of the validated map context, may be nil
-- treturn: ?tab the vector context when it is usable
-- treturn: ?string failure detail
-- treturn: ?tab record count per layer array field
local function _validate_vector_context(vector_context, map_revision)
    if type(vector_context) ~= "table" then
        return nil, "the Strikemap vector context is not a table"
    end

    local vector_revision = vector_context.revision

    if vector_revision ~= nil and map_revision ~= nil and vector_revision ~= map_revision then
        return nil, string_format("the Strikemap vector context revision (%s) does not match the map revision (%s)",
            tostring(vector_revision), tostring(map_revision))
    end

    local counts = {}

    for i = 1, #VECTOR_LAYER_SPECS do
        local spec = VECTOR_LAYER_SPECS[i]
        local array = vector_context[spec.array_field]
        local stride_value = vector_context[spec.stride_field]

        if stride_value ~= nil and tonumber(stride_value) ~= spec.stride then
            return nil, string_format("the Strikemap vector context uses an unsupported %s (%s)",
                spec.stride_field, tostring(stride_value))
        end

        local count = tonumber(vector_context[spec.count_field])

        if array == nil then
            if count ~= nil and count > 0 then
                return nil, string_format("the Strikemap vector context is missing the %s array", spec.array_field)
            end

            counts[spec.array_field] = 0
        else
            if type(array) ~= "table" then
                return nil, string_format("the Strikemap vector context %s array is not a table", spec.array_field)
            end

            count = count or math_floor(#array / spec.stride)

            if count < 0 then
                return nil, string_format("the Strikemap vector context reports a negative %s", spec.count_field)
            end

            count = math_floor(count)

            if count > 0 and type(array[count * spec.stride]) ~= "number" then
                return nil, string_format("the Strikemap vector context %s array is shorter than its %s",
                    spec.array_field, spec.count_field)
            end

            counts[spec.array_field] = count
        end
    end

    local chains = vector_context.chains

    if chains ~= nil and type(chains) ~= "table" then
        return nil, "the Strikemap vector context chains field is not a table"
    end

    local transition_chain = vector_context.transition_chain

    if transition_chain ~= nil then
        if type(transition_chain) ~= "table" then
            return nil, "the Strikemap vector context transition_chain field is not a table"
        end

        for i = 1, counts.transitions do
            local chain_id = transition_chain[i]

            if chain_id ~= nil and (type(chains) ~= "table" or chains[chain_id] == nil) then
                return nil, string_format(
                    "the Strikemap vector context transition_chain[%d] references a missing chain (%s)",
                    i, tostring(chain_id))
            end
        end
    end

    return vector_context, nil, counts
end

--- Disables vector details for one geometry revision after they failed to load or draw.
-- The map triangles keep drawing; vectors are retried when Strikemap publishes a new revision.
-- param: revision geometry revision the failure belongs to
-- string: detail failure reason for the log
function StrikemapCompatibility:_mark_vector_failed(revision, detail)
    self._vector_context = nil
    self._vector_counts = nil
    self._vector_failed_revision = revision
    mod:info(string_format("[Radar] Strikemap vector details disabled for this geometry revision: %s",
        tostring(detail)))
end

--- Fetches and validates the vector context for a freshly validated map context.
-- Skipped when the API has no vector support or vectors already failed for this revision.
-- tab: api compatibility API
-- tab: map_context validated map context
function StrikemapCompatibility:_refresh_vector_context(api, map_context)
    self._vector_context = nil
    self._vector_counts = nil

    local get_vector_context = api.get_vector_context

    if type(get_vector_context) ~= "function" then
        return
    end

    local revision = map_context.revision

    if self._vector_failed_revision == revision then
        return
    end

    local ok, vector_context = pcall(get_vector_context)

    if not ok then
        self:_mark_vector_failed(revision, tostring(vector_context))

        return
    end

    if vector_context == nil then
        return
    end

    local valid_vector_context, detail, counts = _validate_vector_context(vector_context, revision)

    if not valid_vector_context then
        self:_mark_vector_failed(revision, detail)

        return
    end

    self._vector_context = valid_vector_context
    self._vector_counts = counts
end

--- Resolves the API if needed, polls Strikemap's status and refetches the map context when it changed.
-- All API calls run through `pcall`. When the status reports the same geometry revision as
-- the cached context, only the next poll is scheduled. Every outcome sets the status and the
-- time of the next attempt or refresh.
-- number: now gameplay time
-- treturn: ?tab validated map context, or nil when none is usable
function StrikemapCompatibility:_refresh(now)
    local api = self._api

    if api == nil then
        local strikemap_mod = _resolve_strikemap_mod()

        if not strikemap_mod then
            self._context = nil
            self._next_attempt_t = now + RETRY_WAITING_INTERVAL
            self:_set_status("waiting", "strikemap_not_active")

            return nil
        end

        api = _resolve_strikemap_api(strikemap_mod)

        if api == nil then
            self._context = nil
            self:_set_status("incompatible",
                "the installed Strikemap version does not expose the compatibility API")

            return nil
        end

        local api_version = tonumber(api.api_version)

        if api_version ~= nil and api_version ~= SUPPORTED_STRIKEMAP_API_VERSION then
            self._context = nil
            self:_set_status("incompatible",
                string_format("unsupported Strikemap API version %s", tostring(api.api_version)))

            return nil
        end

        self._api = api
    end

    self:_register_consumer(api)

    if type(api.get_status) == "function" then
        local ok_status, status = pcall(api.get_status)

        if not ok_status then
            self._context = nil
            self:_set_status("error", tostring(status))

            return nil
        end

        if type(status) == "table" then
            if status.available == false then
                self._context = nil
                self._next_attempt_t = now + RETRY_MAP_UNAVAILABLE_INTERVAL
                self:_set_status("map_unavailable",
                    "the compatibility API is disabled in Strikemap's settings.")

                return nil
            end

            if status.map_loaded ~= true then
                self._context = nil

                local strikemap_status = status.status

                if strikemap_status == "loading" or strikemap_status == "not_in_mission" then
                    self._next_attempt_t = now + RETRY_WAITING_INTERVAL
                    self:_set_status("waiting", strikemap_status)
                else
                    self._next_attempt_t = now + RETRY_MAP_UNAVAILABLE_INTERVAL
                    self:_set_status("map_unavailable")
                end

                return nil
            end

            local revision = status.geometry_revision

            if self._context ~= nil and revision ~= nil and revision == self._context_revision then
                self._next_refresh_t = now + STATUS_POLL_INTERVAL

                return self._context
            end
        end
    end

    local ok_context, context = pcall(api.get_map_context)

    if not ok_context then
        self._context = nil
        self:_set_status("error", tostring(context))

        return nil
    end

    if context == nil then
        self._context = nil
        self._next_attempt_t = now + RETRY_MAP_UNAVAILABLE_INTERVAL
        self:_set_status("map_unavailable")

        return nil
    end

    local valid_context, failure, detail = _validate_map_context(context)

    if not valid_context then
        self._context = nil

        if failure == "map_unavailable" then
            self._next_attempt_t = now + RETRY_MAP_UNAVAILABLE_INTERVAL
            self:_set_status("map_unavailable")
        elseif failure == "incompatible_version" then
            self:_set_status("incompatible",
                string_format("unsupported Strikemap API version %s", tostring(detail)))
        else
            self:_set_status("error", tostring(detail))
        end

        return nil
    end

    self:_refresh_vector_context(api, valid_context)

    self._context = valid_context
    self._context_revision = valid_context.revision
    self._next_refresh_t = now
        + (valid_context.revision ~= nil and STATUS_POLL_INTERVAL or CONTEXT_REFRESH_INTERVAL)
    self:_set_status("active", tostring(valid_context.map_id or valid_context.mission_name))

    return valid_context
end

--- Returns the Strikemap map context for this frame, refreshing it when due.
-- Returns nil without touching Strikemap while the integration is disabled by setting, in a
-- sticky failure status or waiting for its retry interval.
-- ?number: t gameplay time
-- treturn: ?tab validated map context
function StrikemapCompatibility:get_map_context(t)
    if not self:is_integration_enabled() then
        if self._status ~= "disabled" then
            self:reset("disabled")
        end

        return nil
    end

    if STICKY_STATUSES[self._status] then
        return nil
    end

    local now = tonumber(t) or 0
    local context = self._context

    if context ~= nil then
        if now < self._next_refresh_t then
            return context
        end
    elseif now < self._next_attempt_t then
        return nil
    end

    return self:_refresh(now)
end

--- Returns everything the Strikemap geometry renderer needs for this frame.
-- ?number: t gameplay time
-- treturn: ?tab map context
-- treturn: ?tab vector context, nil when unsupported or failed for this revision
-- return: geometry revision of the map context, may be nil
-- treturn: ?tab record count per vector layer
function StrikemapCompatibility:get_geometry_contexts(t)
    local context = self:get_map_context(t)

    if context == nil then
        return nil, nil, nil, nil
    end

    return context, self._vector_context, self._context_revision, self._vector_counts
end

--- Returns the API version reported by the resolved Strikemap API, if any.
-- treturn: ?number
function StrikemapCompatibility:get_api_version()
    local api = self._api

    return api and tonumber(api.api_version) or nil
end

--- Drops the cached contexts and enters the sticky `error` status, for renderer failures.
-- param: err error value
function StrikemapCompatibility:mark_error(err)
    self._context = nil
    self._vector_context = nil
    self._vector_counts = nil
    self:_set_status("error", tostring(err))
end

--- Disables vector details for the current geometry revision after a vector draw error.
-- param: err error value
function StrikemapCompatibility:mark_vector_error(err)
    self:_mark_vector_failed(self._context_revision, tostring(err))
end

--- Drops the cached contexts and enters the sticky `incompatible` status.
-- param: reason reason for the log
function StrikemapCompatibility:mark_unsupported(reason)
    self._context = nil
    self._vector_context = nil
    self._vector_counts = nil
    self:_set_status("incompatible", tostring(reason))
end

--- Clears all cached contexts, retry timers and failure state, and resets the geometry renderer.
-- The consumer is unregistered when the integration ends up disabled.
-- ?string: status status to start from; `waiting` or `disabled` by setting when nil
function StrikemapCompatibility:reset(status)
    self._context = nil
    self._context_revision = nil
    self._vector_context = nil
    self._vector_counts = nil
    self._vector_failed_revision = false
    self._next_attempt_t = 0
    self._next_refresh_t = 0
    self._status = status or (self:is_integration_enabled() and "waiting" or "disabled")
    self._status_detail = nil

    if self._status == "disabled" then
        self:_unregister_consumer()
    end

    local reset_renderer = mod._strikemap_geometry_renderer_reset

    if reset_renderer then
        reset_renderer()
    end
end

--- Resets the Strikemap integration so it resolves Strikemap and its map again.
function mod:reset_strikemap_integration()
    StrikemapCompatibility:reset()
end

local previous_on_setting_changed = mod.on_setting_changed

--- DMF callback, chained after any previously installed handler.
-- Resets the integration when the map geometry source changes, to `waiting` when Strikemap
-- geometry is now wanted and to `disabled` otherwise.
-- string: setting_id changed setting
-- param: ... further DMF arguments, forwarded to the previous handler
mod.on_setting_changed = function(setting_id, ...)
    if previous_on_setting_changed then
        previous_on_setting_changed(setting_id, ...)
    end

    if setting_id == "map_geometry_source" then
        if StrikemapCompatibility:is_integration_enabled() then
            StrikemapCompatibility:reset()
        else
            StrikemapCompatibility:reset("disabled")
        end
    end
end

local previous_on_disabled = mod.on_disabled

--- DMF callback, chained after any previously installed handler; unregisters Radar as a Strikemap consumer.
-- param: ... DMF arguments, forwarded to the previous handler
mod.on_disabled = function(...)
    if previous_on_disabled then
        previous_on_disabled(...)
    end

    StrikemapCompatibility:_unregister_consumer()
end

-- Cached for the reload guard at the top of the file.
mod._strikemap_compatibility = StrikemapCompatibility

return StrikemapCompatibility
