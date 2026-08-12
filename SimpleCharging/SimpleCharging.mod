return {
    run = function()
        fassert(rawget(_G, 'new_mod'), '`SimpleCharging` encountered an error loading the Darktide Mod Framework.')

        new_mod('SimpleCharging', {
            mod_script = 'SimpleCharging/scripts/mods/SimpleCharging/SimpleCharging',
            mod_data = 'SimpleCharging/scripts/mods/SimpleCharging/SimpleCharging_data',
            mod_localization = 'SimpleCharging/scripts/mods/SimpleCharging/SimpleCharging_localization',
        })
    end,
    packages = {},
    version = '0.0.9',
    mod_id = '1141',
}
