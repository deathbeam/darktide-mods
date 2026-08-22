return {
	run = function()
		fassert(rawget(_G, 'new_mod'), '`EnemyStats` encountered an error loading the Darktide Mod Framework.')

		new_mod('EnemyStats', {
			mod_script = 'EnemyStats/scripts/mods/EnemyStats/EnemyStats',
			mod_data = 'EnemyStats/scripts/mods/EnemyStats/EnemyStats_data',
			mod_localization = 'EnemyStats/scripts/mods/EnemyStats/EnemyStats_localization',
		})
	end,
	packages = {},
}
