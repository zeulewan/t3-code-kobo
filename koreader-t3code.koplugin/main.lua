local Dispatcher = require("dispatcher") -- luacheck:ignore
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputText = require("ui/widget/inputtext")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Settings = require("settings")
local Transport = require("transport")

local T3Code = WidgetContainer:extend{
    name = "t3code",
    is_doc_only = false,
}

local max_chat_chars = 100000

local function stashMarkdownSpan(spans, value)
    table.insert(spans, value)
    return "\30" .. tostring(#spans) .. "\31"
end

local function restoreMarkdownSpans(text, spans)
    return (text:gsub("\30(%d+)\31", function(index)
        return spans[tonumber(index)] or ""
    end))
end

local function stripUnderscoreItalics(text)
    text = text:gsub("([^%w])_([^_%s][^_]-)_([^%w])", "%1%2%3")
    text = text:gsub("^_([^_%s][^_]-)_([^%w])", "%1%2")
    text = text:gsub("([^%w])_([^_%s][^_]-)_$", "%1%2")
    text = text:gsub("^_([^_%s][^_]-)_$", "%1")
    return text
end

local function markdownToKoreaderText(text)
    local spans = {}
    local bold_start = TextBoxWidget.PTF_BOLD_START
    local bold_end = TextBoxWidget.PTF_BOLD_END

    text = tostring(text or "")
    text = text:gsub("`([^`\n]-)`", function(code)
        return stashMarkdownSpan(spans, code)
    end)
    text = text:gsub("!%[([^%]]-)%]%(([^%)]+)%)", "%1 (%2)")
    text = text:gsub("%[([^%]]-)%]%(([^%)]+)%)", "%1 (%2)")

    text = text:gsub("%*%*%*([^%*]-)%*%*%*", bold_start .. "%1" .. bold_end)
    text = text:gsub("___([^_]-)___", bold_start .. "%1" .. bold_end)
    text = text:gsub("%*%*([^%*]-)%*%*", bold_start .. "%1" .. bold_end)
    text = text:gsub("__([^_]-)__", bold_start .. "%1" .. bold_end)

    -- TextBoxWidget's lightweight PTF has bold only; keep italic emphasis readable.
    text = text:gsub("%*([^%s%*][^%*]-)%*", "%1")
    text = stripUnderscoreItalics(text)
    text = restoreMarkdownSpans(text, spans)

    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local heading = line:match("^%s*#+%s+(.+)$")
        if heading then
            table.insert(lines, bold_start .. heading .. bold_end)
        else
            table.insert(lines, (line:gsub("^%s*>%s?", "| ")))
        end
    end

    return TextBoxWidget.PTF_HEADER .. table.concat(lines, "\n")
end

local function setScrollTextMarkdown(scroll_widget, text)
    local text_widget = scroll_widget and scroll_widget.text_widget
    if not text_widget then
        return
    end
    text_widget.text = markdownToKoreaderText(text)
    text_widget.charlist = nil
    text_widget._ptf_char_is_bold = nil
    text_widget:free()
    text_widget:init()
    scroll_widget:resetScroll()
end

local function chatKeyboardKeys()
    return {
        {
            { "Q", "q", "!", "1" },
            { "W", "w", "@", "2" },
            { "E", "e", "#", "3" },
            { "R", "r", "$", "4" },
            { "T", "t", "%", "5" },
            { "Y", "y", "^", "6" },
            { "U", "u", "&", "7" },
            { "I", "i", "*", "8" },
            { "O", "o", "(", "9" },
            { "P", "p", ")", "0" },
        },
        {
            { "A", "a", "-", "_" },
            { "S", "s", "+", "=" },
            { "D", "d", "/", "\\" },
            { "F", "f", ":", ";" },
            { "G", "g", "'", "\"" },
            { "H", "h", "<", ">" },
            { "J", "j", "[", "]" },
            { "K", "k", "{", "}" },
            { "L", "l", "|", "`" },
        },
        {
            { label = "", width = 1.5 },
            { "Z", "z", "~", "~" },
            { "X", "x", "€", "€" },
            { "C", "c", "£", "£" },
            { "V", "v", "•", "•" },
            { "B", "b", "?", "¿" },
            { "N", "n", "!", "¡" },
            { "M", "m", ",", "." },
            { label = "", width = 1.5 },
        },
        {
            { label = "⌥", width = 1.5, bold = true, alt_label = "SYM" },
            { label = "_", " ", " ", " ", " ", width = 6.0 },
            { label = "Send", "\n", "\n", "\n", "\n", width = 2.5 },
        },
    }
end

local function useChatKeyboard(input_widget)
    local keyboard = input_widget and input_widget.keyboard
    if not keyboard then
        return
    end
    keyboard.KEYS = chatKeyboardKeys()
    keyboard.shiftmode_keys = { [""] = true }
    keyboard.symbolmode_keys = { ["⌥"] = true }
    keyboard.utf8mode_keys = {}
    keyboard.umlautmode_keys = {}
    keyboard.min_layer = 1
    keyboard.max_layer = 4
    local keys_height = G_reader_settings:isTrue("keyboard_key_compact") and 48 or 64
    keyboard.height = Device.screen:scaleBySize(keys_height * #keyboard.KEYS)
    keyboard:initLayer(keyboard.keyboard_layer)
end

local function smoothPanScroll(widget)
    if not widget then
        return
    end
    widget.onPanText = function(this, arg, ges)
        local line_h = this:getLineHeight()
        if not line_h or line_h <= 0 then
            return true
        end
        local current_y = ges.relative and ges.relative.y or 0
        local previous_y = this._t3_last_pan_y or current_y
        local delta_y = current_y - previous_y
        local lines = math.floor(math.abs(delta_y) / line_h)
        if lines > 0 then
            if delta_y > 0 then
                this.text_widget:scrollLines(-lines)
            else
                this.text_widget:scrollLines(lines)
            end
            this._t3_last_pan_y = previous_y + (delta_y > 0 and lines or -lines) * line_h
            UIManager:setDirty(this.dialog, "fast")
        elseif not this._t3_last_pan_y then
            this._t3_last_pan_y = current_y
        end
        return true
    end
    widget.onPanReleaseText = function(this)
        this._t3_last_pan_y = nil
        this:updateScrollBar(true)
        return true
    end
end

local T3ChatDialog = InputContainer:extend{
    is_always_active = true,
    covers_fullscreen = true,
    title = "T3 Code",
    subtitle = nil,
    history = "",
    input_hint = "Type a message",
    buttons = nil,
    on_send = nil,
    on_back = nil,
    on_close = nil,
}

local T3MenuDialog = InputContainer:extend{
    covers_fullscreen = true,
    title = "T3 Code KOReader Menu",
    status_text = nil,
    crash_text = nil,
    buttons = nil,
    on_refresh = nil,
    on_settings = nil,
    on_close = nil,
}

function T3MenuDialog:init()
    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()
    local content_w = screen_w - 2 * Size.padding.large
    local scrollbar_w = ScrollableContainer:getScrollbarWidth()
    local table_w = content_w - scrollbar_w
    local icon_w = Device.screen:scaleBySize(62)
    local title_w = screen_w - icon_w * 3
    local title_max_w = title_w - 2 * Size.padding.default
    self.region = Geom:new{ w = screen_w, h = screen_h }
    self.title_widget = TextWidget:new{
        text = self.title,
        face = Font:getFace("x_smalltfont"),
        bold = true,
        max_width = title_max_w,
    }
    self.status_widget = TextWidget:new{
        text = tostring(self.status_text or ""),
        face = Font:getFace("xx_smallinfofont"),
        bold = true,
        max_width = title_max_w,
    }
    self.title_stack = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Size.padding.small },
        self.title_widget,
        VerticalSpan:new{ width = Device.screen:scaleBySize(4) },
        self.status_widget,
        VerticalSpan:new{ width = Size.padding.small },
    }
    local top_h = math.max(Device.screen:scaleBySize(64), self.title_stack:getSize().h)
    self.top_bar = HorizontalGroup:new{
        align = "center",
        allow_mirroring = false,
        Button:new{
            icon = "close",
            callback = self.on_close,
            width = icon_w,
            height = top_h,
            bordersize = 0,
            padding = Size.padding.small,
            show_parent = self,
        },
        LeftContainer:new{
            dimen = Geom:new{ w = title_w, h = top_h },
            self.title_stack,
        },
        Button:new{
            icon = "cre.render.reload",
            callback = self.on_refresh,
            width = icon_w,
            height = top_h,
            bordersize = 0,
            padding = Size.padding.small,
            show_parent = self,
        },
        Button:new{
            icon = "appbar.settings",
            callback = self.on_settings,
            width = icon_w,
            height = top_h,
            bordersize = 0,
            padding = Size.padding.small,
            show_parent = self,
        },
    }
    self.top_line = LineWidget:new{
        dimen = Geom:new{ w = screen_w, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    }
    local crash_widget
    if self.crash_text and self.crash_text ~= "" then
        crash_widget = TextBoxWidget:new{
            text = self.crash_text,
            face = Font:getFace("x_smallinfofont"),
            bold = true,
            width = content_w,
            alignment = "left",
        }
    end
    self.button_table = ButtonTable:new{
        width = table_w,
        buttons = self.buttons,
        sep_width = Size.line.medium,
        zero_sep = true,
        show_parent = self,
    }
    local widgets = {
        align = "left",
        self.top_bar,
        self.top_line,
        VerticalSpan:new{ width = Size.padding.small },
    }
    if crash_widget then
        table.insert(widgets, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = crash_widget:getSize().h },
            crash_widget,
        })
        table.insert(widgets, VerticalSpan:new{ width = Size.padding.default })
    end

    local used_h = self.top_bar:getSize().h
        + self.top_line:getSize().h
        + Size.padding.small
        + (crash_widget and (crash_widget:getSize().h + Size.padding.default) or 0)
    local list_h = self.button_table:getSize().h
    local max_list_h = screen_h - used_h
    if max_list_h < Device.screen:scaleBySize(160) then
        max_list_h = Device.screen:scaleBySize(160)
    end
    if list_h > max_list_h then
        self.cropping_widget = ScrollableContainer:new{
            dimen = Geom:new{ w = content_w, h = max_list_h },
            show_parent = self,
            self.button_table,
        }
        table.insert(widgets, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = max_list_h },
            self.cropping_widget,
        })
    else
        table.insert(widgets, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = list_h },
            self.button_table,
        })
    end
    self.vgroup = VerticalGroup:new(widgets)
    self.dialog_frame = FrameContainer:new{
        width = screen_w,
        height = screen_h,
        radius = 0,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.vgroup,
    }
    self[1] = self.dialog_frame
end

function T3MenuDialog:onShow()
    UIManager:setDirty(nil, "full")
end

function T3MenuDialog:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

local T3SettingsDialog = InputContainer:extend{
    covers_fullscreen = true,
    title = "T3 Code Settings",
    endpoint = "",
    transport = "",
    on_close = nil,
    on_pair = nil,
    on_status = nil,
    on_save = nil,
}

function T3SettingsDialog:init()
    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()
    local width = screen_w
    local content_w = width - 2 * Size.padding.large
    local card_padding = Size.padding.large
    local card_border = Size.line.medium
    local inner_w = content_w - 2 * (card_padding + card_border)
    local line_h = Device.screen:scaleBySize(42)
    local icon_w = Device.screen:scaleBySize(62)
    local title_w = width - icon_w * 2
    self.region = Geom:new{ w = screen_w, h = screen_h }
    self.title_widget = TextWidget:new{
        text = self.title,
        face = Font:getFace("x_smalltfont"),
        bold = true,
        max_width = title_w - 2 * Size.padding.default,
    }
    self.subtitle_widget = TextWidget:new{
        text = "Pairing, bridge, and transport",
        face = Font:getFace("xx_smallinfofont"),
        bold = true,
        max_width = title_w - 2 * Size.padding.default,
    }
    self.title_stack = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Size.padding.small },
        self.title_widget,
        VerticalSpan:new{ width = Device.screen:scaleBySize(4) },
        self.subtitle_widget,
        VerticalSpan:new{ width = Size.padding.small },
    }
    local top_h = math.max(Device.screen:scaleBySize(64), self.title_stack:getSize().h)
    self.top_bar = HorizontalGroup:new{
        align = "center",
        allow_mirroring = false,
        Button:new{
            icon = "chevron.left",
            callback = self.on_close,
            width = icon_w,
            height = top_h,
            bordersize = 0,
            padding = Size.padding.small,
            show_parent = self,
        },
        LeftContainer:new{
            dimen = Geom:new{ w = title_w, h = top_h },
            self.title_stack,
        },
        HorizontalSpan:new{ width = icon_w },
    }
    self.top_line = LineWidget:new{
        dimen = Geom:new{ w = width, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    }
    self.endpoint_input = InputText:new{
        text = self.endpoint or "",
        hint = "100.101.214.44:18892",
        face = Font:getFace("x_smallinfofont"),
        width = inner_w,
        height = line_h,
        padding = Size.padding.default,
        margin = 0,
        scroll = true,
        cursor_at_end = true,
        parent = self,
    }
    self.transport_input = InputText:new{
        text = self.transport or "http",
        hint = "http",
        face = Font:getFace("x_smallinfofont"),
        width = inner_w,
        height = line_h,
        padding = Size.padding.default,
        margin = 0,
        scroll = true,
        cursor_at_end = true,
        parent = self,
    }

    local actions_label = TextBoxWidget:new{
        text = "Actions",
        face = Font:getFace("x_smallinfofont"),
        bold = true,
        width = inner_w,
        alignment = "left",
    }
    local actions_note = TextBoxWidget:new{
        text = "Pair the Kobo with the workstation bridge or inspect the current bridge status.",
        face = Font:getFace("xx_smallinfofont"),
        width = inner_w,
        alignment = "left",
    }
    self.action_table = ButtonTable:new{
        width = inner_w,
        sep_width = Size.line.medium * 2,
        zero_sep = true,
        show_parent = self,
        buttons = {
            {
                {
                    text = "Pair Device",
                    callback = self.on_pair,
                    height = Device.screen:scaleBySize(52),
                    font_size = 19,
                    font_bold = true,
                },
                {
                    text = "Check Status",
                    callback = self.on_status,
                    height = Device.screen:scaleBySize(52),
                    font_size = 19,
                    font_bold = true,
                },
            },
        },
    }
    self.actions_card = FrameContainer:new{
        width = content_w,
        radius = Size.radius.window,
        bordersize = card_border,
        padding = card_padding,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            actions_label,
            VerticalSpan:new{ width = Size.padding.small },
            actions_note,
            VerticalSpan:new{ width = Size.padding.default },
            self.action_table,
        },
    }

    local bridge_label = TextBoxWidget:new{
        text = "Bridge",
        face = Font:getFace("x_smallinfofont"),
        bold = true,
        width = inner_w,
        alignment = "left",
    }
    local bridge_note = TextBoxWidget:new{
        text = "Choose the bridge endpoint and transport the Kobo should use for T3 Code.",
        face = Font:getFace("xx_smallinfofont"),
        width = inner_w,
        alignment = "left",
    }
    local endpoint_label = TextBoxWidget:new{
        text = "Endpoint",
        face = Font:getFace("xx_smallinfofont"),
        bold = true,
        width = inner_w,
        alignment = "left",
    }
    local transport_label = TextBoxWidget:new{
        text = "Transport",
        face = Font:getFace("xx_smallinfofont"),
        bold = true,
        width = inner_w,
        alignment = "left",
    }
    self.bridge_card = FrameContainer:new{
        width = content_w,
        radius = Size.radius.window,
        bordersize = card_border,
        padding = card_padding,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            bridge_label,
            VerticalSpan:new{ width = Size.padding.small },
            bridge_note,
            VerticalSpan:new{ width = Size.padding.default },
            endpoint_label,
            VerticalSpan:new{ width = Size.padding.small },
            self.endpoint_input,
            VerticalSpan:new{ width = Size.padding.default },
            transport_label,
            VerticalSpan:new{ width = Size.padding.small },
            self.transport_input,
        },
    }

    self.button_table = ButtonTable:new{
        width = content_w,
        sep_width = 0,
        zero_sep = true,
        show_parent = self,
        buttons = {
            {
                {
                    text = "Save Changes",
                    callback = function()
                        if self.on_save then
                            self.on_save(self.endpoint_input:getText(), self.transport_input:getText())
                        end
                    end,
                    height = Device.screen:scaleBySize(60),
                    font_size = 22,
                    font_bold = true,
                    align = "center",
                },
            },
        },
    }

    local footer_note = TextBoxWidget:new{
        text = "Use the back button to leave without saving.",
        face = Font:getFace("xx_smallinfofont"),
        width = content_w,
        alignment = "left",
    }
    self.vgroup = VerticalGroup:new{
        align = "left",
        self.top_bar,
        self.top_line,
        VerticalSpan:new{ width = Size.padding.large },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = self.actions_card:getSize().h },
            self.actions_card,
        },
        VerticalSpan:new{ width = Size.padding.large },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = self.bridge_card:getSize().h },
            self.bridge_card,
        },
        VerticalSpan:new{ width = Size.padding.large },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = self.button_table:getSize().h },
            self.button_table,
        },
        VerticalSpan:new{ width = Size.padding.default },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = footer_note:getSize().h },
            footer_note,
        },
    }
    self.dialog_frame = FrameContainer:new{
        width = screen_w,
        height = screen_h,
        radius = 0,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.vgroup,
    }
    self[1] = self.dialog_frame
end

function T3SettingsDialog:onShow()
    UIManager:setDirty(nil, "full")
end

function T3SettingsDialog:onCloseWidget()
    if self.endpoint_input then
        self.endpoint_input:onCloseWidget()
    end
    if self.transport_input then
        self.transport_input:onCloseWidget()
    end
    UIManager:setDirty(nil, "full")
end

function T3ChatDialog:init()
    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()
    local width = screen_w
    local title_h
    local line_h = Device.screen:scaleBySize(36)
    self.region = Geom:new{ w = screen_w, h = screen_h }
    self.title_bar = TitleBar:new{
        width = width,
        align = "left",
        with_bottom_line = true,
        title = self.title,
        subtitle = self.subtitle,
        title_multilines = false,
        left_icon = "chevron.left",
        left_icon_tap_callback = self.on_back,
        show_parent = self,
    }
    title_h = self.title_bar:getHeight()

    self.input_widget = InputText:new{
        text = "",
        hint = self.input_hint,
        face = Font:getFace("x_smallinfofont"),
        width = width - 2 * Size.padding.large,
        height = line_h,
        padding = Size.padding.default,
        margin = Size.margin.small,
        scroll = true,
        cursor_at_end = true,
        enter_callback = self.on_send,
        parent = self,
    }
    useChatKeyboard(self.input_widget)

    if self.buttons then
        self.button_table = ButtonTable:new{
            width = width,
            buttons = self.buttons,
            zero_sep = true,
            show_parent = self,
        }
    end

    local keyboard_h = self.input_widget:getKeyboardDimen().h
    local input_h = self.input_widget:getSize().h
    local buttons_h = self.button_table and self.button_table:getSize().h or 0
    local history_h = screen_h - keyboard_h - title_h - input_h - buttons_h - Size.padding.large * 2
    if history_h < line_h * 4 then
        history_h = line_h * 4
    end

    self.history_widget = ScrollTextWidget:new{
        text = markdownToKoreaderText(self.history ~= "" and self.history or _("No messages yet.")),
        face = Font:getFace("x_smallinfofont"),
        width = width - 2 * Size.padding.large,
        height = history_h,
        dialog = self,
        scroll_by_pan = true,
    }
    smoothPanScroll(self.history_widget)
    self.history_widget:scrollToBottom()

    local widgets = {
        align = "left",
        self.title_bar,
        VerticalSpan:new{ width = Size.padding.small },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = self.history_widget:getSize().h },
            self.history_widget,
        },
        VerticalSpan:new{ width = Size.padding.small },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = input_h },
            self.input_widget,
        },
    }
    if self.button_table then
        table.insert(widgets, self.button_table)
    end
    self.vgroup = VerticalGroup:new(widgets)

    self.dialog_frame = FrameContainer:new{
        width = screen_w,
        height = screen_h - keyboard_h,
        radius = 0,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.vgroup,
    }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = screen_h - keyboard_h },
        ignore_if_over = "height",
        self.dialog_frame,
    }
end

function T3ChatDialog:onShow()
    UIManager:setDirty(self, "ui")
end

function T3ChatDialog:onCloseWidget()
    if self.input_widget then
        self.input_widget:onCloseWidget()
    end
    UIManager:setDirty(nil, "full")
end

function T3ChatDialog:onShowKeyboard()
    self.input_widget:onShowKeyboard()
end

function T3ChatDialog:closeKeyboard()
    if self.input_widget then
        self.input_widget:onCloseKeyboard()
    end
end

function T3ChatDialog:getInputText()
    return self.input_widget:getText()
end

function T3ChatDialog:setInputText(text)
    self.input_widget:setText(tostring(text or ""))
end

function T3ChatDialog:setHistory(text)
    text = tostring(text or "")
    if text == "" then
        text = _("No messages yet.")
    end
    if #text > max_chat_chars then
        text = "...\n" .. text:sub(#text - max_chat_chars)
    end
    self.history = text
    setScrollTextMarkdown(self.history_widget, text)
    self.history_widget:scrollToBottom()
    UIManager:setDirty(self, "ui")
end

local function showMessage(text)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 4,
    })
end

local function currentTarget()
    local config = Settings.load()
    return tostring(config.target or "")
end

local function transcriptPreview()
    local target = currentTarget()
    local ok, text = Transport.new():thread(10)
    if not ok then
        text = Settings.readTranscript(target)
    end
    if text == "" then
        return _("No messages yet.")
    end
    text = tostring(text):gsub("\t", "  "):gsub("\\n", "\n")
    if #text > max_chat_chars then
        text = "...\n" .. text:sub(#text - max_chat_chars)
    end
    return text
end

local prompt_marker = "\n\n> "

local function streamPath()
    return Settings.streamPath(currentTarget())
end

local function normalizeRenderedHistory(text)
    text = tostring(text or ""):gsub("%s+$", "")
    if text == "" or text == _("No messages yet.") then
        return ""
    end
    return text
end

local function appendHistoryEntry(rendered, entry)
    local base = normalizeRenderedHistory(rendered)
    local clean = normalizeRenderedHistory(entry)
    if clean == "" then
        return base
    end
    if base == "" then
        return clean
    end
    return base .. "\n\n" .. clean
end

local function displayHistory(rendered, optimistic_anchor, optimistic_tail)
    local base = normalizeRenderedHistory(rendered)
    if optimistic_tail ~= "" and optimistic_anchor ~= nil and base == optimistic_anchor then
        base = appendHistoryEntry(base, optimistic_tail)
    end
    if base == "" then
        return _("No messages yet.")
    end
    return base
end

local function chatInputText()
    local history = transcriptPreview()
    if history == _("No messages yet.") then
        history = ""
    end
    return history .. prompt_marker
end

local function chatInputTextWithPrompt(prompt)
    local history = transcriptPreview()
    if history == _("No messages yet.") then
        history = ""
    end
    return history .. prompt_marker .. tostring(prompt or "")
end

local function chatInputTextFromHistory(history, prompt)
    history = tostring(history or "")
    if history == "" or history == _("No messages yet.") then
        history = ""
    end
    if #history > max_chat_chars then
        history = "...\n" .. history:sub(#history - max_chat_chars)
    end
    return history .. prompt_marker .. tostring(prompt or "")
end

local function urlDecode(value)
    value = tostring(value or "")
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function latestEventFrame(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local text = file:read("*a") or ""
    file:close()
    local rendered
    for line in text:gmatch("[^\r\n]+") do
        local _seq, kind, _status, encoded = line:match("^([0-9]+)\t([^\t]*)\t([^\t]*)\t(.*)$")
        if kind == "replace" then
            rendered = urlDecode(encoded)
        elseif kind == "append" then
            rendered = tostring(rendered or "") .. urlDecode(encoded)
        end
    end
    if rendered == nil or rendered == "" then
        return nil
    end
    return rendered
end

local function outgoingMessage(text)
    local marker_start
    local search_from = 1
    while true do
        local found = tostring(text or ""):find(prompt_marker, search_from, true)
        if not found then
            break
        end
        marker_start = found
        search_from = found + #prompt_marker
    end
    local message = marker_start and text:sub(marker_start + #prompt_marker) or tostring(text or "")
    return message:match("^%s*(.-)%s*$")
end

local function parseAgentLines(text)
    local agents = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local fields = {}
        for field in (line .. "\t"):gmatch("(.-)\t") do
            table.insert(fields, field)
        end
        local id = fields[1]
        local title = fields[2]
        if id and title then
            local project = fields[5] or ""
            local effort = ""
            if #fields >= 7 then
                effort = fields[6] or ""
            end
            table.insert(agents, {
                id = id,
                title = title,
                status = fields[3] or "idle",
                model = fields[4] or "",
                project = project ~= "" and project or "No project",
                effort = effort,
            })
        end
    end
    return agents
end

local function projectGroups(agents)
    local groups = {}
    local order = {}
    for _, agent in ipairs(agents) do
        local project = agent.project or "No project"
        if not groups[project] then
            groups[project] = {}
            table.insert(order, project)
        end
        table.insert(groups[project], agent)
    end
    table.sort(order)
    return groups, order
end

local function trimText(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function ellipsize(value, max_len)
    value = tostring(value or "")
    if #value <= max_len then
        return value
    end
    return value:sub(1, math.max(1, max_len - 3)) .. "..."
end

local function menuButton(text, callback, opts)
    opts = opts or {}
    return {
        text = text,
        callback = callback or function() end,
        enabled = opts.enabled ~= false,
        align = opts.align or "left",
        height = opts.height or Device.screen:scaleBySize(54),
        font_size = opts.font_size or 22,
        font_bold = opts.font_bold ~= false,
        background = opts.background,
    }
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function urlEncode(value)
    value = tostring(value or "")
    return (value:gsub("([^%w%-_%.~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function saveTarget(target, title, meta)
    local config = Settings.load()
    config.target = target
    config.target_title = title or target
    config.target_project = meta and meta.project or ""
    config.target_model = meta and meta.model or ""
    config.target_effort = meta and meta.effort or ""
    config.pairing_token = tostring(target) .. " " .. tostring(config.endpoint or "")
    Settings.save(config)
end

local function chatTitle()
    local config = Settings.load()
    local agent = tostring(config.target_title or config.target or "")
    local parts = {}
    if agent ~= "" then
        table.insert(parts, agent)
    end
    local project = tostring(config.target_project or "")
    local model = tostring(config.target_model or "")
    local effort = tostring(config.target_effort or "")
    if project ~= "" then
        table.insert(parts, project)
    end
    if effort ~= "" then
        if model ~= "" then
            model = model .. " / " .. effort
        else
            model = effort
        end
    end
    if model ~= "" then
        table.insert(parts, model)
    end
    if #parts == 0 then
        return "Chat"
    end
    return table.concat(parts, "  |  ")
end

local function telemetryUrl(config, kind, message)
    local endpoint = tostring(config.endpoint or "")
    if endpoint == "" then
        return nil
    end
    if not endpoint:match("^https?://") then
        endpoint = "http://" .. endpoint
    end
    endpoint = endpoint:gsub("/+$", "")
    return endpoint
        .. "/telemetry?source=kobo-koreader"
        .. "&kind=" .. urlEncode(kind)
        .. "&message=" .. urlEncode(message)
end

local function sendTelemetry(config, kind, message)
    local url = telemetryUrl(config, kind, message)
    if not url then
        return
    end
    os.execute("wget -q -T 8 -O /dev/null " .. shellQuote(url) .. " >/dev/null 2>&1 &")
end

local function fileSize(path)
    local handle = io.popen("wc -c < " .. shellQuote(path) .. " 2>/dev/null")
    if not handle then
        return nil
    end
    local output = handle:read("*a") or ""
    handle:close()
    return output:match("%d+")
end

local function crashTail(path, max_bytes)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local size = file:seek("end") or 0
    file:seek("set", math.max(0, size - max_bytes))
    local text = file:read("*a")
    file:close()
    return text
end

local function crashStatusLine(config)
    local crash_log = "/mnt/onboard/.adds/koreader/crash.log"
    local marker = fileSize(crash_log)
    if not marker or marker == "" then
        return "Crash telemetry: no crash log"
    end
    local tail = crashTail(crash_log, 3000) or ""
    local looks_like_crash = tail:find("stack traceback", 1, true)
        or tail:find("Uh oh", 1, true)
        or tail:find("./luajit:", 1, true)
    if not looks_like_crash then
        return "Crash telemetry: no recent crash"
    end
    if tostring(config.crash_report_marker or "") == tostring(marker) then
        return "Crash telemetry: report sent"
    end
    return "Crash telemetry: pending restart"
end

local function menuStatusLine(ok)
    if ok then
        return "✓ Connected"
    end
    return "Offline"
end

function T3Code:onDispatcherRegisterActions()
    Dispatcher:registerAction("t3code_chat", {
        category = "none",
        event = "T3CodeApp",
        title = _("T3 Code"),
        general = true,
    })
    Dispatcher:registerAction("t3code_pair", {
        category = "none",
        event = "T3CodePair",
        title = _("T3 Code pair"),
        general = true,
    })
end

function T3Code:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self:sendStartupTelemetry()
end

function T3Code:sendStartupTelemetry()
    local config = Settings.load()
    sendTelemetry(config, "startup", "T3 Code plugin loaded")

    local crash_log = "/mnt/onboard/.adds/koreader/crash.log"
    local marker = fileSize(crash_log)
    if marker and marker ~= "" and marker ~= tostring(config.crash_report_marker or "") then
        config.crash_report_marker = marker
        Settings.save(config)
        local tail = crashTail(crash_log, 3000)
        if tail and tail ~= "" and (tail:find("stack traceback", 1, true) or tail:find("Uh oh", 1, true) or tail:find("./luajit:", 1, true)) then
            sendTelemetry(config, "crash", tail)
        end
    end
end

function T3Code:addToMainMenu(menu_items)
    menu_items.t3code = {
        text = _("T3 Code"),
        sorting_hint = "tools",
        callback = function()
            self:onT3CodeApp()
        end,
    }
end

function T3Code:onT3CodeStatus()
    local transport = Transport.new()
    showMessage(_("T3 Code") .. "\n" .. transport:status())
end

function T3Code:onT3CodeTranscript()
    local text = Settings.readTranscript(currentTarget())
    if text == "" then
        text = _("No messages yet.")
    end
    UIManager:show(InfoMessage:new{
        text = text,
    })
end

function T3Code:onT3CodePair()
    local config = Settings.load()
    local dialog
    dialog = InputDialog:new{
        title = _("Pair T3 Code"),
        input = config.pairing_token or "",
        input_hint = _("Paste pairing code or URL"),
        description = _("Saved locally for now. The transport module can use it once Coby finalizes networking."),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local transport = Transport.new()
                        local ok, message = transport:pair(dialog:getInputText())
                        UIManager:close(dialog)
                        showMessage(message or (ok and _("Saved.") or _("Failed.")))
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function T3Code:onT3CodeSettings(return_to_menu)
    local config = Settings.load()
    local dialog
    dialog = T3SettingsDialog:new{
        endpoint = config.endpoint or "",
        transport = config.transport or "http",
        on_close = function()
            UIManager:close(dialog)
            if return_to_menu then
                UIManager:nextTick(function()
                    self:onT3CodeAgentSelector(true)
                end)
            end
        end,
        on_pair = function()
            self:onT3CodePair()
        end,
        on_status = function()
            showMessage(_("T3 Code") .. "\n" .. Transport.new():status())
        end,
        on_save = function(endpoint, transport)
            config.endpoint = trimText(endpoint)
            config.transport = trimText(transport)
            if config.transport == "" then
                config.transport = "http"
            end
            Settings.save(config)
            UIManager:close(dialog)
            if return_to_menu then
                UIManager:nextTick(function()
                    self:onT3CodeAgentSelector(true)
                end)
            end
        end,
    }
    UIManager:show(dialog)
end

function T3Code:onT3CodeAgentSelector(open_chat, expanded_project)
    local dialog
    local function transitionTo(callback)
        callback()
        UIManager:close(dialog)
    end
    local ok, body = Transport.new():agents()
    local agents = ok and parseAgentLines(body) or {}
    local groups, projects = projectGroups(agents)
    local buttons = {}
    if not ok then
        table.insert(buttons, {
            menuButton(_("Could not load agents"), function()
                showMessage(tostring(body))
            end),
        })
    else
        for project_index = 1, #projects do
            local project = projects[project_index]
            local project_agents = groups[project] or {}
            local count = #project_agents
            local expanded = expanded_project == project
            local marker = expanded and "v " or "> "
            table.insert(buttons, {
                menuButton(marker .. ellipsize(project, 50) .. " (" .. tostring(count) .. ")", function()
                    local next_project = project
                    if expanded then
                        next_project = nil
                    end
                    transitionTo(function()
                        self:onT3CodeAgentSelector(open_chat, next_project)
                    end)
                end),
            })
            if expanded then
                for agent_index = 1, #project_agents do
                    local selected_agent = project_agents[agent_index]
                    local status = selected_agent.status ~= "" and selected_agent.status or "idle"
                    table.insert(buttons, {
                        menuButton("    " .. ellipsize(selected_agent.title, 48) .. "  [" .. status .. "]", function()
                            saveTarget(selected_agent.id, selected_agent.title, selected_agent)
                            if open_chat then
                                transitionTo(function()
                                    self:onT3CodeChatApp()
                                end)
                            else
                                UIManager:close(dialog)
                            end
                        end, {
                            height = Device.screen:scaleBySize(46),
                            font_size = 20,
                            font_bold = false,
                        }),
                    })
                end
                if count == 0 then
                    table.insert(buttons, {
                        menuButton("    " .. _("No agents in project"), function() end, {
                            height = Device.screen:scaleBySize(46),
                            font_size = 20,
                            font_bold = false,
                        }),
                    })
                end
            end
        end
        if #projects == 0 then
            table.insert(buttons, {
                menuButton(_("No agents"), function() end),
            })
        end
    end
    dialog = T3MenuDialog:new{
        title = "T3 Code KOReader Menu",
        status_text = menuStatusLine(ok),
        on_refresh = function()
            transitionTo(function()
                self:onT3CodeAgentSelector(open_chat, expanded_project)
            end)
        end,
        on_settings = function()
            transitionTo(function()
                self:onT3CodeSettings(true)
            end)
        end,
        on_close = function()
            UIManager:close(dialog)
        end,
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function T3Code:onT3CodeApp()
    self:onT3CodeAgentSelector(true)
end

function T3Code:onT3CodeChatApp()
    local dialog
    local poll_task
    local poll_count = 0
    local last_rendered = nil
    local last_stream_rendered = ""
    local optimistic_anchor = nil
    local optimistic_tail = ""
    local stream_pid = nil
    local stream_path = streamPath()

    local function stopPolling()
        if poll_task then
            UIManager:unschedule(poll_task)
            poll_task = nil
        end
        if stream_pid then
            Transport.new():stopStream(stream_pid)
            stream_pid = nil
        end
    end

    local function refreshChat(keep_prompt)
        local prompt = keep_prompt and dialog:getInputText() or ""
        local rendered = transcriptPreview()
        last_stream_rendered = normalizeRenderedHistory(rendered)
        if optimistic_tail ~= "" and optimistic_anchor ~= nil and last_stream_rendered ~= optimistic_anchor then
            optimistic_tail = ""
            optimistic_anchor = nil
        end
        rendered = displayHistory(last_stream_rendered, optimistic_anchor, optimistic_tail)
        if rendered ~= last_rendered then
            last_rendered = rendered
            dialog:setHistory(rendered)
        end
        dialog:setInputText(prompt)
    end

    local function pollChat()
        poll_task = nil
        poll_count = poll_count + 1
        local frame = latestEventFrame(stream_path)
        if frame then
            last_stream_rendered = normalizeRenderedHistory(frame)
            if optimistic_tail ~= "" and optimistic_anchor ~= nil and last_stream_rendered ~= optimistic_anchor then
                optimistic_tail = ""
                optimistic_anchor = nil
            end
            local rendered = displayHistory(last_stream_rendered, optimistic_anchor, optimistic_tail)
            if rendered ~= last_rendered then
                last_rendered = rendered
                dialog:setHistory(rendered)
            end
        end
        if stream_pid then
            poll_task = UIManager:scheduleIn(1, pollChat)
        end
    end

    local function startPolling()
        if stream_pid then
            return
        end
        poll_count = 0
        local stream_ok, stream_result = Transport.new():startStream(stream_path, 10)
        if stream_ok then
            stream_pid = stream_result
            poll_task = UIManager:scheduleIn(1, pollChat)
        else
            showMessage(tostring(stream_result))
            poll_task = UIManager:scheduleIn(3, function()
                refreshChat(false)
            end)
        end
    end

    local function backToAgents()
        stopPolling()
        if dialog then
            dialog:closeKeyboard()
        end
        self:onT3CodeAgentSelector(true)
        UIManager:close(dialog)
    end

    local function sendCurrentMessage()
        local message = dialog:getInputText():match("^%s*(.-)%s*$")
        if message == "" then
            showMessage(_("Message is empty."))
            return
        end
        local target = currentTarget()
        local user_entry = "You: " .. message
        Settings.appendTranscript(user_entry, target)
        if optimistic_anchor == nil then
            optimistic_anchor = last_stream_rendered
        end
        optimistic_tail = appendHistoryEntry(optimistic_tail, user_entry)
        local optimistic = displayHistory(last_stream_rendered, optimistic_anchor, optimistic_tail)
        last_rendered = optimistic
        dialog:setHistory(optimistic)
        dialog:setInputText("")
        UIManager:forceRePaint()
        UIManager:yieldToEPDC()

        local ok, response = Transport.new():send(message)
        if not ok then
            local error_entry = "T3: " .. tostring(response)
            Settings.appendTranscript(error_entry, target)
            optimistic_tail = appendHistoryEntry(optimistic_tail, error_entry)
            local rendered = displayHistory(last_stream_rendered, optimistic_anchor, optimistic_tail)
            last_rendered = rendered
            dialog:setHistory(rendered)
            showMessage(tostring(response))
            return
        end

        startPolling()
    end

    dialog = T3ChatDialog:new{
        title = chatTitle(),
        subtitle = nil,
        history = transcriptPreview(),
        input_hint = _("> Type a message"),
        on_send = sendCurrentMessage,
        on_back = backToAgents,
        on_close = function()
            stopPolling()
            dialog:closeKeyboard()
            UIManager:close(dialog)
        end,
    }
    last_rendered = dialog.history
    last_stream_rendered = normalizeRenderedHistory(dialog.history)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    startPolling()
end

return T3Code
