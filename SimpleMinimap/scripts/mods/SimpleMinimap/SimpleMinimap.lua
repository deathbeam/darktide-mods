local mod = get_mod('SimpleMinimap')

-- Settings cache
mod.settings = {}

local function _collect_settings()
    mod.settings.size = mod:get('minimap_size') or 200
    mod.settings.max_range = mod:get('minimap_max_range') or 50
    mod.settings.background_opacity = mod:get('background_opacity') or 128
    mod.settings.show_teammates = mod:get('show_teammates')
    mod.settings.show_class_icons = mod:get('show_class_icons')
    mod.settings.show_objectives = mod:get('show_objectives')
    mod.settings.show_pings = mod:get('show_pings')
    mod.settings.show_enemies = mod:get('show_enemies')
    mod.settings.enemy_radar_range = mod:get('enemy_radar_range') or 30
    mod.settings.show_enemy_monsters = mod:get('show_enemy_monsters')
    mod.settings.show_enemy_elites = mod:get('show_enemy_elites')
    mod.settings.show_enemy_specials = mod:get('show_enemy_specials')
    mod.settings.show_enemy_horde = mod:get('show_enemy_horde')
    mod.settings.show_enemy_roamer = mod:get('show_enemy_roamer')
end

-- Register HUD element
mod:add_require_path('SimpleMinimap/scripts/mods/SimpleMinimap/hud_element_simple_minimap')

mod:hook('UIHud', 'init', function(func, self, elements, visibility_groups, params)
    if not table.find_by_key(elements, 'class_name', 'HudElementSimpleMinimap') then
        table.insert(elements, {
            class_name = 'HudElementSimpleMinimap',
            filename = 'SimpleMinimap/scripts/mods/SimpleMinimap/hud_element_simple_minimap',
            use_hud_scale = true,
            visibility_groups = { 'alive', 'communication_wheel' },
        })
    end

    return func(self, elements, visibility_groups, params)
end)

mod.on_all_mods_loaded = function()
    _collect_settings()
end

mod.on_setting_changed = function()
    _collect_settings()
end
