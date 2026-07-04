local mod = get_mod('WeaponStats')

local DamageProfile = mod:original_require('scripts/utilities/attack/damage_profile')
local DamageCalculation = mod:original_require('scripts/utilities/attack/damage_calculation')
local ArmorSettings = mod:original_require('scripts/settings/damage/armor_settings')
local PowerLevelSettings = mod:original_require('scripts/settings/damage/power_level_settings')
local Action = mod:original_require('scripts/utilities/action/action')
local MasterItems = mod:original_require('scripts/backend/master_items')
local UISettings = mod:original_require('scripts/settings/ui/ui_settings')

local FALLBACK_LERP = 0.5
local DEFAULT_POWER_LEVEL = 500

local ARMOR_NAMES = {
    unarmored = 'Unarmored',
    armored = 'Flak',
    resistant = 'Unyielding',
    berserker = 'Maniac',
    super_armor = 'Carapace',
    disgustingly_resilient = 'Infested',
    void_shield = 'Void Shield',
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

local DAMAGE_TYPE_NAMES = {
    auto_bullet = 'Auto Bullet',
    bullet = 'Bullet',
    laser = 'Laser',
    plasma = 'Plasma',
    bolt = 'Bolt Shell',
    shotgun = 'Shotgun',
    fire = 'Fire',
    toxin = 'Toxin',
    warp = 'Warp',
    physical = 'Physical',
    electrocution = 'Electrocution',
    grenade_frag = 'Frag Grenade',
}

local STAGGER_NAMES = {
    melee = 'Melee',
    uppercut = 'Uppercut',
    killshot = 'Knockback',
    heavy = 'Heavy',
    light = 'Light',
    special = 'Special',
}

local ACTION_LABEL_OVERRIDES = {
    shoot_hip = 'Hipfire',
    shoot_zoomed = 'ADS',
    zoom_shoot = 'ADS Fire',
    shoot = 'Shoot',
    zoom = 'Aim',
    reload = 'Reload',
    wield = 'Wield',
    unwield = 'Unwield',
    weapon_special = 'Weapon Special',
    special = 'Special',
    pushfollowup = 'Push Follow-up',
    parry_special = 'Parry Special',
}

local function prettify_enum(s)
    if type(s) ~= 'string' then
        return tostring(s)
    end
    return (
        s:gsub('_', ' '):gsub('(%a)([%w]*)', function(first, rest)
            return first:upper() .. rest:lower()
        end)
    )
end

local WeaponStatsUtils = {}

function WeaponStatsUtils.armor_name(armor_key)
    return ARMOR_NAMES[armor_key] or prettify_enum(armor_key)
end

function WeaponStatsUtils.damage_type_name(damage_type)
    if damage_type == nil then
        return nil
    end
    if type(damage_type) == 'string' then
        return DAMAGE_TYPE_NAMES[damage_type] or prettify_enum(damage_type)
    end
    return tostring(damage_type)
end

function WeaponStatsUtils.stagger_name(stagger_category)
    if stagger_category == nil then
        return nil
    end
    return STAGGER_NAMES[stagger_category] or prettify_enum(stagger_category)
end

function WeaponStatsUtils.friendly_action_label(action_name)
    if type(action_name) ~= 'string' then
        return tostring(action_name)
    end
    local name = action_name:gsub('^action_', '')
    if ACTION_LABEL_OVERRIDES[name] then
        return ACTION_LABEL_OVERRIDES[name]
    end
    name = name:gsub('^light_', 'light '):gsub('^heavy_', 'heavy '):gsub('^special_', 'special ')
    return prettify_enum(name)
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

    -- Fallback for templates not listed in weapon_patterns (e.g. bot/exotic
    -- weapons): best-effort names from the first master item that references them.
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

-- first target for melee, default for ranged.
function WeaponStatsUtils.target_settings(damage_profile, is_ranged)
    if not damage_profile or not damage_profile.targets then
        return damage_profile
    end
    local idx = is_ranged and 'default_target' or 1
    return DamageProfile.target_settings(damage_profile, idx)
end

-- The game's damage helpers read `current_target_settings_lerp_values` off the lerp
-- table; set it from the per-target sub-table for UI calls (no real attacker),
-- restoring the previous value after.
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
    local ok, attack, impact = pcall(
        DamageCalculation.base_ui_damage,
        damage_profile,
        target_settings,
        power_level or DEFAULT_POWER_LEVEL,
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
    target_index
)
    local cur_lerps, prev = _with_target_lerps(action_lerp, target_index)
    local ok, mult = pcall(
        DamageCalculation.ui_finesse_multiplier,
        damage_profile,
        target_settings,
        ArmorSettings.types.unarmored,
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
        false -- armor_penetrating
    )
    _restore_lerps(action_lerp, prev)
    if not ok then
        return nil
    end
    return mod
end

-- The game's fallback ADM for an armor type when a profile lacks an explicit entry
-- (PowerLevelSettings.default_armor_damage_modifier).
function WeaponStatsUtils.default_armor_modifier(power_type, armor_type)
    local defaults = PowerLevelSettings.default_armor_damage_modifier
    local by_type = defaults and defaults[power_type or 'attack']
    return by_type and by_type[armor_type] or 1
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

function WeaponStatsUtils.armor_order()
    return ARMOR_ORDER
end

function WeaponStatsUtils.fallback_lerp()
    return FALLBACK_LERP
end

return WeaponStatsUtils
