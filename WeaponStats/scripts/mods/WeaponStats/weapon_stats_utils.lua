local mod = get_mod('WeaponStats')

local DamageProfile = mod:original_require('scripts/utilities/attack/damage_profile')
local DamageCalculation = mod:original_require('scripts/utilities/attack/damage_calculation')
local ArmorSettings = mod:original_require('scripts/settings/damage/armor_settings')
local PowerLevelSettings = mod:original_require('scripts/settings/damage/power_level_settings')
local PowerLevel = mod:original_require('scripts/utilities/attack/power_level')
local Action = mod:original_require('scripts/utilities/action/action')
local MasterItems = mod:original_require('scripts/backend/master_items')
local UISettings = mod:original_require('scripts/settings/ui/ui_settings')
local WeaponHandlingTemplates =
    mod:original_require('scripts/settings/equipment/weapon_handling_templates/weapon_handling_templates')
local WeaponTweakTemplates = mod:original_require('scripts/extension_systems/weapon/utilities/weapon_tweak_templates')
local FALLBACK_LERP = 0.5
local DEFAULT_POWER_LEVEL = 500
local GESTALT_TOKENS = { 'smiter', 'linesman', 'tank', 'ninja_fencer' }

local function _localize_or_prettify(loc_id, key)
    local localized = mod:localize(loc_id)
    if localized and not localized:find('^<') then
        return localized
    end
    if type(key) ~= 'string' then
        return tostring(key)
    end
    local prettified = key:gsub('_', ' ')
    prettified = prettified:gsub('(%a)(%a+)', function(first, rest)
        return first:upper() .. rest
    end)
    return prettified
end

local function _label(prefix, key)
    if key == nil then
        return nil
    end
    return _localize_or_prettify(prefix .. tostring(key), key)
end

local WeaponStatsUtils = {}

function WeaponStatsUtils.armor_name(armor_key)
    return _label('armor_', armor_key)
end

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
    local prettified = key:gsub('_', ' ')
    prettified = prettified:gsub('(%a)(%a+)', function(first, rest)
        return first:upper() .. rest
    end)
    return prettified
end

-- Weapon display names ----------------------------------------------------

local function _safe_localize(text)
    if not text or text == '' or text == 'n/a' then
        return nil
    end
    local ok, localized = pcall(Localize, text)
    if not ok then
        return nil
    end
    return localized
end

-- item.weapon_family/pattern/mark_display_name are each { loc_id = "..." }.
local function _lore_name(item, field)
    local desc = item and item[field]
    local loc_id = desc and desc.loc_id
    return loc_id and _safe_localize(loc_id) or nil
end

-- template_name -> { family, pattern, mark }. Cached on the module.
local _weapon_name_cache
local function _weapon_name_map()
    if _weapon_name_cache then
        return _weapon_name_cache
    end
    local map = {}

    local weapon_patterns = UISettings and UISettings.weapon_patterns
    if weapon_patterns then
        for _pattern_key, pattern_data in pairs(weapon_patterns) do
            local family = _safe_localize(pattern_data.display_name)
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
                        }
                    end
                end
            end
        end
    end

    -- Fallback for templates not in weapon_patterns (bot/exotic weapons).
    local master_items = MasterItems and MasterItems.get_cached and MasterItems.get_cached()
    if master_items then
        for _id, item in pairs(master_items) do
            local template_name = item.weapon_template
            if template_name and not map[template_name] then
                map[template_name] = {
                    family = _lore_name(item, 'weapon_family_display_name'),
                    pattern = _lore_name(item, 'weapon_pattern_display_name'),
                    mark = _lore_name(item, 'weapon_mark_display_name'),
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
            -- Match the gestalt as a whole underscore-delimited token in any position
            -- (start / middle / end / whole name), never as a substring of another word.
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

    -- No gestalt token => the slot's default gestalt.
    if not gestalt then
        local displayed = weapon_template and weapon_template.displayed_attacks
        local entry = displayed and displayed[slot_key]
        if not entry then
            return nil
        end
        return _safe_localize(entry.display_name) or _label('gestalt_', entry.type)
    end

    return _safe_localize('loc_gestalt_' .. gestalt) or _label('gestalt_', gestalt)
end

-- Matches the in-game card: title = family, subtitle = pattern • mark.
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

-- Damage profile helpers --------------------------------------------------

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

-- lerp_values are keyed by action name, then optionally damage profile name.
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

-- Mirrors Action.stat_power_level so explosive/charged profiles use the right power.
function WeaponStatsUtils.action_power_level(action, template_index)
    if Action and Action.stat_power_level then
        local ok, pl = pcall(Action.stat_power_level, action, template_index)
        if ok and pl then
            return pl
        end
    end
    return action.power_level or DEFAULT_POWER_LEVEL
end

-- Damage profile target index: targets[1] for melee, targets.default_target for ranged.
function WeaponStatsUtils.target_settings(damage_profile, is_ranged)
    if not damage_profile or not damage_profile.targets then
        return damage_profile, nil
    end

    local target_index = damage_profile.targets[1] and 1 or 'default_target'
    return DamageProfile.target_settings(damage_profile, target_index), target_index
end

-- Lerpable {lerp_basic, lerp_perfect} -> midpoint; scalars pass through.
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

-- DamageProfile helpers read current_target_settings_lerp_values off the lerp table (set by
-- DamageProfile.lerp_values when an attacker exists). With no attacker we patch it onto
-- action_lerp for the call then restore; mirrors damage_profile.lua lerp_values().
-- Shared empty table so current_target_settings_lerp_values is never nil (lerp_value_from_path indexes it).
local _TARGET_SETTINGS_NO_LERP_VALUES = {}

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

function WeaponStatsUtils.base_powers(
    damage_profile,
    target_settings,
    power_level,
    action_lerp,
    dropoff_scalar,
    target_index
)
    local cur_lerps, prev = _with_target_lerps(action_lerp, target_index)

    -- power_level_multiplier is applied by DamageCalculation.calculate, not base_ui_damage.
    local resolved_power_level = power_level or DEFAULT_POWER_LEVEL
    if target_settings.power_level_multiplier then
        local pl_lerp = WeaponStatsUtils.lerp_from_path(cur_lerps, 'targets', target_index, 'power_level_multiplier')
        local mult = WeaponStatsUtils.lerp_entry(target_settings.power_level_multiplier, pl_lerp)
        if type(mult) == 'number' then
            resolved_power_level = resolved_power_level * mult
        end
    end

    local ok, attack, impact = pcall(
        DamageCalculation.base_ui_damage,
        damage_profile,
        target_settings,
        resolved_power_level,
        1, -- charge_level (full)
        dropoff_scalar,
        cur_lerps
    )
    _restore_lerps(action_lerp, prev)
    if not ok then
        return nil, nil
    end
    return attack, impact
end

-- Returns the additive-over-1 multiplier, e.g. 1.75 means +75% weakspot damage.
function WeaponStatsUtils.finesse_multiplier(
    damage_profile,
    target_settings,
    action_lerp,
    hit_weakspot,
    is_crit,
    target_index,
    armor_type
)
    -- armor_type selects the per-armor finesse_boost entry.
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
        false, -- armor_penetrating
        1 -- charge_level (full)
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

-- 0 = point-blank (no falloff), 1 = at/inside max range (full falloff).
-- false when the profile has no ranges (melee).
function WeaponStatsUtils.dropoff_scalar(hit_distance, damage_profile, action_lerp)
    local cur_lerps = action_lerp or {}
    local ok, scalar = pcall(DamageProfile.dropoff_scalar, hit_distance, damage_profile, cur_lerps)
    if not ok then
        return false
    end
    return scalar
end

function WeaponStatsUtils.fallback_lerp()
    return FALLBACK_LERP
end

-- Cleave target count from the power-curve pipeline (PowerLevel.scale_power_level_to_power_type_curve
-- then cleave_distribution), mapped onto PowerLevelSettings.cleave_output min/max.
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

function WeaponStatsUtils.cleave_values(profile, target_settings, power_level, action_lerp)
    if not profile then
        return nil, nil
    end

    local cleave_distribution = profile.cleave_distribution or PowerLevelSettings.default_cleave_distribution

    local scaled_power_level, _ =
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

-- Sticky damage entries for hit_stickyness_settings.always_sticky (or special-active) actions.
function WeaponStatsUtils.sticky_damage_entries(action, use_special_active)
    if type(action) ~= 'table' then
        return nil
    end

    local settings = action.hit_stickyness_settings
    if use_special_active then
        settings = action.hit_stickyness_settings_special_active or settings
    end

    if not settings or not (use_special_active or settings.always_sticky) then
        return nil
    end

    local damage = settings.damage
    if type(damage) ~= 'table' then
        return nil
    end

    local instances = damage.instances or 1
    if type(instances) ~= 'number' or instances <= 0 then
        return nil
    end

    local normal_profile = damage.damage_profile
    local last_profile = damage.last_damage_profile or normal_profile
    local power_level = damage.stat_power_level
        or damage.power_level
        or settings.stat_power_level
        or settings.power_level
        or DEFAULT_POWER_LEVEL

    local entries = {}

    local normal_ticks = instances - 1
    if normal_ticks > 0 and normal_profile then
        entries[#entries + 1] = { profile = normal_profile, weight = normal_ticks, power_level = power_level }
    end

    if last_profile then
        entries[#entries + 1] = { profile = last_profile, weight = 1, power_level = power_level }
    end

    return #entries > 0 and entries or nil
end

-- Inner explosion close_damage_profile (bolter/plasma), separate from the impact profile
function WeaponStatsUtils.explosion_profile(action, template_index)
    if type(action) ~= 'table' then
        return nil
    end

    local ok, explosion_template = pcall(Action.explosion_template, action, template_index)
    if not ok or not explosion_template then
        return nil
    end

    local inner = explosion_template.close_damage_profile
    if not inner then
        return nil
    end

    local power_level = explosion_template.static_power_level
    return inner, power_level
end

-- critical_strike.chance_modifier from weapon_handling
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
