local mod = get_mod('CombatStats')

mod:add_global_localize_strings({
    loc_combat_stats_reset_stats = {
        en = 'Reset Stats',
        ['zh-cn'] = '重置统计', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '重置統計',
    },
    loc_combat_stats_view_history = {
        en = 'View History',
        ['zh-cn'] = '查看历史', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '查看歷史紀錄',
    },
    loc_combat_stats_back_to_current = {
        en = 'Back to Current',
        ['zh-cn'] = '返回当前', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '返回目前統計',
    },
    loc_combat_stats_back_to_history = {
        en = 'Back to History',
        ['zh-cn'] = '返回历史', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '返回歷史紀錄',
    },
    loc_combat_stats_delete_entry = {
        en = 'Delete Entry',
        ['zh-cn'] = '删除条目', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '刪除項目',
    },
    loc_combat_stats_menu_button = {
        en = 'Combat Stats',
        ['zh-cn'] = '战斗统计',
        ['zh-tw'] = '戰鬥統計',
    },
})

return {
    mod_name = {
        en = 'Combat Stats',
        ['zh-cn'] = '战斗统计',
        ['zh-tw'] = '戰鬥統計',
    },
    mod_description = {
        en = 'Track detailed combat statistics including damage, kills, buff uptime, and more.',
        ['zh-cn'] = '追踪详细的战斗统计数据，包括伤害、击杀、增益持续时间等。',
        ['zh-tw'] = '追蹤詳細戰鬥統計，包括傷害、擊殺、增益持續時間等。',
    },

    -- Config
    save_history = {
        en = 'Save History',
        ['zh-cn'] = '保存历史', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '儲存歷史',
    },
    save_history_tooltip = {
        en = 'Save combat statistics from previous missions for later viewing.',
        ['zh-cn'] = '保存先前任务的战斗统计数据以供以后查看。', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '儲存先前任務的戰鬥統計，以便稍後查看。',
    },
    toggle_view_keybind = {
        en = 'Toggle Stats View',
        ['zh-cn'] = '切换统计视图',
        ['zh-tw'] = '切換統計檢視',
    },
    only_in_psykhanium = {
        en = 'Only In Psykhanium',
        ['zh-cn'] = '仅在灵能室', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '僅限靈能室',
    },
    only_in_psykhanium_tooltip = {
        en = 'Only track and show combat stats when in the Psykhanium.',
        ['zh-cn'] = '仅在灵能室中追踪和显示战斗统计数据。', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '只有在靈能室中才追蹤並顯示戰鬥統計。',
    },
    hud = {
        en = 'HUD',
        ['zh-cn'] = 'HUD',
        ['zh-tw'] = 'HUD',
    },
    show_hud_in_missions = {
        en = 'Show Overlay In Missions',
        ['zh-cn'] = '在任务中显示覆盖层', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '在任務中顯示疊加介面',
    },
    show_hud_in_hub = {
        en = 'Show Overlay In Hub',
        ['zh-cn'] = '在集结区显示覆盖层', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '在大廳顯示疊加介面',
    },
    hud_pos_x = {
        en = 'X Position',
        ['zh-cn'] = 'X位置',
        ['zh-tw'] = 'X 位置',
    },
    hud_pos_y = {
        en = 'Y Position',
        ['zh-cn'] = 'Y位置',
        ['zh-tw'] = 'Y 位置',
    },
    combat_detection = {
        en = 'Combat Detection',
        ['zh-cn'] = '战斗检测', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '戰鬥偵測',
    },
    track_incoming_attacks = {
        en = 'Track Incoming Attacks',
        ['zh-cn'] = '追踪传入攻击', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '追蹤受到的攻擊',
    },
    track_incoming_attacks_tooltip = {
        en = 'Start combat when enemies attack you (even if blocked/dodged).',
        ['zh-cn'] = '当敌人攻击你时开始战斗（即使被格挡/闪避）。', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '當敵人攻擊你時開始戰鬥（即使被格擋或閃避）。',
    },
    engagement_timeout = {
        en = 'Engagement Timeout (seconds)',
        ['zh-cn'] = '交战超时（秒）', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '交戰逾時（秒）',
    },
    engagement_timeout_tooltip = {
        en = 'Time in seconds before ending an enemy engagement due to inactivity.',
        ['zh-cn'] = '由于不活动而结束敌人交战的时间（秒）。', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '因未活動而結束敵人交戰前的等待時間（秒）。',
    },
    enemy_types_to_track = {
        en = 'Enemy Types to Track',
        ['zh-cn'] = '追踪的敌人类型',
        ['zh-tw'] = '要追蹤的敵人類型',
    },

    -- Common Stats
    unknown = {
        en = 'unknown',
        ['zh-cn'] = '未知',
        ['zh-tw'] = '未知',
    },
    time = {
        en = 'Time',
        ['zh-cn'] = '时间',
        ['zh-tw'] = '時間',
    },
    kills = {
        en = 'Kills',
        ['zh-cn'] = '击杀数',
        ['zh-tw'] = '擊殺數',
    },
    dps = {
        en = 'DPS',
        ['zh-cn'] = 'DPS',
        ['zh-tw'] = 'DPS',
    },
    damage = {
        en = 'Damage',
        ['zh-cn'] = '伤害',
        ['zh-tw'] = '傷害',
    },
    hits = {
        en = 'Hits',
        ['zh-cn'] = '命中数',
        ['zh-tw'] = '命中數',
    },
    total = {
        en = 'Total',
        ['zh-cn'] = '总计',
        ['zh-tw'] = '總計',
    },
    overkill = {
        en = 'Overkill',
        ['zh-cn'] = '过量伤害', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '溢出傷害',
    },
    melee = {
        en = 'Melee',
        ['zh-cn'] = '近战',
        ['zh-tw'] = '近戰',
    },
    ranged = {
        en = 'Ranged',
        ['zh-cn'] = '远程',
        ['zh-tw'] = '遠程',
    },
    explosion = {
        en = 'Explosion',
        ['zh-cn'] = '爆炸',
        ['zh-tw'] = '爆炸',
    },
    companion = {
        en = 'Companion',
        ['zh-cn'] = '同伴',
        ['zh-tw'] = '同伴',
    },
    arc = {
        en = 'Arc',
        ['zh-cn'] = '电弧', -- FIXME: confirm translation, translated via google translate
        ['zh-tw'] = '電弧',
    },
    buff = {
        en = 'Buff',
        ['zh-cn'] = '增益',
        ['zh-tw'] = '增益',
    },
    crit = {
        en = 'Crit',
        ['zh-cn'] = '暴击',
        ['zh-tw'] = '致命一擊',
    },
    weakspot = {
        en = 'Weakspot',
        ['zh-cn'] = '弱点',
        ['zh-tw'] = '弱點',
    },
    bleed = {
        en = 'Bleed',
        ['zh-cn'] = '流血',
        ['zh-tw'] = '流血',
    },
    burn = {
        en = 'Burn',
        ['zh-cn'] = '燃烧',
        ['zh-tw'] = '燃燒',
    },
    toxin = {
        en = 'Toxin',
        ['zh-cn'] = '毒素',
        ['zh-tw'] = '毒素',
    },
    enemy = {
        en = 'Enemy',
        ['zh-cn'] = '敌人',
        ['zh-tw'] = '敵人',
    },
    enemy_type = {
        en = 'Enemy Type',
        ['zh-cn'] = '敌人类型',
        ['zh-tw'] = '敵人類型',
    },

    -- View
    search_placeholder = {
        en = 'Search enemies...',
        ['zh-cn'] = '搜索敌人...',
        ['zh-tw'] = '搜尋敵人...',
    },
    enemy_stats = {
        en = 'Enemy Stats',
        ['zh-cn'] = '敌人统计',
        ['zh-tw'] = '敵人統計',
    },
    damage_stats = {
        en = 'Damage Stats',
        ['zh-cn'] = '伤害统计',
        ['zh-tw'] = '傷害統計',
    },
    hit_stats = {
        en = 'Hit Stats',
        ['zh-cn'] = '命中统计',
        ['zh-tw'] = '命中統計',
    },
    buff_uptime = {
        en = 'Buff Uptime',
        ['zh-cn'] = '增益持续时间',
        ['zh-tw'] = '增益持續時間',
    },

    -- Breed Types
    breed_monster = {
        en = 'monster',
        ['zh-cn'] = '怪物',
        ['zh-tw'] = '巨獸',
    },
    breed_ritualist = {
        en = 'ritualist',
        ['zh-cn'] = '仪式术士',
        ['zh-tw'] = '渣滓祭司',
    },
    breed_disabler = {
        en = 'disabler',
        ['zh-cn'] = '控制型',
        ['zh-tw'] = '控制型',
    },
    breed_special = {
        en = 'special',
        ['zh-cn'] = '专家',
        ['zh-tw'] = '專家',
    },
    breed_elite = {
        en = 'elite',
        ['zh-cn'] = '精英',
        ['zh-tw'] = '精英',
    },
    breed_horde = {
        en = 'horde',
        ['zh-cn'] = '尸潮',
        ['zh-tw'] = '屍潮',
    },
    breed_unknown = {
        en = 'unknown',
        ['zh-cn'] = '未知',
        ['zh-tw'] = '未知',
    },
}
