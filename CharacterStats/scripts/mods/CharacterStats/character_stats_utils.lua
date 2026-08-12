local mod = get_mod('CharacterStats')

local Stamina = mod:original_require('scripts/utilities/attack/stamina')
local WeaponTemplate = mod:original_require('scripts/utilities/weapon/weapon_template')
local BuffSettings = mod:original_require('scripts/settings/buff/buff_settings')
local PlayerDifficultySettings = mod:original_require('scripts/settings/difficulty/player_difficulty_settings')
local BuffTemplates = mod:original_require('scripts/settings/buff/buff_templates')
local PlayerAbilities = mod:original_require('scripts/settings/ability/player_abilities/player_abilities')
local CharacterSheet = mod:original_require('scripts/utilities/character_sheet')
local WeaponTraitTemplates = mod:original_require('scripts/settings/equipment/weapon_traits/weapon_trait_templates')
local WeaponHandlingTemplates =
    mod:original_require('scripts/settings/equipment/weapon_handling_templates/weapon_handling_templates')
local WeaponTweakTemplates = mod:original_require('scripts/extension_systems/weapon/utilities/weapon_tweak_templates')
local Weapon = mod:original_require('scripts/extension_systems/weapon/weapon')
local MasterItems = mod:original_require('scripts/backend/master_items')
local HomePlanets = mod:original_require('scripts/settings/character/home_planets')
local Childhood = mod:original_require('scripts/settings/character/childhood')
local GrowingUp = mod:original_require('scripts/settings/character/growing_up')
local FormativeEvent = mod:original_require('scripts/settings/character/formative_event')
local Crimes = mod:original_require('scripts/settings/character/crimes')
local Personalities = mod:original_require('scripts/settings/character/personalities')
local CrimesCompabilityMap = mod:original_require('scripts/settings/character/crimes_compability_mapping')
local TraitValueParser = mod:original_require('scripts/utilities/trait_value_parser')
local SharedUtils = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/shared/shared_utils')

-- Constants -------------------------------------------------------------

local EMPTY = {}
local ABILITY_FIELD_BY_TYPE = {
    combat_ability = 'combat_ability',
    grenade_ability = 'grenade_ability',
    pocketable_ability = 'pocketable_ability',
}
local stat_buff_types = BuffSettings.stat_buff_types
local stat_buff_type_base = BuffSettings.stat_buff_type_base_values
local LERP_MIDPOINT = 0.5
local MAX_PLAYER_CHALLENGE = 5
local HAVOC_CHALLENGE_BY_RANK = {
    { max_rank = 10, challenge = 3 },
    { max_rank = 20, challenge = 4 },
    { max_rank = 40, challenge = 5 },
}

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

local function _assumed_ability_extension(profile)
    local max_charges = {}
    local function consider(ability_type, ability)
        if not ability or not ability.max_charges then
            return
        end
        max_charges[ability_type] = ability.max_charges
    end
    local function resolve(equipped)
        if type(equipped) == 'string' then
            return PlayerAbilities[equipped]
        end
        if type(equipped) ~= 'table' then
            return nil
        end
        return equipped.max_charges and equipped or PlayerAbilities[equipped.name]
    end
    local function consider_loadout(loadout)
        for ability_type, field_name in pairs(ABILITY_FIELD_BY_TYPE) do
            consider(ability_type, loadout[field_name])
        end
    end
    local function resolve_class_loadout()
        if not profile or not profile.archetype or not CharacterSheet.class_loadout then
            return nil
        end
        local loadout = {
            ability = {},
            blitz = {},
            aura = {},
            pocketable = {},
            passives = {},
            coherency = {},
            special_rules = {},
            buff_template_tiers = {},
            iconics = {},
            modifiers = {},
        }
        local ok = pcall(CharacterSheet.class_loadout, profile, loadout, false, profile.talents)
        return ok and loadout or nil
    end
    local class_loadout = resolve_class_loadout()
    if class_loadout then
        consider_loadout(class_loadout)
    end
    local abilities = profile and profile.abilities
    if type(abilities) == 'table' then
        for ability_type, equipped in pairs(abilities) do
            if not max_charges[ability_type] then
                consider(ability_type, resolve(equipped))
            end
        end
    end
    return {
        remaining_ability_charges = function(_, ability_type)
            return max_charges[ability_type] or 0
        end,
        max_ability_charges = function(_, ability_type)
            return max_charges[ability_type] or 0
        end,
    }
end

-- Use a stable maximum normal challenge for build stats; a configured Havoc rank selects its bracket.
local function _assumed_challenge(havoc_rank)
    havoc_rank = tonumber(havoc_rank) or 0
    if havoc_rank > 0 then
        for i = 1, #HAVOC_CHALLENGE_BY_RANK do
            local entry = HAVOC_CHALLENGE_BY_RANK[i]
            if havoc_rank <= entry.max_rank then
                return entry.challenge
            end
        end
    end
    return MAX_PLAYER_CHALLENGE
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

-- Max crit chance_modifier across the weapon's handling templates. Resolved per-item (the
-- chance_modifier is lerped by the item's stat rolls); falls back to base templates at midpoint.
local function _weapon_crit_modifier(wep_template, item)
    if not wep_template or not wep_template.__base_template_lookup then
        return nil
    end

    if item then
        local ok, tweak_templates = pcall(Weapon._init_traits, nil, wep_template, item, nil, nil)
        local handling = ok and tweak_templates and tweak_templates.weapon_handling
        if handling then
            local best = nil
            for _, stats in pairs(handling) do
                local mod = stats and stats.critical_strike and stats.critical_strike.chance_modifier
                if type(mod) == 'number' and (best == nil or mod > best) then
                    best = mod
                end
            end
            if best ~= nil then
                return best
            end
        end
    end

    local best = nil
    for action_name in pairs(wep_template.actions or EMPTY) do
        local base_id = WeaponTweakTemplates.get_template_identifiers(wep_template, 'weapon_handling', action_name)
        local cs = base_id and WeaponHandlingTemplates[base_id] and WeaponHandlingTemplates[base_id].critical_strike
        local mod = cs and cs.chance_modifier
        if type(mod) == 'table' then
            local lo, hi = mod.lerp_basic, mod.lerp_perfect
            if type(lo) == 'number' and type(hi) == 'number' then
                mod = math.lerp(lo, hi, 0.5)
            else
                mod = mod.lerp_perfect or mod.lerp_basic
            end
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

local function _static_stat_buffs(template, stat, cond, proc, ability_extension, stacks, lerp_t)
    local multiplier = template.stat_buff_multiplier
    local multipliers = template.stat_buff_multipliers
    if type(multiplier) ~= 'function' and type(multipliers) ~= 'table' then
        return stat, cond, proc
    end
    local template_data = { ability_extension = ability_extension }
    local template_context = {
        is_local_unit = false,
        is_player = false,
        is_server = false,
        stack_count = stacks or 1,
        buff_lerp_value = lerp_t,
        template = template,
    }
    local function resolve(stat_buffs)
        if type(stat_buffs) ~= 'table' then
            return stat_buffs
        end
        local resolved = {}
        for name, value in pairs(stat_buffs) do
            local value_multiplier = multipliers and multipliers[name] or multiplier
            if type(value_multiplier) == 'function' and type(value) == 'number' then
                local ok, result = pcall(value_multiplier, template_data, template_context)
                if ok and type(result) == 'number' then
                    value = value * result
                end
            end
            resolved[name] = value
        end
        return resolved
    end
    return resolve(stat), resolve(cond), resolve(proc)
end

local function _fold(result, template, tier, stacks, source, lerp_t, ability_extension)
    if not template then
        return
    end
    local stat, cond, proc = _effective(template, tier)
    stat, cond, proc = _static_stat_buffs(template, stat, cond, proc, ability_extension, stacks, lerp_t)
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

local function _trait_display_name(trait_item, trait_name, trait_level, lerp_value)
    local ok, text = pcall(TraitValueParser.trait_description, trait_item, trait_level, lerp_value)
    if ok and type(text) == 'string' and text ~= '' and not text:lower():find('unlocalized') then
        return text
    end
    return nil
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
                                    or _trait_display_name(trait_item, trait_name, rarity, trait.value)
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
                            or _trait_display_name(trait_item, trait_name, data.rarity, data.value)
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

-- Wounds have a difficulty base and additive stat buffs, so resolve the assumed difficulty
-- and bonuses together.
function M.compute_max_wounds(folded, base_wounds, archetype, havoc_rank)
    if type(base_wounds) ~= 'number' then
        return nil, nil
    end
    local challenge = _assumed_challenge(havoc_rank)
    local settings = PlayerDifficultySettings.archetype_wounds
    local by_archetype = archetype and settings and settings[archetype.name]
    local assumed_base = by_archetype and challenge and by_archetype[math.min(challenge, #by_archetype)] or base_wounds
    local values = folded and folded.values
    local extra_wounds = values and values.extra_max_amount_of_wounds or 0
    return math.max(assumed_base + extra_wounds, 1), assumed_base
end

-- max_health/max_toughness/max_stamina derived from the archetype BASE plus the folded stat
-- buffs. The live extension returns the base value where buffs aren't active (e.g. the hub),
-- so deriving from folded gives a consistent value everywhere and lines up with the per-source
-- breakdown.
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
    local ability_extension = _assumed_ability_extension(profile)
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
                _fold(result, template, entry.tier, _stacks_for(template, toggles), source, nil, ability_extension)
            end
            local rel = related[entry.talent_name]
            if rel then
                for j = 1, #rel do
                    local bname = rel[j]
                    local tmpl = BuffTemplates[bname]
                    if not passive[bname] and tmpl and tmpl.buff_category ~= 'aura' then
                        _fold(result, tmpl, entry.tier, _stacks_for(tmpl, toggles), source, nil, ability_extension)
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
                _fold(result, template, nil, _stacks_for(template, toggles), coh_source, nil, ability_extension)
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
            -- Engine applies override.stat_buffs as per-key replacements within each pass, and
            -- override.conditional/proc_stat_buffs wholesale. Merging separately double-counts.
            local stat_overrides = override and override.stat_buffs
            local function with_overrides(t)
                if not t then
                    return nil
                end
                if not stat_overrides then
                    return t
                end
                local copy = table.clone(t)
                for k, v in pairs(stat_overrides) do
                    if copy[k] ~= nil then
                        copy[k] = v
                    end
                end
                return copy
            end
            local base = with_overrides(template.stat_buffs)
            local cond = override and override.conditional_stat_buffs or with_overrides(template.conditional_stat_buffs)
            local proc = override and override.proc_stat_buffs or with_overrides(template.proc_stat_buffs)
            _merge(result, base, stacks, source)
            _merge(result, cond, stacks, source)
            _merge(result, proc, stacks, source)
        end
    end

    local archetype = profile and profile.archetype
    local base_crit = (archetype and archetype.base_critical_strike_chance) or 0
    if base_crit ~= 0 then
        _inject_source(result, 'critical_strike_chance', base_crit, mod:localize('source_base'))
    end
    local wep_template = M.wielded_weapon_template(unit, weapon_slot)
    local vl = unit and ScriptUnit.has_extension(unit, 'visual_loadout_system')
    local item = vl and weapon_slot and vl:item_from_slot(weapon_slot)
    local crit_mod = _weapon_crit_modifier(wep_template, item)
    if crit_mod and crit_mod ~= 0 then
        local weapon_name = (item and SharedUtils.safe_localize(item.display_name))
            or (wep_template and wep_template.name)
            or mod:localize('mod_name')
        _inject_source(result, 'critical_strike_chance', crit_mod, weapon_name)
    end

    for _, entry in ipairs(_gadget_buffs(player)) do
        _fold(
            result,
            BuffTemplates[entry.template_name],
            nil,
            1,
            entry.display_name,
            entry.lerp_value,
            ability_extension
        )
    end

    local havoc_rank = toggles.havoc_rank or 0
    if havoc_rank > 0 then
        local havoc_source = mod:localize('source_havoc')
        for _, name in ipairs(_havoc_debuffs(havoc_rank)) do
            _fold(result, BuffTemplates[name], nil, 1, havoc_source, nil, ability_extension)
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

-- Mirrors PlayerUnitToughnessExtension._update_toughness: coherency rate + toughness_regen_percent summed into one regen_rate.
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
    local percent_fraction = (fv and fv.toughness_regen_percent or s.toughness_regen_percent or 0)
    local total_regen = coherency_regen + percent_fraction * (max_toughness or 0)

    local percent_sources = nil
    local list = M.sources_for_stat(folded, 'toughness_regen_percent')
    if list and #list > 0 then
        local merged = M.merge_sources_by_name(list, 'delta', 'add')
        for i = 1, #merged do
            merged[i].per_second = merged[i].delta
            merged[i].delta = nil
        end
        percent_sources = merged
    end

    return total_regen, percent_sources
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

-- Proc/over-time talents that call Toughness.replenish_percentage directly; replenish modifiers applied to match in-game recovery.
function M.toughness_bonus_regen(unit, profile, toggles, live_stat_buffs, folded)
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

    local fv = folded and folded.values
    local replenish_mod = (fv and fv.toughness_replenish_modifier)
        or (live_stat_buffs and live_stat_buffs.toughness_replenish_modifier)
        or 1
    local replenish_mult = (fv and fv.toughness_replenish_multiplier)
        or (live_stat_buffs and live_stat_buffs.toughness_replenish_multiplier)
        or 1
    local multiplier = replenish_mod * replenish_mult
    total = total * multiplier
    for i = 1, #sources do
        sources[i].per_second = sources[i].per_second * multiplier
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
