-- Factory that builds a stats-list view class on top of BaseView, shared across
-- the stats mods. Each mod passes its mod instance and config; the returned
-- class already carries the shared grid/search/input-legend/close/update plumbing.
-- Subclasses override the virtual methods: _on_init, _on_update, _setup_entries,
-- _present_detail, and optionally _cb_on_list_presented / cb_on_list_entry_left_pressed.
local function make_view(mod, config)
    local class_name = config.class_name
    local prefix = config.prefix
    local SharedUtils = config.shared_utils
    local icon_packages = config.icon_packages
    local definitions_path = config.definitions_path
    local list_blueprints_path = config.list_blueprints_path
    local single_detail = config.single_detail
    -- When set, skip the left list + search and show only the detail panel.

    local mod_name = mod:get_name()
    local SharedSettings = nil
    local function settings_module()
        if not SharedSettings then
            SharedSettings = mod:io_dofile(mod_name .. '/scripts/mods/' .. mod_name .. '/shared/shared_settings')
        end
        return SharedSettings
    end

    local ViewElementInputLegend =
        mod:original_require('scripts/ui/view_elements/view_element_input_legend/view_element_input_legend')
    local ViewElementGrid = mod:original_require('scripts/ui/view_elements/view_element_grid/view_element_grid')
    mod:original_require('scripts/ui/views/base_view')

    local View = class(class_name, 'BaseView')

    function View:ui_renderer()
        return self._ui_renderer
    end

    function View:init(settings, context)
        self._definitions = mod:io_dofile(definitions_path)
        View.super.init(self, self._definitions, settings)

        self._pass_draw = false
        self._last_search_text = ''
        self:_on_init(settings, context)
    end

    -- Virtual: subclasses set up mod-specific state.
    function View:_on_init(settings, context) end

    function View:on_enter()
        View.super.on_enter(self)

        -- Close any other stats view that's open so these don't stack.
        local ui_manager = Managers.ui
        if ui_manager then
            local names = SharedUtils.stats_view_names
            for i = 1, #names do
                local name = names[i]
                if name ~= self.view_name and ui_manager:view_active(name) then
                    ui_manager:close_view(name)
                end
            end
        end
        if icon_packages then
            self._loaded_icon_packages = SharedUtils.load_icon_packages(mod, icon_packages)
        end

        self:_setup_input_legend()
        if not single_detail then
            self:_setup_search()
            self:_setup_list_grid()
        end
        self:_setup_detail_grid()
        if not single_detail then
            self:_setup_entries()
        end

        -- Settings views need the focused-widget draw hook (see shared_settings).
        if self:_setting_ids() then
            settings_module().install_focus_hook(mod, self.view_name .. '_list_grid')
        end
    end

    function View:_present_list(entries)
        self._filtered_list = entries

        local blueprints = mod:io_dofile(list_blueprints_path)(self:_list_width())
        local left_click_callback = callback(self, 'cb_on_list_entry_left_pressed')
        local on_present_callback = callback(self, '_cb_on_list_presented')

        self._list_grid:present_grid_layout(
            entries,
            blueprints,
            left_click_callback,
            nil,
            nil,
            'down',
            on_present_callback
        )
    end

    function View:_setup_search()
        local search_widget = self._widgets_by_name[prefix .. '_search']
        if search_widget then
            search_widget.content.input_text = ''
            search_widget.content.placeholder_text = mod:localize('search_placeholder')

            local style = search_widget.style
            if style then
                style.background.color = { 255, 30, 30, 30 }
                style.baseline.color = Color.terminal_text_body(100, true)
            end
        end
    end

    function View:_setup_input_legend()
        self._input_legend_element = self:_add_element(ViewElementInputLegend, 'input_legend', 10)
        local legend_inputs = self._definitions.legend_inputs

        for i = 1, #legend_inputs do
            local legend_input = legend_inputs[i]
            local on_pressed_callback = legend_input.on_pressed_callback
                and callback(self, legend_input.on_pressed_callback)

            self._input_legend_element:add_entry(
                legend_input.display_name,
                legend_input.input_action,
                legend_input.visibility_function,
                on_pressed_callback,
                legend_input.alignment
            )
        end
    end

    -- Grid elements ----------------------------------------------------------

    function View:_setup_list_grid()
        if not single_detail and self._list_grid then
            self._list_grid = nil
            self:_remove_element('list_grid')
        end

        local grid_settings = self._definitions.list_grid_settings
        self._list_grid = self:_add_element(ViewElementGrid, 'list_grid', 10, grid_settings)
        self:_update_list_grid_position()
    end

    function View:_setup_detail_grid()
        if self._detail_grid then
            self._detail_grid = nil
            self:_remove_element('detail_grid')
        end

        local grid_settings = self._definitions.detail_grid_settings
        self._detail_grid = self:_add_element(ViewElementGrid, 'detail_grid', 10, grid_settings)
        self:_update_detail_grid_position()
    end

    function View:_update_list_grid_position()
        if not self._list_grid then
            return
        end

        local position = self:_scenegraph_world_position(prefix .. '_list_content')
        if position then
            self._list_grid:set_pivot_offset(position[1], position[2])
        end
    end

    function View:_update_detail_grid_position()
        if not self._detail_grid then
            return
        end

        local position = self:_scenegraph_world_position(prefix .. '_detail_content')
        if position then
            self._detail_grid:set_pivot_offset(position[1], position[2])
        end
    end

    function View:_list_width()
        local grid_settings = self._definitions.list_grid_settings
        return grid_settings and grid_settings.grid_size[1] or 480
    end

    function View:_detail_width()
        local grid_settings = self._definitions.detail_grid_settings
        return grid_settings and grid_settings.grid_size[1] or 600
    end

    -- List selection ---------------------------------------------------------

    function View:_setup_entries()
        local setting_ids = self:_setting_ids()
        if not setting_ids then
            return
        end
        local width = self:_list_width()
        local entries = settings_module().build_entries(mod, setting_ids)
        local blueprints = settings_module().make_blueprints(width)
        local left_click_callback = callback(self, 'cb_on_list_entry_left_pressed')
        self._list_grid:present_grid_layout(entries, blueprints, left_click_callback)
    end

    function View:_cb_on_list_presented()
        local entries = self._filtered_list
        if not entries or #entries == 0 then
            self:_present_detail(nil)
            return
        end

        self._list_grid:select_grid_index(1)
        self:_select_entry(entries[1])
    end

    -- Settings rows activate internally; list clicks do nothing in settings mode.
    function View:cb_on_list_entry_left_pressed(widget, element)
        if not self:_setting_ids() then
            self:_select_entry(element)
        end
    end

    function View:_select_entry(entry)
        if self:_setting_ids() then
            return
        end
        if entry and not entry.disabled then
            local index = self._list_grid:index_by_element(entry) or self._list_grid:selected_grid_index()
            if index then
                self._list_grid:select_grid_index(index)
            end
        end
        self:_present_detail(entry)
    end

    -- Detail panel -----------------------------------------------------------

    -- Virtual: subclasses render the selected entry into the detail grid.
    function View:_present_detail(entry) end

    function View:cb_on_detail_entry_left_pressed(widget, element)
        return
    end

    function View:cb_on_copy_pressed()
        local entry = self._detail_entry
        if not entry then
            return
        end
        local text = SharedUtils.layout_to_markdown(entry.name, self._detail_layout)
        SharedUtils.copy_to_clipboard(text)
    end

    -- Callbacks --------------------------------------------------------------

    function View:cb_on_close_pressed()
        Managers.ui:close_view(self.view_name)
    end

    function View:update(dt, t, input_service)
        self:_on_update(dt, t, input_service)

        -- Synced here, not in _on_update, so subclasses can override _on_update.
        if self:_setting_ids() then
            settings_module().sync_focus(self._list_grid)
        end

        if not single_detail and not self:_setting_ids() then
            local search_widget = self._widgets_by_name[prefix .. '_search']
            if search_widget then
                local current_search = search_widget.content.input_text or ''
                if current_search ~= self._last_search_text then
                    self._last_search_text = current_search
                    self:_setup_entries()
                end
            end
        end

        return View.super.update(self, dt, t, input_service)
    end

    -- The setting_ids this view registered, if any.
    function View:_setting_ids()
        return SharedUtils.stats_view_setting_ids and SharedUtils.stats_view_setting_ids[self.view_name]
    end

    -- Virtual: subclasses with per-frame work override this.
    function View:_on_update(dt, t, input_service) end

    function View:on_exit()
        if self._input_legend_element then
            self._input_legend_element = nil
            self:_remove_element('input_legend')
        end

        if self._list_grid then
            self._list_grid = nil
            self:_remove_element('list_grid')
        end

        if self._detail_grid then
            self._detail_grid = nil
            self:_remove_element('detail_grid')
        end

        if self._loaded_icon_packages then
            SharedUtils.release_icon_packages(mod, self._loaded_icon_packages)
            self._loaded_icon_packages = nil
        end

        View.super.on_exit(self)
    end

    return View
end

return make_view
