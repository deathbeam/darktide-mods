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
    local pct = n * 100
    local fmt = math.abs(pct - math.floor(pct)) < 0.05 and '%.0f%%' or '%.1f%%'
    return string.format(fmt, pct)
end

local function _fmt_mult(n)
    if n == nil then
        return '-'
    end
    return string.format('x%.2f', n)
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

-- Render the contributing sources for a stat as indented sub-rows, merged by display name so
-- duplicate curios / multi-template talents collapse to one row with summed deltas.
-- Like _sources but appends `tag` (e.g. " (Melee)") to each source's label, so a merged
-- variant group shows which variant each source contributes to.
local function _sources_tagged(records, folded, stat_key, stat_type, tag)
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
        local value_str
        if stat_type == 'mult' then
            value_str = string.format('x%.2f', src.delta)
        elseif stat_type == 'flat' then
            value_str = string.format('%s%.0f', src.delta >= 0 and '+' or '', src.delta)
        else
            value_str = (src.delta >= 0 and '+' or '') .. _fmt_pct(src.delta)
        end
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

local function _sources(records, folded, stat_key, stat_type)
    _sources_tagged(records, folded, stat_key, stat_type, '')
end

-- A source row for a base (non-buff) value: the archetype/weapon contribution that
-- isn't in the folded buff sources. Shown first so the breakdown reads base + buffs = total.
local function _base_source(records, label, delta, stat_type)
    if not delta or delta == 0 then
        return
    end
    local value_str
    if stat_type == 'flat' then
        value_str = string.format('%s%.0f', delta >= 0 and '+' or '', delta)
    else
        value_str = (delta >= 0 and '+' or '') .. _fmt_pct(delta)
    end
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

-- Unified stat group: mult keys multiply, add keys sum their deltas (final = mult * (1 + Σ add)).
-- One composition covers additive damage, multiplicative block/resistance, and mixed damage-taken.
-- `independent` variants (grouped breed resistances) show their key alone, not folded with generic.
local function _stat_group(records, folded, base_label, generic_keys, variants, color, default_type)
    local v = folded and folded.values
    if not v then
        return
    end
    local default = default_type or 'add'
    local function entry(key)
        -- Plain strings inherit default_type; a { key, type } entry overrides it.
        if type(key) == 'table' then
            return key.key, key.type or default
        end
        return key, default
    end
    local function compose(keys)
        local mult, add_delta = 1, 0
        for i = 1, #keys do
            local k, t = entry(keys[i])
            local val = v[k]
            if type(val) == 'number' and val ~= 1 then
                if t == 'mult' then
                    mult = mult * val
                else
                    add_delta = add_delta + val - 1
                end
            end
        end
        return mult * (1 + add_delta)
    end

    local function combined_keys(variant)
        -- Variants overlay generic keys (mults multiply, adds sum), so fold them together.
        local combined = {}
        for i = 1, #generic_keys do
            combined[#combined + 1] = generic_keys[i]
        end
        for i = 1, #variant.keys do
            combined[#combined + 1] = variant.keys[i]
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

    -- x1.20 for mult groups (matches per-source rows); +20% otherwise.
    local fmt = default == 'mult' and _fmt_mult or function(n)
        return _fmt_pct(n - 1)
    end

    if generic ~= 1 then
        _stat(records, mod:localize(base_label), fmt(generic), color)
    end
    for i = 1, #variants do
        local variant = variants[i]
        -- Independent variants read the first key alone (grouped breeds share one value); others overlay generic.
        if compose(variant.keys) ~= 1 then
            local shown = variant.independent and v[variant.keys[1]] or compose(combined_keys(variant))
            shown = type(shown) == 'number' and shown or 1
            local label = mod:localize(base_label) .. _variant_tag(variant.tags)
            _stat(records, label, fmt(shown), color)
        end
    end

    for i = 1, #generic_keys do
        local k, t = entry(generic_keys[i])
        _sources(records, folded, k, t)
    end
    for i = 1, #variants do
        local variant = variants[i]
        local tag = _variant_tag(variant.tags)
        local keys = variant.keys
        local n = variant.independent and 1 or #keys
        for j = 1, n do
            local k, t = entry(keys[j])
            _sources_tagged(records, folded, k, t, tag)
        end
    end
end

local function _stat_with_sources(records, folded, label, stat_key, color, src_type)
    if not Utils.has_stat(folded, stat_key) then
        return
    end
    local delta = Utils.stat_delta(folded, stat_key)
    local display = src_type == 'mult' and _fmt_mult(1 + delta) or _fmt_pct(delta)
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
        _base_source(records, mod:localize('source_base'), vitals.archetype and vitals.archetype.health, 'flat')
        _sources(records, folded, 'max_health_modifier', 'add')
        _sources(records, folded, 'max_health_multiplier', 'add')
    end
    if vitals.max_wounds then
        _stat(records, mod:localize('stat_wounds'), _fmt_num(vitals.max_wounds), COLORS.VITAL)
    end
    if vitals.max_toughness then
        _stat(records, mod:localize('stat_toughness'), _fmt_num(vitals.max_toughness), COLORS.VITAL)
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
    _stat_group(records, folded, 'stat_damage', { 'damage', 'power_level_modifier' }, {
        { keys = { 'melee_damage', 'melee_power_level_modifier' }, tags = { 'variant_melee' } },
        {
            keys = { 'ranged_damage', 'ranged_power_level_modifier' },
            tags = { 'variant_ranged' },
        },
        { keys = { 'damage_vs_elites' }, tags = { 'variant_elites' } },
        {
            keys = { 'melee_heavy_damage_vs_elites' },
            tags = { 'variant_melee', 'variant_heavy', 'variant_elites' },
        },
        { keys = { 'damage_vs_specials' }, tags = { 'variant_specials' } },
        { keys = { 'damage_vs_monsters' }, tags = { 'variant_monsters' } },
        {
            keys = { 'ranged_damage_vs_monsters' },
            tags = { 'variant_ranged', 'variant_monsters' },
        },
        { keys = { 'damage_vs_ogryn' }, tags = { 'variant_ogryn' } },
        {
            keys = { 'damage_vs_ogryn_and_monsters' },
            tags = { 'variant_ogryn', 'variant_monsters' },
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
        _stat(records, mod:localize('stat_crit_chance'), _fmt_pct(crit), COLORS.OFFENSE)
        _sources(records, folded, 'critical_strike_chance', 'add')
        _sources_tagged(records, folded, 'melee_critical_strike_chance', 'add', _variant_tag({ 'variant_melee' }))
        _sources_tagged(records, folded, 'ranged_critical_strike_chance', 'add', _variant_tag({ 'variant_ranged' }))
    end

    -- Crit damage bonus: generic + melee/ranged.
    _stat_group(records, folded, 'stat_crit_damage', { 'critical_strike_damage' }, {
        { keys = { 'melee_critical_strike_damage' }, tags = { 'variant_melee' } },
        { keys = { 'ranged_critical_strike_damage' }, tags = { 'variant_ranged' } },
    }, COLORS.OFFENSE)

    -- Weakspot damage bonus: generic + melee/ranged.
    _stat_group(records, folded, 'stat_weakspot', { 'weakspot_damage' }, {
        { keys = { 'melee_weakspot_damage' }, tags = { 'variant_melee' } },
        { keys = { 'ranged_weakspot_damage' }, tags = { 'variant_ranged' } },
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

    _stat_with_sources(records, folded, 'stat_power_level', 'power_level_modifier', COLORS.OFFENSE)
    _sources(records, folded, 'melee_power_level_modifier', 'add')
    _sources(records, folded, 'ranged_power_level_modifier', 'add')

    if Utils.is_ranged(wep_template) then
        _stat_with_sources(records, folded, 'stat_reload_speed', 'reload_speed', COLORS.OFFENSE)
        _stat_with_sources(records, folded, 'stat_spread', 'spread_modifier', COLORS.OFFENSE)
    end

    _stat_group(records, folded, 'stat_impact', { 'impact_modifier' }, {
        { keys = { 'melee_impact_modifier' }, tags = { 'variant_melee' } },
        { keys = { 'ranged_impact_modifier' }, tags = { 'variant_ranged' } },
    }, COLORS.OFFENSE)

    _stat_group(records, folded, 'stat_cleave', { 'max_hit_mass_attack_modifier' }, {
        { keys = { 'max_melee_hit_mass_attack_modifier' }, tags = { 'variant_melee' } },
        { keys = { 'ranged_max_hit_mass_attack_modifier' }, tags = { 'variant_ranged' } },
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
        local coherency_regen, percent_regen =
            Utils.toughness_regen(unit, stat_buffs, tough_template, vitals.max_toughness, folded)
        local regen_delay = Utils.toughness_regen_delay(unit, stat_buffs, tough_template)
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
        _spacer(records)
    end

    return records, header_text, subtext, header_icon
end

return {
    build_stats = build_stats,
}
