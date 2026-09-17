--- DMF entry script that builds Radar's shared runtime environment and installs its modules.
-- DMF runs this file as the `mod_script` named in `Radar.mod`; `Radar_data.lua` and
-- `Radar_localization.lua` are loaded by DMF from the same declaration.
--
-- Radar's runtime is split into installer modules. Each returns `function(env)` and runs its
-- body under `setfenv(1, env)` with the `shared_env` built here, so any global it assigns
-- (a `function _name` without `local`, an upper-case table) becomes visible to every other
-- installer. Locals stay private to their module. The install order is
--
-- 1. `Radar_enemy_definitions` (marker kind registries, enemy definitions)
-- 2. `Radar_runtime_helpers` (generic engine, runtime and HUD helpers)
-- 3. `Radar_tracking` (category-agnostic tracking and radar target collection)
-- 4. `Radar_players`, `Radar_pickups`, `Radar_mission_objectives`, `Radar_expeditions` and
--    `Radar_events` (feature modules)
-- 5. `Radar_navmesh` (live map geometry source)
--
-- The order only matters for code that runs while a module installs; shared functions are
-- looked up in `shared_env` when called, so a module may call one installed after it.
-- `Radar_tracking` registers the HUD element (`ui/Radar_hud_element.lua`), which reaches the
-- runtime through `mod` methods only. `compatibility/Radar_strikemap.lua` is loaded last as an
-- explicit module that registers its own callbacks.
--
-- This file also keeps the scroll position of Radar's category in the DMF options view.
-- module: Radar
-- author: LucLeto
-- author: Alfthebigheaded
local mod = get_mod("Radar")
local Pickups = require("scripts/settings/pickup/pickups")
local PlayerUnitStatus = require("scripts/utilities/attack/player_unit_status")
local PlayerUnitVisualLoadout = require("scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout")
local CompanionServoSkullSettings = require("scripts/settings/companion/companion_servo_skull_settings")

--- Runs one runtime installer module inside the shared environment.
-- `mod:io_dofile` executes the file and returns its chunk result, which must be the
-- installer function; anything else is a packaging error and aborts loading the mod.
-- string: resource_path DMF resource path of the installer, without extension
-- tab: env shared runtime environment handed to the installer
local function _install(resource_path, env)
    local installer = mod:io_dofile(resource_path)

    if type(installer) ~= "function" then
        error(string.format("[Radar] Module `%s` did not return an installer function", tostring(resource_path)))
    end

    installer(env)
end

--- Shared runtime environment that every installer module runs in.
-- Globals assigned by installers land here instead of in `_G`, which is how the runtime
-- modules share functions, constants and state. Reads fall back to `_G` through the
-- metatable, so engine and game globals stay reachable. The game modules listed here are
-- required once for all installers.
local shared_env = {
    mod = mod,
    Pickups = Pickups,
    PlayerUnitStatus = PlayerUnitStatus,
    PlayerUnitVisualLoadout = PlayerUnitVisualLoadout,
    CompanionServoSkullSettings = CompanionServoSkullSettings,
}

setmetatable(shared_env, { __index = _G })

_install("Radar/scripts/mods/Radar/Radar_enemy_definitions", shared_env)
_install("Radar/scripts/mods/Radar/Radar_runtime_helpers", shared_env)
_install("Radar/scripts/mods/Radar/Radar_tracking", shared_env)

_install("Radar/scripts/mods/Radar/Radar_players", shared_env)
_install("Radar/scripts/mods/Radar/Radar_pickups", shared_env)
_install("Radar/scripts/mods/Radar/Radar_mission_objectives", shared_env)
_install("Radar/scripts/mods/Radar/Radar_expeditions", shared_env)
_install("Radar/scripts/mods/Radar/Radar_events", shared_env)

_install("Radar/scripts/mods/Radar/Radar_navmesh", shared_env)

mod:io_dofile("Radar/scripts/mods/Radar/compatibility/Radar_strikemap")

--- Scroll state of Radar's category in the DMF options view.
-- Remembered so that returning to Radar's long settings list restores the previous
-- position instead of jumping back to the top. Contributed by Alfthebigheaded.
local last_scroll_amount = 0
local last_category = nil

--- Returns whether the DMF options view currently shows Radar's settings category.
-- DMF names each category after the mod's localized display name.
-- tab: self DMF options view instance
-- treturn: bool true while Radar's category is selected
local function is_radar_category(self)
    local selected_category = self._selected_category
    if not selected_category then
        return false
    end

    return selected_category == mod:localize("mod_name")
end

-- Forgets the selected category when the DMF options view closes, so the next visit
-- counts as entering Radar's category and restores the remembered scroll position.
mod:hook_safe(CLASS.BaseView, "on_exit", function(self)
    if self.view_name == "dmf_options_view" then
        last_category = nil
    end
end)

-- Restores the remembered scroll position when Radar's category is entered and keeps
-- recording it while the category stays selected. Navigation grid 2 is the settings
-- list of the DMF options view.
mod:hook_safe(CLASS.BaseView, "update", function(self)
    if self.view_name ~= "dmf_options_view" then
        return
    end

    local navigation_grids = self._navigation_grids
    if not navigation_grids then
        return
    end

    local settings_grid = navigation_grids[2]
    if not settings_grid then
        return
    end

    local scrollbar_widget = settings_grid._scrollbar_widget
    local scrollbar_content = scrollbar_widget and scrollbar_widget.content
    if not scrollbar_content then
        return
    end

    local current_category = self._selected_category
    local in_radar_category = is_radar_category(self)

    if in_radar_category and (last_category ~= current_category or last_category == nil) then
        scrollbar_content.scroll_value = last_scroll_amount
        scrollbar_content.value = last_scroll_amount
    end

    if in_radar_category then
        local scroll_progress = settings_grid._scroll_progress
        if scroll_progress ~= nil and last_scroll_amount ~= scroll_progress then
            last_scroll_amount = scroll_progress
        end
    end

    last_category = current_category
end)

return mod
