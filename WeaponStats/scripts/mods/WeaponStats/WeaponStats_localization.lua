local mod = get_mod('WeaponStats')

mod:add_global_localize_strings({
    loc_weapon_stats_menu_button = {
        en = 'Weapon Stats',
    },
})

return {
    mod_name = {
        en = 'Weapon Stats',
    },
    mod_description = {
        en = 'Shows detailed weapon damage profiles, attack speed, crit, cleave, armor damage and more in the inventory.',
    },
    search_placeholder = {
        en = 'Search weapons...',
    },
    kind_ranged = {
        en = 'Ranged',
    },
    kind_melee = {
        en = 'Melee',
    },
}
