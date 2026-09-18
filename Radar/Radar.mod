return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Radar` encountered an error loading the Darktide Mod Framework.")

		new_mod("Radar", {
			mod_script       = "Radar/scripts/mods/Radar/Radar",
			mod_data         = "Radar/scripts/mods/Radar/Radar_data",
			mod_localization = "Radar/scripts/mods/Radar/Radar_localization",
		})
	end,
	packages = {
		"packages/ui/views/inventory_view/inventory_view",
		"packages/ui/views/inventory_weapons_view/inventory_weapons_view",
		"packages/ui/hud/player_weapon/player_weapon",
		"packages/ui/views/inventory_background_view/inventory_background_view",
		"packages/ui/views/inventory_weapon_details_view/inventory_weapon_details_view",
		"packages/ui/views/inventory_weapon_marks_view/inventory_weapon_marks_view",
		"packages/ui/views/main_menu_view/main_menu_view",
		"packages/ui/views/player_character_options_view/player_character_options_view",
		"packages/ui/views/talent_builder_view/talent_builder_view",
		"packages/ui/views/live_events_view/live_events_view",
		"packages/content/live_events/saints/live_event_saints_ui_assets",
		"packages/content/live_events/skulls/live_event_skulls_ui_assets",
		"packages/ui/views/group_finder_view/group_finder_view",
		"packages/ui/views/mission_board_view/mission_board_view",
		"packages/ui/views/scanner_display_view/scanner_display_view",
		"packages/ui/material_sets/circumstances",
		"packages/ui/views/crafting_view/crafting_view",
		"packages/ui/views/penance_overview_view/penance_overview_view",
		"packages/ui/views/expedition_view/expedition_view",
		"packages/ui/views/end_player_view/end_player_view",
	},
}
