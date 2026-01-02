local mod = get_mod('CombatStats')

local Breeds = mod:original_require('scripts/settings/breed/breeds')
local BuffTemplates = mod:original_require('scripts/settings/buff/buff_templates')
local ArchetypeTalents = mod:original_require('scripts/settings/ability/archetype_talents/archetype_talents')
local Archetypes = mod:original_require('scripts/settings/archetype/archetypes')
local WeaponTraitTemplates = mod:original_require('scripts/settings/equipment/weapon_traits/weapon_trait_templates')
local MasterItems = mod:original_require('scripts/backend/master_items')
local Missions = mod:original_require('scripts/settings/mission/mission_templates')

local BUFF_SUFFIXES = {
    '_stat_buff',
    '_buff',
    '_stacks',
    '_stack',
    '_parent',
    '_child',
    '_duration',
    '_proc',
    '_stat',
    '_passive',
    '_regen',
    '_visual',
    '_effect',
}

local CombatStatsUtils = class('CombatStatsUtils')

function CombatStatsUtils:init()
    self._breed_cache = {}
    self._buff_cache = {}
    self._icon_cache = {}
    self._archetype_cache = {}
end

local function safe_localize(text)
    if not text or text == '' or text == 'n/a' then
        return nil
    end

    local success, localized = pcall(Localize, text)
    if not success then
        return nil
    end

    if
        localized
        and type(localized) == 'string'
        and localized ~= text
        and not localized:find('^loc_')
        and not localized:lower():find('unlocalized')
    then
        return localized
    end

    return nil
end

function CombatStatsUtils:get_archetype_display_name(archetype_name)
    if not archetype_name or archetype_name == 'unknown' then
        return mod:localize('unknown')
    end

    if self._archetype_cache[archetype_name] then
        return self._archetype_cache[archetype_name]
    end

    local result = archetype_name
    local archetype_data = Archetypes[archetype_name]
    if archetype_data and archetype_data.archetype_name then
        local localized = safe_localize(archetype_data.archetype_name)
        if localized then
            result = localized
        end
    end

    self._archetype_cache[archetype_name] = result
    return result
end

function CombatStatsUtils:get_mission_display_name(mission_name)
    if not mission_name or mission_name == 'unknown' then
        return mod:localize('unknown')
    end

    local mission_settings = Missions[mission_name]
    if mission_settings and mission_settings.mission_name then
        return safe_localize(mission_settings.mission_name) or mission_name
    end

    return mission_name
end

function CombatStatsUtils:get_breed_display_name(breed_name)
    if not breed_name or breed_name == 'unknown' then
        return mod:localize('unknown')
    end

    if self._breed_cache[breed_name] then
        return self._breed_cache[breed_name]
    end

    local result = breed_name
    local breed = Breeds[breed_name]
    if breed then
        if breed.display_name then
            local localized = safe_localize(breed.display_name)
            if localized then
                result = localized
                self._breed_cache[breed_name] = result
                return result
            end
        end

        if breed.boss_display_name then
            if type(breed.boss_display_name) == 'table' and #breed.boss_display_name > 0 then
                local localized = safe_localize(breed.boss_display_name[1])
                if localized then
                    result = localized
                    self._breed_cache[breed_name] = result
                    return result
                end
            elseif type(breed.boss_display_name) == 'string' then
                local localized = safe_localize(breed.boss_display_name)
                if localized then
                    result = localized
                    self._breed_cache[breed_name] = result
                    return result
                end
            end
        end
    end

    self._breed_cache[breed_name] = result
    return result
end

function CombatStatsUtils:get_buff_display_name(buff_name)
    if not buff_name or buff_name == 'unknown' then
        return mod:localize('unknown')
    end

    if self._buff_cache[buff_name] then
        return self._buff_cache[buff_name]
    end

    local result = buff_name
    local buff_template = BuffTemplates[buff_name]

    if not buff_template then
        self._buff_cache[buff_name] = result
        return result
    end

    -- Check if buff has display_title
    if buff_template.display_title then
        local localized = safe_localize(buff_template.display_title)
        if localized then
            result = localized
            self._buff_cache[buff_name] = result
            return result
        end
    end

    -- Try to find related talent
    local buff_related_talent = buff_template.related_talents and buff_template.related_talents[1]

    for player_archetype, archetype_talents in pairs(ArchetypeTalents) do
        for talent_name, definition in pairs(archetype_talents) do
            local talent_buff_passive = definition.passive and definition.passive.buff_template_name
            local talent_buff_coherency = definition.coherency and definition.coherency.buff_template_name

            -- Check if buff name matches template name (with suffix variations)
            local function matches_buff(template_name)
                if type(template_name) == 'string' then
                    if template_name == buff_name then
                        return true
                    end
                    for _, suffix in ipairs(BUFF_SUFFIXES) do
                        if (template_name .. suffix) == buff_name then
                            return true
                        end
                    end
                elseif type(template_name) == 'table' then
                    for _, name in ipairs(template_name) do
                        if matches_buff(name) then
                            return true
                        end
                    end
                end
                return false
            end

            if
                (talent_buff_passive and matches_buff(talent_buff_passive))
                or (talent_buff_coherency and matches_buff(talent_buff_coherency))
                or talent_name == buff_related_talent
            then
                if definition.display_name then
                    local localized = safe_localize(definition.display_name)
                    if localized then
                        result = localized
                        self._buff_cache[buff_name] = result
                        return result
                    end
                end
            end

            -- Check format_values for buff references
            if definition.format_values then
                for _, format_value in pairs(definition.format_values) do
                    if
                        type(format_value) == 'table'
                        and format_value.find_value
                        and format_value.find_value.buff_template_name == buff_name
                    then
                        if definition.display_name then
                            local localized = safe_localize(definition.display_name)
                            if localized then
                                result = localized
                                self._buff_cache[buff_name] = result
                                return result
                            end
                        end
                        break
                    end
                end
            end
        end
    end

    -- Try to find weapon trait
    for trait_name, trait_definition in pairs(WeaponTraitTemplates) do
        if trait_definition.format_values then
            for _, format_value in pairs(trait_definition.format_values) do
                if
                    type(format_value) == 'table'
                    and format_value.find_value
                    and format_value.find_value.buff_template_name == buff_name
                then
                    local master_items = MasterItems.get_cached()
                    if master_items then
                        for item_id, item_data in pairs(master_items) do
                            if item_data.trait == trait_name and item_data.display_name then
                                local localized = safe_localize(item_data.display_name)
                                if localized then
                                    result = localized
                                    self._buff_cache[buff_name] = result
                                    return result
                                end
                            end
                        end
                    end
                    break
                end
            end
        end
    end

    self._buff_cache[buff_name] = result
    return result
end

function CombatStatsUtils:get_buff_icon(buff_name)
    if not buff_name then
        return nil, nil
    end

    if self._icon_cache[buff_name] then
        local cached = self._icon_cache[buff_name]
        return cached.icon, cached.gradient_map
    end

    local template = BuffTemplates[buff_name]
    if not template then
        self._icon_cache[buff_name] = { icon = nil, gradient_map = nil }
        return nil, nil
    end

    local icon = template.hud_icon
    local gradient_map = template.hud_icon_gradient_map

    if not icon then
        icon = 'content/ui/textures/icons/talents/broker/stimm_tree/broker_stimm_combat_1'
    end

    self._icon_cache[buff_name] = { icon = icon, gradient_map = gradient_map }
    return icon, gradient_map
end

return CombatStatsUtils
