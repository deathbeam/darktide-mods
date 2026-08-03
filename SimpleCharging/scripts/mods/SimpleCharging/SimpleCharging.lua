local mod = get_mod('SimpleCharging')

local ChargeSources = mod:io_dofile('SimpleCharging/scripts/mods/SimpleCharging/modules/ChargeSources')
mod.charge_sources = ChargeSources
local HudElementSimpleCharging =
    mod:io_dofile('SimpleCharging/scripts/mods/SimpleCharging/modules/HudElementSimpleCharging')

mod.hud_element = HudElementSimpleCharging
