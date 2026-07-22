local mod = get_mod('CharacterStats')

local SharedUtils = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/shared/shared_utils')
local Builder = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/character_stats_builder')
local make_view = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/shared/shared_view_base')
local make_detail_blueprints =
    mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/character_stats_view/character_stats_detail_blueprints')

local CharacterStatsView = make_view(mod, {
    class_name = 'CharacterStatsView',
    prefix = 'character_stats',
    shared_utils = SharedUtils,
    single_detail = true,
    definitions_path = 'CharacterStats/scripts/mods/CharacterStats/character_stats_view/character_stats_view_definitions',
    list_blueprints_path = 'CharacterStats/scripts/mods/CharacterStats/character_stats_view/character_stats_view_blueprints',
})

function CharacterStatsView:_on_init(settings, context)
    self._detail_entry = true
    self._detail_built = false
end

-- Detail panel: render the builder's record list through the shared stat/section/spacer
-- blueprints. No left list in single_detail mode, so on_enter kicks off the build directly.
function CharacterStatsView:_present_detail()
    if not self._detail_grid then
        return
    end

    self._detail_entry = true
    local width = self:_detail_width()
    local blueprints = make_detail_blueprints(width)

    local layout = {}
    local records, header_text, subtext = Builder.build_stats()

    if header_text then
        layout[#layout + 1] = {
            widget_type = 'header_icon',
            text = header_text,
            subtext = subtext or '',
            subtext_color = Color.terminal_text_body_sub_header(255, true),
            color = Color.terminal_text_header(255, true),
        }
        layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }
    end

    local stripe_count = 0
    for i = 1, #records do
        local record = records[i]
        local rtype = record.type
        if rtype == 'stat' then
            layout[#layout + 1] = {
                widget_type = 'stat',
                label = record.label,
                value = record.value,
                label_color = record.label_color,
                value_color = record.value_color,
                indent = record.indent or 0,
                stripe = stripe_count % 2 == 1,
            }
            stripe_count = stripe_count + 1
        else
            layout[#layout + 1] = {
                widget_type = rtype,
                text = record.text,
                subtext = record.subtext,
                color = record.color,
                subtext_color = record.subtext_color,
                size = record.size,
                indent = record.indent,
                level = record.level,
            }
            stripe_count = 0
        end
    end

    -- Real data is present once build_stats returns records beyond the placeholder. The
    -- builder returns a single placeholder stat when the player unit isn't loaded yet.
    self._detail_built = #records > 1 or (#records == 1 and records[1].value ~= mod:localize('no_character'))

    local left_click_callback = callback(self, 'cb_on_detail_entry_left_pressed')
    self._detail_layout = layout
    self._detail_grid:present_grid_layout(layout, blueprints, left_click_callback)
end

-- Build the detail panel once it's safe to do so. The local player unit and its buff
-- extension aren't available the instant the view opens (the buff snapshot only populates
-- after a fixed_update cycle), so we retry each frame until build_stats returns real data,
-- then stop. No periodic refresh: we only rebuild on open, on setting change, or on weapon
-- swap (which the user does by closing/reopening the view).
function CharacterStatsView:_on_update(dt, t, input_service)
    if self._detail_built then
        return
    end
    if not self._detail_entry or not self._detail_grid then
        return
    end
    -- pcall: game state can transition under us (e.g. leaving a mission) and briefly make
    -- the player unit/extensions unavailable; never let a build error tear down the view.
    pcall(function()
        self:_present_detail()
    end)
end

return CharacterStatsView
