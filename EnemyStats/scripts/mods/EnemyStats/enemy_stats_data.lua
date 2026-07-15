local mod = get_mod('EnemyStats')

local Breeds = require('scripts/settings/breed/breeds')
local ArmorSettings = require('scripts/settings/damage/armor_settings')
local MinionDifficultySettings = require('scripts/settings/difficulty/minion_difficulty_settings')
local HavocModifierConfig = require('scripts/settings/havoc/havoc_modifier_config')
local HavocSettings = require('scripts/settings/havoc_settings')
local armor_types = ArmorSettings.types

local DIFFICULTY_KEYS = { 'sedition', 'uprising', 'malice', 'heresy', 'damnation' }

local ARMOR_COLOR = {
    [armor_types.unarmored] = { 90, 195, 90 },
    [armor_types.armored] = { 215, 150, 50 },
    [armor_types.super_armor] = { 150, 155, 175 },
    [armor_types.berserker] = { 210, 70, 70 },
    [armor_types.resistant] = { 160, 95, 195 },
    [armor_types.disgustingly_resilient] = { 150, 185, 70 },
    [armor_types.player] = { 90, 195, 90 },
    [armor_types.void_shield] = { 80, 165, 240 },
}

local CATEGORY_ORDER = { 'regular', 'elite', 'specialist', 'boss' }

local HIT_ZONE_ORDER = {
    'head',
    'torso',
    'center_mass',
    'upper_left_arm',
    'lower_left_arm',
    'upper_right_arm',
    'lower_right_arm',
    'upper_left_leg',
    'lower_left_leg',
    'upper_right_leg',
    'lower_right_leg',
    'captain_void_shield',
    'shield',
    'corruptor_armor',
    'backpack',
    'tentacle',
    'weakspot',
    'right_shoulderguard',
    'afro',
    'tongue',
    'upper_tail',
    'lower_tail',
}

-- Specialist classification for breeds whose tags don't carry an explicit category.
local SPECIALIST_TAGS = {
    special = true,
    disabler = true,
    sniper = true,
    interrupter = true,
}

local name_cache = {}

local function breed_label(breed_name)
    if name_cache[breed_name] then
        return name_cache[breed_name]
    end
    local breed = Breeds[breed_name]
    local label
    if breed and breed.display_name then
        local ok, s = pcall(Localize, breed.display_name)
        if ok and s and s ~= '' and not s:find('^<') then
            label = s
        end
    end
    if not label then
        label = breed_name:gsub('_', ' ')
        label = label:gsub("(%a)([%w']*)", function(a, b)
            return a:upper() .. b
        end)
    end
    name_cache[breed_name] = label
    return label
end

local function breed_category(breed)
    local tags = breed.tags or {}
    if breed.is_boss or tags.monster then
        return 'boss'
    end
    if tags.elite then
        return 'elite'
    end
    for tag in pairs(SPECIALIST_TAGS) do
        if tags[tag] then
            return 'specialist'
        end
    end
    return 'regular'
end

-- 'monster' outranks 'ogryn' so daemonhosts/plague ogryns show as Monster.
local function breed_size(breed)
    local tags = breed.tags or {}
    if tags.monster or breed.is_boss then
        return 'monster'
    end
    if tags.ogryn then
        return 'ogryn'
    end
    return 'human'
end

-- Whether the breed has a ranged weapon kit; melee breeds have no top-level `ranged`.
local function breed_is_ranged(breed)
    return breed.ranged == true
end

-- Player-facing faction label (Dregs/Scabs/Moebians) from sub_faction_name.
local function breed_faction(breed)
    return breed.sub_faction_name or breed.faction_name or 'chaos'
end

local function zone_armor(breed, zone_name)
    local overrides = breed.hitzone_armor_override
    return overrides and overrides[zone_name] or breed.armor_type
end

local function breed_zone_lookup(breed)
    local zones = {}
    local hit_zones = breed.hit_zones
    if type(hit_zones) == 'table' then
        for i = 1, #hit_zones do
            local entry = hit_zones[i]
            if type(entry) == 'table' and entry.name then
                zones[entry.name] = true
            end
        end
    end
    return zones
end

local function format_number(n)
    if type(n) ~= 'number' then
        return nil
    end
    if n == math.floor(n) then
        return tostring(n)
    end
    return string.format('%.2f', n):gsub('%.?0+$', '')
end

local function tier_value(table_val, challenge)
    if type(table_val) ~= 'table' then
        return table_val
    end
    local idx = math.min(#table_val, challenge)
    return table_val[idx]
end

-- HavocModifierConfig accumulates modifiers from rank 1 up to the current rank.
local function havoc_modifiers_at_rank(rank)
    local accumulated = {}
    for i = 1, rank do
        local block = HavocModifierConfig[i]
        if block then
            for name, tier in pairs(block) do
                accumulated[name] = tier
            end
        end
    end
    return accumulated
end

-- Additive percentage for a havoc modifier at a rank. Returns 0 when inactive.
local function havoc_modifier_value(modifier_name, stat_key, modifiers)
    local tier = modifiers[modifier_name]
    if not tier then
        return 0
    end
    local templates = HavocSettings.modifier_templates or {}
    local template = templates[modifier_name]
    if type(template) ~= 'table' then
        return 0
    end
    local entry = template[tier]
    local value = entry and entry[stat_key]
    return type(value) == 'number' and value or 0
end

-- Total havoc health modifier for a breed at a rank.
local function havoc_health_modifier(breed, modifiers)
    local tags = breed.tags or {}
    local sum = 0
    if tags.elite then
        sum = sum + havoc_modifier_value('buff_elites', 'modify_elite_health', modifiers)
    end
    if tags.special or tags.interrupter then
        sum = sum + havoc_modifier_value('buff_specials', 'modify_special_health', modifiers)
    end
    if tags.monster then
        sum = sum + havoc_modifier_value('buff_monsters', 'modify_monster_health', modifiers)
    end
    if tags.horde then
        sum = sum + havoc_modifier_value('buff_horde', 'modify_horde_health', modifiers)
    end
    return sum
end

local function havoc_hit_mass_modifier(breed, modifiers)
    if not (breed.tags or {}).horde then
        return 0
    end
    return havoc_modifier_value('buff_horde', 'modify_horde_hit_mass', modifiers)
end

-- Havoc base challenge by rank bucket.
local function havoc_challenge(rank)
    if rank <= 10 then
        return 3
    elseif rank <= 20 then
        return 4
    end
    return 5
end

local EnemyStatsData = {}

local function difficulty_name(key)
    return mod:localize('diff_' .. key)
end

local function zone_name(zone_key)
    local s = mod:localize('zone_' .. zone_key)
    if s and not s:find('^<') then
        return s
    end
    return zone_key:gsub('_', ' '):gsub("(%a)([%w']*)", function(a, b)
        return a:upper() .. b
    end)
end

local function weakspot_name(type_key)
    return mod:localize('weakspot_' .. type_key)
end

-- Builds the full enemy list, grouped and sorted by category, deduped by display name.
function EnemyStatsData.build_enemy_list()
    local by_label = {}
    for breed_name, breed in pairs(Breeds) do
        if breed.tags then
            local label = breed_label(breed_name)
            local cat = breed_category(breed)
            local entry = by_label[label]
            -- First entry wins; keeps a stable canonical breed per display name.
            if not entry or (cat == 'boss' and entry.category ~= 'boss') then
                by_label[label] = {
                    breed_name = breed_name,
                    label = label,
                    category = cat,
                    size = breed_size(breed),
                    is_ranged = breed_is_ranged(breed),
                    faction = breed_faction(breed),
                }
            end
        end
    end

    local groups = {}
    for _, cat in ipairs(CATEGORY_ORDER) do
        groups[cat] = {}
    end
    for _, entry in pairs(by_label) do
        local group = groups[entry.category]
        if group then
            group[#group + 1] = entry
        end
    end
    for _, group in pairs(groups) do
        table.sort(group, function(a, b)
            return a.label:lower() < b.label:lower()
        end)
    end
    return groups
end

function EnemyStatsData.category_order()
    return CATEGORY_ORDER
end

-- Difficulty-scaling rows: { difficulty, health, hit_mass }.
function EnemyStatsData.difficulty_table(breed_name)
    local breed = Breeds[breed_name]
    if not breed then
        return nil
    end

    local health_settings = MinionDifficultySettings.health[breed_name]
    local hit_mass_setting = breed.hit_mass
    -- Non-minion breeds carry no difficulty scaling; skip empty rows.
    if not health_settings and hit_mass_setting == nil then
        return nil
    end
    local rows = {}

    -- Regular tiers
    for challenge = 1, #DIFFICULTY_KEYS do
        local key = DIFFICULTY_KEYS[challenge]
        local health = health_settings and tier_value(health_settings, challenge)
        local hm = tier_value(hit_mass_setting, challenge)
        rows[#rows + 1] = {
            difficulty = difficulty_name(key),
            is_havoc = false,
            health = format_number(health),
            hit_mass = format_number(hm),
        }
    end

    -- Havoc breakpoints: collapse ranks 1-40 into unique (challenge, hp, mass) combos.
    local havoc_rows = {}
    local prev = nil
    for rank = 1, 40 do
        local modifiers = havoc_modifiers_at_rank(rank)
        local challenge = havoc_challenge(rank)
        local hp_mod = havoc_health_modifier(breed, modifiers)
        local hm_mod = havoc_hit_mass_modifier(breed, modifiers)
        local base_hp = health_settings and tier_value(health_settings, challenge) or 0
        local base_hm = tier_value(hit_mass_setting, challenge) or 0
        local hp = base_hp * (1 + hp_mod)
        local hm = base_hm * (1 + hm_mod)
        local key = challenge .. ':' .. hp .. ':' .. hm
        if key ~= prev then
            prev = key
            havoc_rows[#havoc_rows + 1] = {
                rank_start = rank,
                rank_end = rank,
                is_havoc = true,
                health = format_number(hp),
                hit_mass = format_number(hm),
            }
        else
            havoc_rows[#havoc_rows].rank_end = rank
        end
    end
    local havoc_label = difficulty_name('havoc')
    for i = 1, #havoc_rows do
        local r = havoc_rows[i]
        if r.rank_start == r.rank_end then
            r.difficulty = havoc_label .. ' ' .. r.rank_start
        else
            r.difficulty = havoc_label .. ' ' .. r.rank_start .. '-' .. r.rank_end
        end
        rows[#rows + 1] = r
    end

    return rows
end

-- Per hit-zone armor breakdown with weakspot flags.
function EnemyStatsData.hit_zones(breed_name)
    local breed = Breeds[breed_name]
    if not breed then
        return nil
    end

    local zoneset = breed_zone_lookup(breed)
    local weakspot_types = breed.hit_zone_weakspot_types or {}
    local zones = {}

    for i = 1, #HIT_ZONE_ORDER do
        local zone = HIT_ZONE_ORDER[i]
        if zoneset[zone] then
            local armor_cat = zone_armor(breed, zone)
            local weakspot = weakspot_types[zone]
            zones[#zones + 1] = {
                zone = zone,
                label = zone_name(zone),
                armor_cat = armor_cat,
                armor_label = mod:localize('armor_' .. armor_cat),
                armor_color = ARMOR_COLOR[armor_cat] or { 200, 200, 200 },
                weakspot = weakspot,
                weakspot_label = weakspot and weakspot_name(weakspot) or nil,
            }
        end
    end

    -- Catch any zones not in the predefined order.
    for zone in pairs(zoneset) do
        local found = false
        for i = 1, #HIT_ZONE_ORDER do
            if HIT_ZONE_ORDER[i] == zone then
                found = true
                break
            end
        end
        if not found then
            local armor_cat = zone_armor(breed, zone)
            local weakspot = weakspot_types[zone]
            zones[#zones + 1] = {
                zone = zone,
                label = zone_name(zone),
                armor_cat = armor_cat,
                armor_label = mod:localize('armor_' .. armor_cat),
                armor_color = ARMOR_COLOR[armor_cat] or { 200, 200, 200 },
                weakspot = weakspot,
                weakspot_label = weakspot and weakspot_name(weakspot) or nil,
            }
        end
    end

    return zones
end

function EnemyStatsData.breed_info(breed_name)
    local breed = Breeds[breed_name]
    if not breed then
        return nil
    end

    local tags = breed.tags or {}
    local size = breed_size(breed)
    return {
        breed_name = breed_name,
        category = breed_category(breed),
        size = size,
        is_ranged = breed_is_ranged(breed),
        faction = breed_faction(breed),
        stagger_resistance = breed.stagger_resistance,
        stagger_reduction = breed.stagger_reduction,
        run_speed = breed.run_speed,
        walk_speed = breed.walk_speed,
        challenge_rating = breed.challenge_rating,
        tags = tags,
    }
end

return EnemyStatsData
