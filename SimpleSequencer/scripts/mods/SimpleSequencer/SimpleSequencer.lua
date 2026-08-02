local mod = get_mod('SimpleSequencer')

local ModeManager = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/ModeManager')
local SequenceEngine = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceEngine')

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
    end

    return mod.engine:handle_input(action_name, value)
end

local function _refresh_mode_display_name_input(view)
    if view.view_name ~= 'dmf_options_view' or not view._settings_category_widgets then
        return
    end

    for _, rows in pairs(view._settings_category_widgets) do
        for _, row in ipairs(rows) do
            local widget = row.widget
            local entry = widget and widget.content and widget.content.entry

            if entry and entry.setting_id == 'mode_display_name' and not widget.content.is_writing then
                local value = mod:get('mode_display_name')

                if type(value) == 'table' then
                    value = value[1] or ''
                end

                widget.content.input_text = value or ''
            end
        end
    end
end

mod:hook_safe(CLASS.BaseView, 'update', _refresh_mode_display_name_input)

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
