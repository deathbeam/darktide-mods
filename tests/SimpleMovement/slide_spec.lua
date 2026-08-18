describe('SimpleMovement forward sprint-slide', function()
    local hooks
    local mod
    local service
    local unit_data_extension
    local character_state
    local sprint_character_state
    local unit_ready
    local now

    local REQUIRE_PATHS = {
        ['scripts/settings/player_character/player_character_constants'] = { slide_move_speed_threshold_sq = 4 },
        ['scripts/extension_systems/weapon/utilities/action_availability'] = {
            available_in_sprint = function()
                return false, false
            end,
        },
        ['scripts/settings/action/action_handler_settings'] = { abort_sprint = {} },
        ['scripts/extension_systems/character_state_machine/character_states/utilities/sprint'] = {
            requires_press_to_interrupt = function()
                return false
            end,
            no_interruption_for_sprint = function()
                return false
            end,
        },
    }

    local function _vec(x, y, z)
        return { x = x, y = y, z = z }
    end

    local function _setup(overrides, state_name, sprint_state)
        hooks = {}
        now = 0
        unit_ready = false

        character_state = { state_name = state_name or 'walking', entered_t = 0 }
        sprint_character_state = sprint_state or { is_sprinting = false }
        local dodge_character_state = {
            started_from_crouch = false,
            distance_left = 1,
            consecutive_dodges = 0,
            consecutive_dodges_cooldown = 0,
        }
        local locomotion = { velocity_current = _vec(0, 5, 0) }
        local movement_state = { is_crouching = false }

        unit_data_extension = {
            is_local_unit = function()
                return true
            end,
            read_component = function(_, name)
                if name == 'character_state' then
                    return character_state
                elseif name == 'sprint_character_state' then
                    return sprint_character_state
                elseif name == 'dodge_character_state' then
                    return dodge_character_state
                elseif name == 'locomotion' then
                    return locomotion
                elseif name == 'movement_state' then
                    return movement_state
                end
                return nil
            end,
        }

        service = {}

        local input_settings = { hold_to_crouch = true }

        mod = {
            get = function(_, id)
                return overrides and overrides[id]
            end,
            hook = function(_, class, method, callback)
                hooks[class] = hooks[class] or {}
                hooks[class][method] = callback
            end,
            hook_safe = function(_, class, method, callback)
                hooks[class] = hooks[class] or {}
                hooks[class][method] = callback
            end,
            hook_require = function() end,
        }

        _G.get_mod = function()
            return mod
        end
        _G.CLASS = {
            InputService = {},
            CharacterStateMachine = {},
            PlayerCharacterStateSliding = {},
            PlayerCharacterStateSprinting = {},
            ActionSweep = {},
            ActionHandler = {},
            EventManager = {},
            PlayerUnitDataExtension = {},
        }
        _G.Managers = {
            time = {
                time = function(_, timer)
                    return now
                end,
            },
            player = {
                local_player_safe = function()
                    return { player_unit = {} }
                end,
            },
            save = {
                account_data = function()
                    return { input_settings = input_settings }
                end,
            },
            event = {},
        }
        _G.ScriptUnit = {
            has_extension = function(_, extension_name)
                if extension_name == 'unit_data_system' and unit_ready then
                    return unit_data_extension
                end
                return nil
            end,
        }
        _G.Vector3 = setmetatable({
            flat = function(v)
                return _vec(v.x, v.y, 0)
            end,
            length = function(v)
                return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
            end,
            length_squared = function(v)
                return v.x * v.x + v.y * v.y + v.z * v.z
            end,
            normalize = function(v)
                local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
                if len == 0 then
                    return _vec(0, 0, 0)
                end
                return _vec(v.x / len, v.y / len, v.z / len)
            end,
        }, {
            __call = function(_, x, y, z)
                return _vec(x, y, z)
            end,
        })

        for path, stub in pairs(REQUIRE_PATHS) do
            package.loaded[path] = stub
        end

        dofile('SimpleMovement/scripts/mods/SimpleMovement/SimpleMovement.lua')
        mod.on_enabled()
    end

    local function _input_hook(action_name, values)
        local input = hooks[_G.CLASS.InputService]._get
        local func = function(_, name)
            return values[name]
        end
        return input(func, service, action_name)
    end

    local function _press_forward_dodge_and_crouch()
        _input_hook('move_forward', { move_forward = 1 })
        _input_hook('dodge', { dodge = true, dodge_hold = false })
        return _input_hook('crouching', { crouching = false })
    end

    after_each(function()
        _G.get_mod = nil
        _G.CLASS = nil
        _G.Managers = nil
        _G.ScriptUnit = nil
        _G.Vector3 = nil
        for path in pairs(REQUIRE_PATHS) do
            package.loaded[path] = nil
        end
    end)

    it('fires the slide without any init hook when the unit spawns after on_enabled', function()
        _setup(nil, 'sprinting', { is_sprinting = true })

        -- The local player unit did not exist when on_enabled ran, so a cached
        -- design would have an empty component store. Resolving fresh must still
        -- produce the slide once the unit is present.
        unit_ready = true

        assert.is_true(_press_forward_dodge_and_crouch())
    end)

    it('recovers the sprint state after an unhooked transition', function()
        _setup(nil, 'walking', { is_sprinting = false })
        unit_ready = true

        -- Prime move_forward while walking.
        _input_hook('move_forward', { move_forward = 1 })

        -- The engine transitions to sprinting without our code observing a
        -- _change_state hook (we no longer install one). State is read from the
        -- authoritative character_state component on the next input read.
        character_state.state_name = 'sprinting'
        sprint_character_state.is_sprinting = true

        assert.is_true(_press_forward_dodge_and_crouch())
    end)

    it('does not force a slide when dodge_slide is disabled', function()
        _setup({ dodge_slide = false }, 'sprinting', { is_sprinting = true })
        unit_ready = true

        assert.is_false(_press_forward_dodge_and_crouch())
    end)
end)
