local mod = get_mod('CharacterStats')

local SharedUtils = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/shared/shared_utils')
local _loc = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/CharacterStats_localization')
SharedUtils.apply_loc_settings(mod, _loc)

-- Register Character Stats View (and its ESC-menu button)
SharedUtils.register_stats_view(
    mod,
    'character_stats_view',
    'CharacterStatsView',
    'CharacterStats/scripts/mods/CharacterStats/character_stats_view/character_stats_view',
    'loc_character_stats_menu_button'
)

-- Refresh the open view's detail panel when an assume/breakdown toggle flips so the
-- folded stat buffs recompute live. No-op when the view isn't active.
local REFRESH_SETTINGS = {
    assume_proc_stacks = true,
    coherency_allies = true,
    havoc_rank = true,
}

mod.on_setting_changed = function(id)
    if not REFRESH_SETTINGS[id] then
        return
    end
    local ui_manager = Managers.ui
    if not ui_manager or not ui_manager:view_active('character_stats_view') then
        return
    end
    local view = ui_manager:view_instance('character_stats_view')
    if view and view._detail_entry then
        view:_present_detail(view._detail_entry)
    end
end
