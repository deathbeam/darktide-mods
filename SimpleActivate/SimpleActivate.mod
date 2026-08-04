return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`SimpleActivate` encountered an error loading the Darktide Mod Framework.")

		new_mod("SimpleActivate", {
			mod_script       = "SimpleActivate/scripts/mods/SimpleActivate/SimpleActivate",
			mod_data         = "SimpleActivate/scripts/mods/SimpleActivate/SimpleActivate_data",
			mod_localization = "SimpleActivate/scripts/mods/SimpleActivate/SimpleActivate_localization",
		})
	end,
	packages = {},
	version = '0.0.1',
    mod_id = '1145',
}
