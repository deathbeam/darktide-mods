local mod = get_mod('SimpleSequencer')

local ModeManager = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/ModeManager')
local SequenceController = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceController')
local Input = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/Input')

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
mod.input = Input:new()
mod.controller = SequenceController:new(mod.mode_manager)

local function _ui_using_input()
    local ui_manager = Managers and Managers.ui

    return ui_manager and ui_manager.using_input and ui_manager:using_input() or false
end

local function _is_local_player_unit(unit)
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager.local_player_safe and player_manager:local_player_safe(1)

    return unit and player and player.player_unit == unit or false
end

local function _input_hook(func, self, action_name)
    local value = func(self, action_name)

    if self.type ~= 'Ingame' or not mod.ready() or _ui_using_input() then
        return value
    end

    local input = mod.input:observe(action_name, value, function(physical_action_name)
        return func(self, physical_action_name)
    end)

    return mod.controller:handle_input(input)
end

local function _reset_for_disruptive_state(_, unit)
    if mod.ready() and _is_local_player_unit(unit) then
        mod.controller:reset()
        mod.input:reset()
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
    mod.controller:reset()
    mod.input:reset()
end

function mod.on_all_mods_loaded()
    mod.mode_manager:sync_settings()
    mod.controller:invalidate()
    initialized = true
end

function mod.on_setting_changed(setting_name)
    mod.mode_manager:on_setting_changed(setting_name)
end

function mod.on_game_state_changed()
    mod.controller:reset()
    mod.input:reset()
    mod.controller:invalidate()
end

function mod.update()
    if not mod.ready() then
        return
    end

    -- Finish action transitions before a pending mode resets the controller.
    mod.controller:update()
    mod.mode_manager:update()
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
        mod.controller:on_slot_wielded()
        mod.input:reset()
    end
end)

mod:hook_safe(
    CLASS.ActionHandler,
    'start_action',
    function(self, id, _, action_name, _, action_settings, _, t, _, _, automatic_input)
        if mod.ready() and id == 'weapon_action' and _is_local_player_unit(self._unit) then
            mod.controller:on_action_started(action_name, t, automatic_input, action_settings)
        end
    end
)

mod:hook_safe(CLASS.ActionSweep, '_exit_damage_window', function(self)
    if mod.ready() and _is_local_player_unit(self._player_unit) then
        mod.controller:on_damage_window_exited(self._action_settings)
    end
end)

for _, state_class in pairs(RESET_STATE_CLASSES) do
    if state_class then
        mod:hook_safe(state_class, 'on_enter', _reset_for_disruptive_state)
    end
end
