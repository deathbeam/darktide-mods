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

-- " (Melee, Monsters)" suffix for source rows / variant totals. The tag words come from
-- the game's own loc keys (melee/ranged) or our variant_* keys, so variants stay consistent.
local function _variant_tag(tags)
    if not tags or #tags == 0 then
        return ''
    end
    local parts = {}
    for i = 1, #tags do
        parts[i] = mod:localize(tags[i])
    end
    return ' (' .. table.concat(parts, ', ') .. ')'
end

-- A mult_pool entry names its pool (e.g. pool = 'strength') so the factor can be labelled
-- (strength -> "Power") and several pools render as separate labelled xN.NN steps. The loc key is
-- auto-derived as 'pool_' .. name, falling back to prettify when no entry exists.
local function _pool_label(name)
    return name and SharedUtils.localize_or_prettify(mod, 'pool_', name) or nil
end

-- Format a source row's value by stat type: xN.NN for mult/mult_pool (+ optional pool label),
-- +N for flat, +N.N% for add.
local function _fmt_source_value(delta, stat_type, pool_label)
    if stat_type == 'mult' then
        return SharedUtils.fmt_mult(delta)
    elseif stat_type == 'mult_pool' then
        local s = SharedUtils.fmt_mult(1 + delta)
        return pool_label and s .. ' (' .. pool_label .. ')' or s
    elseif stat_type == 'flat' then
        return (delta >= 0 and '+' or '') .. SharedUtils.fmt_num(delta)
    end
    return (delta >= 0 and '+' or '') .. SharedUtils.fmt_pct(delta)
end

-- Render the contributing sources for a stat as indented sub-rows, merged by display name so
-- duplicate curios / multi-template talents collapse to one row with summed deltas.
-- Like _sources but appends `tag` (e.g. " (Melee)") to each source's label, so a merged
-- variant group shows which variant each source contributes to.
local function _sources_tagged(records, folded, stat_key, stat_type, tag, pool_label)
    if not folded then
        return
    end
    local list = Utils.sources_for_stat(folded, stat_key)
    if not list or #list == 0 then
        return
    end
    local merged = Utils.merge_sources_by_name(list, 'delta', stat_type)
    for i = 1, #merged do
        local src = merged[i]
        local value_str = _fmt_source_value(src.delta, stat_type, pool_label)
        _add(records, {
            type = 'stat',
            label = src.name .. tag,
            value = value_str,
            label_color = COLORS.META,
            value_color = COLORS.META,
            indent = 1,
            stripe = true,
        })
    end
end

local function _sources(records, folded, stat_key, stat_type, pool_label)
    _sources_tagged(records, folded, stat_key, stat_type, '', pool_label)
end

-- A source row for a base (non-buff) value: the archetype/weapon contribution that
-- isn't in the folded buff sources. Shown first so the breakdown reads base + buffs = total.
local function _base_source(records, label, delta, stat_type)
    if not delta or delta == 0 then
        return
    end
    local value_str = _fmt_source_value(delta, stat_type)
    _add(records, {
        type = 'stat',
        label = label,
        value = value_str,
        label_color = COLORS.META,
        value_color = COLORS.META,
        indent = 1,
        stripe = true,
    })
end

-- 'mult' multiplies keys, 'add' sums deltas (1 + Σ), 'mult_pool' sums deltas into a named
-- × (1 + Σ) pool. Strength (power_level_modifier = 1 + Σ, applied as × S on power level) is
-- multiplicative to the additive damage pool, so it carries pool = 'strength'.
local function _stat_group(records, folded, base_label, generic_keys, variants, color, default_type)
    local v = folded and folded.values
    if not v then
        return
    end
    local default = default_type or 'add'
    local function entry(key)
        if type(key) == 'table' then
            return key.key, key.type or default, key.pool
        end
        return key, default, nil
    end
    local function compose(keys)
        local mult, add_delta = 1, 0
        local pools = {}
        for i = 1, #keys do
            local k, t, pool_name = entry(keys[i])
            local val = v[k]
            if type(val) == 'number' and val ~= 1 then
                if t == 'mult' then
                    mult = mult * val
                elseif t == 'mult_pool' then
                    local name = pool_name or ''
                    pools[name] = (pools[name] or 0) + val - 1
                else
                    add_delta = add_delta + val - 1
                end
            end
        end
        local pool_product = 1
        for _, delta in pairs(pools) do
            pool_product = pool_product * (1 + delta)
        end
        return mult * (1 + add_delta) * pool_product
    end
    local function _is_subset_tags(super, sub)
        for j = 1, #sub do
            local found = false
            for k = 1, #super do
                if super[k] == sub[j] then
                    found = true
                    break
                end
            end
            if not found then
                return false
            end
        end
        return true
    end

    local generic_names = {}
    for i = 1, #generic_keys do
        generic_names[entry(generic_keys[i])] = true
    end

    -- A combined variant overlays generic keys plus any parent variant whose tags are a strict
    -- subset of its own (so "Ranged, Ogryn" inherits the "Ranged" stack), then its own keys.
    local function combined_keys(variant)
        if variant.independent then
            return { variant.keys[1] }
        end
        local combined, seen = {}, {}
        local function add(key)
            local k = type(key) == 'table' and key.key or key
            if not seen[k] then
                seen[k] = true
                combined[#combined + 1] = key
            end
        end
        for i = 1, #generic_keys do
            add(generic_keys[i])
        end
        local tags = variant.tags
        for i = 1, #variants do
            local parent = variants[i]
            if parent ~= variant and not parent.independent and _is_subset_tags(tags, parent.tags) then
                for j = 1, #parent.keys do
                    add(parent.keys[j])
                end
            end
        end
        for i = 1, #variant.keys do
            add(variant.keys[i])
        end
        return combined
    end

    local generic = compose(generic_keys)
    local has_variant = false
    for i = 1, #variants do
        if compose(variants[i].keys) ~= 1 then
            has_variant = true
            break
        end
    end
    if generic == 1 and not has_variant then
        return
    end

    local function fmt_group(total)
        if default == 'mult' then
            return SharedUtils.fmt_mult(total)
        end
        return SharedUtils.fmt_pct(total - 1)
    end

    if generic ~= 1 then
        _stat(records, mod:localize(base_label), fmt_group(generic), color)
        for i = 1, #generic_keys do
            local k, t, pool_name = entry(generic_keys[i])
            _sources(records, folded, k, t, _pool_label(pool_name))
        end
    end
    -- Each variant header is followed by its own sources only; inherited parent keys are already
    -- listed under their own headers, so combined rows stay free of repeated inherited sources.
    for i = 1, #variants do
        local variant = variants[i]
        if compose(variant.keys) ~= 1 then
            local shown = variant.independent and v[variant.keys[1]] or compose(combined_keys(variant))
            shown = type(shown) == 'number' and shown or 1
            local tag = _variant_tag(variant.tags)
            _stat(records, mod:localize(base_label) .. tag, fmt_group(shown), color)
            local keys = variant.keys
            local n = variant.independent and 1 or #keys
            for j = 1, n do
                local k, t, pool_name = entry(keys[j])
                if not generic_names[k] then
                    _sources_tagged(records, folded, k, t, tag, _pool_label(pool_name))
                end
            end
        end
    end
end

local function _stat_with_sources(records, folded, label, stat_key, color, src_type)
    if not Utils.has_stat(folded, stat_key) then
        return
    end
    local delta = Utils.stat_delta(folded, stat_key)
    local display = src_type == 'mult' and SharedUtils.fmt_mult(1 + delta) or SharedUtils.fmt_pct(delta)
    _stat(records, mod:localize(label), display, color)
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
    local weapon_slot = mod:get('weapon_slot') or 'slot_primary'
    local wep_template = Utils.wielded_weapon_template(unit, weapon_slot)

    local toggles = {
        weapon_slot = weapon_slot,
        assume_proc_stacks = mod:get('assume_proc_stacks'),
        havoc_rank = mod:get('havoc_rank') or 0,
        coherency_allies = mod:get('coherency_allies') or 3,
    }
    local folded = Utils.folded_stat_buffs(unit, profile, player, toggles)

    -- Derive max vitals from base + folded buffs: the live extension reads the base value where
    -- curio/talent buffs aren't active (e.g. the hub).
    local folded_max_health, folded_max_toughness =
        Utils.compute_max_vitals(folded, vitals.archetype, vitals.toughness_template)
    local max_health = folded_max_health or vitals.max_health
    vitals.max_toughness = folded_max_toughness or vitals.max_toughness
    local max_wounds, base_max_wounds =
        Utils.compute_max_wounds(folded, vitals.max_wounds, vitals.archetype, toggles.havoc_rank)

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
        _stat(records, mod:localize('stat_health'), SharedUtils.fmt_num(max_health), COLORS.VITAL)
        _base_source(records, mod:localize('source_base'), vitals.archetype and vitals.archetype.health, 'flat')
        _sources(records, folded, 'max_health_modifier', 'add')
        _sources(records, folded, 'max_health_multiplier', 'add')
    end
    if max_wounds then
        _stat(records, mod:localize('stat_wounds'), SharedUtils.fmt_num(max_wounds), COLORS.VITAL)
        _base_source(records, mod:localize('source_base'), base_max_wounds, 'flat')
        _sources(records, folded, 'extra_max_amount_of_wounds', 'flat')
    end
    if vitals.max_toughness then
        _stat(records, mod:localize('stat_toughness'), SharedUtils.fmt_num(vitals.max_toughness), COLORS.VITAL)
        _base_source(
            records,
            mod:localize('source_base'),
            vitals.toughness_template and vitals.toughness_template.max,
            'flat'
        )
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
            _stat(records, mod:localize('stat_stamina'), SharedUtils.fmt_num(mobility.max_stamina), COLORS.MOBILITY)
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
            _stat(records, mod:localize('stat_dodge_count'), SharedUtils.fmt_num(mobility.dodge_count), COLORS.MOBILITY)
        end
        if mobility.dodge_dist then
            _stat(records, mod:localize('stat_dodge_dist'), string.format('%.1f', mobility.dodge_dist), COLORS.MOBILITY)
        end
        _stat_with_sources(records, folded, 'stat_dodge_speed', 'dodge_speed_multiplier', COLORS.MOBILITY, 'mult')

        _stat_group(records, folded, 'stat_block', { 'block_cost_multiplier', 'block_cost_modifier' }, {
            { keys = { 'block_cost_ranged_multiplier', 'block_cost_ranged_modifier' }, tags = { 'variant_ranged' } },
        }, COLORS.MOBILITY, 'mult')
        _stat_group(
            records,
            folded,
            'stat_movement_speed',
            { 'movement_speed', 'sprint_movement_speed' },
            {},
            COLORS.MOBILITY
        )
        _spacer(records)
    end

    -- OFFENSE
    _section(records, mod:localize('header_offense'), COLORS.OFFENSE)

    -- Damage: generic + melee/ranged weapon-type variants + damage-vs-X variants, all under
    -- one group with annotated sources.
    _stat_group(records, folded, 'stat_damage', {
        'damage',
        { key = 'power_level_modifier', type = 'mult_pool', pool = 'strength' },
    }, {
        {
            keys = { 'melee_damage', { key = 'melee_power_level_modifier', type = 'mult_pool', pool = 'strength' } },
            tags = { 'variant_melee' },
        },
        {
            keys = { 'ranged_damage', { key = 'ranged_power_level_modifier', type = 'mult_pool', pool = 'strength' } },
            tags = { 'variant_ranged' },
        },
        {
            keys = {
                'melee_heavy_damage',
                { key = 'melee_heavy_power_level_modifier', type = 'mult_pool', pool = 'strength' },
            },
            tags = { 'variant_melee', 'variant_heavy' },
        },
        {
            keys = {
                { key = 'weakspot_power_level_modifier', type = 'mult_pool', pool = 'strength' },
                { key = 'melee_weakspot_power_modifier', type = 'mult_pool', pool = 'strength' },
            },
            tags = { 'variant_weakspot' },
        },
        { keys = { 'damage_vs_elites' }, tags = { 'variant_elites' } },
        {
            keys = { 'damage_vs_elites', 'melee_heavy_damage_vs_elites' },
            tags = { 'variant_melee', 'variant_heavy', 'variant_elites' },
        },
        { keys = { 'damage_vs_specials' }, tags = { 'variant_specials' } },
        { keys = { 'damage_vs_captains' }, tags = { 'variant_captains' } },
        {
            keys = { 'damage_vs_captains', 'ranged_damage_vs_captains' },
            tags = { 'variant_ranged', 'variant_captains' },
        },
        {
            keys = { 'damage_vs_monsters', 'damage_vs_ogryn_and_monsters' },
            tags = { 'variant_monsters' },
        },
        {
            keys = { 'damage_vs_monsters', 'ranged_damage_vs_monsters', 'damage_vs_ogryn_and_monsters' },
            tags = { 'variant_ranged', 'variant_monsters' },
        },
        {
            keys = { 'damage_vs_ogryn', 'damage_vs_ogryn_and_monsters' },
            tags = { 'variant_ogryn' },
        },
        {
            keys = { 'damage_vs_ogryn', 'ranged_damage_vs_ogryn', 'damage_vs_ogryn_and_monsters' },
            tags = { 'variant_ranged', 'variant_ogryn' },
        },
        { keys = { 'damage_vs_horde' }, tags = { 'variant_horde' } },
        { keys = { 'damage_vs_bleeding' }, tags = { 'variant_bleeding' } },
        { keys = { 'damage_vs_burning' }, tags = { 'variant_burning' } },
        {
            keys = { 'damage_vs_electrocuted' },
            tags = { 'variant_electrocuted' },
        },
        { keys = { 'damage_vs_staggered' }, tags = { 'variant_staggered' } },
        { keys = { 'damage_vs_suppressed' }, tags = { 'variant_suppressed' } },
        { keys = { 'damage_vs_healthy' }, tags = { 'variant_healthy' } },
    }, COLORS.OFFENSE)

    -- Armor-type damage: separate multiplicative step (base_damage * stat_buff) from the common
    -- "+damage vs Armored/Unarmored/etc." perks.
    _stat_group(records, folded, 'stat_armor_damage', {}, {
        { keys = { 'unarmored_damage' }, tags = { 'variant_armor_unarmored' } },
        { keys = { 'armored_damage' }, tags = { 'variant_armor_armored' } },
        { keys = { 'resistant_damage' }, tags = { 'variant_armor_resistant' } },
        { keys = { 'berserker_damage' }, tags = { 'variant_armor_berserker' } },
        { keys = { 'super_armor_damage' }, tags = { 'variant_armor_super_armor' } },
    }, COLORS.OFFENSE)

    -- Attack speed: generic + melee/ranged.
    _stat_group(records, folded, 'stat_attack_speed', { 'attack_speed' }, {
        { keys = { 'melee_attack_speed' }, tags = { 'variant_melee' } },
        { keys = { 'ranged_attack_speed' }, tags = { 'variant_ranged' } },
    }, COLORS.OFFENSE)

    -- Crit chance: a fraction (not a bonus), so render the total directly; melee/ranged variants
    -- add on top of the generic. The base + weapon crit are injected into critical_strike_chance.
    local crit = Utils.crit_chance(folded, wep_template)
    if crit and crit > 0 then
        _stat(records, mod:localize('stat_crit_chance'), SharedUtils.fmt_pct(crit), COLORS.OFFENSE)
        _sources(records, folded, 'critical_strike_chance', 'add')
        _sources_tagged(records, folded, 'melee_critical_strike_chance', 'add', _variant_tag({ 'variant_melee' }))
        _sources_tagged(records, folded, 'ranged_critical_strike_chance', 'add', _variant_tag({ 'variant_ranged' }))
    end

    -- Crit damage bonus: generic finesse + crit stats + melee/ranged variants + crit-weakspot.
    _stat_group(records, folded, 'stat_crit_damage', {
        'critical_strike_damage',
        'finesse_modifier_bonus',
    }, {
        { keys = { 'melee_critical_strike_damage' }, tags = { 'variant_melee' } },
        { keys = { 'ranged_critical_strike_damage' }, tags = { 'variant_ranged' } },
        { keys = { 'melee_finesse_modifier_bonus' }, tags = { 'variant_melee' } },
        { keys = { 'ranged_finesse_modifier_bonus' }, tags = { 'variant_ranged' } },
        { keys = { 'critical_strike_weakspot_damage' }, tags = { 'variant_weakspot' } },
    }, COLORS.OFFENSE)

    -- Weakspot damage bonus: generic + melee/ranged; finesse_modifier_bonus applies to all weakspot hits.
    _stat_group(records, folded, 'stat_weakspot', {
        'weakspot_damage',
        'finesse_modifier_bonus',
    }, {
        { keys = { 'melee_weakspot_damage' }, tags = { 'variant_melee' } },
        { keys = { 'ranged_weakspot_damage' }, tags = { 'variant_ranged' } },
        { keys = { 'melee_finesse_modifier_bonus' }, tags = { 'variant_melee' } },
        { keys = { 'ranged_finesse_modifier_bonus' }, tags = { 'variant_ranged' } },
    }, COLORS.OFFENSE)

    -- Rending: generic + melee/ranged + conditional variants, all under one sum.
    _stat_group(records, folded, 'stat_rending', { 'rending_multiplier' }, {
        { keys = { 'melee_rending_multiplier' }, tags = { 'variant_melee' } },
        {
            keys = { 'melee_heavy_rending_multiplier' },
            tags = { 'variant_melee', 'variant_heavy' },
        },
        { keys = { 'ranged_rending_multiplier' }, tags = { 'variant_ranged' } },
        {
            keys = { 'ranged_critical_strike_rending_multiplier' },
            tags = { 'variant_ranged', 'variant_crit' },
        },
        { keys = { 'backstab_rending_multiplier' }, tags = { 'variant_backstab' } },
        { keys = { 'flanking_rending_multiplier' }, tags = { 'variant_flanking' } },
        { keys = { 'critical_strike_rending_multiplier' }, tags = { 'variant_crit' } },
        {
            keys = { 'rending_vs_staggered_multiplier' },
            tags = { 'variant_staggered' },
        },
        {
            keys = { 'rending_vs_electrocuted_multiplier' },
            tags = { 'variant_electrocuted' },
        },
        {
            keys = { 'close_range_rending_multiplier' },
            tags = { 'variant_close_range' },
        },
        { keys = { 'warp_attacks_rending_multiplier' }, tags = { 'variant_warp' } },
    }, COLORS.OFFENSE)

    if Utils.is_ranged(wep_template) then
        _stat_with_sources(records, folded, 'stat_reload_speed', 'reload_speed', COLORS.OFFENSE)
        _stat_with_sources(records, folded, 'stat_spread', 'spread_modifier', COLORS.OFFENSE)
    end

    _stat_group(records, folded, 'stat_impact', {
        'impact_modifier',
        { key = 'power_level_modifier', type = 'mult_pool', pool = 'strength' },
    }, {
        {
            keys = {
                'melee_impact_modifier',
                { key = 'melee_power_level_modifier', type = 'mult_pool', pool = 'strength' },
            },
            tags = { 'variant_melee' },
        },
        {
            keys = {
                'ranged_impact_modifier',
                { key = 'ranged_power_level_modifier', type = 'mult_pool', pool = 'strength' },
            },
            tags = { 'variant_ranged' },
        },
        {
            keys = { { key = 'melee_heavy_power_level_modifier', type = 'mult_pool', pool = 'strength' } },
            tags = { 'variant_melee', 'variant_heavy' },
        },
        {
            keys = {
                { key = 'weakspot_power_level_modifier', type = 'mult_pool', pool = 'strength' },
                { key = 'melee_weakspot_power_modifier', type = 'mult_pool', pool = 'strength' },
            },
            tags = { 'variant_weakspot' },
        },
        {
            keys = { 'melee_weakspot_impact_modifier' },
            tags = { 'variant_melee', 'variant_weakspot' },
        },
    }, COLORS.OFFENSE)

    _stat_group(records, folded, 'stat_cleave', {
        'max_hit_mass_attack_modifier',
        { key = 'power_level_modifier', type = 'mult_pool', pool = 'strength' },
    }, {
        {
            keys = {
                'max_melee_hit_mass_attack_modifier',
                { key = 'melee_power_level_modifier', type = 'mult_pool', pool = 'strength' },
            },
            tags = { 'variant_melee' },
        },
        {
            keys = {
                'ranged_max_hit_mass_attack_modifier',
                { key = 'ranged_power_level_modifier', type = 'mult_pool', pool = 'strength' },
            },
            tags = { 'variant_ranged' },
        },
        {
            keys = { { key = 'melee_heavy_power_level_modifier', type = 'mult_pool', pool = 'strength' } },
            tags = { 'variant_melee', 'variant_heavy' },
        },
        {
            keys = {
                { key = 'weakspot_power_level_modifier', type = 'mult_pool', pool = 'strength' },
                { key = 'melee_weakspot_power_modifier', type = 'mult_pool', pool = 'strength' },
            },
            tags = { 'variant_weakspot' },
        },
    }, COLORS.OFFENSE)

    _spacer(records)

    -- DEFENSE
    local has_health = max_health and max_health > 0

    _section(records, mod:localize('header_defense'), COLORS.DEFENSE)
    if has_health then
        _stat_group(records, folded, 'stat_damage_reduction', {
            { key = 'damage_taken_multiplier', type = 'mult' },
            { key = 'damage_taken_modifier', type = 'add' },
        }, {
            {
                keys = {
                    { key = 'melee_damage_taken_multiplier', type = 'mult' },
                    { key = 'melee_damage_taken_modifier', type = 'add' },
                },
                tags = { 'variant_melee' },
            },
            {
                keys = {
                    { key = 'ranged_damage_taken_multiplier', type = 'mult' },
                    { key = 'ranged_damage_taken_modifier', type = 'add' },
                },
                tags = { 'variant_ranged' },
            },
        }, COLORS.DEFENSE, 'mult')
    end
    -- Independent multiplicative resistances (corruption, enemy types, status effects).
    _stat_group(records, folded, 'stat_damage_resistances', {}, {
        { keys = { 'corruption_taken_multiplier' }, tags = { 'variant_corruption' }, independent = true },
        { keys = { 'corruption_taken_grimoire_multiplier' }, tags = { 'variant_grimoire' }, independent = true },
        { keys = { 'damage_taken_from_toxic_gas_multiplier' }, tags = { 'variant_toxic_gas' }, independent = true },
        { keys = { 'damage_taken_from_toxin' }, tags = { 'variant_toxin' }, independent = true },
        { keys = { 'damage_taken_from_explosions' }, tags = { 'variant_explosions' }, independent = true },
        { keys = { 'damage_taken_from_prop_explosions' }, tags = { 'variant_prop_explosions' }, independent = true },
        { keys = { 'damage_taken_from_burning' }, tags = { 'variant_burning' }, independent = true },
        { keys = { 'damage_taken_from_bleeding' }, tags = { 'variant_bleeding' }, independent = true },
        { keys = { 'damage_taken_from_electrocution' }, tags = { 'variant_electrocution' }, independent = true },
        { keys = { 'damage_taken_from_kinetic' }, tags = { 'variant_kinetic' }, independent = true },
        {
            keys = {
                'damage_taken_by_cultist_grenadier_multiplier',
                'damage_taken_by_renegade_grenadier_multiplier',
            },
            tags = { 'variant_bombers' },
            independent = true,
        },
        {
            keys = {
                'damage_taken_by_cultist_flamer_multiplier',
                'damage_taken_by_renegade_flamer_multiplier',
                'damage_taken_by_renegade_flamer_mutator_multiplier',
            },
            tags = { 'variant_flamers' },
            independent = true,
        },
        {
            keys = {
                'damage_taken_by_cultist_gunner_multiplier',
                'damage_taken_by_renegade_gunner_multiplier',
                'damage_taken_by_chaos_ogryn_gunner_multiplier',
            },
            tags = { 'variant_gunners' },
            independent = true,
        },
        {
            keys = {
                'damage_taken_by_cultist_mutant_multiplier',
                'damage_taken_by_cultist_mutant_mutator_multiplier',
            },
            tags = { 'variant_mutants' },
            independent = true,
        },
        {
            keys = {
                'damage_taken_by_chaos_hound_multiplier',
                'damage_taken_by_chaos_hound_mutator_multiplier',
                'damage_taken_by_chaos_armored_hound_multiplier',
            },
            tags = { 'variant_pox_hounds' },
            independent = true,
        },
        { keys = { 'damage_taken_by_renegade_sniper_multiplier' }, tags = { 'variant_snipers' }, independent = true },
    }, COLORS.DEFENSE, 'mult')

    _stat_group(records, folded, 'stat_tough_reduction', {
        { key = 'toughness_damage_taken_multiplier', type = 'mult' },
        { key = 'toughness_damage_taken_modifier', type = 'add' },
    }, {
        {
            keys = {
                { key = 'melee_toughness_damage_taken_multiplier', type = 'mult' },
                { key = 'melee_toughness_damage_taken_modifier', type = 'add' },
            },
            tags = { 'variant_melee' },
        },
        {
            keys = {
                { key = 'ranged_toughness_damage_taken_multiplier', type = 'mult' },
                { key = 'ranged_toughness_damage_taken_modifier', type = 'add' },
            },
            tags = { 'variant_ranged' },
        },
    }, COLORS.DEFENSE, 'mult')

    _spacer(records)

    -- TOUGHNESS regen
    if vitals.toughness_template then
        local tough_template = vitals.toughness_template
        local regen_total, regen_sources =
            Utils.toughness_regen(unit, stat_buffs, tough_template, vitals.max_toughness, folded)
        local regen_delay = Utils.toughness_regen_delay(unit, stat_buffs, tough_template)
        local bonus_regen, bonus_sources = Utils.toughness_bonus_regen(unit, profile, toggles, stat_buffs, folded)

        _section(records, mod:localize('header_toughness'), COLORS.DEFENSE)
        if regen_total then
            local max_tough = vitals.max_toughness or 0
            local total_pct = max_tough > 0 and (regen_total / max_tough * 100) or 0
            _stat(
                records,
                mod:localize('stat_toughness_regen_percent'),
                string.format('%.1f/s (%.1f%%/s)', regen_total, total_pct),
                COLORS.DEFENSE
            )
            _sources(records, folded, 'toughness_regen_rate_modifier', 'add')
            _sources(records, folded, 'toughness_regen_rate_multiplier', 'mult')
            _sources(records, folded, 'toughness_coherency_regen_rate_modifier', 'add')
            _sources(records, folded, 'toughness_extra_regen_rate', 'add')
            _sources(records, folded, 'toughness_coherency_regen_rate_multiplier', 'add')
            if regen_sources then
                for i = 1, #regen_sources do
                    local src = regen_sources[i]
                    local flat = src.per_second * max_tough
                    _add(records, {
                        type = 'stat',
                        label = src.name,
                        value = string.format('%.1f/s (%.1f%%/s)', flat, src.per_second * 100),
                        label_color = COLORS.META,
                        value_color = COLORS.META,
                        indent = 1,
                        stripe = true,
                    })
                end
            end
        end
        -- Proc talents call Toughness.replenish_percentage directly, separate from the regen_rate path.
        if bonus_regen and vitals.max_toughness then
            local bonus_per_s = bonus_regen * vitals.max_toughness
            _stat(
                records,
                mod:localize('stat_tough_bonus_regen'),
                string.format('%.1f/s (%.1f%%/s)', bonus_per_s, bonus_regen * 100),
                COLORS.DEFENSE
            )
            _sources(records, folded, 'toughness_replenish_modifier', 'add')
            _sources(records, folded, 'toughness_replenish_multiplier', 'mult')
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
        _spacer(records)
    end

    return records, header_text, subtext, header_icon
end

return {
    build_stats = build_stats,
}
