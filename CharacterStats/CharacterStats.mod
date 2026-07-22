return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`CharacterStats` encountered an error loading the Darktide Mod Framework.")

		new_mod("CharacterStats", {
			mod_script       = "CharacterStats/scripts/mods/CharacterStats/CharacterStats",
			mod_data         = "CharacterStats/scripts/mods/CharacterStats/CharacterStats_data",
			mod_localization = "CharacterStats/scripts/mods/CharacterStats/CharacterStats_localization",
		})
	end,
	packages = {},
	version = "0.0.1",
    mod_id = "1093"
}
