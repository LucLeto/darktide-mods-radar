local mod = get_mod("Radar")
local Pickups = require("scripts/settings/pickup/pickups")
local PlayerUnitStatus = require("scripts/utilities/attack/player_unit_status")

local function _install(resource_path, env)
    local installer = mod:io_dofile(resource_path)

    if type(installer) ~= "function" then
        error(string.format("[Radar] Module `%s` did not return an installer function", tostring(resource_path)))
    end

    installer(env)
end

local shared_env = {
    mod = mod,
    Pickups = Pickups,
    PlayerUnitStatus = PlayerUnitStatus,
}

setmetatable(shared_env, { __index = _G })

_install("Radar/scripts/mods/Radar/Radar_enemy_definitions", shared_env)
_install("Radar/scripts/mods/Radar/Radar_runtime_helpers", shared_env)
_install("Radar/scripts/mods/Radar/Radar_expeditions", shared_env)
_install("Radar/scripts/mods/Radar/Radar_tracking", shared_env)

-- save scroll position
-- Author: Alfthebigheaded
local last_scroll_amount = 0
local last_category = nil

local function is_radar_category(self)
    local selected_category = self._selected_category
    if not selected_category then
        return false
    end

    return selected_category == mod:localize("mod_name")
end

mod:hook_safe(CLASS.BaseView, "on_exit", function(self)
    if self.view_name == "dmf_options_view" then
        last_category = nil
    end
end)

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

    --  Detect category switch into my mod
    if in_radar_category and (last_category ~= current_category or last_category == nil) then
        scrollbar_content.scroll_value = last_scroll_amount
        scrollbar_content.value = last_scroll_amount
    end

    --  Always track scroll while inside my mod
    if in_radar_category then
        local scroll_progress = settings_grid._scroll_progress
        if scroll_progress ~= nil and last_scroll_amount ~= scroll_progress then
            last_scroll_amount = scroll_progress
        end
    end

    last_category = current_category
end)

return mod
