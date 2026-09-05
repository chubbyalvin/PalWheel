local BindingEditor = {}
BindingEditor.__index = BindingEditor

local L = require("localization")
local TextLayout = require("text_layout")
local function T(key, variables) return L.get(key, variables) end

local okPalworldBindings, PalworldBindings = pcall(require, "palworld_bindings")

local CONFLICT_SELECTED = { R = 1.00, G = 0.30, B = 0.14, A = 1.0 }
local CURRENT_BOUND = { R = 0.13, G = 0.55, B = 0.13, A = 1.0 }
local WARNING_TEXT = { R = 1.00, G = 0.78, B = 0.16, A = 1.0 }
local WARNING_CHOICE = { R = 0.92, G = 0.48, B = 0.08, A = 1.0 }
local WARNING_SELECTED = { R = 1.00, G = 0.64, B = 0.16, A = 1.0 }

local function setTextColorSafe(widget, color)
    if widget == nil or color == nil then return false end
    local ok = pcall(function()
        widget:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
    end)
    if ok then return true end
    ok = pcall(function()
        local slate = widget.ColorAndOpacity
        slate.SpecifiedColor = color
        slate.ColorUseRule = 0
        widget:SetColorAndOpacity(slate)
    end)
    if ok then return true end
    return pcall(function() widget:SetColorAndOpacity(color) end)
end

local FIELD_INFO = {
    openKey = { action = T("openWheel"), device = "keyboard" },
    keyboardNextWheelButton = { action = T("nextWheel"), device = "keyboard" },
    settingsKey = { action = T("palwheelMenu"), device = "keyboard" },
    controllerOpenButton = { action = T("openWheel"), device = "controller" },
    controllerNextWheelButton = { action = T("nextWheel"), device = "controller" },
    controllerPalWheelMenuButton = { action = T("palwheelMenu"), device = "controller" },
}

local CONTROLLER_LABELS = {
    Gamepad_FaceButton_Bottom = { ps = "Cross", xbox = "A" },
    Gamepad_FaceButton_Right = { ps = "Circle", xbox = "B" },
    Gamepad_FaceButton_Left = { ps = "Square", xbox = "X" },
    Gamepad_FaceButton_Top = { ps = "Triangle", xbox = "Y" },
    Gamepad_LeftShoulder = { ps = "L1", xbox = "LB" },
    Gamepad_RightShoulder = { ps = "R1", xbox = "RB" },
    Gamepad_LeftTrigger = { ps = "L2", xbox = "LT" },
    Gamepad_RightTrigger = { ps = "R2", xbox = "RT" },
    Gamepad_LeftThumbstick = { ps = "L3", xbox = "LS" },
    Gamepad_RightThumbstick = { ps = "R3", xbox = "RS" },
    Gamepad_DPad_Up = { ps = "D-Pad Up", xbox = "D-Pad Up" },
    Gamepad_DPad_Down = { ps = "D-Pad Down", xbox = "D-Pad Down" },
    Gamepad_DPad_Left = { ps = "D-Pad Left", xbox = "D-Pad Left" },
    Gamepad_DPad_Right = { ps = "D-Pad Right", xbox = "D-Pad Right" },
    Gamepad_Special_Left = { ps = "Create / Share", xbox = "View" },
    Gamepad_Special_Right = { ps = "Options", xbox = "Menu" },
    Gamepad_Touchpad_Button = { ps = "Touchpad", xbox = "-" },
    Gamepad_LeftBack = { ps = "-", xbox = "Left Back" },
    Gamepad_RightBack = { ps = "-", xbox = "Right Back" },
    Gamepad_LeftPaddle = { ps = "-", xbox = "Left Paddle" },
    Gamepad_RightPaddle = { ps = "-", xbox = "Right Paddle" },
}

local function normalized(value)
    return string.lower(string.gsub(tostring(value or ""), "[^%w]", ""))
end

local AUX_DIRECT_CONTROLLER_KEYS = {}
for _, name in ipairs({
    "Gamepad_DPad_Left", "Gamepad_DPad_Up", "Gamepad_DPad_Right", "Gamepad_DPad_Down",
    "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
    "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Bottom",
}) do
    AUX_DIRECT_CONTROLLER_KEYS[normalized(name)] = true
end

local function pointInRect(x, y, rect)
    return rect ~= nil and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

local function addUnique(result, seen, value)
    value = tostring(value or "")
    local key = normalized(value)
    if value == "" or key == "" or seen[key] then return end
    seen[key] = true
    result[#result + 1] = value
end

function BindingEditor.new(options)
    local self = setmetatable({
        o = options or {},
        built = false,
        open = false,
        capture = nil,
        pickerField = nil,
        pickerDevice = nil,
        pickerPendingValue = nil,
        overlayWidgets = {},
        captureWidgets = {},
        keyboardPickerWidgets = {},
        controllerPickerWidgets = {},
        modeWidgets = {},
        bindingTexts = {},
        changeRects = {},
        keyboardChoiceRects = {},
        keyboardChoiceBorders = {},
        keyboardChoiceWidgets = {},
        controllerChoiceRects = {},
        controllerChoiceBorders = {},
        draft = nil,
        confirmWidgets = {}, confirmOpen = false,
        saveBorder = nil,
        statusConflictText = nil,
        palworldBindings = nil,
        palworldBindingScanOk = false,
        palworldBindingScanError = nil,
    }, BindingEditor)
    if okPalworldBindings and type(PalworldBindings) == "table"
        and type(PalworldBindings.new) == "function" then
        self.palworldBindings = PalworldBindings.new({ log = self.o.log })
    end
    return self
end

function BindingEditor:displayName(value)
    
    return tostring(value or "")
end

function BindingEditor:current(field, fallback)
    if self.open and type(self.draft) == "table" and self.draft[field] ~= nil then
        return self.draft[field]
    end
    return self.o.cfg(field, fallback)
end

function BindingEditor:snapshotDraft()
    self.draft = {
        openKey = self.o.cfg("openKey", "CapsLock"),
        keyboardNextWheelButton = self.o.cfg("keyboardNextWheelButton", "MiddleMouseButton"),
        settingsKey = self.o.cfg("settingsKey", "F7"),
        controllerOpenButton = self.o.cfg("controllerOpenButton", "Gamepad_LeftShoulder"),
        controllerNextWheelButton = self.o.cfg("controllerNextWheelButton", "Gamepad_RightShoulder"),
        controllerPalWheelMenuButton = self.o.cfg("controllerPalWheelMenuButton", "Gamepad_RightThumbstick"),
        openWheelBehavior = self.o.cfg("openWheelBehavior", "hold"),
    }
end

function BindingEditor:log(message)
    if type(self.o.log) == "function" then self.o.log(message, true) end
end

function BindingEditor:setCaptureInputMode(active, device)
    if type(self.o.captureStateChanged) ~= "function" then return true end
    local ok, result = pcall(self.o.captureStateChanged, active == true, device)
    if not ok or result == false then
        self:log("Binding capture input-mode change failed: " .. tostring(result))
        return false
    end
    return true
end

function BindingEditor:track(group, widget)
    if widget ~= nil then group[#group + 1] = widget end
    return widget
end

function BindingEditor:cell(root, x, y, width, height, color, label, inset, fontSize, justification)
    local o = self.o
    local border = o.construct("/Script/UMG.Border", o.state.tree)
    local slot = border and o.addToCanvas(root, border) or nil
    if slot ~= nil then
        o.place(slot, x, y, width, height)
        o.setBorderColor(border, color)
        pcall(function() border:SetVisibility(o.hitTestInvisible) end)
    end
    local padding = inset or 12
    local size = tonumber(fontSize) or 14
    
    
    
    
    local textH = math.max(18, height - 4)
    local centered = tonumber(justification) == 1
    local textX = centered and (x + width * 0.5) or (x + padding)
    local textY = y + height * 0.5
    local textW = math.max(10, width - padding * 2)
    size = TextLayout.fitFontSize(label or "", size, textW, textH, 8)
    local text = o.createText(o.state.tree, root, label or "",
        textX, textY, textW,
        textH, size, justification or 0)
    pcall(function() if text ~= nil then text:SetAutoWrapText(false) end end)
    
    
    
    pcall(function()
        if text ~= nil and text.Slot ~= nil then
            text.Slot:SetAutoSize(false)
            text.Slot:SetAlignment({ X = centered and 0.5 or 0.0, Y = 0.5 })
            text.Slot:SetPosition({ X = textX, Y = textY })
        end
    end)
    return border, text
end

function BindingEditor:outline(root, x, y, width, height, group)
    local o = self.o
    local function edge(ex, ey, ew, eh)
        local border = o.construct("/Script/UMG.Border", o.state.tree)
        local slot = border and o.addToCanvas(root, border) or nil
        if slot ~= nil then
            o.place(slot, ex, ey, ew, eh)
            o.setBorderColor(border, o.colors.button)
            pcall(function() border:SetVisibility(o.hitTestInvisible) end)
        end
        self:track(group, border)
    end
    edge(x, y, width, 2)
    edge(x, y + height - 2, width, 2)
    edge(x, y, 2, height)
    edge(x + width - 2, y, 2, height)
end

function BindingEditor:setGroupVisible(group, visible)
    for _, widget in ipairs(group or {}) do self.o.setVisible(widget, visible == true) end
end

function BindingEditor:setGroupZOrder(group, z)
    for _, widget in ipairs(group or {}) do
        pcall(function() if widget ~= nil and widget.Slot ~= nil then widget.Slot:SetZOrder(z) end end)
    end
end

function BindingEditor:build(root, summaryRoot)
    if self.built then return true end
    local o = self.o

    local summaryBorder, summaryText = self:cell(summaryRoot or root, 180, 902, 250, 34,
        o.colors.button, "", 8, 11, 1)
    self.summaryText = summaryText
    self.summaryRect = { x = 180, y = 902, w = 250, h = 34 }

    local panel = o.construct("/Script/UMG.Border", o.state.tree)
    local panelSlot = panel and o.addToCanvas(root, panel) or nil
    if panelSlot ~= nil then
        o.place(panelSlot, 360, 190, 1200, 650)
        o.setBorderColor(panel, o.colors.panel)
    end
    self:track(self.overlayWidgets, panel)
    self:outline(root, 360, 190, 1200, 650, self.overlayWidgets)
    self:track(self.overlayWidgets, o.createText(o.state.tree, root,
        T("controlsTitle"), 410, 220, 620, 40, 21, 0))
    local resetBorder, resetText = self:cell(root, 1040, 210, 230, 36,
        o.colors.button, T("restoreDefaults"), 0, 12, 1)
    local instructionsBorder, instructionsText = self:cell(root, 1280, 210, 230, 36,
        o.colors.button, T("instructions"), 0, 12, 1)
    self.resetRect = { x = 1040, y = 210, w = 230, h = 36 }
    self.instructionsRect = { x = 1280, y = 210, w = 230, h = 36 }
    for _, widget in ipairs({ resetBorder, resetText, instructionsBorder, instructionsText }) do
        self:track(self.overlayWidgets, widget)
    end
    self:track(self.overlayWidgets, o.createText(o.state.tree, root,
        T("controlsIntro"),
        410, 262, 1100, 28, 13, 0))

    local actionHeader, actionHeaderText = self:cell(root, 410, 310, 240, 38,
        o.colors.button, T("action"), 14, 14)
    local keyboardHeader, keyboardHeaderText = self:cell(root, 660, 310, 380, 38,
        o.colors.button, T("keyboardMouse"), 14, 14)
    local controllerHeader, controllerHeaderText = self:cell(root, 1050, 310, 460, 38,
        o.colors.button, T("controller"), 14, 14)
    for _, widget in ipairs({ actionHeader, actionHeaderText, keyboardHeader,
        keyboardHeaderText, controllerHeader, controllerHeaderText }) do
        self:track(self.overlayWidgets, widget)
    end

    local rows = {
        { y = 365, action = T("openWheel"), keyboard = "openKey",
            controller = "controllerOpenButton", openMode = true },
        { y = 445, action = T("nextWheel"), keyboard = "keyboardNextWheelButton",
            controller = "controllerNextWheelButton" },
        { y = 525, action = T("palwheelMenu"), keyboard = "settingsKey",
            controller = "controllerPalWheelMenuButton" },
    }
    for _, row in ipairs(rows) do
        local actionBorder, actionText, actionPaddingText
        if row.openMode then
            actionBorder, actionPaddingText = self:cell(root, 410, row.y, 240, 72,
                o.colors.row, "", 14, 15)
            
            
            actionText = o.createText(o.state.tree, root,
                row.action, 424, row.y + 2, 210, 34, 15, 0)
            local modeLabel = o.createText(o.state.tree, root,
                T("mode"), 424, row.y + 36, 58, 28, 11, 0)
            local modeBorder, modeText = self:cell(root, 490, row.y + 34, 104, 28,
                o.colors.button, "", 8, 11)
            self.openModeText = modeText
            self.openModeBorder = modeBorder
            self.openModeRect = { x = 490, y = row.y + 34, w = 104, h = 28 }
            for _, widget in ipairs({ actionPaddingText, modeLabel, modeBorder, modeText }) do
                self:track(self.overlayWidgets, widget)
            end
            for _, widget in ipairs({ modeLabel, modeBorder, modeText }) do
                self:track(self.modeWidgets, widget)
            end
        else
            actionBorder, actionText = self:cell(root, 410, row.y, 240, 62,
                o.colors.row, row.action, 14, 15)
        end

        local keyboardBorder, keyboardText = self:cell(root, 660, row.y, 250, 62,
            o.colors.rowAlt, "", 14, 12)
        local keyboardChangeBorder, keyboardChangeText = self:cell(root, 920, row.y, 120, 62,
            o.colors.button, T("change"), 0, 11, 1)

        local controllerBorder, controllerText
        local controllerChangeBorder, controllerChangeText
        if row.controller ~= nil then
            controllerBorder, controllerText = self:cell(root, 1050, row.y, 330, 62,
                o.colors.rowAlt, "", 14, 11)
            controllerChangeBorder, controllerChangeText = self:cell(root, 1390, row.y, 120, 62,
                o.colors.button, T("change"), 0, 11, 1)
        end

        for _, widget in ipairs({ actionBorder, actionText, keyboardBorder, keyboardText,
            keyboardChangeBorder, keyboardChangeText, controllerBorder, controllerText,
            controllerChangeBorder, controllerChangeText }) do
            self:track(self.overlayWidgets, widget)
        end
        self.bindingTexts[row.keyboard] = keyboardText
        self.changeRects[row.keyboard] = { x = 920, y = row.y, w = 120, h = 62 }
        if row.controller ~= nil then
            self.bindingTexts[row.controller] = controllerText
            self.changeRects[row.controller] = { x = 1390, y = row.y, w = 120, h = 62 }
        end
    end

    self.controllerMenuHelp = self:track(self.overlayWidgets,
        o.createText(o.state.tree, root, T("mainWheelRequired"),
            1050, 590, 460, 16, 9, 0))
    pcall(function()
        if self.controllerMenuHelp ~= nil then self.controllerMenuHelp:SetRenderOpacity(0.58) end
    end)

    self.statusText = self:track(self.overlayWidgets, o.createText(o.state.tree, root,
        T("controlsUnique"),
        410, 610, 1100, 30, 13, 0))
    
    
    self.statusConflictText = self:track(self.overlayWidgets, o.createText(o.state.tree, root,
        "", 410, 642, 1100, 88, 13, 0))
    pcall(function() self.statusConflictText:SetAutoWrapText(true) end)
    pcall(function() self.statusConflictText:SetWrapTextAt(1090.0) end)
    setTextColorSafe(self.statusConflictText, WARNING_TEXT)
    
    
    
    local saveBorder, saveText = self:cell(root, 1010, 742, 300, 48,
        o.colors.saveIdle or o.colors.row, T("saveAndApply"), 0, 14, 1)
    self.saveBorder = saveBorder
    local closeBorder, closeText = self:cell(root, 1320, 742, 190, 48,
        o.colors.row, T("close"), 0, 14, 1)
    self.saveRect = { x = 1010, y = 742, w = 300, h = 48 }
    self.closeRect = { x = 1320, y = 742, w = 190, h = 48 }
    for _, widget in ipairs({ saveBorder, saveText, closeBorder, closeText }) do
        self:track(self.overlayWidgets, widget)
    end

    self:buildCapturePanel(root)
    self:buildKeyboardPicker(root)
    self:buildControllerPicker(root)
    self:buildDiscardPanel(root)
    self:setGroupZOrder(self.overlayWidgets, 40)
    self:setGroupZOrder(self.modeWidgets, 45)
    self:setGroupZOrder(self.captureWidgets, 55)
    self:setGroupZOrder(self.keyboardPickerWidgets, 50)
    self:setGroupZOrder(self.controllerPickerWidgets, 50)
    self:setGroupZOrder(self.confirmWidgets, 60)
    self:setGroupVisible(self.overlayWidgets, false)
    self:setGroupVisible(self.captureWidgets, false)
    self:setGroupVisible(self.keyboardPickerWidgets, false)
    self:setGroupVisible(self.controllerPickerWidgets, false)
    self:setGroupVisible(self.confirmWidgets, false)
    self.built = true
    self:updateTexts()
    o.setVisible(summaryBorder, true)
    o.setVisible(summaryText, true)
    return true
end

function BindingEditor:buildCapturePanel(root)
    local o = self.o
    local panel = o.construct("/Script/UMG.Border", o.state.tree)
    local slot = panel and o.addToCanvas(root, panel) or nil
    if slot ~= nil then
        o.place(slot, 545, 325, 830, 330)
        o.setBorderColor(panel, o.colors.panel)
    end
    self:track(self.captureWidgets, panel)
    self:outline(root, 545, 325, 830, 330, self.captureWidgets)
    self.captureTitle = self:track(self.captureWidgets,
        o.createText(o.state.tree, root, T("automaticDetection"), 595, 365, 730, 36, 19, 0))
    self.capturePrompt = self:track(self.captureWidgets,
        o.createText(o.state.tree, root, "", 595, 420, 730, 70, 16, 0))
    self.captureStatus = self:track(self.captureWidgets,
        o.createText(o.state.tree, root, T("pressNewInput"), 595, 505, 730, 40, 14, 0))
    local cancelBorder, cancelText = self:cell(root, 845, 570, 230, 48,
        o.colors.row, T("cancel"), 82, 14)
    self.captureCancelRect = { x = 845, y = 570, w = 230, h = 48 }
    self:track(self.captureWidgets, cancelBorder)
    self:track(self.captureWidgets, cancelText)
end

function BindingEditor:buildKeyboardPicker(root)
    local o = self.o
    local panel = o.construct("/Script/UMG.Border", o.state.tree)
    local slot = panel and o.addToCanvas(root, panel) or nil
    if slot ~= nil then
        o.place(slot, 360, 230, 1200, 570)
        
        
        o.setBorderColor(panel, o.colors.panel)
    end
    self:track(self.keyboardPickerWidgets, panel)
    self:outline(root, 360, 230, 1200, 570, self.keyboardPickerWidgets)
    self.keyboardPickerTitle = self:track(self.keyboardPickerWidgets,
        o.createText(o.state.tree, root, T("chooseKeyboardBinding"), 400, 250, 1120, 30, 19, 0))
    self.keyboardPickerCurrent = self:track(self.keyboardPickerWidgets,
        o.createText(o.state.tree, root, "", 400, 280, 1120, 24, 12, 0))

    local allowed = {}
    for _, name in ipairs(self.o.cfg("keyboardBindingKeys", {}) or {}) do allowed[name] = true end
    local seen = {}
    local keyH, gap = 28, 4
    local baseX = 400

    local pretty = {
        Escape="ESC", BackSpace="BACKSPACE", CapsLock="CAPS", Enter="ENTER",
        SpaceBar="SPACE", LeftShift="SHIFT", RightShift="SHIFT", LeftControl="CTRL",
        RightControl="CTRL", LeftAlt="ALT", RightAlt="ALT", PrintScreen="PRT SC",
        ScrollLock="SCR LK", NumLock="NUM LK", PageUp="PG UP", PageDown="PG DN",
        Insert="INS", Delete="DEL", Left="LEFT", Right="RIGHT", Up="UP", Down="DOWN",
        Tilde="`", Hyphen="-", Equals="=", Semicolon=";", Apostrophe="'",
        Comma=",", Period=".", Slash="/", LeftBracket="[", RightBracket="]",
        Backslash="\\", LeftMouseButton="LMB", RightMouseButton="RMB",
        MiddleMouseButton="MMB", ThumbMouseButton="MOUSE 4", ThumbMouseButton2="MOUSE 5",
    }
    local digits = { Zero="0", One="1", Two="2", Three="3", Four="4",
        Five="5", Six="6", Seven="7", Eight="8", Nine="9" }
    local numpad = { NumPadZero="0", NumPadOne="1", NumPadTwo="2", NumPadThree="3",
        NumPadFour="4", NumPadFive="5", NumPadSix="6", NumPadSeven="7",
        NumPadEight="8", NumPadNine="9", Multiply="*", Add="+", Subtract="-",
        Decimal=".", Divide="/" }

    local function labelFor(name)
        return pretty[name] or digits[name] or numpad[name] or tostring(name)
    end

    local function addChoice(name, x, y, width, font)
        if not allowed[name] or seen[name] then return false end
        seen[name] = true
        local border, text = self:cell(root, x, y, width, keyH,
            o.colors.rowAlt, labelFor(name), 0, font or 8, 1)
        self.keyboardChoiceRects[name] = { x = x, y = y, w = width, h = keyH }
        self.keyboardChoiceBorders[name] = border
        self.keyboardChoiceWidgets[name] = { border, text }
        self:track(self.keyboardPickerWidgets, border)
        self:track(self.keyboardPickerWidgets, text)
        return true
    end

    
    local y = 310
    addChoice("Escape", baseX, y, 50, 8)
    local x = baseX + 64
    for i = 1, 12 do
        addChoice("F" .. i, x, y, 44, 8)
        x = x + 48
        if i == 4 or i == 8 then x = x + 10 end
    end
    y = 342
    x = baseX + 64
    for i = 13, 24 do
        addChoice("F" .. i, x, y, 44, 8)
        x = x + 48
        if i == 16 or i == 20 then x = x + 10 end
    end

    local unit = 48
    y = 378
    x = baseX
    for _, name in ipairs({"Tilde","One","Two","Three","Four","Five","Six","Seven","Eight","Nine","Zero","Hyphen","Equals"}) do
        addChoice(name, x, y, unit, 9); x = x + unit + gap
    end
    addChoice("BackSpace", x, y, 104, 7)

    y = 410
    x = baseX
    addChoice("Tab", x, y, 72, 8); x = x + 72 + gap
    for _, name in ipairs({"Q","W","E","R","T","Y","U","I","O","P","LeftBracket","RightBracket","Backslash"}) do
        addChoice(name, x, y, unit, 9); x = x + unit + gap
    end

    y = 442
    x = baseX
    addChoice("CapsLock", x, y, 86, 8); x = x + 86 + gap
    for _, name in ipairs({"A","S","D","F","G","H","J","K","L","Semicolon","Apostrophe"}) do
        addChoice(name, x, y, unit, 9); x = x + unit + gap
    end
    addChoice("Enter", x, y, 96, 8)

    y = 474
    x = baseX
    addChoice("LeftShift", x, y, 104, 8); x = x + 104 + gap
    for _, name in ipairs({"Z","X","C","V","B","N","M","Comma","Period","Slash"}) do
        addChoice(name, x, y, unit, 9); x = x + unit + gap
    end
    addChoice("RightShift", x, y, 104, 8)

    y = 506
    x = baseX
    addChoice("LeftControl", x, y, 82, 8); x = x + 82 + gap
    addChoice("LeftAlt", x, y, 72, 8); x = x + 72 + gap
    addChoice("SpaceBar", x, y, 350, 8); x = x + 350 + gap
    addChoice("RightAlt", x, y, 72, 8); x = x + 72 + gap
    addChoice("RightControl", x, y, 82, 8)

    
    local sideX, navW = 1200, 78
    for row, entries in ipairs({
        {"Insert","Home","PageUp"}, {"Delete","End","PageDown"},
    }) do
        x = sideX
        for _, name in ipairs(entries) do
            addChoice(name, x, 378 + (row - 1) * 32, navW, 7)
            x = x + navW + gap
        end
    end
    addChoice("Up", sideX + navW + gap, 446, navW, 8)
    addChoice("Left", sideX, 478, navW, 7)
    addChoice("Down", sideX + navW + gap, 478, navW, 7)
    addChoice("Right", sideX + 2 * (navW + gap), 478, navW, 7)

    
    local numX, numW, numY = 1200, 56, 518
    local numRows = {
        {"NumPadSeven","NumPadEight","NumPadNine","Divide"},
        {"NumPadFour","NumPadFive","NumPadSix","Multiply"},
        {"NumPadOne","NumPadTwo","NumPadThree","Subtract"},
        {"NumPadZero","Decimal","Add"},
    }
    for r, entries in ipairs(numRows) do
        x = numX
        for _, name in ipairs(entries) do
            addChoice(name, x, numY + (r - 1) * 32, numW, 8)
            x = x + numW + gap
        end
    end

    
    y = 550
    x = baseX
    for _, entry in ipairs({
        {"LeftMouseButton",92},{"RightMouseButton",92},{"MiddleMouseButton",92},
        {"ThumbMouseButton",104},{"ThumbMouseButton2",104},
    }) do
        addChoice(entry[1], x, y, entry[2], 7); x = x + entry[2] + gap
    end
    y = 582
    x = baseX
    for _, entry in ipairs({{"Pause",82},{"PrintScreen",90},{"ScrollLock",90},{"NumLock",82}}) do
        addChoice(entry[1], x, y, entry[2], 7); x = x + entry[2] + gap
    end

    
    local extras = {}
    for _, name in ipairs(self.o.cfg("keyboardBindingKeys", {}) or {}) do
        if not seen[name] then extras[#extras + 1] = name end
    end
    if #extras > 0 then
        local otherText = self:track(self.keyboardPickerWidgets,
            o.createText(o.state.tree, root, T("other"), 400, 618, 65, 22, 9, 0))
        x = 468
        for _, name in ipairs(extras) do
            addChoice(name, x, 614, 78, 7); x = x + 82
        end
    end

    self.keyboardPickerReason = self:track(self.keyboardPickerWidgets,
        o.createText(o.state.tree, root,
            T("selectKeyInfo"), 400, 650, 1120, 70, 11, 0))
    pcall(function() self.keyboardPickerReason:SetAutoWrapText(true) end)

    
    
    local confirmBorder, confirmText = self:cell(root, 470, 730, 245, 44,
        o.colors.row, T("confirm"), 0, 12, 1)
    local autoBorder, autoText = self:cell(root, 755, 730, 330, 44,
        o.colors.button, T("automaticDetection"), 0, 12, 1)
    local cancelBorder, cancelText = self:cell(root, 1125, 730, 245, 44,
        o.colors.row, T("cancel"), 0, 12, 1)
    self.keyboardPickerConfirmRect = { x = 470, y = 730, w = 245, h = 44 }
    self.keyboardAutoRect = { x = 755, y = 730, w = 330, h = 44 }
    self.keyboardPickerCancelRect = { x = 1125, y = 730, w = 245, h = 44 }
    for _, widget in ipairs({ confirmBorder, confirmText, autoBorder, autoText, cancelBorder, cancelText }) do
        self:track(self.keyboardPickerWidgets, widget)
    end
end

function BindingEditor:buildControllerPicker(root)
    local o = self.o
    local panel = o.construct("/Script/UMG.Border", o.state.tree)
    local slot = panel and o.addToCanvas(root, panel) or nil
    local panelX, panelY, panelW, panelH = 550, 178, 820, 689
    if slot ~= nil then
        o.place(slot, panelX, panelY, panelW, panelH)
        o.setBorderColor(panel, o.colors.panel)
    end
    self:track(self.controllerPickerWidgets, panel)
    self:outline(root, panelX, panelY, panelW, panelH, self.controllerPickerWidgets)
    self.controllerPickerTitle = self:track(self.controllerPickerWidgets,
        o.createText(o.state.tree, root, T("chooseControllerBinding"), 600, 214, 720, 32, 19, 0))
    self.controllerPickerCurrent = self:track(self.controllerPickerWidgets,
        o.createText(o.state.tree, root, "", 600, 246, 720, 24, 11, 0))

    local tableX = 635
    local keyW, psW, xboxW = 312, 132, 156
    local gap = 6
    local psX = tableX + keyW + gap
    local xboxX = psX + psW + gap
    local headerY, headerH = 278, 30
    local keyHeader, keyHeaderText = self:cell(root, tableX, headerY, keyW, headerH,
        o.colors.button, T("inputKey"), 12, 11)
    local psHeader, psHeaderText = self:cell(root, psX, headerY, psW, headerH,
        o.colors.button, T("ps"), 0, 11, 1)
    local xboxHeader, xboxHeaderText = self:cell(root, xboxX, headerY, xboxW, headerH,
        o.colors.button, T("xbox"), 0, 11, 1)
    for _, widget in ipairs({ keyHeader, keyHeaderText, psHeader, psHeaderText,
        xboxHeader, xboxHeaderText }) do
        self:track(self.controllerPickerWidgets, widget)
    end

    local all = self.o.cfg("controllerBindingKeys", {}) or {}
    local rowH, rowGap = 24, 3
    local firstY = headerY + headerH + 4
    for index, name in ipairs(all) do
        local y = firstY + (index - 1) * (rowH + rowGap)
        local labels = CONTROLLER_LABELS[name] or { ps = "-", xbox = "-" }
        local psTexture = type(o.glyphTextureForKey) == "function"
            and o.glyphTextureForKey(name, "dualsense") or nil
        local xboxTexture = type(o.glyphTextureForKey) == "function"
            and o.glyphTextureForKey(name, "xbox") or nil
        local keyBorder, keyText = self:cell(root, tableX, y, keyW, rowH,
            o.colors.rowAlt, tostring(name), 8, 10)
        local psBorder, psText = self:cell(root, psX, y, psW, rowH,
            o.colors.row, psTexture ~= nil and "" or (labels.ps or "-"), 0, 10, 1)
        local xboxBorder, xboxText = self:cell(root, xboxX, y, xboxW, rowH,
            o.colors.row, xboxTexture ~= nil and "" or (labels.xbox or "-"), 0, 10, 1)
        local psGlyph = psTexture ~= nil and type(o.createIcon) == "function"
            and o.createIcon(o.state.tree, root, psTexture,
                psX + psW * 0.5, y + rowH * 0.5, 20) or nil
        local xboxGlyph = xboxTexture ~= nil and type(o.createIcon) == "function"
            and o.createIcon(o.state.tree, root, xboxTexture,
                xboxX + xboxW * 0.5, y + rowH * 0.5, 20) or nil
        self.controllerChoiceRects[name] = { x = tableX, y = y, w = keyW, h = rowH }
        self.controllerChoiceBorders[name] = keyBorder
        
        
        
        
        
        for _, widget in ipairs({ keyBorder, keyText, psBorder, psText, xboxBorder, xboxText }) do
            self:track(self.controllerPickerWidgets, widget)
        end
        self:track(self.controllerPickerWidgets, psGlyph)
        self:track(self.controllerPickerWidgets, xboxGlyph)
    end

    
    
    
    self.controllerPickerReason = self:track(self.controllerPickerWidgets,
        o.createText(o.state.tree, root,
            T("selectButtonInfo"), 600, 746, 720, 56, 10, 0))
    pcall(function() self.controllerPickerReason:SetAutoWrapText(true) end)

    local confirmBorder, confirmText = self:cell(root, 610, 808, 200, 44,
        o.colors.row, T("confirm"), 56, 12)
    local autoBorder, autoText = self:cell(root, 825, 808, 285, 44,
        o.colors.button, T("automaticDetection"), 42, 11)
    local cancelBorder, cancelText = self:cell(root, 1125, 808, 185, 44,
        o.colors.row, T("cancel"), 57, 12)
    self.controllerPickerConfirmRect = { x = 610, y = 808, w = 200, h = 44 }
    self.controllerAutoRect = { x = 825, y = 808, w = 285, h = 44 }
    self.controllerPickerCancelRect = { x = 1125, y = 808, w = 185, h = 44 }
    for _, widget in ipairs({ confirmBorder, confirmText, autoBorder, autoText, cancelBorder, cancelText }) do
        self:track(self.controllerPickerWidgets, widget)
    end
end

function BindingEditor:buildDiscardPanel(root)
    local o = self.o
    local panel = o.construct("/Script/UMG.Border", o.state.tree)
    local slot = panel and o.addToCanvas(root, panel) or nil
    if slot ~= nil then
        o.place(slot, 555, 350, 810, 250)
        o.setBorderColor(panel, o.colors.panel)
    end
    self:track(self.confirmWidgets, panel)
    self:outline(root, 555, 350, 810, 250, self.confirmWidgets)
    self:track(self.confirmWidgets, o.createText(o.state.tree, root,
        T("discardControlsTitle"), 605, 385, 710, 38, 18, 0))
    self:track(self.confirmWidgets, o.createText(o.state.tree, root,
        T("discardControlsBody"),
        605, 440, 710, 55, 13, 0))
    local discardBorder, discardText = self:cell(root, 700, 520, 210, 46,
        o.colors.unavailable or o.colors.row, T("discard"), 60, 14)
    local cancelBorder, cancelText = self:cell(root, 970, 520, 210, 46,
        o.colors.button, T("cancel"), 62, 14)
    self.confirmDiscardRect = { x = 700, y = 520, w = 210, h = 46 }
    self.confirmCancelRect = { x = 970, y = 520, w = 210, h = 46 }
    for _, widget in ipairs({ discardBorder, discardText, cancelBorder, cancelText }) do
        self:track(self.confirmWidgets, widget)
    end
end

function BindingEditor:hasUnsavedChanges()
    if type(self.draft) ~= "table" then return false end
    local fields = {
        "openKey", "keyboardNextWheelButton", "settingsKey",
        "controllerOpenButton", "controllerNextWheelButton", "controllerPalWheelMenuButton", "openWheelBehavior",
    }
    for _, field in ipairs(fields) do
        local fallback = field == "openWheelBehavior" and "hold" or ""
        if tostring(self.draft[field] or fallback) ~= tostring(self.o.cfg(field, fallback) or fallback) then
            return true
        end
    end
    return false
end

function BindingEditor:updateSaveVisual()
    if self.saveBorder ~= nil then
        self.o.setBorderColor(self.saveBorder,
            self:hasUnsavedChanges() and (self.o.colors.saveDirty or self.o.colors.button)
                or (self.o.colors.saveIdle or self.o.colors.row))
    end
end

function BindingEditor:setConfirmVisible(visible)
    self.confirmOpen = visible == true
    self:setGroupVisible(self.confirmWidgets, self.confirmOpen)
end

function BindingEditor:requestClose()
    if self:hasUnsavedChanges() then
        self:setConfirmVisible(true)
        return false
    end
    self:closePanel(true)
    return true
end

function BindingEditor:updateTexts()
    if not self.built then return end
    local o = self.o
    local values = {
        openKey = self:displayName(self:current("openKey", "CapsLock")),
        keyboardNextWheelButton = self:displayName(self:current("keyboardNextWheelButton", "MiddleMouseButton")),
        settingsKey = self:displayName(self:current("settingsKey", "F7")),
        controllerOpenButton = self:displayName(self:current("controllerOpenButton", "Gamepad_LeftShoulder")),
        controllerNextWheelButton = self:displayName(self:current("controllerNextWheelButton", "Gamepad_RightShoulder")),
        controllerPalWheelMenuButton = self:displayName(self:current("controllerPalWheelMenuButton", "Gamepad_RightThumbstick")),
    }
    for field, text in pairs(self.bindingTexts) do o.setText(text, tostring(values[field] or "")) end
    if self.summaryText ~= nil then
        o.setText(self.summaryText, T("controlsEdit"))
    end
    if self.openModeText ~= nil then
        local behavior = string.lower(tostring(self:current("openWheelBehavior", "hold")))
        o.setText(self.openModeText, T(behavior == "toggle" and "toggle" or "hold"))
    end
    self:updateSaveVisual()
end

function BindingEditor:isSummaryHit(x, y)
    return self.built and not self.open and pointInRect(x, y, self.summaryRect)
end

function BindingEditor:isOpen() return self.open == true end
function BindingEditor:isCapturing() return self.capture ~= nil end

function BindingEditor:handleReservedSettingsKey()
    if self.capture == nil then return false end
    local name = self:displayName(self:current("settingsKey", "F7"))
    local message
    if self.capture.field == "settingsKey" then
        message = name .. " is already the PalWheel Menu key. Press another input to change it."
    else
        message = name .. " is reserved for the PalWheel Menu. Press another input."
    end
    self.o.setText(self.captureStatus, message)
    self:setStatus(T("notSavedPrefix", { message = message }))
    return true
end

function BindingEditor:openPanel()
    if not self.built then return false end
    self.open = true
    self.capture = nil
    self.pickerField = nil
    self.pickerDevice = nil
    self.pickerPendingValue = nil
    self:snapshotDraft()
    self:setConfirmVisible(false)
    self:setGroupVisible(self.overlayWidgets, true)
    self:setGroupVisible(self.captureWidgets, false)
    self:setGroupVisible(self.keyboardPickerWidgets, false)
    self:setGroupVisible(self.controllerPickerWidgets, false)
    self:updateTexts()
    self:setStatus(
        T("controlsDraftHelp"))
    return true
end

function BindingEditor:closePicker()
    self.pickerField = nil
    self.pickerDevice = nil
    self.pickerPendingValue = nil
    self:setGroupVisible(self.keyboardPickerWidgets, false)
    self:setGroupVisible(self.controllerPickerWidgets, false)
end

function BindingEditor:closePanel(force)
    if force ~= true and self.open and self:hasUnsavedChanges() then
        self:setConfirmVisible(true)
        return false
    end
    if self.capture ~= nil then self:setCaptureInputMode(false, self.capture.device) end
    self.open = false
    self.capture = nil
    self:closePicker()
    self.draft = nil
    self:setConfirmVisible(false)
    self:setGroupVisible(self.overlayWidgets, false)
    self:setGroupVisible(self.captureWidgets, false)
    self:updateTexts()
    return true
end

function BindingEditor:refreshPalworldBindings()
    self.palworldBindingScanOk = false
    self.palworldBindingScanError = nil
    if self.palworldBindings == nil or type(self.palworldBindings.scan) ~= "function" then
        self.palworldBindingScanError = "Palworld binding reader is unavailable"
        return false
    end
    local ok, result, why = pcall(function() return self.palworldBindings:scan() end)
    if ok and result == true then
        self.palworldBindingScanOk = true
        return true
    end
    self.palworldBindingScanError = tostring((ok and why) or result or "unknown error")
    self:log("Live Palworld binding scan unavailable: " .. self.palworldBindingScanError)
    return false
end

function BindingEditor:isListedBindingKey(device, name)
    local target = normalized(name)
    local values = device == "controller"
        and self.o.cfg("controllerBindingKeys", {}) or self.o.cfg("keyboardBindingKeys", {})
    for _, value in ipairs(values or {}) do
        if normalized(value) == target then return true end
    end
    return false
end

function BindingEditor:isSupportedBindingKey(device, name)
    local target = normalized(name)
    local values = device == "controller"
        and self.o.cfg("controllerCancelButtons", self.o.cfg("controllerBindingKeys", {}))
        or self.o.cfg("keyboardCancelKeys", self.o.cfg("keyboardBindingKeys", {}))
    for _, value in ipairs(values or {}) do
        if normalized(value) == target then return true end
    end
    return false
end

function BindingEditor:isMovementKey(device, name)
    local values = device == "controller"
        and self.o.cfg("controllerMovementKeys", {}) or self.o.cfg("keyboardMovementKeys", {})
    local target = normalized(name)
    for _, value in ipairs(values or {}) do
        if normalized(value) == target then return true end
    end
    if self.palworldBindingScanOk and self.palworldBindings ~= nil
        and type(self.palworldBindings.isMovement) == "function" then
        return self.palworldBindings:isMovement(device, name) == true
    end
    return false
end

function BindingEditor:palworldLabels(device, name)
    local result, seen = {}, {}
    local function append(label)
        local text = tostring(label or "")
        if text == "" then return end
        local id = normalized(text)
        if id == "" or seen[id] then return end
        seen[id] = true
        result[#result + 1] = text
    end

    
    if self.palworldBindingScanOk and self.palworldBindings ~= nil
        and type(self.palworldBindings.labels) == "function" then
        for _, label in ipairs(self.palworldBindings:labels(device, name) or {}) do
            append(label)
        end
    end

    
    
    
    if device == "keyboard" then
        local key = normalized(name)
        local aimMouse = normalized(self.o.cfg("aimMouseButton", "RightMouseButton"))
        local launcherAimMouse = normalized(self.o.cfg("keyboardSphereLauncherAimButton",
            "RightMouseButton"))
        if key ~= "" and (key == aimMouse or key == launcherAimMouse) then
            append("Aim")
        end
    end

    return result
end

function BindingEditor:pickerIssue(device, field, name)
    local key = normalized(name)
    local info = FIELD_INFO[field]
    if info == nil then return { blocked = true, message = T("unavailableUnknownControl") } end
    if not self:isListedBindingKey(device, name) then
        return { blocked = true, message = T("unavailableSelectableSet") }
    end

    local hardReason = nil
    local warningReasons = {}
    local contextualController = device == "controller"
        and (field == "controllerNextWheelButton"
            or field == "controllerPalWheelMenuButton")

    if device == "keyboard" then
        local settingsKey = normalized(self:current("settingsKey", "F7"))
        local activateKey = normalized(self.o.cfg("mouseActivateButton", "LeftMouseButton"))
        local isMouse = string.find(string.lower(tostring(name)), "mouse", 1, true) ~= nil
        if self:isMovementKey(device, name) then
            hardReason = T("movementControlBlocked", { key = name })
        elseif key == activateKey then
            hardReason = T("mouseSelectionReserved", { key = name })
        elseif field ~= "settingsKey" and key == settingsKey then
            hardReason = T("alreadyMenuKey", { key = name })
        elseif field == "settingsKey" and isMouse then
            hardReason = T("mouseMenuBlocked")
        elseif field == "settingsKey"
            and (key == normalized(self:current("openKey", "CapsLock"))
                or key == normalized(self:current("keyboardNextWheelButton", "MiddleMouseButton"))) then
            hardReason = T("menuShareBlocked")
        elseif field ~= "settingsKey" then
            local other = field == "openKey" and "keyboardNextWheelButton" or "openKey"
            if key == normalized(self:current(other, "")) then
                hardReason = T("openNextDifferent")
            end
        end
        if hardReason == nil and type(self.o.shortcutKeyConflict) == "function" then
            local conflict = self.o.shortcutKeyConflict(name)
            if conflict ~= nil then
                hardReason = T("shortcutKeyInUse", { key = name,
                    shortcut = conflict.label or conflict.id or T("unknown") })
            end
        end
    else
        
        
        
        
        
        
        if contextualController then
            for _, other in ipairs({ "controllerOpenButton", "controllerNextWheelButton",
                "controllerPalWheelMenuButton" }) do
                if other ~= field and key == normalized(self:current(other, "")) then
                    hardReason = T("controllerBindingsDifferent")
                    break
                end
            end
            if AUX_DIRECT_CONTROLLER_KEYS[key] then
                warningReasons[#warningReasons + 1] = T("auxConflict", { key = name })
            end
        else
            if self:isMovementKey(device, name) then
                hardReason = T("movementInputBlocked", { key = name })
            else
                for _, other in ipairs({ "controllerOpenButton", "controllerNextWheelButton",
                    "controllerPalWheelMenuButton" }) do
                    if other ~= field and key == normalized(self:current(other, "")) then
                        hardReason = T("controllerBindingsDifferent")
                        break
                    end
                end
            end
            if AUX_DIRECT_CONTROLLER_KEYS[key] then
                warningReasons[#warningReasons + 1] = T("auxConflict", { key = name })
            end
        end
    end

    
    
    
    if device == "controller"
        and (field == "controllerOpenButton" or field == "controllerNextWheelButton"
            or field == "controllerPalWheelMenuButton") then
        local zoomEnabled = self.o.cfg("controllerZoomEnabled", true) == true
        if type(self.o.controllerZoomEnabled) == "function" then
            local okZoom, currentZoomEnabled = pcall(self.o.controllerZoomEnabled)
            if okZoom then zoomEnabled = currentZoomEnabled == true end
        end
        if zoomEnabled and (key == normalized("Gamepad_LeftTrigger")
            or key == normalized("Gamepad_RightTrigger")) then
            warningReasons[#warningReasons + 1] = T(
                key == normalized("Gamepad_LeftTrigger") and "zoomInConflict" or "zoomOutConflict",
                { key = name })
        end
    end

    
    
    
    local labels = contextualController and {} or self:palworldLabels(device, name)
    if #labels > 0 then
        warningReasons[#warningReasons + 1] = T("palworldUsesKey", {
            key = name, actions = table.concat(labels, ", ") })
    end

    if hardReason ~= nil then
        local message = T("unavailableReason", { reason = hardReason })
        if #warningReasons > 0 then message = message .. "  " .. table.concat(warningReasons, "  ") end
        return { blocked = true, warning = true, message = message, labels = labels }
    end
    if #warningReasons > 0 then
        return { blocked = false, warning = true,
            message = T("conflictAllowed", { reason = table.concat(warningReasons, "  ") }),
            labels = labels }
    end
    if not self.palworldBindingScanOk and device == "keyboard" then
        return { blocked = false, warning = false,
            message = T("noConflictLimited") }
    end
    return { blocked = false, warning = false, message = T("noKnownConflict") }
end

function BindingEditor:pickerColor(device, field, name)
    local issue = self:pickerIssue(device, field, name)
    local key = normalized(name)
    local current = normalized(self:current(field, ""))
    local selected = key == normalized(self.pickerPendingValue)

    
    
    
    if key == current then return CURRENT_BOUND end

    
    
    
    if issue.blocked then
        return selected and CONFLICT_SELECTED or self.o.colors.unavailable
    end
    if selected then
        return self.o.colors.weapon or self.o.colors.selected
    end
    if issue.warning then
        return WARNING_CHOICE
    end
    return self.o.colors.rowAlt
end

function BindingEditor:refreshPickerVisuals()
    local field, device = self.pickerField, self.pickerDevice
    if field == nil or device == nil then return end
    local current = self:displayName(self:current(field, ""))
    local selected = self:displayName(self.pickerPendingValue or current)
    local issue = self:pickerIssue(device, field, selected)

    local reason = tostring(issue.message or "")
    local warn = issue.warning == true or issue.blocked == true
    if warn then reason = "⚠ " .. reason end
    local function styleReason(widget)
        if widget == nil then return end
        self.o.setText(widget, reason)
        local color = warn and WARNING_TEXT
            or (self.o.colors.text or { R = 1, G = 1, B = 1, A = 1 })
        setTextColorSafe(widget, color)
    end

    if device == "keyboard" then
        self.o.setText(self.keyboardPickerCurrent, T("currentSelected", { current = current, selected = selected }))
        styleReason(self.keyboardPickerReason)
        for name, border in pairs(self.keyboardChoiceBorders) do
            for _, widget in ipairs(self.keyboardChoiceWidgets[name] or {}) do self.o.setVisible(widget, true) end
            self.o.setBorderColor(border, self:pickerColor(device, field, name))
        end
    else
        self.o.setText(self.controllerPickerCurrent, T("currentSelected", { current = current, selected = selected }))
        styleReason(self.controllerPickerReason)
        for name, border in pairs(self.controllerChoiceBorders) do
            self.o.setBorderColor(border, self:pickerColor(device, field, name))
        end
    end
end

function BindingEditor:selectPending(name)
    if self.pickerField == nil then return false end
    self.pickerPendingValue = tostring(name or "")
    self:refreshPickerVisuals()
    return true
end

function BindingEditor:candidateNames(device, field)
    local result, seen = {}, {}
    local values = device == "controller"
        and self.o.cfg("controllerBindingKeys", self.o.cfg("controllerCancelButtons", {}))
        or self.o.cfg("keyboardBindingKeys", self.o.cfg("keyboardCancelKeys", {}))
    for _, value in ipairs(values or {}) do
        local issue = self:pickerIssue(device, field, value)
        if issue.blocked ~= true then addUnique(result, seen, value) end
    end
    return result
end

function BindingEditor:choiceAllowed(device, field, name)
    if not self:isListedBindingKey(device, name) then return false end
    return self:pickerIssue(device, field, name).blocked ~= true
end

function BindingEditor:openPicker(field)
    local info = FIELD_INFO[field]
    if info == nil then return false end
    self.capture = nil
    self.pickerField = field
    self.pickerDevice = info.device
    self.pickerPendingValue = self:current(field, "")
    self:refreshPalworldBindings()
    self:setGroupVisible(self.captureWidgets, false)
    self:setGroupVisible(self.keyboardPickerWidgets, info.device == "keyboard")
    self:setGroupVisible(self.controllerPickerWidgets, info.device == "controller")
    if info.device == "keyboard" then
        self.o.setText(self.keyboardPickerTitle, info.action .. " - " .. T("keyboardMouse"))
    else
        self.o.setText(self.controllerPickerTitle, info.action .. " - " .. T("controller"))
    end
    self:refreshPickerVisuals()
    self:log("Manual binding picker opened: " .. tostring(field) .. " (" .. tostring(info.device) .. ")")
    return true
end

function BindingEditor:makeCandidate(name)
    return { name = name, key = self.o.makeFKey(name), down = false, ready = true }
end

function BindingEditor:armCapture(pc)
    local capture = self.capture
    if capture == nil or not self.o.alive(pc) then return false end
    for _, candidate in ipairs(capture.candidates or {}) do
        local down = self:inputActive(pc, candidate)
        candidate.down = down
        candidate.ready = not down
    end
    capture.armed = true
    self.o.setText(self.captureStatus, T("pressNewInput"))
    self:log("Binding capture armed: " .. tostring(capture.field))
    return true
end

function BindingEditor:startCapture(field, fromPicker)
    local info = FIELD_INFO[field]
    if info == nil then return false end
    local candidates = {}
    for _, name in ipairs(self:candidateNames(info.device, field)) do
        candidates[#candidates + 1] = self:makeCandidate(name)
    end
    self.capture = {
        field = field,
        device = info.device,
        candidates = candidates,
        armed = false,
        fromPicker = fromPicker == true,
    }
    self:setGroupVisible(self.keyboardPickerWidgets, false)
    self:setGroupVisible(self.controllerPickerWidgets, false)
    self:setGroupVisible(self.captureWidgets, true)
    self.o.setText(self.capturePrompt, info.action .. " - "
        .. (info.device == "controller" and T("controller") or T("keyboardMouse")))
    self.o.setText(self.captureStatus, T("preparingInput"))
    if not self:setCaptureInputMode(true, info.device) then
        self.capture = nil
        self:setGroupVisible(self.captureWidgets, false)
        if fromPicker then self:openPicker(field) end
        self:setStatus(T("autoDetectionUnavailable"))
        return false
    end
    self:log("Binding automatic detection started: " .. tostring(field)
        .. " (" .. tostring(info.device) .. ")")
    local pc = self.o.state and self.o.state.pc or nil
    self:armCapture(pc)
    return true
end

function BindingEditor:stopCapture(reason, returnToPicker)
    local previous = self.capture
    self.capture = nil
    self:setGroupVisible(self.captureWidgets, false)
    if previous ~= nil then
        self:setCaptureInputMode(false, previous.device)
        self:log("Binding automatic detection ended: " .. tostring(reason or "cancelled"))
        if returnToPicker == true and previous.fromPicker then self:openPicker(previous.field) end
    end
end

function BindingEditor:setStatus(message, conflictMessage)
    self.o.setText(self.statusText, tostring(message or ""))
    if self.statusConflictText ~= nil then
        local conflict = tostring(conflictMessage or "")
        if conflict ~= "" then
            self.o.setText(self.statusConflictText, "⚠ " .. conflict)
            setTextColorSafe(self.statusConflictText, WARNING_TEXT)
        else
            self.o.setText(self.statusConflictText, "")
        end
    end
end

function BindingEditor:validate(field, value)
    local info = FIELD_INFO[field]
    if info == nil then return false, T("unavailableUnknownControl") end
    local key = normalized(value)
    if key == "" then return false, T("bindingCannotBeEmpty") end
    if not self:isListedBindingKey(info.device, value) then
        local original = self.o.cfg(field, "")
        if self:isSupportedBindingKey(info.device, value)
            and normalized(value) == normalized(original) then
            return true
        end
        return false, T("bindingNotSelectable", { key = value })
    end
    local issue = self:pickerIssue(info.device, field, value)
    if issue.blocked then
        return false, issue.message or T("bindingUnavailable", { key = value })
    end
    return true
end

function BindingEditor:commit(field, value)
    local ok, message = self:validate(field, value)
    if not ok then
        self:setStatus(T("notSavedPrefix", { message = message }))
        if self.capture ~= nil then self.o.setText(self.captureStatus, tostring(message)) end
        return false
    end
    if type(self.draft) ~= "table" then self:snapshotDraft() end
    self.draft[field] = value
    self:updateTexts()
    local message = T("bindingChangedDraft", {
        action = FIELD_INFO[field].action, binding = value })
    local issue = self:pickerIssue(FIELD_INFO[field].device, field, value)
    local conflictMessage = nil
    if issue.warning and not issue.blocked then
        conflictMessage = tostring(issue.message or "")
    end
    self:setStatus(message, conflictMessage)
    return true
end

function BindingEditor:save()
    if type(self.draft) ~= "table" then return false end
    for field, _ in pairs(FIELD_INFO) do
        local ok, why = self:validate(field, self.draft[field])
        if not ok then
            self:setStatus(T("notSavedPrefix", { message = why }))
            return false
        end
    end
    local behavior = string.lower(tostring(self.draft.openWheelBehavior or "hold"))
    self.draft.openWheelBehavior = behavior == "toggle" and "toggle" or "hold"
    if type(self.o.applyDraft) ~= "function" then
        self:setStatus(T("notSavedPrefix", { message = "Controls apply function is unavailable." }))
        return false
    end
    local ok, why = self.o.applyDraft(self.draft)
    if ok ~= true then
        self:setStatus(T("notSavedPrefix", { message = why or "settings.lua could not be saved" }))
        return false
    end
    if type(self.o.onBindingChanged) == "function" then
        pcall(self.o.onBindingChanged, "settingsKey", self.draft.settingsKey)
    end
    self:snapshotDraft()
    self:updateTexts()
    self:setStatus(T("savedControls"))
    return true
end

function BindingEditor:inputActive(pc, candidate)
    if candidate == nil or candidate.key == nil then return false end
    if self.o.isKeyDown(pc, candidate.key) then return true end
    local ok, value = pcall(function() return pc:GetInputAnalogKeyState(candidate.key) end)
    return ok and math.abs(tonumber(value) or 0) >= 0.50
end

function BindingEditor:finishAutomaticSelection(field, device, name)
    local capture = self.capture
    local fromPicker = capture ~= nil and capture.fromPicker == true
    self:stopCapture("input detected", false)
    if fromPicker then
        self.pickerField = field
        self.pickerDevice = device
        self:setGroupVisible(self.keyboardPickerWidgets, device == "keyboard")
        self:setGroupVisible(self.controllerPickerWidgets, device == "controller")
        self:selectPending(name)
    end
end

function BindingEditor:tick(pc)
    local capture = self.capture
    if capture == nil or not self.o.alive(pc) then return false end
    if capture.device == "keyboard" then return true end
    if not capture.armed then
        self:armCapture(pc)
        return true
    end
    local pressed = nil
    for _, candidate in ipairs(capture.candidates or {}) do
        local down = self:inputActive(pc, candidate)
        if not down then candidate.ready = true end
        if candidate.ready and down and candidate.down ~= true and pressed == nil then
            pressed = candidate.name
            candidate.ready = false
        end
        candidate.down = down
    end
    if pressed ~= nil then
        local field = capture.field
        self:log("Binding automatic detection found: " .. tostring(pressed))
        self:finishAutomaticSelection(field, "controller", pressed)
    end
    return true
end

function BindingEditor:handleKeyboardEvent(name)
    local capture = self.capture
    if capture == nil or capture.device ~= "keyboard" then return false end
    if not self:choiceAllowed("keyboard", capture.field, name) then return false end
    local field = capture.field
    self:log("Binding automatic detection found: " .. tostring(name))
    self:finishAutomaticSelection(field, "keyboard", name)
    return true
end

function BindingEditor:handleClick(x, y, direction)
    if not self.open then return false end
    if self.confirmOpen then
        if direction < 0 or pointInRect(x, y, self.confirmCancelRect) then
            self:setConfirmVisible(false)
            return true
        end
        if pointInRect(x, y, self.confirmDiscardRect) then
            self:closePanel(true)
            return true
        end
        return true
    end

    if self.capture ~= nil then
        if direction < 0 or pointInRect(x, y, self.captureCancelRect) then
            self:stopCapture("cancelled by user", true)
        end
        return true
    end

    if self.pickerField ~= nil then
        local field, device = self.pickerField, self.pickerDevice
        if device == "keyboard" then
            if direction < 0 or pointInRect(x, y, self.keyboardPickerCancelRect) then
                self:closePicker()
                return true
            end
            if pointInRect(x, y, self.keyboardPickerConfirmRect) then
                local pending = self.pickerPendingValue
                if pending ~= nil and self:commit(field, pending) then self:closePicker()
                else self:refreshPickerVisuals() end
                return true
            end
            if pointInRect(x, y, self.keyboardAutoRect) then
                self:startCapture(field, true)
                return true
            end
            for name, rect in pairs(self.keyboardChoiceRects) do
                if pointInRect(x, y, rect) then
                    self:selectPending(name)
                    return true
                end
            end
        else
            if direction < 0 or pointInRect(x, y, self.controllerPickerCancelRect) then
                self:closePicker()
                return true
            end
            if pointInRect(x, y, self.controllerPickerConfirmRect) then
                local pending = self.pickerPendingValue
                if pending ~= nil and self:commit(field, pending) then self:closePicker()
                else self:refreshPickerVisuals() end
                return true
            end
            if pointInRect(x, y, self.controllerAutoRect) then
                self:startCapture(field, true)
                return true
            end
            for name, rect in pairs(self.controllerChoiceRects) do
                if pointInRect(x, y, rect) then
                    self:selectPending(name)
                    return true
                end
            end
        end
        return true
    end

    if pointInRect(x, y, self.instructionsRect) then
        if type(self.o.openInstructions) == "function" then self.o.openInstructions("controls") end
        return true
    end
    if direction < 0 or pointInRect(x, y, self.closeRect) then
        self:requestClose()
        return true
    end
    if pointInRect(x, y, self.saveRect) then
        self:save()
        return true
    end
    if pointInRect(x, y, self.resetRect) then
        if type(self.draft) ~= "table" then self:snapshotDraft() end
        self.draft.openKey = "CapsLock"
        self.draft.keyboardNextWheelButton = "MiddleMouseButton"
        self.draft.settingsKey = "F7"
        self.draft.controllerOpenButton = "Gamepad_LeftShoulder"
        self.draft.controllerNextWheelButton = "Gamepad_RightShoulder"
        self.draft.controllerPalWheelMenuButton = "Gamepad_RightThumbstick"
        self.draft.openWheelBehavior = "hold"
        self:updateTexts()
        self:setStatus(
            T("defaultControlsDraft"))
        return true
    end
    if pointInRect(x, y, self.openModeRect) then
        if type(self.draft) ~= "table" then self:snapshotDraft() end
        local previous = string.lower(tostring(self.draft.openWheelBehavior or "hold"))
        self.draft.openWheelBehavior = previous == "toggle" and "hold" or "toggle"
        self:updateTexts()
        self:setStatus(T("behaviorDraft", { behavior = T(self.draft.openWheelBehavior) }))
        return true
    end
    for field, rect in pairs(self.changeRects) do
        if pointInRect(x, y, rect) then
            self:openPicker(field)
            return true
        end
    end
    return true
end

return BindingEditor
