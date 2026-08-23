local mod = get_mod('SimpleSequencer')
local Profiles = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceProfiles')

local localizations = {
    mod_name = {
        en = ' {#color(80,200,255)}Simple{#reset()} Sequencer',
    },
    mod_description = {
        en = 'Hold-driven attack sequencer for melee combos and ranged autofire, with four switchable modes, per-weapon profiles, and a customizable HUD indicator.',
    },
    global_melee = {
        en = 'All Melee Weapons',
    },
    global_ranged = {
        en = 'All Ranged Weapons',
    },
    hud_display_mode = {
        en = 'HUD Display',
    },
    hud_display_disabled = {
        en = 'Disabled',
    },
    hud_display_icon = {
        en = 'Icon',
    },
    hud_display_name = {
        en = 'Name',
    },
    hud_display_icon_and_name = {
        en = 'Icon + Name',
    },
    editing_mode = {
        en = 'Mode to Configure',
    },
    melee_weapon_selection = {
        en = 'Weapon Override',
    },
    ranged_weapon_selection = {
        en = 'Weapon Override',
    },
    melee_use_current_weapon = {
        en = 'Use Current Melee Weapon',
    },
    ranged_use_current_weapon = {
        en = 'Use Current Ranged Weapon',
    },
    use_current_weapon_button = {
        en = 'Use Current',
    },
    melee_sequence_cycle_point = {
        en = 'Cycle Point',
    },
    ranged_automatic_fire_hip = {
        en = 'Hipfire Automatic Fire',
    },
    ranged_automatic_fire_ads = {
        en = 'ADS Automatic Fire',
    },
    ranged_auto_charge_threshold = {
        en = 'Charge Threshold %%',
    },
    select_mode = {
        en = 'Activate Mode',
    },
    select_mode_previous = {
        en = 'Previous Mode',
    },
    select_mode_next = {
        en = 'Next Mode',
    },
    select_mode_toggle = {
        en = 'Switch to Previous Mode',
    },
    hud_position_x = {
        en = 'HUD Horizontal Offset',
    },
    hud_position_y = {
        en = 'HUD Vertical Offset',
    },
    general_settings = {
        en = 'General',
    },
    mode_keybinds = {
        en = 'Modes',
    },
    melee_settings = {
        en = 'Melee (Current Mode)',
    },
    ranged_settings = {
        en = 'Ranged (Current Mode)',
    },
    mode_display_name = {
        en = 'Mode Name',
    },
    mode_display_icon = {
        en = 'Mode Icon',
    },
    mode_display_color = {
        en = 'Mode Color',
    },
    none = {
        en = 'None',
    },
    light_attack = {
        en = 'Light Attack',
    },
    heavy_attack = {
        en = 'Heavy Attack',
    },
    special_action = {
        en = 'Special Action',
    },
    special_action_heavy = {
        en = 'Special Action Heavy',
    },
    block = {
        en = 'Block',
    },
    push = {
        en = 'Push',
    },
    push_attack = {
        en = 'Push Attack',
    },
    no_repeat = {
        en = 'No Repeat (Switch to Previous Mode)',
    },
    standard = {
        en = 'Standard',
    },
    charged = {
        en = 'Charged',
    },
    special = {
        en = 'Special',
    },
    special_charged = {
        en = 'Special Charged',
    },
}

for i = 1, Profiles.sequence_step_count do
    localizations[Profiles.sequence_step_prefix .. i] = { en = 'Sequence Step ' .. i }
end

for i = 1, 4 do
    local mode = 'mode_' .. i

    localizations[mode] = { en = 'Mode ' .. i }
    localizations[mode .. '_select'] = { en = 'Activate Mode ' .. i }
end

return localizations
