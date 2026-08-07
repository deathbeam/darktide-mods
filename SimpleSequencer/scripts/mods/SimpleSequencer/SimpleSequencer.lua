local mod = get_mod('SimpleSequencer')

local ModeManager = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/ModeManager')
local SequenceEngine = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceEngine')

local RESET_STATE_CLASSES = {
    CLASS.PlayerCharacterStateStunned,
    CLASS.PlayerCharacterStateKnockedDown,
    CLASS.PlayerCharacterStateNetted,
    CLASS.PlayerCharacterStatePounced,
    CLASS.PlayerCharacterStateGrabbed,
    CLASS.PlayerCharacterStateHogtied,
    CLASS.PlayerCharacterStateDead,
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

local function _is_local_player_unit(unit)
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager:local_player_safe(1)

    return player and player.player_unit == unit or false
end

local function _input_hook(func, self, action_name, ...)
    local value = func(self, action_name, ...)

    if self.type ~= 'Ingame' or not initialized or not enabled or _ui_using_input() then
        return value
    end

    return mod.engine:handle_input(action_name, value)
end

local function _reset_for_disruptive_state(_, unit)
    if mod.ready() and _is_local_player_unit(unit) then
        mod.engine:reset()
    end
end

function mod.ready()
    return initialized and enabled
end

function mod.on_enabled()
    enabled = true
end

function mod.on_disabled()
    enabled = false
    mod.engine:reset()
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
        mod.engine:reset()
    end
end

function mod.on_game_state_changed()
    mod.engine:reset()
    mod.engine:invalidate()
end

function mod.update()
    if not mod.ready() then
        return
    end

    mod.mode_manager:update()
    mod.engine:update()
end

local function _select_mode(index)
    if not _ui_using_input() then
        mod.mode_manager:select_index(index)
    end
end

function mod.select_mode_1()
    _select_mode(1)
end

function mod.select_mode_2()
    _select_mode(2)
end

function mod.select_mode_3()
    _select_mode(3)
end

function mod.select_mode_4()
    _select_mode(4)
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
    if _is_local_player_unit(self._unit) then
        mod.engine:on_slot_wielded()
    end
end)

for _, state_class in pairs(RESET_STATE_CLASSES) do
    if state_class then
        mod:hook_safe(state_class, 'on_enter', _reset_for_disruptive_state)
    end
end

local function _set_sweep_state(self, state)
    if mod.ready() and _is_local_player_unit(self._player_unit) then
        mod.engine:set_sweep_state(state)
    end
end

mod:hook_safe(CLASS.ActionSweep, '_reset_sweep_component', function(self)
    _set_sweep_state(self, 'before_damage_window')
end)

mod:hook_safe(CLASS.ActionSweep, '_exit_damage_window', function(self)
    _set_sweep_state(self, 'after_damage_window')
end)
