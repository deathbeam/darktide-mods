local mod = get_mod('EnemyStats')

local _game_loc = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/EnemyStats_localization').game_loc or {}

local _orig_localize = mod.localize
function mod:localize(text_id, ...)
    local loc_id = _game_loc[text_id]
    if loc_id then
        local ok, s = pcall(Localize, loc_id)
        if ok and s and s ~= '' and not s:find('^<') then
            return s
        end
    end
    return _orig_localize(self, text_id, ...)
end

-- Register Enemy Stats View
mod:add_require_path('EnemyStats/scripts/mods/EnemyStats/enemy_stats_view/enemy_stats_view')
mod:register_view({
    view_name = 'enemy_stats_view',
    view_settings = {
        init_view_function = function()
            return true
        end,
        class = 'EnemyStatsView',
        disable_game_world = false,
        game_world_blur = 0,
        load_always = true,
        load_in_hub = true,
        path = 'EnemyStats/scripts/mods/EnemyStats/enemy_stats_view/enemy_stats_view',
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
local ENEMY_STATS_MENU_BUTTON = {
    text = 'loc_enemy_stats_menu_button',
    type = 'button',
    icon = 'content/ui/materials/icons/system/escape/settings',
    trigger_function = function()
        Managers.ui:open_view('enemy_stats_view')
    end,
}
mod:hook(CLASS.SystemView, '_setup_content_widgets', function(func, self, content, ...)
    local patched = content
    if content then
        patched = {}
        for state_key, list in pairs(content) do
            local cloned = table.clone(list)
            -- Insert before the first spacing_vertical divider.
            local insert_at = #cloned + 1
            for i = 1, #cloned do
                if cloned[i].type == 'spacing_vertical' then
                    insert_at = i
                    break
                end
            end
            table.insert(cloned, insert_at, ENEMY_STATS_MENU_BUTTON)
            patched[state_key] = cloned
        end
    end
    return func(self, patched, ...)
end)
