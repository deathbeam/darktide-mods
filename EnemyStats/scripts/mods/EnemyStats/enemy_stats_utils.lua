local mod = get_mod('EnemyStats')
local SharedUtils = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/shared/shared_utils')

local Breeds = require('scripts/settings/breed/breeds')
local MinionDifficultySettings = require('scripts/settings/difficulty/minion_difficulty_settings')
local HavocModifierConfig = require('scripts/settings/havoc/havoc_modifier_config')
local HavocSettings = require('scripts/settings/havoc_settings')
local StaggerSettings = require('scripts/settings/damage/stagger_settings')
local BreedActions = require('scripts/settings/breed/breed_actions')
local DamageCalculation = require('scripts/utilities/attack/damage_calculation')
local DamageProfile = require('scripts/utilities/attack/damage_profile')

local DIFFICULTY_KEYS = { 'sedition', 'uprising', 'malice', 'heresy', 'damnation' }

-- Stagger types in display order; values are the enum numbers from StaggerSettings.
local STAGGER_TYPE_ORDER = {
    { key = 'light', label = 'stagger_light' },
    { key = 'medium', label = 'stagger_medium' },
    { key = 'heavy', label = 'stagger_heavy' },
    { key = 'light_ranged', label = 'stagger_light_ranged' },
    { key = 'explosion', label = 'stagger_explosion' },
    { key = 'killshot', label = 'stagger_killshot' },
    { key = 'sticky', label = 'stagger_sticky' },
    { key = 'electrocuted', label = 'stagger_electrocuted' },
}

local function difficulty_label(key)
    local base = mod:localize('diff_' .. key)
    if key == 'damnation' then
        return base .. ' / ' .. mod:localize('diff_auric')
    end
    return base
end

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

local MELEE_CHALLENGE = 3 -- heresy midpoint for the representative damage value

local MELEE_ATTACK_COLUMNS = {
    { label = nil },
    { label = nil },
    { label = nil },
    { label = nil },
    { label = nil },
}

local RANGED_ATTACK_COLUMNS = {
    { label = nil },
    { label = nil },
    { label = nil },
    { label = nil },
    { label = nil },
    { label = nil },
}

local function breed_category(breed)
    local category = SharedUtils.classify_breed(breed)
    if category == 'disabler' then
        category = 'specialist'
    elseif category == 'roamer' then
        category = 'horde'
    end
    return category
end

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
    return overrides and overrides[zone_name] or breed.armor_type or 'unarmored'
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

local function zone_name(zone_key)
    return SharedUtils.localize_or_prettify(mod, 'zone_', zone_key)
end

local function weakspot_name(type_key)
    return mod:localize('weakspot_' .. type_key)
end

local function breed_signature(breed)
    local hit_mass = breed.hit_mass
    local hit_mass_key = type(hit_mass) == 'table' and table.concat(hit_mass, ',') or tostring(hit_mass or '')
    local parts = {
        breed.armor_type or 'none',
        breed.run_speed or '',
        breed.walk_speed or '',
        breed.stagger_resistance or '',
        breed.stagger_reduction or '',
        breed.base_height or '',
        hit_mass_key,
        breed.ranged == true and 'r' or 'm',
    }
    local zone_list = {}
    for zone in pairs(breed_zone_lookup(breed)) do
        zone_list[#zone_list + 1] = zone .. ':' .. zone_armor(breed, zone)
    end
    table.sort(zone_list)
    return table.concat(parts, '|') .. '#' .. table.concat(zone_list, ',')
end

function EnemyStatsData.build_enemy_list()
    local all = {}
    for breed_name, breed in pairs(Breeds) do
        if breed.tags then
            all[#all + 1] = {
                breed_name = breed_name,
                label = SharedUtils.breed_display_name(breed_name),
                category = breed_category(breed),
                category_icon = SharedUtils.category_icon(breed_category(breed)),
                icon = SharedUtils.category_icon(breed_category(breed)),
                size = breed_size(breed),
                is_ranged = breed_is_ranged(breed),
                faction = breed_faction(breed),
                signature = breed_signature(breed, breed_name),
            }
        end
    end

    -- Collapse same-name breeds whose displayed stats are identical. A divergent
    -- mutator variant (e.g. a circumstance hound with lower HP) stays distinct.
    local by_label = {}
    for i = 1, #all do
        local entry = all[i]
        local group = by_label[entry.label]
        if not group then
            group = {}
            by_label[entry.label] = group
        end
        group[#group + 1] = entry
    end

    local deduped = {}
    for label, group in pairs(by_label) do
        local seen_sigs = {}
        for i = 1, #group do
            local entry = group[i]
            if not seen_sigs[entry.signature] then
                seen_sigs[entry.signature] = true
                deduped[#deduped + 1] = entry
            end
        end
    end

    -- Disambiguate any remaining same-name entries that genuinely differ.
    local label_counts = {}
    for i = 1, #deduped do
        local label = deduped[i].label
        label_counts[label] = (label_counts[label] or 0) + 1
    end
    for i = 1, #deduped do
        local entry = deduped[i]
        if label_counts[entry.label] > 1 then
            entry.label = entry.label .. ' (' .. entry.breed_name .. ')'
        end
    end

    table.sort(deduped, function(a, b)
        return a.label:lower() < b.label:lower()
    end)
    return deduped
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
            name = difficulty_label(key),
            is_havoc = false,
            cells = {
                { text = format_number(health) },
                { text = format_number(hm) },
            },
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
                cells = {
                    { text = format_number(hp) },
                    { text = format_number(hm) },
                },
            }
        else
            havoc_rows[#havoc_rows].rank_end = rank
        end
    end
    for i = 1, #havoc_rows do
        local r = havoc_rows[i]
        if r.rank_start == r.rank_end then
            r.name = difficulty_label('havoc') .. ' ' .. r.rank_start
        else
            r.name = difficulty_label('havoc') .. ' ' .. r.rank_start .. '-' .. r.rank_end
        end
        rows[#rows + 1] = r
    end

    return rows
end

-- Per hit-zone armor breakdown with weakspot flags.
local function _build_zone(zone, breed, weakspot_types)
    local armor_cat = zone_armor(breed, zone)
    local weakspot = weakspot_types[zone]
    local weakspot_color = weakspot and Color.ui_terminal(255, true) or Color.terminal_text_body(255, true)
    local armor_color = SharedUtils.armor_color(armor_cat)
    local armor_label = armor_cat and mod:localize('armor_' .. armor_cat) or ''
    return {
        zone = zone,
        name = zone_name(zone),
        label = zone_name(zone),
        armor_cat = armor_cat,
        armor_label = armor_label,
        armor_color = armor_color,
        weakspot = weakspot,
        weakspot_label = weakspot and weakspot_name(weakspot) or nil,
        cells = {
            { text = armor_label, color = armor_color },
            { text = weakspot and weakspot_name(weakspot) or '', color = weakspot_color },
        },
    }
end

function EnemyStatsData.hit_zones(breed_name)
    local breed = Breeds[breed_name]
    if not breed then
        return nil
    end

    local zoneset = breed_zone_lookup(breed)
    local weakspot_types = breed.hit_zone_weakspot_types or {}
    local zones = {}
    local seen = {}

    for i = 1, #HIT_ZONE_ORDER do
        local zone = HIT_ZONE_ORDER[i]
        if zoneset[zone] then
            seen[zone] = true
            zones[#zones + 1] = _build_zone(zone, breed, weakspot_types)
        end
    end

    -- Catch any zones not in the predefined order.
    for zone in pairs(zoneset) do
        if not seen[zone] then
            zones[#zones + 1] = _build_zone(zone, breed, weakspot_types)
        end
    end

    return zones
end

-- Per-stagger-type duration table (seconds) for the detail view.
function EnemyStatsData.stagger_table(breed_name)
    local breed = Breeds[breed_name]
    if not breed then
        return nil
    end
    local durations = breed.stagger_durations
    if not durations then
        return nil
    end
    local stagger_types = StaggerSettings.stagger_types
    local rows = {}
    for i = 1, #STAGGER_TYPE_ORDER do
        local entry = STAGGER_TYPE_ORDER[i]
        local type_id = stagger_types[entry.key]
        local duration = durations[type_id]
        if duration then
            rows[#rows + 1] = {
                name = mod:localize(entry.label),
                cells = {
                    { text = string.format('%.2fs', duration) },
                },
            }
        end
    end
    if #rows == 0 then
        return nil
    end
    return rows
end

-- Attack timing for melee and ranged actions.
--
-- Melee: one row per action, aggregating its animations into min/max timing ranges
-- (fastest vs slowest swing) plus the action's computed base damage and reach.
-- Captures every action with attack_anim_damage_timings + attack_anim_durations.
--
-- Ranged: one row per shooting action, with windup, burst size, fire rate, base damage,
-- max range, and spread. Captures every action with a shoot_template.

local function _fmt_time(n)
    if type(n) ~= 'number' then
        return '-'
    end
    return string.format('%.2fs', n)
end

-- Base damage for a minion attack at a given challenge level. Mirrors the game's
-- base_ui_damage path (same as WeaponStats), but seeds power_level from the breed's
-- power_level_type resolved against the action's attack-type key, exactly as
-- DifficultyManager.get_minion_attack_power_level does. Returns nil if any piece
-- is missing or the calc errors.
local function _base_damage(breed, action, attack_type, challenge)
    local profile = action.damage_profile
    if not profile then
        return nil
    end
    local breed_pl_type = breed.power_level_type
    local pl_type = type(breed_pl_type) == 'table' and breed_pl_type[attack_type] or breed_pl_type
    if not pl_type then
        return nil
    end
    local pl_settings = MinionDifficultySettings.power_level[pl_type]
    if not pl_settings then
        return nil
    end
    local power_level = pl_settings[math.min(#pl_settings, challenge)]
    if type(power_level) ~= 'number' then
        return nil
    end

    local target_index = profile.targets and (profile.targets[1] and 1 or 'default_target') or 1
    local target_settings = DamageProfile.target_settings(profile, target_index)
    if not target_settings then
        return nil
    end
    -- base_ui_damage indexes lerp_values.current_target_settings_lerp_values; pass an
    -- empty table so the default lerp fallbacks apply instead of crashing on nil.
    local lerp_values = { current_target_settings_lerp_values = {} }
    local ok, attack =
        pcall(DamageCalculation.base_ui_damage, profile, target_settings, power_level, 1, false, lerp_values)
    if not ok or type(attack) ~= 'number' then
        return nil
    end
    return attack
end

-- Format a min/max pair as a range string. Single value collapses to that value.
local function _fmt_range(lo, hi)
    if lo == nil then
        return '-'
    end
    if hi == nil or math.abs(hi - lo) < 0.005 then
        return string.format('%.2fs', lo)
    end
    return string.format('%.2fs–%.2fs', lo, hi)
end

-- One row per action, aggregating its animations into min/max timing ranges. The range
-- span (fastest vs slowest swing) is the useful "reaction window" signal; the per-anim
-- breakdown that WeaponStats merges would just be noise here since damage/reach are
-- shared across an action's anims. Sorted by fastest hit time (most dangerous first).
local function _melee_rows(breed, actions)
    local rows = {}
    for action_name, action in pairs(actions) do
        if type(action) == 'table' then
            local timings = action.attack_anim_damage_timings
            local durations = action.attack_anim_durations
            if type(timings) == 'table' and type(durations) == 'table' then
                local attack_type = action.power_level_type or 'melee'
                local damage = _base_damage(breed, action, attack_type, MELEE_CHALLENGE)
                local raw_reach = action.weapon_reach
                -- weapon_reach may be a number or a {default=X, attack_reach_up=Y} table;
                -- the default is the representative reach.
                local reach = type(raw_reach) == 'table' and (raw_reach.default or raw_reach[1]) or raw_reach
                local label = SharedUtils.localize_or_prettify(mod, 'action_', action_name)

                local hit_min, hit_max, dur_min, dur_max
                for anim_name, raw_hit in pairs(timings) do
                    local dur = durations[anim_name]
                    if type(dur) == 'number' and dur > 0 then
                        -- hit time may be a single number or a table of multi-hit timings
                        -- (daemonhost/berzerker combos); use the first and last hit for the range.
                        local first, last = raw_hit, raw_hit
                        if type(raw_hit) == 'table' then
                            first = raw_hit[1]
                            last = raw_hit[#raw_hit]
                        end
                        if type(first) == 'number' and type(last) == 'number' then
                            hit_min = not hit_min and first or math.min(hit_min, first)
                            hit_max = not hit_max and last or math.max(hit_max, last)
                            dur_min = not dur_min and dur or math.min(dur_min, dur)
                            dur_max = not dur_max and dur or math.max(dur_max, dur)
                        end
                    end
                end

                if hit_min then
                    local rec_min, rec_max = dur_min - hit_max, dur_max - hit_min
                    rows[#rows + 1] = {
                        name = label,
                        sort_hit = hit_min,
                        cells = {
                            { text = _fmt_range(hit_min, hit_max), color = Color.ui_terminal(255, true) },
                            { text = _fmt_range(dur_min, dur_max) },
                            { text = _fmt_range(rec_min, rec_max) },
                            { text = SharedUtils.fmt_num(damage), color = Color.ui_orange_medium(255, true) },
                            { text = reach and string.format('%.1f', reach) or '-' },
                        },
                    }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        return a.sort_hit < b.sort_hit
    end)
    return #rows > 0 and rows or nil
end

-- A ranged stat field may be a plain number or a difficulty-scaled table shaped as
-- { [diff]= {lo, hi}, ... } (1..5 = sedition..damnation). Resolve to a single
-- representative number: heresy (diff 3) midpoint. Returns nil if not resolvable.
local function _resolve_ranged_stat(value)
    if type(value) == 'number' then
        return value
    end
    if type(value) ~= 'table' then
        return nil
    end
    local entry = value[3] or value[1] or value[#value]
    if type(entry) == 'number' then
        return entry
    end
    if type(entry) == 'table' then
        local lo, hi = entry[1], entry[2]
        if type(lo) == 'number' and type(hi) == 'number' then
            return (lo + hi) / 2
        end
        if type(lo) == 'number' then
            return lo
        end
    end
    return nil
end

local function _ranged_rows(breed, actions)
    local rows = {}
    for action_name, action in pairs(actions) do
        if type(action) == 'table' and action.shoot_template then
            local windup = _resolve_ranged_stat(action.aim_duration or action.peek_duration)
            local num_shots = _resolve_ranged_stat(action.num_shots)
            local time_per_shot = _resolve_ranged_stat(action.time_per_shot)
            local max_range = action.max_distance_to_target
            local spread
            local shoot = action.shoot_template
            if type(shoot) == 'table' and type(shoot.spread) == 'number' then
                spread = math.radians_to_degrees(shoot.spread)
            end
            -- Ranged damage lives on hit_scan_template.damage.impact.damage_profile;
            -- ranged power_level_type from the breed.
            local damage
            local hit_scan = shoot and shoot.hit_scan_template
            local impact = hit_scan and hit_scan.damage and hit_scan.damage.impact
            if impact and impact.damage_profile then
                local ranged_action = { damage_profile = impact.damage_profile }
                damage = _base_damage(breed, ranged_action, 'ranged', MELEE_CHALLENGE)
            end
            rows[#rows + 1] = {
                name = SharedUtils.localize_or_prettify(mod, 'action_', action_name),
                sort_name = action_name,
                cells = {
                    { text = _fmt_time(windup), color = Color.ui_terminal(255, true) },
                    { text = num_shots and string.format('%d', num_shots) or '-' },
                    { text = _fmt_time(time_per_shot) },
                    { text = SharedUtils.fmt_num(damage), color = Color.ui_orange_medium(255, true) },
                    { text = max_range and string.format('%.0f', max_range) or '-' },
                    { text = spread and string.format('%.1f°', spread) or '-' },
                },
            }
        end
    end
    table.sort(rows, function(a, b)
        return a.sort_name < b.sort_name
    end)
    return #rows > 0 and rows or nil
end

-- Returns melee_rows, ranged_rows for a breed. Each is nil when the breed has no actions
-- of that category.
function EnemyStatsData.attack_tables(breed_name)
    local breed = Breeds[breed_name]
    local actions = breed and BreedActions[breed_name]
    if not actions then
        return nil, nil
    end
    MELEE_ATTACK_COLUMNS[1].label = mod:localize('stat_hit_time')
    MELEE_ATTACK_COLUMNS[2].label = mod:localize('stat_duration')
    MELEE_ATTACK_COLUMNS[3].label = mod:localize('stat_recovery')
    MELEE_ATTACK_COLUMNS[4].label = mod:localize('stat_damage')
    MELEE_ATTACK_COLUMNS[5].label = mod:localize('stat_weapon_reach')
    RANGED_ATTACK_COLUMNS[1].label = mod:localize('stat_windup')
    RANGED_ATTACK_COLUMNS[2].label = mod:localize('stat_shots')
    RANGED_ATTACK_COLUMNS[3].label = mod:localize('stat_fire_rate')
    RANGED_ATTACK_COLUMNS[4].label = mod:localize('stat_damage')
    RANGED_ATTACK_COLUMNS[5].label = mod:localize('stat_range')
    RANGED_ATTACK_COLUMNS[6].label = mod:localize('stat_spread')
    return _melee_rows(breed, actions), _ranged_rows(breed, actions)
end

EnemyStatsData.melee_attack_columns = function()
    return MELEE_ATTACK_COLUMNS
end
EnemyStatsData.ranged_attack_columns = function()
    return RANGED_ATTACK_COLUMNS
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
        category_icon = SharedUtils.category_icon(breed_category(breed)),
        size = size,
        is_ranged = breed_is_ranged(breed),
        faction = breed_faction(breed),
        armor_type = breed.armor_type,
        stagger_resistance = breed.stagger_resistance,
        stagger_reduction = breed.stagger_reduction,
        run_speed = breed.run_speed,
        walk_speed = breed.walk_speed,
        detection_radius = breed.detection_radius,
        challenge_rating = breed.challenge_rating,
        tags = tags,
    }
end

return EnemyStatsData
