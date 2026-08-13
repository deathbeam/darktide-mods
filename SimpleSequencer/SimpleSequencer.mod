return {
    run = function()
        fassert(rawget(_G, 'new_mod'), '`SimpleSequencer` encountered an error loading the Darktide Mod Framework.')

        new_mod('SimpleSequencer', {
            mod_script = 'SimpleSequencer/scripts/mods/SimpleSequencer/SimpleSequencer',
            mod_data = 'SimpleSequencer/scripts/mods/SimpleSequencer/SimpleSequencer_data',
            mod_localization = 'SimpleSequencer/scripts/mods/SimpleSequencer/SimpleSequencer_localization',
        })
    end,
    packages = {},
    version = '0.0.8',
    mod_id = '1160',
}
