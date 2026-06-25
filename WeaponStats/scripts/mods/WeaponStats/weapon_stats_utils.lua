local mod = get_mod('WeaponStats')

local DamageProfile = mod:original_require('scripts/utilities/attack/damage_profile')
local ArmorSettings = mod:original_require('scripts/settings/damage/armor_settings')

local FALLBACK_LERP = 0.5

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

-- Resolve a power_distribution entry at the item's real lerp for the given action.
function WeaponStatsUtils.resolve_power(action_lerp, entry, power_type)
    if type(entry) ~= 'table' then
        return entry
    end
    local lerp = WeaponStatsUtils.lerp_from_path(action_lerp, 'power_distribution', power_type) or FALLBACK_LERP
    return math.lerp(entry[1], entry[2], lerp)
end

-- Resolve the armor damage modifiers for every armor type, using the item's lerp.
-- Returns a list of { armor_key, normal, crit } (only types that have a modifier).
function WeaponStatsUtils.resolve_armor_table(profile, target_settings, action_lerp, power_type)
    local adm = target_settings.armor_damage_modifier or profile.armor_damage_modifier
    if not adm then
        return {}
    end

    local results = {}
    local crit_mod = profile.crit_mod

    for _, armor_key in ipairs(ARMOR_ORDER) do
        local armor_type = ArmorSettings.types[armor_key]
        local entry = adm[power_type] and adm[power_type][armor_type]
        if entry ~= nil then
            local lerp = WeaponStatsUtils.lerp_from_path(action_lerp, 'armor_damage_modifier', power_type, armor_type)
                or FALLBACK_LERP
            local normal = WeaponStatsUtils.lerp_entry(entry, lerp)
            local crit = normal
            local crit_entry = crit_mod and crit_mod[power_type] and crit_mod[power_type][armor_type]
            if crit_entry then
                crit = normal + WeaponStatsUtils.lerp_entry(crit_entry, lerp)
            end
            results[#results + 1] = {
                armor_key = armor_key,
                normal = normal,
                crit = crit,
            }
        end
    end

    return results
end

return WeaponStatsUtils
