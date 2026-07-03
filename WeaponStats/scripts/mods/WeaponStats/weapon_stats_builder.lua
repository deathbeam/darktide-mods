local mod = get_mod('WeaponStats')

local WeaponTemplate = mod:original_require('scripts/utilities/weapon/weapon_template')
local Weapon = mod:original_require('scripts/extension_systems/weapon/weapon')
local Action = mod:original_require('scripts/utilities/action/action')
local WeaponTweakTemplates = mod:original_require('scripts/extension_systems/weapon/utilities/weapon_tweak_templates')
local ArmorSettings = mod:original_require('scripts/settings/damage/armor_settings')
local Utils = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_utils')

-- Colors
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
    SPECIAL = '255,140,255',
}

-- Helpers -----------------------------------------------------------------

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

-- Format a number compactly: integers as-is, small fractions with 1-2 decimals.
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

-- Resolve the per-action weapon-handling template. The built weapon_handling table is keyed by
-- a per-action identifier from get_template_identifiers, NOT the raw weapon_handling_template name
-- -- so we must use that helper (matching the game's weapon_stats.lua).
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

-- Profile extraction ------------------------------------------------------

-- Resolve a template reference (table or name) against a registry of templates.
local function resolve_template_ref(ref, template_table)
    if type(ref) == 'table' then
        return ref
    end
    if type(ref) == 'string' then
        return template_table[ref]
    end
    return nil
end

-- Extract every (damage_profile, info) pair an action can deal, using the game's own
-- Action.damage_template helper so we cover melee sweeps, hitscan, shotshell, projectile,
-- flamer gas, and explosion profiles uniformly.
local function extract_profiles(action)
    local profiles = {}

    local num_templates = 1
    local ok_n, n = pcall(Action.num_damage_templates, action)
    if ok_n and type(n) == 'number' and n > 0 then
        num_templates = n
    end

    -- A secondary profile is either a special-active mode (melee with damage_profile_special_active)
    -- or an on-hit explosion (ranged hitscan/projectile). We only surface the special-active;
    -- explosions are skipped (the main profile already carries crit/weakspot data).
    local has_direct_profile = action.damage_profile ~= nil
        or action.inner_damage_profile ~= nil
        or action.sweeps ~= nil

    for i = 1, num_templates do
        local ok, dmg_profile, special_profile = pcall(Action.damage_template, action, i)
        if ok and dmg_profile then
            -- Ranged: pull pellets/range/power_level out of the source fire config template.
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
                            ranged_extra.range = tmpl.range
                            ranged_extra.spread_pitch = tmpl.spread_pitch
                            ranged_extra.spread_yaw = tmpl.spread_yaw
                        end
                    end
                end
            end

            -- The secondary profile is either a special-active mode (melee with
            -- damage_profile_special_active) or an on-hit explosion (ranged hitscan/projectile).
            -- We only surface the special-active; explosions are skipped (their impact damage
            -- isn't shown separately, and the main profile already carries crit/weakspot data).
            local special_active_profile
            if special_profile and special_profile ~= dmg_profile and has_direct_profile then
                special_active_profile = special_profile
            end

            profiles[#profiles + 1] = {
                profile = dmg_profile,
                special_active_profile = special_active_profile,
                ranged_extra = ranged_extra,
                template_index = i,
            }
        end
    end

    return profiles
end

-- Category (light/heavy/ranged/special). The game marks the special action via
-- weapon_template.special_action_name (action_bash/action_stab/action_pistol_whip/etc. --
-- names that don't all contain "special"), so compare against that field, not substring-match.
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

-- Two profiles are "the same" for dedup purposes (so we don't list light_1..light_4 separately
-- when they share a damage profile). Special-active profiles count toward identity so a power
-- sword's inactive+active pair is kept distinct from a plain sword's single profile.
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
    -- Identity covers the special-active secondary profile so two attacks only collapse together
    local a_second = secondary_name(a.special_active_profile)
    local b_second = secondary_name(b.special_active_profile)
    if a_second ~= b_second then
        return false
    end
    local ra, rb = a.ranged_extra, b.ranged_extra
    local pa, pb = ra and ra.num_pellets or 0, rb and rb.num_pellets or 0
    return pa == pb
end

-- Render a single (profile) block ----------------------------------------

local function render_timing(out, action, weapon_template, weapon_tweak_templates, action_name)
    local time_scale = 1
    local total_time = action.total_time or 0
    local fire_rate_shown = false

    local tmpl = handling_template_for_action(weapon_template, weapon_tweak_templates, action_name)
    if tmpl then
        time_scale = tmpl.time_scale or 1
        local auto_fire_time = tmpl.fire_rate and tmpl.fire_rate.auto_fire_time
        if type(auto_fire_time) == 'number' and auto_fire_time > 0 then
            out = line(out, 'Fire Rate:', string.format('%.2f/s', 1 / auto_fire_time), COLORS.TIMING)
            fire_rate_shown = true
        end
    end

    if not fire_rate_shown and action.allowed_chain_actions then
        local chain_time
        local chains = action.allowed_chain_actions
        for _, chain_data in pairs(chains) do
            if chain_data.action_name == action_name and chain_data.chain_time then
                chain_time = chain_data.chain_time
                break
            end
        end
        if not chain_time then
            chain_time = (chains.shoot_pressed and chains.shoot_pressed.chain_time)
                or (chains.start_attack and chains.start_attack.chain_time)
                or (chains.shoot and chains.shoot.chain_time)
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

-- Render one damage profile (inactive or special-active) for an attack.
local render_armor
local function render_profile(out, ctx)
    local profile = ctx.profile
    local action_lerp = ctx.action_lerp
    local is_ranged = ctx.is_ranged
    local is_active = ctx.is_active
    local power_level = ctx.power_level

    local target_settings = Utils.target_settings(profile, is_ranged)
    if not target_settings then
        return out
    end

    local dropoff = is_ranged and 0 or nil

    if is_active then
        out = out .. '    ' .. value(COLORS.SPECIAL, '> Special Active') .. '\n'
    end

    -- Base resolved damage (matches the in-game card) and impact.
    local base_attack, base_impact = Utils.base_powers(profile, target_settings, power_level, action_lerp, dropoff)
    if base_attack and math.abs(base_attack) > 0.01 then
        out = line(out, 'Damage:', fmt_num(base_attack), COLORS.DAMAGE)
    end
    if base_impact and math.abs(base_impact) > 0.01 then
        out = line(out, 'Impact:', fmt_num(base_impact), COLORS.IMPACT)
    end

    -- Multipliers: weakspot (finesse), crit, and crit+weakspot.
    local weakspot_mult = Utils.finesse_multiplier(profile, target_settings, action_lerp, true, false)
    local crit_mult = Utils.finesse_multiplier(profile, target_settings, action_lerp, false, true)
    local crit_weakspot_mult = Utils.finesse_multiplier(profile, target_settings, action_lerp, true, true)

    local any_mult = (weakspot_mult and math.abs(weakspot_mult - 1) > 0.005)
        or (crit_mult and math.abs(crit_mult - 1) > 0.005)
    if any_mult then
        out = out .. '  ' .. label('Multipliers:') .. '\n'
        if weakspot_mult and math.abs(weakspot_mult - 1) > 0.005 then
            out = line(out, '  Weakspot:', fmt_mult(weakspot_mult), COLORS.WEAKSPOT)
        end
        if crit_mult and math.abs(crit_mult - 1) > 0.005 then
            out = line(out, '  Crit:', fmt_mult(crit_mult), COLORS.CRIT)
        end
        if
            crit_weakspot_mult
            and math.abs(crit_weakspot_mult - math.max(weakspot_mult or 1, crit_mult or 1)) > 0.005
        then
            out = line(out, '  Crit+Weak:', fmt_mult(crit_weakspot_mult), COLORS.CRIT)
        end
    end

    -- Ranged-specific: pellets, range, effective range, spread, suppression.
    local ranged_extra = ctx.ranged_extra
    if ranged_extra then
        if ranged_extra.num_pellets then
            out = line(out, 'Pellets:', string.format('x%d', ranged_extra.num_pellets), COLORS.PELLET)
        end
        if ranged_extra.range then
            out = line(out, 'Max Range:', tostring(ranged_extra.range), COLORS.PELLET)
        end
        if ranged_extra.spread_pitch and ranged_extra.spread_yaw then
            out = line(
                out,
                'Spread:',
                string.format('%.1f / %.1f', ranged_extra.spread_pitch, ranged_extra.spread_yaw),
                COLORS.PELLET
            )
        end
    end

    local min_r, max_r = Utils.ranges(profile, action_lerp)
    if min_r and max_r then
        out = line(out, 'Effective Range:', string.format('%.0f - %.0f m', min_r, max_r), COLORS.FALLOFF)
    end

    if profile.suppression_value ~= nil then
        local sup = Utils.lerp_entry(profile.suppression_value, Utils.lerp_from_path(action_lerp, 'suppression_value'))
        if sup and math.abs(sup) > 0.01 then
            out = line(out, 'Suppression:', fmt_num(sup), COLORS.ADVANCED)
        end
    end

    -- Crit modifier (weapon handling) and crit strings.
    local tmpl = handling_template_for_action(ctx.weapon_template, ctx.weapon_tweak_templates, ctx.action_name)
    local crit_strike = tmpl and tmpl.critical_strike
    if crit_strike then
        if crit_strike.chance_modifier and crit_strike.chance_modifier ~= 0 then
            local sign = crit_strike.chance_modifier >= 0 and '+' or ''
            out = line(
                out,
                'Crit Modifier:',
                string.format('%s%.1f%%', sign, crit_strike.chance_modifier * 100),
                COLORS.CRIT
            )
        end
        if crit_strike.max_critical_shots and crit_strike.max_critical_shots ~= 0 then
            out = line(out, 'Crit Strings:', tostring(crit_strike.max_critical_shots), COLORS.CRIT)
        end
    end

    -- Backstab bonus (extra damage on rear hits).
    if profile.backstab_bonus and profile.backstab_bonus ~= 0 then
        local bonus = Utils.lerp_entry(profile.backstab_bonus)
        out = line(out, 'Backstab:', string.format('%.0f%%', bonus * 100), COLORS.WEAKSPOT)
    end

    -- Cleave (attack/impact distribution).
    if profile.cleave_distribution and type(profile.cleave_distribution) == 'table' then
        local cleave_lerp = Utils.lerp_from_path(action_lerp, 'cleave_distribution', 'attack') or Utils.fallback_lerp()
        local attack_cleave = Utils.lerp_entry(profile.cleave_distribution.attack, cleave_lerp)
        local impact_cleave = Utils.lerp_entry(profile.cleave_distribution.impact, cleave_lerp)
        if type(attack_cleave) == 'number' and attack_cleave > 0.01 then
            if
                type(impact_cleave) == 'number'
                and impact_cleave > 0.01
                and math.abs(impact_cleave - attack_cleave) > 0.01
            then
                out = line(out, 'Cleave:', string.format('%.2f / %.2f', attack_cleave, impact_cleave), COLORS.DAMAGE)
            else
                out = line(out, 'Cleave:', string.format('%.2f', attack_cleave), COLORS.DAMAGE)
            end
        end
    end

    -- Stagger category.
    local stagger = Utils.stagger_name(profile.stagger_category)
    if stagger then
        out = line(out, 'Stagger:', stagger, COLORS.LABEL)
    end

    -- Gibbing.
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

    -- Flags.
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

    -- Armor damage table (normal / crit).
    out = render_armor(out, profile, target_settings, action_lerp, dropoff)

    return out
end

-- Per-armor damage modifiers as percentages.
render_armor = function(out, profile, target_settings, action_lerp, dropoff)
    local armor_order = Utils.armor_order()
    local has_any = false
    local rows = {}

    for _, armor_key in ipairs(armor_order) do
        local armor_type = ArmorSettings.types[armor_key]
        if armor_type then
            local normal =
                Utils.armor_modifier(profile, target_settings, action_lerp, 'attack', armor_type, false, dropoff)
            local crit =
                Utils.armor_modifier(profile, target_settings, action_lerp, 'attack', armor_type, true, dropoff)
            if normal and (math.abs(normal - 1) > 0.005 or math.abs(crit - normal) > 0.005) then
                has_any = true
                rows[#rows + 1] = { armor_key = armor_key, normal = normal, crit = crit }
            end
        end
    end

    if not has_any then
        return out
    end

    out = out .. '  ' .. label('Armor Damage:') .. '\n'
    for _, entry in ipairs(rows) do
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
    return out
end

-- Render one attack (which may carry an inactive + a special-active profile).
local function render_attack(out, attack_data, weapon_template, weapon_tweak_templates, damage_profile_lerp_values)
    local action = attack_data.action
    local action_name = attack_data.names[1]
    local is_ranged = attack_data.is_ranged

    local labels = {}
    for _, name in ipairs(attack_data.names) do
        labels[#labels + 1] = Utils.friendly_action_label(name)
    end
    out = out .. '  ' .. value(COLORS.ATTACK, table.concat(labels, ', ')) .. '\n'

    if attack_data.profile.damage_type then
        out = line(out, 'Type:', tostring(Utils.damage_type_name(attack_data.profile.damage_type)), COLORS.LABEL)
    end

    out = render_timing(out, action, weapon_template, weapon_tweak_templates, action_name)

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
            weapon_tweak_templates = weapon_tweak_templates,
            weapon_template = weapon_template,
        }
        out = render_profile(out, ctx)

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
                weapon_tweak_templates = weapon_tweak_templates,
                weapon_template = weapon_template,
            }
            out = render_profile(out, active_ctx)
        end
    end

    return out .. '\n'
end

-- Build the full stats text for a weapon item ----------------------------

local function build_stats_text(item)
    if not item then
        return 'No weapon selected'
    end

    local weapon_template = WeaponTemplate.weapon_template_from_item(item)
    if not weapon_template or not weapon_template.actions then
        return 'No weapon template found'
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
            -- Use the first profile for categorization.
            local first_profile = profiles[1].profile
            local category = categorize(action_name, first_profile, weapon_template)
            if category then
                -- Dedup against existing attacks in this category. Special-active-aware so
                -- power sword combos (which differ only in the active profile) are preserved.
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

    local text = ''
    for _, category in ipairs({ 'ranged', 'light', 'heavy', 'special' }) do
        local category_attacks = attacks[category]
        if #category_attacks > 0 then
            local header = string.upper(category)
            if category == 'ranged' and not is_ranged_weapon then
                header = 'RANGED (ALT)'
            elseif category == 'special' then
                header = 'WEAPON SPECIAL'
            end
            text = text .. colored(COLORS.HEADER, header .. ' ATTACKS') .. '\n\n'
            for _, attack_data in ipairs(category_attacks) do
                text = render_attack(
                    text,
                    attack_data,
                    weapon_template,
                    weapon_tweak_templates,
                    damage_profile_lerp_values
                )
            end
        end
    end

    return text
end

return {
    build_stats_text = build_stats_text,
}
