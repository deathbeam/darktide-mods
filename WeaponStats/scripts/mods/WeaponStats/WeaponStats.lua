local mod = get_mod('WeaponStats')

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
            table.insert(cloned, insert_at, WEAPON_STATS_MENU_BUTTON)
            patched[state_key] = cloned
        end
    end
    return func(self, patched, ...)
end)

function mod.on_all_mods_loaded()
    local function load_package(package_name)
        if not Managers.package:has_loaded(package_name) then
            Managers.package:load(package_name, 'WeaponStats')
        end
    end

    load_package('packages/ui/views/inventory_view/inventory_view')
    load_package('packages/ui/views/inventory_weapons_view/inventory_weapons_view')
    load_package('packages/ui/hud/player_weapon/player_weapon')
end
