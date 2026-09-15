return function(env)
    setfenv(1, env)

    local mod = mod
    local pcall = pcall
    local pairs = pairs
    local tonumber = tonumber
    local tostring = tostring
    local type = type
    local rawget = rawget
    local string_find = string.find
    local string_format = string.format

    local table_clear = table.clear or function(t)
        for k in pairs(t) do
            t[k] = nil
        end
    end

    -- ----------------------------------------------------------------------------
    -- Constants
    -- ----------------------------------------------------------------------------

    -- Mission objective interactables come from the game's own objective
    -- extension systems, not from the HUD world marker list. The marker list was
    -- tried first and rejected: it only contains what the HUD is drawing right
    -- now, so objectives appeared late or not at all.
    --
    -- MissionObjectiveTargetExtension carries `_objective_name`, which ties each
    -- unit to a named objective, and MissionObjectiveSystem reports which
    -- objectives are active. That pairing is what keeps the ~105 objective units
    -- in a level down to the handful that currently matter.
    local MISSION_OBJECTIVE_TARGET_SYSTEM = "mission_objective_target_system"
    local MISSION_OBJECTIVE_ZONE_SYSTEM = "mission_objective_zone_system"

    -- Per-target scanned state lives here: each scannable unit carries _is_active,
    -- which the zone clears as the target is scanned. This is the only per-target
    -- completion signal that exists; the interactee reports active=true for the
    -- whole mission and the zone selection array carries no flags.
    local MISSION_OBJECTIVE_SCANNABLE_SYSTEM = "mission_objective_zone_scannable_system"
    local MISSION_OBJECTIVE_SOURCE = "mission_objective_system"

    -- Systems whose every unit is objective-specific by definition, so they need
    -- no active-objective confirmation. Counts are small (3 decoders, 16 zones in
    -- a Hab Dreyko run), which is why they can be shown wholesale.
    local MISSION_OBJECTIVE_DEDICATED_SOURCES = {
        { system = "decoder_device_system", kind = "mission_objective_hacking" },
        { system = "scanning_event_system", kind = "mission_objective_scanner" },
    }
    local MISSION_OBJECTIVE_DEDICATED_SOURCE_COUNT = #MISSION_OBJECTIVE_DEDICATED_SOURCES
    local MISSION_OBJECTIVE_MARKER_KINDS = {
        mission_objective_scanner = true,
        mission_objective_growth = true,
        mission_objective_destroy = true,
        mission_objective_hacking = true,
        mission_objective_servo_skull = true,
        mission_objective_other = true,
    }

    -- Interaction types that name the device directly. `scanning` and
    -- `servo_skull_activator` are both confirmed from live mission logs.
    local MISSION_OBJECTIVE_KIND_BY_INTERACTION_TYPE = {
        servo_skull_activator = "mission_objective_servo_skull",
        servo_skull = "mission_objective_servo_skull",
        decoder_device = "mission_objective_hacking",
        decoding = "mission_objective_hacking",
    }
    local MISSION_OBJECTIVE_MINIGAME_SYSTEM = "minigame_system"
    local MISSION_OBJECTIVE_MINIGAME_COMPLETE_STATE = "complete"
    local MISSION_OBJECTIVE_MINIGAME_GAMEPLAY_STATE = "gameplay"
    local MISSION_OBJECTIVE_MINIGAME_WAITING = "waiting"
    local MISSION_OBJECTIVE_MINIGAME_ACTIVE = "active"

    -- Interaction types owned exclusively by a more specific pass. A scan target
    -- is only ever a scanner marker while its zone selects it; once scanned it
    -- must disappear rather than fall through to the generic category. Luggable
    -- sockets have had their own marker kind since long before this scan, and a
    -- second marker on the same socket is pure duplication.
    local MISSION_OBJECTIVE_EXCLUSIVE_INTERACTION_TYPES = {
        scanning = true,
        luggable_socket = true,
    }
    local OBJECTIVE_MARKER_SETTLE_SECONDS = 2

    -- ----------------------------------------------------------------------------
    -- Mutable runtime state
    -- ----------------------------------------------------------------------------

    -- Read once per scan from the debug setting; every debug line in this
    -- module keys off it.
    local _objective_debug_logging = false

    -- Objective units that already classify as something else keep that kind, so
    -- the objective scan never relabels a luggable or its socket.
    local _mission_objective_kind_by_unit = {}
    local _scratch_mission_objective_kind_enabled = {}
    local _scratch_active_objective_names = {}
    local _scratch_seen_mission_objective_units = {}
    local _scratch_mission_objective_zone_units = {}

    -- Scan targets and similar objective steps never report themselves used;
    -- they simply stop being active once completed. Mirrors the Martyr's Skull
    -- fallback lifecycle: a unit observed active and later inactive is finished,
    -- while one that was never seen active is treated as still upcoming.
    local _mission_objective_lifecycle_by_unit = {}

    -- A hacking device keeps its interactee active and unused for the whole
    -- mission, so the puzzle's own state is the only thing that says it is done.
    -- `_active` is not that signal: it only means a player currently has the
    -- puzzle open, so hiding on it made markers disappear while idle and appear
    -- while somebody was already solving them.
    -- Objectives whose steps are daemonic growth. The objective name differs on
    -- every mission that runs the event -- `..._corruptor_event` on Silo
    -- Cluster, `..._demolition_first/a/b/final` on Propaganda,
    -- `..._demo_floor_one/two` on Rise -- so a name list only ever covered the
    -- missions written into it. What does identify one is the objective's own
    -- type: all nine growths logged, on four missions, are `demolition`
    -- objectives, and across 23 logs nothing else is. The targets'
    -- `_ui_target_type=demolition` is not the same thing: that is only the
    -- game's marker style for "destroy this", and core_research's ice, cm_raid's
    -- filtration tanks, km_heresy's Stimm tanks and op_train's cogitators carry
    -- it too, under `goal` and `collect` objectives.
    --
    -- Remembered per objective for the rest of the mission once seen. Only the
    -- icon, the tentacle search and the helper-target exception depend on this:
    -- the marker is claimed, coloured and retired exactly as any other step.
    local _growth_objective_by_name = {}

    -- Which of the two live states a running puzzle is in, so the marker can say
    -- whether it still needs somebody or already has one. A device that has not
    -- been started gets no state at all and keeps its category's colour, which
    -- is what the game itself shows before the puzzle is placed.
    local _minigame_state_by_unit = {}

    -- One meta table per unit, reused across scans: the state changes, the table
    -- does not, so a device being solved does not allocate on every pass.
    local _minigame_meta_by_unit = {}

    -- Declared with the other per-scan marker state rather than beside the
    -- objective maps that fill it: the meta builder above needs it, and a local
    -- is invisible before its declaration.
    local _scratch_growth_objective_units = {}

    -- Targets any other objective marks for destruction: ice on machinery,
    -- tanks, cogitators. Their own kind, so they read neither as a growth nor as
    -- a switch to press.
    local _scratch_destroy_objective_units = {}

    -- Bare objective steps -- the train controls destroyed to stop the train --
    -- carry no completion state anywhere: not an interactee, no health, in no
    -- system at all, and their own target extension never changes a field. The
    -- game's own world marker is the only thing that goes away when one is
    -- finished, so it stands in for the signal the unit does not have.
    --
    -- Declared here with the rest of the per-scan marker state rather than
    -- beside the pass that fills it: the puzzle state below is read from it and
    -- runs earlier in the frame, and a local is invisible before its
    -- declaration.
    local _scratch_world_marker_units = {}
    local _world_marker_units_available = false

    -- Units the game is currently pointing at through something other than its
    -- own world marker list. Every objective system answers "is the HUD showing
    -- this right now" in its own way -- a scan zone by its selection, a growth by
    -- its corruptor's marker -- so each pass writes what it knows here and the
    -- range decision reads one set. Declared early: the passes that fill it run
    -- well before the accessor that reads it.
    local _scratch_objective_range_exempt = {}

    -- Whether an objective is one that mixes real steps with position hints.
    -- A luggable objective holds the cells and their sockets, which you can act
    -- on, alongside spawn points and waypoints, which you cannot -- so its bare
    -- units are hints. An objective made of nothing but bare units is different:
    -- there the bare units are the step, as with the train controls you destroy
    -- to stop the train, and filtering them would leave the objective unmarked.
    --
    -- Decided per objective rather than per pass, because missions run more than
    -- one at a time -- the train runs "stop the train" and "defuse the bombs"
    -- together.
    local _scratch_objective_has_actionable = {}
    local _scratch_objective_actionable_by_unit = {}

    -- `_add_marker_on_objective_start` is the level's own statement that it will
    -- mark this unit when the objective begins. Chasm Logistratum files nine
    -- possible cargo containers and the one that actually holds the cargo under
    -- one objective, identical in every other field, and only the real one has
    -- it set. Read per objective: when none of an objective's units claims a
    -- start marker the flag says nothing, and nothing is hidden.
    local _scratch_objective_has_start_marker = {}
    local _scratch_start_marker_by_unit = {}

    -- Objective-bound units whose objective is not live. The system pass already
    -- skips them, but the interactee pass reaches the same units by interaction
    -- type alone and used to mark them whatever the objective was doing, which
    -- left an unused hacking device drawn for the rest of the mission once its
    -- event had finished.
    local _scratch_inactive_objective_units = {}

    -- Latched for the mission rather than rebuilt each scan. "No unit of this
    -- objective has a marker" is ambiguous: it means either that the list does
    -- not describe this objective, or that every one of its units is finished.
    -- Rebuilt per scan it read the second case as the first, so the last unit's
    -- marker going away switched the filter off instead of retiring the marker.
    -- Once an objective has been seen in the list it stays trusted.
    local _objective_world_marker_seen = {}

    -- When an objective first went live. The game does not assign its markers in
    -- the same frame, so for a moment no unit of a new objective has one, which
    -- is indistinguishable from an objective the marker list never describes.
    -- Waiting this long before falling back to "show everything" keeps every
    -- candidate of a just-started event from flashing up at once, while still
    -- showing the steps of an objective the list genuinely says nothing about.
    local _objective_first_active_t = {}

    -- Containers hiding a luggable objective's items. lm_rails' cargo and
    -- lm_scavenge's samples are filed under their objective together with a
    -- whole bank of identical lockers -- sixty-one on lm_scavenge -- and nothing
    -- on a locker says which of them hold anything: one prefab, the same
    -- fields, and the game marks none of them. The luggable says so itself. It
    -- exists inside its closed locker from the moment the objective starts,
    -- tracked like any other, 0.43 m to the side of the locker's origin and
    -- 1.3 m above it, while the nearest other locker stands 2 m or more away.
    --
    -- Only containers of a prefab found holding a luggable are ever dropped, so
    -- the objective's other steps -- lm_rails files two valves under the same
    -- objective -- and every objective where nothing turns up inside anything
    -- are left exactly as they were.
    local LUGGABLE_HOLDER = {
        -- Sideways, squared: a metre, halfway to the nearest other locker.
        reach_squared = 1,
        -- Up or down: the luggable rests above the locker's origin.
        height = 3,
        active = false,
        objectives = {},
        count = 0,
        units = {},
        x = {},
        y = {},
        z = {},
        -- What holds a luggable, refilled every scan.
        holds = {},
        -- Each luggable still shut inside one, and the container it is in.
        inside = {},
        -- Per objective, the prefabs found holding one of its luggables. Kept for
        -- the mission rather than refilled: once the last luggable is out of its
        -- container nothing holds anything, and the empty ones must stay empty.
        container_prefabs = {},
        -- Per unit, read once; `false` when the engine cannot say.
        prefab_of = {},
        -- Per kind, whether it is a luggable rather than a socket.
        luggable_kind = {},
        -- Where each luggable was first seen, and how far from there it may be
        -- and still count as never moved: 0.3 m, squared.
        origin = {},
        still_squared = 0.09,
        -- Per objective, the kind of luggable it is about, and per socket, its
        -- objective. Kept for the mission: the last luggable put in a socket
        -- leaves nothing to read, and the sockets must not change category then.
        cargo = {},
        socket_objective = {},
        -- The mission cargo that goes into the mission's own machinery rather
        -- than a power socket. Its sockets are drawn as the objective step they
        -- are. Power cells are not in it, and keep the power socket.
        objective_cargo = {
            luggable_vacuum_capsule = true,
            luggable_special_issue_ammo = true,
            luggable_cryonic_rod = true,
            luggable_moebian_pox_zetaphyte_13_sample = true,
            luggable_prismata_crystal_repository = true,
        },
    }

    -- A growth tentacle carries three small destructible eyes, and they are the
    -- only part of the event a player can act on: the corruptor the objective
    -- marks is protected until its tentacles are cleared. Nothing names them.
    -- They belong to no objective system, their unit names are hashed, and the
    -- game draws its three yellow markers on them through a HUD element that
    -- never reaches `request_world_markers_list`, so none of the routes every
    -- other objective step uses can find them.
    --
    -- What they do have is a shape. The three eyes of a tentacle are one prefab:
    -- across eight tentacles of a single run their pairwise distances measured
    -- 0.328, 0.347 and 0.407 metres every time, to the millimetre, while the
    -- level's own breakables around the event each stood alone with no other
    -- destructible within 20 metres. A destructible with two more inside half a
    -- metre is a tentacle, and in the data nothing else in the level is.
    local GROWTH_EYE = {
        -- Only a bound on the work. The level's own breakables sit well inside
        -- it -- the nearest was closer than any tentacle -- and are rejected by
        -- the shape rather than by this.
        range_squared = 1600,
        -- Comfortably above the prefab's widest pair at 0.407 m and far below
        -- the spacing of anything else observed near an event.
        link_squared = 0.25,
        cluster_size = 3,
        -- Bounds the pairwise pass, which is quadratic in what the range test
        -- lets through. Nine live eyes and a handful of breakables is what a
        -- tentacle stage actually produces.
        candidate_limit = 64,
        anchor_x = {},
        anchor_y = {},
        anchor_z = {},
        units = {},
        x = {},
        y = {},
        z = {},
        -- Indices of a candidate cluster while it is being matched.
        found = {},
        -- A tentacle survives its own eyes leaving the destructible system, so
        -- which units made it up is remembered rather than re-derived. All of
        -- this lives for the mission and is bounded by the event's spawn points:
        -- nine tentacles across a run, three units each.
        group_of = {},
        member_units = {},
        member_group = {},
        member_count = 0,
        group_next = 0,
        group_standing = {},
        group_carrier = {},
        -- Each candidate's prefab. `false` records that the engine could not
        -- say, so it is not asked again.
        prefab_of = {},
        -- Each anchor's reach, squared: an event's targets reach its tentacles
        -- at `range_squared`, a riddle's position at `riddle_range_squared`.
        anchor_range = {},
        -- A Martyr's Skull riddle blocked by growth tentacles: where it is,
        -- from the riddle data, and how near a tentacle stands to be the
        -- riddle's. dm_forge's stood 4.9 to 7.1 metres from the riddle's
        -- button, the nearest of the growth event's own 24 metres away.
        riddle_range_squared = 64,
        -- Of those, only the ones at the door's own level block it. The two
        -- that do stood 1.5 metres above the button; a third, 6.4 metres up
        -- over the skull, is not needed to solve it and carries no marker.
        riddle_height = 3,
        riddle_x = {},
        riddle_y = {},
        riddle_z = {},
        riddle_kind = { martyr_skull_riddle_interactable = true },
    }

    -- ----------------------------------------------------------------------------
    -- Objective lifecycle and kind predicates
    -- ----------------------------------------------------------------------------

    function _update_mission_objective_lifecycle(unit, active_state, used_state)
        local state = _mission_objective_lifecycle_by_unit[unit]

        if used_state == true then
            if not state then
                state = {}
                _mission_objective_lifecycle_by_unit[unit] = state
            end

            state.retired = true

            return
        end

        if active_state == true then
            if not state then
                state = {}
                _mission_objective_lifecycle_by_unit[unit] = state
            end

            state.seen_active = true
            state.retired = false
        elseif active_state == false and state and state.seen_active then
            state.retired = true
        end
    end

    function _is_mission_objective_unit_retired(unit)
        local state = _mission_objective_lifecycle_by_unit[unit]

        return state ~= nil and state.retired == true
    end

    local function _reset_mission_objective_lifecycle()
        table_clear(_mission_objective_lifecycle_by_unit)
    end

    function _is_mission_objective_marker_kind(kind)
        return MISSION_OBJECTIVE_MARKER_KINDS[kind] == true
    end

    function _mission_objective_kind_for_interaction_type(interaction_type)
        return MISSION_OBJECTIVE_KIND_BY_INTERACTION_TYPE[interaction_type]
    end

    function _is_unit_of_inactive_objective(unit)
        return _scratch_inactive_objective_units[unit] == true
    end

    -- ----------------------------------------------------------------------------
    -- Luggable holders
    -- ----------------------------------------------------------------------------

    -- Whether a luggable is still where the radar first saw it. One inside a
    -- closed container has not moved since the objective started; one a player
    -- has carried, dropped or put in a socket has, and is inside nothing. On
    -- lm_rails a canister carried past a valve made the valve a "container",
    -- and every valve holding nothing was then dropped as an empty one while
    -- the game was marking it.
    function _luggable_unmoved(unit, x, y, z)
        local origin = LUGGABLE_HOLDER.origin[unit]

        if origin == nil then
            LUGGABLE_HOLDER.origin[unit] = { x, y, z }

            return true
        end

        local dx = x - origin[1]
        local dy = y - origin[2]
        local dz = z - origin[3]

        return dx * dx + dy * dy + dz * dz <= LUGGABLE_HOLDER.still_squared
    end

    -- The luggables the radar is tracking, whatever their own display setting:
    -- tracking is not gated on it, drawing is. A socket is a `luggable_` kind
    -- too, and holds nothing.
    local function _collect_objective_luggables()
        local holder = LUGGABLE_HOLDER
        local luggable_kind = holder.luggable_kind
        local count = 0

        for unit, data in pairs(mod._tracked_units) do
            local kind = data and data.kind or nil

            if kind ~= nil then
                local is_luggable = luggable_kind[kind]

                if is_luggable == nil then
                    is_luggable = type(kind) == "string" and string_find(kind, "luggable_", 1, true) == 1
                        and kind ~= "luggable_socket"
                    luggable_kind[kind] = is_luggable
                end

                if is_luggable then
                    local x, y, z = _vector3_components(_safe_unit_position(unit))

                    if x ~= nil and _luggable_unmoved(unit, x, y, z) then
                        count = count + 1
                        holder.units[count] = unit
                        holder.x[count] = x
                        holder.y[count] = y
                        holder.z[count] = z
                    end
                end
            end
        end

        holder.count = count
    end

    -- The luggable inside `unit`, if one is.
    local function _luggable_inside(unit)
        local x, y, z = _vector3_components(_safe_unit_position(unit))

        if x == nil then
            return nil
        end

        local holder = LUGGABLE_HOLDER
        local height = holder.height

        for i = 1, holder.count do
            -- The luggables are filed under their objective too, as
            -- interactables of their own, and one is not its own container.
            if holder.units[i] ~= unit then
                local dx = holder.x[i] - x
                local dy = holder.y[i] - y
                local dz = holder.z[i] - z

                if dx * dx + dy * dy <= holder.reach_squared and dz <= height and dz >= -height then
                    return holder.units[i]
                end
            end
        end

        return nil
    end

    -- The prefab a unit was spawned from, read once into `cache` and kept for the
    -- mission: a unit never changes what it was spawned from. `false` in the
    -- cache records that the engine could not say, and comes back as nil.
    local function _cached_unit_prefab(cache, unit)
        local known = cache[unit]

        if known == nil then
            known = _safe_unit_prefab_name ~= nil and _safe_unit_prefab_name(unit) or false
            cache[unit] = known
        end

        return known or nil
    end

    local function _luggable_holder_prefab(unit)
        return _cached_unit_prefab(LUGGABLE_HOLDER.prefab_of, unit)
    end

    -- A luggable in a container the radar is drawing: the container's marker
    -- already stands where it is, and the luggable's own would only sit under
    -- it. Only while the container is drawn, so the place is never left
    -- unmarked -- and an opened container is retired and never drawn again, so
    -- the luggable comes back the moment it is opened.
    function _luggable_hidden_in_container(unit)
        local container = LUGGABLE_HOLDER.inside[unit]

        return container ~= nil and mod._tracked_units[container] ~= nil
    end

    local function _note_luggable_holder(unit, objective_name, luggable)
        LUGGABLE_HOLDER.holds[unit] = true
        LUGGABLE_HOLDER.inside[luggable] = unit

        local prefab = _luggable_holder_prefab(unit)

        if prefab ~= nil then
            local prefabs = LUGGABLE_HOLDER.container_prefabs[objective_name]

            if prefabs == nil then
                prefabs = {}
                LUGGABLE_HOLDER.container_prefabs[objective_name] = prefabs
            end

            prefabs[prefab] = true
        end

        if _objective_debug_logging then
            _log_once("luggable_container:" .. tostring(unit), string_format(
                "Luggable container: mission=%s objective=%s prefab=%s position=%s",
                tostring(_safe_mission_name()),
                objective_name,
                tostring(prefab),
                _debug_unit_position_text(unit)
            ))
        end
    end

    -- A luggable objective files both its luggables and its sockets under its
    -- name, and the game only lets a luggable into a socket of its own
    -- objective, so the objective says what each socket takes.
    local function _note_luggable_cargo(unit, objective_name)
        local tracked = mod._tracked_units[unit]
        local kind = tracked and tracked.kind or nil
        local holder = LUGGABLE_HOLDER

        if kind == "luggable_socket" then
            holder.socket_objective[unit] = objective_name

            if _objective_debug_logging and holder.cargo[objective_name] ~= nil then
                _log_once("luggable_socket:" .. tostring(unit), string_format(
                    "Luggable socket: mission=%s objective=%s cargo=%s drawn_as=%s position=%s",
                    tostring(_safe_mission_name()),
                    objective_name,
                    holder.cargo[objective_name],
                    _luggable_socket_display_kind(unit),
                    _debug_unit_position_text(unit)
                ))
            end
        elseif kind ~= nil and holder.cargo[objective_name] == nil and holder.luggable_kind[kind] == true then
            holder.cargo[objective_name] = kind
        end
    end

    -- What a socket is drawn as. A power cell's socket stays a power socket; one
    -- for mission cargo -- capsules, canisters, rods, samples, the Prismata
    -- case -- is a step of the mission's machinery, which the game marks as an
    -- objective. Until its cargo is known, a socket is drawn as it always was.
    function _luggable_socket_display_kind(unit)
        local holder = LUGGABLE_HOLDER
        local objective_name = holder.socket_objective[unit]
        local cargo = objective_name ~= nil and holder.cargo[objective_name] or nil

        if cargo ~= nil and holder.objective_cargo[cargo] == true then
            return "mission_objective_other"
        end

        return "luggable_socket"
    end

    -- ----------------------------------------------------------------------------
    -- Active objectives and growth objectives
    -- ----------------------------------------------------------------------------

    local function _any_mission_objective_kind_enabled()
        local enabled_by_kind = _scratch_mission_objective_kind_enabled
        local any_enabled = false

        for kind in pairs(MISSION_OBJECTIVE_MARKER_KINDS) do
            local enabled = _kind_enabled(kind)
            enabled_by_kind[kind] = enabled
            any_enabled = any_enabled or enabled
        end

        return any_enabled
    end

    -- MissionObjective exposes no accessor for its units, so the objective name
    -- is read straight off the instance and matched against the name each
    -- target unit stores.
    local function _refresh_active_objective_names()
        local names = _scratch_active_objective_names
        table_clear(names)
        table_clear(LUGGABLE_HOLDER.objectives)
        LUGGABLE_HOLDER.active = false

        local objective_system = _safe_extension_system(MISSION_OBJECTIVE_SOURCE)

        if type(objective_system) ~= "table" then
            return nil
        end

        -- Field read, never a call: see the note on _safe_zone_field. The
        -- objective system is server-authoritative and its methods drive live
        -- mission state.
        local active_objectives = rawget(objective_system, "_active_objectives")

        if type(active_objectives) ~= "table" then
            return nil
        end

        local found = false

        for key, value in pairs(active_objectives) do
            local objective = type(key) == "table" and key or (type(value) == "table" and value or nil)
            local name = objective and rawget(objective, "_name") or nil

            if type(name) == "string" then
                names[name] = true
                found = true

                _note_growth_objective(name, objective)

                if rawget(objective, "_objective_type") == "luggable" then
                    LUGGABLE_HOLDER.objectives[name] = true
                    LUGGABLE_HOLDER.active = true
                end
            end
        end

        return found and names or nil
    end

    local function _safe_objective_target_name(extension)
        if type(extension) ~= "table" then
            return nil
        end

        local name = rawget(extension, "_objective_name")

        return type(name) == "string" and name or nil
    end

    -- Field reads only, for the same reason as the zone extension below.
    local function _safe_objective_target_field(extension, field_name)
        if type(extension) ~= "table" then
            return nil
        end

        return rawget(extension, field_name)
    end

    -- Read-only by design. MissionObjectiveZoneExtension owns
    -- _equip_auspex_to_players, _unequip_auspex_from_players, _deactivate_zone
    -- and _inform_skull_of_completion, and names like zone_finished are
    -- completion routines rather than queries. Calling into this class from a
    -- client mod changes live objective state, so only fields are ever read.
    local function _safe_zone_field(extension, field_name)
        if type(extension) ~= "table" then
            return nil
        end

        return rawget(extension, field_name)
    end

    -- Zone collections are sometimes arrays and sometimes unit-keyed sets, so
    -- both shapes are read the same way.
    local function _collection_unit(key, value)
        if value ~= nil and type(value) ~= "boolean" then
            return value
        end

        return key
    end

    function _is_growth_objective_name(objective_name)
        return objective_name ~= nil and _growth_objective_by_name[objective_name] == true
    end

    -- Read off the live objective as the active objectives are listed, before
    -- any target is looked at. A field, never a call.
    function _note_growth_objective(objective_name, objective)
        if _growth_objective_by_name[objective_name] == true
            or rawget(objective, "_objective_type") ~= "demolition" then
            return
        end

        _growth_objective_by_name[objective_name] = true
    end

    -- ----------------------------------------------------------------------------
    -- Minigame devices
    -- ----------------------------------------------------------------------------

    -- Steps used more than once. lm_rails' cargo valves stay active, unused and
    -- offering their prompt for the whole objective; what says a valve is the
    -- step right now is the game's objective marker on it, which comes and goes
    -- as the capsules go into the sockets beside it. So an interactable the game
    -- has marked as an objective this mission follows that marker from then on.
    -- One the game never marks is shown as before, and with no readable marker
    -- list nothing is hidden. The prompt a player gets standing next to
    -- something is not a mark. Remembered in the unit's lifecycle state, which
    -- the mission reset clears.
    local function _objective_marker_lapsed(unit)
        if not _world_marker_units_available or _game_marks_as_objective == nil then
            return false
        end

        local state = _mission_objective_lifecycle_by_unit[unit]

        if _game_marks_as_objective(unit) then
            if state == nil then
                state = {}
                _mission_objective_lifecycle_by_unit[unit] = state
            end

            state.objective_marked = true

            return false
        end

        return state ~= nil and state.objective_marked == true
    end

    -- Walks the whole minigame map rather than looking units up one at a time:
    -- a mission carries a handful of these (2 in Core Research, 5 on the train),
    -- so one pass per scan is cheaper than a lookup per objective unit.
    local function _refresh_minigame_states()
        table_clear(_minigame_state_by_unit)

        local minigame_map = _safe_unit_to_extension_map(MISSION_OBJECTIVE_MINIGAME_SYSTEM)

        if type(minigame_map) ~= "table" then
            return
        end

        for unit, extension in pairs(minigame_map) do
            if type(extension) == "table" then
                local minigame = rawget(extension, "_minigame")
                local state = type(minigame) == "table" and rawget(minigame, "_current_state") or nil

                if state == MISSION_OBJECTIVE_MINIGAME_COMPLETE_STATE then
                    _minigame_state_by_unit[unit] = MISSION_OBJECTIVE_MINIGAME_COMPLETE_STATE
                elseif state == MISSION_OBJECTIVE_MINIGAME_GAMEPLAY_STATE then
                    -- `_active` is the one field that says a player is at this
                    -- device right now, and it is per device, so it stands on
                    -- its own.
                    if rawget(extension, "_active") == true then
                        _minigame_state_by_unit[unit] = MISSION_OBJECTIVE_MINIGAME_ACTIVE
                    elseif _scratch_world_marker_units[unit] ~= nil then
                        -- Red means "this device is asking for a player", and
                        -- the puzzle state alone cannot say that: a solved one
                        -- does not report itself solved. It goes back to
                        -- `gameplay` with nobody attached, which is the same
                        -- reading as a fresh breakdown. On Power Matrix a
                        -- repaired interrogator sat in that state for the rest
                        -- of the event and turned red again the moment the next
                        -- one broke.
                        --
                        -- The game's own marker is what separates them: it marks
                        -- the device it is currently asking for and nothing
                        -- else. Both real breakdowns in that run carried one,
                        -- and the repaired device carried none even with the
                        -- player stood at it. It is also what exempts the device
                        -- from the radar's range, so the red one and the one
                        -- drawn past the range are the same device by
                        -- construction rather than by two rules agreeing.
                        _minigame_state_by_unit[unit] = MISSION_OBJECTIVE_MINIGAME_WAITING
                    end
                end
            end
        end
    end

    -- Only units that actually carry a puzzle get a state, so every other
    -- objective marker keeps the shared objective tint. A solved puzzle keeps
    -- its marker too and falls back to that same tint: the devices stay part of
    -- the objective until it ends, and one blinking out and returning in red
    -- when it re-arms reads as something having gone wrong.
    function _minigame_marker_meta(unit, meta)
        local state = _minigame_state_by_unit[unit]

        if state == MISSION_OBJECTIVE_MINIGAME_COMPLETE_STATE then
            state = nil
        end

        if state == nil then
            -- A unit that had a state and lost it has to be told so. The tracked
            -- entry keeps its previous meta when none is supplied, which would
            -- otherwise leave a solved puzzle wearing the colour it had while
            -- running. The cached table is the one the entry holds, so clearing
            -- the field here clears it there.
            local cached = _minigame_meta_by_unit[unit]

            if cached ~= nil then
                cached.minigame_state = nil
            end

            return meta
        end

        if meta == nil then
            meta = _minigame_meta_by_unit[unit]

            if meta == nil then
                meta = {}
                _minigame_meta_by_unit[unit] = meta
            end
        end

        meta.minigame_state = state

        return meta
    end

    -- ----------------------------------------------------------------------------
    -- Objective kind resolution
    -- ----------------------------------------------------------------------------

    function _refresh_mission_objective_markers()
        table_clear(_mission_objective_kind_by_unit)

        local enabled = _any_mission_objective_kind_enabled()

        if enabled then
            table_clear(_scratch_world_marker_units)

            -- Read here, at the head of the frame, rather than in the objective
            -- pass that used to own it: the puzzle state below is derived from
            -- it and runs first, and reading last frame's answer would colour a
            -- device a scan behind the game.
            --
            -- Guarded rather than called outright: a scan must not fail because
            -- one helper is missing, and without the list the filters that use
            -- it simply do not run.
            _world_marker_units_available = _refresh_world_marker_units ~= nil
                and _refresh_world_marker_units(_scratch_world_marker_units) == true

            _refresh_minigame_states()
        end

        return enabled
    end

    function _mission_objective_kind_for_unit(unit)
        return _mission_objective_kind_by_unit[unit]
    end

    -- Cheap test for the hidden-interactee path: a single extension call, so
    -- scanning every hidden interactee each tick stays affordable.
    function _hidden_mission_objective_kind(extension, unit)
        local kind = _mission_objective_kind_by_unit[unit]

        if kind then
            return kind
        end

        local interaction_type_fn = extension and extension.interaction_type

        if type(interaction_type_fn) ~= "function" then
            return nil
        end

        local ok_type, value = pcall(interaction_type_fn, extension)

        if not ok_type then
            return nil
        end

        return MISSION_OBJECTIVE_KIND_BY_INTERACTION_TYPE[_safe_lower_string(value)]
    end

    local function _mission_objective_unit_kind(unit, interactee_map, default_kind)
        local interactee_extension = interactee_map and interactee_map[unit] or nil
        local interaction_type = nil

        if type(interactee_extension) == "table" then
            -- State first, kind second. A completed step reports itself used,
            -- and missions place several copies of the same device with only one
            -- armed at a time, so an inactive interactee is not the one the
            -- current step wants. Resolving the kind before these checks let
            -- every copy through.
            local used_fn = interactee_extension.used

            if type(used_fn) == "function" then
                local ok_used, used = pcall(used_fn, interactee_extension)

                if not ok_used or used == true then
                    return nil
                end
            end

            local active_fn = interactee_extension.active

            if type(active_fn) == "function" then
                local ok_active, active = pcall(active_fn, interactee_extension)

                if not ok_active or active ~= true then
                    return nil
                end
            end

            local interaction_type_fn = interactee_extension.interaction_type

            if type(interaction_type_fn) == "function" then
                local ok_type, value = pcall(interaction_type_fn, interactee_extension)
                interaction_type = ok_type and _safe_lower_string(value) or nil
            end
        end

        if _is_mission_objective_unit_retired(unit) then
            return nil
        end

        if interaction_type then
            local kind = MISSION_OBJECTIVE_KIND_BY_INTERACTION_TYPE[interaction_type]

            if kind then
                return kind
            end

            -- Owned by a more specific pass; never falls through to the generic
            -- category.
            if MISSION_OBJECTIVE_EXCLUSIVE_INTERACTION_TYPES[interaction_type] then
                return nil
            end
        end

        if _scratch_growth_objective_units[unit] == true then
            return "mission_objective_growth"
        end

        if _scratch_destroy_objective_units[unit] == true then
            return "mission_objective_destroy"
        end

        return default_kind or "mission_objective_other"
    end

    -- ----------------------------------------------------------------------------
    -- Debug logging
    -- ----------------------------------------------------------------------------

    -- Debug mode only: `_objective_debug_logging` is read once per scan, so none
    -- of these lines costs anything outside it.
    --
    -- One line per objective marker the radar draws, once per unit, kind and
    -- state of the game's own marker on it: enough to trace a report of a marker
    -- drawn or missing to what the radar saw.
    local function _debug_log_objective_marker(unit, kind)
        local game_marker = "unreadable"

        if _world_marker_units_available then
            if _game_marks_as_objective ~= nil and _game_marks_as_objective(unit) then
                game_marker = "objective"
            elseif _scratch_world_marker_units[unit] ~= nil then
                game_marker = "other"
            else
                game_marker = "none"
            end
        end

        local target_map = _safe_unit_to_extension_map(MISSION_OBJECTIVE_TARGET_SYSTEM)
        local objective_name = type(target_map) == "table" and _safe_objective_target_name(target_map[unit]) or nil

        _log_once("objective_marker:" .. tostring(unit) .. "|" .. kind .. "|" .. game_marker, string_format(
            "Objective marker: mission=%s kind=%s objective=%s game_marker=%s position=%s",
            tostring(_safe_mission_name()),
            kind,
            tostring(objective_name),
            game_marker,
            _debug_unit_position_text(unit)
        ))
    end

    -- A unit the game marks as an objective that the radar draws nothing for:
    -- the first thing to look at after a game patch or on a new mission. Once
    -- per unit, and not while a just-started objective's markers are still held
    -- back.
    local function _debug_log_untracked_objective_markers()
        if not _world_marker_units_available or _game_marks_as_objective == nil then
            return
        end

        local tracked_units = mod._tracked_units
        local target_map = _safe_unit_to_extension_map(MISSION_OBJECTIVE_TARGET_SYSTEM)
        local interactee_map = _safe_unit_to_extension_map("interactee_system")
        local now = _safe_gameplay_time() or 0

        for unit in pairs(_scratch_world_marker_units) do
            if tracked_units[unit] == nil and _game_marks_as_objective(unit) then
                local objective_name = type(target_map) == "table" and _safe_objective_target_name(target_map[unit])
                    or nil
                local first_active = objective_name ~= nil and _objective_first_active_t[objective_name] or nil

                if first_active == nil or now - first_active >= OBJECTIVE_MARKER_SETTLE_SECONDS then
                    _log_once("untracked_objective_marker:" .. tostring(unit), string_format(
                        "Untracked objective marker: mission=%s objective=%s objective_active=%s retired=%s interactee=%s position=%s",
                        tostring(_safe_mission_name()),
                        tostring(objective_name),
                        tostring(objective_name ~= nil and _scratch_active_objective_names[objective_name] == true),
                        tostring(_is_mission_objective_unit_retired(unit)),
                        tostring(type(interactee_map) == "table" and interactee_map[unit] ~= nil),
                        _debug_unit_position_text(unit)
                    ))
                end
            end
        end
    end

    -- ----------------------------------------------------------------------------
    -- Marker claims
    -- ----------------------------------------------------------------------------

    -- `objective_confirmed` says the caller has already established that this
    -- unit belongs to a live objective. The scan zone pass has: it checks its
    -- zone's own objective before selecting any target. Its targets must not
    -- then be re-judged by the objective the target system files them under,
    -- which is not always the one whose zone selected them.
    local function _claim_mission_objective_unit(unit, kind, enabled_by_kind, seen_units, objective_confirmed)
        if not kind or not enabled_by_kind[kind] or seen_units[unit] then
            return
        end

        -- Single choke point for retirement, so a step that has been completed
        -- cannot be re-claimed by any source.
        if _is_mission_objective_unit_retired(unit) then
            return
        end

        if not objective_confirmed and _is_unit_of_inactive_objective(unit) then
            return
        end

        local owned = mod._tracked_units[unit]

        -- Units another scan claimed keep their own classification, so luggables
        -- and their sockets are never relabelled. Units this scan already owns
        -- must still be re-confirmed every pass, otherwise the prune below drops
        -- them and they flicker.
        if owned ~= nil and owned.source ~= MISSION_OBJECTIVE_SOURCE then
            return
        end

        if not _is_trackable_unit_alive(unit, kind) then
            return
        end

        -- Destructible steps -- the ice over the gears, and the like -- report
        -- nothing at all through the objective system once they are broken: the
        -- objective only ends when the last of them is gone. Their health
        -- extension is the one per-unit completion signal they carry. Units
        -- without one read nil here and are unaffected.
        if _safe_health_alive(unit) == false then
            return
        end

        seen_units[unit] = true
        _mission_objective_kind_by_unit[unit] = kind
        _track_unit(unit, kind, MISSION_OBJECTIVE_SOURCE, _minigame_marker_meta(unit, nil))

        if _objective_debug_logging then
            _debug_log_objective_marker(unit, kind)
        end
    end

    -- ----------------------------------------------------------------------------
    -- Scan zones and scannable targets
    -- ----------------------------------------------------------------------------

    -- The zone selection table is the only place a per-target scanned flag can
    -- live, so its exact shape is logged: key type, value type and value for
    -- each entry, alongside the zone's own progression counters. Keyed by the
    -- whole shape, so each distinct state during a scan is reported once and the
    -- table can be watched changing as targets are scanned.
    -- Scan targets carry no completion signal of their own: every scanning
    -- interactee reports active=true, used=false for the whole mission. The only
    -- per-target signal is inside the zone's own selection table, so it is read
    -- here rather than inferred from interactee state.
    --
    -- The table is trusted to mark scanned targets only when its own numbers
    -- agree with the zone's progression counter. If the shapes disagree the
    -- interpretation is dropped and every selected target stays visible, which
    -- is the previous behaviour rather than a guess that could hide live targets.
    local function _scanned_units_from_selection(scannables, progression)
        if progression == nil then
            return nil
        end

        local entry_count = 0
        local flagged_count = 0

        for _, value in pairs(scannables) do
            entry_count = entry_count + 1

            if type(value) ~= "boolean" then
                return nil
            end

            if value == true then
                flagged_count = flagged_count + 1
            end
        end

        if entry_count == 0 or flagged_count ~= progression then
            return nil
        end

        return true
    end

    -- Missing data never hides a target: an absent extension or field means the
    -- scannable stays visible, so a changed engine layout degrades to the old
    -- behaviour instead of blanking live objectives.
    local function _is_scannable_still_active(scannable_map, unit)
        local extension = scannable_map and scannable_map[unit] or nil

        if type(extension) ~= "table" then
            return true
        end

        local is_active = rawget(extension, "_is_active")

        if is_active == nil then
            return true
        end

        return is_active == true
    end

    -- Clients never receive the zone's selection: _select_scannable_units_for_event
    -- runs on the server, so a joining player sees _num_scannables_in_zone but an
    -- empty _selected_scannable_units. The scannable extensions themselves are
    -- replicated, so the selection is recovered from their _is_active flags.
    --
    -- Self-validating: the recovered set is only used when its size matches the
    -- zone's own outstanding count. A mismatch marks nothing and says so in the
    -- log, which keeps a misread flag from putting every scannable in the level
    -- on the radar.
    local function _track_active_scannables(scannable_map, expected, enabled_by_kind, seen_units)
        if type(scannable_map) ~= "table" or expected == nil or expected <= 0 then
            return
        end

        local active_count = 0

        for _, extension in pairs(scannable_map) do
            if type(extension) == "table" and rawget(extension, "_is_active") == true then
                active_count = active_count + 1
            end
        end

        -- Fewer active scannables than the zone reports outstanding is normal:
        -- the flag clears the moment a target is scanned, while the zone's
        -- progression counter catches up a tick later. Only a count larger than
        -- the zone expects means the flag is not understood, so equality would
        -- blank every marker for a frame after each scan.
        local trusted = active_count <= expected

        if trusted then
            for unit, extension in pairs(scannable_map) do
                if type(extension) == "table" and rawget(extension, "_is_active") == true then
                    _claim_mission_objective_unit(unit, "mission_objective_scanner", enabled_by_kind,
                        seen_units, true)

                    _scratch_objective_range_exempt[unit] = true
                end
            end
        end
    end

    local function _track_mission_objective_scan_zones(enabled_by_kind, active_names, seen_units, zone_units)
        local extension_map = _safe_unit_to_extension_map(MISSION_OBJECTIVE_ZONE_SYSTEM)

        if type(extension_map) ~= "table" then
            return
        end

        local scanner_enabled = enabled_by_kind.mission_objective_scanner == true
        local scannable_map = scanner_enabled and _safe_unit_to_extension_map(MISSION_OBJECTIVE_SCANNABLE_SYSTEM)
            or nil
        local expected_outstanding = 0
        local marked_from_selection = 0
        local has_active_zone = false

        for zone_unit, extension in pairs(extension_map) do
            zone_units[zone_unit] = true

            if scanner_enabled and active_names ~= nil then
                local objective_name = _safe_objective_target_name(extension)
                local is_active_objective = type(objective_name) == "string"
                    and active_names[objective_name] == true
                local activated = _safe_zone_field(extension, "_activated") == true
                local progression = tonumber(_safe_zone_field(extension, "_current_progression"))
                local total = tonumber(_safe_zone_field(extension, "_num_scannables_in_zone"))
                local finished = progression ~= nil and total ~= nil and total > 0 and progression >= total

                if is_active_objective and activated and not finished then
                    has_active_zone = true

                    local outstanding = (total or 0) - (progression or 0)

                    if outstanding > 0 then
                        expected_outstanding = expected_outstanding + outstanding
                    end

                    -- Never the zone's full scannable list: that holds every
                    -- scannable in the level, not the ones selected for this run.
                    local scannables = _safe_zone_field(extension, "_selected_scannable_units")

                    if type(scannables) == "table" then
                        local scanned_is_true = _scanned_units_from_selection(scannables, progression)

                        for key, value in pairs(scannables) do
                            local unit = _collection_unit(key, value)
                            local scanned = scanned_is_true == true and value == true

                            if unit ~= nil and not scanned and _is_scannable_still_active(scannable_map, unit) then
                                marked_from_selection = marked_from_selection + 1

                                _claim_mission_objective_unit(unit, "mission_objective_scanner", enabled_by_kind,
                                    seen_units, true)

                                -- Selected by a live zone and still outstanding
                                -- is the same state the vanilla HUD draws its
                                -- own marker from, so it is what exempts the
                                -- target from the radar's range.
                                _scratch_objective_range_exempt[unit] = true
                            end
                        end

                    end
                end
            end
        end

        if has_active_zone and marked_from_selection == 0 then
            _track_active_scannables(scannable_map, expected_outstanding, enabled_by_kind, seen_units)
        end
    end

    -- ----------------------------------------------------------------------------
    -- Actionable objective targets
    -- ----------------------------------------------------------------------------

    -- The objective target system also holds pure position hints: luggable spawn
    -- points, socket placements and waypoints the game never makes reachable.
    -- They carry no state of their own and there is nothing to do at them, which
    -- is exactly what tells them apart -- a real step is either an interactee (a
    -- device, a console, a luggable) or a destructible with health (ice, a
    -- barricade). Applied only to the broad target system; the dedicated systems
    -- hold nothing but real devices.
    local function _is_actionable_objective_target(unit, interactee_map)
        if interactee_map ~= nil and interactee_map[unit] ~= nil then
            return true
        end

        -- nil means no health extension at all, false means destroyed; the claim
        -- itself drops the destroyed ones.
        return _safe_health_alive(unit) ~= nil
    end

    -- Actionability is evaluated once per unit here and read back below, so the
    -- health-extension lookup runs once per active objective unit per scan
    -- rather than twice.
    local function _refresh_objective_actionable_targets(extension_map, interactee_map, active_names)
        local has_actionable = _scratch_objective_has_actionable
        local actionable_by_unit = _scratch_objective_actionable_by_unit

        table_clear(has_actionable)
        table_clear(actionable_by_unit)
        table_clear(_scratch_objective_has_start_marker)
        table_clear(_scratch_start_marker_by_unit)
        table_clear(_scratch_growth_objective_units)
        table_clear(_scratch_destroy_objective_units)
        table_clear(LUGGABLE_HOLDER.holds)
        table_clear(LUGGABLE_HOLDER.inside)
        LUGGABLE_HOLDER.count = 0

        if LUGGABLE_HOLDER.active then
            _collect_objective_luggables()
        end

        if type(extension_map) ~= "table" then
            return
        end

        for unit, extension in pairs(extension_map) do
            local objective_name = _safe_objective_target_name(extension)

            if objective_name ~= nil then
                if active_names ~= nil and active_names[objective_name] == true then
                    if _objective_first_active_t[objective_name] == nil then
                        _objective_first_active_t[objective_name] = _safe_gameplay_time() or 0
                    end

                    local actionable = _is_actionable_objective_target(unit, interactee_map)

                    actionable_by_unit[unit] = actionable

                    if actionable then
                        has_actionable[objective_name] = true
                    end

                    if _scratch_world_marker_units[unit] then
                        _objective_world_marker_seen[objective_name] = true
                    end

                    if _is_growth_objective_name(objective_name) then
                        _scratch_growth_objective_units[unit] = true
                    elseif _safe_objective_target_field(extension, "_ui_target_type") == "demolition" then
                        _scratch_destroy_objective_units[unit] = true
                    end

                    if LUGGABLE_HOLDER.objectives[objective_name] == true then
                        _note_luggable_cargo(unit, objective_name)
                    end

                    if LUGGABLE_HOLDER.count > 0 and LUGGABLE_HOLDER.objectives[objective_name] == true
                        and interactee_map ~= nil and interactee_map[unit] ~= nil then
                        local luggable = _luggable_inside(unit)

                        if luggable ~= nil then
                            _note_luggable_holder(unit, objective_name, luggable)
                        end
                    end

                    if _safe_objective_target_field(extension, "_add_marker_on_objective_start") == true then
                        _scratch_start_marker_by_unit[unit] = true
                        _scratch_objective_has_start_marker[objective_name] = true
                    end
                else
                    _scratch_inactive_objective_units[unit] = true
                end
            end
        end
    end

    -- ----------------------------------------------------------------------------
    -- Growth tentacles
    -- ----------------------------------------------------------------------------

    -- The prefab a tentacle candidate was spawned from, read once per unit: a
    -- unit never changes what it was spawned from, and decoration near a growth
    -- is re-tested every scan. nil when the engine cannot say -- then for every
    -- candidate alike, which leaves the shape to decide on its own as it did
    -- before prefabs were read.
    function _growth_eye_prefab(unit)
        return _cached_unit_prefab(GROWTH_EYE.prefab_of, unit)
    end

    -- Where this mission's Martyr's Skull riddle is blocked by growth
    -- tentacles: the riddle entries flagged `tentacles`. A mission lists a
    -- handful of entries, so this is read every scan.
    local function _collect_riddle_tentacle_anchors()
        local mission_name = _safe_mission_name()
        local signatures = mission_name ~= nil and MARTYR_SKULL_RIDDLE_SIGNATURES_BY_MISSION[mission_name] or nil
        local count = 0

        if signatures == nil then
            return 0
        end

        for _, entry in pairs(signatures) do
            if type(entry) == "table" and entry.tentacles == true then
                for i = 1, #entry do
                    local position = entry[i]

                    count = count + 1
                    GROWTH_EYE.riddle_x[count] = position.x
                    GROWTH_EYE.riddle_y[count] = position.y
                    GROWTH_EYE.riddle_z[count] = position.z
                end
            end
        end

        return count
    end

    -- The marker a standing tentacle carries. One beside a Martyr's Skull
    -- riddle is the riddle's and never a growth's, whatever event runs around
    -- it: dm_forge's riddle door stands 26 metres from a growth. Any other is
    -- the growth's only while it stands inside the live event. Tentacles are
    -- remembered for the mission, and the riddle's, left standing, came back
    -- 200 metres away when dm_forge's final event started.
    local function _growth_tentacle_kind(unit, growth_anchor_count, riddle_count, riddle_live)
        local x, y, z = _vector3_components(_safe_unit_position(unit))

        if x == nil then
            return nil
        end

        local eye = GROWTH_EYE

        for i = 1, riddle_count do
            local dx = eye.riddle_x[i] - x
            local dy = eye.riddle_y[i] - y
            local dz = eye.riddle_z[i] - z

            if dx * dx + dy * dy + dz * dz <= eye.riddle_range_squared then
                if riddle_live and dz <= eye.riddle_height and dz >= -eye.riddle_height then
                    return "martyr_skull_riddle_interactable"
                end

                return nil
            end
        end

        for i = 1, growth_anchor_count do
            local dx = eye.anchor_x[i] - x
            local dy = eye.anchor_y[i] - y
            local dz = eye.anchor_z[i] - z

            if dx * dx + dy * dy + dz * dz <= eye.range_squared then
                return "mission_objective_growth"
            end
        end

        return nil
    end

    -- One marker per tentacle rather than three: at radar scale three markers
    -- 40 cm apart are a single blob. It is carried by the tentacle's
    -- lowest-sorting living eye, so it survives the first two being destroyed
    -- and the shared health gate in `_claim_mission_objective_unit` retires it
    -- when the last one goes. The event ending empties the anchor set, and the
    -- scan's own prune then drops whatever is left.
    local function _track_growth_tentacle_units(enabled_by_kind, seen_units)
        local growth_enabled = enabled_by_kind["mission_objective_growth"] == true
        local riddle_count = _collect_riddle_tentacle_anchors()
        -- A riddle's tentacles are looked for only while it is open and its
        -- markers are on; the ones already known stay off the growth's either
        -- way.
        local riddle_live = riddle_count > 0
            and not _is_current_mission_martyr_skull_riddle_solved()
            and _kind_enabled("martyr_skull_riddle_interactable")

        if not growth_enabled and not riddle_live then
            return
        end

        local anchor_x = GROWTH_EYE.anchor_x
        local anchor_y = GROWTH_EYE.anchor_y
        local anchor_z = GROWTH_EYE.anchor_z
        local anchor_range = GROWTH_EYE.anchor_range
        local anchor_count = 0
        -- The tentacles carry no marker of their own: the game draws its three
        -- yellow pips on them with something that never reaches the marker list.
        -- What it does mark is the corruptor they belong to, so the event's own
        -- marker is what says the HUD is pointing at this fight.
        local growth_marked = false

        -- Anchored on the live objective's own targets, which includes the
        -- event's unused spawn points. Tentacles stood 10 to 17 metres from the
        -- corruptor they belonged to.
        if growth_enabled then
            for unit in pairs(_scratch_growth_objective_units) do
                local x, y, z = _vector3_components(_safe_unit_position(unit))

                if x ~= nil then
                    anchor_count = anchor_count + 1
                    anchor_x[anchor_count] = x
                    anchor_y[anchor_count] = y
                    anchor_z[anchor_count] = z
                    anchor_range[anchor_count] = GROWTH_EYE.range_squared
                end

                if _world_marker_units_available and _scratch_world_marker_units[unit] == true
                    and (_game_draws_marker_on == nil or _game_draws_marker_on(unit)) then
                    growth_marked = true
                end
            end
        end

        local growth_anchor_count = anchor_count

        if riddle_live then
            for i = 1, riddle_count do
                anchor_count = anchor_count + 1
                anchor_x[anchor_count] = GROWTH_EYE.riddle_x[i]
                anchor_y[anchor_count] = GROWTH_EYE.riddle_y[i]
                anchor_z[anchor_count] = GROWTH_EYE.riddle_z[i]
                anchor_range[anchor_count] = GROWTH_EYE.riddle_range_squared
            end
        end

        if anchor_count == 0 then
            return
        end

        local extension_map = _safe_unit_to_extension_map("destructible_system")

        if type(extension_map) ~= "table" then
            return
        end

        local units = GROWTH_EYE.units
        local xs = GROWTH_EYE.x
        local ys = GROWTH_EYE.y
        local zs = GROWTH_EYE.z
        local limit = GROWTH_EYE.candidate_limit
        local count = 0

        for unit, extension in pairs(extension_map) do
            -- Nav gates are the level's monster wall volumes: numerous, never a
            -- target, and cheaper to reject than to measure.
            if type(extension) == "table" and rawget(extension, "_is_nav_gate") ~= true then
                local x, y, z = _vector3_components(_safe_unit_position(unit))

                if x ~= nil then
                    for i = 1, anchor_count do
                        local dx = anchor_x[i] - x
                        local dy = anchor_y[i] - y
                        local dz = anchor_z[i] - z

                        if dx * dx + dy * dy + dz * dz <= anchor_range[i] and count < limit then
                            count = count + 1
                            units[count] = unit
                            xs[count] = x
                            ys[count] = y
                            zs[count] = z

                            break
                        end
                    end
                end
            end
        end

        local link_squared = GROWTH_EYE.link_squared
        local members_needed = GROWTH_EYE.cluster_size
        local group_of = GROWTH_EYE.group_of
        local member_units = GROWTH_EYE.member_units
        local member_group = GROWTH_EYE.member_group
        local found = GROWTH_EYE.found

        -- Register a tentacle the first time its whole prefab is standing here.
        -- A destroyed eye leaves the destructible system, so the shape can only
        -- be recognised while all three are present; from then on the tentacle
        -- is remembered by the units it was made of rather than re-derived from
        -- what is left, which is what used to drop the marker at the first kill.
        --
        -- Eyes already belonging to a tentacle are excluded from both ends of
        -- the match, so a new tentacle at a spawn point one has just been
        -- cleared from cannot absorb the remains of its predecessor.
        for i = 1, count do
            if group_of[units[i]] == nil then
                local x = xs[i]
                local y = ys[i]
                local z = zs[i]
                local found_count = 1

                found[1] = i

                for j = 1, count do
                    if j ~= i and group_of[units[j]] == nil then
                        local dx = xs[j] - x
                        local dy = ys[j] - y
                        local dz = zs[j] - z

                        if dx * dx + dy * dy + dz * dz <= link_squared then
                            found_count = found_count + 1
                            found[found_count] = j
                        end
                    end
                end

                -- The three eyes of a tentacle are one prefab; the level's own
                -- breakables are not. Beside a growth on hm_strain a row of
                -- decoration three prefabs wide stood within half a metre of
                -- itself and was drawn as a tentacle. The eyes are compared with
                -- each other rather than with a known id, so nothing is
                -- hard-coded, and not by the triangle they form: one tentacle on
                -- the same mission measured 0.328, 0.422 and 0.548 metres a
                -- second after it spawned, against 0.328, 0.347 and 0.407 at rest.
                if found_count >= members_needed then
                    local prefab = _growth_eye_prefab(units[i])
                    local kept = 1

                    for k = 2, found_count do
                        if _growth_eye_prefab(units[found[k]]) == prefab then
                            kept = kept + 1
                            found[kept] = found[k]
                        end
                    end

                    found_count = kept
                end

                if found_count >= members_needed then
                    local group = GROWTH_EYE.group_next + 1
                    local member_count = GROWTH_EYE.member_count

                    GROWTH_EYE.group_next = group

                    for k = 1, found_count do
                        local member = units[found[k]]

                        member_count = member_count + 1
                        member_units[member_count] = member
                        member_group[member_count] = group
                        group_of[member] = group
                    end

                    GROWTH_EYE.member_count = member_count
                end
            end
        end

        local standing = GROWTH_EYE.group_standing
        local carrier = GROWTH_EYE.group_carrier

        table_clear(standing)
        table_clear(carrier)

        -- An eye's own entry in the destructible system is what says it is still
        -- there: a destroyed one is gone from the map. The unit and health
        -- checks cover a game that retires one without removing it.
        for k = 1, GROWTH_EYE.member_count do
            local member = member_units[k]

            if extension_map[member] ~= nil
                and _safe_unit_alive(member)
                and _safe_health_alive(member) ~= false then
                local group = member_group[k]

                standing[group] = (standing[group] or 0) + 1

                if carrier[group] == nil then
                    carrier[group] = k
                end
            end
        end

        -- One marker per tentacle, carried by the first of its eyes still
        -- standing. Registration order is fixed for the life of the tentacle, so
        -- the marker moves only when the eye carrying it is destroyed, and the
        -- tentacle leaves the radar only when its last eye does.
        for group, k in pairs(carrier) do
            local member = member_units[k]
            local kind = _growth_tentacle_kind(member, growth_anchor_count, riddle_count, riddle_live)

            if kind == "martyr_skull_riddle_interactable" then
                _claim_mission_objective_unit(member, kind, GROWTH_EYE.riddle_kind, seen_units, true)
            elseif kind ~= nil then
                -- Confirmed by the live objective these sit inside, not by the
                -- target system, which has never heard of them.
                _claim_mission_objective_unit(member, kind, enabled_by_kind, seen_units, true)

                -- Only while the game is marking the growth, and only for the
                -- tentacles of that growth. A breakable the event is not running
                -- on is never in this set.
                if growth_marked then
                    _scratch_objective_range_exempt[member] = true
                end
            end

            -- Per tentacle, remaining eye count and marker, so a run shows each
            -- one being worn down and what it was drawn as.
            if _objective_debug_logging then
                _log_once("growth_tentacle:" .. group .. "|" .. standing[group] .. "|" .. tostring(kind), string_format(
                    "Growth tentacle standing: mission=%s tentacle=%d eyes=%d as=%s position=%s",
                    tostring(_safe_mission_name()),
                    group,
                    standing[group],
                    tostring(kind),
                    _debug_unit_position_text(member)
                ))
            end
        end

        for i = 1, count do
            units[i] = nil
        end
    end

    -- ----------------------------------------------------------------------------
    -- Radar range exemption
    -- ----------------------------------------------------------------------------

    -- Whether the game is currently pointing the player at this unit, which is
    -- what lets a mission objective past the radar's configured scan range. One
    -- decision; the systems that answer it differently feed it from two places.
    --
    -- Most objectives carry their own entry in `request_world_markers_list`, the
    -- list the vanilla HUD draws from, so they are answered by a direct lookup
    -- and nothing has to be maintained for them. That list does not separate an
    -- objective marker from an interaction prompt and does not need to: a prompt
    -- only appears within a few metres, where the range filter was never going
    -- to hide anything.
    --
    -- The rest never reach that list at all, and each objective system exposes
    -- the same fact its own way: a scan zone by which of its targets it has
    -- selected and not yet had scanned, a growth tentacle by the marker on the
    -- corruptor it belongs to. Those passes write what they know into one set as
    -- they run, and it is rebuilt from scratch every scan, so an exemption lasts
    -- exactly as long as the state behind it.
    function _objective_ignores_radar_range(unit)
        -- Only while the game is drawing its marker. Its objective markers stop
        -- at 300 metres, and Mortis Trials marks the start of all three arenas,
        -- two of them 550 to 650 metres off where no player is.
        if _world_marker_units_available and _scratch_world_marker_units[unit] == true
            and (_game_draws_marker_on == nil or _game_draws_marker_on(unit)) then
            return true
        end

        -- A container still holding its objective's luggable stands in for the
        -- cargo the mission is sending the player to find, which the radar
        -- would otherwise only show once the player was standing near it.
        if LUGGABLE_HOLDER.holds[unit] == true then
            return true
        end

        return _scratch_objective_range_exempt[unit] == true
    end

    -- ----------------------------------------------------------------------------
    -- Objective system passes
    -- ----------------------------------------------------------------------------

    local function _track_mission_objective_units(system_name, interactee_map, enabled_by_kind, active_names,
                                                  require_active_objective, seen_units, default_kind, skip_units)
        local extension_map = _safe_unit_to_extension_map(system_name)

        if type(extension_map) ~= "table" then
            return
        end

        local has_actionable = nil
        local actionable_by_unit = nil

        if require_active_objective then
            has_actionable = _scratch_objective_has_actionable
            actionable_by_unit = _scratch_objective_actionable_by_unit
        end

        for unit, extension in pairs(extension_map) do
            local keep = not require_active_objective

            if require_active_objective then
                local objective_name = _safe_objective_target_name(extension)

                keep = objective_name ~= nil and active_names ~= nil and active_names[objective_name] == true

                -- Both filters below are guesses about which of an objective's
                -- units is the live one, and the game's own marker is not a
                -- guess. A unit it is currently pointing at is the live one
                -- whatever the flags say, so the marker overrides them.
                --
                -- Power Matrix files the elevator's call point and the platform
                -- it takes you to under one objective. Only the call point
                -- claims `_add_marker_on_objective_start`, so the platform was
                -- dropped as an alternative the mission had not chosen -- while
                -- the game was drawing an objective marker on it and the player
                -- was being sent there. This only ever adds a marker the game is
                -- already showing; nothing it used to draw stops being drawn.
                local game_marks_unit = _world_marker_units_available
                    and _scratch_world_marker_units[unit] ~= nil

                -- Except over a growth's demolition targets. The game marks each
                -- of them only to hang its three pointers at the tentacles off
                -- it, and they stand a fraction of a metre from the centre eye
                -- that claims the start marker, so on the radar the override
                -- stacked four markers on one spot. The tentacles carry markers
                -- of their own, so for these the start marker decides, as it did
                -- before the override. A centre eye that is itself a demolition
                -- target claims the start marker and is kept by it. A growth's
                -- alone: under any other objective a target styled that way is
                -- the thing to destroy, and the game's marker keeps it.
                if keep
                    and _scratch_objective_has_start_marker[objective_name] == true
                    and _scratch_start_marker_by_unit[unit] ~= true
                    -- Nor is a container still holding the objective's luggable:
                    -- lm_rails' lockers claim no start marker, and were dropped
                    -- until the player stood at one, with the canister inside
                    -- drawn in their place.
                    and LUGGABLE_HOLDER.holds[unit] ~= true
                    and (not game_marks_unit
                        or (_is_growth_objective_name(objective_name)
                            and _safe_objective_target_field(extension, "_ui_target_type") == "demolition")) then
                    -- An alternative the mission chose not to use.
                    keep = false
                end

                if keep and not game_marks_unit
                    and has_actionable[objective_name] == true
                    and actionable_by_unit[unit] ~= true then
                    keep = false
                end

                -- Applied to every objective target that is not an interactee.
                -- An interactee is shown before the game marks it, which is the
                -- whole point of the feature, but a target with no interaction
                -- has no prompt to be early for, and the game marks exactly the
                -- one that is live: a purge event files four dormant growth eyes
                -- and the active one under the same objective, all carrying
                -- health, and only the active one has a marker.
                --
                -- Only trusted for an objective the marker list has been seen to
                -- cover: if none of its units was ever marked the list does not
                -- describe this objective, and dropping them all would hide the
                -- step rather than retire it.
                if keep and interactee_map ~= nil and interactee_map[unit] == nil
                    and _world_marker_units_available then
                    if _objective_world_marker_seen[objective_name] == true then
                        keep = game_marks_unit
                    else
                        -- No unit of this objective has been marked yet. That is
                        -- either an objective the list does not describe, or one
                        -- whose markers have not been assigned yet, and the two
                        -- look identical. Hold the candidates back until the
                        -- settle window has passed rather than showing them all
                        -- for the first moments of an event.
                        local first_active = _objective_first_active_t[objective_name]
                        local now = _safe_gameplay_time()

                        if first_active ~= nil and now ~= nil
                            and now - first_active < OBJECTIVE_MARKER_SETTLE_SECONDS then
                            keep = false
                        end
                    end
                end

                -- Of a bank of identical containers under a luggable objective,
                -- only those holding a luggable. Only containers of a prefab
                -- found holding one: see LUGGABLE_HOLDER.
                if keep and LUGGABLE_HOLDER.objectives[objective_name] == true
                    and LUGGABLE_HOLDER.holds[unit] ~= true
                    and interactee_map ~= nil and interactee_map[unit] ~= nil then
                    local prefab = _luggable_holder_prefab(unit)
                    local containers = LUGGABLE_HOLDER.container_prefabs[objective_name]

                    if prefab ~= nil and containers ~= nil and containers[prefab] == true then
                        keep = false
                    end
                end
            end

            if keep and not (skip_units and skip_units[unit]) then
                local kind = _mission_objective_unit_kind(unit, interactee_map, default_kind)

                -- Generic interactables only: a puzzle device, a scan target or
                -- a servo skull keeps its own state. See _objective_marker_lapsed.
                if kind == "mission_objective_other" and interactee_map ~= nil and interactee_map[unit] ~= nil
                    and _objective_marker_lapsed(unit) then
                    kind = nil
                end

                _claim_mission_objective_unit(unit, kind, enabled_by_kind, seen_units)
            end
        end
    end

    -- ----------------------------------------------------------------------------
    -- Objective scan and reset
    -- ----------------------------------------------------------------------------

    -- Objective zones and targets are frequently not interactees at all, so they
    -- can never be reached through the interactee scan. This walks the objective
    -- systems directly and is the only path that can surface them.
    function _scan_mission_objective_targets(interactee_map)
        _objective_debug_logging = mod:get("debug_mode") == true

        local tracked_units = mod._tracked_units
        local seen_units = _scratch_seen_mission_objective_units
        local zone_units = _scratch_mission_objective_zone_units
        table_clear(seen_units)
        table_clear(zone_units)
        table_clear(_scratch_inactive_objective_units)
        -- Ahead of every pass, so an objective that has ended cannot leave an
        -- exemption behind and nothing survives a scan that does not re-earn it.
        table_clear(_scratch_objective_range_exempt)

        if _any_mission_objective_kind_enabled() then
            local enabled_by_kind = _scratch_mission_objective_kind_enabled
            local active_names = _refresh_active_objective_names()

            _refresh_objective_actionable_targets(_safe_unit_to_extension_map(MISSION_OBJECTIVE_TARGET_SYSTEM),
                interactee_map, active_names)

            _track_mission_objective_scan_zones(enabled_by_kind, active_names, seen_units, zone_units)

            for i = 1, MISSION_OBJECTIVE_DEDICATED_SOURCE_COUNT do
                local source = MISSION_OBJECTIVE_DEDICATED_SOURCES[i]

                _track_mission_objective_units(source.system, interactee_map, enabled_by_kind, nil, false, seen_units,
                    source.kind, nil)
            end

            -- Zone units also appear here; skipping them keeps the invisible
            -- trigger volumes off the radar.
            _track_mission_objective_units(MISSION_OBJECTIVE_TARGET_SYSTEM, interactee_map, enabled_by_kind,
                active_names, true, seen_units, nil, zone_units)

            -- Last, because these units are in no objective system at all and
            -- must not take a classification away from one that is.
            _track_growth_tentacle_units(enabled_by_kind, seen_units)
        end

        for unit, data in pairs(tracked_units) do
            if data and data.source == MISSION_OBJECTIVE_SOURCE and not seen_units[unit] then
                tracked_units[unit] = nil
            end
        end

        if _objective_debug_logging then
            _debug_log_untracked_objective_markers()
        end
    end

    -- Dropping the unit map keeps stale unit references out of the next mission.
    function _reset_mission_objective_marker_state()
        _reset_mission_objective_lifecycle()
        table_clear(_minigame_state_by_unit)
        table_clear(_minigame_meta_by_unit)
        table_clear(_mission_objective_kind_by_unit)
        table_clear(_scratch_active_objective_names)
        table_clear(_scratch_seen_mission_objective_units)
        table_clear(_scratch_mission_objective_zone_units)
        table_clear(_scratch_inactive_objective_units)
        table_clear(_scratch_growth_objective_units)
        table_clear(_scratch_destroy_objective_units)
        table_clear(LUGGABLE_HOLDER.objectives)
        table_clear(LUGGABLE_HOLDER.holds)
        table_clear(LUGGABLE_HOLDER.prefab_of)
        table_clear(LUGGABLE_HOLDER.container_prefabs)
        table_clear(LUGGABLE_HOLDER.units)
        table_clear(LUGGABLE_HOLDER.inside)
        table_clear(LUGGABLE_HOLDER.origin)
        table_clear(LUGGABLE_HOLDER.cargo)
        table_clear(LUGGABLE_HOLDER.socket_objective)
        LUGGABLE_HOLDER.active = false
        LUGGABLE_HOLDER.count = 0
        -- Keyed by objective name, which the next mission may reuse for an
        -- objective that is not a growth.
        table_clear(_growth_objective_by_name)
        -- The only one of the tentacle arrays that holds unit references.
        table_clear(GROWTH_EYE.units)
        table_clear(GROWTH_EYE.group_of)
        table_clear(GROWTH_EYE.member_units)
        table_clear(GROWTH_EYE.member_group)
        table_clear(GROWTH_EYE.prefab_of)
        GROWTH_EYE.member_count = 0
        GROWTH_EYE.group_next = 0
        table_clear(_scratch_world_marker_units)
        table_clear(_objective_world_marker_seen)
        table_clear(_objective_first_active_t)
        table_clear(_scratch_objective_has_start_marker)
        table_clear(_scratch_start_marker_by_unit)
        _world_marker_units_available = false

        -- The game's marker sets hold units too, and are otherwise only emptied
        -- by the next refresh, which never comes with every objective category
        -- switched off.
        if _clear_world_marker_units ~= nil then
            _clear_world_marker_units()
        end
    end

end
