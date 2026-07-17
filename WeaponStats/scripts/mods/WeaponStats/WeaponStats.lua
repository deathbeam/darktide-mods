local mod = get_mod('WeaponStats')

local SharedUtils = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/shared/shared_utils')
local _loc = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/WeaponStats_localization')
SharedUtils.apply_loc_settings(mod, _loc)

-- Register Weapon Stats View
mod:add_require_path('WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_view')
mod:register_view({
    view_name = 'weapon_stats_view',
    view_settings = {
        init_view_function = function()
            return true
        end,
        class = 'WeaponStatsView',
        disable_game_world = false,
        game_world_blur = 0,
        load_always = true,
        load_in_hub = true,
        path = 'WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_view',
        package = 'packages/ui/views/options_view/options_view',
        state_bound = false,
        enter_sound_events = {
            'wwise/events/ui/play_ui_enter_short',
        },
        exit_sound_events = {
            'wwise/events/ui/play_ui_back_short',
        },
        wwise_states = {
            options = 'ingame_menu',
        },
    },
    view_transitions = {},
    view_options = {
        close_all = false,
        close_previous = false,
        close_transition_time = nil,
        transition_time = nil,
    },
})

-- Add a button to the ESC menu that opens the view
local WEAPON_STATS_MENU_BUTTON = {
    text = 'loc_weapon_stats_menu_button',
    type = 'button',
    icon = 'content/ui/materials/icons/system/escape/settings',
    trigger_function = function()
        Managers.ui:open_view('weapon_stats_view')
    end,
}
mod:hook(CLASS.SystemView, '_setup_content_widgets', function(func, self, content, ...)
    local patched = content
    if content then
        patched = {}
        for state_key, list in pairs(content) do
            local cloned = table.clone(list)
            -- Insert before the first spacing_vertical (the divider above news/options/quit).
            local insert_at = #cloned + 1
            for i = 1, #cloned do
                if cloned[i].type == 'spacing_vertical' then
                    insert_at = i
                    break
                end
            end
            if mod:get('add_to_esc_menu') then
                table.insert(cloned, insert_at, WEAPON_STATS_MENU_BUTTON)
            end
            patched[state_key] = cloned
        end
    end
    return func(self, patched, ...)
end)

-- Add a button to the weapon options grid that opens the view
mod:hook(CLASS.ViewElementGrid, 'present_grid_layout', function(func, self, layout, ...)
    if self._element_view_id == 'inventory_weapons_view_weapon_options' and layout then
        local already_added = false
        for i = 1, #layout do
            if layout[i]._is_weapon_stats_button then
                already_added = true
                break
            end
        end
        if not already_added then
            layout[#layout + 1] = {
                _is_weapon_stats_button = true,
                widget_type = 'button',
                display_icon = '',
                display_name = mod:localize('mod_name'),
                callback = function()
                    local parent = self._parent
                    local previewed_item = parent and parent._previewed_item
                    local weapon_template_name = previewed_item and previewed_item.weapon_template
                    Managers.ui:open_view('weapon_stats_view', nil, nil, nil, nil, {
                        weapon_template_name = weapon_template_name,
                    })
                end,
            }
            -- Grow the grid to fit the extra button.
            local menu_settings = self._menu_settings
            if menu_settings then
                local new_height = #layout * 86
                menu_settings.grid_size[2] = new_height
                menu_settings.mask_size[2] = new_height
            end
        end
    end
    return func(self, layout, ...)
end)
