return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`CombatStats` encountered an error loading the Darktide Mod Framework.")

		new_mod("CombatStats", {
			mod_script       = "CombatStats/scripts/mods/CombatStats/CombatStats",
			mod_data         = "CombatStats/scripts/mods/CombatStats/CombatStats_data",
			mod_localization = "CombatStats/scripts/mods/CombatStats/CombatStats_localization",
		})
	end,
	packages = {},
}
