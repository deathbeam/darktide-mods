local ActionClassifier = {}

function ActionClassifier.classify(action_name, action_settings, expected_command)
    if not action_name or action_name == 'idle' then
        return 'idle'
    end

    local start_input = action_settings and action_settings.start_input
    local kind = action_settings and action_settings.kind

    if start_input == 'special_action_hold' then
        return 'special_start_attack'
    elseif start_input == 'special_action_light' then
        return 'special_light_attack'
    elseif start_input == 'special_action_heavy' then
        return 'special_heavy_execute'
    elseif start_input == 'special_action' then
        return 'special_action'
    elseif start_input == 'start_attack' then
        return 'start_attack'
    elseif kind == 'charge_ammo' then
        return 'charge'
    elseif start_input == 'shoot_pressed' then
        return 'shoot'
    elseif start_input == 'charge' then
        return 'charge'
    elseif kind == 'trigger_explosion' then
        return 'special_heavy_execute'
    end

    if
        (expected_command == 'start_attack' or expected_command == 'light_attack' or expected_command == 'heavy_attack')
        and string.find(action_name, 'start', 1, true)
        and string.find(action_name, 'special', 1, true)
    then
        return 'start_attack'
    elseif
        expected_command == 'special_start_attack'
        and (kind == 'windup' or string.find(action_name, 'start', 1, true))
    then
        return 'special_start_attack'
    elseif expected_command == 'special_light_attack' and kind == 'sweep' then
        return 'special_light_attack'
    elseif expected_command == 'special_heavy_execute' and kind == 'sweep' then
        return 'special_heavy_execute'
    elseif expected_command == 'light_attack' and kind == 'sweep' then
        return 'light_attack'
    elseif expected_command == 'heavy_attack' and kind == 'sweep' then
        return 'heavy_attack'
    elseif expected_command == 'shoot' and (kind == 'chain_lightning' or kind == 'damage_target') then
        return 'shoot'
    end

    if string.find(action_name, 'wield', 1, true) then
        return 'quick_wield'
    end

    if string.find(action_name, 'reload', 1, true) or string.find(action_name, 'vent', 1, true) then
        return 'weapon_reload'
    end

    if string.find(action_name, 'pushfollow', 1, true) or string.find(action_name, 'push_follow', 1, true) then
        return 'push_follow_up'
    end

    if string.find(action_name, 'push', 1, true) or string.find(action_name, 'fling', 1, true) then
        return 'push'
    end

    if string.find(action_name, 'block', 1, true) then
        return 'block'
    end

    if string.find(action_name, 'shoot', 1, true) or action_name == 'rapid_left' then
        return 'shoot'
    end

    if string.find(action_name, 'charge', 1, true) then
        return 'charge'
    end

    if string.find(action_name, 'invert', 1, true) then
        return 'special_invert'
    elseif
        string.find(action_name, 'activate_special', 1, true) or string.find(action_name, 'toggle_special', 1, true)
    then
        return 'special_action'
    elseif string.find(action_name, 'stab_start', 1, true) or string.find(action_name, 'bash_start', 1, true) then
        return 'special_start_attack'
    elseif string.find(action_name, 'stab_heavy', 1, true) or string.find(action_name, 'bash_heavy', 1, true) then
        return 'special_heavy_execute'
    elseif string.find(action_name, 'bash', 1, true) or string.find(action_name, 'stab', 1, true) then
        return 'special_light_attack'
    end

    if string.find(action_name, 'special', 1, true) then
        if string.find(action_name, 'start', 1, true) then
            return 'special_start_attack'
        elseif string.find(action_name, 'execute', 1, true) or string.find(action_name, 'heavy', 1, true) then
            return 'special_heavy_execute'
        elseif string.find(action_name, 'light', 1, true) then
            return 'special_light_attack'
        end

        return 'special_action'
    end

    if string.find(action_name, 'start', 1, true) then
        return 'start_attack'
    end

    if string.find(action_name, 'heavy', 1, true) then
        return 'heavy_attack'
    end

    if string.find(action_name, 'light', 1, true) or string.find(action_name, 'swing', 1, true) then
        return 'light_attack'
    end

    return 'idle'
end

return ActionClassifier
