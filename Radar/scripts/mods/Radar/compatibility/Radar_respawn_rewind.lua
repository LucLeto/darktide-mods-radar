--- Optional integration with the Respawn Rewind mod's respawn world markers.
-- Respawn Rewind decides which respawn beacon is active, where the run-back threshold lies and,
-- in its practice mode, what the whole respawn layout looks like. It publishes all of that as
-- ordinary world markers of type `respawn_rewind`. Radar is a consumer only: it reads the world
-- marker list it already has access to, classifies each marker into one of four roles, copies the
-- world position out of the engine, and hands the result to the normal radar point pipeline.
--
-- Radar never enables Respawn Rewind settings, never creates its markers, never runs its private
-- beacon code and never duplicates its path selection. With Respawn Rewind missing, disabled or
-- silent, the scan contributes no targets and the rest of Radar is untouched. The world marker
-- list is read on the existing droppable scan tick; no HUD element is hooked.
--
-- Installer module, installed after the feature modules into Radar's shared runtime environment
-- (see `Radar.lua`). Contributes `_scan_respawn_rewind_markers` and
-- `_reset_respawn_rewind_state`. Relies on `_safe_world_markers_list`, `_safe_unit_position`,
-- `_copy_vector3` and `_safe_gameplay_time` from `Radar_runtime_helpers.lua`, on `_track_point`
-- and `_kind_enabled` from `Radar_tracking.lua`, and on `RESPAWN_MARKER_KINDS` from
-- `Radar_enemy_definitions.lua`.
-- module: Radar_respawn_rewind
-- author: LucLeto
return function(env)
    setfenv(1, env)

    local mod = mod
    local pairs = pairs
    local pcall = pcall
    local rawget = rawget
    local tonumber = tonumber
    local tostring = tostring
    local type = type
    local string_format = string.format
    local string_match = string.match

    -- ----------------------------------------------------------------------------
    -- Constants
    -- ----------------------------------------------------------------------------

    --- World marker type Respawn Rewind registers all of its markers under.
    local RESPAWN_REWIND_MARKER_TYPE = "respawn_rewind"

    --- Mod names Respawn Rewind may be registered under with DMF, tried in order.
    local RESPAWN_REWIND_MOD_NAME_CANDIDATES = {
        "RespawnRewind",
        "respawn_rewind",
        "Respawn Rewind",
    }

    --- Seconds between attempts to resolve Respawn Rewind while it is not available.
    -- Without the mod there is nothing to read, so the scan skips the world marker request
    -- entirely and only pays a table lookup until the next attempt.
    local MOD_RESOLVE_RETRY_INTERVAL = 5

    --- Radar marker kind of each respawn role.
    local KIND_BY_ROLE = {
        active = "respawn_active",
        runback = "respawn_runback",
        practice_beacon = "respawn_practice_beacon",
        practice_line = "respawn_practice_line",
    }

    --- Roles Respawn Rewind publishes as unit markers; the others are position markers.
    -- The shape is half of the classification, since a role can never change which of the two
    -- kinds of world marker it is added as.
    local ROLE_NEEDS_UNIT = {
        active = true,
        practice_beacon = true,
    }

    --- Roles that only exist while Respawn Rewind's practice mode is on.
    local PRACTICE_ROLES = {
        practice_beacon = true,
        practice_line = true,
    }

    --- Icon colours Respawn Rewind gives each of its markers, keyed by their red, green and blue.
    -- Read from its own marker module. Radar never draws with them; they are the only signal
    -- that separates a numberless practice beacon from the active respawn, whose labels are both
    -- exactly `Respawn` once Respawn Rewind's distance text is switched off.
    local ROLE_BY_COLOUR_KEY = {
        ["120,200,255"] = "active",
        ["120,220,120"] = "runback",
        ["130,170,200"] = "practice_beacon",
        ["175,175,175"] = "practice_line",
    }

    --- Run-back label prefixes and whether each one carries the team's offset.
    -- `Run back` and `Stay behind` report how far the team stands from the threshold, which is
    -- not a distance to the marker. `Hold back` is Respawn Rewind's fallback where no offset
    -- exists, and its number is a plain distance, so no offset is taken from it.
    local RUNBACK_STATUS_PATTERNS = {
        { pattern = "^Run back", status = "run_back", has_offset = true },
        { pattern = "^Stay behind", status = "stay_behind", has_offset = true },
        { pattern = "^Hold back", status = "hold_back", has_offset = false },
    }

    --- Offset in a run-back label, the number after the separator, such as `29m` or `-12m`.
    local RUNBACK_OFFSET_PATTERN = "|%s*(%-?%d+%a*)%s*$"

    -- ----------------------------------------------------------------------------
    -- Mutable runtime state
    -- ----------------------------------------------------------------------------

    --- Resolved Respawn Rewind mod and the time of the next resolve attempt.
    -- Stays nil while the mod is missing or switched off, which is retried, not cached forever.
    mod._respawn_rewind_mod = nil
    mod._respawn_rewind_next_resolve_t = 0

    --- Meta table reused per point id, so a scan allocates nothing while the markers hold still.
    local _scratch_respawn_meta_by_id = {}

    --- Enablement of each role, rewritten at the start of every scan instead of allocated.
    local _scratch_respawn_role_enabled = {}

    -- ----------------------------------------------------------------------------
    -- Mod detection
    -- ----------------------------------------------------------------------------

    --- Finds the Respawn Rewind mod under any of its known names.
    -- A mod that reports itself disabled is skipped; one without `is_enabled` is accepted.
    -- treturn: ?tab Respawn Rewind mod, or nil when it is not installed or not enabled
    local function _resolve_respawn_rewind_mod()
        local get_mod_fn = rawget(_G, "get_mod")

        if type(get_mod_fn) ~= "function" then
            return nil
        end

        for i = 1, #RESPAWN_REWIND_MOD_NAME_CANDIDATES do
            local ok, other_mod = pcall(get_mod_fn, RESPAWN_REWIND_MOD_NAME_CANDIDATES[i])

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

    --- Returns whether Respawn Rewind is available, re-resolving it at most every few seconds.
    -- Resolution is lazy, so no load order is required, and a mod switched off in the menu is
    -- noticed on the next attempt rather than at the next mission.
    -- treturn: bool
    local function _is_respawn_rewind_available()
        if mod._respawn_rewind_mod ~= nil then
            return true
        end

        local now = _safe_gameplay_time() or 0

        if now < (mod._respawn_rewind_next_resolve_t or 0) then
            return false
        end

        mod._respawn_rewind_next_resolve_t = now + MOD_RESOLVE_RETRY_INTERVAL
        mod._respawn_rewind_mod = _resolve_respawn_rewind_mod()

        return mod._respawn_rewind_mod ~= nil
    end

    -- ----------------------------------------------------------------------------
    -- Marker classification
    -- ----------------------------------------------------------------------------

    --- Returns the role a marker's own metadata names, where Respawn Rewind provides one.
    -- The preferred contract: a later Respawn Rewind that sets `data.role` needs no change here,
    -- and the colour and label rules below stay only as the backwards compatible fallback.
    -- ?tab: data marker data
    -- treturn: ?string role
    local function _role_from_data_role(data)
        local role = data.role

        if type(role) ~= "string" or KIND_BY_ROLE[role] == nil then
            return nil
        end

        return role
    end

    --- Returns the role Respawn Rewind's icon colour names, where it agrees with the marker shape.
    -- tab: data marker data
    -- bool: has_unit whether the marker is anchored to a unit
    -- treturn: ?string role
    local function _role_from_colour(data, has_unit)
        local colour = data.color

        if type(colour) ~= "table" then
            return nil
        end

        local red = tonumber(colour[2])
        local green = tonumber(colour[3])
        local blue = tonumber(colour[4])

        if red == nil or green == nil or blue == nil then
            return nil
        end

        local role = ROLE_BY_COLOUR_KEY[string_format("%d,%d,%d", red, green, blue)]

        if role == nil or (ROLE_NEEDS_UNIT[role] == true) ~= has_unit then
            return nil
        end

        return role
    end

    --- Returns the role a marker's label names, where it agrees with the marker shape.
    -- The labels are Respawn Rewind's own, untranslated strings: `Respawn`, `Respawn | 29m`,
    -- `Respawn 3`, `Run back`, `Stay behind`, `Hold back`, `3 ends` and `Line`.
    -- param: text marker label
    -- bool: has_unit whether the marker is anchored to a unit
    -- treturn: ?string role
    local function _role_from_label(text, has_unit)
        if type(text) ~= "string" then
            return nil
        end

        if has_unit then
            if string_match(text, "^Respawn %d") then
                return "practice_beacon"
            end

            if text == "Respawn" or string_match(text, "^Respawn |") then
                return "active"
            end

            return nil
        end

        for i = 1, #RUNBACK_STATUS_PATTERNS do
            if string_match(text, RUNBACK_STATUS_PATTERNS[i].pattern) then
                return "runback"
            end
        end

        if text == "Line" or string_match(text, "^%d+ ends") then
            return "practice_line"
        end

        return nil
    end

    --- Classifies one Respawn Rewind world marker.
    -- Kept here, away from Radar's generic tracking, so a Respawn Rewind change never reaches
    -- further than this file. An unrecognised marker returns nil and is left alone: drawing a
    -- whole practice set as high priority active respawns would be worse than drawing nothing.
    -- tab: marker world marker record
    -- bool: has_unit whether the marker is anchored to a unit
    -- treturn: ?string role
    local function _respawn_marker_role(marker, has_unit)
        local data = marker.data

        if type(data) ~= "table" then
            return nil
        end

        return _role_from_data_role(data)
            or _role_from_colour(data, has_unit)
            or _role_from_label(data.text, has_unit)
    end

    -- ----------------------------------------------------------------------------
    -- Marker import
    -- ----------------------------------------------------------------------------

    --- Returns a marker's world position as a plain table Radar owns.
    -- A unit marker is read through its unit, a position marker through its `Vector3Box`. The
    -- unboxed engine vector is copied straight away and never kept across frames.
    -- tab: marker world marker record
    -- param: unit marker unit, nil for a position marker
    -- treturn: ?tab `{ x, y, z }`
    local function _respawn_marker_position(marker, unit)
        if unit ~= nil then
            return _safe_unit_position(unit)
        end

        local world_position = marker.world_position

        if world_position == nil then
            return nil
        end

        local unbox = world_position.unbox

        if type(unbox) ~= "function" then
            return nil
        end

        local ok, position = pcall(unbox, world_position)

        if not ok then
            return nil
        end

        return _copy_vector3(position)
    end

    --- Returns the reused meta table of a point id, emptied of the fields this module writes.
    -- string: id point id
    -- treturn: tab meta table
    local function _respawn_meta(id)
        local meta = _scratch_respawn_meta_by_id[id]

        if meta == nil then
            meta = {}
            _scratch_respawn_meta_by_id[id] = meta

            return meta
        end

        meta.respawn_source_text = nil
        meta.respawn_status = nil
        meta.respawn_offset_text = nil

        return meta
    end

    --- Records Respawn Rewind's run-back label on a point's meta.
    -- `Run back | 29m` and `Stay behind | -12m` report the team's offset from the threshold, not
    -- a distance to the marker, so the offset is kept apart from every Radar distance. The
    -- `Hold back` fallback carries a plain distance instead and contributes no offset.
    -- tab: meta meta table of the point
    -- param: text marker label
    local function _apply_runback_status(meta, text)
        if type(text) ~= "string" then
            return
        end

        meta.respawn_source_text = text

        for i = 1, #RUNBACK_STATUS_PATTERNS do
            local status = RUNBACK_STATUS_PATTERNS[i]

            if string_match(text, status.pattern) then
                meta.respawn_status = status.status

                if status.has_offset then
                    meta.respawn_offset_text = string_match(text, RUNBACK_OFFSET_PATTERN)
                end

                return
            end
        end
    end

    --- Returns whether the practice markers may be tracked this scan.
    -- The practice set covers the whole map, which is what the overview is for and what the
    -- normal radar has no room for. Decided here rather than in the shared target filter, so a
    -- hot path every marker passes through stays untouched.
    -- treturn: bool
    local function _respawn_practice_allowed()
        if mod:get("respawn_practice_overview_only") ~= true then
            return true
        end

        local is_overview_mode_active = mod.is_overview_mode_active

        return is_overview_mode_active ~= nil and is_overview_mode_active(mod) == true
    end

    --- Reads Respawn Rewind's world markers and tracks each recognised one as a radar point.
    -- Runs on the droppable scan tick, which rebuilds every tracked point, so a marker Respawn
    -- Rewind has removed simply stops being tracked. Skipped entirely while none of the respawn
    -- kinds is switched on or while Respawn Rewind is unavailable.
    function _scan_respawn_rewind_markers()
        local role_enabled = _scratch_respawn_role_enabled
        local any_enabled = false

        for role, kind in pairs(KIND_BY_ROLE) do
            local enabled = _kind_enabled(kind)

            role_enabled[role] = enabled
            any_enabled = any_enabled or enabled
        end

        if not any_enabled or not _is_respawn_rewind_available() then
            return
        end

        local markers = _safe_world_markers_list()

        if not markers then
            return
        end

        local practice_allowed = nil

        for i = 1, #markers do
            local marker = markers[i]

            if marker ~= nil and marker.type == RESPAWN_REWIND_MARKER_TYPE then
                local unit = marker.unit
                local role = _respawn_marker_role(marker, unit ~= nil)

                if role ~= nil and role_enabled[role] then
                    if PRACTICE_ROLES[role] and practice_allowed == nil then
                        practice_allowed = _respawn_practice_allowed()
                    end

                    if not PRACTICE_ROLES[role] or practice_allowed then
                        local position = _respawn_marker_position(marker, unit)

                        if position ~= nil then
                            local id = string_format("respawn_rewind:%s:%s", role, tostring(marker.id))
                            local meta = _respawn_meta(id)

                            if role == "runback" then
                                _apply_runback_status(meta, marker.data.text)
                            else
                                meta.respawn_source_text = marker.data.text
                            end

                            _track_point(id, KIND_BY_ROLE[role], position, "respawn_rewind", meta)
                        end
                    end
                end
            end
        end
    end

    --- Clears the resolved mod and the meta cache, so the next mission resolves Respawn Rewind again.
    function _reset_respawn_rewind_state()
        mod._respawn_rewind_mod = nil
        mod._respawn_rewind_next_resolve_t = 0
        _scratch_respawn_meta_by_id = {}
    end
end
