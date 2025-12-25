local mod = get_mod('WeaponStats')
local UIWidget = require('scripts/managers/ui/ui_widget')
local WeaponTemplate = require('scripts/utilities/weapon/weapon_template')
local ArmorSettings = require('scripts/settings/damage/armor_settings')

-- Scroll state
local scroll_offset = 0

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

    local text = '{#color(255,200,100)}=== WEAPON DAMAGE ==={#reset()}\n'
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
        light = {},
        heavy = {},
        special = {},
    }

    -- Helper to check if attack already exists with same stats
    local function is_duplicate(list, profile)
        for _, existing in ipairs(list) do
            local e = existing.profile
            if
                e.damage_type == profile.damage_type
                and e.finesse_ability_damage_multiplier == profile.finesse_ability_damage_multiplier
                and (e.backstab_bonus or 0) == (profile.backstab_bonus or 0)
                and e.stagger_category == profile.stagger_category
            then
                -- Check cleave match
                local cleave_match = true
                if profile.cleave_distribution and e.cleave_distribution then
                    for k, v in pairs(profile.cleave_distribution) do
                        if type(v) == 'table' then
                            if
                                not e.cleave_distribution[k]
                                or e.cleave_distribution[k][1] ~= v[1]
                                or e.cleave_distribution[k][2] ~= v[2]
                            then
                                cleave_match = false
                                break
                            end
                        end
                    end
                end
                if cleave_match then
                    return true
                end
            end
        end
        return false
    end

    for action_name, action in pairs(weapon_template.actions) do
        if action.damage_profile and type(action.damage_profile) == 'table' then
            local profile = action.damage_profile

            -- Categorize attack
            local category = nil
            if string.match(action_name, 'special') then
                category = 'special'
            elseif profile.melee_attack_strength == 'heavy' or string.match(action_name, 'heavy') then
                category = 'heavy'
            elseif profile.melee_attack_strength == 'light' or string.match(action_name, 'light') then
                category = 'light'
            end

            if category and not is_duplicate(attacks[category], profile) then
                table.insert(attacks[category], { name = action_name, action = action, profile = profile })
            end
        end
    end

    -- Display attacks by category
    for _, category in ipairs({ 'light', 'heavy', 'special' }) do
        local category_attacks = attacks[category]
        if #category_attacks > 0 then
            text = text
                .. string.format('{#color(255,200,100)}=== %s ATTACKS ==={#reset()}\n\n', string.upper(category))

            for i, attack_data in ipairs(category_attacks) do
                local profile = attack_data.profile

                text = text .. string.format('{#color(100,200,255)}Attack %d{#reset()}\n', i)

                -- Show target data (damage, crit boost, armor pen PER TARGET)
                if profile.targets and type(profile.targets) == 'table' then
                    for target_idx, target in ipairs(profile.targets) do
                        if target_idx == 1 then
                            -- Only show first target in detail for clarity

                            -- Power distribution (actual damage values)
                            if target.power_distribution and type(target.power_distribution) == 'table' then
                                if target.power_distribution.attack then
                                    local atk = target.power_distribution.attack
                                    local dmg_min = resolve_lerp(atk[1] or 0)
                                    local dmg_max = resolve_lerp(atk[2] or 0)
                                    text = text
                                        .. string.format(
                                            '  {#color(255,200,100)}Damage: %.0f-%.0f{#reset()}\n',
                                            dmg_min,
                                            dmg_max
                                        )
                                end
                            end

                            -- Crit boost
                            if target.crit_boost then
                                local crit_val = resolve_lerp(target.crit_boost)
                                if crit_val > 0 then
                                    text = text
                                        .. string.format(
                                            '  Crit Damage: {#color(255,255,100)}+%.0f%%{#reset()}\n',
                                            crit_val * 100
                                        )
                                end
                            end

                            if target.armor_damage_modifier and type(target.armor_damage_modifier) == 'table' then
                                text = text .. '  {#color(255,150,150)}Armor Penetration:{#reset()}\n'

                                local armor_types_obj = ArmorSettings.types

                                -- Iterate through armor types
                                for armor_key, armor_type_id in pairs(armor_types_obj) do
                                    local attack_mod = target.armor_damage_modifier.attack
                                        and target.armor_damage_modifier.attack[armor_type_id]
                                    local crit_mod = profile.crit_mod
                                        and profile.crit_mod.attack
                                        and profile.crit_mod.attack[armor_type_id]

                                    if attack_mod then
                                        local armor_val = resolve_lerp(attack_mod)
                                        local crit_bonus = crit_mod and resolve_lerp(crit_mod) or 0
                                        local crit_val = armor_val + crit_bonus

                                        if armor_val > 0 or crit_val > 0 then
                                            local armor_display = armor_names[armor_key] or tostring(armor_key)
                                            local line = string.format('    %s: %.0f%%', armor_display, armor_val * 100)

                                            -- Show crit value if different from normal
                                            if math.abs(crit_bonus) > 0.01 then
                                                line = line
                                                    .. string.format(
                                                        ' {#color(255,255,100)}(crit: %.0f%%){#reset()}',
                                                        crit_val * 100
                                                    )
                                            end

                                            text = text .. line .. '\n'
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                -- Damage type
                if profile.damage_type then
                    text = text .. string.format('  Type: %s\n', tostring(profile.damage_type))
                end

                -- Weakspot multiplier
                if profile.finesse_ability_damage_multiplier and profile.finesse_ability_damage_multiplier ~= 1 then
                    text = text
                        .. string.format(
                            '  Weakspot: {#color(255,200,100)}%.1fx{#reset()}\n',
                            profile.finesse_ability_damage_multiplier
                        )
                end

                -- Backstab bonus
                if profile.backstab_bonus and profile.backstab_bonus > 0 then
                    text = text
                        .. string.format(
                            '  Backstab: {#color(255,200,100)}+%.0f%%{#reset()}\n',
                            profile.backstab_bonus * 100
                        )
                end

                -- Cleave
                if profile.cleave_distribution and type(profile.cleave_distribution) == 'table' then
                    for key, value in pairs(profile.cleave_distribution) do
                        if type(value) == 'table' and (value[1] ~= 0 or value[2] ~= 0) then
                            text = text .. string.format('  Cleave %s: %.1f-%.1f\n', key, value[1], value[2])
                        elseif type(value) == 'number' and value ~= 0 then
                            text = text .. string.format('  Cleave %s: %.1f\n', key, value)
                        end
                    end
                end

                -- Profile-level armor damage (fallback if no per-target modifier)
                -- This is rarely used but shown if targets don't have their own
                if not (profile.targets and profile.targets[1] and profile.targets[1].armor_damage_modifier) then
                    if profile.armor_damage_modifier and type(profile.armor_damage_modifier) == 'table' then
                        text = text .. '  {#color(255,150,150)}Armor Penetration (% of damage):{#reset()}\n'
                        for damage_category, modifiers in pairs(profile.armor_damage_modifier) do
                            if type(modifiers) == 'table' then
                                text = text .. string.format('    %s:\n', damage_category)
                                for armor_type, multiplier in pairs(modifiers) do
                                    if type(multiplier) == 'number' and multiplier ~= 0 then
                                        text = text
                                            .. string.format(
                                                '      %s: %.0f%%\n',
                                                tostring(armor_type),
                                                multiplier * 100
                                            )
                                    elseif
                                        type(multiplier) == 'table' and (multiplier[1] ~= 0 or multiplier[2] ~= 0)
                                    then
                                        text = text
                                            .. string.format(
                                                '      %s: %.0f-%.0f%%\n',
                                                tostring(armor_type),
                                                multiplier[1] * 100,
                                                multiplier[2] * 100
                                            )
                                    end
                                end
                            end
                        end
                    end
                end

                -- Critical strike armor modifiers (only show if no target-level armor mod shown above)

                -- Stagger
                if profile.stagger_category then
                    text = text .. string.format('  Stagger: %s\n', tostring(profile.stagger_category))
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
        size = { 500, 650 },
        position = { 1350, -100, 50 }, -- High z-index to be above buttons
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
                size = { 470, 620 },
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
                offset = { 0, -5, 1 },
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
