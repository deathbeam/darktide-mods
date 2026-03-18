return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`SimpleMovement` encountered an error loading the Darktide Mod Framework.")

		new_mod("SimpleMovement", {
			mod_script       = "SimpleMovement/scripts/mods/SimpleMovement/SimpleMovement",
			mod_localization = "SimpleMovement/scripts/mods/SimpleMovement/SimpleMovement_localization",
		})
	end,
	packages = {},
}
