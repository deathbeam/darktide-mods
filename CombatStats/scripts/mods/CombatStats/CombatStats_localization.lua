local mod = get_mod('CombatStats')

-- Register global localization strings (for input legend, etc.)
mod:add_global_localize_strings({
    loc_combat_stats_reset_stats = {
        en = 'Reset Stats',
    },
})

return {
    mod_name = {
        en = 'Combat Stats',
    },
    mod_description = {
        en = 'Track detailed combat statistics including damage, kills, buff uptime, and more.',
    },
    show_hud_overlay = {
        en = 'Show Overlay',
    },
    show_hud_overlay_tooltip = {
        en = 'Display the minimal stats overlay during combat.',
    },
    enable_in_missions = {
        en = 'Enable in Missions',
    },
    enable_in_missions_tooltip = {
        en = 'Enables stat tracking while in missions.',
    },
    enable_in_hub = {
        en = 'Enable in Hub',
    },
    enable_in_hub_tooltip = {
        en = 'Shows stats from last session while in the hub area.',
    },
    toggle_view_keybind = {
        en = 'Toggle Stats View',
    },

    -- Common Stats
    time = {
        en = 'Time',
    },
    kills = {
        en = 'Kills',
    },
    dps = {
        en = 'DPS',
    },
    damage = {
        en = 'Damage',
    },
    hits = {
        en = 'Hits',
    },
    total = {
        en = 'Total',
    },
    melee = {
        en = 'Melee',
    },
    ranged = {
        en = 'Ranged',
    },
    explosion = {
        en = 'Explosion',
    },
    companion = {
        en = 'Companion',
    },
    buff = {
        en = 'Buff',
    },
    crit = {
        en = 'Crit',
    },
    weakspot = {
        en = 'Weakspot',
    },
    bleed = {
        en = 'Bleed',
    },
    burn = {
        en = 'Burn',
    },
    toxin = {
        en = 'Toxin',
    },
    enemy = {
        en = 'Enemy',
    },

    -- View
    combat_stats_view_title = {
        en = 'Combat Statistics',
    },
    search_placeholder = {
        en = 'Search enemies...',
    },
    overall_stats = {
        en = 'Overall Stats',
    },
    damage_stats = {
        en = 'Damage Stats',
    },
    hit_stats = {
        en = 'Hit Stats',
    },
    buff_uptime = {
        en = 'Buff Uptime',
    },

    -- Status
    in_progress = {
        en = 'IN PROGRESS',
    },
    killed = {
        en = 'KILLED',
    },

    -- Breed Types
    breed_monster = {
        en = 'monster',
    },
    breed_ritualist = {
        en = 'ritualist',
    },
    breed_disabler = {
        en = 'disabler',
    },
    breed_special = {
        en = 'special',
    },
    breed_elite = {
        en = 'elite',
    },
    breed_horde = {
        en = 'horde',
    },
    breed_unknown = {
        en = 'unknown',
    },
}
