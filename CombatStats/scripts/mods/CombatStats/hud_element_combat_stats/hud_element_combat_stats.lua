local mod = get_mod('CombatStats')

local Definitions =
    mod:io_dofile('CombatStats/scripts/mods/CombatStats/hud_element_combat_stats/hud_element_combat_stats_definitions')

local HudElementCombatStats = class('HudElementCombatStats', 'HudElementBase')

function HudElementCombatStats:init(parent, draw_layer, start_scale)
    HudElementCombatStats.super.init(self, parent, draw_layer, start_scale, Definitions)
end

function HudElementCombatStats:update(dt, t, ui_renderer, render_settings, input_service)
    HudElementCombatStats.super.update(self, dt, t, ui_renderer, render_settings, input_service)

    if not mod:get('show_hud_overlay') then
        return
    end

    local tracker = mod.tracker
    if not tracker or not tracker:is_enabled(true) then
        return
    end

    local widget = self._widgets_by_name.session_stats
    if not widget then
        return
    end

    local session_data = tracker:get_session_stats()
    local stats = session_data.stats
    local duration = session_data.duration

    widget.content.duration_text = string.format('%s: %.1fs', mod:localize('time'), duration)

    local kill_text = string.format('%s: %d', mod:localize('kills'), stats.total_kills)
    if next(stats.kills) then
        local kill_details = {}
        for breed_type, count in pairs(stats.kills) do
            if breed_type ~= 'horde' then
                table.insert(kill_details, string.format('%s:%d', breed_type:sub(1, 1):upper(), count))
            end
        end
        if #kill_details > 0 then
            kill_text = kill_text .. ' (' .. table.concat(kill_details, ' ') .. ')'
        end
    end
    widget.content.kills_text = kill_text

    if duration > 0 and stats.total_damage > 0 then
        local dps = stats.total_damage / duration
        widget.content.dps_text = string.format('%.0f %s', dps, mod:localize('dps'))
    else
        widget.content.dps_text = string.format('0 %s', mod:localize('dps'))
    end

    widget.content.damage_text =
        string.format('%s: %d (%d)', mod:localize('damage'), stats.total_damage, stats.total_hits)

    local damage_types = {}
    if stats.melee_damage > 0 then
        local pct = (stats.melee_damage / stats.total_damage * 100)
        local crit_text = ''
        if stats.melee_crit_hits > 0 and stats.melee_hits > 0 then
            local crit_rate = (stats.melee_crit_hits / stats.melee_hits * 100)
            crit_text = string.format(' (%.0f%%)', crit_rate)
        end
        table.insert(damage_types, {
            icon = 'content/ui/materials/icons/weapons/actions/linesman',
            color = Color.gray(255, true),
            text = string.format('%.0f%%%s', pct, crit_text),
        })
    end
    if stats.ranged_damage > 0 then
        local pct = (stats.ranged_damage / stats.total_damage * 100)
        local crit_text = ''
        if stats.ranged_crit_hits > 0 and stats.ranged_hits > 0 then
            local crit_rate = (stats.ranged_crit_hits / stats.ranged_hits * 100)
            crit_text = string.format(' (%.0f%%)', crit_rate)
        end
        table.insert(damage_types, {
            icon = 'content/ui/materials/icons/weapons/actions/hipfire',
            color = { 255, 139, 101, 69 },
            text = string.format('%.0f%%%s', pct, crit_text),
        })
    end
    if stats.explosion_damage > 0 then
        local pct = (stats.explosion_damage / stats.total_damage * 100)
        table.insert(damage_types, {
            icon = 'content/ui/materials/icons/throwables/hud/small/party_grenade',
            color = { 255, 255, 100, 0 },
            text = string.format('%.0f%%', pct),
        })
    end
    if stats.companion_damage > 0 then
        local pct = (stats.companion_damage / stats.total_damage * 100)
        table.insert(damage_types, {
            icon = 'content/ui/materials/icons/throwables/hud/adamant_whistle',
            color = { 255, 100, 149, 237 },
            text = string.format('%.0f%%', pct),
        })
    end

    widget.content.damage_type_1_icon = damage_types[1] and damage_types[1].icon or nil
    widget.style.damage_type_1_icon.color = damage_types[1] and damage_types[1].color or Color.white(255, true)
    widget.content.damage_type_1_text = damage_types[1] and damage_types[1].text or ''
    widget.content.damage_type_2_icon = damage_types[2] and damage_types[2].icon or nil
    widget.style.damage_type_2_icon.color = damage_types[2] and damage_types[2].color or Color.white(255, true)
    widget.content.damage_type_2_text = damage_types[2] and damage_types[2].text or ''
    widget.content.damage_type_3_icon = damage_types[3] and damage_types[3].icon or nil
    widget.style.damage_type_3_icon.color = damage_types[3] and damage_types[3].color or Color.white(255, true)
    widget.content.damage_type_3_text = damage_types[3] and damage_types[3].text or ''
    widget.content.damage_type_4_icon = damage_types[4] and damage_types[4].icon or nil
    widget.style.damage_type_4_icon.color = damage_types[4] and damage_types[4].color or Color.white(255, true)
    widget.content.damage_type_4_text = damage_types[4] and damage_types[4].text or ''

    local buff_types = {}
    if stats.bleed_damage > 0 then
        local pct = (stats.bleed_damage / stats.total_damage * 100)
        table.insert(buff_types, {
            icon = 'content/ui/materials/icons/presets/preset_13',
            color = Color.red(255, true),
            text = string.format('%.0f%%', pct),
        })
    end
    if stats.burn_damage > 0 then
        local pct = (stats.burn_damage / stats.total_damage * 100)
        table.insert(buff_types, {
            icon = 'content/ui/materials/icons/presets/preset_20',
            color = { 255, 255, 140, 0 },
            text = string.format('%.0f%%', pct),
        })
    end
    if stats.toxin_damage > 0 then
        local pct = (stats.toxin_damage / stats.total_damage * 100)
        table.insert(buff_types, {
            icon = 'content/ui/materials/icons/circumstances/havoc/havoc_mutator_nurgle',
            color = { 255, 50, 205, 50 },
            text = string.format('%.0f%%', pct),
        })
    end

    widget.content.buff_type_1_icon = buff_types[1] and buff_types[1].icon or nil
    widget.style.buff_type_1_icon.color = buff_types[1] and buff_types[1].color or Color.white(255, true)
    widget.content.buff_type_1_text = buff_types[1] and buff_types[1].text or ''
    widget.content.buff_type_2_icon = buff_types[2] and buff_types[2].icon or nil
    widget.style.buff_type_2_icon.color = buff_types[2] and buff_types[2].color or Color.white(255, true)
    widget.content.buff_type_2_text = buff_types[2] and buff_types[2].text or ''
    widget.content.buff_type_3_icon = buff_types[3] and buff_types[3].icon or nil
    widget.style.buff_type_3_icon.color = buff_types[3] and buff_types[3].color or Color.white(255, true)
    widget.content.buff_type_3_text = buff_types[3] and buff_types[3].text or ''
end

function HudElementCombatStats:draw(dt, t, ui_renderer, render_settings, input_service)
    if not mod:get('show_hud_overlay') then
        return
    end

    local tracker = mod.tracker
    if not tracker or not tracker:is_enabled(true) then
        return
    end

    HudElementCombatStats.super.draw(self, dt, t, ui_renderer, render_settings, input_service)
end

return HudElementCombatStats
