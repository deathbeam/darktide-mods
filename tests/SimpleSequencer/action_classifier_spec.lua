local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/SimpleSequencer/') or '.'
local ActionClassifier = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/modules/ActionClassifier.lua')

describe('SimpleSequencer ActionClassifier', function()
    it('uses action metadata for charge-ammo weapons', function()
        local action = ActionClassifier.classify('action_charge', {
            kind = 'charge_ammo',
            start_input = 'shoot_pressed',
        }, 'charge')

        assert.are.equal('charge', action)
    end)

    it('classifies special input metadata before action-name fallbacks', function()
        local action = ActionClassifier.classify('activate_special', {
            start_input = 'special_action_heavy',
        }, 'special_heavy_execute')

        assert.are.equal('special_heavy_execute', action)
    end)

    it('uses the expected command to classify sweep actions', function()
        local action = ActionClassifier.classify('sweep_attack', { kind = 'sweep' }, 'heavy_attack')

        assert.are.equal('heavy_attack', action)
    end)

    it('falls back to common action-name patterns', function()
        assert.are.equal('quick_wield', ActionClassifier.classify('quick_wield', nil, 'quick_wield'))
        assert.are.equal('push_follow_up', ActionClassifier.classify('pushfollow', nil, 'push_follow_up'))
        assert.are.equal('special_invert', ActionClassifier.classify('activate_invert', nil, 'special_invert'))
    end)
end)
