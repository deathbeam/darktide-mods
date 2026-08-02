local source = debug.getinfo(1, 'S').source
local source_path = source:sub(1, 1) == '@' and source:sub(2) or source
local root = source_path:match('^(.*)/tests/shared/') or '.'
root = root .. (root:sub(-1) == '/' and '' or '/')

local DarktideMock = {}

local function _new_template(name, template)
    template = template or {}
    template.name = template.name or name
    template.actions = template.actions or {}
    template.action_inputs = template.action_inputs or {}
    template.displayed_attacks = template.displayed_attacks or {
        primary = { type = 'ranged' },
    }

    return template
end

local function _new_class()
    local class = {}

    function class:new(...)
        local instance = setmetatable({}, { __index = class })

        if instance.init then
            instance:init(...)
        end

        return instance
    end

    return class
end

function DarktideMock.new()
    local mock = {
        now = 0,
        settings = {
            reset_on_interrupt = true,
        },
        unit = {},
        mod = {},
        extension = nil,
        player = nil,
    }

    local inventory = {
        wielded_slot = 'slot_secondary',
    }
    local weapons = {}
    local action_component = {
        current_action_name = 'none',
        start_t = nil,
    }
    local charge_component = {
        charge_level = 0,
        max_charge = nil,
        charge_start_time = nil,
    }

    mock.extension = {
        _inventory_component = inventory,
        _weapons = weapons,
        _weapon_action_component = action_component,
        _action_module_charge_component = charge_component,
        _running_action_settings = nil,
        _action_handler = {
            _registered_components = {
                weapon_action = {},
            },
        },
    }

    function mock.extension:running_action_settings()
        return self._running_action_settings
    end

    function mock.extension:_wielded_weapon(current_inventory)
        local weapon = self._weapons[current_inventory.wielded_slot]

        return weapon
    end

    mock.player = {
        player_unit = mock.unit,
    }

    function mock.mod:get(setting_id)
        return mock.settings[setting_id]
    end

    function mock.mod:io_dofile(path)
        local filename = path:sub(-4) == '.lua' and path or path .. '.lua'

        return dofile(root .. filename)
    end

    function mock:set_action(action_name, settings, start_t)
        action_component.current_action_name = action_name or 'none'
        action_component.start_t = start_t
        mock.extension._running_action_settings = settings
    end

    function mock:set_charge(level, max_charge, start_t)
        charge_component.charge_level = level or 0
        charge_component.max_charge = max_charge
        charge_component.charge_start_time = start_t
    end

    function mock:set_weapon(slot, name, template)
        weapons[slot] = {
            weapon_template = _new_template(name, template),
        }
    end

    function mock:set_wielded_slot(slot)
        inventory.wielded_slot = slot
    end

    function mock:install()
        _G.get_mod = function()
            return self.mod
        end

        _G.class = _new_class
        _G.Managers = {
            time = {
                time = function()
                    return self.now
                end,
            },
            player = {
                local_player_safe = function()
                    return self.player
                end,
            },
        }
        _G.ScriptUnit = {
            has_extension = function(unit, extension_name)
                if unit == self.unit and extension_name == 'weapon_system' then
                    return self.extension
                end

                return nil
            end,
        }
    end

    function mock:load_sequence_engine(mode_manager)
        self:install()
        local sequence_engine =
            dofile(root .. 'SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceEngine.lua')

        return sequence_engine:new(self.mod, mode_manager)
    end

    function mock:load_weapon_context()
        self:install()

        return dofile(root .. 'SimpleSequencer/scripts/mods/SimpleSequencer/modules/WeaponContext.lua')
    end

    mock:set_weapon('slot_secondary', 'test_ranged')
    mock:set_weapon('slot_primary', 'test_melee', {
        displayed_attacks = {
            primary = { type = 'melee' },
        },
    })
    mock:install()

    return mock
end

return DarktideMock
