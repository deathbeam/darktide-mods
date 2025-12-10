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
    if not tracker or not tracker:is_enabled() then
        return
    end

    local widget = self._widgets_by_name.session_stats
    if not widget then
        return
    end

    local duration = tracker:_get_session_duration()
    local stats = tracker:_calculate_session_stats()

    widget.content.duration_text = string.format('Combat Time: %.1fs', duration)

    local kill_text = string.format('Kills: %d', stats.total_kills)
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
        widget.content.dps_text = string.format('DPS: %.0f', dps)
    else
        widget.content.dps_text = 'DPS: 0'
    end

    widget.content.damage_text = string.format('Damage: %d', stats.total_damage)
    widget.content.hits_text = string.format('Hits: %d', stats.total_hits)

    local breakdown_parts = {}
    if stats.melee_damage > 0 then
        local pct = (stats.melee_damage / stats.total_damage * 100)
        table.insert(breakdown_parts, string.format('M:%.0f%%', pct))
    end
    if stats.ranged_damage > 0 then
        local pct = (stats.ranged_damage / stats.total_damage * 100)
        table.insert(breakdown_parts, string.format('R:%.0f%%', pct))
    end
    if stats.buff_damage > 0 then
        local pct = (stats.buff_damage / stats.total_damage * 100)
        table.insert(breakdown_parts, string.format('B:%.0f%%', pct))
    end

    if stats.melee_crit_hits > 0 and stats.melee_hits > 0 then
        local crit_rate = (stats.melee_crit_hits / stats.melee_hits * 100)
        table.insert(breakdown_parts, string.format('MCrit:%.0f%%', crit_rate))
    end
    if stats.ranged_crit_hits > 0 and stats.ranged_hits > 0 then
        local crit_rate = (stats.ranged_crit_hits / stats.ranged_hits * 100)
        table.insert(breakdown_parts, string.format('RCrit:%.0f%%', crit_rate))
    end

    widget.content.breakdown_text = table.concat(breakdown_parts, '  ')
end

function HudElementCombatStats:draw(dt, t, ui_renderer, render_settings, input_service)
    if not mod:get('show_hud_overlay') then
        return
    end

    local tracker = mod.tracker
    if not tracker or not tracker:is_enabled() then
        return
    end

    HudElementCombatStats.super.draw(self, dt, t, ui_renderer, render_settings, input_service)
end

return HudElementCombatStats
