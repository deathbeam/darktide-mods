local mod = get_mod('WeaponStats')

local WeaponTemplate = mod:original_require('scripts/utilities/weapon/weapon_template')
local Weapon = mod:original_require('scripts/extension_systems/weapon/weapon')
local Action = mod:original_require('scripts/utilities/action/action')
local WeaponTweakTemplates = mod:original_require('scripts/extension_systems/weapon/utilities/weapon_tweak_templates')
local ArmorSettings = mod:original_require('scripts/settings/damage/armor_settings')
local WeaponActionData = mod:original_require('scripts/settings/equipment/weapon_action_handler_data')
local Utils = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_utils')

local COLORS = {
    HEADER = Color.terminal_text_header(255, true),
    ATTACK = Color.ui_terminal(255, true),
    SPECIAL = Color.ui_orange_medium(255, true),
    CRIT = Color.ui_orange_light(255, true),
    WEAKSPOT = Color.ui_hud_yellow_light(255, true),
    DAMAGE = Color.terminal_text_body(255, true),
    TIMING = Color.ui_hud_green_light(255, true),
    META = Color.terminal_text_body_sub_header(255, true),
}

local ARMOR_COLORS = {
    unarmored = Color.ui_hud_red_super_light(255, true),
    armored = Color.ui_blue_light(255, true),
    resistant = Color.ui_hud_red_light(255, true),
    berserker = Color.ui_orange_light(255, true),
    super_armor = Color.ui_brown_light(255, true),
    disgustingly_resilient = Color.ui_hud_green_light(255, true),
    void_shield = Color.ui_hud_warp_charge_low(255, true),
}

local ARMOR_ORDER = {
    'unarmored',
    'armored',
    'resistant',
    'berserker',
    'super_armor',
    'disgustingly_resilient',
    'void_shield',
}

-- Records ----------------------------------------------------------------

local function add(records, rec)
    records[#records + 1] = rec
end

local function add_section(records, text)
    add(records, { type = 'section', text = text, color = COLORS.HEADER })
end

local function add_attack(records, text)
    add(records, { type = 'attack', text = text, color = COLORS.ATTACK })
end

local function add_subheader(records, text, indent)
    add(records, { type = 'subheader', text = text, color = COLORS.HEADER, indent = indent or 0 })
end

local function add_special_active(records)
    add(records, { type = 'attack', text = mod:localize('stat_special_active'), color = COLORS.SPECIAL })
end

local function add_stat(records, label, value, label_color, indent)
    add(records, {
        type = 'stat',
        label = label,
        value = value,
        label_color = label_color or COLORS.META,
        indent = indent or 0,
    })
end

local function add_armor(records, rows, is_ranged, header)
    add(records, {
        type = 'armor',
        header = header,
        color = COLORS.HEADER,
        rows = rows,
        is_ranged = is_ranged,
    })
end

local function add_spacer(records, height)
    add(records, { type = 'spacer', height = height or 8 })
end

local function fmt_num(n)
    if n == nil then
        return '-'
    end
    if math.abs(n - math.floor(n)) < 0.05 then
        return string.format('%d', math.floor(n + 0.5))
    end
    if math.abs(n) >= 100 then
        return string.format('%.0f', n)
    end
    return string.format('%.1f', n)
end

local function fmt_mult(n)
    if n == nil then
        return '-'
    end
    if math.abs(n - 1) < 0.005 then
        return '1.00x'
    end
    return string.format('%.2fx', n)
end

-- weapon_handling is keyed by a per-action identifier from get_template_identifiers,
-- not the raw weapon_handling_template name.
local function handling_template_for_action(weapon_template, weapon_tweak_templates, action_name)
    local handling = weapon_tweak_templates and weapon_tweak_templates.weapon_handling
    if not handling or not weapon_template or not action_name then
        return nil
    end
    local ok, _, identifier =
        pcall(WeaponTweakTemplates.get_template_identifiers, weapon_template, 'weapon_handling', action_name)
    if not ok or not identifier then
        return nil
    end
    return handling[identifier]
end

-- Profile extraction -----------------------------------------------------

local function resolve_template_ref(ref, template_table)
    if type(ref) == 'table' then
        return ref
    end
    if type(ref) == 'string' then
        return template_table[ref]
    end
    return nil
end

local function extract_profiles(action)
    local profiles = {}

    local num_templates = 1
    local ok_n, n = pcall(Action.num_damage_templates, action)
    if ok_n and type(n) == 'number' and n > 0 then
        num_templates = n
    end

    -- Gather main, inner-explosion, and sticky profiles for render_profile to fold together.
    local has_direct_profile = action.damage_profile ~= nil
        or action.inner_damage_profile ~= nil
        or action.sweeps ~= nil

    for i = 1, num_templates do
        local ok, dmg_profile, special_profile = pcall(Action.damage_template, action, i)
        if ok and dmg_profile then
            local ranged_extra
            local cfg_ok, cfg = pcall(function()
                local fire_configs = action.fire_configurations
                if not fire_configs then
                    fire_configs = { action.fire_configuration }
                end
                return fire_configs[i] or fire_configs[1]
            end)
            if cfg_ok and cfg then
                for _, key in ipairs({ 'shotshell', 'hit_scan_template', 'projectile', 'flamer_gas_template' }) do
                    local ref = cfg[key]
                    if ref then
                        local tmpl = resolve_template_ref(ref, _G) or ref
                        if type(tmpl) == 'table' then
                            ranged_extra = ranged_extra or {}
                            ranged_extra.num_pellets = tmpl.num_pellets
                            ranged_extra.spread_pitch = tmpl.spread_pitch
                            ranged_extra.spread_yaw = tmpl.spread_yaw
                        end
                    end
                end
            end

            -- Inner explosion applies separately with its own power level.
            local explosion_profile, explosion_power_level = Utils.explosion_profile(action, i)
            local extra_profile
            if explosion_profile and explosion_profile ~= dmg_profile then
                extra_profile = {
                    profile = explosion_profile,
                    power_level = explosion_power_level,
                }
            end

            -- Sticky ticks: instances-1 normal + 1 last, weighted by tick count.
            local sticky_entries = Utils.sticky_damage_entries(action, false)
            local sticky_entries_special = Utils.sticky_damage_entries(action, true)

            profiles[#profiles + 1] = {
                profile = dmg_profile,
                special_active_profile = special_active_profile,
                extra_profile = extra_profile,
                ranged_extra = ranged_extra,
                sticky_entries = sticky_entries,
                sticky_entries_special = sticky_entries_special,
                template_index = i,
            }
        end
    end
    return profiles
end

-- The game marks the special action via weapon_template.special_action_name
-- (action_bash/action_stab/action_pistol_whip/etc.), so compare against that
-- field rather than substring-matching "special".
local function categorize(action_name, profile, weapon_template)
    if weapon_template and weapon_template.special_action_name == action_name then
        return 'special'
    end
    if string.match(action_name, 'shoot') or string.match(action_name, 'zoom') then
        return 'ranged'
    end
    if profile.melee_attack_strength == 'heavy' or string.match(action_name, 'heavy') then
        return 'heavy'
    end
    if profile.melee_attack_strength == 'light' or string.match(action_name, 'light') then
        return 'light'
    end
    return nil
end

-- Dedup profiles that share a damage profile (so light_1..light_4 collapse).
-- Special-active profiles count toward identity so a power sword's
-- inactive+active pair stays distinct from a plain sword's single profile.
local function profiles_equivalent(a, b)
    if not a or not b or not a.profile or not b.profile then
        return false
    end
    local ap, bp = a.profile, b.profile
    if ap.name ~= bp.name then
        return false
    end
    local function secondary_name(p)
        return p and p.name
    end
    local a_second = secondary_name(a.special_active_profile)
    local b_second = secondary_name(b.special_active_profile)
    if a_second ~= b_second then
        return false
    end
    local ra, rb = a.ranged_extra, b.ranged_extra
    local pa, pb = ra and ra.num_pellets or 0, rb and rb.num_pellets or 0
    if pa ~= pb then
        return false
    end

    -- Explosion/sticky change totals, so they join dedup identity.
    local function extra_name(p)
        return p and p.profile and p.profile.name
    end
    if extra_name(a.extra_profile) ~= extra_name(b.extra_profile) then
        return false
    end

    local function sticky_count(entries)
        if not entries then
            return 0
        end
        local n = 0
        for i = 1, #entries do
            n = n + entries[i].weight
        end
        return n
    end

    return sticky_count(a.sticky_entries) == sticky_count(b.sticky_entries)
        and sticky_count(a.sticky_entries_special) == sticky_count(b.sticky_entries_special)
end

-- Render -----------------------------------------------------------------

-- damage_window_end for attacks, total_time for kinds with no damage window.
local function _action_total_time(action)
    if not action then
        return nil
    end

    local t = action.damage_window_end or action.total_time

    if type(t) ~= 'number' or t == math.huge or t == -math.huge then
        return nil
    end
    return t
end

local function render_timing(records, action, weapon_template, weapon_tweak_templates, action_name)
    local fire_rate_shown = false

    -- Lerpable time_scale resolves to its midpoint.
    local tmpl = handling_template_for_action(weapon_template, weapon_tweak_templates, action_name)
    local raw_time_scale = tmpl and tmpl.time_scale
    local time_scale = Utils.resolve_lerpable(raw_time_scale)
    if type(time_scale) ~= 'number' or time_scale <= 0 then
        time_scale = 1
    end

    if tmpl then
        local auto_fire_time = tmpl.fire_rate and tmpl.fire_rate.auto_fire_time
        if type(auto_fire_time) == 'number' and auto_fire_time > 0 then
            add_stat(
                records,
                mod:localize('stat_fire_rate'),
                string.format('%.2f/s', 1 / auto_fire_time),
                COLORS.TIMING
            )
            fire_rate_shown = true
        end
    end

    if fire_rate_shown then
        return
    end

    -- Chain time from the action's self-loop or start_attack/shoot chain.
    local chain_time
    local chains = action.allowed_chain_actions
    if chains then
        for _, chain_data in pairs(chains) do
            if type(chain_data) == 'table' and chain_data.action_name == action_name and chain_data.chain_time then
                chain_time = chain_data.chain_time
                break
            end
        end
        if not chain_time then
            chain_time = (chains.shoot_pressed and chains.shoot_pressed.chain_time)
                or (chains.start_attack and chains.start_attack.chain_time)
                or (chains.shoot and chains.shoot.chain_time)
        end
    end

    -- Fall back to the action's own duration when no chain time is declared.
    if not chain_time then
        local total_time = _action_total_time(action)
        if total_time and total_time > 0 and total_time < 1000 then
            chain_time = total_time
        end
    end

    if not chain_time or chain_time <= 0 then
        return
    end

    local scaled_time
    if time_scale < 1 and WeaponActionData.action_kinds_with_inverted_timescale[action.kind] then
        scaled_time = chain_time * time_scale
    else
        scaled_time = chain_time / time_scale
    end

    if scaled_time <= 0 then
        return
    end

    local lbl = (action.kind == 'shoot_hit_scan' or action.kind == 'shoot_pellets') and mod:localize('stat_fire_rate')
        or mod:localize('stat_attack_speed')
    add_stat(records, lbl, string.format('%.2f/s', 1 / scaled_time), COLORS.TIMING)
end

-- Ranged profiles carry near/far ADM (point-blank vs max-range falloff); melee has a single value.
local function render_armor(records, profile, target_settings, action_lerp, is_ranged, power_type, header, target_index)
    local armor_order = ARMOR_ORDER
    local rows = {}

    local near_dropoff, far_dropoff
    if is_ranged then
        near_dropoff = 0
        far_dropoff = 1
    end

    for _, armor_key in ipairs(armor_order) do
        local armor_type = ArmorSettings.types[armor_key]
        if armor_type then
            local normal_near = Utils.armor_modifier(
                profile,
                target_settings,
                action_lerp,
                power_type,
                armor_type,
                false,
                near_dropoff,
                target_index
            )
            local crit_near = Utils.armor_modifier(
                profile,
                target_settings,
                action_lerp,
                power_type,
                armor_type,
                true,
                near_dropoff,
                target_index
            )

            local normal_far, crit_far
            if is_ranged then
                normal_far = Utils.armor_modifier(
                    profile,
                    target_settings,
                    action_lerp,
                    power_type,
                    armor_type,
                    false,
                    far_dropoff,
                    target_index
                )
                crit_far = Utils.armor_modifier(
                    profile,
                    target_settings,
                    action_lerp,
                    power_type,
                    armor_type,
                    true,
                    far_dropoff,
                    target_index
                )
            end

            rows[#rows + 1] = {
                name = Utils.armor_name(armor_key),
                name_color = ARMOR_COLORS[armor_key],
                normal = normal_near,
                crit = crit_near,
                has_crit = math.abs(crit_near - normal_near) > 0.005,
                normal_far = normal_far,
                crit_far = crit_far,
                has_far = is_ranged,
            }
        end
    end

    if #rows > 0 then
        add_armor(records, rows, is_ranged, header)
    end
end

local function render_profile(records, ctx)
    local profile = ctx.profile
    local action_lerp = ctx.action_lerp
    local is_ranged = ctx.is_ranged
    local is_active = ctx.is_active
    local power_level = ctx.power_level

    local target_settings, target_index = Utils.target_settings(profile)
    if not target_settings then
        return
    end

    local dropoff = is_ranged and 0 or nil

    if is_active then
        add_special_active(records)
    end

    -- Base damage plus inner-explosion/sticky-tick totals per hit.
    local base_attack, base_impact =
        Utils.base_powers(profile, target_settings, power_level, action_lerp, dropoff, target_index)
    local extra_attack, extra_impact = 0, 0
    if ctx.extra_profile then
        local ep = ctx.extra_profile
        local e_ts, e_idx = Utils.target_settings(ep.profile)
        if e_ts then
            local e_a, e_i =
                Utils.base_powers(ep.profile, e_ts, ep.power_level or power_level, action_lerp, dropoff, e_idx)
            extra_attack = e_a or 0
            extra_impact = e_i or 0
        end
    end
    -- Sticky ticks weighted by instances for the full hit total.
    for _, entry in ipairs(ctx.sticky_entries or {}) do
        local s_ts, s_idx = Utils.target_settings(entry.profile)
        if s_ts then
            local s_pl = entry.power_level or power_level
            local s_a, s_i = Utils.base_powers(entry.profile, s_ts, s_pl, action_lerp, dropoff, s_idx)
            extra_attack = extra_attack + (s_a or 0) * entry.weight
            extra_impact = extra_impact + (s_i or 0) * entry.weight
        end
    end

    if base_attack and (math.abs(base_attack) > 0.01 or extra_attack > 0.01) then
        local total = (base_attack or 0) + extra_attack
        if math.abs(total) > 0.01 then
            add_stat(records, mod:localize('stat_damage'), fmt_num(total), COLORS.DAMAGE)
        end
    end
    if base_impact and (math.abs(base_impact) > 0.01 or extra_impact > 0.01) then
        local total = (base_impact or 0) + extra_impact
        if math.abs(total) > 0.01 then
            add_stat(records, mod:localize('stat_impact'), fmt_num(total), COLORS.DAMAGE)
        end
    end

    -- Cleave target count from the power-curve pipeline.
    local cleave_attack, cleave_impact = Utils.cleave_values(profile, power_level, action_lerp)
    local has_attack_cleave = cleave_attack and math.abs(cleave_attack) > 0.01
    local has_impact_cleave = cleave_impact and math.abs(cleave_impact) > 0.01
    if has_attack_cleave then
        if has_impact_cleave and math.abs(cleave_impact - cleave_attack) > 0.01 then
            add_stat(
                records,
                mod:localize('stat_cleave'),
                string.format('%.2f / %.2f', cleave_attack, cleave_impact),
                COLORS.DAMAGE
            )
        else
            add_stat(records, mod:localize('stat_cleave'), string.format('%.2f', cleave_attack), COLORS.DAMAGE)
        end
    end

    if profile.backstab_bonus and profile.backstab_bonus ~= 0 then
        local bonus = Utils.lerp_entry(profile.backstab_bonus)
        add_stat(records, mod:localize('stat_backstab'), string.format('%.0f%%', bonus * 100), COLORS.WEAKSPOT)
    end

    local weakspot_mult = Utils.finesse_multiplier(profile, target_settings, action_lerp, true, false, target_index)
    local crit_mult = Utils.finesse_multiplier(profile, target_settings, action_lerp, false, true, target_index)
    local crit_weakspot_mult = Utils.finesse_multiplier(profile, target_settings, action_lerp, true, true, target_index)

    local any_mult = (weakspot_mult and math.abs(weakspot_mult - 1) > 0.005)
        or (crit_mult and math.abs(crit_mult - 1) > 0.005)
    if any_mult then
        add_subheader(records, mod:localize('stat_finesse_and_crit'))
        if weakspot_mult and math.abs(weakspot_mult - 1) > 0.005 then
            add_stat(records, mod:localize('stat_weakspot'), fmt_mult(weakspot_mult), COLORS.WEAKSPOT, 1)
        end
        if crit_mult and math.abs(crit_mult - 1) > 0.005 then
            add_stat(records, mod:localize('stat_crit'), fmt_mult(crit_mult), COLORS.CRIT, 1)
        end
        if
            crit_weakspot_mult
            and math.abs(crit_weakspot_mult - math.max(weakspot_mult or 1, crit_mult or 1)) > 0.005
        then
            add_stat(records, mod:localize('stat_crit_plus_weakspot'), fmt_mult(crit_weakspot_mult), COLORS.WEAKSPOT, 1)
        end
    end

    -- Crit modifier: weapon_handling (per-action) then legacy weapon_handling_template.
    local chance_modifier =
        Utils.crit_chance_modifier(ctx.action, ctx.weapon_template, ctx.weapon_tweak_templates, ctx.action_name)
    if chance_modifier then
        local sign = chance_modifier >= 0 and '+' or ''
        add_stat(
            records,
            mod:localize('stat_crit_modifier'),
            string.format('%s%.1f%%', sign, chance_modifier * 100),
            COLORS.CRIT
        )
    end

    local tmpl = handling_template_for_action(ctx.weapon_template, ctx.weapon_tweak_templates, ctx.action_name)
    local crit_strike = tmpl and tmpl.critical_strike
    if crit_strike and crit_strike.max_critical_shots and crit_strike.max_critical_shots ~= 0 then
        add_stat(records, mod:localize('stat_crit_strings'), tostring(crit_strike.max_critical_shots), COLORS.CRIT)
    end

    local ranged_extra = ctx.ranged_extra
    if ranged_extra then
        if ranged_extra.num_pellets then
            add_stat(records, mod:localize('stat_pellets'), string.format('x%d', ranged_extra.num_pellets), COLORS.META)
        end
        if ranged_extra.spread_pitch and ranged_extra.spread_yaw then
            add_stat(
                records,
                mod:localize('stat_spread'),
                string.format('%.1f / %.1f', ranged_extra.spread_pitch, ranged_extra.spread_yaw),
                COLORS.META
            )
        end
    end

    local min_r, max_r = Utils.ranges(profile, action_lerp)
    if min_r and max_r then
        add_stat(records, mod:localize('stat_falloff_range'), string.format('%.0f - %.0f m', min_r, max_r), COLORS.META)
    end

    if profile.suppression_value ~= nil then
        local sup = Utils.lerp_entry(profile.suppression_value, Utils.lerp_from_path(action_lerp, 'suppression_value'))
        if sup and math.abs(sup) > 0.01 then
            add_stat(records, mod:localize('stat_suppression'), fmt_num(sup), COLORS.META)
        end
    end

    local stagger = Utils.stagger_name(profile.stagger_category)
    if stagger then
        add_stat(records, mod:localize('stat_stagger'), stagger, COLORS.META)
    end

    local flags = {}
    if profile.weapon_special then
        flags[#flags + 1] = mod:localize('flag_weapon_special')
    end
    if profile.ignore_stagger_reduction then
        flags[#flags + 1] = mod:localize('flag_ignores_stagger_reduction')
    end
    if profile.ignore_shield then
        flags[#flags + 1] = mod:localize('flag_ignores_shield')
    end
    if profile.ignore_hitzone_multiplier then
        flags[#flags + 1] = mod:localize('flag_ignores_hitzone_multiplier')
    end
    if profile.is_push then
        flags[#flags + 1] = mod:localize('flag_is_push')
    end
    if #flags > 0 then
        add_stat(records, mod:localize('stat_flags'), table.concat(flags, ', '), COLORS.META)
    end

    render_armor(
        records,
        profile,
        target_settings,
        action_lerp,
        is_ranged,
        'attack',
        mod:localize('stat_adm'),
        target_index
    )
    render_armor(
        records,
        profile,
        target_settings,
        action_lerp,
        is_ranged,
        'impact',
        mod:localize('stat_impact'),
        target_index
    )
end

local function render_attack(
    records,
    attack_data,
    category,
    weapon_template,
    weapon_tweak_templates,
    damage_profile_lerp_values
)
    local action = attack_data.action
    local action_name = attack_data.names[1]
    local is_ranged = attack_data.is_ranged

    local labels = {}
    for _, name in ipairs(attack_data.names) do
        labels[#labels + 1] = Utils.friendly_action_label(name)
    end
    add_attack(records, table.concat(labels, ', '))

    local slot_key = category == 'heavy' and 'secondary' or (category == 'special' and 'special') or 'primary'
    local attack_type =
        Utils.attack_type_name(weapon_template, slot_key, attack_data.profile and attack_data.profile.name)
    if attack_type then
        add_stat(records, mod:localize('stat_attack_type'), attack_type, COLORS.META)
    end

    if attack_data.profile.damage_type then
        add_stat(
            records,
            mod:localize('stat_type'),
            tostring(Utils.damage_type_name(attack_data.profile.damage_type)),
            COLORS.META
        )
    end

    render_timing(records, action, weapon_template, weapon_tweak_templates, action_name)

    for _, prof_info in ipairs(attack_data.profiles) do
        local action_lerp = Utils.lerp_for_action(damage_profile_lerp_values, action_name, prof_info.profile)
        local power_level = Utils.action_power_level(action, prof_info.template_index)

        local ctx = {
            profile = prof_info.profile,
            action = action,
            action_name = action_name,
            action_lerp = action_lerp,
            is_ranged = is_ranged,
            is_active = false,
            power_level = power_level,
            ranged_extra = prof_info.ranged_extra,
            extra_profile = prof_info.extra_profile,
            sticky_entries = prof_info.sticky_entries,
            weapon_tweak_templates = weapon_tweak_templates,
            weapon_template = weapon_template,
        }
        render_profile(records, ctx)

        if prof_info.special_active_profile then
            local active_lerp =
                Utils.lerp_for_action(damage_profile_lerp_values, action_name, prof_info.special_active_profile)
            local active_ctx = {
                profile = prof_info.special_active_profile,
                action = action,
                action_name = action_name,
                action_lerp = active_lerp,
                is_ranged = is_ranged,
                is_active = true,
                power_level = power_level,
                ranged_extra = prof_info.ranged_extra,
                extra_profile = prof_info.extra_profile,
                sticky_entries = prof_info.sticky_entries_special or prof_info.sticky_entries,
                weapon_tweak_templates = weapon_tweak_templates,
                weapon_template = weapon_template,
            }
            render_profile(records, active_ctx)
        end
    end

    add_spacer(records, 10)
end

local function build_stats(item)
    if not item then
        return {}
    end

    local weapon_template = WeaponTemplate.weapon_template_from_item(item)
    if not weapon_template or not weapon_template.actions then
        return {}
    end

    local init_ok, weapon_tweak_templates, damage_profile_lerp_values = pcall(function()
        local wt, lerp_values = Weapon._init_traits(nil, weapon_template, item, nil, nil)
        return wt, lerp_values
    end)
    if not init_ok then
        mod:error('Failed to init weapon traits: %s', tostring(weapon_tweak_templates))
        weapon_tweak_templates = nil
        damage_profile_lerp_values = nil
    end

    local is_ranged_weapon = WeaponTemplate.is_ranged(weapon_template)

    local attacks = {
        ranged = {},
        light = {},
        heavy = {},
        special = {},
    }

    for action_name, action in pairs(weapon_template.actions) do
        local profiles = extract_profiles(action)
        if #profiles > 0 then
            local first_profile = profiles[1].profile
            local category = categorize(action_name, first_profile, weapon_template)
            if category then
                local existing = attacks[category]
                local merged = false
                for _, existing_attack in ipairs(existing) do
                    if profiles_equivalent(existing_attack.profiles[1], profiles[1]) then
                        table.insert(existing_attack.names, action_name)
                        merged = true
                        break
                    end
                end
                if not merged then
                    table.insert(existing, {
                        names = { action_name },
                        action = action,
                        profile = first_profile,
                        profiles = profiles,
                        is_ranged = is_ranged_weapon or category == 'ranged',
                    })
                end
            end
        end
    end

    for _, category in pairs(attacks) do
        table.sort(category, function(a, b)
            return a.names[1] < b.names[1]
        end)
    end

    local records = {}
    for _, category in ipairs({ 'ranged', 'light', 'heavy', 'special' }) do
        local category_attacks = attacks[category]
        if #category_attacks > 0 then
            local header
            if category == 'ranged' then
                header = mod:localize('header_ranged_attacks')
            elseif category == 'light' then
                header = mod:localize('header_light_attacks')
            elseif category == 'heavy' then
                header = mod:localize('header_heavy_attacks')
            else
                header = mod:localize('header_weapon_special_attacks')
            end
            add_section(records, header)
            add_spacer(records, 4)
            for _, attack_data in ipairs(category_attacks) do
                render_attack(
                    records,
                    attack_data,
                    category,
                    weapon_template,
                    weapon_tweak_templates,
                    damage_profile_lerp_values
                )
            end
        end
    end

    return records
end

return {
    build_stats = build_stats,
}
