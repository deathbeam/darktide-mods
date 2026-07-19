local mod = get_mod('WeaponStats')
local SharedUtils = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/shared/shared_utils')

local DamageProfile = mod:original_require('scripts/utilities/attack/damage_profile')
local DamageCalculation = mod:original_require('scripts/utilities/attack/damage_calculation')
local ArmorSettings = mod:original_require('scripts/settings/damage/armor_settings')
local PowerLevelSettings = mod:original_require('scripts/settings/damage/power_level_settings')
local PowerLevel = mod:original_require('scripts/utilities/attack/power_level')
local Action = mod:original_require('scripts/utilities/action/action')
local MasterItems = mod:original_require('scripts/backend/master_items')
local Items = mod:original_require('scripts/utilities/items')
local UISettings = mod:original_require('scripts/settings/ui/ui_settings')
local WeaponHandlingTemplates =
    mod:original_require('scripts/settings/equipment/weapon_handling_templates/weapon_handling_templates')
local WeaponTweakTemplates = mod:original_require('scripts/extension_systems/weapon/utilities/weapon_tweak_templates')

-- Constants
local FALLBACK_LERP = 0.5
local DEFAULT_POWER_LEVEL = 500
local DEFAULT_MELEE_ICON = 'content/ui/materials/icons/weapons/hud/combat_blade_01'
local DEFAULT_RANGED_ICON = 'content/ui/materials/icons/weapons/hud/autogun_01'
local MAX_TRAIT_RANK = 4

local function _valid_material(path)
    if not path or path == '' then
        return false
    end
    local can_get = Application and Application.can_get_resource
    if not can_get then
        return true
    end
    local ok, exists = pcall(can_get, 'material', path)
    return ok and exists or false
end

local GESTALT_TOKENS = {
    'smiter',
    'linesman',
    'tank',
    'ninja_fencer',
}

local DIRECTION_TOKENS = {
    left = 'left',
    right = 'right',
    cross = 'cross',
    up = 'up',
    down = 'down',
    stab = 'thrust',
    thrust = 'thrust',
    push = 'thrust',
    pull = 'thrust',
}

local COMBO_CHAIN_INPUTS = { 'light_attack', 'heavy_attack' }
local SPECIAL_CHAIN_INPUT = 'special_action'
local PUSH_CHAIN_INPUTS = { 'push', 'push_follow_up' }
local MODE_SWAP_PATTERNS = { '_activate', '_deactivate' }

local _TARGET_SETTINGS_NO_LERP_VALUES = {}

local function _label(prefix, key)
    return SharedUtils.localize_or_prettify(mod, prefix, key)
end

local WeaponStatsUtils = {
    MAX_TRAIT_RANK = MAX_TRAIT_RANK,
}

function WeaponStatsUtils.damage_type_name(damage_type)
    if damage_type == nil then
        return nil
    end
    if type(damage_type) ~= 'string' then
        return tostring(damage_type)
    end
    return _label('damage_type_', damage_type)
end

function WeaponStatsUtils.stagger_name(stagger_category)
    return _label('stagger_', stagger_category)
end

function WeaponStatsUtils.friendly_action_label(action_name)
    if type(action_name) ~= 'string' then
        return tostring(action_name)
    end
    local key = action_name:gsub('^action_', '')
    local localized = mod:localize('action_' .. key)
    if localized and not localized:find('^<') then
        return localized
    end
    key = key:gsub('^light_', 'light '):gsub('^heavy_', 'heavy '):gsub('^special_', 'special ')
    return SharedUtils.prettify(key)
end

-- Combo action numbering

local function _chain_targets(action, chain_input)
    local chains = action and action.allowed_chain_actions
    local entry = chains and chains[chain_input]
    if type(entry) ~= 'table' then
        return nil
    end

    if entry[1] ~= nil then
        local out = {}
        for i = 1, #entry do
            local child = entry[i]
            if type(child) == 'table' and type(child.action_name) == 'string' then
                out[#out + 1] = child.action_name
            end
        end
        return #out > 0 and out or nil
    end

    if type(entry.action_name) == 'string' then
        return { entry.action_name }
    end
    return nil
end

local function _first_chain_target(action, chain_input)
    local targets = _chain_targets(action, chain_input)
    return targets and targets[1]
end

local function _combo_strength(action, action_name)
    local strength = nil
    for _, field in ipairs({ 'damage_profile', 'inner_damage_profile', 'outer_damage_profile' }) do
        local ok, profile = pcall(function()
            return type(action[field]) == 'table' and action[field]
                or (field == 'damage_profile' and Action.damage_template(action))
        end)
        if ok and profile then
            if profile.melee_attack_strength == 'heavy' then
                return 'Heavy'
            elseif profile.melee_attack_strength == 'light' then
                strength = 'Light'
            end
        end
    end
    if strength then
        return strength
    end
    if action_name and action_name:find('heavy', 1, true) then
        return 'Heavy'
    end
    return nil
end

-- Walk a combo branch from start_sweep, numbering each sweep. Windups continue via
-- the combo input; sweeps continue via start_attack (next windup) then the combo input.
-- Rejoin (a late windup loops back to an earlier sweep) stops at a labelled action.
-- Skipped actions are walked past without consuming a number.
local function _walk_branch(actions, start_sweep, chain_input, label_for, names, skip)
    local index = 0
    local current = start_sweep
    while current and not names[current] do
        local action = actions[current]
        if not action then
            break
        end

        if action.kind == 'sweep' and not (skip and skip[current]) then
            index = index + 1
            names[current] = label_for(current, index)
        end

        if action.kind == 'windup' then
            current = _first_chain_target(action, chain_input)
        else
            current = _first_chain_target(action, 'start_attack') or _first_chain_target(action, chain_input)
        end
    end
end

function WeaponStatsUtils.is_powered_mode(action_name)
    return type(action_name) == 'string' and action_name:find('_special', 1, true) ~= nil
end

local function _label_for(chain_input, action_name)
    local base = chain_input == 'light_attack' and 'Light' or 'Heavy'
    if WeaponStatsUtils.is_powered_mode(action_name) then
        return 'Special ' .. base
    end
    return base
end

-- Walk every wield start_attack branch so mode-swap weapons (base + powered mode) both
-- get numbered. Each branch leads to a windup whose combo input is the first real sweep.
local function _number_combo(actions, chain_input, names, skip)
    local wield = actions.action_wield
    if not wield then
        return
    end

    for _, branch in ipairs(_chain_targets(wield, 'start_attack') or {}) do
        local start_action = actions[branch]
        if start_action and start_action.kind == 'windup' then
            local first_sweep = _first_chain_target(start_action, chain_input)
            if first_sweep and actions[first_sweep] and actions[first_sweep].kind == 'sweep' then
                _walk_branch(actions, first_sweep, chain_input, function(action_name, index)
                    return _label_for(chain_input, action_name) .. ' ' .. index
                end, names, skip)
            end
        end
    end
end

local function _number_specials(actions, names, skip)
    local special_action_name = nil
    for action_name, action in pairs(actions) do
        if type(action) == 'table' and action.kind == 'sweep' then
            local target = _first_chain_target(action, SPECIAL_CHAIN_INPUT)
            if target and actions[target] and actions[target].kind == 'sweep' and not names[target] then
                special_action_name = target
            end
        end
    end

    if not special_action_name then
        return
    end

    _walk_branch(actions, special_action_name, SPECIAL_CHAIN_INPUT, function(action_name, index)
        local strength = _combo_strength(actions[action_name], action_name)
        local label = strength and ('Weapon Special ' .. strength) or 'Weapon Special'
        return label .. ' ' .. index
    end, names, skip)
end

local function _tag_push_attacks(actions, names)
    local tagged = {}
    for _source_name, source_action in pairs(actions) do
        if type(source_action) == 'table' then
            for _, input in ipairs(PUSH_CHAIN_INPUTS) do
                local targets = _chain_targets(source_action, input)
                if targets then
                    for i = 1, #targets do
                        local target = targets[i]
                        local action = actions[target]
                        if action and action.kind == 'sweep' and not names[target] then
                            tagged[target] = true
                        end
                    end
                end
            end
        end
    end

    for action_name in pairs(tagged) do
        local strength = _combo_strength(actions[action_name], action_name)
        local prefix = WeaponStatsUtils.is_powered_mode(action_name) and 'Special Push Attack' or 'Push Attack'
        names[action_name] = strength and (prefix .. ' ' .. strength) or prefix
    end
end

local function _is_mode_swap_utility(action_name)
    for i = 1, #MODE_SWAP_PATTERNS do
        if action_name:find(MODE_SWAP_PATTERNS[i], 1, true) then
            return true
        end
    end
    return false
end

-- Returns {action_name -> display_name} and a skip set of mode-swap utility actions.
function WeaponStatsUtils.action_display_names(weapon_template)
    local actions = weapon_template and weapon_template.actions
    if type(actions) ~= 'table' then
        return {}, {}
    end

    local names = {}
    local skip = {}
    for action_name in pairs(actions) do
        if _is_mode_swap_utility(action_name) then
            skip[action_name] = true
        end
    end

    for _, input in ipairs(COMBO_CHAIN_INPUTS) do
        _number_combo(actions, input, names, skip)
    end
    _number_specials(actions, names, skip)
    _tag_push_attacks(actions, names)

    return names, skip
end

function WeaponStatsUtils.action_directions(action)
    if type(action) ~= 'table' then
        return {}
    end

    local override = action.attack_direction_override
    if type(override) == 'string' then
        local dir = DIRECTION_TOKENS[override:lower()]
        if dir then
            return { [dir] = true }
        end
    end

    local collected = {}
    for _, field in ipairs({ 'anim_event', 'anim_event_3p' }) do
        local value = action[field]
        if type(value) == 'string' then
            for token in value:lower():gmatch('[^_]+') do
                local dir = DIRECTION_TOKENS[token]
                if dir then
                    collected[dir] = true
                end
            end
        end
    end

    local dirs = {}
    if collected.thrust then
        dirs.thrust = true
    end
    local has_side = false
    for dir in pairs(collected) do
        if dir == 'left' or dir == 'right' or dir == 'cross' then
            dirs[dir] = true
            has_side = true
        end
    end
    if not has_side then
        if collected.up then
            dirs.up = true
        end
        if collected.down then
            dirs.down = true
        end
    end
    return dirs
end

-- Weapon display names

local function _lore_name(item, field)
    local desc = item and item[field]
    local loc_id = desc and desc.loc_id
    return loc_id and SharedUtils.safe_localize(loc_id) or nil
end

local _weapon_name_cache
local function _weapon_name_map()
    if _weapon_name_cache then
        return _weapon_name_cache
    end
    local map = {}

    local weapon_patterns = UISettings and UISettings.weapon_patterns
    if weapon_patterns then
        for _pattern_key, pattern_data in pairs(weapon_patterns) do
            local family = SharedUtils.safe_localize(pattern_data.display_name)
            local marks = pattern_data.marks
            if marks then
                for i = 1, #marks do
                    local mark = marks[i]
                    local template_name = mark.name
                    if template_name then
                        local item = MasterItems and MasterItems.get_item and MasterItems.get_item(mark.item)
                        map[template_name] = {
                            family = family,
                            pattern = _lore_name(item, 'weapon_pattern_display_name'),
                            mark = _lore_name(item, 'weapon_mark_display_name'),
                            hud_icon = _valid_material(item and item.hud_icon) and item.hud_icon or nil,
                        }
                    end
                end
            end
        end
    end

    local master_items = MasterItems and MasterItems.get_cached and MasterItems.get_cached()
    if master_items then
        for _id, item in pairs(master_items) do
            local template_name = item.weapon_template
            if template_name and not map[template_name] then
                map[template_name] = {
                    family = _lore_name(item, 'weapon_family_display_name'),
                    pattern = _lore_name(item, 'weapon_pattern_display_name'),
                    mark = _lore_name(item, 'weapon_mark_display_name'),
                    hud_icon = _valid_material(item.hud_icon) and item.hud_icon or nil,
                }
            end
        end
    end

    _weapon_name_cache = map
    return map
end

function WeaponStatsUtils.attack_type_name(weapon_template, slot_key, damage_profile_name)
    local gestalt = nil

    if type(damage_profile_name) == 'string' then
        for i = 1, #GESTALT_TOKENS do
            local token = GESTALT_TOKENS[i]
            local token_len = #token
            if
                damage_profile_name == token
                or damage_profile_name:sub(1, token_len + 1) == token .. '_'
                or damage_profile_name:sub(-(token_len + 1)) == '_' .. token
                or damage_profile_name:find('_' .. token .. '_', 1, true)
            then
                gestalt = token
                break
            end
        end
    end

    if not gestalt then
        local displayed = weapon_template and weapon_template.displayed_attacks
        local entry = displayed and displayed[slot_key]
        if not entry then
            return nil
        end
        return SharedUtils.safe_localize(entry.display_name) or _label('gestalt_', entry.type)
    end

    return SharedUtils.safe_localize('loc_gestalt_' .. gestalt) or _label('gestalt_', gestalt)
end

function WeaponStatsUtils.weapon_display_name(template_name)
    local map = _weapon_name_map()
    local entry = map[template_name]
    if not entry then
        return nil, nil
    end
    local family = entry.family
    local pattern = entry.pattern
    local mark = entry.mark

    local display_name = (family and family ~= 'n/a') and family or nil

    local sub_parts = {}
    if pattern and pattern ~= 'n/a' then
        sub_parts[#sub_parts + 1] = pattern
    end
    if mark and mark ~= 'n/a' then
        sub_parts[#sub_parts + 1] = mark
    end
    local sub_display_name = #sub_parts > 0 and table.concat(sub_parts, ' • ') or nil

    return display_name, sub_display_name, family
end
function WeaponStatsUtils.weapon_hud_icon(template_name, is_ranged)
    local map = _weapon_name_map()
    local entry = map[template_name]
    local hud_icon = entry and entry.hud_icon
    return hud_icon or (is_ranged and DEFAULT_RANGED_ICON or DEFAULT_MELEE_ICON)
end

-- Returns the available blessing (trait) items for a weapon item, sorted by
-- display name. Filters master items for item_type == 'TRAIT' matching the
-- weapon's trait_category.
function WeaponStatsUtils.weapon_blessings(item)
    if not item then
        return nil
    end
    local category = Items.trait_category(item)
    if not category then
        return nil
    end
    local cached = MasterItems.get_cached()
    if not cached then
        return nil
    end
    local blessings = {}
    for _id, trait_item in pairs(cached) do
        if trait_item.item_type == 'TRAIT' and Items.trait_category(trait_item) == category then
            blessings[#blessings + 1] = trait_item
        end
    end
    if #blessings == 0 then
        return nil
    end
    table.sort(blessings, function(a, b)
        return (a.display_name or a.name) < (b.display_name or b.name)
    end)
    return blessings
end

-- Returns the description text for a trait at the highest rank.
function WeaponStatsUtils.trait_description(trait_item)
    if not trait_item then
        return nil
    end
    local success, desc = pcall(Items.trait_description, trait_item, MAX_TRAIT_RANK, nil)
    return success and desc or nil
end

-- Damage profile helpers
function WeaponStatsUtils.lerp_entry(entry, lerp_value)
    if type(entry) ~= 'table' then
        return entry
    end
    return math.lerp(entry[1], entry[2], lerp_value or FALLBACK_LERP)
end

function WeaponStatsUtils.lerp_from_path(action_lerp, ...)
    if not action_lerp then
        return nil
    end
    local ok, value = pcall(DamageProfile.lerp_value_from_path, action_lerp, ...)
    if not ok then
        return nil
    end
    return value
end

function WeaponStatsUtils.lerp_for_action(damage_profile_lerp_values, action_name, damage_profile)
    if not damage_profile_lerp_values then
        return nil
    end
    local cur = damage_profile_lerp_values[action_name]
    if not cur then
        return nil
    end
    if damage_profile and damage_profile.name then
        cur = cur[damage_profile.name] or cur
    end
    return cur
end

function WeaponStatsUtils.action_power_level(action, template_index)
    if Action and Action.stat_power_level then
        local ok, pl = pcall(Action.stat_power_level, action, template_index)
        if ok and pl then
            return pl
        end
    end
    return action.power_level or DEFAULT_POWER_LEVEL
end

function WeaponStatsUtils.target_settings(damage_profile)
    if not damage_profile or not damage_profile.targets then
        return damage_profile, nil
    end

    local target_index = damage_profile.targets[1] and 1 or 'default_target'
    return DamageProfile.target_settings(damage_profile, target_index), target_index
end

function WeaponStatsUtils.resolve_lerpable(value)
    if type(value) ~= 'table' then
        return value
    end
    local lo = value.lerp_basic
    local hi = value.lerp_perfect
    if type(lo) == 'number' and type(hi) == 'number' then
        return math.lerp(lo, hi, 0.5)
    end
    return nil
end

local function _with_target_lerps(action_lerp, target_index)
    local cur = action_lerp or {}
    local targets = cur.targets
    local key = target_index or 1
    local ts_lerps = targets and (targets[key] or targets.default_target) or _TARGET_SETTINGS_NO_LERP_VALUES
    local prev = cur.current_target_settings_lerp_values
    cur.current_target_settings_lerp_values = ts_lerps
    return cur, prev
end

local function _restore_lerps(action_lerp, prev)
    if action_lerp then
        action_lerp.current_target_settings_lerp_values = prev
    end
end

local function _apply_power_level_multiplier(power_level, target_settings, action_lerp)
    if not target_settings or not target_settings.power_level_multiplier then
        return power_level
    end
    local pl_lerp = WeaponStatsUtils.lerp_from_path(action_lerp, 'targets', 1, 'power_level_multiplier')
    local mult = WeaponStatsUtils.lerp_entry(target_settings.power_level_multiplier, pl_lerp)
    if type(mult) == 'number' then
        return power_level * mult
    end
    return power_level
end

function WeaponStatsUtils.base_powers(
    damage_profile,
    target_settings,
    power_level,
    action_lerp,
    dropoff_scalar,
    target_index
)
    local cur_lerps, prev = _with_target_lerps(action_lerp, target_index)

    local resolved_power_level =
        _apply_power_level_multiplier(power_level or DEFAULT_POWER_LEVEL, target_settings, action_lerp)

    local ok, attack, impact = pcall(
        DamageCalculation.base_ui_damage,
        damage_profile,
        target_settings,
        resolved_power_level,
        1,
        dropoff_scalar,
        cur_lerps
    )
    _restore_lerps(action_lerp, prev)
    if not ok then
        return nil, nil
    end
    return attack, impact
end

function WeaponStatsUtils.finesse_multiplier(
    damage_profile,
    target_settings,
    action_lerp,
    hit_weakspot,
    is_crit,
    target_index,
    armor_type
)
    armor_type = armor_type or ArmorSettings.types.unarmored
    local cur_lerps, prev = _with_target_lerps(action_lerp, target_index)
    local ok, mult = pcall(
        DamageCalculation.ui_finesse_multiplier,
        damage_profile,
        target_settings,
        armor_type,
        hit_weakspot,
        is_crit,
        cur_lerps
    )
    _restore_lerps(action_lerp, prev)
    if not ok then
        return 1
    end
    return mult or 1
end

function WeaponStatsUtils.armor_modifier(
    damage_profile,
    target_settings,
    action_lerp,
    power_type,
    armor_type,
    is_crit,
    dropoff_scalar,
    target_index
)
    local cur_lerps, prev = _with_target_lerps(action_lerp, target_index)
    local ok, mod = pcall(
        DamageProfile.armor_damage_modifier,
        power_type or 'attack',
        damage_profile,
        target_settings,
        cur_lerps,
        armor_type,
        is_crit,
        dropoff_scalar,
        false,
        1
    )
    _restore_lerps(action_lerp, prev)
    if not ok or not mod then
        local defaults = PowerLevelSettings.default_armor_damage_modifier
        local by_type = defaults and defaults[power_type or 'attack']
        return by_type and by_type[armor_type] or 1
    end
    return mod
end

function WeaponStatsUtils.ranges(damage_profile, action_lerp)
    if not damage_profile or not damage_profile.ranges then
        return nil, nil
    end
    local cur_lerps = action_lerp or {}
    local ok, min_r, max_r = pcall(DamageProfile.ranges, damage_profile, cur_lerps)
    if not ok then
        return nil, nil
    end
    return min_r, max_r
end

function WeaponStatsUtils.dropoff_scalar(hit_distance, damage_profile, action_lerp)
    local cur_lerps = action_lerp or {}
    local ok, scalar = pcall(DamageProfile.dropoff_scalar, hit_distance, damage_profile, cur_lerps)
    if not ok then
        return false
    end
    return scalar
end

local function _cleave_value(cleave_min, cleave_range, scaled_cleave_power_level, distribution, power_type, action_lerp)
    local dist = distribution and distribution[power_type]

    if type(dist) == 'table' then
        local lerp_value = WeaponStatsUtils.lerp_from_path(action_lerp, 'cleave_distribution', power_type)
            or FALLBACK_LERP
        local ok, resolved = pcall(DamageProfile.lerp_damage_profile_entry, dist, lerp_value)
        if ok and type(resolved) == 'number' then
            dist = resolved
        end
    end

    if type(dist) ~= 'number' then
        return 0
    end

    local cleave_power_level = scaled_cleave_power_level * dist
    local percentage = PowerLevel.power_level_percentage(cleave_power_level)
    return cleave_min + cleave_range * percentage
end

function WeaponStatsUtils.cleave_values(profile, power_level, action_lerp)
    if not profile then
        return nil, nil
    end

    local cleave_distribution = profile.cleave_distribution or PowerLevelSettings.default_cleave_distribution

    local scaled_power_level =
        PowerLevel.scale_by_charge_level(power_level or DEFAULT_POWER_LEVEL, 1, profile.charge_level_scaler)
    local scaled_cleave_power_level =
        PowerLevel.scale_power_level_to_power_type_curve(scaled_power_level, 'cleave', nil, nil, nil, nil, nil, profile)

    local cleave_output = PowerLevelSettings.cleave_output
    local cleave_min, cleave_max = cleave_output.min, cleave_output.max
    local cleave_range = cleave_max - cleave_min

    local attack =
        _cleave_value(cleave_min, cleave_range, scaled_cleave_power_level, cleave_distribution, 'attack', action_lerp)
    local impact =
        _cleave_value(cleave_min, cleave_range, scaled_cleave_power_level, cleave_distribution, 'impact', action_lerp)

    return attack, impact
end

-- Extra damage applied alongside the main profile: inner explosion (bolter/plasma) plus
-- sticky ticks (chainswords). Each entry carries its own power level.
function WeaponStatsUtils.extra_damage_entries(action, main_profile, template_index, use_special_active)
    local entries = {}

    if type(action) == 'table' then
        local ok, explosion_template = pcall(Action.explosion_template, action, template_index)
        local inner = ok and explosion_template and explosion_template.close_damage_profile
        if inner and inner ~= main_profile then
            entries[#entries + 1] = {
                profile = inner,
                weight = 1,
                power_level = explosion_template.static_power_level,
            }
        end
    end

    local settings = action and action.hit_stickyness_settings
    if use_special_active and action then
        settings = action.hit_stickyness_settings_special_active or settings
    end
    if settings and (use_special_active or settings.always_sticky) then
        local damage = settings.damage
        if type(damage) == 'table' then
            local instances = damage.instances or 1
            if type(instances) == 'number' and instances > 0 then
                local normal_profile = damage.damage_profile
                local last_profile = damage.last_damage_profile or normal_profile
                local power_level = damage.stat_power_level or damage.power_level or DEFAULT_POWER_LEVEL

                local normal_ticks = instances - 1
                if normal_ticks > 0 and normal_profile then
                    entries[#entries + 1] =
                        { profile = normal_profile, weight = normal_ticks, power_level = power_level }
                end
                if last_profile then
                    entries[#entries + 1] = { profile = last_profile, weight = 1, power_level = power_level }
                end
            end
        end
    end

    return #entries > 0 and entries or nil
end

function WeaponStatsUtils.explosion_suppression(action, template_index)
    if type(action) ~= 'table' then
        return nil, nil
    end
    local ok, explosion_template = pcall(Action.explosion_template, action, template_index)
    if not ok or not explosion_template then
        return nil, nil
    end
    local area = explosion_template.explosion_area_suppression
    if type(area) ~= 'table' then
        return nil, nil
    end
    local value = WeaponStatsUtils.lerp_entry(area.suppression_value)
    local radius = WeaponStatsUtils.lerp_entry(area.distance)
    return (type(value) == 'number' and math.abs(value) > 0.01 and value or nil),
        (type(radius) == 'number' and radius > 0.01 and radius or nil)
end

function WeaponStatsUtils.crit_chance_modifier(action, weapon_template, weapon_tweak_templates, action_name)
    if type(action) ~= 'table' then
        return nil
    end

    local chance_modifier

    if weapon_tweak_templates and weapon_template and action_name then
        local handling = weapon_tweak_templates['weapon_handling']
        if handling then
            local ok, _, identifier =
                pcall(WeaponTweakTemplates.get_template_identifiers, weapon_template, 'weapon_handling', action_name)
            if ok and identifier then
                local action_stats = handling[identifier]
                local critical_strike = action_stats and action_stats.critical_strike
                chance_modifier = critical_strike and critical_strike.chance_modifier
            end
        end
    end

    if chance_modifier == nil then
        local template_name = action.weapon_handling_template or 'none'
        local handling_template = WeaponHandlingTemplates[template_name]
        local critical_strike = handling_template and handling_template.critical_strike
        chance_modifier = critical_strike and critical_strike.chance_modifier
    end

    chance_modifier = WeaponStatsUtils.resolve_lerpable(chance_modifier)

    if type(chance_modifier) ~= 'number' or chance_modifier <= 0 then
        return nil
    end

    return chance_modifier
end

return WeaponStatsUtils
