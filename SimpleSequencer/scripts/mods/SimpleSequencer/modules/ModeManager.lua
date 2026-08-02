local mod = get_mod('SimpleSequencer')
local Profiles = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceProfiles')

local ModeManager = class('SimpleSequencerModeManager')

local MODES = { 'mode_1', 'mode_2', 'mode_3', 'mode_4' }
local PROFILE_DATA_KEY = 'profile_data'
local SELECTED_WEAPONS_KEY = 'selected_weapons'

local function _mode_index(mode)
    return tonumber(string.match(mode or '', '%d+')) or 1
end

local function _kind_setting(setting_name)
    setting_name = setting_name or ''

    if string.sub(setting_name, 1, 6) == 'melee_' then
        return 'MELEE', string.sub(setting_name, 7)
    elseif string.sub(setting_name, 1, 7) == 'ranged_' then
        return 'RANGED', string.sub(setting_name, 8)
    end

    return nil, nil
end

function ModeManager:init(mod_instance)
    self.mod = mod_instance
    self.active_mode = 'mode_1'
    self.previous_mode = 'mode_2'
    self.pending_mode = nil
    self.editing_mode = mod_instance:get('editing_mode') or 'mode_1'
    self.revision = 0
    self.data = Profiles.ensure(mod_instance:get(PROFILE_DATA_KEY))
    self.selected_weapons = mod_instance:get(SELECTED_WEAPONS_KEY) or {}

    if not self.data[self.editing_mode] then
        self.editing_mode = 'mode_1'
    end

    for _, mode in ipairs(MODES) do
        self.selected_weapons[mode] = self.selected_weapons[mode] or {}
        self.selected_weapons[mode].MELEE = self.selected_weapons[mode].MELEE or 'global_melee'
        self.selected_weapons[mode].RANGED = self.selected_weapons[mode].RANGED or 'global_ranged'
    end

    mod_instance:set(PROFILE_DATA_KEY, self.data, false)
    mod_instance:set(SELECTED_WEAPONS_KEY, self.selected_weapons, false)
    mod_instance:set('editing_mode', self.editing_mode, false)
end

function ModeManager:active()
    return self.active_mode
end

function ModeManager:_activate(mode)
    local previous_mode = self.active_mode

    self.active_mode = mode
    self.previous_mode = previous_mode
    self.pending_mode = nil
    self.revision = self.revision + 1

    if self.mod.engine then
        self.mod.engine:reset('mode_changed')
    end
end

function ModeManager:select(mode)
    if not self.data[mode] then
        return false
    end

    if self.active_mode == mode then
        local changed = self.pending_mode ~= nil
        self.pending_mode = nil

        return changed
    end

    local engine = self.mod.engine

    if engine and engine:is_in_action() and not engine:is_safe_to_switch_mode() then
        self.pending_mode = mode
    else
        self:_activate(mode)
    end

    return true
end

function ModeManager:select_index(index)
    index = math.max(1, math.min(#MODES, tonumber(index) or 1))

    return self:select(MODES[index])
end

function ModeManager:next()
    return self:select_index(_mode_index(self.active_mode) % #MODES + 1)
end

function ModeManager:previous()
    return self:select_index((_mode_index(self.active_mode) - 2) % #MODES + 1)
end

function ModeManager:toggle()
    return self:select(self.previous_mode or 'mode_2')
end

function ModeManager:update()
    local engine = self.mod.engine

    if self.pending_mode and (not engine or not engine:is_in_action() or engine:is_safe_to_switch_mode()) then
        self:_activate(self.pending_mode)
    end
end

function ModeManager:profile(kind, weapon_name)
    return Profiles.get(self.data, self.active_mode, kind, weapon_name)
end

function ModeManager:_edit_profile(kind)
    local mode_data = self.data[self.editing_mode]
    local profiles = mode_data[kind]
    local weapon_key = self.selected_weapons[self.editing_mode][kind]
    local global_key = kind == 'MELEE' and 'global_melee' or 'global_ranged'

    if weapon_key ~= global_key and not profiles[weapon_key] then
        profiles[weapon_key] = Profiles.clone(profiles[global_key])
    end

    return profiles[weapon_key]
end

function ModeManager:_save()
    self.mod:set(PROFILE_DATA_KEY, self.data, false)
    self.mod:set(SELECTED_WEAPONS_KEY, self.selected_weapons, false)
    self.revision = self.revision + 1

    if self.mod.engine then
        self.mod.engine:invalidate()
    end
end

function ModeManager:_sync_kind(kind)
    local profile = self:_edit_profile(kind)
    local prefix = string.lower(kind) .. '_'

    self.mod:set(prefix .. 'weapon_selection', self.selected_weapons[self.editing_mode][kind], false)

    for _, key in ipairs(Profiles.keys(kind)) do
        self.mod:set(prefix .. key, profile[key], false)
    end
end

function ModeManager:sync_settings()
    self:_sync_kind('MELEE')
    self:_sync_kind('RANGED')
end

function ModeManager:on_setting_changed(setting_name)
    if setting_name == 'editing_mode' then
        local editing_mode = self.mod:get(setting_name)
        self.editing_mode = self.data[editing_mode] and editing_mode or 'mode_1'
        self:sync_settings()

        return true
    end

    local kind, key = _kind_setting(setting_name)

    if not kind then
        return false
    end

    if key == 'weapon_selection' then
        self.selected_weapons[self.editing_mode][kind] = self.mod:get(setting_name)
        self:_edit_profile(kind)
        self:_save()
        self:_sync_kind(kind)

        return true
    end

    local profile = self:_edit_profile(kind)
    profile[key] = self.mod:get(setting_name)
    self:_save()

    return true
end

return ModeManager
