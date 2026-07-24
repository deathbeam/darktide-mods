local CheckboxPassTemplates = require('scripts/ui/pass_templates/checkbox_pass_templates')
local DropdownPassTemplates = require('scripts/ui/pass_templates/dropdown_pass_templates')
local SliderPassTemplates = require('scripts/ui/pass_templates/slider_pass_templates')
local UIFontSettings = require('scripts/managers/ui/ui_font_settings')

local CONTROL_HEIGHT = 48
local LABEL_HEIGHT = 20
local MAX_VISIBLE_OPTIONS = 5

local label_style = table.clone(UIFontSettings.header_4)
label_style.font_size = 16
label_style.text_color = Color.terminal_text_body(255, true)
label_style.text_vertical_alignment = 'bottom'
label_style.text_horizontal_alignment = 'left'
label_style.offset = { 0, 0, 2 }

local SharedSettings = {}

-- Each setting is a label row + the game's control (checkbox/slider/dropdown) at full row
-- width. We reuse the game's pass templates but write our own init/update, so no OptionsView
-- focus coupling leaks in.
function SharedSettings.make_blueprints(width)
    local blueprints = {}

    blueprints.setting = {
        size = { width, CONTROL_HEIGHT },
        pass_template_function = function(_, entry)
            local passes = {}
            local control_type = entry.control_type
            if control_type == 'checkbox' then
                passes = CheckboxPassTemplates.settings_checkbox(width, CONTROL_HEIGHT, width, 2, true)
            elseif control_type == 'value_slider' then
                -- header_width (width - settings_area_width) holds the value text and must
                -- be >= ~100 or its offset goes negative.
                local slider_area = width - 110
                passes = SliderPassTemplates.settings_value_slider(width, CONTROL_HEIGHT, slider_area, true)
            elseif control_type == 'dropdown' then
                local options = entry.options or {}
                local num_visible = math.min(#options, MAX_VISIBLE_OPTIONS)
                passes = DropdownPassTemplates.settings_dropdown(width, CONTROL_HEIGHT, width, num_visible, true)
            end
            return passes
        end,
        init = function(_, widget, entry)
            local content = widget.content
            content.entry = entry

            if entry.control_type == 'checkbox' then
                content.option_1 = Localize('loc_setting_checkbox_on')
                content.option_2 = Localize('loc_setting_checkbox_off')
            elseif entry.control_type == 'value_slider' then
                content.area_length = width - 110
                content.step_size = entry.normalized_step_size
                content.apply_on_drag = entry.apply_on_drag and true
                local value = entry.get_function(entry)
                content.slider_value = math.normalize_01(value, entry.min_value, entry.max_value)
            elseif entry.control_type == 'dropdown' then
                local options = entry.options or {}
                local options_by_value = {}
                for i = 1, #options do
                    options_by_value[options[i].value] = options[i]
                end
                content.options = options
                content.options_by_value = options_by_value
                content.num_visible_options = math.min(#options, MAX_VISIBLE_OPTIONS)
                content.area_length = CONTROL_HEIGHT * content.num_visible_options
                content.scroll_length = math.max(CONTROL_HEIGHT * #options - content.area_length, 0)
                content.scroll_amount = content.scroll_length > 0 and (CONTROL_HEIGHT / content.scroll_length) or 0
            end
        end,
        update = function(parent, widget, input_service, dt, t)
            local content = widget.content
            local entry = content.entry
            local control_type = entry.control_type
            local hotspot = content.hotspot

            if control_type == 'checkbox' then
                local value = entry.get_function(entry)
                if hotspot.on_pressed then
                    value = not value
                    entry.on_activated(value, entry)
                end
                content.option_hotspot_1.is_selected = value
                content.option_hotspot_2.is_selected = not value
            elseif control_type == 'value_slider' then
                local drag_active = content.drag_active
                local slider_value = content.slider_value
                if drag_active and slider_value ~= content.previous_slider_value then
                    entry.on_activated(entry.explode_function(slider_value, entry), entry)
                elseif input_service:get('confirm_pressed') and (hotspot.is_focused or hotspot.is_selected) then
                    entry.on_activated(entry.explode_function(slider_value, entry), entry)
                end
                if not drag_active then
                    local value = entry.get_function(entry)
                    content.slider_value = math.normalize_01(value, entry.min_value, entry.max_value)
                end
                content.previous_slider_value = content.slider_value
                content.value_text = entry.format_value_function(entry.explode_function(content.slider_value, entry))
            elseif control_type == 'dropdown' then
                local options = content.options
                local style = widget.style

                if hotspot.on_pressed then
                    content.exclusive_focus = not content.exclusive_focus
                    content.anim_exclusive_focus_progress = content.exclusive_focus and 1 or 0
                    content.selected_index = nil
                end

                local focused = content.exclusive_focus
                content.grow_downwards = true
                local value = entry.get_function(entry)
                local current_index = 1
                for i = 1, #options do
                    if options[i].value == value then
                        current_index = i
                        break
                    end
                end
                content.value_text = options[current_index].display_name

                if focused then
                    local selected_index = content.selected_index or current_index

                    if input_service:get('navigate_up_continuous') then
                        selected_index = math.max(1, selected_index - 1)
                    elseif input_service:get('navigate_down_continuous') then
                        selected_index = math.min(#options, selected_index + 1)
                    end

                    -- left_pressed lands on the hovered option row this frame; on_pressed
                    -- is only set on the next draw.
                    local end_index = math.min(content.num_visible_options, #options)
                    for i = 1, end_index do
                        local option_hotspot = content['option_hotspot_' .. i]
                        if option_hotspot and option_hotspot.is_hover and input_service:get('left_pressed') then
                            selected_index = i
                            entry.on_activated(options[i].value, entry)
                            content.exclusive_focus = false
                            content.anim_exclusive_focus_progress = 0
                            break
                        end
                    end

                    if input_service:get('confirm_pressed') and not hotspot.on_pressed then
                        entry.on_activated(options[selected_index].value, entry)
                        content.exclusive_focus = false
                        content.anim_exclusive_focus_progress = 0
                    end

                    -- Don't treat a click on an option row as a click-away close.
                    local cursor_on_option = false
                    for i = 1, end_index do
                        local option_hotspot = content['option_hotspot_' .. i]
                        if option_hotspot and option_hotspot.is_hover then
                            cursor_on_option = true
                            break
                        end
                    end
                    if input_service:get('left_pressed') and not hotspot.is_hover and not cursor_on_option then
                        content.exclusive_focus = false
                        content.anim_exclusive_focus_progress = 0
                    end

                    content.selected_index = selected_index

                    for i = 1, end_index do
                        local option_hotspot = content['option_hotspot_' .. i]
                        if option_hotspot then
                            option_hotspot.is_selected = i == selected_index
                        end
                        local y = CONTROL_HEIGHT * i
                        if style['option_hotspot_' .. i] then
                            style['option_hotspot_' .. i].offset[2] = y
                        end
                        if style['option_text_' .. i] then
                            style['option_text_' .. i].offset[2] = y
                            content['option_text_' .. i] = options[i].display_name
                        end
                    end
                end
            end
        end,
    }

    blueprints.setting_label = {
        size = { width, LABEL_HEIGHT },
        pass_template = {
            {
                pass_type = 'text',
                value_id = 'text',
                style = label_style,
                value = '',
            },
        },
        init = function(_, widget, entry)
            widget.content.text = entry.display_name or ''
        end,
    }

    return blueprints
end

-- DMF localizes titles and option texts during widget init, so entries built from its
-- store are fully localized for free.
local function find_mod_widgets(mod)
    local dmf = get_mod and get_mod('DMF')
    if not dmf or not dmf.options_widgets_data then
        return nil
    end
    local mod_name = mod:get_name()
    for i = 1, #dmf.options_widgets_data do
        local widgets = dmf.options_widgets_data[i]
        local header = widgets and widgets[1]
        if header and header.mod_name == mod_name then
            return widgets
        end
    end
    return nil
end

function SharedSettings.build_entries(mod, setting_ids)
    local entries = {}
    if not setting_ids or #setting_ids == 0 then
        return entries
    end

    local widgets = find_mod_widgets(mod)
    if not widgets then
        return entries
    end

    local by_id = {}
    for i = 2, #widgets do
        local w = widgets[i]
        if w and w.setting_id then
            by_id[w.setting_id] = w
        end
    end

    local function add(widget_data)
        entries[#entries + 1] = {
            widget_type = 'setting_label',
            display_name = widget_data.title or widget_data.setting_id,
        }

        local entry = {
            on_activated = function(new_value)
                mod:set(widget_data.setting_id, new_value, true)
                return true
            end,
            get_function = function()
                return mod:get(widget_data.setting_id)
            end,
        }

        local wtype = widget_data.type
        if wtype == 'checkbox' then
            entry.widget_type = 'setting'
            entry.control_type = 'checkbox'
            entry.default_value = widget_data.default_value
        elseif wtype == 'dropdown' then
            entry.widget_type = 'setting'
            entry.control_type = 'dropdown'
            entry.default_value = widget_data.default_value
            local opts = widget_data.options or {}
            entry.options = {}
            for i = 1, #opts do
                local src = opts[i]
                entry.options[i] = {
                    value = src.value,
                    display_name = src.text,
                }
            end
        elseif wtype == 'numeric' then
            entry.widget_type = 'setting'
            entry.control_type = 'value_slider'
            entry.default_value = widget_data.default_value
            entry.min_value = widget_data.range[1]
            entry.max_value = widget_data.range[2]
            local value_range = entry.max_value - entry.min_value
            local decimals = widget_data.decimals_number or 0
            local step = math.pow(10, -decimals)
            entry.step_size_value = step
            entry.normalized_step_size = step / value_range
            entry.explode_function = function(normalized)
                local v = entry.min_value + normalized * value_range
                return math.round(v / step) * step
            end
            entry.format_value_function = function(value)
                if decimals > 0 then
                    return string.format('%.' .. decimals .. 'f', value)
                end
                return string.format('%d', value)
            end
            entry.apply_on_drag = true
        end

        entries[#entries + 1] = entry
    end

    for i = 1, #setting_ids do
        local w = by_id[setting_ids[i]]
        if w then
            add(w)
        end
    end

    return entries
end

-- Draw the focused widget last with real input, null the rest, so neighbors can't steal
-- clicks and the foldout renders on top. Scoped to one grid.
function SharedSettings.install_focus_hook(mod, element_view_id)
    local flag = '_shared_settings_focus_hook_' .. element_view_id
    if rawget(_G, flag) then
        return
    end
    _G[flag] = true

    mod:hook(
        CLASS.ViewElementGrid,
        '_draw_grid',
        function(func, self, dt, t, ui_renderer, input_service, render_settings)
            local focused = self._shared_settings_focused_widget
            if not focused or self._element_view_id ~= element_view_id then
                return func(self, dt, t, ui_renderer, input_service, render_settings)
            end
            local widgets = self._grid_widgets
            local null_service = input_service:null_service()
            local saved_widgets = widgets
            local others = {}
            for i = 1, #widgets do
                if widgets[i] ~= focused then
                    others[#others + 1] = widgets[i]
                end
            end
            self._grid_widgets = others
            local ok, err = pcall(func, self, dt, t, ui_renderer, null_service, render_settings)
            self._grid_widgets = saved_widgets
            if not ok then
                error(err)
            end
            self._grid_widgets = { focused }
            ok, err = pcall(func, self, dt, t, ui_renderer, input_service, render_settings)
            self._grid_widgets = saved_widgets
            if not ok then
                error(err)
            end
        end
    )
end

function SharedSettings.sync_focus(grid)
    if not grid then
        return
    end
    local widgets = grid:widgets()
    local focused_widget = nil
    for i = 1, #widgets do
        local widget = widgets[i]
        local content = widget.content
        if content.exclusive_focus then
            focused_widget = widget
        end
        widget.offset[3] = (widget == focused_widget) and 90 or 0
    end
    grid._shared_settings_focused_widget = focused_widget
end

return SharedSettings
