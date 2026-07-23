local mod = get_mod('CharacterStats')

local Stamina = mod:original_require('scripts/utilities/attack/stamina')
local WeaponTemplate = mod:original_require('scripts/utilities/weapon/weapon_template')
local BuffSettings = mod:original_require('scripts/settings/buff/buff_settings')
local BuffTemplates = mod:original_require('scripts/settings/buff/buff_templates')
local WeaponTraitTemplates = mod:original_require('scripts/settings/equipment/weapon_traits/weapon_trait_templates')
local WeaponHandlingTemplates =
    mod:original_require('scripts/settings/equipment/weapon_handling_templates/weapon_handling_templates')
local WeaponTweakTemplates = mod:original_require('scripts/extension_systems/weapon/utilities/weapon_tweak_templates')
local MasterItems = mod:original_require('scripts/backend/master_items')
local HomePlanets = mod:original_require('scripts/settings/character/home_planets')
local Childhood = mod:original_require('scripts/settings/character/childhood')
local GrowingUp = mod:original_require('scripts/settings/character/growing_up')
local FormativeEvent = mod:original_require('scripts/settings/character/formative_event')
local Crimes = mod:original_require('scripts/settings/character/crimes')
local Personalities = mod:original_require('scripts/settings/character/personalities')
local CrimesCompabilityMap = mod:original_require('scripts/settings/character/crimes_compability_mapping')
local SharedUtils = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/shared/shared_utils')

-- Constants -------------------------------------------------------------

local EMPTY = {}
local stat_buff_types = BuffSettings.stat_buff_types
local stat_buff_type_base = BuffSettings.stat_buff_type_base_values
local LERP_MIDPOINT = 0.5

local _havoc
local _related_cache

local _HAVOC_PLAYER_FACING = {
    reduce_health_and_wounds = true,
    reduce_toughness = true,
    reduce_toughness_regen = true,
}

-- Enemy-type damage resistance curio perks: damage_taken_by_<breed>_multiplier (multiplicative).
local GADGET_STAT_LABEL = {
    gadget_health_increase = 'Max Health',
    gadget_innate_health_increase = 'Max Health',
    gadget_max_wounds_increase = 'Wounds',
    gadget_innate_max_wounds_increase = 'Wounds',
    gadget_stamina_increase = 'Max Stamina',
    gadget_toughness_increase = 'Toughness',
    gadget_innate_toughness_increase = 'Toughness',
    gadget_stamina_regeneration = 'Stamina Regeneration',
    gadget_sprint_cost_reduction = 'Sprint Efficiency',
    gadget_toughness_regen_delay = 'Toughness Regeneration Speed',
}

local M = {}

-- Private helpers -------------------------------------------------------

local function _ext(unit, system)
    return unit and ScriptUnit.has_extension(unit, system) or nil
end

local function _is_melee(t)
    return t ~= nil and WeaponTemplate.is_melee(t)
end

local function _is_ranged(t)
    return t ~= nil and WeaponTemplate.is_ranged(t)
end

local function _weapon_toughness_template(unit)
    local weapon_ext = _ext(unit, 'weapon_system')
    return weapon_ext and weapon_ext:toughness_template() or nil
end

-- Max crit chance_modifier across the weapon template's actions. Ninja weapons (combat knife,
-- hatchets, saws, shivs) carry a crit bump on their handling template. The template is
-- preparsed at load, which mutates each action's weapon_handling_template into a lookup key,
-- so the original name is recovered via get_template_identifiers().base_identifier.
local function _weapon_crit_modifier(wep_template)
    if not wep_template or not wep_template.__base_template_lookup then
        return nil
    end
    local best = nil
    for action_name in pairs(wep_template.actions or EMPTY) do
        local base_id = WeaponTweakTemplates.get_template_identifiers(wep_template, 'weapon_handling', action_name)
        local cs = base_id and WeaponHandlingTemplates[base_id] and WeaponHandlingTemplates[base_id].critical_strike
        local mod = cs and cs.chance_modifier
        if type(mod) == 'table' then
            mod = mod.lerp_perfect or mod.lerp_basic
        end
        if type(mod) == 'number' and (best == nil or mod > best) then
            best = mod
        end
    end
    return best
end

local function _resolve_crime(key)
    return Crimes[CrimesCompabilityMap[key] or key]
end

-- Resolve a personality by key, falling back to matching the selected voice (FS has renamed
-- keys before without leaving compat entries).
local function _resolve_personality(personality_key, voice_fallback)
    local p = Personalities[personality_key]
    if p then
        return p
    end
    if voice_fallback then
        for _, candidate in pairs(Personalities) do
            if candidate.character_voice == voice_fallback then
                return candidate
            end
        end
    end
    return nil
end

local function _havoc_tables()
    if _havoc ~= nil then
        return _havoc
    end
    local ok_cfg, cfg = pcall(function()
        return mod:original_require('scripts/settings/havoc/havoc_modifier_config')
    end)
    local ok_set, set = pcall(function()
        return mod:original_require('scripts/settings/havoc_settings')
    end)
    _havoc = (ok_cfg and ok_set and cfg and set) and { config = cfg, settings = set } or false
    return _havoc
end

local function _stat_base(name)
    local b = stat_buff_type_base[name]
    return b ~= nil and b or 1
end

-- Inject a single additive stat contribution (value + named source) into the folded result,
-- bypassing the buff template path. Used for non-buff base values like the weapon crit bump.
local function _inject_source(result, stat_name, value, source)
    if not value or value == 0 or not source then
        return
    end
    local cur = result.values[stat_name]
    result.values[stat_name] = (cur or _stat_base(stat_name)) + value
    local list = result.sources[stat_name]
    if not list then
        list = {}
        result.sources[stat_name] = list
    end
    list[#list + 1] = { name = source, delta = value, stacks = 1 }
end

local function _merge(result, stat_buffs, stack_count, source, lerp_t)
    if type(stat_buffs) ~= 'table' then
        return
    end
    local values, sources, stacks = result.values, result.sources, stack_count or 1
    for name, raw in pairs(stat_buffs) do
        local value = raw
        if type(value) == 'table' then
            local mn, mx = value.min, value.max
            value = (type(mn) == 'number' and type(mx) == 'number') and math.lerp(mn, mx, lerp_t or LERP_MIDPOINT)
                or nil
        end
        if type(value) == 'number' then
            local cur = values[name]
            local contribution
            if stat_buff_types[name] == 'multiplicative_multiplier' then
                values[name] = (cur ~= nil and cur or _stat_base(name)) * value
                contribution = value
            else
                values[name] = (cur ~= nil and cur or _stat_base(name)) + value * stacks
                contribution = value * stacks
            end
            if source then
                local list = sources[name]
                if not list then
                    list = {}
                    sources[name] = list
                end
                list[#list + 1] = { name = source, delta = contribution, stacks = stacks }
            end
        end
    end
end

-- Resolve a template's stat-buff tables (always-on / conditional / proc / lerped / stepped)
-- with talent-tier overrides applied. Lerped entries are kept as {min,max} tables and resolved by
-- _merge at the caller's lerp_t (curios pass their rarity; talents/coherency use the midpoint),
-- so curios aren't locked to the wrong value.
local function _effective(template, tier)
    local override
    if tier and template.talent_overrides then
        local n = #template.talent_overrides
        override = n > 0 and template.talent_overrides[math.min(tier, n)] or nil
    end
    local stat = (override and override.stat_buffs) or template.stat_buffs
    local cond = (override and override.conditional_stat_buffs) or template.conditional_stat_buffs
    local proc = (override and override.proc_stat_buffs) or template.proc_stat_buffs
    -- Lerped + stepped entries carry {min,max} / per-step arrays rather than flat values;
    -- resolve them into a flat copy of the stat table so _merge sees plain numbers. (A single
    -- template only ever has one of these, but resolving into one table avoids a pairs() proxy
    -- bug where a later field would shadow an earlier one.)
    local lerped = (override and override.lerped_stat_buffs) or template.lerped_stat_buffs
    local cond_lerped = (override and override.conditional_lerped_stat_buffs) or template.conditional_lerped_stat_buffs
    local stepped = (override and override.stepped_stat_buffs) or template.stepped_stat_buffs
    local has_extra = lerped or cond_lerped or (stepped and stepped[1])
    if has_extra then
        local stat_flat, cond_flat = {}, {}
        if stat then
            for k, v in pairs(stat) do
                stat_flat[k] = v
            end
        end
        if cond then
            for k, v in pairs(cond) do
                cond_flat[k] = v
            end
        end
        if lerped then
            for k, v in pairs(lerped) do
                stat_flat[k] = v
            end
        end
        if cond_lerped then
            for k, v in pairs(cond_lerped) do
                cond_flat[k] = v
            end
        end
        if stepped and stepped[1] then
            -- Stepped buffs (e.g. per-stack toughness DR) fold at the max step to match the
            -- assume_proc_stacks ceiling; a 0/1st step contributes nothing.
            for k, v in pairs(stepped[#stepped]) do
                stat_flat[k] = v
            end
        end
        stat, cond = stat_flat, cond_flat
    end
    return stat, cond, proc
end

local function _fold(result, template, tier, stacks, source, lerp_t)
    if not template then
        return
    end
    local stat, cond, proc = _effective(template, tier)
    _merge(result, stat, stacks, source, lerp_t)
    _merge(result, cond, stacks, source, lerp_t)
    _merge(result, proc, stacks, source, lerp_t)
end

local function _stacks_for(template, toggles)
    return toggles.assume_proc_stacks and (template and template.max_stacks or 1) or 1
end

-- Cached talent_name -> { buff_template_name, ... } for templates whose related_talents lists it.
-- Finds active-effect proc buffs a talent grants but that aren't its passive buff_template_name.
local function _related_by_talent()
    if _related_cache then
        return _related_cache
    end
    local map = {}
    for name, template in pairs(BuffTemplates) do
        local related = template and template.related_talents
        if type(related) == 'table' then
            for i = 1, #related do
                local list = map[related[i]]
                if not list then
                    list = {}
                    map[related[i]] = list
                end
                list[#list + 1] = name
            end
        end
    end
    _related_cache = map
    return map
end

local function _talent_passive_buffs(talent)
    local passive = talent.passive
    local bname = passive and passive.buff_template_name
    if not bname then
        return {}
    end
    if type(bname) == 'table' then
        return bname
    end
    return { bname }
end

local function _equip_loadout(player)
    if not player or not player.player_unit then
        return nil
    end
    return ScriptUnit.has_extension(player.player_unit, 'visual_loadout_system')
end

local function _display_for_buff(template_name)
    local template = BuffTemplates[template_name]
    return (template and SharedUtils.safe_localize(template.display_name)) or SharedUtils.prettify(template_name)
end

-- Both blessings (item.traits) and perks (item.perks) carry on-equip stat buffs in the same
-- shape (WeaponTraitTemplates[name].buffs -> rarity-indexed overrides), so fold them together.
local function _weapon_buffs(player, slot_name)
    local vl = _equip_loadout(player)
    if not vl or not slot_name then
        return {}
    end
    local cached = MasterItems.get_cached()
    if not cached then
        return {}
    end
    local out = {}
    local item = vl:item_from_slot(slot_name)
    if item then
        for _, list_key in ipairs({ 'traits', 'perks' }) do
            local list = item[list_key]
            if list then
                for i = 1, #list do
                    local trait = list[i]
                    local trait_item = trait.id and cached[trait.id]
                    local trait_name = trait_item and trait_item.trait
                    local def = trait_name and WeaponTraitTemplates[trait_name]
                    if def and def.buffs then
                        local rarity = trait.rarity or 1
                        for buff_template_name, levels in pairs(def.buffs) do
                            local override
                            for r = rarity, 1, -1 do
                                override = levels[r]
                                if override then
                                    break
                                end
                            end
                            out[#out + 1] = {
                                template_name = buff_template_name,
                                override_data = override,
                                display_name = SharedUtils.safe_localize(trait_item and trait_item.display_name)
                                    or _display_for_buff(buff_template_name),
                            }
                        end
                    end
                end
            end
        end
    end
    return out
end

local function _gadget_buffs(player)
    local vl = _equip_loadout(player)
    local cached = vl and MasterItems.get_cached()
    if not cached then
        return {}
    end
    local out = {}
    for i = 1, 3 do
        local item = vl:item_in_slot('slot_attachment_' .. i)
        if item then
            local function collect(list)
                if not list then
                    return
                end
                for j = 1, #list do
                    local data = list[j]
                    local trait_item = data.id and cached[data.id]
                    local trait_name = trait_item and trait_item.trait
                    out[#out + 1] = {
                        template_name = trait_name,
                        lerp_value = data.value,
                        display_name = SharedUtils.safe_localize(trait_item and trait_item.display_name)
                            or GADGET_STAT_LABEL[trait_name]
                            or SharedUtils.prettify(trait_name),
                    }
                end
            end
            collect(item.perks)
            collect(item.traits)
        end
    end
    return out
end

local function _havoc_debuffs(rank)
    if not rank or rank <= 0 then
        return {}
    end
    local data = _havoc_tables()
    local entry = data and data.config[rank]
    if not entry then
        return {}
    end
    -- Definitions live in modifier_templates; havoc_settings.modifiers is just a name array.
    local templates = data.settings.modifier_templates
    local out = {}
    for name, tier in pairs(entry) do
        if _HAVOC_PLAYER_FACING[name] then
            local mod_def = templates and templates[name]
            local buff_name = mod_def and mod_def[tier] and mod_def[tier].add_player_buff
            if buff_name and BuffTemplates[buff_name] then
                out[#out + 1] = buff_name
            end
        end
    end
    return out
end

local function _talent_entries(unit, profile)
    local archetype = profile and profile.archetype
    if not archetype then
        return nil, nil
    end
    local talent_ext = unit and ScriptUnit.has_extension(unit, 'talent_system')
    local allocated
    if talent_ext then
        local ok, result = pcall(function()
            return talent_ext.talents and talent_ext:talents()
        end)
        allocated = (ok and result) or talent_ext._talents
    end
    allocated = allocated or (profile and profile.talents)
    if not allocated then
        return nil, nil
    end

    local entries, coherency_templates, talents = {}, {}, archetype.talents
    for talent_name, tier in pairs(allocated) do
        local talent = talents and talents[talent_name]
        if talent then
            entries[#entries + 1] = {
                talent_name = talent_name,
                tier = tier,
                buff_template_names = _talent_passive_buffs(talent),
                display_name = SharedUtils.safe_localize(talent.display_name) or SharedUtils.prettify(talent_name),
            }
            local coh = talent.coherency
            if coh and coh.buff_template_name then
                coherency_templates[#coherency_templates + 1] = coh.buff_template_name
            end
        end
    end
    return entries, coherency_templates
end

local function _folded_values(folded)
    return folded and folded.values or nil
end

-- Group damage-taken terms that share a label (e.g. a Gunners perk buffs 3 breeds to the
-- same value): collapses them into one term carrying all keys, value taken from the first.
-- {label, key, delta} terms for the given stat keys, skipping defaults (multiplier base 1).
-- damage_taken / toughness_damage_taken share the same compose: mult = <prefix>_multiplier,
-- mod = <prefix>_modifier (+ melee/ranged variants), final = mult * mod.
local function _compose_taken(values, prefix)
    local function compose(is_melee, is_ranged)
        local mult = values[prefix .. '_multiplier'] or 1
        local mod = values[prefix .. '_modifier'] or 1
        if is_melee then
            mult = mult * (values['melee_' .. prefix .. '_multiplier'] or 1)
            mod = mod + (values['melee_' .. prefix .. '_modifier'] or 1) - 1
        elseif is_ranged then
            mult = mult * (values['ranged_' .. prefix .. '_multiplier'] or 1)
            mod = mod + (values['ranged_' .. prefix .. '_modifier'] or 1) - 1
        end
        return mult * mod
    end
    return { generic = compose(false, false), melee = compose(true, false), ranged = compose(false, true) }
end

-- Public API ------------------------------------------------------------

-- Merge source rows by `name`, composing `field` per the stat type: multiplicative
-- stats multiply (matching the engine), additive/flat stats sum. One row per named
-- contributor, so a talent granting several same-named buffs collapses to one line.
function M.merge_sources_by_name(sources, field, stat_type)
    local merged, by_name = {}, {}
    local mult = stat_type == 'mult'
    for i = 1, #sources do
        local src = sources[i]
        local existing = by_name[src.name]
        if existing then
            existing[field] = mult and (existing[field] * src[field]) or (existing[field] + src[field])
        else
            local copy = { name = src.name }
            copy[field] = src[field]
            by_name[src.name] = copy
            merged[#merged + 1] = copy
        end
    end
    return merged
end

function M.local_player_unit()
    local player = Managers.player and Managers.player:local_player_safe(1)
    if not player then
        return nil, nil
    end
    local unit = player.player_unit
    if not unit or not ALIVE[unit] then
        return nil, player
    end
    return unit, player
end

function M.profile(player)
    if not player then
        return nil
    end
    local ok, profile = pcall(player.profile, player)
    return ok and profile or nil
end

-- Bio fields from profile.lore.backstory. Returns { title, option, text } per field:
-- title/option come from the game's character-creation loc keys + the chosen option's
-- display_name; text is the description. The archetype entry has option = nil.
function M.character_bio(profile)
    if not profile then
        return nil
    end
    local backstory = profile.lore and profile.lore.backstory
    if not backstory then
        return nil
    end
    local function entry(title_key, data, override_text)
        local text = override_text or (data and SharedUtils.safe_localize(data.description)) or nil
        if not text or text == '' then
            return nil
        end
        return {
            title = mod:localize(title_key),
            option = data and SharedUtils.safe_localize(data.display_name) or nil,
            text = text,
        }
    end
    local archetype = profile.archetype
    local out = {}
    out[#out + 1] = entry('bio_origin', nil, archetype and SharedUtils.safe_localize(archetype.archetype_description))
    out[#out + 1] = entry('bio_home_planet', HomePlanets[backstory.planet])
    out[#out + 1] = entry('bio_early_life', Childhood[backstory.childhood])
    out[#out + 1] = entry('bio_first_conflict', GrowingUp[backstory.growing_up])
    out[#out + 1] = entry('bio_key_event', FormativeEvent[backstory.formative_event])
    out[#out + 1] = entry('bio_crime', _resolve_crime(backstory.crime))
    out[#out + 1] = entry('bio_personality', _resolve_personality(backstory.personality, profile.selected_voice))
    local filtered = {}
    for i = 1, #out do
        if out[i] then
            filtered[#filtered + 1] = out[i]
        end
    end
    return filtered
end

function M.wielded_weapon_template(unit, slot_name)
    local vl = unit and ScriptUnit.has_extension(unit, 'visual_loadout_system')
    if not vl or not slot_name then
        return nil
    end
    local item = vl:item_from_slot(slot_name)
    return item and WeaponTemplate.weapon_template_from_item(item) or nil
end

function M.vitals(unit)
    local health_ext = _ext(unit, 'health_system')
    local toughness_ext = _ext(unit, 'toughness_system')
    local buff_ext = _ext(unit, 'buff_system')
    local unit_data_ext = _ext(unit, 'unit_data_system')
    local archetype = unit_data_ext and unit_data_ext:archetype()
    return {
        max_health = health_ext and health_ext:max_health() or nil,
        max_wounds = health_ext and health_ext:max_wounds() or nil,
        max_toughness = toughness_ext and toughness_ext:max_toughness() or nil,
        archetype = archetype,
        toughness_template = archetype and archetype.toughness,
        stat_buffs = buff_ext and buff_ext:stat_buffs(),
    }
end

-- max_health/max_toughness/max_stamina derived from the archetype BASE plus the folded stat
-- buffs. The live extension reads return the base value in contexts where buffs aren't active
-- (e.g. the hub), so deriving from folded gives a consistent value everywhere and lines up
-- with the per-source breakdown.
function M.compute_max_vitals(folded, archetype, toughness_template, stamina_template, weapon_stamina_template)
    local v = folded and folded.values
    local max_health, max_toughness, max_stamina
    if archetype and archetype.health then
        max_health =
            math.ceil(archetype.health * ((v and v.max_health_modifier) or 1) * ((v and v.max_health_multiplier) or 1))
    end
    if toughness_template and toughness_template.max then
        max_toughness = math.ceil(
            (toughness_template.max + ((v and v.toughness) or 0)) * ((v and v.toughness_bonus) or 1)
        ) + ((v and v.toughness_bonus_flat) or 0)
    end
    if stamina_template then
        max_stamina = (stamina_template.base_stamina or 0)
            + (weapon_stamina_template and weapon_stamina_template.stamina_modifier or 0)
            + ((v and v.stamina_modifier) or 0)
    end
    return max_health, max_toughness, max_stamina
end

-- Builds the assumed-active ceiling: every buff the character is capable of (talents +
-- related procs + blessings + curios + coherency + havoc), folded at max stacks. Not seeded from
-- the live snapshot, which would double-count any currently-active buff.
function M.folded_stat_buffs(unit, profile, player, toggles)
    toggles = toggles or {}
    local result = { values = {}, sources = {} }
    local related = _related_by_talent()

    local entries, coherency_templates = _talent_entries(unit, profile)
    if entries then
        for i = 1, #entries do
            local entry = entries[i]
            local source = entry.display_name or entry.talent_name
            local passive = {}
            for j = 1, #entry.buff_template_names do
                local bname = entry.buff_template_names[j]
                local template = BuffTemplates[bname]
                passive[bname] = true
                _fold(result, template, entry.tier, _stacks_for(template, toggles), source)
            end
            local rel = related[entry.talent_name]
            if rel then
                for j = 1, #rel do
                    local bname = rel[j]
                    local tmpl = BuffTemplates[bname]
                    if not passive[bname] and tmpl and tmpl.buff_category ~= 'aura' then
                        _fold(result, tmpl, entry.tier, _stacks_for(tmpl, toggles), source)
                    end
                end
            end
        end
    end

    local ally_count = toggles.coherency_allies or 0
    if ally_count > 0 then
        local names = { 'coherency_toughness_regen' }
        for i = 1, #coherency_templates do
            names[#names + 1] = coherency_templates[i]
        end
        local coh_source = mod:localize('source_coherency')
        for i = 1, #names do
            local template = BuffTemplates[names[i]]
            local stepped = template and template.stepped_stat_buffs
            if stepped and stepped[1] then
                _merge(result, stepped[math.min(ally_count + 1, #stepped)] or stepped[1], 1, coh_source)
            else
                _fold(result, template, nil, _stacks_for(template, toggles), coh_source)
            end
        end
    end

    local weapon_slot = toggles.weapon_slot
    for _, entry in ipairs(_weapon_buffs(player, weapon_slot)) do
        local template = BuffTemplates[entry.template_name]
        if template then
            local stacks = _stacks_for(template, toggles)
            local override = entry.override_data
            local source = entry.display_name or entry.template_name
            _merge(result, (override and override.stat_buffs) or template.stat_buffs, stacks, source)
            _merge(
                result,
                (override and override.conditional_stat_buffs) or template.conditional_stat_buffs,
                stacks,
                source
            )
            _merge(result, (override and override.proc_stat_buffs) or template.proc_stat_buffs, stacks, source)
        end
    end

    local archetype = profile and profile.archetype
    local base_crit = (archetype and archetype.base_critical_strike_chance) or 0
    if base_crit ~= 0 then
        _inject_source(result, 'critical_strike_chance', base_crit, mod:localize('source_base'))
    end
    local wep_template = M.wielded_weapon_template(unit, weapon_slot)
    local crit_mod = _weapon_crit_modifier(wep_template)
    if crit_mod and crit_mod ~= 0 then
        local vl = unit and ScriptUnit.has_extension(unit, 'visual_loadout_system')
        local item = vl and weapon_slot and vl:item_from_slot(weapon_slot)
        local weapon_name = (item and SharedUtils.safe_localize(item.display_name))
            or (wep_template and wep_template.name)
            or mod:localize('mod_name')
        _inject_source(result, 'critical_strike_chance', crit_mod, weapon_name)
    end

    for _, entry in ipairs(_gadget_buffs(player)) do
        _fold(result, BuffTemplates[entry.template_name], nil, 1, entry.display_name, entry.lerp_value)
    end

    local havoc_rank = toggles.havoc_rank or 0
    if havoc_rank > 0 then
        local havoc_source = mod:localize('source_havoc')
        for _, name in ipairs(_havoc_debuffs(havoc_rank)) do
            _fold(result, BuffTemplates[name], nil, 1, havoc_source)
        end
    end

    return result
end

function M.sources_for_stat(folded, stat_key)
    return folded and folded.sources and folded.sources[stat_key] or nil
end

function M.crit_chance(folded, wep_template)
    local s = folded and folded.values
    if not s then
        return nil
    end
    local add = s.critical_strike_chance or 0
    if _is_melee(wep_template) then
        add = add + (s.melee_critical_strike_chance or 0)
    elseif _is_ranged(wep_template) then
        add = add + (s.ranged_critical_strike_chance or 0)
    end
    local chance = math.clamp(add, 0, 1)
    return chance * (1 - (s.critical_strike_chance_to_damage_convert or 0))
end

function M.mobility(unit, live_stat_buffs, folded)
    local s = live_stat_buffs
    if not unit or not s then
        return nil
    end
    local unit_data_ext = _ext(unit, 'unit_data_system')
    if not unit_data_ext then
        return nil
    end
    local archetype = unit_data_ext:archetype()
    local stam = archetype.stamina
    local sprint = archetype.sprint
    local dodge = archetype.dodge
    local weapon_ext = _ext(unit, 'weapon_system')
    local wep_stam = weapon_ext and weapon_ext:stamina_template()
    local wep_sprint = weapon_ext and weapon_ext:sprint_template()
    local wep_dodge = weapon_ext and weapon_ext:dodge_template()

    local max_stamina
    if stam then
        local _, folded_stamina = M.compute_max_vitals(folded, nil, nil, stam, wep_stam)
        if folded_stamina then
            max_stamina = folded_stamina
        else
            local ok, _, max = pcall(Stamina.current_and_max_value, unit, { current_fraction = 1 }, stam)
            max_stamina = ok and max or nil
        end
    end

    local fv = folded and folded.values
    local stamina_regen = stam
            and stam.regeneration_per_second * (s.stamina_regeneration_modifier or 1) * (s.stamina_regeneration_multiplier or 1)
        or nil
    local stamina_delay = stam and (stam.regeneration_delay + (s.stamina_regeneration_delay or 0)) or nil

    local sprint_speed = sprint and (sprint.sprint_move_speed + (wep_sprint and wep_sprint.sprint_speed_mod or 0))
        or nil
    local sprint_time = max_stamina
            and max_stamina / (((wep_stam and wep_stam.sprint_cost_per_second) or math.huge) * (s.sprinting_cost_multiplier or 1))
        or nil

    -- dodge prefers folded (talent buffs aren't active in the hub); live is the fallback.
    local extra_dodges = (fv and fv.extra_consecutive_dodges) or (s.extra_consecutive_dodges or 0)
    local dodge_count = wep_dodge and math.ceil((wep_dodge.diminishing_return_start or 2) + math.round(extra_dodges))
        or nil
    local dist_mod = (fv and fv.dodge_distance_modifier) or (s.dodge_distance_modifier or 1)
    local dodge_dist = wep_dodge
            and ((wep_dodge.base_distance or (dodge and dodge.base_distance) or 0) * (wep_dodge.distance_scale or 1) * dist_mod)
        or nil
    local dodge_speed = (fv and fv.dodge_speed_multiplier) or (s.dodge_speed_multiplier or 1)

    return {
        max_stamina = max_stamina,
        stamina_regen = stamina_regen,
        stamina_delay = stamina_delay,
        sprint_speed = sprint_speed,
        sprint_time = sprint_time,
        dodge_count = dodge_count,
        dodge_dist = dodge_dist,
        dodge_speed = dodge_speed,
    }
end

-- Mirrors PlayerUnitToughnessExtension._update_toughness. The coherency-gated rate
-- (line 149) and the always-on toughness_regen_percent term (line 161) are separate
-- mechanisms, so they're returned apart for distinct display.
function M.toughness_regen(unit, live_stat_buffs, tough_template, max_toughness, folded)
    local s = live_stat_buffs
    if not s or not tough_template then
        return nil, nil
    end
    local fv = folded and folded.values
    local wep_tough = _weapon_toughness_template(unit)
    local regen = tough_template.regeneration_speed
    local base_rate = regen and (regen.still or regen.moving or 0)
    local wep_mod_t = wep_tough and wep_tough.regeneration_speed_modifier
    local wep_mod = wep_mod_t and (wep_mod_t.still or wep_mod_t.moving or 1)

    local rate_modifier = (fv and fv.toughness_regen_rate_modifier or s.toughness_regen_rate_modifier or 1)
        * (fv and fv.toughness_regen_rate_multiplier or s.toughness_regen_rate_multiplier or 1)
    local coherency_value = (
        fv and fv.toughness_coherency_regen_rate_modifier
        or s.toughness_coherency_regen_rate_modifier
        or 0
    ) + (fv and fv.toughness_extra_regen_rate or s.toughness_extra_regen_rate or 0)
    local coherency_modifier = coherency_value
        * (fv and fv.toughness_coherency_regen_rate_multiplier or s.toughness_coherency_regen_rate_multiplier or 1)
    local coherency_regen = base_rate * wep_mod * rate_modifier * coherency_modifier
    local percent_regen = (fv and fv.toughness_regen_percent or s.toughness_regen_percent or 0) * (max_toughness or 0)
    return coherency_regen, percent_regen
end

function M.toughness_regen_delay(unit, live_stat_buffs, tough_template)
    local s = live_stat_buffs
    if not s or not tough_template then
        return nil
    end
    local wep_tough = _weapon_toughness_template(unit)
    local wep_mod = wep_tough and wep_tough.regeneration_delay_modifier or 1
    local buff_mod = (s.toughness_regen_delay_modifier or 1) * (s.toughness_regen_delay_multiplier or 1)
    return tough_template.regeneration_delay * wep_mod * buff_mod
end

function M.compose_taken(folded, prefix)
    local v = _folded_values(folded)
    return v and _compose_taken(v, prefix) or nil
end

-- Sum the bonus toughness regen granted by allocated talents' proc/over-time buffs that call
-- Toughness.replenish_percentage directly (never in stat_buffs). Returns a per-second fraction
-- of max toughness, plus contributing sources { name, per_second } (merged by display name).
function M.toughness_bonus_regen(unit, profile, toggles)
    local entries = _talent_entries(unit, profile)
    if not entries then
        return nil, nil
    end

    local ability_ext = _ext(unit, 'ability_system')
    local charges = 0
    if ability_ext then
        local fn = (toggles and toggles.assume_proc_stacks) and 'max_ability_charges' or 'remaining_ability_charges'
        local ok, n = pcall(ability_ext[fn], ability_ext, 'combat_ability')
        charges = (ok and n) or 0
    end

    local total, sources = 0, {}
    local function fold(template, display)
        if not template then
            return
        end
        -- Only _per_stack rates scale with stacks; a flat toughness_regen_per_second is
        -- applied once per buff instance regardless of stack count (matches the engine).
        local per_stack = template.toughness_regen_per_second_per_stack
        local per_s = template.toughness_regen_per_second
        if not per_s then
            local total_amount = template.toughness_restored_on_proc or template.toughness_regen_on_proc
            local dur = template.active_duration or template.duration
            per_s = (total_amount and dur and dur > 0) and (total_amount / dur) or nil
        end
        if per_s or per_stack then
            local stacks = (toggles and toggles.assume_proc_stacks) and (template.max_stacks or 1) or 1
            local contributed = (per_s or 0) + (per_stack or 0) * stacks
            if template.increased_toughness_regen_per_charge then
                contributed = contributed + template.increased_toughness_regen_per_charge * charges
            end
            if contributed > 0 then
                total = total + contributed
                sources[#sources + 1] = { name = display, per_second = contributed }
            end
        end
    end

    for i = 1, #entries do
        local entry = entries[i]
        local display = entry.display_name or entry.talent_name
        for j = 1, #entry.buff_template_names do
            local bname = entry.buff_template_names[j]
            local template = BuffTemplates[bname]
            fold(template, display)
            -- A server_only_proc_buff parent delegates its effect to a <name>_stack child that
            -- carries the toughness_regen fields; fold that child too.
            if template and template.class_name == 'server_only_proc_buff' then
                fold(BuffTemplates[bname .. '_stack'], display)
            end
        end
    end

    if total == 0 and #sources == 0 then
        return nil, nil
    end

    return total, M.merge_sources_by_name(sources, 'per_second', 'add')
end

function M.has_stat(folded, stat_key)
    local v = folded and folded.values and folded.values[stat_key]
    return type(v) == 'number' and v ~= 1
end

function M.stat_delta(folded, stat_key)
    local v = folded and folded.values and folded.values[stat_key]
    return type(v) == 'number' and (v - 1) or 0
end

function M.is_ranged(wep_template)
    return _is_ranged(wep_template)
end

return M
