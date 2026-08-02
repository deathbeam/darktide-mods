local mod = get_mod('SimpleSequencer')

local ModeManager = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/ModeManager')
local SequenceEngine = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceEngine')

local MONITORED_ACTIONS = {
    action_one_pressed = true,
    action_one_hold = true,
    action_two_hold = true,
    weapon_extra_pressed = true,
    weapon_extra_hold = true,
    weapon_reload_hold = true,
    quick_wield = true,
    sprint = true,
}

mod:register_hud_element({
    class_name = 'HudElementSimpleSequencer',
    filename = 'SimpleSequencer/scripts/mods/SimpleSequencer/modules/HudElementSimpleSequencer',
    use_hud_scale = true,
    visibility_groups = {
        'alive',
    },
})

local initialized = false
local enabled = true

mod.mode_manager = ModeManager:new(mod)
mod.engine = SequenceEngine:new(mod, mod.mode_manager)

local function _ui_using_input()
    local ui_manager = Managers and Managers.ui

    return ui_manager and ui_manager.using_input and ui_manager:using_input() or false
end

local function _input_hook(func, self, action_name, ...)
    local value = func(self, action_name, ...)

    if not initialized or not enabled or _ui_using_input() then
        return value
    elseif not MONITORED_ACTIONS[action_name] then
        return value
    end

    return mod.engine:handle_input(action_name, value)
end

function mod.ready()
    return initialized and enabled
end

function mod.on_enabled()
    enabled = true
end

function mod.on_disabled()
    enabled = false
    mod.engine:reset('disabled')
end

function mod.on_all_mods_loaded()
    mod.mode_manager:sync_settings()
    mod.engine:invalidate()
    initialized = true
end

function mod.on_setting_changed(setting_name)
    if mod.mode_manager:on_setting_changed(setting_name) then
        return
    end

    if setting_name == 'reset_on_interrupt' then
        mod.engine:reset('setting_changed')
    end
end

function mod.on_game_state_changed()
    mod.engine:reset('game_state_changed')
    mod.engine:invalidate()
end

function mod.update()
    if not mod.ready() then
        return
    end

    mod.mode_manager:update()
    mod.engine:update()
end

function mod.select_mode_one()
    if not _ui_using_input() then
        mod.mode_manager:select_index(1)
    end
end

function mod.select_mode_two()
    if not _ui_using_input() then
        mod.mode_manager:select_index(2)
    end
end

function mod.select_mode_three()
    if not _ui_using_input() then
        mod.mode_manager:select_index(3)
    end
end

function mod.select_mode_four()
    if not _ui_using_input() then
        mod.mode_manager:select_index(4)
    end
end

function mod.select_mode_previous()
    if not _ui_using_input() then
        mod.mode_manager:previous()
    end
end

function mod.select_mode_next()
    if not _ui_using_input() then
        mod.mode_manager:next()
    end
end

function mod.select_mode_toggle()
    if not _ui_using_input() then
        mod.mode_manager:toggle()
    end
end

mod:hook(CLASS.InputService, '_get', _input_hook)

mod:hook_safe(CLASS.PlayerUnitWeaponExtension, 'on_slot_wielded', function(self)
    local player = Managers.player and Managers.player:local_player_safe(1)

    if player and player.player_unit == self._unit then
        mod.engine:reset('weapon_changed')
        mod.engine:invalidate()
    end
end)

mod:hook_safe(CLASS.PlayerCharacterStateStunned, 'on_enter', function(self, unit, dt, t, previous_state, params)
    local player = Managers.player and Managers.player:local_player_safe(1)

    if mod.ready() and player and player.player_unit == unit then
        mod.engine:reset('stunned')
    end
end)

mod:hook_safe(CLASS.ActionSweep, '_reset_sweep_component', function()
    if mod.ready() then
        mod.engine:set_sweep_state('before_damage_window')
    end
end)

mod:hook_safe(CLASS.ActionSweep, '_exit_damage_window', function()
    if mod.ready() then
        mod.engine:set_sweep_state('after_damage_window')
    end
end)
