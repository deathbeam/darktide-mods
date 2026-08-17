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

local consumed_weapon_inputs = setmetatable({}, { __mode = 'k' })
mod.mode_manager = ModeManager:new(mod)
mod.input = Input:new()
mod.controller = SequenceController:new(mod.mode_manager)

local function _ui_using_input()
    local ui_manager = Managers and Managers.ui

    return ui_manager and ui_manager.using_input and ui_manager:using_input() or false
end

local function _local_player()
    local player_manager = Managers and Managers.player

    return player_manager and player_manager.local_player_safe and player_manager:local_player_safe(1)
end

local function _is_local_player_unit(unit)
    local player = _local_player()

    return unit and player and player.player_unit == unit or false
end

local function _capture_input_hook(func, self, action_name)
    local value = func(self, action_name)

    if self.type == 'Ingame' and mod.ready() and not _ui_using_input() then
        mod.input:observe(action_name, value, function(physical_action_name)
            return func(self, physical_action_name)
        end)
    end

    return value
end

local function _buffer_input_hook(func, self, input_cache, input_service, buffer_index)
    local result = func(self, input_cache, input_service, buffer_index)
    local player = _local_player()
    local unit = player and player.player_unit
    local action_input_extension = unit and ScriptUnit.has_extension(unit, 'action_input_system')
    local parser = action_input_extension
        and action_input_extension._action_input_parsers
        and action_input_extension._action_input_parsers.weapon_action
    local lookup = parser and parser._RAW_INPUTS_NETWORK_LOOKUP

    if self._player == player and lookup and mod.ready() and not _ui_using_input() then
        local action_lookup = self._action_lookup
        local frame_inputs = {}

        for index = 1, #lookup do
            local action_name = lookup[index]
            local cache_index = action_lookup[action_name]
            local values = cache_index and input_cache[cache_index]

            if values then
                frame_inputs[action_name] = values[buffer_index]
            end
        end

        local primary_release_handled = false
        if not mod.input.primary_held and frame_inputs.action_one_hold ~= nil then
            local event = mod.input:frame_event('action_one_hold', frame_inputs.action_one_hold, frame_inputs)
            frame_inputs.action_one_hold = mod.controller:handle_input(event)
            primary_release_handled = true
        end

        for index = 1, #lookup do
            local action_name = lookup[index]
            local value = frame_inputs[action_name]

            if value ~= nil and (action_name ~= 'action_one_hold' or not primary_release_handled) then
                local event = mod.input:frame_event(action_name, value, frame_inputs)
                frame_inputs[action_name] = mod.controller:handle_input(event)
            end
        end

        for action_name, value in pairs(frame_inputs) do
            local cache_index = action_lookup[action_name]
            input_cache[cache_index][buffer_index] = value
        end
    end

    mod.input:clear_events()

    return result
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

mod:hook(CLASS.InputService, '_get', _capture_input_hook)
mod:hook(CLASS.InputService, '_get_simulate', _capture_input_hook)
mod:hook(CLASS.HumanInputHandler, '_parse_input', _buffer_input_hook)
mod:hook(CLASS.PlayerUnitActionInputExtension, 'consume_next_input', function(func, self, id, t)
    local parser = self._action_input_parsers and self._action_input_parsers[id]
    local player = _local_player()

    if mod.ready() and id == 'weapon_action' and parser and parser._player == player then
        local action_input = self:peek_next_input(id)
        consumed_weapon_inputs[self] = { input = action_input, t = t }
    end

    return func(self, id, t)
end)

mod:hook_safe(CLASS.PlayerUnitWeaponExtension, 'on_slot_wielded', function(self)
    if _is_local_player_unit(self._unit) then
        mod.controller:on_slot_wielded()
        mod.input:reset()
    end
end)

mod:hook_safe(
    CLASS.ActionHandler,
    'start_action',
    function(self, id, _, action_name, _, action_settings, _used_input, t, _, _, automatic_input)
        if mod.ready() and id == 'weapon_action' and _is_local_player_unit(self._unit) then
            local input_extension = self._action_input_extension
            local consumed = consumed_weapon_inputs[input_extension]
            local parser_input = not automatic_input and consumed and consumed.t == t and consumed.input or nil
            consumed_weapon_inputs[input_extension] = nil
            mod.controller:on_action_started(action_name, t, automatic_input, action_settings, parser_input)
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
