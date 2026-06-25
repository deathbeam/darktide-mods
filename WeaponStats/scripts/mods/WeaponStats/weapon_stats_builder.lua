local mod = get_mod('WeaponStats')

local WeaponTemplate = mod:original_require('scripts/utilities/weapon/weapon_template')
local HitScanTemplates = mod:original_require('scripts/settings/projectile/hit_scan_templates')
local ShotshellTemplates = mod:original_require('scripts/settings/projectile/shotshell_templates')
local Weapon = mod:original_require('scripts/extension_systems/weapon/weapon')

local Utils = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_utils')

local COLORS = {
    HEADER = '255,200,100',
    ATTACK = '100,200,255',
    LABEL = '180,180,180',
    DAMAGE = '255,200,100',
    ARMOR = '255,150,150',
    CRIT = '255,255,100',
    IMPACT = '200,200,255',
    WEAKSPOT = '255,200,100',
    TIMING = '150,255,150',
    FALLOFF = '180,220,255',
    PELLET = '255,180,255',
    ADVANCED = '160,160,200',
}

local function colored(color, text)
    return string.format('{#color(%s)}%s{#reset()}', color, text)
end

local function label(text)
    return colored(COLORS.LABEL, text)
end

local function value(color, text)
    return colored(color, text)
end

local function line(out, lbl, val, val_color)
    return out .. '  ' .. label(lbl) .. ' ' .. value(val_color or COLORS.DAMAGE, val) .. '\n'
end

local function resolve_template_ref(ref, template_table)
    if type(ref) == 'table' then
        return ref
    end
    if type(ref) == 'string' then
        return template_table[ref]
    end
    return nil
end

-- Extract the damage profile and ranged info (pellets, range, power_level) from an action.
local function extract_profile(action)
    if action.damage_profile and type(action.damage_profile) == 'table' then
        return action.damage_profile, nil
    end

    local configs = {}
    if action.fire_configuration then
        configs[#configs + 1] = action.fire_configuration
    end
    if type(action.fire_configurations) == 'table' then
        for _, cfg in ipairs(action.fire_configurations) do
            configs[#configs + 1] = cfg
        end
    end

    for _, cfg in ipairs(configs) do
        if cfg.hit_scan_template then
            local template = resolve_template_ref(cfg.hit_scan_template, HitScanTemplates)
            if template and template.damage and template.damage.impact then
                return template.damage.impact.damage_profile,
                    {
                        range = template.range,
                        power_level = template.power_level,
                    }
            end
        end
        if cfg.shotshell then
            local template = resolve_template_ref(cfg.shotshell, ShotshellTemplates)
            if template and template.damage and template.damage.impact then
                return template.damage.impact.damage_profile,
                    {
                        range = template.range,
                        power_level = template.power_level,
                        num_pellets = template.num_pellets,
                    }
            end
        end
    end

    return nil, nil
end

-- Skip an attack if one with the same effective stats is already listed.
local function is_duplicate(list, profile, action_name, ranged_extra)
    for _, existing in ipairs(list) do
        local e = existing.profile
        local is_same = e.damage_type == profile.damage_type

        if is_same then
            local e_target = e.targets and e.targets[1] or e
            local p_target = profile.targets and profile.targets[1] or profile
            if e_target.power_distribution and p_target.power_distribution then
                local e_dmg = e_target.power_distribution.attack
                local p_dmg = p_target.power_distribution.attack
                if e_dmg and p_dmg then
                    if type(e_dmg) == 'table' and type(p_dmg) == 'table' then
                        is_same = e_dmg[1] == p_dmg[1] and e_dmg[2] == p_dmg[2]
                    else
                        is_same = e_dmg == p_dmg
                    end
                end
            end
        end

        if is_same then
            local e_pellets = existing.ranged_extra and existing.ranged_extra.num_pellets
            local p_pellets = ranged_extra and ranged_extra.num_pellets
            is_same = (e_pellets or 0) == (p_pellets or 0)
        end
        if is_same then
            is_same = (e.finesse_ability_damage_multiplier or 1) == (profile.finesse_ability_damage_multiplier or 1)
                and (e.backstab_bonus or 0) == (profile.backstab_bonus or 0)
                and e.stagger_category == profile.stagger_category
        end

        if is_same and profile.cleave_distribution and e.cleave_distribution then
            for k, v in pairs(profile.cleave_distribution) do
                local ev = e.cleave_distribution[k]
                if type(v) == 'table' then
                    is_same = type(ev) == 'table' and ev[1] == v[1] and ev[2] == v[2]
                else
                    is_same = ev == v
                end
                if not is_same then
                    break
                end
            end
        elseif is_same and (profile.cleave_distribution or e.cleave_distribution) then
            is_same = false
        end

        if is_same then
            table.insert(existing.names, action_name)
            return true
        end
    end
    return false
end

-- Build the per-target damage falloff chain (resolved attack power per target hit).
local function build_falloff_chain(profile, action_lerp)
    local targets = profile.targets
    if not targets then
        return nil
    end

    local chain = {}
    local function add_target(target)
        local attack = target and target.power_distribution and target.power_distribution.attack
        if attack ~= nil then
            chain[#chain + 1] = Utils.resolve_power(action_lerp, attack, 'attack')
        end
    end

    local i = 1
    while targets[i] do
        add_target(targets[i])
        i = i + 1
    end
    add_target(targets.default_target)

    if #chain <= 1 then
        return nil
    end
    return chain
end

local function render_timing(out, action, weapon_tweak_templates, action_name)
    local time_scale = 1
    local total_time = action.total_time or 0
    local fire_rate_shown = false

    if weapon_tweak_templates and weapon_tweak_templates.weapon_handling then
        local handling_templates = weapon_tweak_templates.weapon_handling
        if handling_templates and action.weapon_handling_template then
            local action_template = handling_templates[action.weapon_handling_template]
            if action_template then
                time_scale = action_template.time_scale or 1
                local auto_fire_time = action_template.fire_rate and action_template.fire_rate.auto_fire_time
                if type(auto_fire_time) == 'number' and auto_fire_time > 0 then
                    out = line(out, 'Fire Rate:', string.format('%.2f/s', 1 / auto_fire_time), COLORS.TIMING)
                    fire_rate_shown = true
                end
            end
        end
    end

    -- Melee and semi-auto ranged use the chain time back into the same action.
    if action.allowed_chain_actions and not fire_rate_shown then
        local chain_time
        local chain_actions = action.allowed_chain_actions

        for _, chain_data in pairs(chain_actions) do
            if chain_data.action_name == action_name and chain_data.chain_time then
                chain_time = chain_data.chain_time
                break
            end
        end
        if not chain_time then
            chain_time = (chain_actions.shoot_pressed and chain_actions.shoot_pressed.chain_time)
                or (chain_actions.start_attack and chain_actions.start_attack.chain_time)
                or (chain_actions.shoot and chain_actions.shoot.chain_time)
        end
        if not chain_time and total_time > 0 and total_time < 1000 then
            chain_time = total_time
        end

        if chain_time and chain_time > 0 then
            local lbl = (action.kind == 'shoot_hit_scan' or action.kind == 'shoot_pellets') and 'Fire Rate:'
                or 'Attack Speed:'
            out = line(out, lbl, string.format('%.2f/s', 1 / (chain_time / time_scale)), COLORS.TIMING)
        end
    end

    return out
end

local function render_armor(out, profile, target_settings, action_lerp)
    local results = Utils.resolve_armor_table(profile, target_settings, action_lerp, 'attack')
    if #results == 0 then
        return out
    end

    out = out .. '  ' .. label('Armor Damage:') .. '\n'
    for _, entry in ipairs(results) do
        -- Skip rows that are 100% with no crit difference (keeps the table concise).
        if math.abs(entry.normal - 1) > 0.005 or math.abs(entry.crit - entry.normal) > 0.005 then
            local seg = string.format(
                '    %s: %s',
                Utils.armor_name(entry.armor_key),
                value(COLORS.ARMOR, string.format('%.0f%%', entry.normal * 100))
            )
            if math.abs(entry.crit - entry.normal) > 0.005 then
                seg = seg .. ' ' .. value(COLORS.CRIT, string.format('(C: %.0f%%)', entry.crit * 100))
            end
            out = out .. seg .. '\n'
        end
    end
    return out
end

local function render_attack(out, attack_data, weapon_tweak_templates, damage_profile_lerp_values)
    local profile = attack_data.profile
    local action = attack_data.action
    local action_name = attack_data.names[1]
    local action_lerp = damage_profile_lerp_values and damage_profile_lerp_values[action_name] or nil
    local first_target = profile.targets and profile.targets[1] or profile

    local labels = {}
    for _, name in ipairs(attack_data.names) do
        labels[#labels + 1] = Utils.friendly_action_label(name)
    end
    out = out .. '  ' .. value(COLORS.ATTACK, table.concat(labels, ', ')) .. '\n'

    if profile.damage_type then
        out = line(out, 'Type:', tostring(Utils.damage_type_name(profile.damage_type)), COLORS.LABEL)
    end

    out = render_timing(out, action, weapon_tweak_templates, action_name)

    local ranged_extra = attack_data.ranged_extra
    if ranged_extra then
        if ranged_extra.num_pellets then
            out = line(out, 'Pellets:', string.format('×%d', ranged_extra.num_pellets), COLORS.PELLET)
        end
        if ranged_extra.range then
            out = line(out, 'Range:', tostring(ranged_extra.range), COLORS.PELLET)
        end
        if ranged_extra.power_level then
            out = line(out, 'Power Level:', tostring(ranged_extra.power_level), COLORS.PELLET)
        end
    end

    if first_target.power_distribution and type(first_target.power_distribution) == 'table' then
        if first_target.power_distribution.attack then
            local chain = build_falloff_chain(profile, action_lerp)
            if chain then
                local segments = {}
                for idx, v in ipairs(chain) do
                    if idx > 1 then
                        segments[#segments + 1] = ' ' .. value(COLORS.FALLOFF, '→') .. ' '
                    end
                    segments[#segments + 1] = value(COLORS.DAMAGE, string.format('%.0f', v))
                end
                out = out .. '  ' .. label('Damage:') .. ' ' .. table.concat(segments, '') .. '\n'
            else
                local dmg = Utils.resolve_power(action_lerp, first_target.power_distribution.attack, 'attack')
                out = line(out, 'Damage:', string.format('%.0f', dmg), COLORS.DAMAGE)
            end
        end

        if first_target.power_distribution.impact then
            local impact_dmg = Utils.resolve_power(action_lerp, first_target.power_distribution.impact, 'impact')
            out = line(out, 'Impact:', string.format('%.0f', impact_dmg), COLORS.IMPACT)
        end
    end

    -- Crit modifier (additive modifier to the archetype base crit chance, not the chance itself).
    local crit_chance, max_crit_shots
    if weapon_tweak_templates and weapon_tweak_templates.weapon_handling then
        local handling_templates = weapon_tweak_templates.weapon_handling
        if handling_templates and action.weapon_handling_template then
            local action_template = handling_templates[action.weapon_handling_template]
            local crit_strike = action_template and action_template.critical_strike
            if crit_strike then
                crit_chance = crit_strike.chance_modifier
                max_crit_shots = crit_strike.max_critical_shots
            end
        end
    end

    if crit_chance and crit_chance ~= 0 then
        local sign = crit_chance >= 0 and '+' or ''
        out = line(out, 'Crit Modifier:', string.format('%s%.1f%%', sign, crit_chance * 100), COLORS.CRIT)
    end
    if max_crit_shots and max_crit_shots ~= 0 then
        out = line(out, 'Crit Strings:', tostring(max_crit_shots), COLORS.CRIT)
    end

    if first_target.crit_boost then
        local crit_val = Utils.lerp_entry(first_target.crit_boost)
        if crit_val and crit_val ~= 0 then
            out = line(out, 'Crit Damage:', string.format('%.0f%%', crit_val * 100), COLORS.CRIT)
        end
    end

    if profile.finesse_ability_damage_multiplier and profile.finesse_ability_damage_multiplier ~= 1 then
        local mult = Utils.lerp_entry(profile.finesse_ability_damage_multiplier)
        out = line(out, 'Weakspot:', string.format('%.1fx', mult), COLORS.WEAKSPOT)
    end

    if profile.backstab_bonus and profile.backstab_bonus ~= 0 then
        local bonus = Utils.lerp_entry(profile.backstab_bonus)
        out = line(out, 'Backstab:', string.format('%.0f%%', bonus * 100), COLORS.WEAKSPOT)
    end

    if profile.cleave_distribution and type(profile.cleave_distribution) == 'table' then
        local cleave_lerp = Utils.lerp_from_path(action_lerp, 'cleave_distribution', 'attack') or 0.5
        local attack_cleave = profile.cleave_distribution.attack
        local impact_cleave = profile.cleave_distribution.impact
        local attack_str = Utils.lerp_entry(attack_cleave, cleave_lerp)
        local impact_str = Utils.lerp_entry(impact_cleave, cleave_lerp)
        if type(attack_str) == 'number' and attack_str > 0.01 then
            if type(impact_str) == 'number' and impact_str > 0.01 and math.abs(impact_str - attack_str) > 0.01 then
                out = line(out, 'Cleave:', string.format('%.1f (A) / %.1f (I)', attack_str, impact_str), COLORS.DAMAGE)
            else
                out = line(out, 'Cleave:', string.format('%.1f', attack_str), COLORS.DAMAGE)
            end
        end
    end

    local stagger = Utils.stagger_name(profile.stagger_category)
    if stagger then
        out = line(out, 'Stagger:', stagger, COLORS.LABEL)
    end

    -- Extra detail that only applies to some attacks.
    if first_target.boost_curve_multiplier_finesse and type(first_target.boost_curve_multiplier_finesse) == 'table' then
        local curve = first_target.boost_curve_multiplier_finesse
        out = line(out, 'Finesse Curve:', string.format('%.2f - %.2f', curve[1], curve[2]), COLORS.ADVANCED)
    end
    if first_target.power_level_multiplier and type(first_target.power_level_multiplier) == 'table' then
        local plm = first_target.power_level_multiplier
        out = line(out, 'Power Mult:', string.format('%.2f - %.2f', plm[1], plm[2]), COLORS.ADVANCED)
    end

    local gib_power = Utils.gibbing_power_name(profile.gibbing_power)
    local gib_type = Utils.gibbing_type_name(profile.gibbing_type)
    local gib_parts = {}
    if gib_power then
        gib_parts[#gib_parts + 1] = gib_power
    end
    if gib_type then
        gib_parts[#gib_parts + 1] = gib_type
    end
    if #gib_parts > 0 then
        out = line(out, 'Gibbing:', table.concat(gib_parts, ' / '), COLORS.ADVANCED)
    end

    local flags = {}
    if profile.weapon_special then
        flags[#flags + 1] = 'Weapon Special'
    end
    if profile.ignore_stagger_reduction then
        flags[#flags + 1] = 'Ignores Stagger Reduction'
    end
    if #flags > 0 then
        out = line(out, 'Flags:', table.concat(flags, ', '), COLORS.ADVANCED)
    end

    local target_settings = profile.targets and (profile.targets[1] or profile.targets.default_target) or profile
    out = render_armor(out, profile, target_settings, action_lerp)

    return out .. '\n'
end

local function build_stats_text(item)
    if not item then
        return 'No weapon selected'
    end

    local weapon_template = WeaponTemplate.weapon_template_from_item(item)
    if not weapon_template or not weapon_template.actions then
        return 'No weapon template found'
    end

    -- _init_traits can fail on malformed items; degrade gracefully instead of crashing.
    local init_ok, weapon_tweak_templates, damage_profile_lerp_values = pcall(function()
        local wt, lerp_values = Weapon._init_traits(nil, weapon_template, item, nil, nil)
        return wt, lerp_values
    end)
    if not init_ok then
        mod:error('Failed to init weapon traits: %s', tostring(weapon_tweak_templates))
        weapon_tweak_templates = nil
        damage_profile_lerp_values = nil
    end

    local attacks = {
        ranged = {},
        light = {},
        heavy = {},
        special = {},
    }

    for action_name, action in pairs(weapon_template.actions) do
        local profile, ranged_extra = extract_profile(action)
        if profile then
            local category
            if string.match(action_name, 'special') then
                category = 'special'
            elseif string.match(action_name, 'shoot') or string.match(action_name, 'zoom') then
                category = 'ranged'
            elseif profile.melee_attack_strength == 'heavy' or string.match(action_name, 'heavy') then
                category = 'heavy'
            elseif profile.melee_attack_strength == 'light' or string.match(action_name, 'light') then
                category = 'light'
            end
            if category and not is_duplicate(attacks[category], profile, action_name, ranged_extra) then
                table.insert(attacks[category], {
                    names = { action_name },
                    action = action,
                    profile = profile,
                    ranged_extra = ranged_extra,
                })
            end
        end
    end

    -- Stable, sensible combo order (e.g. light_1, light_2, light_3).
    for _, category in pairs(attacks) do
        table.sort(category, function(a, b)
            return a.names[1] < b.names[1]
        end)
    end

    local text = ''
    for _, category in ipairs({ 'ranged', 'light', 'heavy', 'special' }) do
        local category_attacks = attacks[category]
        if #category_attacks > 0 then
            text = text .. colored(COLORS.HEADER, string.upper(category) .. ' ATTACKS') .. '\n\n'
            for _, attack_data in ipairs(category_attacks) do
                text = render_attack(text, attack_data, weapon_tweak_templates, damage_profile_lerp_values)
            end
        end
    end

    return text
end

return {
    build_stats_text = build_stats_text,
}
