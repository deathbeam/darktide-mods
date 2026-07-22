local mod = get_mod('CharacterStats')

local Utils = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/character_stats_utils')
local SharedUtils = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/shared/shared_utils')
local ProfileUtils = mod:original_require('scripts/utilities/profile_utils')

local COLORS = {
    HEADER = Color.terminal_text_header(255, true),
    VITAL = { 255, 90, 195, 90 },
    DEFENSE = { 255, 80, 165, 240 },
    OFFENSE = { 255, 171, 91, 81 },
    MOBILITY = Color.ui_hud_yellow_light(255, true),
    META = Color.terminal_text_body_sub_header(255, true),
}

local function _add(records, rec)
    records[#records + 1] = rec
end

local function _section(records, text, color)
    _add(records, { type = 'section', level = 1, text = text, color = color or COLORS.HEADER })
end

local function _stat(records, label, value, color, indent)
    _add(records, {
        type = 'stat',
        label = label,
        value = value,
        label_color = COLORS.META,
        value_color = color,
        indent = indent or 0,
    })
end

local function _spacer(records)
    _add(records, { type = 'spacer', size = 'group' })
end

local function _fmt_num(n)
    if n == nil then
        return '-'
    end
    if math.abs(n - math.floor(n)) < 0.05 then
        return string.format('%d', math.floor(n + 0.5))
    end
    return string.format('%.1f', n)
end

local function _fmt_pct(n)
    if n == nil then
        return '-'
    end
    return string.format('%.0f%%', n * 100)
end

-- "<base> (<suffix>)" — e.g. "Toughness Damage Reduction (Melee)". The suffix words come
-- from the game's own loc keys (proxied via game_loc), so variants stay consistent with it.
local function _variant(base_key, suffix_key)
    return mod:localize(base_key) .. ' (' .. mod:localize(suffix_key) .. ')'
end

-- Render the contributing sources for a stat as indented sub-rows, merged by display name so
-- duplicate curios / multi-template talents collapse to one row with summed deltas.
local function _sources(records, folded, stat_key, stat_type)
    if not folded then
        return
    end
    local list = Utils.sources_for_stat(folded, stat_key)
    if not list or #list == 0 then
        return
    end
    local merged = Utils._merge_sources_by_name(list, 'delta', stat_type)
    for i = 1, #merged do
        local src = merged[i]
        local value_str
        if stat_type == 'mult' then
            value_str = string.format('x%.2f', src.delta)
        elseif stat_type == 'flat' then
            value_str = string.format('%s%.0f', src.delta >= 0 and '+' or '', src.delta)
        else
            value_str = string.format('%s%.0f%%', src.delta >= 0 and '+' or '', src.delta * 100)
        end
        _add(records, {
            type = 'stat',
            label = src.name,
            value = value_str,
            label_color = COLORS.META,
            value_color = COLORS.META,
            indent = 1,
            stripe = true,
        })
    end
end

-- Render a stat line (delta as %) plus its contributing sources, only when the stat has at
-- least one non-default source. Used by the offense/defense additive-bonus blocks.
local function _stat_with_sources(records, folded, label, stat_key, color, src_type)
    if not Utils.has_stat(folded, stat_key) then
        return
    end
    _stat(records, mod:localize(label), _fmt_pct(Utils.stat_delta(folded, stat_key)), color)
    _sources(records, folded, stat_key, src_type or 'add')
end

-- Build the full record list for the currently local player. Returns records plus a name/subtext
-- for the header. When no player is available, returns a placeholder header.
function build_stats()
    local unit, player = Utils.local_player_unit()
    if not player then
        return {}, nil, nil
    end

    local profile = Utils.profile(player)
    local archetype = profile and profile.archetype
    local archetype_name = archetype and archetype.name

    local char_name = ''
    local ok_name, n = pcall(player.name, player)
    if ok_name and n and n ~= '' then
        char_name = n
    end
    local archetype_title = ''
    if profile and archetype then
        local ok_t, t = pcall(ProfileUtils.character_archetype_title, profile, true)
        archetype_title = (ok_t and t) or SharedUtils.safe_localize(archetype.archetype_name) or archetype_name or ''
    end
    local header_icon = archetype and archetype.archetype_badge or nil

    local header_text = char_name ~= '' and char_name or mod:localize('current_character')
    local subtext = archetype_title

    if not unit then
        local records = {}
        _add(records, { type = 'text', text = mod:localize('no_character') })
        return records, header_text, subtext, header_icon
    end

    local records = {}

    local vitals = Utils.vitals(unit)
    local stat_buffs = vitals.stat_buffs
    local wep_template = Utils.wielded_weapon_template(unit)

    local toggles = {
        assume_proc_stacks = mod:get('assume_proc_stacks'),
        havoc_rank = mod:get('havoc_rank') or 0,
        coherency_allies = mod:get('coherency_allies') or 3,
    }
    local folded = Utils.folded_stat_buffs(stat_buffs, unit, profile, player, toggles)

    -- Derive max_health/max_toughness from base + folded buffs: the live extension reads
    -- return the base value where curio/talent buffs aren't active (e.g. the hub).
    local folded_max_health, folded_max_toughness =
        Utils.compute_max_vitals(folded, vitals.archetype, vitals.toughness_template)
    local max_health = folded_max_health or vitals.max_health
    vitals.max_toughness = folded_max_toughness or vitals.max_toughness

    -- BIO: field type header with the chosen option as subtext, then the description text.
    local bio = Utils.character_bio(profile)
    if bio and #bio > 0 then
        _section(records, mod:localize('header_bio'), COLORS.HEADER)
        for i = 1, #bio do
            local e = bio[i]
            _add(records, {
                type = 'section',
                level = 2,
                text = e.title,
                subtext = e.option,
                color = COLORS.META,
                subtext_color = COLORS.HEADER,
            })
            if e.text and e.text ~= '' then
                _add(records, { type = 'text', text = e.text })
            end
        end
        _spacer(records)
    end

    -- VITALS
    _section(records, mod:localize('header_vitals'), COLORS.VITAL)
    if max_health then
        _stat(records, mod:localize('stat_health'), _fmt_num(max_health), COLORS.VITAL)
        _sources(records, folded, 'max_health_modifier', 'add')
        _sources(records, folded, 'max_health_multiplier', 'add')
    end
    if vitals.max_wounds then
        _stat(records, mod:localize('stat_wounds'), _fmt_num(vitals.max_wounds), COLORS.VITAL)
    end
    if vitals.max_toughness then
        _stat(records, mod:localize('stat_toughness'), _fmt_num(vitals.max_toughness), COLORS.VITAL)
        _sources(records, folded, 'toughness_bonus', 'add')
        _sources(records, folded, 'toughness', 'flat')
        _sources(records, folded, 'toughness_bonus_flat', 'flat')
    end
    _spacer(records)

    -- MOBILITY
    local mobility = Utils.mobility(unit, stat_buffs, folded)
    if mobility then
        _section(records, mod:localize('header_mobility'), COLORS.MOBILITY)
        if mobility.max_stamina then
            _stat(records, mod:localize('stat_stamina'), _fmt_num(mobility.max_stamina), COLORS.MOBILITY)
            _sources(records, folded, 'stamina_modifier', 'flat')
        end
        if mobility.stamina_regen then
            _stat(
                records,
                mod:localize('stat_stamina_regen'),
                string.format('%.1f/s', mobility.stamina_regen),
                COLORS.MOBILITY
            )
            _sources(records, folded, 'stamina_regeneration_modifier', 'add')
        end
        if mobility.stamina_delay then
            _stat(
                records,
                mod:localize('stat_stamina_delay'),
                string.format('%.1fs', mobility.stamina_delay),
                COLORS.MOBILITY
            )
        end
        if mobility.sprint_speed then
            _stat(
                records,
                mod:localize('stat_sprint_speed'),
                string.format('%.1f', mobility.sprint_speed),
                COLORS.MOBILITY
            )
        end
        if mobility.sprint_time then
            _stat(
                records,
                mod:localize('stat_sprint_time'),
                string.format('%.1fs', mobility.sprint_time),
                COLORS.MOBILITY
            )
        end
        if mobility.dodge_count then
            _stat(records, mod:localize('stat_dodge_count'), _fmt_num(mobility.dodge_count), COLORS.MOBILITY)
        end
        if mobility.dodge_dist then
            _stat(records, mod:localize('stat_dodge_dist'), string.format('%.1f', mobility.dodge_dist), COLORS.MOBILITY)
        end
        if mobility.dodge_speed and mobility.dodge_speed ~= 1 then
            _stat(records, mod:localize('stat_dodge_speed'), _fmt_pct(mobility.dodge_speed), COLORS.MOBILITY)
        end
        _spacer(records)
    end

    -- OFFENSE
    _section(records, mod:localize('header_offense'), COLORS.OFFENSE)

    local dmg_mult = Utils.damage_multiplier(folded)
    if dmg_mult then
        if dmg_mult.generic ~= 1 then
            _stat(records, mod:localize('stat_total_damage'), _fmt_pct(dmg_mult.generic - 1), COLORS.OFFENSE)
            _sources(records, folded, 'damage', 'add')
            _sources(records, folded, 'power_level_modifier', 'add')
        end
        if dmg_mult.melee ~= dmg_mult.generic then
            _stat(records, mod:localize('stat_melee_damage'), _fmt_pct(dmg_mult.melee - 1), COLORS.OFFENSE)
            _sources(records, folded, 'melee_damage', 'add')
            _sources(records, folded, 'melee_power_level_modifier', 'add')
        end
        if dmg_mult.ranged ~= dmg_mult.generic then
            _stat(records, mod:localize('stat_ranged_damage'), _fmt_pct(dmg_mult.ranged - 1), COLORS.OFFENSE)
            _sources(records, folded, 'ranged_damage', 'add')
            _sources(records, folded, 'ranged_power_level_modifier', 'add')
        end
    end

    local vs_terms = Utils.damage_vs_terms(folded)
    if vs_terms then
        for i = 1, #vs_terms do
            local t = vs_terms[i]
            _stat(records, mod:localize(t.label), _fmt_pct(t.delta), COLORS.OFFENSE)
            _sources(records, folded, t.key, 'add')
        end
    end

    local atk_speed = Utils.attack_speed(unit, folded, wep_template)
    if atk_speed and atk_speed ~= 1 then
        _stat(records, mod:localize('stat_attack_speed'), _fmt_pct(atk_speed - 1), COLORS.OFFENSE)
        _sources(records, folded, 'attack_speed', 'add')
        _sources(records, folded, 'melee_attack_speed', 'add')
        _sources(records, folded, 'ranged_attack_speed', 'add')
    end

    local crit = Utils.crit_chance(player, unit, wep_template, folded)
    if crit then
        _stat(records, mod:localize('stat_crit_chance'), _fmt_pct(crit), COLORS.OFFENSE)
        _sources(records, folded, 'critical_strike_chance', 'add')
        _sources(records, folded, 'melee_critical_strike_chance', 'add')
        _sources(records, folded, 'ranged_critical_strike_chance', 'add')
    end

    local crit_dmg = Utils.crit_damage_mult(folded, wep_template)
    if crit_dmg and crit_dmg ~= 1 then
        _stat(records, mod:localize('stat_crit_damage'), _fmt_pct(crit_dmg - 1), COLORS.OFFENSE)
        _sources(records, folded, 'critical_strike_damage', 'add')
        _sources(records, folded, 'melee_critical_strike_damage', 'add')
        _sources(records, folded, 'ranged_critical_strike_damage', 'add')
    end

    local weakspot = Utils.weakspot_damage(folded, wep_template)
    if weakspot and weakspot.generic ~= 1 then
        _stat(records, mod:localize('stat_weakspot'), _fmt_pct(weakspot.generic - 1), COLORS.OFFENSE)
        _sources(records, folded, 'weakspot_damage', 'add')
        if weakspot.melee ~= weakspot.generic then
            _stat(records, _variant('stat_weakspot', 'melee'), _fmt_pct(weakspot.melee - 1), COLORS.OFFENSE)
            _sources(records, folded, 'melee_weakspot_damage', 'add')
        end
        if weakspot.ranged ~= weakspot.generic then
            _stat(records, _variant('stat_weakspot', 'ranged'), _fmt_pct(weakspot.ranged - 1), COLORS.OFFENSE)
            _sources(records, folded, 'ranged_weakspot_damage', 'add')
        end
    end

    local rending_terms = Utils.rending_terms(folded, wep_template)
    if rending_terms and #rending_terms > 0 then
        local rending_sum = 0
        for i = 1, #rending_terms do
            rending_sum = rending_sum + rending_terms[i].delta
        end
        _stat(records, mod:localize('stat_rending'), _fmt_pct(rending_sum), COLORS.OFFENSE)
        for i = 1, #rending_terms do
            _sources(records, folded, rending_terms[i].key, 'add')
        end
    end

    _stat_with_sources(records, folded, 'stat_power_level', 'power_level_modifier', COLORS.OFFENSE)
    _sources(records, folded, 'melee_power_level_modifier', 'add')
    _sources(records, folded, 'ranged_power_level_modifier', 'add')

    if Utils.is_ranged(wep_template) then
        _stat_with_sources(records, folded, 'stat_reload_speed', 'reload_speed', COLORS.OFFENSE)
        _stat_with_sources(records, folded, 'stat_spread', 'spread_modifier', COLORS.OFFENSE)
    end

    if Utils.has_stat(folded, 'impact_modifier') then
        _stat(
            records,
            mod:localize('stat_impact'),
            _fmt_pct(Utils.stat_delta(folded, 'impact_modifier')),
            COLORS.OFFENSE
        )
        _sources(records, folded, 'impact_modifier', 'add')
        _sources(records, folded, 'melee_impact_modifier', 'add')
        _sources(records, folded, 'ranged_impact_modifier', 'add')
    end

    if Utils.has_stat(folded, 'movement_speed') then
        _stat(
            records,
            mod:localize('stat_movement_speed'),
            _fmt_pct(Utils.stat_delta(folded, 'movement_speed')),
            COLORS.MOBILITY
        )
        _sources(records, folded, 'movement_speed', 'add')
        _sources(records, folded, 'sprint_movement_speed', 'add')
    end
    _spacer(records)

    -- DEFENSE
    local dmg_taken = Utils.damage_taken(folded)
    local has_health = max_health and max_health > 0
    local has_defense = dmg_taken and (dmg_taken.generic ~= 1 or dmg_taken.melee ~= 1 or dmg_taken.ranged ~= 1)

    _section(records, mod:localize('header_defense'), COLORS.DEFENSE)
    if has_defense and has_health then
        if dmg_taken.generic ~= 1 then
            _stat(records, mod:localize('stat_damage_reduction'), _fmt_pct(1 - dmg_taken.generic), COLORS.DEFENSE)
            _sources(records, folded, 'damage_taken_multiplier', 'mult')
            _sources(records, folded, 'damage_taken_modifier', 'add')
        end
        if dmg_taken.melee ~= dmg_taken.generic then
            _stat(records, _variant('stat_damage_reduction', 'melee'), _fmt_pct(1 - dmg_taken.melee), COLORS.DEFENSE)
            _sources(records, folded, 'melee_damage_taken_multiplier', 'mult')
            _sources(records, folded, 'melee_damage_taken_modifier', 'add')
        end
        if dmg_taken.ranged ~= dmg_taken.generic then
            _stat(records, _variant('stat_damage_reduction', 'ranged'), _fmt_pct(1 - dmg_taken.ranged), COLORS.DEFENSE)
            _sources(records, folded, 'ranged_damage_taken_multiplier', 'mult')
            _sources(records, folded, 'ranged_damage_taken_modifier', 'add')
        end
    end

    local tough_taken = Utils.toughness_damage_taken(folded)
    local has_tough_defense = tough_taken
        and (tough_taken.generic ~= 1 or tough_taken.melee ~= 1 or tough_taken.ranged ~= 1)
    if has_tough_defense then
        if tough_taken.generic ~= 1 then
            _stat(records, mod:localize('stat_tough_reduction'), _fmt_pct(1 - tough_taken.generic), COLORS.DEFENSE)
            _sources(records, folded, 'toughness_damage_taken_multiplier', 'mult')
            _sources(records, folded, 'toughness_damage_taken_modifier', 'add')
        end
        if tough_taken.melee ~= tough_taken.generic then
            _stat(records, _variant('stat_tough_reduction', 'melee'), _fmt_pct(1 - tough_taken.melee), COLORS.DEFENSE)
            _sources(records, folded, 'melee_toughness_damage_taken_multiplier', 'mult')
            _sources(records, folded, 'melee_toughness_damage_taken_modifier', 'add')
        end
        if tough_taken.ranged ~= tough_taken.generic then
            _stat(records, _variant('stat_tough_reduction', 'ranged'), _fmt_pct(1 - tough_taken.ranged), COLORS.DEFENSE)
            _sources(records, folded, 'ranged_toughness_damage_taken_multiplier', 'mult')
            _sources(records, folded, 'ranged_toughness_damage_taken_modifier', 'add')
        end
    end

    local source_terms = Utils.damage_taken_from_sources(folded)
    if source_terms then
        for i = 1, #source_terms do
            local t = source_terms[i]
            local reduction = t.kind == 'mult' and (1 - t.value) or -t.delta
            _stat(records, mod:localize(t.label), _fmt_pct(reduction), COLORS.DEFENSE)
            -- A grouped term's keys share identical sources (one perk buffs every breed
            -- in the group to the same value), so render sources from the first key only.
            _sources(records, folded, t.keys[1], t.kind == 'mult' and 'mult' or 'add')
        end
    end
    _spacer(records)

    -- TOUGHNESS regen
    if vitals.toughness_template then
        local tough_template = vitals.toughness_template
        local coherency_regen, percent_regen, coherency_mult =
            Utils.toughness_regen(unit, stat_buffs, tough_template, vitals.max_toughness, folded)
        local regen_delay = Utils.toughness_regen_delay(unit, stat_buffs, tough_template)
        local bounty =
            Utils.toughness_melee_bounty(unit, stat_buffs, tough_template, vitals.max_toughness, wep_template)
        local bonus_regen, bonus_sources = Utils.toughness_bonus_regen(unit, profile, toggles)

        _section(records, mod:localize('header_toughness'), COLORS.DEFENSE)
        if coherency_regen then
            _stat(
                records,
                mod:localize('stat_toughness_regen'),
                string.format('%.1f/s', coherency_regen),
                COLORS.DEFENSE
            )
            _sources(records, folded, 'toughness_regen_rate_modifier', 'add')
            _sources(records, folded, 'toughness_regen_rate_multiplier', 'mult')
            _sources(records, folded, 'toughness_coherency_regen_rate_modifier', 'add')
            _sources(records, folded, 'toughness_extra_regen_rate', 'add')
            _sources(records, folded, 'toughness_coherency_regen_rate_multiplier', 'mult')
        end
        if percent_regen and percent_regen ~= 0 then
            _stat(
                records,
                mod:localize('stat_toughness_regen_percent'),
                string.format('%.1f/s', percent_regen),
                COLORS.DEFENSE
            )
            _sources(records, folded, 'toughness_regen_percent', 'add')
        end
        -- Bonus regen from proc/over-time talents: these call Toughness.replenish_percentage
        -- directly (not stat buffs), so they are computed separately and shown per-source.
        if bonus_regen and vitals.max_toughness then
            local bonus_per_s = bonus_regen * vitals.max_toughness
            _stat(records, mod:localize('stat_tough_bonus_regen'), string.format('%.1f/s', bonus_per_s), COLORS.DEFENSE)
            if bonus_sources then
                for i = 1, #bonus_sources do
                    local src = bonus_sources[i]
                    local src_per_s = src.per_second * vitals.max_toughness
                    _add(records, {
                        type = 'stat',
                        label = src.name,
                        value = string.format('%.1f/s (%.1f%%/s)', src_per_s, src.per_second * 100),
                        label_color = COLORS.META,
                        value_color = COLORS.META,
                        indent = 1,
                        stripe = true,
                    })
                end
            end
        end
        if regen_delay then
            _stat(records, mod:localize('stat_tough_regen_delay'), string.format('%.1fs', regen_delay), COLORS.DEFENSE)
        end
        if bounty and bounty > 0 then
            _stat(records, mod:localize('stat_tough_bounty'), _fmt_num(bounty), COLORS.DEFENSE)
        end
        _spacer(records)
    end

    return records, header_text, subtext, header_icon
end

return {
    build_stats = build_stats,
}
