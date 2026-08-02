local mod = get_mod('SimpleSequencer')
local Profiles = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceProfiles')
local WeaponContext = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/WeaponContext')

local ModeManager = class('SimpleSequencerModeManager')

local MODES = { 'mode_1', 'mode_2', 'mode_3', 'mode_4' }
local PROFILE_DATA_KEY = 'profile_data'
local SELECTED_WEAPONS_KEY = 'selected_weapons'

local DISPLAY_DEFAULTS = {
    mode_1 = {
        name = 'Mode 1',
        icon = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_uprising',
        color = { 255, 190, 80 },
    },
    mode_2 = {
        name = 'Mode 2',
        icon = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_malice',
        color = { 100, 190, 255 },
    },
    mode_3 = {
        name = 'Mode 3',
        icon = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_heresy',
        color = { 255, 110, 110 },
    },
    mode_4 = {
        name = 'Mode 4',
        icon = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_damnation',
        color = { 190, 140, 255 },
    },
}

local DISPLAY_KEYS = { 'name', 'icon', 'color_r', 'color_g', 'color_b' }
local DISPLAY_KEY_SET = {
    name = true,
    icon = true,
    color_r = true,
    color_g = true,
    color_b = true,
}
local DISPLAY_SETTING_PREFIX = 'mode_display_'

local function _display_setting_key(mode, key)
    return mode .. '_' .. key
end

local function _display_value(value, default_value)
    if type(value) == 'table' then
        value = value[1]
    end

    if value == nil or value == '' then
        return default_value
    end

    return value
end

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

    for _, mode in ipairs(MODES) do
        local defaults = DISPLAY_DEFAULTS[mode]
        local color = defaults.color
        local name = _display_value(mod_instance:get(_display_setting_key(mode, 'name')), defaults.name)
        local icon = _display_value(mod_instance:get(_display_setting_key(mode, 'icon')), defaults.icon)
        local red = tonumber(mod_instance:get(_display_setting_key(mode, 'color_r'))) or color[1]
        local green = tonumber(mod_instance:get(_display_setting_key(mode, 'color_g'))) or color[2]
        local blue = tonumber(mod_instance:get(_display_setting_key(mode, 'color_b'))) or color[3]

        mod_instance:set(_display_setting_key(mode, 'name'), name, false)
        mod_instance:set(_display_setting_key(mode, 'icon'), icon, false)
        mod_instance:set(_display_setting_key(mode, 'color_r'), red, false)
        mod_instance:set(_display_setting_key(mode, 'color_g'), green, false)
        mod_instance:set(_display_setting_key(mode, 'color_b'), blue, false)
    end
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

function ModeManager:_use_current_weapon(kind)
    local weapon_name = WeaponContext.equipped(kind)

    if not weapon_name then
        return false
    end

    self.selected_weapons[self.editing_mode][kind] = weapon_name
    self:_edit_profile(kind)
    self:_save()
    self:_sync_kind(kind)

    return true
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

function ModeManager:_sync_display()
    local defaults = DISPLAY_DEFAULTS[self.editing_mode] or DISPLAY_DEFAULTS.mode_1

    for _, key in ipairs(DISPLAY_KEYS) do
        local value = self.mod:get(_display_setting_key(self.editing_mode, key))

        if value == nil then
            if key == 'name' then
                value = defaults.name
            elseif key == 'icon' then
                value = defaults.icon
            else
                local color_index = key == 'color_r' and 1 or key == 'color_g' and 2 or 3
                value = defaults.color[color_index]
            end
        end

        self.mod:set(DISPLAY_SETTING_PREFIX .. key, value, false)
    end
end

function ModeManager:sync_settings()
    self:_sync_kind('MELEE')
    self:_sync_kind('RANGED')
    self:_sync_display()
end

function ModeManager:_on_display_setting_changed(setting_name)
    if string.sub(setting_name, 1, #DISPLAY_SETTING_PREFIX) ~= DISPLAY_SETTING_PREFIX then
        return false
    end

    local key = string.sub(setting_name, #DISPLAY_SETTING_PREFIX + 1)

    if not DISPLAY_KEY_SET[key] then
        return false
    end

    local value = _display_value(self.mod:get(setting_name), nil)

    if value ~= nil then
        self.mod:set(_display_setting_key(self.editing_mode, key), value, false)
    end

    return true
end

function ModeManager:on_setting_changed(setting_name)
    if self:_on_display_setting_changed(setting_name) then
        return true
    end

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

    if key == 'use_current_weapon' then
        self:_use_current_weapon(kind)
        self.mod:set(setting_name, false, false)

        return true
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
