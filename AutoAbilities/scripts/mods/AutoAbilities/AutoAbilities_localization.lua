local function cf(text, color_name)
    local color = Color[color_name](255, true)
    return string.format('{#color(%s,%s,%s)}', color[2], color[3], color[4]) .. text .. '{#color(203,203,203)}'
end

local box = 2
local rock = 4
local nuke = 1
local frag = 3
local krak = 2
local smoke = 3
local flame = 3
local shock = 3
local mine = 2
local arbites = 4
local flask = 3
local launcher = 2
local enhanced = 2
local grenadier = 1

return {
    mod_name = {
        en = 'AutoAbilities',
    },
    mod_description = {
        en = 'Automatically use abilities and consumables based on conditions or keybinds',
    },

    -- Chemical AutoStim
    chemical_autostim = {
        en = 'Chemical AutoStim',
    },
    chemical_autostim_enabled = {
        en = 'Enable Chemical AutoStim',
    },

    -- Quick Deploy
    quick_deploy = {
        en = 'Quick Deploy',
    },
    quick_deploy_enabled = {
        en = 'Enable Quick Deploy',
    },
    quick_deploy_enabled_tooltip = {
        en = 'Automatically use ammo/medkits/stims when wielded',
    },

    -- Auto Blitz
    auto_blitz = {
        en = 'Auto Blitz',
    },
    auto_blitz_enabled = {
        en = 'Enable Auto Blitz',
    },
    auto_blitz_enabled_tooltip = {
        en = 'Automatically throw grenades when wielded (skips quick-throw grenades like Zealot Knives and Broker Flash)',
    },
}
