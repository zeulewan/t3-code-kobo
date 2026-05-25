local Dispatcher = require("dispatcher") -- luacheck:ignore
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputText = require("ui/widget/inputtext")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
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

local function customizeChatKeyboard(input_widget)
    local keyboard = input_widget and input_widget.keyboard
    if not keyboard or not keyboard.KEYS or #keyboard.KEYS < 2 then
        return
    end

    -- Keep this plugin-local: mutate this input's keyboard instance only.
    table.remove(keyboard.KEYS, 1)
    local last_row = keyboard.KEYS[#keyboard.KEYS]
    local enter_key = last_row and last_row[#last_row]
    if enter_key then
        enter_key.label = "Send"
        enter_key[1], enter_key[2], enter_key[3], enter_key[4] = "\n", "\n", "\n", "\n"
        enter_key.width = 2.0
    end

    local keys_height = G_reader_settings:isTrue("keyboard_key_compact") and 48 or 64
    keyboard.height = Device.screen:scaleBySize(keys_height * #keyboard.KEYS)
    keyboard:initLayer(keyboard.keyboard_layer)
end

local T3ChatDialog = InputContainer:extend{
    is_always_active = true,
    covers_fullscreen = true,
    title = "T3 Code",
    history = "",
    input_hint = "Type a message",
    buttons = nil,
    on_send = nil,
    on_back = nil,
    on_close = nil,
}

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
        title_multilines = false,
        left_icon = "chevron.left",
        left_icon_tap_callback = self.on_back,
        close_callback = self.on_close,
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
    customizeChatKeyboard(self.input_widget)

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
        text = self.history ~= "" and self.history or _("No messages yet."),
        face = Font:getFace("x_smallinfofont"),
        width = width - 2 * Size.padding.large,
        height = history_h,
        dialog = self,
        scroll_by_pan = true,
    }

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
    if #text > 2600 then
        text = "...\n" .. text:sub(#text - 2600)
    end
    self.history = text
    self.history_widget.text_widget:setText(text)
    self.history_widget:resetScroll()
    self.history_widget:scrollToBottom()
    UIManager:setDirty(self, "ui")
end

local function showMessage(text)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 4,
    })
end

local function transcriptPreview()
    local ok, text = Transport.new():thread(10)
    if not ok then
        text = Settings.readTranscript()
    end
    if text == "" then
        return _("No messages yet.")
    end
    text = tostring(text):gsub("\t", "  "):gsub("\\n", "\n")
    if #text > 2600 then
        text = "...\n" .. text:sub(#text - 2600)
    end
    return text
end

local prompt_marker = "\n\n> "
local stream_path = Settings.base_dir .. "/stream.txt"

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
    if #history > 2600 then
        history = "...\n" .. history:sub(#history - 2600)
    end
    return history .. prompt_marker .. tostring(prompt or "")
end

local function latestStreamFrame()
    local file = io.open(stream_path, "r")
    if not file then
        return nil
    end
    local text = file:read("*a") or ""
    file:close()
    local marker = string.char(30)
    local last_marker
    local search_from = 1
    while true do
        local found = text:find(marker, search_from, true)
        if not found then
            break
        end
        last_marker = found
        search_from = found + 1
    end
    if not last_marker then
        return nil
    end
    return text:sub(last_marker + 1)
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
        local id, title, status = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)")
        if id and title then
            table.insert(agents, {
                id = id,
                title = title,
                status = status or "idle",
            })
        end
    end
    return agents
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

local function saveTarget(target, title)
    local config = Settings.load()
    config.target = target
    config.target_title = title or target
    config.pairing_token = tostring(target) .. " " .. tostring(config.endpoint or "")
    Settings.save(config)
end

local function chatTitle()
    local config = Settings.load()
    local agent = tostring(config.target_title or config.target or "")
    if #agent > 24 then
        agent = agent:sub(1, 23) .. "..."
    end
    return "T3 Code  " .. agent
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

function T3Code:onDispatcherRegisterActions()
    Dispatcher:registerAction("t3code_chat", {
        category = "none",
        event = "T3CodeChat",
        title = _("T3 Code chat"),
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
    local text = Settings.readTranscript()
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

function T3Code:onT3CodeAgentSelector(open_chat)
    local dialog
    local ok, body = Transport.new():agents()
    local agents = ok and parseAgentLines(body) or {}
    local buttons = {}
    table.insert(buttons, {
        {
            text = _("Status"),
            callback = function()
                showMessage(_("T3 Code") .. "\n" .. Transport.new():status())
            end,
        },
        {
            text = _("Pair"),
            callback = function()
                UIManager:close(dialog)
                UIManager:nextTick(function()
                    self:onT3CodePair()
                end)
            end,
        },
        {
            text = _("Refresh"),
            callback = function()
                UIManager:close(dialog)
                UIManager:nextTick(function()
                    self:onT3CodeAgentSelector(open_chat)
                end)
            end,
        },
    })
    for agent_index, agent in ipairs(agents) do
        local selected_agent = agent
        table.insert(buttons, {
            {
                text = tostring(agent_index) .. ". " .. selected_agent.title .. " [" .. selected_agent.status .. "]",
                callback = function()
                    saveTarget(selected_agent.id, selected_agent.title)
                    UIManager:close(dialog)
                    if open_chat then
                        UIManager:nextTick(function()
                            self:onT3CodeChatApp()
                        end)
                    end
                end,
            },
        })
    end
    if not ok then
        table.insert(buttons, {
            {
                text = _("Could not load agents"),
                callback = function()
                    showMessage(tostring(body))
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Custom"),
            callback = function()
                UIManager:close(dialog)
                local config = Settings.load()
                local custom_dialog
                custom_dialog = InputDialog:new{
                    title = _("Custom agent"),
                    input = config.target or "agent",
                    input_hint = _("Agent handle"),
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(custom_dialog)
                                    if open_chat then
                                        UIManager:nextTick(function()
                                            self:onT3CodeAgentSelector(true)
                                        end)
                                    end
                                end,
                            },
                            {
                                text = _("Save"),
                                is_enter_default = true,
                                callback = function()
                                    local target = custom_dialog:getInputText()
                                    saveTarget(target, target)
                                    UIManager:close(custom_dialog)
                                    if open_chat then
                                        UIManager:nextTick(function()
                                            self:onT3CodeChatApp()
                                        end)
                                    end
                                end,
                            },
                        },
                    },
                }
                UIManager:show(custom_dialog)
                custom_dialog:onShowKeyboard()
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Close"),
            callback = function()
                UIManager:close(dialog)
            end,
        },
    })
    dialog = ButtonDialog:new{
        title = _("T3 Code"),
        width = Device.screen:getWidth(),
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
    local stream_pid = nil
    local pending_message = nil

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
        if rendered ~= last_rendered then
            last_rendered = rendered
            dialog:setHistory(rendered)
        end
        dialog:setInputText(prompt)
    end

    local function pollChat()
        poll_task = nil
        poll_count = poll_count + 1
        local frame = latestStreamFrame()
        if frame then
            local rendered = frame
            if rendered ~= last_rendered then
                if not pending_message or rendered:find(pending_message, 1, true) or poll_count > 8 then
                    pending_message = nil
                    last_rendered = rendered
                    dialog:setHistory(rendered)
                end
            end
        end
        if poll_count < 120 then
            poll_task = UIManager:scheduleIn(1, pollChat)
        else
            stopPolling()
        end
    end
    local function backToAgents()
        stopPolling()
        UIManager:close(dialog)
        UIManager:nextTick(function()
            self:onT3CodeAgentSelector(true)
        end)
    end

    local function sendCurrentMessage()
        local message = dialog:getInputText():match("^%s*(.-)%s*$")
        if message == "" then
            showMessage(_("Message is empty."))
            return
        end
        local ok, response = Transport.new():send(message)
        Settings.appendTranscript("You: " .. message)
        Settings.appendTranscript("T3: " .. tostring(response))
        if not ok then
            showMessage(tostring(response))
            return
        end

        pending_message = message
        dialog:setInputText("")
        dialog:setHistory((last_rendered or transcriptPreview()) .. "\n\nYou: " .. message)
        last_rendered = dialog.history

        stopPolling()
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

    dialog = T3ChatDialog:new{
        title = chatTitle(),
        history = transcriptPreview(),
        input_hint = _("> Type a message"),
        on_send = sendCurrentMessage,
        on_back = backToAgents,
        on_close = function()
            stopPolling()
            UIManager:close(dialog)
        end,
    }
    last_rendered = dialog.history
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function T3Code:onT3CodeChat()
    local dialog
    dialog = InputDialog:new{
        title = _("T3 Code"),
        input = "",
        input_hint = _("Message a T3 agent"),
        description = _("Uses modular transport. Current default is local stub."),
        allow_newline = true,
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
                    text = _("Send"),
                    is_enter_default = true,
                    callback = function()
                        local message = dialog:getInputText()
                        local transport = Transport.new()
                        local ok, response = transport:send(message)
                        Settings.appendTranscript("You: " .. message)
                        Settings.appendTranscript("T3: " .. tostring(response))
                        UIManager:close(dialog)
                        showMessage((ok and _("Sent") or _("Not sent")) .. "\n" .. tostring(response))
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return T3Code
