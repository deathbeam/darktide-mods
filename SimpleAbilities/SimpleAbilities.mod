return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`SimpleAbilities` encountered an error loading the Darktide Mod Framework.")

		new_mod("SimpleAbilities", {
			mod_script       = "SimpleAbilities/scripts/mods/SimpleAbilities/SimpleAbilities",
			mod_data         = "SimpleAbilities/scripts/mods/SimpleAbilities/SimpleAbilities_data",
			mod_localization = "SimpleAbilities/scripts/mods/SimpleAbilities/SimpleAbilities_localization",
		})
	end,
	packages = {},
	version = "0.0.1",
}
