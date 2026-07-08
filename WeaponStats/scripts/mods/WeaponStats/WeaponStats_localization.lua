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

    -- Config
    toggle_view_keybind = {
        en = 'Toggle Stats View',
        ['zh-cn'] = '切换统计视图',
        ['zh-tw'] = '切換統計檢視',
    },

    -- Window
    search_placeholder = {
        en = 'Search weapons...',
    },
    stat_attack_type = {
        en = 'Attack Type',
    },
    kind_ranged = {
        en = 'Ranged',
    },
    kind_melee = {
        en = 'Melee',
    },

    -- Headers
    header_ranged_attacks = {
        en = 'RANGED ATTACKS',
    },
    header_light_attacks = {
        en = 'LIGHT ATTACKS',
    },
    header_heavy_attacks = {
        en = 'HEAVY ATTACKS',
    },
    header_special_attacks = {
        en = 'SPECIAL ATTACKS',
    },
    header_attack_pattern = {
        en = 'ATTACK PATTERN',
    },
    header_special_active = {
        en = 'SPECIAL ACTIVE ATTACKS',
    },

    -- Stat keys
    stat_fire_rate = {
        en = 'Fire Rate',
    },
    stat_attack_speed = {
        en = 'Attack Speed',
    },
    stat_damage = {
        en = 'Damage',
    },
    stat_impact = {
        en = 'Impact',
    },
    stat_cleave = {
        en = 'Cleave',
    },
    stat_backstab = {
        en = 'Backstab',
    },
    stat_finesse_and_crit = {
        en = 'Finesse & Crit',
    },
    stat_weakspot = {
        en = 'Weakspot',
    },
    stat_crit = {
        en = 'Crit',
    },
    stat_crit_plus_weakspot = {
        en = 'Crit + Weakspot',
    },
    stat_crit_modifier = {
        en = 'Crit Chance',
    },
    stat_crit_strings = {
        en = 'Crit Strings',
    },
    stat_pellets = {
        en = 'Pellets',
    },
    stat_spread = {
        en = 'Spread',
    },
    stat_falloff_range = {
        en = 'Falloff Range',
    },
    stat_suppression = {
        en = 'Suppression',
    },
    stat_stagger = {
        en = 'Stagger',
    },
    stat_type = {
        en = 'Type',
    },
    stat_flags = {
        en = 'Flags',
    },
    stat_special_active = {
        en = 'Special Active',
    },
    stat_adm = {
        en = 'ADM',
    },
    stat_direction = {
        en = 'Direction',
    },

    label_primary = {
        en = 'Light',
    },
    label_secondary = {
        en = 'Heavy',
    },
    label_special = {
        en = 'Special',
    },
    label_extra = {
        en = 'Secondary',
    },

    direction_left = {
        en = 'Left',
    },
    direction_right = {
        en = 'Right',
    },
    direction_down = {
        en = 'Down',
    },
    direction_up = {
        en = 'Up',
    },
    direction_thrust = {
        en = 'Thrust',
    },
    direction_cross = {
        en = 'Cross',
    },

    -- Armor Types
    armor_unarmored = {
        en = 'Unarmored',
    },
    armor_armored = {
        en = 'Flak',
    },
    armor_resistant = {
        en = 'Unyielding',
    },
    armor_berserker = {
        en = 'Maniac',
    },
    armor_super_armor = {
        en = 'Carapace',
    },
    armor_disgustingly_resilient = {
        en = 'Infested',
    },
    armor_void_shield = {
        en = 'Void Shield',
    },

    -- Damage Types
    damage_type_auto_bullet = {
        en = 'Auto Bullet',
    },
    damage_type_bullet = {
        en = 'Bullet',
    },
    damage_type_laser = {
        en = 'Laser',
    },
    damage_type_laser_bfg = {
        en = 'Laser',
    },
    damage_type_laser_charged = {
        en = 'Laser',
    },
    damage_type_plasma = {
        en = 'Plasma',
    },
    damage_type_plasma_heavy = {
        en = 'Plasma',
    },
    damage_type_boltshell = {
        en = 'Bolt Shell',
    },
    damage_type_boltshell_small = {
        en = 'Bolt Shell',
    },
    damage_type_boltshell_big = {
        en = 'Bolt Shell',
    },
    damage_type_boltshell_non_armed = {
        en = 'Bolt Shell',
    },
    damage_type_bolt = {
        en = 'Bolt Shell',
    },
    damage_type_pellet = {
        en = 'Shotgun',
    },
    damage_type_pellet_incendiary = {
        en = 'Incendiary',
    },
    damage_type_pellet_shock = {
        en = 'Shock',
    },
    damage_type_shotgun = {
        en = 'Shotgun',
    },
    damage_type_burning = {
        en = 'Fire',
    },
    damage_type_fire = {
        en = 'Fire',
    },
    damage_type_warpfire = {
        en = 'Warp Fire',
    },
    damage_type_toxin = {
        en = 'Toxin',
    },
    damage_type_warp = {
        en = 'Warp',
    },
    damage_type_warp_overload = {
        en = 'Warp Overload',
    },
    damage_type_physical = {
        en = 'Physical',
    },
    damage_type_electrocution = {
        en = 'Electrocution',
    },
    damage_type_phosphor = {
        en = 'Phosphor',
    },
    damage_type_galvanic = {
        en = 'Galvanic',
    },
    damage_type_needle = {
        en = 'Needle',
    },
    damage_type_arc_chain = {
        en = 'Arc',
    },
    damage_type_arc_rifle = {
        en = 'Arc',
    },
    damage_type_grenade_frag = {
        en = 'Frag Grenade',
    },
    damage_type_overheat = {
        en = 'Overheat',
    },
    damage_type_kinetic = {
        en = 'Kinetic',
    },
    damage_type_smite = {
        en = 'Smite',
    },
    damage_type_axe_light = {
        en = 'Axe',
    },
    damage_type_blunt = {
        en = 'Blunt',
    },
    damage_type_blunt_heavy = {
        en = 'Blunt',
    },
    damage_type_blunt_light = {
        en = 'Blunt',
    },
    damage_type_blunt_shock = {
        en = 'Shock',
    },
    damage_type_blunt_thunder = {
        en = 'Thunder',
    },
    damage_type_spiked_blunt = {
        en = 'Spiked Blunt',
    },
    damage_type_knife = {
        en = 'Knife',
    },
    damage_type_combat_blade = {
        en = 'Combat Blade',
    },
    damage_type_crowbar_rip_heavy = {
        en = 'Crowbar',
    },
    damage_type_crowbar_rip_light = {
        en = 'Crowbar',
    },
    damage_type_crowbar_stick_heavy = {
        en = 'Crowbar',
    },
    damage_type_crowbar_stick_light = {
        en = 'Crowbar',
    },
    damage_type_metal_slashing_heavy = {
        en = 'Slashing',
    },
    damage_type_metal_slashing_light = {
        en = 'Slashing',
    },
    damage_type_metal_slashing_medium = {
        en = 'Slashing',
    },
    damage_type_ogryn_physical = {
        en = 'Physical',
    },
    damage_type_ogryn_pipe_club = {
        en = 'Pipe Club',
    },
    damage_type_ogryn_pipe_club_heavy = {
        en = 'Pipe Club',
    },
    damage_type_ogryn_punch = {
        en = 'Punch',
    },
    damage_type_ogryn_slap = {
        en = 'Slap',
    },
    damage_type_ogryn_hook = {
        en = 'Hook',
    },
    damage_type_ogryn_shovel_smack = {
        en = 'Shovel',
    },
    damage_type_ogryn_shovel_fold_special = {
        en = 'Shovel',
    },
    damage_type_ogryn_bullet_bounce = {
        en = 'Bouncing Bullet',
    },
    damage_type_power_sword = {
        en = 'Power Sword',
    },
    damage_type_saw_light = {
        en = 'Saw',
    },
    damage_type_saw_heavy = {
        en = 'Saw',
    },
    damage_type_saw_rip_light = {
        en = 'Saw Rip',
    },
    damage_type_saw_rip_heavy = {
        en = 'Saw Rip',
    },
    damage_type_sawing = {
        en = 'Sawing',
    },
    damage_type_sawing_stuck = {
        en = 'Sawing',
    },
    damage_type_shovel_light = {
        en = 'Shovel',
    },
    damage_type_shovel_medium = {
        en = 'Shovel',
    },
    damage_type_shovel_heavy = {
        en = 'Shovel',
    },
    damage_type_shovel_smack = {
        en = 'Shovel',
    },
    damage_type_rippergun_flechette = {
        en = 'Flechette',
    },
    damage_type_rippergun_pellet = {
        en = 'Pellet',
    },
    damage_type_transonic = {
        en = 'Transonic',
    },
    damage_type_transonic_claw = {
        en = 'Transonic Claw',
    },
    damage_type_transonic_claw_rip = {
        en = 'Transonic Claw',
    },
    damage_type_transonic_claw_stick = {
        en = 'Transonic Claw',
    },
    damage_type_force_sword_cleave = {
        en = 'Force Sword',
    },
    damage_type_forcesword_force_slash_low = {
        en = 'Force Slash',
    },
    damage_type_forcesword_force_slash_middle = {
        en = 'Force Slash',
    },
    damage_type_forcesword_force_slash_high = {
        en = 'Force Slash',
    },
    damage_type_force_staff_bfg = {
        en = 'Force Staff',
    },
    damage_type_force_staff_explosion = {
        en = 'Force Staff',
    },
    damage_type_psyker_biomancer_discharge = {
        en = 'Biomancer Discharge',
    },
    damage_type_shield_push = {
        en = 'Shield Push',
    },
    damage_type_weapon_butt = {
        en = 'Weapon Butt',
    },
    damage_type_punch = {
        en = 'Punch',
    },
    damage_type_piercing_heavy = {
        en = 'Piercing',
    },

    -- Stagger Types
    stagger_melee = {
        en = 'Melee',
    },
    stagger_uppercut = {
        en = 'Uppercut',
    },
    stagger_killshot = {
        en = 'Knockback',
    },
    stagger_ranged = {
        en = 'Ranged',
    },
    stagger_explosion = {
        en = 'Explosion',
    },
    stagger_flamer = {
        en = 'Flamer',
    },
    stagger_sticky = {
        en = 'Sticky',
    },
    stagger_heavy = {
        en = 'Heavy',
    },
    stagger_light = {
        en = 'Light',
    },
    stagger_medium = {
        en = 'Medium',
    },
    stagger_electrocuted = {
        en = 'Electrocuted',
    },
    stagger_force_field = {
        en = 'Force Field',
    },
    stagger_hatchet = {
        en = 'Hatchet',
    },

    -- Flags
    flag_weapon_special = {
        en = 'Weapon Special',
    },
    flag_ignores_stagger_reduction = {
        en = 'Ignores Stagger Reduction',
    },
    flag_ignores_shield = {
        en = 'Ignores Shield',
    },
    flag_ignores_hitzone_multiplier = {
        en = 'Ignores Hitzone Multiplier',
    },
    flag_is_push = {
        en = 'Push',
    },
}
