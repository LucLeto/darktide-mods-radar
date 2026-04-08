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

return mod
