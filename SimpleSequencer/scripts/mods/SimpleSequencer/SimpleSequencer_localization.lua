local localizations = {
    mod_name = {
        en = 'Simple Sequencer',
    },
    mod_description = {
        en = 'Select a sequence mode with keys, then hold primary to execute it.',
    },
    global_melee = {
        en = 'All Melee Weapons',
    },
    global_ranged = {
        en = 'All Ranged Weapons',
    },
    general_settings = {
        en = 'General Settings',
    },
    hud_enabled = {
        en = 'Show Mode HUD',
    },
    reset_on_interrupt = {
        en = 'Reset On Manual Interrupt',
    },
    mode_keybinds = {
        en = 'Modes and Keybinds',
    },
    editing_mode = {
        en = 'Mode to Configure',
    },
    melee_settings = {
        en = 'Melee Sequence',
    },
    ranged_settings = {
        en = 'Ranged Sequence',
    },
    melee_weapon_selection = {
        en = 'Weapon Override',
    },
    ranged_weapon_selection = {
        en = 'Weapon Override',
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
    ranged_rate_of_fire_hip = {
        en = 'Hipfire Attack Delay (ms)',
    },
    ranged_rate_of_fire_ads = {
        en = 'ADS Attack Delay (ms)',
    },
    select_mode_previous = {
        en = 'Previous Mode',
    },
    select_mode_next = {
        en = 'Next Mode',
    },
    select_mode_toggle = {
        en = 'Toggle Last / Current Mode',
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
    special_heavy = {
        en = 'Special Heavy',
    },
    special_invert = {
        en = 'Special Invert',
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
    wield = {
        en = 'Wield',
    },
    no_repeat = {
        en = 'Halt on Completion',
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
    special_standard = {
        en = 'Special + Standard',
    },
}

for i = 1, 12 do
    localizations['sequence_step_' .. i] = { en = 'Sequence Step ' .. i }
end

for i = 1, 4 do
    local mode = 'mode_' .. i

    localizations[mode] = { en = 'Mode ' .. i }
    localizations[mode .. '_select'] = { en = 'Activate Mode ' .. i }
end

return localizations
