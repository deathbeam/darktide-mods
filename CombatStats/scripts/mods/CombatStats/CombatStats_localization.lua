local mod = get_mod('CombatStats')

-- Register global localization strings (for input legend, etc.)
mod:add_global_localize_strings({
    loc_combat_stats_reset_stats = {
        en = 'Reset Stats',
        ["zh-cn"] = '重置统计',
    },
})

return {
    mod_name = {
        en = 'Combat Stats',
        ["zh-cn"] = '战斗统计',
    },
    mod_description = {
        en = 'Track detailed combat statistics including damage, kills, buff uptime, and more.',
        ["zh-cn"] = '追踪详细的战斗统计数据，包括伤害、击杀、增益持续时间等。',
    },

    -- Config
    show_hud_overlay = {
        en = 'Show Overlay',
        ["zh-cn"] = '显示覆盖层',
    },
    show_hud_overlay_tooltip = {
        en = 'Display the minimal stats overlay during combat.',
        ["zh-cn"] = '在战斗期间显示简化的统计覆盖层。',
    },
    enable_in_missions = {
        en = 'Enable in Missions',
        ["zh-cn"] = '在任务中启用',
    },
    enable_in_missions_tooltip = {
        en = 'Enables stat tracking while in missions.',
        ["zh-cn"] = '在任务中启用统计追踪。',
    },
    enable_in_hub = {
        en = 'Enable in Hub',
        ["zh-cn"] = '在枢纽中启用',
    },
    enable_in_hub_tooltip = {
        en = 'Shows stats from last session while in the hub area.',
        ["zh-cn"] = '在枢纽区域显示上一场任务的统计数据。',
    },
    toggle_view_keybind = {
        en = 'Toggle Stats View',
        ["zh-cn"] = '切换统计视图',
    },
    enemy_types_to_track = {
        en = 'Enemy Types to Track',
        ["zh-cn"] = '追踪的敌人类型',
    },

    -- Common Stats
    time = {
        en = 'Time',
        ["zh-cn"] = '时间',
    },
    kills = {
        en = 'Kills',
        ["zh-cn"] = '击杀数',
    },
    dps = {
        en = 'DPS',
        ["zh-cn"] = 'DPS',
    },
    damage = {
        en = 'Damage',
        ["zh-cn"] = '伤害',
    },
    hits = {
        en = 'Hits',
        ["zh-cn"] = '命中数',
    },
    total = {
        en = 'Total',
        ["zh-cn"] = '总计',
    },
    melee = {
        en = 'Melee',
        ["zh-cn"] = '近战',
    },
    ranged = {
        en = 'Ranged',
        ["zh-cn"] = '远程',
    },
    explosion = {
        en = 'Explosion',
        ["zh-cn"] = '爆炸',
    },
    companion = {
        en = 'Companion',
        ["zh-cn"] = '同伴',
    },
    buff = {
        en = 'Buff',
        ["zh-cn"] = '增益',
    },
    crit = {
        en = 'Crit',
        ["zh-cn"] = '暴击',
    },
    weakspot = {
        en = 'Weakspot',
        ["zh-cn"] = '弱点',
    },
    bleed = {
        en = 'Bleed',
        ["zh-cn"] = '流血',
    },
    burn = {
        en = 'Burn',
        ["zh-cn"] = '燃烧',
    },
    toxin = {
        en = 'Toxin',
        ["zh-cn"] = '毒素',
    },
    enemy = {
        en = 'Enemy',
        ["zh-cn"] = '敌人',
    },
    enemy_type = {
        en = 'Enemy Type',
        ["zh-cn"] = '敌人类型',
    },

    -- View
    combat_stats_view_title = {
        en = 'Combat Statistics',
        ["zh-cn"] = '战斗统计',
    },
    search_placeholder = {
        en = 'Search enemies...',
        ["zh-cn"] = '搜索敌人...',
    },
    overall_stats = {
        en = 'Overall Stats',
        ["zh-cn"] = '总体统计',
    },
    enemy_stats = {
        en = 'Enemy Stats',
        ["zh-cn"] = '敌人统计',
    },
    damage_stats = {
        en = 'Damage Stats',
        ["zh-cn"] = '伤害统计',
    },
    hit_stats = {
        en = 'Hit Stats',
        ["zh-cn"] = '命中统计',
    },
    buff_uptime = {
        en = 'Buff Uptime',
        ["zh-cn"] = '增益持续时间',
    },

    -- Breed Types
    breed_monster = {
        en = 'monster',
        ["zh-cn"] = '怪物',
    },
    breed_ritualist = {
        en = 'ritualist',
        ["zh-cn"] = '仪式术士',
    },
    breed_disabler = {
        en = 'disabler',
        ["zh-cn"] = '控制型',
    },
    breed_special = {
        en = 'special',
        ["zh-cn"] = '专家',
    },
    breed_elite = {
        en = 'elite',
        ["zh-cn"] = '精英',
    },
    breed_horde = {
        en = 'horde',
        ["zh-cn"] = '尸潮',
    },
    breed_unknown = {
        en = 'unknown',
        ["zh-cn"] = '未知',
    },
}