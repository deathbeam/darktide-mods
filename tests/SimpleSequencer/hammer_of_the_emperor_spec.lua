local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/SimpleSequencer/') or '.'
local ActionSemantics = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/modules/ActionSemantics.lua')

-- The suffix identifies the native chain node; the sequencer only submits the attack type.
local GUIDE_COMBOS = {
    {
        name = 'Arbites Shock Maul · Branx Mk III',
        horde = { 'PA > Hc > H2 > L3 > L4' },
        single = { 'H1 > SP2 > H1 > L2' },
    },
    {
        name = 'Arc Maul · Branx Mk III',
        horde = { 'L1 > H4 > H3', 'Push > L2 > H3 > H4' },
        single = { 'PA > H1 > H2 > L3' },
    },
    { name = 'Assault Chainaxe · Orestes Mk XII', horde = { 'Push > L1 > L2' }, single = { 'SP > Hs > H2 > H1' } },
    {
        name = 'Assault Chainaxe · Orestes Mk IV',
        horde = { 'PA > H1 > H2' },
        single = { 'SP > Hs > L2 > L3 > L4 > L1' },
    },
    {
        name = 'Assault Chainsword · Cadia Mk IV',
        horde = { 'Push > H2 > H1 > H2 > L3 > Hc' },
        single = { 'SP > Hs > PA > L4 > L1 > H0' },
    },
    {
        name = 'Assault Chainsword · Cadia Mk XIIIg',
        horde = { 'PA > L3 > H3 > L3 > L4' },
        single = { 'SP > Hs > H1 > H2 > L2' },
    },
    { name = 'Combat Axe · Rashad Mk III', horde = { 'PA > L1 > L2 > L3' }, single = { 'H1 > H2' } },
    { name = 'Combat Axe · Antax Mk V', horde = { 'PA > L1 > L2 > L3' }, single = { 'H1 > H2' } },
    { name = 'Combat Axe · Achlys Mk VIII', horde = { 'PA > H1 > L2' }, single = { 'H1 > H2 > H3' } },
    {
        name = 'Combat Blade · Catachan Mk VI',
        horde = { 'H1 > H2 > L3' },
        single = { 'PA > H2 > H3 > H1', 'H1 > H2 > SP > Ls' },
    },
    { name = 'Combat Blade · Catachan Mk III', horde = { 'L1 > L2 > L3 > L4' }, single = { 'PA > H2 > L3' } },
    {
        name = 'Crusher · Indignatus Mk IVe',
        horde = { 'L1 > H2 > L3', 'SP > Ls > H2' },
        single = { 'SP > Hs > L2 > H1' },
    },
    {
        name = 'Devil Claw Sword · Catachan Mk VII',
        horde = { 'Push > H1 > L2' },
        single = { 'SP > Ls > Lc > PA > L3 > L1 > H2' },
    },
    { name = 'Devil Claw Sword · Catachan Mk I', horde = { 'PA > H1 > H2' }, single = { 'SP > Ls > L3 > Hc' } },
    {
        name = 'Devil Claw Sword · Catachan Mk IV',
        horde = { 'Push > L1 > H2 > L3' },
        single = { 'SP > Ls > H1 > PA' },
    },
    { name = 'Duelling Sword · Maccabian Mk II', horde = { 'PA > L3 > H2' }, single = { 'SP > H1 > L2' } },
    { name = 'Duelling Sword · Maccabian Mk IV', horde = { 'L1 > PA > L3 > L2' }, single = { 'SP > H1 > H2' } },
    { name = 'Duelling Sword · Maccabian Mk V', horde = { 'PA > L2 > L3 > L1' }, single = { 'SP > H1 > H2 > L3' } },
    {
        name = 'Heavy Eviscerator · Tigrus Mk III',
        horde = { 'H1 > L2 > L3 > PA' },
        single = { 'SP > Hs > Push > L4 > L1' },
    },
    {
        name = 'Heavy Eviscerator · Tigrus Mk XV',
        horde = { 'Push > L2 > L3 > L4 > L1' },
        single = { 'SP > Hs > H2 > H1' },
    },
    {
        name = 'Heavy Sword · Turtolsky Mk VI',
        horde = { 'Push > L4 > L1 > SP > Ls > H2 > L1' },
        single = { 'SP > H1 > H2 > PA > H2' },
    },
    {
        name = 'Heavy Sword · Turtolsky Mk VII',
        horde = { 'Push > H1 > L2 > SP > H1' },
        single = { 'SP > H1 > H2 > PA > H2' },
    },
    { name = 'Heavy Sword · Turtolsky Mk IX', horde = { 'Push > L1 > H2 > H3' }, single = { 'SP > H1 > PA' } },
    { name = 'Mechanicus Power Sword · Branx Mk VI', horde = { 'PA > L4 > H2' }, single = { 'L1 > L2 > L3 > H3' } },
    {
        name = 'Paired Transonic Blades · Slayer',
        horde = { 'Push > H1 > H2 > L3' },
        single = { 'PA > Lc > SP > Hs > H2' },
    },
    {
        name = 'Paired Transonic Blades · Duellist',
        horde = { 'PA > Lc > SP > Hs > H1' },
        single = { 'H1 > H2 > L1 > L2' },
    },
    {
        name = 'Power Falchion · Aridin Mk I',
        horde = { 'L1 > L2 > H3', 'Push > L2 > H3' },
        single = { 'PA > H1 > H2 > PA > L3' },
    },
    {
        name = 'Power Falchion · Lawbringer Mk IIb',
        horde = { 'PA > L3 > L4 > H1 > L2 > L3' },
        single = { 'Push > Lp > L1 > H2' },
    },
    {
        name = 'Power Sword · Achlys Mk VI',
        horde = { 'SP > L1 > L2 > L3', 'SP > Push > L2 > L3' },
        single = { 'SP > PA > L4 > L1' },
    },
    { name = 'Power Sword · Scandar Mk III', horde = { 'SP > Push > H > H > H' }, single = { 'SP > PA > L1 > L2' } },
    {
        name = 'Relic Blade · Munitorum Mk X',
        horde = { 'L1 > L2 > H3 > L2 > H3 > H4', 'Push > L2 > H3 > L2 > H3 > H4' },
        single = { 'H1 > PA > H2 > L3' },
    },
    {
        name = 'Relic Blade · Munitorum Mk II',
        horde = { 'PA > L3 > H2 > L3', 'PA > H1 > H2 > L3' },
        single = { 'L1 > L2 > H3 > L2 > H3 > H4' },
    },
    { name = 'Sapper Shovel · Munitorum Mk I', horde = { 'Push > H1 > H2 > L3' }, single = { 'PA > L1 > L2 > L3' } },
    { name = 'Sapper Shovel · Munitorum Mk III', horde = { 'Push > L2 > H1' }, single = { 'SP > Hs > H2' } },
    { name = 'Sapper Shovel · Munitorum Mk VII', horde = { 'Push > H1 > H2 > L3' }, single = { 'SP > Ls > PA > L3' } },
    { name = 'Shock Maul · Munitorum Mk III', horde = { 'PA > L4 > H1' }, single = { 'SP > H2 > L3 > H2 > H3' } },
    { name = 'Shock Maul · Agni Mk Ia', horde = { 'Push > L1 > H2' }, single = { 'SP > H1 > PA > L2 > L3 > L4' } },
    { name = 'Shock Maul and Shield · Branx Mk VI', horde = { 'H1 > PA > L2' }, single = { 'L1 > H2 > L3 > L4' } },
    {
        name = 'Shock Maul and Shield · Branx Mk XI',
        horde = { 'Push > H1 > L2 > L1 > L2' },
        single = { 'PA > H2 > H3 > L3 > L4' },
    },
    { name = 'Tactical Axe · Atrox Mk VII', horde = { 'PA > H1 > L2' }, single = { 'PA > L1 > H2 > L3' } },
    { name = 'Tactical Axe · Atrox Mk II', horde = { 'PA > H2 > H1' }, single = { 'PA > L2 > L3 > L1' } },
    { name = 'Tactical Axe · Atrox Mk IV', horde = { 'PA > L2 > L3 > L1' }, single = { 'H1 > H2' } },
    { name = 'Thunder Hammer · Crucis Mk II', horde = { 'H1 > PA > H2' }, single = { 'SP > Hs > L1 > L2 > L3' } },
    {
        name = 'Thunder Hammer · Ironhelm Mk IV',
        horde = { 'H1 > PA > H2 > L1', 'SP > Hs > PA > H2 > L1' },
        single = { 'SP > Hs > Push > L2 > H3' },
    },
}

local function _template()
    return {
        action_input_hierarchy = {
            {
                input = 'start_attack',
                transition = {
                    { input = 'light_attack', transition = 'base' },
                    { input = 'heavy_attack', transition = 'base' },
                },
            },
            {
                input = 'block',
                transition = {
                    { input = 'push', transition = { { input = 'push_follow_up', transition = 'base' } } },
                },
            },
            {
                input = 'special_action_hold',
                transition = {
                    { input = 'special_action_light', transition = 'base' },
                    { input = 'special_action_heavy', transition = 'base' },
                },
            },
            { input = 'special_action', transition = 'base' },
        },
        action_inputs = {},
        actions = {},
    }
end

local function _commands(route)
    route = route:gsub('Sprint Cancel', ''):gsub('Block Cancel', '')
    local commands = {}

    for token in route:gmatch('[^%s>]+') do
        token = token:gsub('[()]', '')
        token = token:match('^[^/]+') or token

        if token == 'Push' then
            commands[#commands + 1] = 'push'
        elseif token == 'PA' then
            commands[#commands + 1] = 'push_attack'
        elseif token:match('^SP') then
            commands[#commands + 1] = 'special_action'
        elseif token:match('^L') then
            commands[#commands + 1] = 'light_attack'
        elseif token:match('^H') then
            commands[#commands + 1] = 'heavy_attack'
        elseif token ~= '' and token ~= 'Cancel' then
            error('unsupported guide token: ' .. token)
        end
    end

    return commands
end

describe('Hammer of the Emperor recommended melee combos', function()
    for _, weapon in ipairs(GUIDE_COMBOS) do
        for _, scenario in ipairs({ 'horde', 'single' }) do
            for route_index, route in ipairs(weapon[scenario]) do
                it(weapon.name .. ' ' .. scenario .. ' route ' .. route_index, function()
                    local template = _template()
                    local commands = _commands(route)
                    local plan = ActionSemantics.compile(
                        { steps = commands, cycle_step = 1, repeating = false },
                        { template = template, kind = 'MELEE' }
                    )

                    assert.are.equal(#commands, #plan.goals)

                    for index, command in ipairs(commands) do
                        assert.are.equal(command, plan.goals[index].command)
                    end
                end)
            end
        end
    end
end)
