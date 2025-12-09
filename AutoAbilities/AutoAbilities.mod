return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`AutoAbilities` encountered an error loading the Darktide Mod Framework.")

		new_mod("AutoAbilities", {
			mod_script       = "AutoAbilities/scripts/mods/AutoAbilities/AutoAbilities",
			mod_data         = "AutoAbilities/scripts/mods/AutoAbilities/AutoAbilities_data",
			mod_localization = "AutoAbilities/scripts/mods/AutoAbilities/AutoAbilities_localization",
		})
	end,
	packages = {},
}
