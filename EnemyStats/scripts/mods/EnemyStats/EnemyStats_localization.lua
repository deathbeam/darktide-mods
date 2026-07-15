local mod = get_mod('EnemyStats')

mod:add_global_localize_strings({
    loc_enemy_stats_menu_button = {
        en = 'Enemy Stats',
    },
})

return {
    mod_name = {
        en = 'Enemy Stats',
    },
    mod_description = {
        en = 'Shows enemy health, hit mass, armor and weakspots across all difficulties and havoc ranks.',
    },

    -- Config
    toggle_view_keybind = {
        en = 'Toggle Stats View',
    },

    -- Section headers
    header_info = {
        en = 'ENEMY INFO',
    },
    header_health = {
        en = 'HEALTH',
    },
    header_hit_zones = {
        en = 'HIT ZONES',
    },

    -- View
    search_placeholder = {
        en = 'Search enemies...',
    },
    kind_regular = {
        en = 'Infantry',
    },
    kind_elite = {
        en = 'Elite',
    },
    kind_specialist = {
        en = 'Specialist',
    },
    kind_boss = {
        en = 'Monstrosity',
    },

    -- Size class
    size_human = {
        en = 'Human-sized',
    },
    size_ogryn = {
        en = 'Ogryn-sized',
    },
    size_monster = {
        en = 'Monster',
    },

    -- Combat role
    role_melee = {
        en = 'Melee',
    },
    role_ranged = {
        en = 'Ranged',
    },

    -- Faction
    faction_chaos = {
        en = 'Poxwalker',
    },
    faction_cultist = {
        en = 'Dreg',
    },
    faction_renegade = {
        en = 'Scab',
    },
    faction_imperium = {
        en = 'Imperium',
    },

    -- Stats labels
    stat_difficulty = {
        en = 'Difficulty',
    },
    stat_health = {
        en = 'Health',
    },
    stat_hit_mass = {
        en = 'Hit Mass',
    },
    stat_zone = {
        en = 'Zone',
    },
    stat_armor = {
        en = 'Armor',
    },
    stat_weakspots = {
        en = 'Weakspot',
    },
    stat_category = {
        en = 'Category',
    },
    stat_size = {
        en = 'Size',
    },
    stat_role = {
        en = 'Role',
    },
    stat_faction = {
        en = 'Faction',
    },
    stat_challenge = {
        en = 'Challenge',
    },
    stat_stagger_resist = {
        en = 'Stagger Resist',
    },
    stat_stagger_reduction = {
        en = 'Stagger Reduction',
    },
    stat_run_speed = {
        en = 'Run Speed',
    },

    -- Difficulty tiers
    diff_sedition = {
        en = 'Sedition',
    },
    diff_uprising = {
        en = 'Uprising',
    },
    diff_malice = {
        en = 'Malice',
    },
    diff_heresy = {
        en = 'Heresy',
    },
    diff_damnation = {
        en = 'Damnation',
    },
    diff_havoc = {
        en = 'Havoc',
    },

    -- Armor types
    armor_unarmored = {
        en = 'Unarmored',
    },
    armor_armored = {
        en = 'Flak',
    },
    armor_super_armor = {
        en = 'Carapace',
    },
    armor_berserker = {
        en = 'Maniac',
    },
    armor_resistant = {
        en = 'Unyielding',
    },
    armor_disgustingly_resilient = {
        en = 'Infested',
    },
    armor_player = {
        en = 'Unarmored',
    },
    armor_void_shield = {
        en = 'Void Shield',
    },

    -- Hit zones
    zone_head = {
        en = 'Head',
    },
    zone_torso = {
        en = 'Torso',
    },
    zone_center_mass = {
        en = 'Center Mass',
    },
    zone_upper_left_arm = {
        en = 'Left Arm (Upper)',
    },
    zone_lower_left_arm = {
        en = 'Left Arm (Lower)',
    },
    zone_upper_right_arm = {
        en = 'Right Arm (Upper)',
    },
    zone_lower_right_arm = {
        en = 'Right Arm (Lower)',
    },
    zone_upper_left_leg = {
        en = 'Left Leg (Upper)',
    },
    zone_lower_left_leg = {
        en = 'Left Leg (Lower)',
    },
    zone_upper_right_leg = {
        en = 'Right Leg (Upper)',
    },
    zone_lower_right_leg = {
        en = 'Right Leg (Lower)',
    },
    zone_shield = {
        en = 'Shield',
    },
    zone_captain_void_shield = {
        en = 'Void Shield',
    },
    zone_corruptor_armor = {
        en = 'Corruptor Armor',
    },
    zone_backpack = {
        en = 'Backpack',
    },
    zone_tentacle = {
        en = 'Tentacle',
    },
    zone_right_shoulderguard = {
        en = 'Shoulderguard',
    },
    zone_weakspot = {
        en = 'Weakspot',
    },
    zone_afro = {
        en = 'Afro',
    },
    zone_tongue = {
        en = 'Tongue',
    },
    zone_upper_tail = {
        en = 'Tail (Upper)',
    },
    zone_lower_tail = {
        en = 'Tail (Lower)',
    },

    -- Weakspot types
    weakspot_headshot = {
        en = 'Headshot',
    },
    weakspot_weakspot = {
        en = 'Weakspot',
    },
    weakspot_protected = {
        en = 'Protected',
    },
    weakspot_protected_weakspot = {
        en = 'Protected Weakspot',
    },
    weakspot_shield = {
        en = 'Shield',
    },
    weakspot_explosive_backpack = {
        en = 'Explosive Backpack',
    },
}
