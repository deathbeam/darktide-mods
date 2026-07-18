local mod = get_mod('WeaponStats')
local Text = mod:original_require('scripts/utilities/ui/text')
local UIFontSettings = mod:original_require('scripts/managers/ui/ui_font_settings')

local Shared = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/shared/shared_detail_blueprints')

local INDENT_PX = 18
local STAT_ROW_HEIGHT = 21
local COLOR_STRIPE = Color.terminal_grid_background(60, true)
local STAT_LABEL_FONT_SIZE = 16
local STAT_VALUE_FONT_SIZE = 16
local STAT_ICON_SIZE = 32
local STAT_ICON_GAP = 8
local STAT_VALUE_TOP_OFFSET = 20
local STAT_WRAP_PAD = 6

local CHAIN_ICON_SIZE = 28
local CHAIN_ICON_SPACING = 6
local CHAIN_ROW_HEIGHT = 34

local GESTALT_ICONS = {
    activate = 'content/ui/materials/icons/weapons/actions/activate',
    ads = 'content/ui/materials/icons/weapons/actions/ads',
    brace = 'content/ui/materials/icons/weapons/actions/brace',
    charge = 'content/ui/materials/icons/weapons/actions/charge',
    defence = 'content/ui/materials/icons/weapons/actions/defence',
    flashlight = 'content/ui/materials/icons/weapons/actions/flashlight',
    hipfire = 'content/ui/materials/icons/weapons/actions/hipfire',
    linesman = 'content/ui/materials/icons/weapons/actions/linesman',
    melee = 'content/ui/materials/icons/weapons/actions/melee',
    melee_hand = 'content/ui/materials/icons/weapons/actions/melee_hand',
    ninja_fencer = 'content/ui/materials/icons/weapons/actions/ninjafencer',
    quick_grenade = 'content/ui/materials/icons/weapons/actions/quick_grenade',
    smiter = 'content/ui/materials/icons/weapons/actions/smiter',
    special_attack = 'content/ui/materials/icons/weapons/actions/special_attack',
    special_bullet = 'content/ui/materials/icons/weapons/actions/special_bullet',
    tank = 'content/ui/materials/icons/weapons/actions/tank',
    vent = 'content/ui/materials/icons/weapons/actions/vent',
}

local function make_blueprints(width)
    local blueprints = Shared.make_blueprints(width)

    blueprints.header_icon = {
        size = { width, 130 },
        pass_template = {
            {
                pass_type = 'texture',
                style_id = 'icon',
                value_id = 'icon',
                value = 'content/ui/materials/base/ui_default_base',
                style = {
                    horizontal_alignment = 'left',
                    vertical_alignment = 'center',
                    size = { 192, 96 },
                    color = Color.terminal_text_body(255, true),
                    offset = { 10, 0, 2 },
                },
                visibility_function = function(content)
                    return content.icon ~= nil
                end,
            },
            {
                pass_type = 'text',
                style_id = 'text',
                value_id = 'text',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 26,
                    text_vertical_alignment = 'bottom',
                    text_horizontal_alignment = 'left',
                    text_color = Color.terminal_text_header(255, true),
                    offset = { 200, 0, 2 },
                    size = { width - 200, 80 },
                    text_overflow_mode = 'truncate',
                },
            },
            {
                pass_type = 'text',
                style_id = 'subtext',
                value_id = 'subtext',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 18,
                    text_vertical_alignment = 'top',
                    text_horizontal_alignment = 'left',
                    text_color = Color.terminal_text_body_sub_header(255, true),
                    offset = { 200, 78, 3 },
                    size = { width - 200, 50 },
                    text_overflow_mode = 'truncate',
                },
            },
        },
        init = function(_, widget, element)
            widget.content.text = element.text or ''
            widget.content.icon = element.icon
            widget.content.subtext = element.subtext or ''
            if element.color then
                widget.style.text.text_color = element.color
            end
        end,
    }

    local function _measure_text(ui_renderer, text, font_size, max_width)
        if not ui_renderer or text == '' then
            return 0
        end
        local style = table.clone(UIFontSettings.body)
        style.font_size = font_size
        style.size = { max_width, 1000 }
        style.text_horizontal_alignment = 'left'
        style.text_vertical_alignment = 'top'
        style.offset = { 0, 0, 0 }
        local ok, h = pcall(Text.text_height, ui_renderer, text, style, nil, true)
        return ok and h or 0
    end

    blueprints.stat = {
        size_function = function(_, config, ui_renderer)
            if not config.wrap then
                return { width, STAT_ROW_HEIGHT }
            end
            local content_x = config.icon and (STAT_ICON_SIZE + STAT_ICON_GAP) or 0
            local value_w = width - content_x
            local value_h = _measure_text(ui_renderer, config.value or '', STAT_VALUE_FONT_SIZE, value_w)
            local h = STAT_VALUE_TOP_OFFSET + math.max(STAT_VALUE_FONT_SIZE, value_h) + STAT_WRAP_PAD
            return { width, math.max(STAT_ROW_HEIGHT, h) }
        end,
        pass_template_function = function(_, config)
            local content_x = config.icon and (STAT_ICON_SIZE + STAT_ICON_GAP) or 0
            local value_w = width - content_x
            local passes = {
                {
                    pass_type = 'rect',
                    style_id = 'stripe',
                    style = {
                        color = COLOR_STRIPE,
                        offset = { 0, 0, 0 },
                    },
                    visibility_function = function(content)
                        return content.stripe == true
                    end,
                },
            }
            if config.icon then
                passes[#passes + 1] = {
                    pass_type = 'texture',
                    style_id = 'icon',
                    value = 'content/ui/materials/icons/traits/traits_container',
                    style = {
                        horizontal_alignment = 'left',
                        vertical_alignment = 'top',
                        size = { STAT_ICON_SIZE, STAT_ICON_SIZE },
                        offset = { 0, 0, 3 },
                        color = Color.terminal_icon(255, true),
                        material_values = { icon = 'content/ui/textures/icons/traits/weapon_trait_unknown' },
                    },
                    visibility_function = function(content)
                        return content.has_icon == true
                    end,
                }
            end
            local label_style = table.clone(UIFontSettings.header_3)
            label_style.font_size = STAT_LABEL_FONT_SIZE
            label_style.text_vertical_alignment = 'top'
            label_style.text_horizontal_alignment = 'left'
            label_style.text_color = Shared.colors.label
            label_style.offset = { content_x, 0, 2 }
            label_style.size = { value_w, STAT_LABEL_FONT_SIZE }
            label_style.text_overflow_mode = 'truncate'
            passes[#passes + 1] = {
                pass_type = 'text',
                style_id = 'label',
                value_id = 'label',
                value = '',
                style = label_style,
            }
            if config.wrap then
                local value_style = table.clone(UIFontSettings.body)
                value_style.font_size = STAT_VALUE_FONT_SIZE
                value_style.text_vertical_alignment = 'top'
                value_style.text_horizontal_alignment = 'left'
                value_style.text_color = Shared.colors.value
                value_style.offset = { content_x, STAT_VALUE_TOP_OFFSET, 2 }
                value_style.size = { value_w, 1000 }
                value_style.text_overflow_mode = 'wrap'
                passes[#passes + 1] = {
                    pass_type = 'text',
                    style_id = 'value',
                    value_id = 'value',
                    value = '',
                    style = value_style,
                }
            else
                local value_style = table.clone(UIFontSettings.header_3)
                value_style.font_size = STAT_VALUE_FONT_SIZE
                value_style.text_vertical_alignment = 'center'
                value_style.text_horizontal_alignment = 'left'
                value_style.text_color = Shared.colors.value
                value_style.offset = { width * 0.55, 0, 2 }
                value_style.size = { width * 0.45, STAT_ROW_HEIGHT }
                value_style.text_overflow_mode = 'truncate'
                passes[#passes + 1] = {
                    pass_type = 'text',
                    style_id = 'value',
                    value_id = 'value',
                    value = '',
                    style = value_style,
                }
            end
            return passes
        end,
        init = function(_, widget, element)
            local content = widget.content
            content.label = element.label or ''
            content.value = element.value or ''
            content.stripe = element.stripe == true
            local style = widget.style
            local indent_x = (element.indent or 0) * INDENT_PX
            style.label.offset[1] = indent_x + (element.icon and (STAT_ICON_SIZE + STAT_ICON_GAP) or 0)
            if not element.wrap then
                style.value.offset[1] = indent_x + width * 0.55
            else
                style.value.offset[1] = style.label.offset[1]
            end
            if element.label_color then
                style.label.text_color = element.label_color
            end
            if element.value_color then
                style.value.text_color = element.value_color
            end
            if element.icon then
                content.has_icon = true
                style.icon.material_values.icon = element.icon
                if element.icon_frame then
                    style.icon.material_values.frame = element.icon_frame
                end
            end
        end,
    }

    blueprints.chain = {
        size = { width, CHAIN_ROW_HEIGHT },
        pass_template_function = function(_, config)
            local chain = config.chain or {}
            local passes = {
                {
                    pass_type = 'text',
                    style_id = 'title',
                    value_id = 'title',
                    value = config.title or '',
                    style = {
                        font_type = 'proxima_nova_bold',
                        font_size = 16,
                        text_vertical_alignment = 'center',
                        text_horizontal_alignment = 'left',
                        text_color = Shared.colors.label,
                        offset = { 0, 0, 2 },
                        size = { width * 0.3, CHAIN_ROW_HEIGHT },
                        text_overflow_mode = 'truncate',
                    },
                },
            }
            local icon_area_x = width * 0.3 + 10
            local step = CHAIN_ICON_SIZE + CHAIN_ICON_SPACING
            for i = 1, #chain do
                local gestalt = chain[i]
                local icon = gestalt and GESTALT_ICONS[gestalt] or nil
                if icon then
                    local x = icon_area_x + (i - 1) * step
                    passes[#passes + 1] = {
                        pass_type = 'texture',
                        style_id = 'icon_' .. i,
                        value = icon,
                        style = {
                            horizontal_alignment = 'left',
                            vertical_alignment = 'center',
                            offset = { x, 0, 2 },
                            size = { CHAIN_ICON_SIZE, CHAIN_ICON_SIZE },
                            color = Color.terminal_text_body(255, true),
                        },
                    }
                end
            end
            return passes
        end,
    }

    blueprints.table = {
        size_function = function(_, config)
            local rows = config.rows or {}
            return { width, Shared.table_height(#rows) }
        end,
        pass_template_function = function(_, config)
            return Shared.make_table_passes(width, config.columns or {}, config.rows or {})
        end,
    }

    return blueprints
end

return make_blueprints
