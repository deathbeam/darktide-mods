local mod = get_mod('WeaponStats')

-- Register Weapon Stats View
mod:add_require_path('WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_view')
mod:register_view({
    view_name = 'weapon_stats_view',
    view_settings = {
        init_view_function = function(ingame_ui_context)
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
