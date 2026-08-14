describe('SimpleActivate', function()
    local hooks
    local mod
    local service
    local template
    local now
    local unit
    local weapon_extension

    local function _base_input()
        return false
    end

    local function _wield_input()
        return true
    end

    local function _base_wield(_, _, _, skip_wield_action)
        return skip_wield_action
    end

    local function _setup(template_name, action_inputs)
        hooks = {}
        now = 1
        unit = {}
        template = {
            name = template_name,
            action_inputs = action_inputs,
        }
        weapon_extension = {
            _weapons = {
                slot_grenade_ability = {
                    weapon_template = template,
                },
            },
        }

        service = {
            current_held = true,
        }

        function service:get_alias_key(action_name)
            return action_name
        end

        function service:get_keys_from_alias()
            return { 'activation_key' }
        end

        function service:devices()
            return { self }
        end

        function service:button_index()
            return 1
        end

        function service:held()
            return self.current_held
        end

        mod = {
            get = function()
                return true
            end,
            hook = function(_, class, method, callback)
                hooks[class] = hooks[class] or {}
                hooks[class][method] = callback
            end,
            hook_safe = function(_, class, method, callback)
                hooks[class] = hooks[class] or {}
                hooks[class][method] = callback
            end,
        }

        _G.get_mod = function()
            return mod
        end
        _G.CLASS = {
            ActionHandler = {},
            InputService = {},
            PlayerUnitWeaponExtension = {},
        }
        _G.Managers = {
            player = {
                local_player_safe = function()
                    return { player_unit = unit }
                end,
            },
            state = {
                game_mode = {
                    game_mode_name = function()
                        return 'mission'
                    end,
                },
            },
            time = {
                has_timer = function()
                    return true
                end,
                time = function()
                    return now
                end,
            },
        }
        _G.ScriptUnit = {
            has_extension = function(_, extension_name)
                return extension_name == 'weapon_system' and weapon_extension or nil
            end,
        }

        dofile('SimpleActivate/scripts/mods/SimpleActivate/SimpleActivate.lua')
        mod.on_enabled()
    end

    local function _arm_and_request_activation()
        local input_hook = hooks[CLASS.InputService]._get
        local wield_hook = hooks[CLASS.PlayerUnitWeaponExtension].on_slot_wielded

        input_hook(_wield_input, service, 'grenade_ability_pressed')
        wield_hook(_base_wield, { _unit = unit }, 'slot_grenade_ability', now, false)

        service.current_held = false
        mod.update()

        return input_hook(_base_input, service, 'action_one_pressed')
    end

    after_each(function()
        _G.get_mod = nil
        _G.CLASS = nil
        _G.Managers = nil
        _G.ScriptUnit = nil
    end)

    it('does not treat the servo-skull targeting template as a primary-action grenade', function()
        _setup('cryptic_servo_skull_order_point', {
            inspect_alt_start = {
                input_sequence = {
                    { input = 'action_one_pressed', value = true },
                },
            },
        })

        assert.is_false(_arm_and_request_activation())
    end)

    it('still auto-activates a grenade whose use input is primary action', function()
        _setup('test_grenade', {
            aim_hold = {
                input_sequence = {
                    { input = 'action_one_pressed', value = true },
                },
            },
            inspect_alt_start = {
                input_sequence = {
                    { input = 'action_one_pressed', value = true },
                },
            },
        })

        assert.is_true(_arm_and_request_activation())
    end)
end)
