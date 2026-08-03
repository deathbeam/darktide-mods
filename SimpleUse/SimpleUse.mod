return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`SimpleUse` encountered an error loading the Darktide Mod Framework.")

		new_mod("SimpleUse", {
			mod_script       = "SimpleUse/scripts/mods/SimpleUse/SimpleUse",
			mod_data         = "SimpleUse/scripts/mods/SimpleUse/SimpleUse_data",
			mod_localization = "SimpleUse/scripts/mods/SimpleUse/SimpleUse_localization",
		})
	end,
	packages = {},
	version = "0.0.1",
}
