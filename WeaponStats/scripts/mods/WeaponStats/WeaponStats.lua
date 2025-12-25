local mod = get_mod('WeaponStats')
local UIWidget = require('scripts/managers/ui/ui_widget')
local WeaponTemplate = require('scripts/utilities/weapon/weapon_template')
local ArmorSettings = require('scripts/settings/damage/armor_settings')
local HitScanTemplates = require('scripts/settings/projectile/hit_scan_templates')
local WeaponHandlingTemplates =
    require('scripts/settings/equipment/weapon_handling_templates/weapon_handling_templates')

-- Scroll state
local scroll_offset = 0

-- Color constants
local COLORS = {
    HEADER = '255,200,100', -- Orange/gold for headers
    ATTACK = '100,200,255', -- Blue for attack numbers
    LABEL = '180,180,180', -- Gray for labels
    ACTION = '150,150,150', -- Lighter gray for action names
    DAMAGE = '255,200,100', -- Orange for damage values
    ARMOR = '255,150,150', -- Red for armor damage
    CRIT = '255,255,100', -- Yellow for crit
    IMPACT = '200,200,255', -- Light blue for impact
    IMPACT_CRIT = '150,200,255', -- Lighter blue for impact crit
    WEAKSPOT = '255,200,100', -- Orange for weakspot/backstab
    TIMING = '150,255,150', -- Green for timing info
}

-- Color utility functions
local function colored(color, text)
    return string.format('{#color(%s)}%s{#reset()}', color, text)
end

local function label(text)
    return colored(COLORS.LABEL, text)
end

local function value(color, text)
    return colored(color, text)
end

-- Armor type display names
local armor_names = {
    unarmored = 'Unarmored',
    armored = 'Flak',
    resistant = 'Unyielding',
    player = 'Player',
    berserker = 'Maniac',
    super_armor = 'Carapace',
    disgustingly_resilient = 'Infested',
    void_shield = 'Void Shield',
}

-- Build stats text from weapon
local function build_stats_text(item)
    if not item then
        return 'No weapon selected'
    end

    local weapon_template = WeaponTemplate.weapon_template_from_item(item)
    if not weapon_template or not weapon_template.actions then
        return 'No weapon template found'
    end

    local text = ''
    local item_lerp = 0.8 -- default max range

    -- Helper to resolve lerp values using item's actual lerp
    local function resolve_lerp(value)
        if type(value) ~= 'table' then
            return value
        end
        -- Interpolate: min + (max - min) * lerp
        return value[1] + (value[2] - value[1]) * item_lerp
    end

    -- Organize attacks by type and deduplicate
    local attacks = {
        ranged = {},
        light = {},
        heavy = {},
        special = {},
    }

    -- Helper to check if attack already exists with same stats
    local function is_duplicate(list, profile, action_name)
        for _, existing in ipairs(list) do
            local e = existing.profile
            local is_same = true

            -- Compare damage type
            if e.damage_type ~= profile.damage_type then
                is_same = false
            end

            -- Compare damage values (targets)
            if is_same then
                local e_target = e.targets and e.targets[1] or e
                local p_target = profile.targets and profile.targets[1] or profile

                if e_target.power_distribution and p_target.power_distribution then
                    local e_dmg = e_target.power_distribution.attack
                    local p_dmg = p_target.power_distribution.attack
                    if e_dmg and p_dmg then
                        local e_min = resolve_lerp(e_dmg[1] or 0)
                        local e_max = resolve_lerp(e_dmg[2] or 0)
                        local p_min = resolve_lerp(p_dmg[1] or 0)
                        local p_max = resolve_lerp(p_dmg[2] or 0)
                        if e_min ~= p_min or e_max ~= p_max then
                            is_same = false
                        end
                    end
                end
            end

            -- Compare armor damage modifiers
            if is_same then
                local e_target = e.targets and e.targets[1] or e
                local p_target = profile.targets and profile.targets[1] or profile
                local e_armor = e_target.armor_damage_modifier or e.armor_damage_modifier
                local p_armor = p_target.armor_damage_modifier or profile.armor_damage_modifier

                if e_armor and p_armor and e_armor.attack and p_armor.attack then
                    local armor_types_obj = ArmorSettings.types
                    for armor_key, armor_type_id in pairs(armor_types_obj) do
                        local e_mod = e_armor.attack[armor_type_id] or e_armor.attack[armor_key]
                        local p_mod = p_armor.attack[armor_type_id] or p_armor.attack[armor_key]
                        local e_val = e_mod and resolve_lerp(e_mod) or 0
                        local p_val = p_mod and resolve_lerp(p_mod) or 0
                        if math.abs(e_val - p_val) > 0.01 then
                            is_same = false
                            break
                        end
                    end
                elseif (e_armor ~= nil) ~= (p_armor ~= nil) then
                    is_same = false
                end
            end

            -- Compare other properties
            if
                is_same
                and (e.finesse_ability_damage_multiplier or 1) ~= (profile.finesse_ability_damage_multiplier or 1)
            then
                is_same = false
            end
            if is_same and (e.backstab_bonus or 0) ~= (profile.backstab_bonus or 0) then
                is_same = false
            end
            if is_same and e.stagger_category ~= profile.stagger_category then
                is_same = false
            end

            -- Compare cleave
            if is_same and profile.cleave_distribution and e.cleave_distribution then
                for k, v in pairs(profile.cleave_distribution) do
                    if type(v) == 'table' then
                        if
                            not e.cleave_distribution[k]
                            or e.cleave_distribution[k][1] ~= v[1]
                            or e.cleave_distribution[k][2] ~= v[2]
                        then
                            is_same = false
                            break
                        end
                    elseif type(v) == 'number' then
                        if e.cleave_distribution[k] ~= v then
                            is_same = false
                            break
                        end
                    end
                end
            end

            if is_same then
                -- Add this action name to the existing entry
                table.insert(existing.names, action_name)
                return true
            end
        end
        return false
    end

    for action_name, action in pairs(weapon_template.actions) do
        local profile = nil

        -- Handle melee weapons (damage_profile directly in action)
        if action.damage_profile and type(action.damage_profile) == 'table' then
            profile = action.damage_profile
        -- Handle ranged weapons (damage_profile in hit_scan_template)
        elseif action.fire_configuration and action.fire_configuration.hit_scan_template then
            local hit_scan_template = action.fire_configuration.hit_scan_template
            -- hit_scan_template can be a table or a reference to HitScanTemplates
            if type(hit_scan_template) == 'table' then
                if hit_scan_template.damage and hit_scan_template.damage.impact then
                    profile = hit_scan_template.damage.impact.damage_profile
                end
            elseif type(hit_scan_template) == 'string' then
                local template = HitScanTemplates[hit_scan_template]
                if template and template.damage and template.damage.impact then
                    profile = template.damage.impact.damage_profile
                end
            end
        end

        if profile then
            -- Categorize attack
            local category = nil
            if string.match(action_name, 'special') then
                category = 'special'
            elseif string.match(action_name, 'shoot') or string.match(action_name, 'zoom') then
                category = 'ranged'
            elseif profile.melee_attack_strength == 'heavy' or string.match(action_name, 'heavy') then
                category = 'heavy'
            elseif profile.melee_attack_strength == 'light' or string.match(action_name, 'light') then
                category = 'light'
            end

            if category and not is_duplicate(attacks[category], profile, action_name) then
                table.insert(attacks[category], { names = { action_name }, action = action, profile = profile })
            end
        end
    end

    -- Display attacks by category
    for _, category in ipairs({ 'ranged', 'light', 'heavy', 'special' }) do
        local category_attacks = attacks[category]
        if #category_attacks > 0 then
            text = text .. colored(COLORS.HEADER, string.upper(category) .. ' ATTACKS') .. '\n\n'

            for i, attack_data in ipairs(category_attacks) do
                local profile = attack_data.profile
                local action = attack_data.action

                text = text .. colored(COLORS.ATTACK, 'Attack ' .. i) .. '\n'

                -- Sort and list all action names for this attack
                table.sort(attack_data.names)
                for _, name in ipairs(attack_data.names) do
                    text = text .. '  ' .. colored(COLORS.ACTION, name) .. '\n'
                end
                text = text .. '\n'

                local target = profile.targets and profile.targets[1]
                if not target then
                    target = profile
                end

                -- Damage type
                if profile.damage_type then
                    text = text .. '  ' .. label('Type:') .. ' ' .. tostring(profile.damage_type) .. '\n'
                end

                -- Timing information - calculate effective attack speed
                local attack_speed = nil
                local time_scale = 1

                -- Get time_scale from weapon_handling_template
                if action.weapon_handling_template then
                    local handling_template = WeaponHandlingTemplates[action.weapon_handling_template]
                    if handling_template and handling_template.time_scale then
                        local ts = handling_template.time_scale
                        -- Handle lerp values
                        if type(ts) == 'table' then
                            time_scale = resolve_lerp(ts)
                        else
                            time_scale = ts
                        end
                    end
                end

                -- For ranged weapons, check auto_fire_time
                if action.weapon_handling_template then
                    local handling_template = WeaponHandlingTemplates[action.weapon_handling_template]
                    if
                        handling_template
                        and handling_template.fire_rate
                        and handling_template.fire_rate.auto_fire_time
                    then
                        local auto_fire = handling_template.fire_rate.auto_fire_time
                        attack_speed = type(auto_fire) == 'table' and resolve_lerp(auto_fire) or auto_fire
                    end
                end

                -- For melee weapons or if no auto_fire_time, check chain_time to self
                if not attack_speed and action.allowed_chain_actions then
                    for chain_action_name, chain_data in pairs(action.allowed_chain_actions) do
                        -- Check if this chains back to the same action
                        if chain_data.action_name == attack_data.names[1] and chain_data.chain_time then
                            local chain_time = chain_data.chain_time
                            if chain_time > 0 and chain_time < 1000 then
                                attack_speed = chain_time / time_scale
                            end
                            break
                        end
                    end
                end

                -- Fallback to total_time
                if not attack_speed and action.total_time and action.total_time < 1000 then
                    attack_speed = action.total_time / time_scale
                end

                -- Display attack speed
                if attack_speed then
                    text = text
                        .. '  '
                        .. label('Attack Speed:')
                        .. ' '
                        .. value(COLORS.TIMING, string.format('%.2fs', attack_speed))
                        .. ' '
                        .. colored(COLORS.ACTION, string.format('(%.1f/s)', 1 / attack_speed))
                        .. '\n'
                end

                -- Power distribution (actual damage values)
                if target.power_distribution and type(target.power_distribution) == 'table' then
                    if target.power_distribution.attack then
                        local atk = target.power_distribution.attack
                        local dmg = resolve_lerp(atk)
                        text = text
                            .. '  '
                            .. label('Damage:')
                            .. ' '
                            .. value(COLORS.DAMAGE, string.format('%.0f', dmg))
                            .. '\n'
                    end

                    -- Impact damage (stagger)
                    if target.power_distribution.impact then
                        local imp = target.power_distribution.impact
                        local impact_dmg = resolve_lerp(imp)
                        text = text
                            .. '  '
                            .. label('Impact:')
                            .. ' '
                            .. value(COLORS.IMPACT, string.format('%.0f', impact_dmg))
                            .. '\n'
                    end
                end

                -- Armor damage
                local armor_mod = target.armor_damage_modifier or profile.armor_damage_modifier
                if armor_mod and type(armor_mod) == 'table' then
                    text = text .. '  ' .. label('Armor Damage:') .. '\n'

                    local armor_types_obj = ArmorSettings.types

                    -- Iterate through armor types
                    for armor_key, armor_type_id in pairs(armor_types_obj) do
                        local attack_mod = armor_mod.attack
                            and (armor_mod.attack[armor_type_id] or armor_mod.attack[armor_key])
                        if not attack_mod then
                            attack_mod = 1
                        end
                        local crit_mod = profile.crit_mod
                            and profile.crit_mod.attack
                            and (profile.crit_mod.attack[armor_type_id] or profile.crit_mod.attack[armor_key])
                        local impact_mod = armor_mod.impact
                            and (armor_mod.impact[armor_type_id] or armor_mod.impact[armor_key])
                        local impact_crit_mod = profile.crit_mod
                            and profile.crit_mod.impact
                            and (profile.crit_mod.impact[armor_type_id] or profile.crit_mod.impact[armor_key])

                        if attack_mod then
                            local armor_val = resolve_lerp(attack_mod)
                            local crit_bonus = crit_mod and resolve_lerp(crit_mod) or 0
                            local crit_val = armor_val + crit_bonus
                            local armor_display = armor_names[armor_key] or tostring(armor_key)
                            local line = string.format('    %s: ', armor_display)
                                .. value(COLORS.ARMOR, string.format('%.0f%%', armor_val * 100))

                            -- Show crit value if different from normal
                            if math.abs(crit_bonus) > 0.01 then
                                line = line .. ' ' .. value(COLORS.CRIT, string.format('C: %.0f%%', crit_val * 100))
                            end

                            -- Show impact value if exists and different
                            if impact_mod then
                                local impact_val = resolve_lerp(impact_mod)
                                local impact_crit_bonus = impact_crit_mod and resolve_lerp(impact_crit_mod) or 0
                                local impact_crit_val = impact_val + impact_crit_bonus

                                if math.abs(impact_val - armor_val) > 0.01 then
                                    line = line
                                        .. ' '
                                        .. value(COLORS.IMPACT, string.format('I: %.0f%%', impact_val * 100))

                                    if math.abs(impact_crit_bonus) > 0.01 then
                                        line = line
                                            .. ' '
                                            .. value(
                                                COLORS.IMPACT_CRIT,
                                                string.format('IC: %.0f%%', impact_crit_val * 100)
                                            )
                                    end
                                end
                            end

                            text = text .. line .. '\n'
                        end
                    end
                end

                -- Crit boost
                if target.crit_boost then
                    local crit_val = resolve_lerp(target.crit_boost)
                    if crit_val > 0 then
                        text = text
                            .. '  '
                            .. label('Crit Damage:')
                            .. ' '
                            .. value(COLORS.CRIT, string.format('+%.0f%%', crit_val * 100))
                            .. '\n'
                    end
                end

                -- Weakspot multiplier
                if profile.finesse_ability_damage_multiplier and profile.finesse_ability_damage_multiplier ~= 1 then
                    text = text
                        .. '  '
                        .. label('Weakspot:')
                        .. ' '
                        .. value(COLORS.WEAKSPOT, string.format('%.1fx', profile.finesse_ability_damage_multiplier))
                        .. '\n'
                end

                -- Backstab bonus
                if profile.backstab_bonus and profile.backstab_bonus > 0 then
                    text = text
                        .. '  '
                        .. label('Backstab:')
                        .. ' '
                        .. value(COLORS.WEAKSPOT, string.format('+%.0f%%', profile.backstab_bonus * 100))
                        .. '\n'
                end

                -- Cleave
                if profile.cleave_distribution and type(profile.cleave_distribution) == 'table' then
                    for key, value_data in pairs(profile.cleave_distribution) do
                        if type(value_data) == 'table' and (value_data[1] ~= 0 or value_data[2] ~= 0) then
                            text = text
                                .. string.format(
                                    '  %s %.1f-%.1f\n',
                                    label('Cleave ' .. key .. ':'),
                                    value_data[1],
                                    value_data[2]
                                )
                        elseif type(value_data) == 'number' and value_data ~= 0 then
                            text = text .. string.format('  %s %.1f\n', label('Cleave ' .. key .. ':'), value_data)
                        end
                    end
                end

                -- Stagger
                if profile.stagger_category then
                    text = text .. '  ' .. label('Stagger:') .. ' ' .. tostring(profile.stagger_category) .. '\n'
                end

                text = text .. '\n'
            end
        end
    end

    return text
end

-- Hook the inventory weapons view
mod:hook_require('scripts/ui/views/inventory_weapons_view/inventory_weapons_view_definitions', function(defs)
    defs.scenegraph_definition.weapon_damage_stats = {
        parent = 'canvas',
        vertical_alignment = 'bottom',
        horizontal_alignment = 'left',
        size = { 370, 650 },
        position = { 1350, -100, 50 },
    }

    -- Background + scrollable text with hotspot for input
    defs.widget_definitions.weapon_damage_stats = UIWidget.create_definition({
        {
            pass_type = 'hotspot',
            content_id = 'hotspot',
        },
        {
            pass_type = 'texture',
            value = 'content/ui/materials/backgrounds/terminal_basic',
            style = {
                color = Color.terminal_background(200, true),
            },
        },
        {
            pass_type = 'text',
            value_id = 'stats_text',
            value = 'Select a weapon to view damage profiles',
            style_id = 'stats_text',
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 16,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                text_color = Color.terminal_text_body(255, true),
                offset = { 15, 15, 1 },
                size = { 340, 590 },
            },
        },
        {
            pass_type = 'text',
            value = '[Hover and scroll to view more]',
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 14,
                text_vertical_alignment = 'bottom',
                text_horizontal_alignment = 'center',
                text_color = Color.terminal_text_header_selected(150, true),
                offset = { 0, -5, 2 },
            },
        },
    }, 'weapon_damage_stats')

    return defs
end)

-- Update stats when weapon is selected
mod:hook_safe(CLASS.InventoryWeaponsView, '_preview_item', function(self, item)
    local widget = self._widgets_by_name.weapon_damage_stats
    if widget then
        scroll_offset = 0 -- Reset scroll when changing weapons
        local stats_text = build_stats_text(item)
        -- mod:debug(stats_text:gsub('%%', ''))
        widget.content.stats_text = stats_text
    end
end)

-- Make widget always visible
mod:hook_safe(CLASS.InventoryWeaponsView, 'on_enter', function(self)
    local widget = self._widgets_by_name.weapon_damage_stats
    if widget then
        widget.visible = true
        scroll_offset = 0
    end
end)

-- Handle scroll input with mouse wheel when hovering
mod:hook(CLASS.InventoryWeaponsView, 'update', function(func, self, dt, t, input_service)
    func(self, dt, t, input_service)

    local widget = self._widgets_by_name.weapon_damage_stats
    if widget and widget.visible and widget.content and widget.content.hotspot then
        -- Check if hovering over widget
        if widget.content.hotspot.is_hover then
            -- Get scroll input
            local scroll_axis = input_service:get('scroll_axis')
            if scroll_axis and scroll_axis[2] and scroll_axis[2] ~= 0 then
                scroll_offset = scroll_offset - (scroll_axis[2] * 50)
                scroll_offset = math.max(0, math.min(scroll_offset, 5000))

                -- Update text offset
                if widget.style and widget.style.stats_text then
                    widget.style.stats_text.offset[2] = 15 - scroll_offset
                    widget.dirty = true
                end
            end
        end
    end
end)
