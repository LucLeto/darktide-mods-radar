return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Radar` encountered an error loading the Darktide Mod Framework.")

		new_mod("Radar", {
			mod_script       = "Radar/scripts/mods/Radar/Radar",
			mod_data         = "Radar/scripts/mods/Radar/Radar_data",
			mod_localization = "Radar/scripts/mods/Radar/Radar_localization",
		})
	end,
	packages = {},
	load_after = {
		"Alfs_DMF_Extensions",
	},
	version = "2.5.0",
	mod_id = "790",
}
