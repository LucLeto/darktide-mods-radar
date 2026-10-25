--- Nearby highlight outlines, drawn on the target units of groups set to Outlines.
-- The game outlines a unit by switching a material layer on, colouring it through the layer's
-- `outline_color` variable and keeping the unit out of culling while the layer shows, which is
-- what its `OutlineSystem` does for minions. A prop has no outline layer of its own, so the first
-- time Radar outlines a unit it adds one built from the game's minion outline material. The
-- layer then stays on the unit for its lifetime and is only switched on and off. A unit that
-- cannot take the layer (no meshes, or the engine refuses it) is remembered for the mission and
-- keeps its highlight bracket. A unit a player carries is never outlined. An outline covers
-- every mesh of a unit, including hidden meshes and ones the game never draws, so on units where
-- those showed (hanging hazard barrels, Heretic Idols) the layer is limited to the meshes of their
-- visible shape.
--
-- The colour is written again every time an outline is switched on, to the unit and to its
-- child units, as the game's `OutlineSystem` does; a colour written only while the layer was off
-- showed the material's default instead. Culling is switched off again twice a second while an
-- outline shows, since other code (another mod's tag outline being removed, the game's own
-- outlines) can switch it back on, which hides the outline behind walls.
--
-- `_collect_screen_highlight_targets` marks every target it outlines in a scan through
-- `_mark_highlight_outline`, and tracking calls `_sync_highlight_outlines` after the collection,
-- which shows what was marked and switches off what was not. While only visible targets are
-- highlighted, the HUD element calls `mod:update_highlight_outline_visibility` every frame, which
-- hides an outline while level geometry blocks the view of its unit, unless a player has tagged
-- the unit. No outline shows during a cinematic, and every outline is switched off when the radar
-- stops, the mission ends or Radar is disabled or unloaded.
--
-- Installer module, installed last into Radar's shared runtime environment (see `Radar.lua`).
-- Contributes `_mark_highlight_outline`, `_sync_highlight_outlines`, `_clear_highlight_outlines`,
-- `_reset_highlight_outlines` and `mod:update_highlight_outline_visibility`, and chains
-- `mod.on_disabled` and `mod.on_unload`. Relies on `_safe_unit_alive`, `_safe_extension_system`,
-- `_safe_unit_outline_extension`, `_safe_gameplay_time`, `_log_once`, the HUD camera and the HUD
-- line-of-sight test from `Radar_runtime_helpers.lua`, and on
-- `mod:is_nearby_highlight_visible_only` from `Radar_tracking.lua`.
-- module: Radar_highlight_outlines
-- author: LucLeto
return function(env)
    setfenv(1, env)

    local mod = mod
    local next = next
    local pairs = pairs
    local pcall = pcall
    local tostring = tostring
    local type = type

    local table_clear = table.clear or function(t)
        for k in pairs(t) do
            t[k] = nil
        end
    end

    -- ----------------------------------------------------------------------------
    -- Constants
    -- ----------------------------------------------------------------------------

    --- Material layer Radar adds to an outlined unit; also the unit data key marking that the unit has it.
    local OUTLINE_LAYER = "radar_highlight_outline"

    --- Game material the layer is built from, the one minions are outlined with.
    -- It ships in `packages/boot_assets`, so it is loaded whenever a mission is.
    local OUTLINE_MATERIAL = "content/characters/materials/minion_outline"

    --- Material variable holding the outline colour, as RGB from 0 to 1.
    local OUTLINE_COLOR_VARIABLE = "outline_color"

    --- Levels of child units below an outlined unit that get its colour too.
    local OUTLINE_CHILD_DEPTH = 2

    --- Seconds between two passes switching culling off again for every shown outline.
    local OUTLINE_CULLING_REFRESH_INTERVAL = 0.5

    --- Locomotion state of a luggable a player is carrying.
    local CARRIED_LOCOMOTION_STATE = "carried"

    --- Meshes the outline layer is limited to, by the root node of the unit they belong to.
    -- The names were read from the units' resources. A hanging hazard barrel (`rp_hazard_sphere_01`)
    -- keeps the meshes of its exploded state hidden in a `broken` visibility group, which a layer
    -- on every mesh drew as arcs around it; its sphere, ceiling mount and cables are listed, its
    -- decals are not. A Heretic Idol, standing (`rp_collectible_destructible_01`) or hanging
    -- (`rp_collectible_destructible_01_hanging`), carries a glow box and a convex collision hull,
    -- which drew a box of flat planes around it; its body's four levels of detail are listed.
    local OUTLINE_MESHES_BY_ROOT_NODE = {
        rp_hazard_sphere_01 = {
            "g_hazard_sphere_01",
            "g_top",
            "g_hazard_sphere_cables_01",
            "g_hazard_sphere_dynamic_cable_01",
        },
        rp_collectible_destructible_01 = {
            "g_collectible_destructible_01_body",
            "g_collectible_destructible_01_body_LOD1",
            "g_collectible_destructible_01_body_LOD2",
            "g_collectible_destructible_01_body_LOD3",
        },
        rp_collectible_destructible_01_hanging = {
            "g_collectible_destructible_01_hanging_body",
            "g_collectible_destructible_01_hanging_body_LOD1",
            "g_collectible_destructible_01_hanging_body_LOD2",
            "g_collectible_destructible_01_hanging_body_LOD3",
        },
    }

    -- ----------------------------------------------------------------------------
    -- Mutable runtime state
    -- ----------------------------------------------------------------------------

    --- Outlined units and their records.
    -- A record holds whether the layer is on (`shown`), whether the last occlusion test hid the
    -- unit (`occluded`), whether a player has tagged it (`tagged`), its colour channels (`red`,
    -- `green`, `blue`), the position the occlusion test aims at (`anchor`) and the scan pass that
    -- last marked the unit (`pass`).
    local _outline_by_unit = {}

    --- Units that cannot take the outline layer this mission, which keep their bracket.
    local _outline_refused_units = {}

    --- Number of the scan pass the collection is marking, advanced by every sync.
    local _outline_pass = 0

    --- Whether the last sync found a cinematic playing, which hides every outline.
    local _outline_cinematic_active = false

    --- Gameplay time from which the next sync switches culling off again for every shown outline.
    local _outline_next_culling_refresh_t = 0

    -- ----------------------------------------------------------------------------
    -- Engine helpers
    -- ----------------------------------------------------------------------------

    --- Returns whether a cinematic is playing, during which the game hides its own outlines too.
    -- treturn: bool
    local function _is_cinematic_active()
        local managers = Managers
        local cinematic_manager = managers and managers.state and managers.state.cinematic
        local cinematic_active = cinematic_manager and cinematic_manager.cinematic_active

        if cinematic_active then
            local ok, active = pcall(cinematic_active, cinematic_manager)

            if ok and active then
                return true
            end
        end

        local cinematic_scene_system = _safe_extension_system("cinematic_scene_system")
        local is_active = cinematic_scene_system and cinematic_scene_system.is_active

        if not is_active then
            return false
        end

        local ok, active = pcall(is_active, cinematic_scene_system)

        return ok and active == true
    end

    --- Returns whether a player is carrying a unit, read from the luggable's locomotion state.
    -- A carried luggable hangs from the player's hands, and an outline there would sit in the
    -- middle of the first-person view.
    -- !Unit: unit live unit
    -- treturn: bool
    local function _is_unit_carried(unit)
        local script_unit = ScriptUnit
        local has_extension = script_unit and script_unit.has_extension

        if not has_extension then
            return false
        end

        local ok, locomotion = pcall(has_extension, unit, "locomotion_system")
        local current_state = ok and type(locomotion) == "table" and locomotion.current_state or nil

        if type(current_state) ~= "function" then
            return false
        end

        local ok_state, state = pcall(current_state, locomotion)

        return ok_state and state == CARRIED_LOCOMOTION_STATE
    end

    --- Returns the meshes an outline on a unit is limited to and the root node that lists them, nil for every mesh.
    -- tab: unit_api engine `Unit` table
    -- !Unit: unit live unit
    -- treturn: ?tab mesh names
    -- treturn: ?string root node the names are listed under
    local function _find_outline_meshes(unit_api, unit)
        local has_node = unit_api.has_node

        if not has_node then
            return nil
        end

        for root_node, meshes in pairs(OUTLINE_MESHES_BY_ROOT_NODE) do
            local ok, found = pcall(has_node, unit, root_node)

            if ok and found then
                return meshes, root_node
            end
        end

        return nil
    end

    --- Returns whether a unit has meshes an outline can be drawn on, true when the engine cannot say.
    local function _unit_has_meshes(unit_api, unit)
        local num_meshes = unit_api.num_meshes

        if not num_meshes then
            return true
        end

        local ok, count = pcall(num_meshes, unit)

        return not ok or type(count) ~= "number" or count > 0
    end

    --- Gives a unit the outline layer, switched off, unless it already carries it.
    -- The layer is added once per unit lifetime and marked in the unit's script data, so
    -- reloading Radar never adds a second one.
    -- !Unit: unit live unit
    -- treturn: bool whether the unit carries the layer
    local function _ensure_outline_layer(unit)
        local unit_api = Unit

        if not unit_api then
            return false
        end

        local get_data = unit_api.get_data
        local set_data = unit_api.set_data
        local add_material_layer = unit_api.add_material_layer
        local set_material_layer = unit_api.set_material_layer

        if not get_data or not set_data or not add_material_layer or not set_material_layer then
            return false
        end

        local ok_data, has_layer = pcall(get_data, unit, OUTLINE_LAYER)

        if ok_data and has_layer == true then
            return true
        end

        if not _unit_has_meshes(unit_api, unit) then
            return false
        end

        local added = false
        local meshes, root_node = _find_outline_meshes(unit_api, unit)

        -- The sixth argument limits the layer to the listed meshes; the fifth is unknown and stays
        -- nil. Should the engine reject the list, the layer goes on every mesh instead.
        if meshes ~= nil then
            local ok, err = pcall(add_material_layer, unit, OUTLINE_LAYER, OUTLINE_MATERIAL, true, nil, meshes)

            added = ok

            if not ok then
                _log_once("outline_mesh_list_rejected:" .. root_node,
                    "Outline mesh list of " .. root_node .. " rejected, outlined on every mesh: " .. tostring(err))
            end
        end

        if not added and not pcall(add_material_layer, unit, OUTLINE_LAYER, OUTLINE_MATERIAL, true) then
            return false
        end

        pcall(set_data, unit, OUTLINE_LAYER, true)
        pcall(set_material_layer, unit, OUTLINE_LAYER, false)

        return true
    end

    --- Writes an outline colour into a unit's outline layer and those of its child units.
    -- A unit without the layer simply rejects the write.
    -- func: set_vector3_for_material engine setter
    -- ?func: get_child_units engine child unit getter
    -- !Unit: unit unit to colour
    -- param: color `Vector3` colour
    -- int: depth levels of child units still to colour
    local function _write_outline_color_tree(set_vector3_for_material, get_child_units, unit, color, depth)
        pcall(set_vector3_for_material, unit, OUTLINE_LAYER, OUTLINE_COLOR_VARIABLE, color)

        if depth <= 0 or not get_child_units then
            return
        end

        local ok, children = pcall(get_child_units, unit)

        if not ok or type(children) ~= "table" then
            return
        end

        for i = 1, #children do
            _write_outline_color_tree(set_vector3_for_material, get_child_units, children[i], color, depth - 1)
        end
    end

    --- Writes a record's colour into its unit's outline layer.
    -- !Unit: unit outlined unit
    -- tab: record outline record of the unit
    local function _write_outline_color(unit, record)
        local unit_api = Unit
        local set_vector3_for_material = unit_api and unit_api.set_vector3_for_material

        if not set_vector3_for_material or not Vector3 then
            return
        end

        _write_outline_color_tree(set_vector3_for_material, unit_api.get_child_units, unit,
            Vector3(record.red / 255, record.green / 255, record.blue / 255), OUTLINE_CHILD_DEPTH)
    end

    --- Switches a unit's outline layer on or off and keeps its culling in line, as the game's outlines do.
    -- Switching it on writes the colour again. Culling is restored only while the game's own
    -- outline system shows nothing on the unit, since that system switches culling off for its
    -- outlines too.
    -- !Unit: unit outlined unit
    -- tab: record outline record of the unit
    -- bool: shown whether the outline shows
    local function _set_outline_shown(unit, record, shown)
        if record.shown == shown then
            return
        end

        record.shown = shown

        local unit_api = Unit

        if not unit_api or not _safe_unit_alive(unit) then
            return
        end

        local set_material_layer = unit_api.set_material_layer
        local set_unit_culling = unit_api.set_unit_culling

        if set_material_layer then
            pcall(set_material_layer, unit, OUTLINE_LAYER, shown)
        end

        if shown then
            _write_outline_color(unit, record)
        end

        if not set_unit_culling then
            return
        end

        if shown then
            pcall(set_unit_culling, unit, false, true)
            return
        end

        local game_outline = _safe_unit_outline_extension(unit)

        if not (game_outline and game_outline.visible_material_layers) then
            pcall(set_unit_culling, unit, true, true)
        end
    end

    --- Stores an ARGB colour in a record, and writes it to a shown outline when its RGB channels changed.
    -- A hidden outline gets the colour when it is switched on.
    -- !Unit: unit outlined unit
    -- tab: record outline record of the unit
    -- tab: color ARGB colour array
    local function _update_outline_color(unit, record, color)
        local red = color[2] or 255
        local green = color[3] or 255
        local blue = color[4] or 255

        if record.red == red and record.green == green and record.blue == blue then
            return
        end

        record.red = red
        record.green = green
        record.blue = blue

        if record.shown then
            _write_outline_color(unit, record)
        end
    end

    --- Switches culling off again for every shown outline whose unit is still alive.
    local function _refresh_outline_culling()
        local unit_api = Unit
        local set_unit_culling = unit_api and unit_api.set_unit_culling

        if not set_unit_culling then
            return
        end

        for unit, record in pairs(_outline_by_unit) do
            if record.shown and _safe_unit_alive(unit) then
                pcall(set_unit_culling, unit, false, true)
            end
        end
    end

    -- ----------------------------------------------------------------------------
    -- Scan pass
    -- ----------------------------------------------------------------------------

    --- Marks a highlight target's unit as outlined in the current scan pass.
    -- Gives the unit its record and outline layer on first contact and keeps its colour. A new
    -- record starts as occluded, so while only visible targets are highlighted its outline
    -- appears once the HUD has seen the unit, never through a wall first; a tagged unit shows
    -- through walls anyway. A unit a player carries is left unmarked, so its outline goes off,
    -- and it gets no bracket either.
    -- ?Unit: unit target unit
    -- tab: color ARGB highlight colour
    -- tab: anchor `{ x, y, z }` position the occlusion test aims at
    -- ?bool: tagged whether a player has tagged the target
    -- treturn: bool whether the target is outlined or carried; false keeps the target's bracket
    function _mark_highlight_outline(unit, color, anchor, tagged)
        if unit == nil or _outline_refused_units[unit] or not _safe_unit_alive(unit) then
            return false
        end

        if _is_unit_carried(unit) then
            return true
        end

        local record = _outline_by_unit[unit]

        if record == nil then
            if not _ensure_outline_layer(unit) then
                _outline_refused_units[unit] = true
                return false
            end

            record = {
                shown = false,
                occluded = true,
                tagged = false,
                red = -1,
                green = -1,
                blue = -1,
                anchor = anchor,
                pass = _outline_pass,
            }
            _outline_by_unit[unit] = record
        end

        record.anchor = anchor
        record.pass = _outline_pass
        record.tagged = tagged == true
        _update_outline_color(unit, record, color)

        return true
    end

    --- Shows the units marked in this scan pass, and switches off and forgets every other one.
    -- A marked outline shows unless a cinematic is playing or, while only visible targets are
    -- highlighted, the last occlusion test hid its untagged unit. Twice a second the shown
    -- outlines get culling switched off again. Called by tracking once per scan, right after the
    -- highlight collection.
    function _sync_highlight_outlines()
        local pass = _outline_pass

        _outline_pass = pass + 1

        if next(_outline_by_unit) == nil then
            return
        end

        local visible_only = mod:is_nearby_highlight_visible_only()
        local cinematic_active = _is_cinematic_active()

        _outline_cinematic_active = cinematic_active

        for unit, record in pairs(_outline_by_unit) do
            if record.pass ~= pass then
                _set_outline_shown(unit, record, false)
                _outline_by_unit[unit] = nil
            else
                _set_outline_shown(unit, record,
                    not cinematic_active and not (visible_only and not record.tagged and record.occluded))
            end
        end

        local t = _safe_gameplay_time()

        if t ~= nil and t >= _outline_next_culling_refresh_t then
            _outline_next_culling_refresh_t = t + OUTLINE_CULLING_REFRESH_INTERVAL
            _refresh_outline_culling()
        end
    end

    --- Switches every outline off and forgets the outlined units; the refused units are kept.
    function _clear_highlight_outlines()
        if next(_outline_by_unit) == nil then
            return
        end

        for unit, record in pairs(_outline_by_unit) do
            _set_outline_shown(unit, record, false)
            _outline_by_unit[unit] = nil
        end
    end

    --- Switches every outline off and forgets the outlined and the refused units, for a new mission.
    function _reset_highlight_outlines()
        _clear_highlight_outlines()
        table_clear(_outline_refused_units)
        _outline_cinematic_active = false
        _outline_next_culling_refresh_t = 0
    end

    --- Hides each untagged outline while level geometry blocks the view of its unit, and shows it again in view.
    -- Called by the HUD element every frame while only visible targets are highlighted. A tagged
    -- unit shows through walls without a test. The test is the game's own interaction marker
    -- line-of-sight check, which ignores the unit's own collider that an anchor inside the prop
    -- would always hit.
    -- tab: hud_element HUD element whose camera is used
    -- ?tab: fallback_camera_position camera position used without a HUD camera
    function mod:update_highlight_outline_visibility(hud_element, fallback_camera_position)
        if next(_outline_by_unit) == nil then
            return
        end

        local camera_position = self:get_hud_player_camera_position(hud_element) or fallback_camera_position

        if not camera_position then
            return
        end

        local is_hidden = self.is_hud_target_hidden_by_geometry
        local cinematic_active = _outline_cinematic_active

        for unit, record in pairs(_outline_by_unit) do
            local occluded = false

            if not record.tagged then
                local ok, hidden = pcall(is_hidden, self, camera_position, record.anchor, unit)

                occluded = ok and hidden == true
            end

            record.occluded = occluded

            if not cinematic_active then
                _set_outline_shown(unit, record, not occluded)
            end
        end
    end

    -- ----------------------------------------------------------------------------
    -- DMF callbacks
    -- ----------------------------------------------------------------------------

    local previous_on_disabled = mod.on_disabled

    --- DMF callback, chained after any previously installed handler; switches every outline off.
    -- Radar's update stops while it is disabled, so nothing else would.
    -- param: ... DMF arguments, forwarded to the previous handler
    mod.on_disabled = function(...)
        if previous_on_disabled then
            previous_on_disabled(...)
        end

        _clear_highlight_outlines()
    end

    local previous_on_unload = mod.on_unload

    --- DMF callback run before Radar is unloaded or reloaded, chained after any previously installed handler.
    -- Switches every outline off; the layers stay on their units and are found again after a reload.
    -- param: ... DMF arguments, forwarded to the previous handler
    mod.on_unload = function(...)
        if previous_on_unload then
            previous_on_unload(...)
        end

        _clear_highlight_outlines()
    end

end
