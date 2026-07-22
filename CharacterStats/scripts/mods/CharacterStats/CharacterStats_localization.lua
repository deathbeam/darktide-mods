return {
    global_loc = {
        loc_character_stats_menu_button = {
            en = 'Character Stats',
            ['zh-cn'] = '角色属性',
        },
        loc_character_stats_copy = {
            en = 'Copy to Clipboard',
            ['zh-cn'] = '复制到剪贴板',
        },
    },
    game_loc = {
        stat_toughness_regen = 'loc_player_buff_coherency_toughness_regen',
        coherency_source = 'loc_player_buff_coherency_toughness_regen',
        stat_toughness_regen_percent = 'loc_toughness_tutorial',
        stat_dodge_dist = 'loc_weapon_stats_display_dodge_distance',
        stat_dodge_speed = 'loc_weapon_stats_display_dodge_speed',
        stat_sprint_speed = 'loc_weapon_stats_display_sprint_speed',
        stat_attack_speed = 'loc_weapon_stats_display_attack_speed',
        stat_reload_speed = 'loc_stats_display_reload_speed_stat',
        stat_spread = 'loc_weapon_stats_display_spread',
        bio_origin = 'loc_character_create_title_bio_origin',
        bio_home_planet = 'loc_character_create_title_home_planet',
        bio_early_life = 'loc_character_create_title_early_life',
        bio_first_conflict = 'loc_character_create_title_first_conflict',
        bio_key_event = 'loc_character_create_title_key_event',
        bio_crime = 'loc_character_create_title_crime',
        bio_personality = 'loc_character_create_title_personality',
    },

    mod_name = {
        en = 'Character Stats',
        ['zh-cn'] = '角色属性',
    },
    mod_description = {
        en = 'Shows derived character stats computed from talents, perks, blessings, curios, and active buffs.',
        ['zh-cn'] = '显示由天赋、特性、祝福、饰品与激活增益计算的衍生属性。',
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

    -- Assumed-buff toggles
    assume_proc_stacks = {
        en = 'Assume max proc stacks',
        ['zh-cn'] = '假设最大触发层数',
    },
    coherency_allies = {
        en = 'Coherency allies',
        ['zh-cn'] = '共鸣队友数',
    },
    havoc_rank = {
        en = 'Havoc rank',
        ['zh-cn'] = '浩劫等级',
    },
    havoc_source = {
        en = 'Havoc',
        ['zh-cn'] = '浩劫',
    },

    -- List
    current_character = {
        en = 'Current Character',
        ['zh-cn'] = '当前角色',
    },
    header_bio = {
        en = 'CHARACTER BACKGROUND',
        ['zh-cn'] = '角色背景',
    },
    no_character = {
        en = 'No active character (enter a mission or the hub)',
        ['zh-cn'] = '无活动角色（进入任务或大厅）',
    },
    search_placeholder = {
        en = 'Search...',
        ['zh-cn'] = '搜索...',
    },

    -- Section headers
    header_vitals = {
        en = 'VITALS',
        ['zh-cn'] = '生命',
    },
    header_toughness = {
        en = 'RECOVERY',
        ['zh-cn'] = '恢复',
    },
    header_defense = {
        en = 'DEFENSE',
        ['zh-cn'] = '防御',
    },
    header_offense = {
        en = 'OFFENSE',
        ['zh-cn'] = '进攻',
    },
    header_mobility = {
        en = 'MOBILITY',
        ['zh-cn'] = '机动性',
    },

    -- Stat labels: vitals
    stat_health = {
        en = 'Max Health',
        ['zh-cn'] = '最大生命值',
    },
    stat_wounds = {
        en = 'Wounds',
        ['zh-cn'] = '伤口',
    },
    stat_toughness = {
        en = 'Max Toughness',
        ['zh-cn'] = '最大韧性',
    },
    stat_archetype = {
        en = 'Archetype',
        ['zh-cn'] = '职业',
    },

    -- Stat labels: recovery
    stat_toughness_regen = {
        en = 'Coherency Toughness Regeneration',
        ['zh-cn'] = '共鸣韧性恢复',
    },
    stat_toughness_regen_percent = {
        en = 'Toughness Regeneration',
        ['zh-cn'] = '韧性恢复',
    },
    stat_tough_bonus_regen = {
        en = 'Toughness Replenishment',
        ['zh-cn'] = '韧性补充',
    },
    stat_tough_regen_delay = {
        en = 'Toughness Regeneration Speed',
        ['zh-cn'] = '韧性恢复速度',
    },
    stat_tough_bounty = {
        en = 'Toughness Replenishment on Melee Kill',
        ['zh-cn'] = '近战击杀补充韧性',
    },
    coherency_source = {
        en = 'Coherency Toughness Regeneration',
        ['zh-cn'] = '共鸣韧性恢复',
    },

    -- Stat labels: defense
    stat_damage_reduction = {
        en = 'Damage Reduction',
        ['zh-cn'] = '伤害减免',
    },
    stat_reduction_melee = {
        en = 'Melee Reduction',
        ['zh-cn'] = '近战减免',
    },
    stat_reduction_ranged = {
        en = 'Ranged Reduction',
        ['zh-cn'] = '远程减免',
    },
    stat_tough_reduction_melee = {
        en = 'Toughness Reduction (Melee)',
        ['zh-cn'] = '近战韧性减免',
    },
    stat_tough_reduction_ranged = {
        en = 'Toughness Reduction (Ranged)',
        ['zh-cn'] = '远程韧性减免',
    },
    stat_taken_from_explosions = {
        en = 'Reduction vs Explosions',
        ['zh-cn'] = '爆炸伤害减免',
    },
    stat_taken_from_prop_explosions = {
        en = 'Reduction vs Prop Explosions',
        ['zh-cn'] = '物块爆炸减免',
    },
    stat_taken_from_toxin = {
        en = 'Reduction vs Toxin',
        ['zh-cn'] = '毒素减免',
    },
    stat_taken_from_burning = {
        en = 'Reduction vs Burning',
        ['zh-cn'] = '燃烧减免',
    },
    stat_taken_from_bleeding = {
        en = 'Reduction vs Bleeding',
        ['zh-cn'] = '流血减免',
    },
    stat_taken_from_electrocution = {
        en = 'Reduction vs Electrocution',
        ['zh-cn'] = '触电减免',
    },
    stat_taken_from_kinetic = {
        en = 'Reduction vs Kinetic',
        ['zh-cn'] = '动能减免',
    },
    stat_taken_from_toxic_gas = {
        en = 'Reduction vs Toxic Gas',
        ['zh-cn'] = '毒气减免',
    },
    stat_taken_from_corruption = {
        en = 'Damage Resistance (Corruption)',
        ['zh-cn'] = '腐化伤害抗性',
    },
    stat_taken_from_grimoire = {
        en = 'Damage Resistance (Grimoires)',
        ['zh-cn'] = '典籍伤害抗性',
    },
    stat_taken_from_bombers = {
        en = 'Damage Resistance (Bombers)',
        ['zh-cn'] = '轰炸者伤害抗性',
    },
    stat_taken_from_flamers = {
        en = 'Damage Resistance (Tox Flamers)',
        ['zh-cn'] = '喷火兵伤害抗性',
    },
    stat_taken_from_gunners = {
        en = 'Damage Resistance (Gunners)',
        ['zh-cn'] = '枪手伤害抗性',
    },
    stat_taken_from_mutants = {
        en = 'Damage Resistance (Mutants)',
        ['zh-cn'] = '变异者伤害抗性',
    },
    stat_taken_from_pox_hounds = {
        en = 'Damage Resistance (Pox Hounds)',
        ['zh-cn'] = '疫犬伤害抗性',
    },
    stat_taken_from_snipers = {
        en = 'Damage Resistance (Snipers)',
        ['zh-cn'] = '狙击手伤害抗性',
    },

    -- Stat labels: offense
    stat_attack_speed = {
        en = 'Attack Speed Bonus',
        ['zh-cn'] = '攻击速度加成',
    },
    stat_crit_chance = {
        en = 'Crit Chance',
        ['zh-cn'] = '暴击几率',
    },
    stat_crit_damage = {
        en = 'Crit Damage Bonus',
        ['zh-cn'] = '暴击伤害加成',
    },
    stat_total_damage = {
        en = 'Total Damage Bonus',
        ['zh-cn'] = '总伤害加成',
    },
    stat_rending = {
        en = 'Rending Bonus',
        ['zh-cn'] = '破甲加成',
    },

    -- Offense breakdown terms
    stat_melee_damage = {
        en = 'Melee Damage Bonus',
        ['zh-cn'] = '近战伤害加成',
    },
    stat_ranged_damage = {
        en = 'Ranged Damage Bonus',
        ['zh-cn'] = '远程伤害加成',
    },
    stat_power_level = {
        en = 'Power Level',
        ['zh-cn'] = '威力等级',
    },
    stat_reload_speed = {
        en = 'Reload Speed',
        ['zh-cn'] = '换弹速度',
    },
    stat_spread = {
        en = 'Spread',
        ['zh-cn'] = '散射',
    },
    stat_impact = {
        en = 'Impact',
        ['zh-cn'] = '冲击',
    },
    stat_movement_speed = {
        en = 'Movement Speed',
        ['zh-cn'] = '移动速度',
    },
    stat_damage_vs_elites = {
        en = 'Damage vs Elites',
        ['zh-cn'] = '对精英伤害',
    },
    stat_damage_vs_specials = {
        en = 'Damage vs Specialists',
        ['zh-cn'] = '对专家伤害',
    },
    stat_damage_vs_monsters = {
        en = 'Damage vs Monsters',
        ['zh-cn'] = '对怪物伤害',
    },
    stat_ranged_vs_monsters = {
        en = 'Ranged vs Monsters',
        ['zh-cn'] = '远程对怪物',
    },
    stat_damage_vs_ogryn = {
        en = 'Damage vs Ogryn',
        ['zh-cn'] = '对欧格林',
    },
    stat_damage_vs_ogryn_monsters = {
        en = 'Damage vs Ogryn/Monsters',
        ['zh-cn'] = '对欧格林/怪物',
    },
    stat_damage_vs_horde = {
        en = 'Damage vs Horde',
        ['zh-cn'] = '对群怪',
    },
    stat_damage_vs_bleeding = {
        en = 'Damage vs Bleeding',
        ['zh-cn'] = '对流血',
    },
    stat_damage_vs_burning = {
        en = 'Damage vs Burning',
        ['zh-cn'] = '对燃烧',
    },
    stat_damage_vs_electrocuted = {
        en = 'Damage vs Electrocuted',
        ['zh-cn'] = '对触电',
    },
    stat_damage_vs_staggered = {
        en = 'Damage vs Staggered',
        ['zh-cn'] = '对踉跄',
    },
    stat_damage_vs_suppressed = {
        en = 'Damage vs Suppressed',
        ['zh-cn'] = '对压制',
    },
    stat_damage_vs_healthy = {
        en = 'Damage vs Healthy',
        ['zh-cn'] = '对健康',
    },
    stat_melee_heavy_vs_elites = {
        en = 'Melee Heavy vs Elites',
        ['zh-cn'] = '近战重击对精英',
    },

    -- Rending breakdown terms
    stat_backstab_rending = {
        en = 'Backstab Rending',
        ['zh-cn'] = '背刺破甲',
    },
    stat_flanking_rending = {
        en = 'Flanking Rending',
        ['zh-cn'] = '侧袭破甲',
    },
    stat_crit_rending = {
        en = 'Crit Rending',
        ['zh-cn'] = '暴击破甲',
    },
    stat_rending_vs_staggered = {
        en = 'Rending vs Staggered',
        ['zh-cn'] = '对踉跄破甲',
    },
    stat_rending_vs_electrocuted = {
        en = 'Rending vs Electrocuted',
        ['zh-cn'] = '对触电破甲',
    },
    stat_close_range_rending = {
        en = 'Close Range Rending',
        ['zh-cn'] = '近距离破甲',
    },
    stat_warp_rending = {
        en = 'Warp Rending',
        ['zh-cn'] = '灵能破甲',
    },
    stat_melee_rending = {
        en = 'Melee Rending',
        ['zh-cn'] = '近战破甲',
    },
    stat_melee_heavy_rending = {
        en = 'Melee Heavy Rending',
        ['zh-cn'] = '近战重击破甲',
    },
    stat_ranged_rending = {
        en = 'Ranged Rending',
        ['zh-cn'] = '远程破甲',
    },
    stat_ranged_crit_rending = {
        en = 'Ranged Crit Rending',
        ['zh-cn'] = '远程暴击破甲',
    },

    -- Damage taken breakdown terms
    stat_damage_taken_mult = {
        en = 'Damage Taken (Mult)',
        ['zh-cn'] = '受到伤害（乘算）',
    },
    stat_damage_taken_mod = {
        en = 'Damage Taken (Add)',
        ['zh-cn'] = '受到伤害（加算）',
    },
    stat_melee_damage_taken_mult = {
        en = 'Melee Taken (Mult)',
        ['zh-cn'] = '近战承受（乘算）',
    },
    stat_melee_damage_taken_mod = {
        en = 'Melee Taken (Add)',
        ['zh-cn'] = '近战承受（加算）',
    },
    stat_ranged_damage_taken_mult = {
        en = 'Ranged Taken (Mult)',
        ['zh-cn'] = '远程承受（乘算）',
    },
    stat_ranged_damage_taken_mod = {
        en = 'Ranged Taken (Add)',
        ['zh-cn'] = '远程承受（加算）',
    },

    -- Stat labels: mobility
    stat_stamina = {
        en = 'Max Stamina',
        ['zh-cn'] = '最大体力',
    },
    stat_stamina_regen = {
        en = 'Stamina Regen',
        ['zh-cn'] = '体力恢复',
    },
    stat_stamina_delay = {
        en = 'Stamina Regen Delay',
        ['zh-cn'] = '体力恢复延迟',
    },
    stat_sprint_speed = {
        en = 'Sprint Speed (m/s)',
        ['zh-cn'] = '冲刺速度（米/秒）',
    },
    stat_sprint_time = {
        en = 'Sprint Duration (sec)',
        ['zh-cn'] = '冲刺持续时间（秒）',
    },
    stat_dodge_count = {
        en = 'Dodge Count',
        ['zh-cn'] = '闪避次数',
    },
    stat_dodge_dist = {
        en = 'Dodge Distance',
        ['zh-cn'] = '闪避距离',
    },
    stat_dodge_speed = {
        en = 'Dodge Speed',
        ['zh-cn'] = '闪避速度',
    },
}
