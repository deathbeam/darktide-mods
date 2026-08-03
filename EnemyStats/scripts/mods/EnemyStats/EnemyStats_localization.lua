return {
    global_loc = {
        loc_enemy_stats_menu_button = {
            en = 'Enemy Stats',
            ['zh-cn'] = '敌人数据统计',
        },
        loc_enemy_stats_copy = {
            en = 'Copy to Clipboard',
        },
    },
    game_loc = {
        -- Armor types
        armor_unarmored = 'loc_weapon_stats_display_unarmored',
        armor_armored = 'loc_weapon_stats_display_armored',
        armor_berserker = 'loc_weapon_stats_display_berzerker',
        armor_disgustingly_resilient = 'loc_weapon_stats_display_disgustingly_resilient',
        armor_resistant = 'loc_glossary_armour_type_resistant',
        armor_super_armor = 'loc_weapon_stats_display_super_armor',
        -- Difficulty tiers
        diff_uprising = 'loc_mission_board_danger_low',
        diff_malice = 'loc_mission_board_danger_medium',
        diff_heresy = 'loc_mission_board_danger_high',
        diff_damnation = 'loc_mission_board_danger_highest',
        diff_auric = 'loc_group_finder_difficulty_auric',
        diff_havoc = 'loc_havoc_name',
        -- Stagger
        stat_stagger_duration = 'loc_weapon_stats_display_stagger_duration',
        stat_stagger_type = 'loc_stagger',
        -- Combat role
        role_melee = 'loc_contract_task_weapon_type_melee',
        role_ranged = 'loc_contract_task_weapon_type_ranged',
        -- Weakspot
        weakspot_weakspot = 'loc_weapon_details_weakspot',
        -- Attack timing
        stat_damage = 'loc_weapon_stats_display_base_damage',
        stat_range = 'loc_weapon_stats_display_effective_range',
        stat_spread = 'loc_weapon_stats_display_spread',
        stat_fire_rate = 'loc_weapon_stats_display_rate_of_fire',
    },

    mod_name = {
        en = ' Enemy {#color(255,191,0)}Stats{#reset()}',
        ['zh-cn'] = '敌人数据统计',
    },
    mod_description = {
        en = 'Shows enemy health, hit mass, armor and weakspots across all difficulties and havoc ranks.',
        ['zh-cn'] = '显示所有难度和浩劫等级下敌人的生命值、命中质量、护甲类型与弱点信息。',
    },

    -- Config
    toggle_view_keybind = {
        en = 'Toggle Stats View',
        ['zh-cn'] = '切换统计视图',
    },
    add_to_esc_menu = {
        en = 'Show in Options Menu',
        ['zh-cn'] = '在选项菜单中显示',
    },

    -- Section headers
    header_info = {
        en = 'ENEMY INFO',
        ['zh-cn'] = '敌人信息',
    },
    header_health = {
        en = 'HEALTH',
        ['zh-cn'] = '生命值',
    },
    header_hit_zones = {
        en = 'HIT ZONES',
        ['zh-cn'] = '命中区域',
    },
    header_stagger = {
        en = 'STAGGER',
        ['zh-cn'] = '硬直',
    },

    -- Window
    search_placeholder = {
        en = 'Search enemies...',
        ['zh-cn'] = '搜索敌人...',
    },

    -- Enemy categories
    kind_horde = {
        en = 'Horde',
        ['zh-cn'] = '群怪',
    },
    kind_specialist = {
        en = 'Specialist',
        ['zh-cn'] = '专家',
    },
    kind_ritualist = {
        en = 'Ritualist',
        ['zh-cn'] = '仪式师',
    },
    kind_elite = {
        en = 'Elite',
        ['zh-cn'] = '精英',
    },
    kind_captain = {
        en = 'Captain',
        ['zh-cn'] = '队长',
    },
    kind_monstrosity = {
        en = 'Monstrosity',
        ['zh-cn'] = '怪物',
    },
    kind_unknown = {
        en = 'Unknown',
        ['zh-cn'] = '未知',
    },

    -- Size class
    size_human = {
        en = 'Human-sized',
        ['zh-cn'] = '人形',
    },
    size_ogryn = {
        en = 'Ogryn-sized',
        ['zh-cn'] = '欧格林',
    },
    size_monster = {
        en = 'Monster',
        ['zh-cn'] = '怪物',
    },

    -- Faction
    faction_chaos = {
        en = 'Poxwalker',
        ['zh-cn'] = '瘟疫行尸',
    },
    faction_cultist = {
        en = 'Dreg',
        ['zh-cn'] = '渣滓',
    },
    faction_renegade = {
        en = 'Scab',
        ['zh-cn'] = '血痂',
    },
    faction_imperium = {
        en = 'Imperium',
        ['zh-cn'] = '帝国',
    },

    -- Stats labels
    stat_difficulty = {
        en = 'Difficulty',
        ['zh-cn'] = '难度',
    },
    stat_health = {
        en = 'Health',
        ['zh-cn'] = '生命值',
    },
    stat_hit_mass = {
        en = 'Hit Mass',
        ['zh-cn'] = '命中质量',
    },
    stat_zone = {
        en = 'Zone',
        ['zh-cn'] = '部位',
    },
    stat_armor = {
        en = 'Armor',
        ['zh-cn'] = '护甲',
    },
    stat_weakspots = {
        en = 'Weakspot',
        ['zh-cn'] = '弱点',
    },
    stat_category = {
        en = 'Category',
        ['zh-cn'] = '分类',
    },
    stat_size = {
        en = 'Size',
        ['zh-cn'] = '体型',
    },
    stat_role = {
        en = 'Role',
        ['zh-cn'] = '角色',
    },
    stat_faction = {
        en = 'Faction',
        ['zh-cn'] = '阵营',
    },
    stat_challenge = {
        en = 'Challenge',
        ['zh-cn'] = '挑战等级',
    },
    stat_stagger_resist = {
        en = 'Stagger Resist',
        ['zh-cn'] = '硬直抗性',
    },
    stat_stagger_reduction = {
        en = 'Stagger Reduction',
        ['zh-cn'] = '硬直减免',
    },
    stat_run_speed = {
        en = 'Run Speed',
        ['zh-cn'] = '奔跑速度',
    },
    stat_walk_speed = {
        en = 'Walk Speed',
        ['zh-cn'] = '行走速度',
    },
    stat_detection_radius = {
        en = 'Detection Radius',
        ['zh-cn'] = '侦测半径',
    },
    stat_hit_time = {
        en = 'Hit Time',
        ['zh-cn'] = '命中时间',
    },
    stat_duration = {
        en = 'Duration',
        ['zh-cn'] = '时长',
    },
    stat_recovery = {
        en = 'Recovery',
        ['zh-cn'] = '后摇',
    },
    stat_weapon_reach = {
        en = 'Weapon Reach',
        ['zh-cn'] = '攻击距离',
    },
    stat_action = {
        en = 'Action',
        ['zh-cn'] = '动作',
    },
    stat_windup = {
        en = 'Windup',
        ['zh-cn'] = '前摇',
    },
    stat_shots = {
        en = 'Shots',
        ['zh-cn'] = '弹数',
    },
    header_melee_attacks = {
        en = 'MELEE ATTACKS',
        ['zh-cn'] = '近战攻击',
    },
    header_ranged_attacks = {
        en = 'RANGED ATTACKS',
        ['zh-cn'] = '远程攻击',
    },

    -- Stagger types
    stagger_light = {
        en = 'Light',
        ['zh-cn'] = '轻型',
    },
    stagger_medium = {
        en = 'Medium',
        ['zh-cn'] = '中型',
    },
    stagger_heavy = {
        en = 'Heavy',
        ['zh-cn'] = '重型',
    },
    stagger_light_ranged = {
        en = 'Light (Ranged)',
        ['zh-cn'] = '轻型(远程)',
    },
    stagger_explosion = {
        en = 'Explosion',
        ['zh-cn'] = '爆炸',
    },
    stagger_killshot = {
        en = 'Knockback',
        ['zh-cn'] = '击退',
    },
    stagger_sticky = {
        en = 'Sticky',
        ['zh-cn'] = '粘滞',
    },
    stagger_electrocuted = {
        en = 'Electrocuted',
        ['zh-cn'] = '电击',
    },

    -- Difficulty tiers
    diff_sedition = {
        en = 'Sedition',
        ['zh-cn'] = '煽动N1',
    },

    -- Armor types
    armor_player = {
        en = 'Unarmored',
        ['zh-cn'] = '无甲',
    },
    armor_void_shield = {
        en = 'Void Shield',
        ['zh-cn'] = '虚空护盾',
    },

    -- Hit zones
    zone_head = {
        en = 'Head',
        ['zh-cn'] = '头部',
    },
    zone_torso = {
        en = 'Torso',
        ['zh-cn'] = '躯干',
    },
    zone_center_mass = {
        en = 'Center Mass',
        ['zh-cn'] = '身体中央',
    },
    zone_upper_left_arm = {
        en = 'Left Arm (Upper)',
        ['zh-cn'] = '左臂（上）',
    },
    zone_lower_left_arm = {
        en = 'Left Arm (Lower)',
        ['zh-cn'] = '左臂（下）',
    },
    zone_upper_right_arm = {
        en = 'Right Arm (Upper)',
        ['zh-cn'] = '右臂（上）',
    },
    zone_lower_right_arm = {
        en = 'Right Arm (Lower)',
        ['zh-cn'] = '右臂（下）',
    },
    zone_upper_left_leg = {
        en = 'Left Leg (Upper)',
        ['zh-cn'] = '左腿（上）',
    },
    zone_lower_left_leg = {
        en = 'Left Leg (Lower)',
        ['zh-cn'] = '左腿（下）',
    },
    zone_upper_right_leg = {
        en = 'Right Leg (Upper)',
        ['zh-cn'] = '右腿（上）',
    },
    zone_lower_right_leg = {
        en = 'Right Leg (Lower)',
        ['zh-cn'] = '右腿（下）',
    },
    zone_shield = {
        en = 'Shield',
        ['zh-cn'] = '盾牌',
    },
    zone_captain_void_shield = {
        en = 'Void Shield',
        ['zh-cn'] = '虚空护盾',
    },
    zone_corruptor_armor = {
        en = 'Corruptor Armor',
        ['zh-cn'] = '腐化装甲',
    },
    zone_backpack = {
        en = 'Backpack',
        ['zh-cn'] = '背包',
    },
    zone_tentacle = {
        en = 'Tentacle',
        ['zh-cn'] = '触手',
    },
    zone_right_shoulderguard = {
        en = 'Shoulderguard',
        ['zh-cn'] = '右肩甲',
    },
    zone_weakspot = {
        en = 'Weakspot',
        ['zh-cn'] = '弱点',
    },
    zone_afro = {
        en = 'Afro',
        ['zh-cn'] = '爆炸发型',
    },
    zone_tongue = {
        en = 'Tongue',
        ['zh-cn'] = '舌头',
    },
    zone_upper_tail = {
        en = 'Tail (Upper)',
        ['zh-cn'] = '尾巴（上）',
    },
    zone_lower_tail = {
        en = 'Tail (Lower)',
        ['zh-cn'] = '尾巴（下）',
    },
    zone_hound_tail = {
        en = 'Tail',
        ['zh-cn'] = '尾巴',
    },
    zone_canister = {
        en = 'Canister',
        ['zh-cn'] = '罐子',
    },

    -- Weakspot types
    weakspot_headshot = {
        en = 'Headshot',
        ['zh-cn'] = '爆头',
    },
    weakspot_protected = {
        en = 'Protected',
        ['zh-cn'] = '护甲覆盖',
    },
    weakspot_protected_weakspot = {
        en = 'Protected Weakspot',
        ['zh-cn'] = '护甲覆盖弱点',
    },
    weakspot_shield = {
        en = 'Shield',
        ['zh-cn'] = '盾牌',
    },
    weakspot_explosive_backpack = {
        en = 'Explosive Backpack',
        ['zh-cn'] = '爆炸背包',
    },
}
