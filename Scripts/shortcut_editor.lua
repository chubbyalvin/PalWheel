local ShortcutEditor = {}
ShortcutEditor.__index = ShortcutEditor

local L = require("localization")
local TextLayout = require("text_layout")
local function T(key, variables) return L.get(key, variables) end

local PAGE_SIZE = 8

local okPalworldBindings, PalworldBindings = pcall(require, "palworld_bindings")
local okInjector, Injector = pcall(require, "palworld_keyinjector")

local CURRENT_BOUND = { R = 0.13, G = 0.55, B = 0.13, A = 1.0 }
local CONFLICT_SELECTED = { R = 1.00, G = 0.30, B = 0.14, A = 1.0 }
local WARNING_TEXT = { R = 1.00, G = 0.78, B = 0.16, A = 1.0 }

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

local DIGIT_FKEYS = {
    ["0"] = "Zero", ["1"] = "One", ["2"] = "Two", ["3"] = "Three", ["4"] = "Four",
    ["5"] = "Five", ["6"] = "Six", ["7"] = "Seven", ["8"] = "Eight", ["9"] = "Nine",
}
local NUMPAD_FKEYS = {
    NUMPAD_0 = "NumPadZero", NUMPAD_1 = "NumPadOne", NUMPAD_2 = "NumPadTwo",
    NUMPAD_3 = "NumPadThree", NUMPAD_4 = "NumPadFour", NUMPAD_5 = "NumPadFive",
    NUMPAD_6 = "NumPadSix", NUMPAD_7 = "NumPadSeven", NUMPAD_8 = "NumPadEight",
    NUMPAD_9 = "NumPadNine",
}
local NAMED_FKEYS = {
    GRAVE = "Tilde", MINUS = "Hyphen", EQUALS = "Equals",
    LEFT_BRACKET = "LeftBracket", RIGHT_BRACKET = "RightBracket", BACKSLASH = "Backslash",
    SEMICOLON = "Semicolon", APOSTROPHE = "Apostrophe", COMMA = "Comma",
    PERIOD = "Period", SLASH = "Slash", SPACE = "SpaceBar", TAB = "Tab",
    ENTER = "Enter", BACKSPACE = "BackSpace", ESCAPE = "Escape", CAPS_LOCK = "CapsLock",
    UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right", INSERT = "Insert",
    DELETE = "Delete", HOME = "Home", END = "End", PAGE_UP = "PageUp", PAGE_DOWN = "PageDown",
    NUMPAD_ADD = "Add", NUMPAD_SUBTRACT = "Subtract", NUMPAD_MULTIPLY = "Multiply",
    NUMPAD_DIVIDE = "Divide", NUMPAD_DECIMAL = "Decimal",
}
local MODIFIER_FKEYS = {
    ctrl = { "LeftControl", "RightControl" },
    shift = { "LeftShift", "RightShift" },
    alt = { "LeftAlt", "RightAlt" },
}

local function normalized(value)
    return string.lower(tostring(value or ""):gsub("[^%w]", ""))
end

local function characterLength(value)
    value = tostring(value or "")
    if utf8 ~= nil and type(utf8.len) == "function" then
        local ok, length = pcall(utf8.len, value)
        if ok and length ~= nil then return length end
    end
    return #value
end

local function withoutLastCharacter(value)
    value = tostring(value or "")
    if value == "" then return "" end
    if utf8 ~= nil and type(utf8.offset) == "function" then
        local ok, offset = pcall(utf8.offset, value, -1)
        if ok and offset ~= nil then return string.sub(value, 1, offset - 1) end
    end
    return string.sub(value, 1, math.max(0, #value - 1))
end

local function pointInRect(x, y, rect)
    return rect ~= nil and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

local function cloneRow(source)
    return {
        id = tostring(source.id or ""), label = tostring(source.label or ""),
        key = tostring(source.key or ""), ctrl = source.ctrl,
        shift = source.shift, alt = source.alt, active = source.active,
        sourceLine = source.sourceLine, originalId = source.originalId,
        rawColumnCount = source.rawColumnCount,
    }
end

local function cloneRows(values)
    local result = {}
    for index, row in ipairs(values or {}) do result[index] = cloneRow(row) end
    return result
end

local function rowsEqual(a, b)
    if #(a or {}) ~= #(b or {}) then return false end
    for index, left in ipairs(a or {}) do
        local right = (b or {})[index]
        if right == nil then return false end
        if tostring(left.id or "") ~= tostring(right.id or "")
            or tostring(left.label or "") ~= tostring(right.label or "")
            or tostring(left.key or "") ~= tostring(right.key or "")
            or (left.ctrl == true) ~= (right.ctrl == true)
            or (left.shift == true) ~= (right.shift == true)
            or (left.alt == true) ~= (right.alt == true)
            or (left.active == true) ~= (right.active == true) then
            return false
        end
    end
    return true
end

local function composeSpec(row)
    local parts = {}
    if row.ctrl == true then parts[#parts + 1] = "CTRL" end
    if row.shift == true then parts[#parts + 1] = "SHIFT" end
    if row.alt == true then parts[#parts + 1] = "ALT" end
    parts[#parts + 1] = tostring(row.key or "")
    return table.concat(parts, "+")
end

local function shortcutKeyDisplay(key)
    key = tostring(key or "")
    if key == "CAPS_LOCK" then return "Caps Lock" end
    if key == "PAGE_UP" then return "Page Up" end
    if key == "PAGE_DOWN" then return "Page Down" end
    if key == "LEFT_BRACKET" then return "[" end
    if key == "RIGHT_BRACKET" then return "]" end
    if key == "BACKSLASH" then return "\\" end
    if key == "SEMICOLON" then return ";" end
    if key == "APOSTROPHE" then return "'" end
    if key == "COMMA" then return "," end
    if key == "PERIOD" then return "." end
    if key == "SLASH" then return "/" end
    if key == "GRAVE" then return "`" end
    if key == "MINUS" then return "-" end
    if key == "EQUALS" then return "=" end
    if key:match("^NUMPAD_%d$") then return "Num " .. key:sub(-1) end
    if key == "NUMPAD_ADD" then return "Num +" end
    if key == "NUMPAD_SUBTRACT" then return "Num -" end
    if key == "NUMPAD_MULTIPLY" then return "Num *" end
    if key == "NUMPAD_DIVIDE" then return "Num /" end
    if key == "NUMPAD_DECIMAL" then return "Num ." end
    return key:gsub("_", " "):gsub("^%l", string.upper)
end

local function composeDisplay(key, modifier)
    local parts = {}
    if modifier == "ctrl" then parts[#parts + 1] = "Ctrl" end
    if modifier == "shift" then parts[#parts + 1] = "Shift" end
    if modifier == "alt" then parts[#parts + 1] = "Alt" end
    parts[#parts + 1] = shortcutKeyDisplay(key)
    return table.concat(parts, " + ")
end

local function rowSingleModifier(row)
    local count, modifier = 0, nil
    if row.ctrl == true then count, modifier = count + 1, "ctrl" end
    if row.shift == true then count, modifier = count + 1, "shift" end
    if row.alt == true then count, modifier = count + 1, "alt" end
    if count == 1 then return modifier end
    return nil
end

local function rowDisplay(row)
    local parts = {}
    if row.ctrl == true then parts[#parts + 1] = "Ctrl" end
    if row.shift == true then parts[#parts + 1] = "Shift" end
    if row.alt == true then parts[#parts + 1] = "Alt" end
    parts[#parts + 1] = shortcutKeyDisplay(row.key)
    return table.concat(parts, " + ")
end

local function shortcutToFKey(spec)
    spec = tostring(spec or "")
    if spec:match("^[A-Z]$") or spec:match("^F%d+$") then return spec end
    if DIGIT_FKEYS[spec] ~= nil then return DIGIT_FKEYS[spec] end
    if NUMPAD_FKEYS[spec] ~= nil then return NUMPAD_FKEYS[spec] end
    return NAMED_FKEYS[spec] or spec
end

local function addUnique(list, seen, value)
    value = tostring(value or "")
    if value == "" or seen[value] then return end
    seen[value] = true
    list[#list + 1] = value
end

function ShortcutEditor.new(options)
    local self = setmetatable({
        o = options or {}, built = false, open = false, page = 1,
        rows = {}, sourceText = nil, headerValid = true, selected = nil,
        pendingDelete = nil, pendingRestore = false, capture = nil, textEdit = nil,
        overlayWidgets = {}, rowWidgets = {}, rowRects = {},
        textWidgets = {}, captureWidgets = {}, confirmWidgets = {},
        textChoices = {}, textLetterChoices = {}, textUppercase = true,
        pickerChoiceRects = {}, pickerChoiceBorders = {}, pickerChoiceWidgets = {},
        modifierRects = {}, modifierBorders = {},
        baselineRows = {}, confirmOpen = false, saveBorder = nil,
        palworldBindings = nil, palworldBindingScanOk = false, palworldBindingScanError = nil,
    }, ShortcutEditor)
    if okPalworldBindings and type(PalworldBindings) == "table"
        and type(PalworldBindings.new) == "function" then
        self.palworldBindings = PalworldBindings.new({ log = self.o.log })
    end
    return self
end

function ShortcutEditor:track(group, widget)
    if widget ~= nil then group[#group + 1] = widget end
    return widget
end

function ShortcutEditor:cell(root, x, y, width, height, color, label, inset, fontSize, justification)
    local o = self.o
    local border = o.construct("/Script/UMG.Border", o.state.tree)
    local slot = border and o.addToCanvas(root, border) or nil
    if slot ~= nil then
        o.place(slot, x, y, width, height)
        o.setBorderColor(border, color)
        pcall(function() border:SetVisibility(o.hitTestInvisible) end)
    end
    local padding = inset or 10
    local size = tonumber(fontSize) or 13
    local centered = tonumber(justification) == 1
    local textX = centered and (x + width * 0.5) or (x + padding)
    local textY = y + height * 0.5
    
    
    
    
    local textHeight = math.max(18, height - 4)
    local textWidth = math.max(10, width - padding * 2)
    size = TextLayout.fitFontSize(label or "", size, textWidth, textHeight, 8)
    local text = o.createText(o.state.tree, root, label or "",
        textX, textY, textWidth,
        textHeight, size, justification or 0)
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

function ShortcutEditor:outline(root, x, y, width, height, group)
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

function ShortcutEditor:setGroupVisible(group, visible)
    for _, widget in ipairs(group or {}) do self.o.setVisible(widget, visible == true) end
end

function ShortcutEditor:setGroupZOrder(group, z)
    for _, widget in ipairs(group or {}) do
        pcall(function() if widget ~= nil and widget.Slot ~= nil then widget.Slot:SetZOrder(z) end end)
    end
end

function ShortcutEditor:build(root, summaryRoot)
    if self.built then return true end
    local o = self.o
    local summaryBorder, summaryText = self:cell(summaryRoot or root, 440, 902, 420, 34,
        o.colors.button, "", 10, 12, 1)
    self.summaryText = summaryText
    self.summaryRect = { x = 440, y = 902, w = 420, h = 34 }

    local panel = o.construct("/Script/UMG.Border", o.state.tree)
    local panelSlot = panel and o.addToCanvas(root, panel) or nil
    if panelSlot ~= nil then
        o.place(panelSlot, 250, 105, 1420, 820)
        o.setBorderColor(panel, o.colors.panel)
    end
    self:track(self.overlayWidgets, panel)
    self:outline(root, 250, 105, 1420, 820, self.overlayWidgets)
    self:track(self.overlayWidgets, o.createText(o.state.tree, root,
        T("customShortcuts"), 300, 130, 850, 40, 21, 0))
    local restoreBorder, restoreText = self:cell(root, 1140, 125, 230, 36,
        o.colors.button, T("restorePackaged"), 0, 12, 1)
    local instructionsBorder, instructionsText = self:cell(root, 1380, 125, 230, 36,
        o.colors.button, T("instructions"), 0, 12, 1)
    self.restoreRect = { x = 1140, y = 125, w = 230, h = 36 }
    self.instructionsRect = { x = 1380, y = 125, w = 230, h = 36 }
    for _, widget in ipairs({ restoreBorder, restoreText, instructionsBorder, instructionsText }) do
        self:track(self.overlayWidgets, widget)
    end
    self:track(self.overlayWidgets, o.createText(o.state.tree, root,
        T("shortcutsIntro"),
        300, 171, 1250, 28, 13, 0))
    self.menuKeyWarningText = self:track(self.overlayWidgets, o.createText(o.state.tree, root,
        T("shortcutsScanPending"),
        300, 198, 1310, 45, 10, 0))
    pcall(function() self.menuKeyWarningText:SetAutoWrapText(true) end)

    local headers = {
        { x = 300, w = 90, text = T("active") }, { x = 400, w = 300, text = T("label") },
        { x = 710, w = 270, text = T("id") }, { x = 990, w = 390, text = T("binding") },
        { x = 1390, w = 220, text = T("action") },
    }
    for _, header in ipairs(headers) do
        local border, text = self:cell(root, header.x, 245, header.w, 36,
            o.colors.button, header.text, 10, 12)
        self:track(self.overlayWidgets, border)
        self:track(self.overlayWidgets, text)
    end

    for row = 1, PAGE_SIZE do
        local y = 290 + (row - 1) * 52
        local widgets = {}
        local activeBorder, activeText = self:cell(root, 300, y, 90, 48,
            o.colors.row, "", 0, 12, 1)
        local labelBorder, labelText = self:cell(root, 400, y, 300, 48,
            o.colors.rowAlt, "", 10, 12)
        local idBorder, idText = self:cell(root, 710, y, 270, 48,
            o.colors.row, "", 10, 11)
        local bindBorder, bindText = self:cell(root, 990, y, 260, 48,
            o.colors.rowAlt, "", 10, 12)
        local changeBorder, changeText = self:cell(root, 1260, y, 120, 48,
            o.colors.button, T("change"), 0, 11, 1)
        local duplicateBorder, duplicateText = self:cell(root, 1390, y, 105, 48,
            o.colors.button, T("copy"), 31, 11)
        local deleteBorder, deleteText = self:cell(root, 1505, y, 105, 48,
            o.colors.row, T("delete"), 24, 11)
        for _, widget in ipairs({ activeBorder, activeText, labelBorder, labelText,
            idBorder, idText, bindBorder, bindText, changeBorder, changeText,
            duplicateBorder, duplicateText, deleteBorder, deleteText }) do
            widgets[#widgets + 1] = widget
            self:track(self.overlayWidgets, widget)
        end
        self.rowWidgets[row] = { all = widgets, activeBorder = activeBorder, activeText = activeText,
            labelText = labelText, idText = idText, bindText = bindText,
            changeText = changeText }
        self.rowRects[row] = {
            active = { x = 300, y = y, w = 90, h = 48 },
            label = { x = 400, y = y, w = 300, h = 48 },
            id = { x = 710, y = y, w = 270, h = 48 },
            binding = { x = 1260, y = y, w = 120, h = 48 },
            duplicate = { x = 1390, y = y, w = 105, h = 48 },
            delete = { x = 1505, y = y, w = 105, h = 48 },
        }
    end

    local prevBorder, prevText = self:cell(root, 300, 715, 130, 44,
        o.colors.button, T("previous"), 34, 12)
    local nextBorder, nextText = self:cell(root, 440, 715, 130, 44,
        o.colors.button, T("next"), 34, 12)
    self.pageText = o.createText(o.state.tree, root, "", 590, 724, 220, 28, 12, 0)
    local addBorder, addText = self:cell(root, 1190, 715, 220, 44,
        o.colors.button, T("addShortcut"), 0, 12, 1)
    local reloadBorder, reloadText = self:cell(root, 1420, 715, 190, 44,
        o.colors.row, T("reloadFile"), 45, 12)
    for _, widget in ipairs({ prevBorder, prevText, nextBorder, nextText,
        self.pageText, addBorder, addText, reloadBorder, reloadText }) do
        self:track(self.overlayWidgets, widget)
    end
    self.prevRect = { x = 300, y = 715, w = 130, h = 44 }
    self.nextRect = { x = 440, y = 715, w = 130, h = 44 }
    self.addRect = { x = 1190, y = 715, w = 220, h = 44 }
    self.reloadRect = { x = 1420, y = 715, w = 190, h = 44 }
    local saveBorder, saveText = self:cell(root, 1130, 825, 300, 50,
        o.colors.saveIdle or o.colors.row, T("saveAndApply"), 73, 14)
    self.saveBorder = saveBorder
    local closeBorder, closeText = self:cell(root, 1440, 825, 170, 50,
        o.colors.row, T("close"), 56, 14)
    self.saveRect = { x = 1130, y = 825, w = 300, h = 50 }
    self.closeRect = { x = 1440, y = 825, w = 170, h = 50 }
    self.statusText = o.createText(o.state.tree, root, "", 300, 790, 800, 82, 12, 0)
    self:track(self.overlayWidgets, saveBorder)
    self:track(self.overlayWidgets, saveText)
    self:track(self.overlayWidgets, closeBorder)
    self:track(self.overlayWidgets, closeText)
    self:track(self.overlayWidgets, self.statusText)

    self:buildTextPanel(root)
    self:buildCapturePanel(root)
    self:buildDiscardPanel(root)
    self:setGroupZOrder(self.overlayWidgets, 40)
    self:setGroupZOrder(self.textWidgets, 50)
    self:setGroupZOrder(self.captureWidgets, 50)
    self:setGroupZOrder(self.confirmWidgets, 60)
    self:setGroupVisible(self.overlayWidgets, false)
    self:setGroupVisible(self.textWidgets, false)
    self:setGroupVisible(self.captureWidgets, false)
    self:setGroupVisible(self.confirmWidgets, false)
    self.built = true
    self:updateSummary()
    o.setVisible(summaryBorder, true)
    o.setVisible(summaryText, true)
    return true
end

function ShortcutEditor:buildTextPanel(root)
    
    
    
    
    local o = self.o
    local panel = o.construct("/Script/UMG.Border", o.state.tree)
    local slot = panel and o.addToCanvas(root, panel) or nil
    if slot ~= nil then
        o.place(slot, 300, 135, 1320, 650)
        
        
        o.setBorderColor(panel, o.colors.panel)
    end
    self:track(self.textWidgets, panel)
    self:outline(root, 300, 135, 1320, 650, self.textWidgets)
    self.textTitle = self:track(self.textWidgets,
        o.createText(o.state.tree, root, T("editText"), 350, 158, 1220, 36, 19, 0))
    local valueBorder, valueText = self:cell(root, 350, 207, 1220, 62,
        o.colors.rowAlt, "", 18, 19, 0)
    self.textValue = valueText
    self:track(self.textWidgets, valueBorder)
    self:track(self.textWidgets, valueText)
    self.textGuide = self:track(self.textWidgets,
        o.createText(o.state.tree, root,
            T("virtualKeyboardHelp"),
            350, 282, 1220, 45, 12, 0))
    pcall(function() self.textGuide:SetAutoWrapText(true) end)

    local keyH = 42
    local function addChoice(x, y, width, label, value, idAllowed, isLetter, fontSize)
        local border, text = self:cell(root, x, y, width, keyH,
            o.colors.rowAlt, label, 6, fontSize or 12, 1)
        local choice = {
            rect = { x = x, y = y, w = width, h = keyH },
            border = border, text = text, value = value,
            idAllowed = idAllowed == true, isLetter = isLetter == true,
        }
        self.textChoices[#self.textChoices + 1] = choice
        if choice.isLetter then self.textLetterChoices[#self.textLetterChoices + 1] = choice end
        self:track(self.textWidgets, border)
        self:track(self.textWidgets, text)
    end

    
    
    local keyW, gap = 66, 6
    local numberX = 400
    local symbolY, numberY = 334, 382
    local numberValues = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" }
    local symbolValues = { "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+" }
    for index, value in ipairs(symbolValues) do
        addChoice(numberX + (index - 1) * (keyW + gap), symbolY,
            keyW, value, value, value == "_", false)
    end
    for index, value in ipairs(numberValues) do
        addChoice(numberX + (index - 1) * (keyW + gap), numberY,
            keyW, value, value, value:match("^%d$") ~= nil or value == "-", false)
    end

    
    local backX = numberX + #numberValues * (keyW + gap)
    local backBorder, backText = self:cell(root, backX, numberY, 150, keyH,
        o.colors.button, T("backspace"), 20, 10, 1)
    self.textBackspaceRect = { x = backX, y = numberY, w = 150, h = keyH }
    self:track(self.textWidgets, backBorder)
    self:track(self.textWidgets, backText)

    
    local qY, qX = 430, 430
    local qRow = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" }
    for index, letter in ipairs(qRow) do
        addChoice(qX + (index - 1) * (keyW + gap), qY,
            keyW, letter, letter, true, true)
    end
    local qTailX = qX + #qRow * (keyW + gap)
    addChoice(qTailX, qY, keyW, "[", "[", false, false)
    addChoice(qTailX + keyW + gap, qY, keyW, "]", "]", false, false)
    addChoice(qTailX + 2 * (keyW + gap), qY, keyW, "\\", "\\", false, false)

    
    local aY = 478
    local caseBorder, caseText = self:cell(root, 350, aY, 120, keyH,
        o.colors.button, T("caseUpper"), 12, 10, 1)
    self.textCaseBorder, self.textCaseText = caseBorder, caseText
    self.textCaseRect = { x = 350, y = aY, w = 120, h = keyH }
    self:track(self.textWidgets, caseBorder)
    self:track(self.textWidgets, caseText)

    local aX = 476
    local aRow = { "A", "S", "D", "F", "G", "H", "J", "K", "L" }
    for index, letter in ipairs(aRow) do
        addChoice(aX + (index - 1) * (keyW + gap), aY,
            keyW, letter, letter, true, true)
    end
    local aTailX = aX + #aRow * (keyW + gap)
    addChoice(aTailX, aY, keyW, ";", ";", false, false)
    addChoice(aTailX + keyW + gap, aY, keyW, ":", ":", false, false)
    addChoice(aTailX + 2 * (keyW + gap), aY, keyW, "'", "'", false, false)

    local zY, zX = 526, 430
    local zRow = { "Z", "X", "C", "V", "B", "N", "M" }
    for index, letter in ipairs(zRow) do
        addChoice(zX + (index - 1) * (keyW + gap), zY,
            keyW, letter, letter, true, true)
    end
    local zTailX = zX + #zRow * (keyW + gap)
    addChoice(zTailX, zY, keyW, ",", ",", false, false)
    addChoice(zTailX + keyW + gap, zY, keyW, ".", ".", false, false)
    addChoice(zTailX + 2 * (keyW + gap), zY, keyW, "/", "/", false, false)
    addChoice(zTailX + 3 * (keyW + gap), zY, keyW, "?", "?", false, false)

    
    local clearBorder, clearText = self:cell(root, 420, 584, 140, 46,
        o.colors.row, T("clear"), 0, 11, 1)
    addChoice(580, 584, 520, T("space"), " ", false, false, 11)
    local restoreBorder, restoreText = self:cell(root, 1120, 584, 160, 46,
        o.colors.row, T("restore"), 0, 11, 1)
    self.textClearRect = { x = 420, y = 584, w = 140, h = 46 }
    self.textRestoreRect = { x = 1120, y = 584, w = 160, h = 46 }
    for _, widget in ipairs({ clearBorder, clearText, restoreBorder, restoreText }) do
        self:track(self.textWidgets, widget)
    end

    
    
    
    local applyBorder, applyText = self:cell(root, 1060, 680, 230, 52,
        o.colors.button, T("applyToDraft"), 0, 13, 1)
    local cancelBorder, cancelText = self:cell(root, 1310, 680, 230, 52,
        o.colors.row, T("cancel"), 0, 13, 1)
    self.textApplyRect = { x = 1060, y = 680, w = 230, h = 52 }
    self.textCancelRect = { x = 1310, y = 680, w = 230, h = 52 }
    for _, widget in ipairs({ applyBorder, applyText, cancelBorder, cancelText }) do
        self:track(self.textWidgets, widget)
    end
end
function ShortcutEditor:buildCapturePanel(root)
    local o = self.o
    local panel = o.construct("/Script/UMG.Border", o.state.tree)
    local slot = panel and o.addToCanvas(root, panel) or nil
    if slot ~= nil then
        o.place(slot, 360, 230, 1200, 570)
        o.setBorderColor(panel, o.colors.panel)
    end
    self:track(self.captureWidgets, panel)
    self:outline(root, 360, 230, 1200, 570, self.captureWidgets)
    self.captureTitle = self:track(self.captureWidgets,
        o.createText(o.state.tree, root, T("changeShortcutBinding"), 400, 250, 1120, 30, 19, 0))
    self.captureCurrent = self:track(self.captureWidgets,
        o.createText(o.state.tree, root, "", 400, 280, 1120, 24, 12, 0))

    
    
    
    local keyH, gap = 28, 4
    local baseX = 400

    local function addKey(spec, label, x, y, width, font)
        local border, text = self:cell(root, x, y, width, keyH,
            o.colors.rowAlt, label or shortcutKeyDisplay(spec), 0, font or 8, 1)
        self.pickerChoiceRects[spec] = { x = x, y = y, w = width, h = keyH }
        self.pickerChoiceBorders[spec] = border
        self.pickerChoiceWidgets[spec] = { border, text }
        self:track(self.captureWidgets, border)
        self:track(self.captureWidgets, text)
    end

    local function addModifier(id, label, x, y, width)
        local border, text = self:cell(root, x, y, width, keyH,
            o.colors.row, label, 0, 8, 1)
        self.modifierRects[id] = { x = x, y = y, w = width, h = keyH }
        self.modifierBorders[id] = border
        self:track(self.captureWidgets, border)
        self:track(self.captureWidgets, text)
    end

    
    local y = 310
    addKey("ESCAPE", "ESC", baseX, y, 50, 8)
    local x = baseX + 64
    for i = 1, 12 do
        addKey("F" .. i, "F" .. i, x, y, 44, 8)
        x = x + 48
        if i == 4 or i == 8 then x = x + 10 end
    end

    
    y = 342
    x = baseX + 64
    for i = 13, 24 do
        addKey("F" .. i, "F" .. i, x, y, 44, 8)
        x = x + 48
        if i == 16 or i == 20 then x = x + 10 end
    end

    local unit = 48
    y = 378
    x = baseX
    local numberRow = {
        {"GRAVE", "`"}, {"1", "1"}, {"2", "2"}, {"3", "3"}, {"4", "4"},
        {"5", "5"}, {"6", "6"}, {"7", "7"}, {"8", "8"}, {"9", "9"},
        {"0", "0"}, {"MINUS", "-"}, {"EQUALS", "="},
    }
    for _, entry in ipairs(numberRow) do
        addKey(entry[1], entry[2], x, y, unit, 9); x = x + unit + gap
    end
    addKey("BACKSPACE", "BACKSPACE", x, y, 104, 8)

    y = 410
    x = baseX
    addKey("TAB", "TAB", x, y, 72, 8); x = x + 72 + gap
    for _, letter in ipairs({"Q","W","E","R","T","Y","U","I","O","P"}) do
        addKey(letter, letter, x, y, unit, 9); x = x + unit + gap
    end
    for _, entry in ipairs({{"LEFT_BRACKET","["},{"RIGHT_BRACKET","]"},{"BACKSLASH","\\"}}) do
        addKey(entry[1], entry[2], x, y, unit, 9); x = x + unit + gap
    end

    y = 442
    x = baseX
    addKey("CAPS_LOCK", "CAPS", x, y, 86, 8); x = x + 86 + gap
    for _, letter in ipairs({"A","S","D","F","G","H","J","K","L"}) do
        addKey(letter, letter, x, y, unit, 9); x = x + unit + gap
    end
    addKey("SEMICOLON", ";", x, y, unit, 9); x = x + unit + gap
    addKey("APOSTROPHE", "'", x, y, unit, 9); x = x + unit + gap
    addKey("ENTER", "ENTER", x, y, 96, 8)

    y = 474
    x = baseX
    addModifier("shift", "SHIFT", x, y, 104); x = x + 104 + gap
    for _, letter in ipairs({"Z","X","C","V","B","N","M"}) do
        addKey(letter, letter, x, y, unit, 9); x = x + unit + gap
    end
    for _, entry in ipairs({{"COMMA",","},{"PERIOD","."},{"SLASH","/"}}) do
        addKey(entry[1], entry[2], x, y, unit, 9); x = x + unit + gap
    end

    y = 506
    x = baseX
    addModifier("ctrl", "CTRL", x, y, 82); x = x + 82 + gap
    addModifier("alt", "ALT", x, y, 72); x = x + 72 + gap
    addKey("SPACE", "SPACE", x, y, 350, 8)

    
    local sideX, navW = 1200, 78
    y = 378
    for row, entries in ipairs({
        {{"INSERT","INS"},{"HOME","HOME"},{"PAGE_UP","PG UP"}},
        {{"DELETE","DEL"},{"END","END"},{"PAGE_DOWN","PG DN"}},
    }) do
        x = sideX
        for _, entry in ipairs(entries) do
            addKey(entry[1], entry[2], x, y + (row - 1) * 32, navW, 7)
            x = x + navW + gap
        end
    end
    addKey("UP", "UP", sideX + navW + gap, 446, navW, 8)
    addKey("LEFT", "LEFT", sideX, 478, navW, 7)
    addKey("DOWN", "DOWN", sideX + navW + gap, 478, navW, 7)
    addKey("RIGHT", "RIGHT", sideX + 2 * (navW + gap), 478, navW, 7)

    local numX, numW = 1200, 56
    local numRows = {
        {{"NUMPAD_7","7"},{"NUMPAD_8","8"},{"NUMPAD_9","9"},{"NUMPAD_DIVIDE","/"}},
        {{"NUMPAD_4","4"},{"NUMPAD_5","5"},{"NUMPAD_6","6"},{"NUMPAD_MULTIPLY","*"}},
        {{"NUMPAD_1","1"},{"NUMPAD_2","2"},{"NUMPAD_3","3"},{"NUMPAD_SUBTRACT","-"}},
        {{"NUMPAD_0","0"},{"NUMPAD_DECIMAL","."},{"NUMPAD_ADD","+"}},
    }
    local numY = 518
    for r, entries in ipairs(numRows) do
        x = numX
        for _, entry in ipairs(entries) do
            addKey(entry[1], entry[2], x, numY + (r - 1) * 32, numW, 8)
            x = x + numW + gap
        end
    end

    local modifierHelp = self:track(self.captureWidgets,
        o.createText(o.state.tree, root,
            T("modifierHelp"),
            400, 552, 720, 24, 9, 0))

    self.captureStatus = self:track(self.captureWidgets,
        o.createText(o.state.tree, root,
            T("selectKeyInfo"), 400, 588, 720, 125, 11, 0))
    pcall(function() self.captureStatus:SetAutoWrapText(true) end)

    local confirmBorder, confirmText = self:cell(root, 590, 730, 245, 44,
        o.colors.row, T("confirm"), 0, 12, 1)
    local cancelBorder, cancelText = self:cell(root, 1085, 730, 245, 44,
        o.colors.row, T("cancel"), 0, 12, 1)
    self.captureConfirmRect = { x = 590, y = 730, w = 245, h = 44 }
    self.captureCancelRect = { x = 1085, y = 730, w = 245, h = 44 }
    for _, widget in ipairs({ confirmBorder, confirmText, cancelBorder, cancelText }) do
        self:track(self.captureWidgets, widget)
    end
end

function ShortcutEditor:buildDiscardPanel(root)
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
        T("discardShortcutsTitle"), 605, 385, 710, 38, 18, 0))
    self:track(self.confirmWidgets, o.createText(o.state.tree, root,
        T("discardShortcutsBody"),
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

function ShortcutEditor:hasUnsavedChanges()
    return not rowsEqual(self.rows, self.baselineRows)
end

function ShortcutEditor:updateSaveVisual()
    if self.saveBorder ~= nil then
        self.o.setBorderColor(self.saveBorder,
            self:hasUnsavedChanges() and (self.o.colors.saveDirty or self.o.colors.button)
                or (self.o.colors.saveIdle or self.o.colors.row))
    end
end

function ShortcutEditor:setConfirmVisible(visible)
    self.confirmOpen = visible == true
    self:setGroupVisible(self.confirmWidgets, self.confirmOpen)
end

function ShortcutEditor:requestClose()
    if self:hasUnsavedChanges() then
        self:setConfirmVisible(true)
        return false
    end
    self:closePanel(true)
    return true
end

function ShortcutEditor:discardAndClose()
    self.rows = cloneRows(self.baselineRows)
    self.page, self.selected = 1, nil
    self.pendingDelete, self.pendingRestore = nil, false
    self:updateList()
    self:closePanel(true)
    return true
end

function ShortcutEditor:pageCount()
    return math.max(1, math.ceil(#self.rows / PAGE_SIZE))
end

function ShortcutEditor:updateSummary()
    if not self.built then return end
    local active, defined = 0, #self.rows
    if defined == 0 and type(self.o.currentCounts) == "function" then
        active, defined = self.o.currentCounts()
    else
        for _, row in ipairs(self.rows or {}) do
            if row.active == true then active = active + 1 end
        end
    end
    local fileStatus = type(self.o.fileInvalid) == "function" and self.o.fileInvalid()
        and T("fileErrorSuffix") or ""
    self.o.setText(self.summaryText, T("shortcutSummary", {
        active = active, defined = defined, fileError = fileStatus }))
end

function ShortcutEditor:updateList()
    if not self.built then return end
    local pageCount = self:pageCount()
    if self.page > pageCount then self.page = pageCount end
    if self.page < 1 then self.page = 1 end
    local first = (self.page - 1) * PAGE_SIZE + 1
    for displayRow = 1, PAGE_SIZE do
        local index = first + displayRow - 1
        local row = self.rows[index]
        local widgets = self.rowWidgets[displayRow]
        local visible = row ~= nil
        for _, widget in ipairs(widgets.all) do self.o.setVisible(widget, visible) end
        if visible then
            local selected = self.selected == index and "> " or ""
            self.o.setText(widgets.activeText, T(row.active == true and "on" or "off"))
            if widgets.activeBorder ~= nil then
                self.o.setBorderColor(widgets.activeBorder,
                    row.active == true and (self.o.colors.saveDirty or CURRENT_BOUND)
                        or self.o.colors.row)
            end
            self.o.setText(widgets.labelText, selected .. tostring(row.label or ""))
            self.o.setText(widgets.idText, tostring(row.id or ""))
            self.o.setText(widgets.bindText, rowDisplay(row))
        end
    end
    self.o.setText(self.pageText, T("page", { page = self.page, pages = pageCount }))
    self:updateSummary()
    self:updateSaveVisual()
end

function ShortcutEditor:validation()
    if type(self.o.validateRows) ~= "function" then return true, {}, {} end
    local data, errors, warnings = self.o.validateRows(self.rows)
    return data ~= nil, errors or {}, warnings or {}
end

function ShortcutEditor:setValidationStatus(prefix)
    local valid, errors, warnings = self:validation()
    if not valid then
        local first = errors[1] or {}
        self.o.setText(self.statusText, T("validationLine", {
            prefix = prefix or T("statusNotSavable"), line = first.line or "?",
            message = first.message or T("validationFailed") }))
    elseif #warnings > 0 then
        self.o.setText(self.statusText, T("validationMessage", {
            prefix = prefix or T("statusReady"), message = warnings[1] }))
    else
        self.o.setText(self.statusText, T("allRowsValid", {
            prefix = prefix or T("statusReady") }))
    end
    return valid
end

function ShortcutEditor:reload()
    local draft, why = self.o.readDraft()
    if draft == nil then
        self.o.setText(self.statusText, T("cannotReadShortcuts", { reason = why }))
        return false
    end
    self.rows = cloneRows(draft.rows)
    self.baselineRows = cloneRows(draft.rows)
    self.sourceText = draft.sourceText
    self.headerValid = draft.headerValid == true
    self.page, self.selected = 1, nil
    self.pendingDelete, self.pendingRestore = nil, false
    self:updateList()
    if not self.headerValid then
        self.o.setText(self.statusText,
            T("invalidTsvHeader"))
    else
        self:setValidationStatus(T("statusLoaded"))
    end
    return true
end

function ShortcutEditor:isSummaryHit(x, y)
    return self.built and not self.open and pointInRect(x, y, self.summaryRect)
end

function ShortcutEditor:isOpen() return self.open == true end
function ShortcutEditor:isCapturing() return self.capture ~= nil or self.textEdit ~= nil end

function ShortcutEditor:handleReservedSettingsKey()
    if not self:isCapturing() then return false end
    local message = T("editorMenuKeyReserved")
    if self.capture ~= nil then self.o.setText(self.captureStatus, message)
    else self.o.setText(self.textGuide, message) end
    return true
end

function ShortcutEditor:openPanel()
    if not self.built then return false end
    self.open = true
    self:setConfirmVisible(false)
    self:setGroupVisible(self.overlayWidgets, true)
    self:setGroupVisible(self.textWidgets, false)
    self:setGroupVisible(self.captureWidgets, false)
    self:refreshPalworldBindings()
    self:updateMenuKeyWarning()
    return self:reload()
end

function ShortcutEditor:stopInput(reason)
    self.capture, self.textEdit = nil, nil
    self:setGroupVisible(self.textWidgets, false)
    self:setGroupVisible(self.captureWidgets, false)
    if reason ~= nil then self.o.log("Shortcut editor input ended: " .. tostring(reason), true) end
end

function ShortcutEditor:closePanel(force)
    if force ~= true and self.open and self:hasUnsavedChanges() then
        self:setConfirmVisible(true)
        return false
    end
    self:stopInput(nil)
    self.open = false
    self:setConfirmVisible(false)
    self:setGroupVisible(self.overlayWidgets, false)
    return true
end

function ShortcutEditor:refreshPalworldBindings()
    self.palworldBindingScanOk = false
    self.palworldBindingScanError = nil
    if self.palworldBindings == nil or type(self.palworldBindings.scan) ~= "function" then
        self.palworldBindingScanError = "Palworld binding reader is unavailable"
        return false
    end
    local ok, result, why = pcall(function()
        local scanned, scanWhy = self.palworldBindings:scan()
        return scanned, scanWhy
    end)
    if ok and result == true then
        self.palworldBindingScanOk = true
        return true
    end
    self.palworldBindingScanError = tostring(why or result or "Palworld binding scan failed")
    if type(self.o.log) == "function" then
        self.o.log("Shortcut picker live Palworld binding scan unavailable: "
            .. self.palworldBindingScanError, true)
    end
    return false
end

function ShortcutEditor:updateMenuKeyWarning()
    if self.menuKeyWarningText == nil then return end
    local message = T("shortcutLeakWarning")
    self.o.setText(self.menuKeyWarningText, message)
    setTextColorSafe(self.menuKeyWarningText, WARNING_TEXT)
end

function ShortcutEditor:palworldLabelsForSpec(spec)
    if not self.palworldBindingScanOk or self.palworldBindings == nil
        or type(self.palworldBindings.labels) ~= "function" then return {} end
    return self.palworldBindings:labels("keyboard", shortcutToFKey(spec)) or {}
end

function ShortcutEditor:isMovementSpec(spec)
    if not self.palworldBindingScanOk or self.palworldBindings == nil
        or type(self.palworldBindings.isMovement) ~= "function" then return false end
    return self.palworldBindings:isMovement("keyboard", shortcutToFKey(spec)) == true
end

function ShortcutEditor:modifierPalworldLabels(modifier)
    local result, seen = {}, {}
    if modifier == nil or not self.palworldBindingScanOk or self.palworldBindings == nil
        or type(self.palworldBindings.labels) ~= "function" then return result end
    for _, fkey in ipairs(MODIFIER_FKEYS[modifier] or {}) do
        for _, label in ipairs(self.palworldBindings:labels("keyboard", fkey) or {}) do
            addUnique(result, seen, label)
        end
    end
    return result
end

function ShortcutEditor:controlConflict(spec)
    local fkey = normalized(shortcutToFKey(spec))
    local controls = {
        { value = self.o.cfg("openKey", "CapsLock"), label = T("openWheel") },
        { value = self.o.cfg("keyboardNextWheelButton", "MiddleMouseButton"), label = T("nextWheel") },
        { value = self.o.cfg("settingsKey", "F7"), label = T("palwheelMenu") },
    }
    for _, control in ipairs(controls) do
        if normalized(control.value) == fkey then return control.label end
    end
    return nil
end

function ShortcutEditor:pickerIssue(spec, modifier)
    spec = tostring(spec or "")
    local display = composeDisplay(spec, modifier)

    if okInjector and type(Injector) == "table" and type(Injector.parse) == "function" then
        local request, parseError = Injector.parse((modifier == "ctrl" and "CTRL+"
            or modifier == "shift" and "SHIFT+" or modifier == "alt" and "ALT+" or "") .. spec)
        if request == nil then
            return { blocked = true, warning = true,
                message = T("shortcutUnsupported", {
                    reason = parseError or T("shortcutUnsupportedGeneric") }) }
        end
    end

    local labels = self:palworldLabelsForSpec(spec)
    if modifier == nil then
        local control = self:controlConflict(spec)
        if control ~= nil then
            return { blocked = true, warning = true,
                message = T("shortcutControlConflict", {
                    key = shortcutKeyDisplay(spec), control = control }) }
        end
        if self:isMovementSpec(spec) then
            local detail = #labels > 0 and table.concat(labels, ", ") or T("movementAction")
            return { blocked = true, warning = true,
                message = T("shortcutMovementConflict", {
                    key = shortcutKeyDisplay(spec), action = detail }) }
        end
        if #labels > 0 then
            return { blocked = false, warning = true,
                message = T("shortcutPalworldConflict", {
                    key = shortcutKeyDisplay(spec), actions = table.concat(labels, ", ") }) }
        end
        if not self.palworldBindingScanOk then
            return { blocked = false, warning = false,
                message = T("shortcutNoConflictLimited") }
        end
        return { blocked = false, warning = false,
            message = T("shortcutAvailable", { key = shortcutKeyDisplay(spec) }) }
    end

    local notes = {}
    if #labels > 0 then
        notes[#notes + 1] = T("shortcutAlsoUsed", {
            key = shortcutKeyDisplay(spec), actions = table.concat(labels, ", ") })
    end
    local modifierLabels = self:modifierPalworldLabels(modifier)
    if #modifierLabels > 0 then
        notes[#notes + 1] = T("modifierAlsoUsed", {
            modifier = modifier == "ctrl" and "Ctrl" or modifier == "shift" and "Shift" or "Alt",
            actions = table.concat(modifierLabels, ", ") })
    end
    local message = T("modifierShortcutAvailable", { binding = display })
    if #notes > 0 then
        message = message .. T("conflictNote", { notes = table.concat(notes, "; ") })
    end
    return { blocked = false, warning = false, message = message }
end

function ShortcutEditor:pickerColor(spec)
    local capture = self.capture
    if capture == nil then return self.o.colors.rowAlt end
    local key = normalized(spec)
    local current = normalized(capture.currentKey)
    local pending = normalized(capture.pendingKey)
    local issue = self:pickerIssue(spec, capture.pendingModifier)
    if key == current then return CURRENT_BOUND end
    if issue.warning or issue.blocked then
        return key == pending and CONFLICT_SELECTED or self.o.colors.unavailable
    end
    return key == pending and (self.o.colors.weapon or self.o.colors.selected) or self.o.colors.rowAlt
end

function ShortcutEditor:modifierColor(modifier)
    local capture = self.capture
    if capture == nil then return self.o.colors.row end
    if capture.currentModifier == modifier then return CURRENT_BOUND end
    if capture.pendingModifier == modifier then
        return self.o.colors.weapon or self.o.colors.selected
    end
    return self.o.colors.row
end

function ShortcutEditor:refreshPickerVisuals()
    local capture = self.capture
    local row = capture and self.rows[capture.index] or nil
    if capture == nil or row == nil then return end
    local selectedDisplay = composeDisplay(capture.pendingKey, capture.pendingModifier)
    self.o.setText(self.captureCurrent, T("currentSelected", {
        current = rowDisplay(row), selected = selectedDisplay }))
    local issue = self:pickerIssue(capture.pendingKey, capture.pendingModifier)
    local warning = issue.warning == true or issue.blocked == true
    local message = tostring(issue.message or "")
    if warning then message = "⚠ " .. message end
    self.o.setText(self.captureStatus, message)
    setTextColorSafe(self.captureStatus, warning and WARNING_TEXT
        or (self.o.colors.text or { R = 1, G = 1, B = 1, A = 1 }))
    for spec, border in pairs(self.pickerChoiceBorders) do
        self.o.setBorderColor(border, self:pickerColor(spec))
    end
    for modifier, border in pairs(self.modifierBorders) do
        self.o.setBorderColor(border, self:modifierColor(modifier))
    end
end

function ShortcutEditor:selectPendingKey(spec)
    if self.capture == nil then return false end
    self.capture.pendingKey = tostring(spec or "")
    self:refreshPickerVisuals()
    return true
end

function ShortcutEditor:togglePendingModifier(modifier)
    if self.capture == nil then return false end
    if self.capture.pendingModifier == modifier then self.capture.pendingModifier = nil
    else self.capture.pendingModifier = modifier end
    self:refreshPickerVisuals()
    return true
end

function ShortcutEditor:startText(index, field)
    local row = self.rows[index]
    if row == nil then return false end
    self.selected, self.pendingDelete = index, nil
    self.textEdit = { index = index, field = field,
        buffer = tostring(row[field] or ""), original = tostring(row[field] or ""),
        replacePending = true }
    self.textUppercase = true
    self:setGroupVisible(self.textWidgets, true)
    self:setGroupVisible(self.captureWidgets, false)
    self.o.setText(self.textTitle, T(field == "label" and "editLabelTitle" or "editIdTitle"))
    self:refreshTextPickerVisuals()
    self:updateTextPanel()
    return true
end

function ShortcutEditor:refreshTextPickerVisuals()
    local edit = self.textEdit
    if edit == nil then return end
    local idMode = edit.field == "id"
    for _, choice in ipairs(self.textChoices) do
        local allowed = not idMode or choice.idAllowed
        
        
        
        self.o.setVisible(choice.border, allowed)
        self.o.setVisible(choice.text, allowed)
        if allowed then self.o.setBorderColor(choice.border, self.o.colors.rowAlt) end
        if choice.isLetter then
            local display = idMode and string.lower(choice.value)
                or (self.textUppercase and choice.value or string.lower(choice.value))
            self.o.setText(choice.text, display)
        end
    end
    self.o.setVisible(self.textCaseBorder, not idMode)
    self.o.setVisible(self.textCaseText, not idMode)
    if not idMode then
        self.o.setText(self.textCaseText, T(self.textUppercase and "caseUpper" or "caseLower"))
        self.o.setBorderColor(self.textCaseBorder, self.o.colors.button)
    end
end

function ShortcutEditor:updateTextPanel(message)
    local edit = self.textEdit
    if edit == nil then return end
    local limit = edit.field == "label" and 20 or 40
    local prefix = edit.replacePending and T("selectedPrefix") or ""
    self.o.setText(self.textValue, prefix .. edit.buffer .. "    ["
        .. tostring(characterLength(edit.buffer))
        .. "/" .. tostring(limit) .. "]")
    self.o.setText(self.textGuide, message or
        (edit.replacePending
            and T("currentValueSelected") or T("appendCharacters")))
end

function ShortcutEditor:insertTextChoice(choice)
    local edit = self.textEdit
    if edit == nil or choice == nil then return false end
    if edit.field == "id" and choice.idAllowed ~= true then
        self:updateTextPanel(T("idCharacterBlocked"))
        return false
    end
    local value = tostring(choice.value or "")
    if choice.isLetter then
        value = edit.field == "id" and string.lower(value)
            or (self.textUppercase and string.upper(value) or string.lower(value))
    end
    local limit = edit.field == "label" and 20 or 40
    local currentLength = edit.replacePending and 0 or characterLength(edit.buffer)
    if currentLength + characterLength(value) > limit then
        self:updateTextPanel(T("characterLimit"))
        return false
    end
    if edit.replacePending then edit.buffer, edit.replacePending = "", false end
    edit.buffer = edit.buffer .. value
    self:updateTextPanel()
    return true
end

function ShortcutEditor:backspaceText()
    local edit = self.textEdit
    if edit == nil then return false end
    if edit.replacePending then edit.buffer, edit.replacePending = "", false
    else edit.buffer = withoutLastCharacter(edit.buffer) end
    self:updateTextPanel()
    return true
end

function ShortcutEditor:clearText()
    if self.textEdit == nil then return false end
    self.textEdit.buffer, self.textEdit.replacePending = "", false
    self:updateTextPanel()
    return true
end

function ShortcutEditor:restoreText()
    if self.textEdit == nil then return false end
    self.textEdit.buffer = self.textEdit.original
    self.textEdit.replacePending = true
    self:updateTextPanel(T("originalRestored"))
    return true
end

function ShortcutEditor:toggleTextCase()
    if self.textEdit == nil then return false end
    if self.textEdit.field == "id" then
        self:updateTextPanel(T("idsLowercase"))
        return false
    end
    self.textUppercase = not self.textUppercase
    self:refreshTextPickerVisuals()
    self:updateTextPanel()
    return true
end

function ShortcutEditor:idExists(value, exceptIndex)
    value = string.lower(tostring(value or ""))
    for index, row in ipairs(self.rows) do
        if index ~= exceptIndex and string.lower(tostring(row.id or "")) == value then
            return true
        end
    end
    return false
end

function ShortcutEditor:commitText()
    local edit = self.textEdit
    if edit == nil then return false end
    if string.match(edit.buffer, "^%s*$") then
        local original = edit.original
        self:stopInput("blank text replacement discarded")
        self:updateList()
        self.o.setText(self.statusText,
            T("unchangedEmpty", { value = original }))
        return false
    end
    if edit.field == "id" and self:idExists(edit.buffer, edit.index) then
        self:updateTextPanel(T("duplicateId"))
        return false
    end
    local row = self.rows[edit.index]
    local previous = row[edit.field]
    row[edit.field] = edit.field == "id" and string.lower(edit.buffer) or edit.buffer
    row.rawColumnCount = 7
    local valid, errors = self:validation()
    if not valid then
        for _, entry in ipairs(errors) do
            if entry.row == edit.index then
                row[edit.field] = previous
                self:updateTextPanel(tostring(entry.message))
                return false
            end
        end
    end
    self:stopInput("text applied to draft")
    self:updateList()
    self:setValidationStatus(T("statusUnsaved"))
    return true
end

function ShortcutEditor:startCapture(index)
    local row = self.rows[index]
    if row == nil then return false end
    self.selected, self.pendingDelete = index, nil
    local currentModifier = rowSingleModifier(row)
    self.capture = {
        index = index,
        currentKey = tostring(row.key or ""),
        currentModifier = currentModifier,
        pendingKey = tostring(row.key or ""),
        pendingModifier = currentModifier,
        currentHadMultipleModifiers = (row.ctrl == true and row.shift == true)
            or (row.ctrl == true and row.alt == true) or (row.shift == true and row.alt == true),
    }
    self:refreshPalworldBindings()
    self:setGroupVisible(self.captureWidgets, true)
    self:setGroupVisible(self.textWidgets, false)
    self:refreshPickerVisuals()
    if self.capture.currentHadMultipleModifiers then
        self.o.setText(self.captureStatus,
            T("multiModifierWarning"))
    end
    self.o.log("Shortcut binding picker opened: " .. tostring(row.id), true)
    return true
end

function ShortcutEditor:commitBinding(candidate, modifiers)
    local capture = self.capture
    local row = capture and self.rows[capture.index] or nil
    if row == nil then return false end
    local previous = cloneRow(row)
    row.key = candidate.spec
    row.ctrl = modifiers ~= nil and modifiers.ctrl == true
    row.shift = modifiers ~= nil and modifiers.shift == true
    row.alt = modifiers ~= nil and modifiers.alt == true
    row.rawColumnCount = 7
    local valid, errors = self:validation()
    if not valid then
        for _, entry in ipairs(errors) do
            if entry.row == capture.index then
                self.rows[capture.index] = previous
                self.o.setText(self.captureStatus, T("notAccepted", { message = entry.message }))
                return false
            end
        end
    end
    local spec = composeSpec(row)
    self.o.log("Shortcut binding capture detected: " .. tostring(spec), true)
    self:updateList()
    self:stopInput("event-driven binding applied to draft")
    self:setValidationStatus(T("statusUnsaved"))
    return true
end

function ShortcutEditor:confirmPendingBinding()
    local capture = self.capture
    if capture == nil then return false end
    local issue = self:pickerIssue(capture.pendingKey, capture.pendingModifier)
    if issue.blocked == true then
        self.o.setText(self.captureStatus, issue.message or T("shortcutUnavailable"))
        return false
    end
    local modifier = capture.pendingModifier
    return self:commitBinding({ spec = capture.pendingKey }, {
        ctrl = modifier == "ctrl",
        shift = modifier == "shift",
        alt = modifier == "alt",
    })
end

function ShortcutEditor:tick(pc)
    return self.textEdit ~= nil or self.capture ~= nil
end

function ShortcutEditor:uniqueId(base)
    base = string.lower(tostring(base or "shortcut")):gsub("[^a-z0-9_-]", "_")
    if base == "" then base = "shortcut" end
    local candidate, suffix = base, 2
    while self:idExists(candidate, nil) do
        candidate = string.sub(base, 1, 35) .. "_" .. tostring(suffix)
        suffix = suffix + 1
    end
    return candidate
end

function ShortcutEditor:addRow(source)
    if #self.rows >= 256 then
        self.o.setText(self.statusText, T("definitionLimit"))
        return false
    end
    local row
    if source ~= nil then
        row = cloneRow(source)
        row.id = self:uniqueId(row.id)
        row.originalId, row.sourceLine = nil, nil
    else
        row = { id = self:uniqueId("shortcut"), label = T("newShortcut"),
            key = "F24", ctrl = false, shift = false, alt = false,
            active = false, originalId = nil }
    end
    row.rawColumnCount = 7
    self.rows[#self.rows + 1] = row
    self.selected = #self.rows
    self.page = self:pageCount()
    self:updateList()
    self:setValidationStatus(T("statusUnsaved"))
    return true
end

function ShortcutEditor:deleteRow(index)
    local row = self.rows[index]
    if row == nil then return false end
    if self.pendingDelete ~= index then
        self.pendingDelete = index
        local slots = type(self.o.assignedSlots) == "function" and self.o.assignedSlots(row.id) or {}
        local suffix = #slots > 0 and T("assignedSlotsEmpty", {
            slots = table.concat(slots, ", ") }) or ""
        self.o.setText(self.statusText, T("deleteShortcutConfirm", {
            id = row.id, suffix = suffix }))
        return false
    end
    table.remove(self.rows, index)
    self.pendingDelete = nil
    self.selected = nil
    self:updateList()
    self:setValidationStatus(T("statusUnsaved"))
    return true
end

function ShortcutEditor:save()
    local valid = self:setValidationStatus(T("statusNotSaved"))
    if not valid then return false end
    local ok, result, why, warnings = self.o.applyDraft(self.rows, self.sourceText)
    if ok ~= true then
        self.o.setText(self.statusText, T("notSavedPrefix", { message = why or result }))
        return false
    end
    self.rows = cloneRows(result.rows)
    self.baselineRows = cloneRows(result.rows)
    for index, row in ipairs(self.rows) do
        row.originalId = row.id
        row.sourceLine = index + 1
    end
    self.sourceText = result.sourceText
    self.headerValid = true
    self.pendingDelete, self.pendingRestore = nil, false
    self:updateList()
    self.o.setText(self.statusText, #((warnings) or {}) > 0
        and T("savedWarning", { message = warnings[1] })
        or T("shortcutsSaved"))
    return true
end

function ShortcutEditor:handleClick(x, y, direction)
    if not self.open then return false end
    if self.confirmOpen then
        if direction < 0 or pointInRect(x, y, self.confirmCancelRect) then
            self:setConfirmVisible(false)
            return true
        end
        if pointInRect(x, y, self.confirmDiscardRect) then
            self:discardAndClose()
            return true
        end
        return true
    end
    if self.textEdit ~= nil then
        if direction < 0 or pointInRect(x, y, self.textCancelRect) then
            self:stopInput("text edit cancelled")
        elseif pointInRect(x, y, self.textApplyRect) then self:commitText()
        elseif self.textEdit.field ~= "id" and pointInRect(x, y, self.textCaseRect) then
            self:toggleTextCase()
        elseif pointInRect(x, y, self.textBackspaceRect) then self:backspaceText()
        elseif pointInRect(x, y, self.textClearRect) then self:clearText()
        elseif pointInRect(x, y, self.textRestoreRect) then self:restoreText()
        else
            for _, choice in ipairs(self.textChoices) do
                local usable = self.textEdit.field ~= "id" or choice.idAllowed == true
                if usable and pointInRect(x, y, choice.rect) then
                    self:insertTextChoice(choice)
                    return true
                end
            end
        end
        return true
    end
    if self.capture ~= nil then
        if direction < 0 or pointInRect(x, y, self.captureCancelRect) then
            self:stopInput("binding picker cancelled")
            return true
        end
        if pointInRect(x, y, self.captureConfirmRect) then
            self:confirmPendingBinding()
            return true
        end
        for modifier, rect in pairs(self.modifierRects) do
            if pointInRect(x, y, rect) then
                self:togglePendingModifier(modifier)
                return true
            end
        end
        for spec, rect in pairs(self.pickerChoiceRects) do
            if pointInRect(x, y, rect) then
                self:selectPendingKey(spec)
                return true
            end
        end
        return true
    end
    if pointInRect(x, y, self.instructionsRect) then
        if type(self.o.openInstructions) == "function" then self.o.openInstructions("shortcuts") end
        return true
    end
    if direction < 0 or pointInRect(x, y, self.closeRect) then self:requestClose(); return true end
    if pointInRect(x, y, self.prevRect) then
        self.page = self.page - 1; if self.page < 1 then self.page = self:pageCount() end
        self:updateList(); return true
    end
    if pointInRect(x, y, self.nextRect) then
        self.page = self.page + 1; if self.page > self:pageCount() then self.page = 1 end
        self:updateList(); return true
    end
    if pointInRect(x, y, self.addRect) then self:addRow(nil); return true end
    if pointInRect(x, y, self.reloadRect) then self:reload(); return true end
    if pointInRect(x, y, self.restoreRect) then
        if not self.pendingRestore then
            self.pendingRestore = true
            self.o.setText(self.statusText,
                T("restorePackagedConfirm"))
        else
            self.rows = cloneRows(self.o.defaultRows())
            self.pendingRestore, self.selected, self.page = false, nil, 1
            self:updateList(); self:setValidationStatus(T("statusUnsavedDefaultDraft"))
        end
        return true
    end
    if pointInRect(x, y, self.saveRect) then self:save(); return true end
    local first = (self.page - 1) * PAGE_SIZE + 1
    for displayRow, rects in ipairs(self.rowRects) do
        local index = first + displayRow - 1
        local row = self.rows[index]
        if row ~= nil then
            if pointInRect(x, y, rects.active) then
                self.selected, self.pendingDelete = index, nil
                row.active = row.active ~= true; row.rawColumnCount = 7
                self:updateList(); self:setValidationStatus(T("statusUnsaved")); return true
            elseif pointInRect(x, y, rects.label) then self:startText(index, "label"); return true
            elseif pointInRect(x, y, rects.id) then self:startText(index, "id"); return true
            elseif pointInRect(x, y, rects.binding) then self:startCapture(index); return true
            elseif pointInRect(x, y, rects.duplicate) then self.selected = index; self:addRow(row); return true
            elseif pointInRect(x, y, rects.delete) then self:deleteRow(index); return true end
        end
    end
    return true
end

return ShortcutEditor
