--- Optional integration with the SafeRoute mod's route markers.
-- SafeRoute works out from the level seed which road the mission keeps at every branching path.
-- It publishes the result as ordinary world markers of type `SafeRoute_marker`, a SAFE ROUTE
-- marker on the kept road and a WRONG WAY marker on every other one. Radar is a consumer only;
-- it reads the world marker list it already has access to, classifies each main marker, copies
-- the world position out of the engine, and hands the result to the normal radar point pipeline.
--
-- SafeRoute's guide dots share the marker type and stand about every 2 m along its recorded
-- routes. They are left out, since dozens of them around every fork would fill the marker limit
-- with targets worth far less than the pickups and enemies they push off the radar.
--
-- Radar never creates or removes SafeRoute's markers, never reads its private state or route
-- tables and never duplicates its crossroad selection. With SafeRoute missing, disabled or
-- silent, the scan contributes no targets and the rest of Radar is untouched. The world marker
-- list is read on the existing droppable scan tick, and only on missions whose main path has
-- branching roads, the only missions SafeRoute marks; no HUD element is hooked.
--
-- Installer module, installed after the Respawn Rewind integration into Radar's shared runtime
-- environment (see `Radar.lua`). Contributes `_scan_safe_route_markers` and
-- `_reset_safe_route_state`. Relies on `_safe_world_markers_list`, `_copy_vector3` and
-- `_safe_gameplay_time` from `Radar_runtime_helpers.lua`, and on `_track_point` and
-- `_kind_enabled` from `Radar_tracking.lua`.
-- module: Radar_safe_route
-- author: LucLeto
return function(env)
    setfenv(1, env)

    local mod = mod
    local next = next
    local pcall = pcall
    local rawget = rawget
    local tostring = tostring
    local type = type

    -- ----------------------------------------------------------------------------
    -- Constants
    -- ----------------------------------------------------------------------------

    --- World marker type SafeRoute registers all of its markers under.
    local SAFE_ROUTE_MARKER_TYPE = "SafeRoute_marker"

    --- Name SafeRoute registers itself under with DMF.
    local SAFE_ROUTE_MOD_NAME = "SafeRoute"

    --- Seconds between attempts to resolve SafeRoute while it is not available.
    -- Without the mod there is nothing to read, so the scan skips the world marker request
    -- entirely and only pays a table lookup until the next attempt.
    local MOD_RESOLVE_RETRY_INTERVAL = 5

    --- Scan source and point id prefix of every SafeRoute point.
    local SAFE_ROUTE_SOURCE = "safe_route"
    local SAFE_ROUTE_POINT_ID_PREFIX = "safe_route:"

    --- Radar marker kinds of the main SAFE ROUTE and WRONG WAY markers.
    local SAFE_KIND = "saferoute_safe"
    local WRONG_KIND = "saferoute_wrong"

    --- Radar marker kind of each SafeRoute role.
    local KIND_BY_ROLE = {
        safe = SAFE_KIND,
        wrong = WRONG_KIND,
    }

    --- Role of each icon SafeRoute gives its markers, read from its own marker code.
    -- The labels cannot serve here, since SafeRoute localizes them.
    local ROLE_BY_ICON = {
        ["content/ui/materials/hud/interactions/icons/location"] = "safe",
        ["content/ui/materials/hud/interactions/icons/attention"] = "wrong",
    }

    --- Crossroad id and road id no crossroad can have, for asking the game's own crossroad lookup.
    local CROSSROAD_PROBE = {}

    -- ----------------------------------------------------------------------------
    -- Mutable runtime state
    -- ----------------------------------------------------------------------------

    --- Resolved SafeRoute mod and the time of the next resolve attempt.
    -- Stays nil while the mod is missing or switched off, which is retried, not cached forever.
    mod._safe_route_mod = nil
    mod._safe_route_next_resolve_t = 0

    --- Main path manager the branching road answer was read from, and that answer.
    -- The game builds one main path manager per mission, so the answer is read once per mission
    -- and every later scan only compares the manager.
    local _branching_roads_main_path = nil
    local _main_path_has_branching_roads = false

    -- ----------------------------------------------------------------------------
    -- Mod detection
    -- ----------------------------------------------------------------------------

    --- Finds the SafeRoute mod.
    -- A mod that reports itself disabled is skipped; one without `is_enabled` is accepted.
    -- treturn: ?tab SafeRoute mod, or nil when it is not installed or not enabled
    local function _resolve_safe_route_mod()
        local get_mod_fn = rawget(_G, "get_mod")

        if type(get_mod_fn) ~= "function" then
            return nil
        end

        local ok, other_mod = pcall(get_mod_fn, SAFE_ROUTE_MOD_NAME)

        if not ok or type(other_mod) ~= "table" then
            return nil
        end

        local is_enabled = other_mod.is_enabled

        if type(is_enabled) ~= "function" then
            return other_mod
        end

        local ok_enabled, enabled = pcall(is_enabled, other_mod)

        if ok_enabled and enabled == true then
            return other_mod
        end

        return nil
    end

    --- Returns whether SafeRoute is available, re-resolving it at most every few seconds.
    -- Resolution is lazy, so no load order is required, and a mod switched on in the menu is
    -- noticed on the next attempt rather than at the next mission.
    -- treturn: bool
    local function _is_safe_route_available()
        if mod._safe_route_mod ~= nil then
            return true
        end

        local now = _safe_gameplay_time() or 0

        if now < (mod._safe_route_next_resolve_t or 0) then
            return false
        end

        mod._safe_route_next_resolve_t = now + MOD_RESOLVE_RETRY_INTERVAL
        mod._safe_route_mod = _resolve_safe_route_mod()

        return mod._safe_route_mod ~= nil
    end

    -- ----------------------------------------------------------------------------
    -- Mission gate
    -- ----------------------------------------------------------------------------

    --- Returns whether a main path manager has branching roads, failing open when unsure.
    -- The game picks the road of every crossroad as it builds the manager, on clients too, and
    -- keeps the picks in `_chosen_crossroads` only when the main path has crossroads at all, so a
    -- table there answers directly. An absent field means either no forks or a game update that
    -- keeps the picks elsewhere. The game's own `is_crossroad_segment_available` tells the two
    -- apart, since it reads the picks wherever the game keeps them and, asked about a crossroad
    -- that does not exist, answers nil only when there are no picks at all. Anything Radar does
    -- not recognise counts as branching, so a change in the game costs the scan a little time
    -- but never costs the markers.
    -- tab: main_path main path manager
    -- treturn: bool
    local function _main_path_has_crossroads(main_path)
        local chosen_crossroads = rawget(main_path, "_chosen_crossroads")

        if type(chosen_crossroads) == "table" then
            return next(chosen_crossroads) ~= nil
        end

        if chosen_crossroads ~= nil then
            return true
        end

        local is_crossroad_segment_available = main_path.is_crossroad_segment_available

        if type(is_crossroad_segment_available) ~= "function" then
            return true
        end

        local ok, available = pcall(is_crossroad_segment_available, main_path, CROSSROAD_PROBE, CROSSROAD_PROBE)

        return not ok or available ~= nil
    end

    --- Returns whether the current mission's main path has branching roads.
    -- SafeRoute marks nothing on any other mission. The answer is read once per main path
    -- manager, so once per mission, and covers Spillway and any other mission with forks alike.
    -- While no manager exists yet nothing is cached, so a scan that runs before the mission is
    -- set up cannot switch the integration off for the whole mission.
    -- treturn: bool
    local function _mission_has_branching_roads()
        local managers = Managers
        local state_managers = managers and managers.state
        local main_path = state_managers and state_managers.main_path

        if type(main_path) ~= "table" then
            return false
        end

        if main_path ~= _branching_roads_main_path then
            _branching_roads_main_path = main_path
            _main_path_has_branching_roads = _main_path_has_crossroads(main_path)
        end

        return _main_path_has_branching_roads
    end

    -- ----------------------------------------------------------------------------
    -- Marker classification
    -- ----------------------------------------------------------------------------

    --- Returns whether a marker is one of SafeRoute's guide dots.
    -- An explicit `data.safe_route_guide` decides where SafeRoute provides one. SafeRoute 1.2.0
    -- sets no such field, and its dots are the only markers that hide behind walls, so line of
    -- sight checking is the backwards compatible fallback.
    -- tab: data marker data
    -- treturn: bool
    local function _is_guide_dot(data)
        local guide = data.safe_route_guide

        if guide == true or guide == false then
            return guide
        end

        return data.check_line_of_sight == true
    end

    --- Classifies one SafeRoute world marker into a Radar marker kind.
    -- The preferred contract is `data.safe_route_role`; a later SafeRoute that sets it needs no
    -- change here. The icon stays as the fallback for SafeRoute 1.2.0. A guide dot or an
    -- unrecognised marker returns nil and is left alone.
    -- tab: marker world marker record
    -- treturn: ?string kind
    local function _safe_route_marker_kind(marker)
        local data = marker.data

        if type(data) ~= "table" or _is_guide_dot(data) then
            return nil
        end

        local role = data.safe_route_role
        local kind = role ~= nil and KIND_BY_ROLE[role] or nil

        if kind ~= nil then
            return kind
        end

        role = ROLE_BY_ICON[data.icon]

        return role ~= nil and KIND_BY_ROLE[role] or nil
    end

    -- ----------------------------------------------------------------------------
    -- Marker import
    -- ----------------------------------------------------------------------------

    --- Returns a position marker's world position as a plain table Radar owns.
    -- The marker's `Vector3Box` is unboxed and the engine vector copied straight away, so it is
    -- never kept across frames.
    -- tab: marker world marker record
    -- treturn: ?tab `{ x, y, z }`
    local function _safe_route_marker_position(marker)
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

    --- Reads SafeRoute's world markers and tracks each main route marker as a radar point.
    -- Runs on the droppable scan tick, which rebuilds every tracked point, so a marker SafeRoute
    -- has removed simply stops being tracked. Skipped entirely while SafeRoute is unavailable, on
    -- a mission without branching roads, or while both SafeRoute kinds are switched off. The two
    -- cached checks come first, so a mission without forks costs a comparison or two per tick.
    function _scan_safe_route_markers()
        if not _is_safe_route_available() or not _mission_has_branching_roads() then
            return
        end

        local safe_enabled = _kind_enabled(SAFE_KIND)
        local wrong_enabled = _kind_enabled(WRONG_KIND)

        if not (safe_enabled or wrong_enabled) then
            return
        end

        local markers = _safe_world_markers_list()

        if not markers then
            return
        end

        for i = 1, #markers do
            local marker = markers[i]

            if marker ~= nil and marker.type == SAFE_ROUTE_MARKER_TYPE then
                local kind = _safe_route_marker_kind(marker)

                if (kind == SAFE_KIND and safe_enabled) or (kind == WRONG_KIND and wrong_enabled) then
                    local position = _safe_route_marker_position(marker)

                    if position ~= nil then
                        _track_point(SAFE_ROUTE_POINT_ID_PREFIX .. tostring(marker.id), kind, position,
                            SAFE_ROUTE_SOURCE)
                    end
                end
            end
        end
    end

    --- Clears the resolved mod and the branching road answer, so the next mission checks both again.
    -- Also drops the reference to the last mission's main path manager.
    function _reset_safe_route_state()
        mod._safe_route_mod = nil
        mod._safe_route_next_resolve_t = 0
        _branching_roads_main_path = nil
        _main_path_has_branching_roads = false
    end
end
