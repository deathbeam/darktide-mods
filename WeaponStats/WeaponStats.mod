return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`WeaponStats` encountered an error loading the Darktide Mod Framework.")

		new_mod("WeaponStats", {
			mod_script       = "WeaponStats/scripts/mods/WeaponStats/WeaponStats",
			mod_data         = "WeaponStats/scripts/mods/WeaponStats/WeaponStats_data",
			mod_localization = "WeaponStats/scripts/mods/WeaponStats/WeaponStats_localization",
		})
	end,
	packages = {},
}
