local mod = get_mod('WeaponStats')

local DamageProfile = mod:original_require('scripts/utilities/attack/damage_profile')
local DamageCalculation = mod:original_require('scripts/utilities/attack/damage_calculation')
local ArmorSettings = mod:original_require('scripts/settings/damage/armor_settings')
local Action = mod:original_require('scripts/utilities/action/action')

local FALLBACK_LERP = 0.5
local DEFAULT_POWER_LEVEL = 500

local ARMOR_NAMES = {
    unarmored = 'Unarmored',
    armored = 'Flak',
    resistant = 'Unyielding',
    player = 'Player',
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
    'player',
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

local GIBBING_POWER_NAMES = {
    always = 'Always',
    light = 'Light',
    medium = 'Medium',
    heavy = 'Heavy',
    impossible = 'None',
    infinite = 'Infinite',
}

local GIBBING_TYPE_NAMES = {
    sawing = 'Sawing',
    crushing = 'Crushing',
    explosive = 'Explosive',
    arc = 'Arc',
    ballistic = 'Ballistic',
    boltshell = 'Bolt Shell',
    explosion = 'Explosion',
    fire = 'Fire',
    implosion = 'Implosion',
    laser = 'Laser',
    phosphor = 'Phosphor',
    plasma = 'Plasma',
    toxin = 'Toxin',
    warp_lightning = 'Warp Lightning',
    warp_shard = 'Warp Shard',
    warp = 'Warp',
    default = 'Default',
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

function WeaponStatsUtils.gibbing_power_name(power)
    return power and (GIBBING_POWER_NAMES[power] or prettify_enum(power)) or nil
end

function WeaponStatsUtils.gibbing_type_name(gib_type)
    return gib_type and (GIBBING_TYPE_NAMES[gib_type] or prettify_enum(gib_type)) or nil
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

-- Resolve a {min, max} entry at the given lerp value; non-table values pass through.
function WeaponStatsUtils.lerp_entry(entry, lerp_value)
    if type(entry) ~= 'table' then
        return entry
    end
    return math.lerp(entry[1], entry[2], lerp_value or FALLBACK_LERP)
end

-- Look up a per-item lerp value (0-1) by path inside the action's lerp table.
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

-- The lerp table returned by Weapon._init_traits is keyed by action name; this fetches the
-- lerp values for one action (and its damage profile) in the shape DamageProfile expects.
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

-- Resolve the power_level used for stat display for an action/template index.
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

-- Target settings the game uses for damage UI (first target for melee, default for ranged).
function WeaponStatsUtils.target_settings(damage_profile, is_ranged)
    if not damage_profile or not damage_profile.targets then
        return damage_profile
    end
    local idx = is_ranged and 'default_target' or 1
    return DamageProfile.target_settings(damage_profile, idx)
end

-- The game's damage helpers read `current_target_settings_lerp_values` off the lerp table.
-- For UI calls with no real attacker, set it from the per-target sub-table (and restore the
-- previous value afterwards) so lerpable armor/power entries resolve correctly.
local function _with_target_lerps(action_lerp, target_index)
    local cur = action_lerp or {}
    local targets = cur.targets
    local key = target_index or 1
    local ts_lerps = targets and (targets[key] or targets.default_target)
    local prev = cur.current_target_settings_lerp_values
    if ts_lerps then
        cur.current_target_settings_lerp_values = ts_lerps
    end
    return cur, prev
end

local function _restore_lerps(action_lerp, prev)
    if action_lerp then
        action_lerp.current_target_settings_lerp_values = prev
    end
end

-- Scaled base attack/impact power at the item's real lerp, using the game's own helper so the
-- numbers match what the in-game weapon card shows.
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

-- Finesse (weakspot) and crit multipliers at the item's real lerp, matching the in-game card.
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

-- Armor damage modifier (0..1+) for a power_type/armor/crit combo at the item's lerp.
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

-- Effective range min/max (near/far) for ranged profiles at the item's lerp.
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

function WeaponStatsUtils.armor_order()
    return ARMOR_ORDER
end

function WeaponStatsUtils.fallback_lerp()
    return FALLBACK_LERP
end

return WeaponStatsUtils
