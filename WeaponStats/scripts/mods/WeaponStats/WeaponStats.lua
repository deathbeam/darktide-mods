local mod = get_mod('WeaponStats')

local SharedUtils = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/shared/shared_utils')
local _loc = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/WeaponStats_localization')
SharedUtils.apply_loc_settings(mod, _loc)

-- Register Weapon Stats View (and its ESC-menu button)
SharedUtils.register_stats_view(
    mod,
    'weapon_stats_view',
    'WeaponStatsView',
    'WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_view',
    'loc_weapon_stats_menu_button'
)

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
