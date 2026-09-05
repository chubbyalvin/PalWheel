
local Builder = {}
Builder.__index = Builder

local L = require("localization")
local TextLayout = require("text_layout")
local function T(key, variables) return L.get(key, variables) end

local PAGE_SIZE = 12
local TOTAL_SLOTS = 36

local function safe(callback)
    return pcall(callback)
end

local BRAND_WHITE = { R = 1.00, G = 1.00, B = 1.00, A = 1.0 }
local BRAND_GOLD = { R = 0.961, G = 0.631, B = 0.102, A = 1.0 }

local BRAND_FONT_PATH = "/Game/Pal/Font/Anton-Regular_Font.Anton-Regular_Font"
local BRAND_FONT_PACKAGE = "/Game/Pal/Font/Anton-Regular_Font"
local UI_FONT_PATH = "/Game/Pal/Font/Ft_PalDefaultFont.Ft_PalDefaultFont"
local UI_FONT_PACKAGE = "/Game/Pal/Font/Ft_PalDefaultFont"
local brandFontObject = nil
local brandFontAttempted = false
local uiFontObject = nil
local uiFontAttempted = false

local function getBrandFont()
    if brandFontAttempted then return brandFontObject end
    brandFontAttempted = true
    local ok, object = safe(function() return StaticFindObject(BRAND_FONT_PATH) end)
    if ok and object ~= nil then
        brandFontObject = object
        return brandFontObject
    end
    if type(LoadAsset) == "function" then
        safe(function() LoadAsset(BRAND_FONT_PACKAGE) end)
        safe(function() LoadAsset(BRAND_FONT_PATH) end)
    end
    ok, object = safe(function() return StaticFindObject(BRAND_FONT_PATH) end)
    if ok and object ~= nil then brandFontObject = object end
    return brandFontObject
end

local function getUIFont()
    if uiFontAttempted then return uiFontObject end
    uiFontAttempted = true
    local ok, object = safe(function() return StaticFindObject(UI_FONT_PATH) end)
    if ok and object ~= nil then
        uiFontObject = object
        return uiFontObject
    end
    if type(LoadAsset) == "function" then
        safe(function() LoadAsset(UI_FONT_PACKAGE) end)
        safe(function() LoadAsset(UI_FONT_PATH) end)
    end
    ok, object = safe(function() return StaticFindObject(UI_FONT_PATH) end)
    if ok and object ~= nil then uiFontObject = object end
    return uiFontObject
end

local function styleText(widget, color, fontSize, bold, useBrandFont)
    if widget == nil then return end
    if tonumber(fontSize) ~= nil or bold == true or useBrandFont == true then
        safe(function()
            local font = widget.Font
            if tonumber(fontSize) ~= nil then
                font.Size = math.floor(tonumber(fontSize))
            end
            if useBrandFont == true then
                local fontObject = getBrandFont()
                if fontObject ~= nil then font.FontObject = fontObject end
                local okName, regularName = safe(function() return FName("Regular") end)
                font.TypefaceFontName = (okName and regularName ~= nil) and regularName or "Regular"
            else
                local fontObject = getUIFont()
                if fontObject ~= nil then font.FontObject = fontObject end
            end
            if useBrandFont ~= true and bold == true then
                local okName, boldName = safe(function() return FName("Bold") end)
                if okName and boldName ~= nil then
                    font.TypefaceFontName = boldName
                else
                    font.TypefaceFontName = "Bold"
                end
            end
            widget:SetFont(font)
        end)
    end
    if color ~= nil then
        local ok = safe(function()
            widget:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
        end)
        if not ok then
            ok = safe(function()
                local slate = widget.ColorAndOpacity
                slate.SpecifiedColor = color
                slate.ColorUseRule = 0
                widget:SetColorAndOpacity(slate)
            end)
        end
        if not ok then
            safe(function() widget:SetColorAndOpacity(color) end)
        end
    end
end

local function createBrandText(o, root, suffix, x, y, width, height, fontSize, boldSuffix)
    local box = o.construct("/Script/UMG.HorizontalBox", o.state.tree)
    local boxSlot = box and o.addToCanvas(root, box) or nil
    if boxSlot == nil then return nil end
    o.place(boxSlot, x, y, width, height)
    safe(function() box:SetVisibility(o.hitTestInvisible) end)

    local function addPiece(textValue, color, bold)
        local text = o.construct("/Script/UMG.TextBlock", o.state.tree)
        if text == nil then return false end
        local added, childSlot = safe(function() return box:AddChildToHorizontalBox(text) end)
        if not added or childSlot == nil then
            added, childSlot = safe(function() return box:AddChild(text) end)
        end
        if not added or childSlot == nil then return false end
        o.setText(text, textValue)
        styleText(text, color, fontSize, bold, true)
        safe(function() text:SetAutoWrapText(false) end)
        safe(function() text:SetVisibility(o.hitTestInvisible) end)
        return true
    end

    if not addPiece("PAL", BRAND_WHITE, true)
        or not addPiece("WHEEL", BRAND_GOLD, true)
        or not addPiece(tostring(suffix or ""), BRAND_WHITE, boldSuffix == true) then
        safe(function() box:RemoveFromParent() end)
        return nil
    end
    return box
end

local function createAuthorText(o, root, prefix, x, y, width, height, fontSize)
    local box = o.construct("/Script/UMG.HorizontalBox", o.state.tree)
    local boxSlot = box and o.addToCanvas(root, box) or nil
    if boxSlot == nil then return nil end
    o.place(boxSlot, x, y, width, height)
    safe(function() box:SetVisibility(o.hitTestInvisible) end)

    local function addPiece(textValue, color, brand)
        local text = o.construct("/Script/UMG.TextBlock", o.state.tree)
        if text == nil then return false end
        local added, childSlot = safe(function() return box:AddChildToHorizontalBox(text) end)
        if not added or childSlot == nil then
            added, childSlot = safe(function() return box:AddChild(text) end)
        end
        if not added or childSlot == nil then return false end
        o.setText(text, textValue)
        styleText(text, color, fontSize, brand == true, brand == true)
        safe(function() text:SetAutoWrapText(false) end)
        safe(function() text:SetVisibility(o.hitTestInvisible) end)
        return true
    end

    if not addPiece(tostring(prefix or ""), BRAND_WHITE, false)
        or not addPiece("CHUBBY", BRAND_WHITE, true)
        or not addPiece("ALVIN", BRAND_GOLD, true) then
        safe(function() box:RemoveFromParent() end)
        return nil
    end
    return box
end

function Builder.new(options)
    return setmetatable({
        o = options,
        started = false,
        complete = false,
        phase = "base",
        rowIndex = 1,
        groupIndex = 1,
        groupRow = 1,
        root = nil,
        progressText = nil,
        rowWidgets = {},
        picker = nil,
        totalUnits = 73,
        completedUnits = 0,
        editorRoot = nil,
    }, Builder)
end

function Builder:cell(x, y, width, height, color, textValue, textInset, fontSize, justification)
    local o, root = self.o, self.root
    local border = o.construct("/Script/UMG.Border", o.state.tree)
    local slot = border and o.addToCanvas(root, border) or nil
    if slot ~= nil then
        o.place(slot, x, y, width, height)
        o.setBorderColor(border, color)
        safe(function() border:SetVisibility(o.hitTestInvisible) end)
    end
    local inset = textInset or 10
    local size = tonumber(fontSize) or 13
    local centered = justification == nil or tonumber(justification) == 1
    local textX = centered and (x + width * 0.5) or (x + inset)
    local textY = y + height * 0.5
    local textWidth = math.max(10, width - inset * 2)
    local textHeight = math.max(18, height - 4)
    size = TextLayout.fitFontSize(textValue or "", size, textWidth, textHeight, 8)
    local text = o.createText(o.state.tree, root, textValue or "", textX, textY,
        textWidth, textHeight,
        size, centered and 1 or (tonumber(justification) or 0))
    
    
    
    safe(function()
        if text ~= nil and text.Slot ~= nil then
            text.Slot:SetAutoSize(false)
            text.Slot:SetAlignment({ X = centered and 0.5 or 0.0, Y = 0.5 })
            text.Slot:SetPosition({ X = textX, Y = textY })
        end
    end)
    return border, text
end

function Builder:outline(x, y, width, height, thickness)
    local o, root = self.o, self.root
    local t = math.max(1, math.floor(tonumber(thickness) or 2))
    local color = o.colors.button

    local function edge(ex, ey, ew, eh)
        local border = o.construct("/Script/UMG.Border", o.state.tree)
        local slot = border and o.addToCanvas(root, border) or nil
        if slot ~= nil then
            o.place(slot, ex, ey, ew, eh)
            o.setBorderColor(border, color)
            safe(function() border:SetVisibility(o.hitTestInvisible) end)
        end
        return border
    end

    return {
        edge(x, y, width, t),
        edge(x, y + height - t, width, t),
        edge(x, y, t, height),
        edge(x + width - t, y, t, height),
    }
end

function Builder:updateMenuHint()
    local o, state = self.o, self.o.state
    if state.editorMenuHintText == nil then return end
    local value = o.cfg("settingsKey", "F7")
    local display = o.cfg("displayName", nil)
    local label = tostring(value or "F7")
    if type(display) == "function" then
        local ok, result = pcall(display, value)
        if ok and result ~= nil then label = tostring(result) end
    end
    o.setText(state.editorMenuHintText, T("menuHint", { key = label }))
end

function Builder:updateProgress()
    if self.progressText == nil then return end
    if self.complete then
        self.o.setVisible(self.progressText, false)
        return
    end
    local percent = math.floor(self.completedUnits / self.totalUnits * 100)
    self.o.setText(self.progressText, T("preparingMenu", { percent = percent }))
end

function Builder:start(pc)
    if self.started then return self.o.alive(self.o.state.editorPanel) end
    local o, state = self.o, self.o.state
    if not o.alive(pc) or not o.alive(state.widget) then return false end

    local editorPanel = o.construct("/Script/UMG.CanvasPanel", state.tree)
    local panelSlot = editorPanel and o.addToCanvas(state.root, editorPanel) or nil
    if panelSlot == nil then return false end
    o.place(panelSlot, 0, 0, tonumber(o.cfg("screenWidth", 1920)) or 1920,
        tonumber(o.cfg("screenHeight", 1080)) or 1080)
    state.editorPanel = editorPanel
    self.root = editorPanel

    local panel = o.construct("/Script/UMG.Border", state.tree)
    local slot = panel and o.addToCanvas(editorPanel, panel) or nil
    if slot ~= nil then
        o.place(slot, 130, 82, 1660, 914)
        o.setBorderColor(panel, o.colors.panel)
        safe(function() panel:SetVisibility(o.hitTestInvisible) end)
    end
    self:outline(130, 82, 1660, 914, 2)

    createBrandText(o, editorPanel, T("menuSuffix"), 180, 108, 760, 42, 24, true)
    state.editorMenuHintText = o.createText(state.tree, editorPanel, "",
        180, 148, 1200, 32, 14, 0)
    self:updateMenuHint()

    
    local TOP_CONTROL_Y = 194
    local TOP_CONTROL_H = 30
    local TOP_CONTROL_FONT = 11
    local function createCompactLabel(label, x, width, centerY, fontSize)
        local size = tonumber(fontSize) or TOP_CONTROL_FONT
        local text = o.createText(state.tree, editorPanel, label, x, centerY,
            width, 20, size, 0, 8)
        safe(function()
            if text ~= nil and text.Slot ~= nil then
                text.Slot:SetAlignment({ X = 0.0, Y = 0.5 })
                text.Slot:SetPosition({ X = x, Y = centerY - 10 })
            end
        end)
        return text
    end

    local TOP_LABEL_CENTER_Y = TOP_CONTROL_Y + TOP_CONTROL_H * 0.5
    createCompactLabel(T("wheels"), 180, 70, TOP_LABEL_CENTER_Y)
    local palWheelCountBorder
    palWheelCountBorder, state.editorWheelCountText = self:cell(
        260, TOP_CONTROL_Y, 70, TOP_CONTROL_H, o.colors.button, "", 8, TOP_CONTROL_FONT)
    state.editorWheelCountDropdownRect = { x = 260, y = TOP_CONTROL_Y, w = 70, h = TOP_CONTROL_H }
    o.updateWheelCountText()

    
    createCompactLabel(T("slowMotion"), 350, 120, TOP_LABEL_CENTER_Y)
    local slowMotionBorder
    slowMotionBorder, state.editorSlowMotionText = self:cell(
        480, TOP_CONTROL_Y, 70, TOP_CONTROL_H, o.colors.button, "", 8, TOP_CONTROL_FONT)
    state.editorSlowMotionRect = { x = 480, y = TOP_CONTROL_Y, w = 70, h = TOP_CONTROL_H }
    o.updateSlowMotionText()
    
    o.createText(state.tree, editorPanel,
        T("multiplayerSlowMotionOff"),
        350, 219, 200, 16, 5, 0)

    
    
    local SKIN_CONTROL_Y = 946
    local SKIN_LABEL_CENTER_Y = SKIN_CONTROL_Y + TOP_CONTROL_H * 0.5
    createCompactLabel(T("skin"), 180, 55, SKIN_LABEL_CENTER_Y)
    local skinBorder
    skinBorder, state.editorSkinText = self:cell(
        240, SKIN_CONTROL_Y, 190, TOP_CONTROL_H, o.colors.button, "", 8, TOP_CONTROL_FONT)
    state.editorSkinDropdownRect = { x = 240, y = SKIN_CONTROL_Y, w = 190, h = TOP_CONTROL_H }
    o.updateSkinText()

    local resetBorder = self:cell(
        1270, 104, 230, 36, o.colors.button, T("restoreDefaults"), 0, 12, 1)
    local instructionsBorder = self:cell(
        1510, 104, 230, 36, o.colors.button, T("instructions"), 0, 12, 1)
    state.editorResetShortcutsRect = { x = 1270, y = 104, w = 230, h = 36 }
    state.editorInstructionsRect = { x = 1510, y = 104, w = 230, h = 36 }

    
    
    local controllerGroup = o.construct("/Script/UMG.Border", state.tree)
    local controllerGroupSlot = controllerGroup and o.addToCanvas(editorPanel, controllerGroup) or nil
    if controllerGroupSlot ~= nil then
        o.place(controllerGroupSlot, 1190, 164, 550, 70)
        o.setBorderColor(controllerGroup, o.colors.rowAlt)
        safe(function() controllerGroup:SetVisibility(o.hitTestInvisible) end)
    end
    o.createText(state.tree, editorPanel, T("controllerOnlySettings"), 1210, 168, 300, 18, 9, 0)

    local CONTROLLER_ROW_Y = 194
    local CONTROLLER_ROW_H = 30
    local CONTROLLER_FONT = 11

    o.createText(state.tree, editorPanel, T("zoom"), 1210, 199, 55, 20, CONTROLLER_FONT, 0)
    state.editorZoomBorder, state.editorZoomText = self:cell(
        1270, CONTROLLER_ROW_Y, 70, CONTROLLER_ROW_H, o.colors.row, "", 10, CONTROLLER_FONT)
    state.editorZoomRect = { x = 1270, y = CONTROLLER_ROW_Y, w = 70, h = CONTROLLER_ROW_H }
    if type(o.updateZoomText) == "function" then o.updateZoomText() end

    o.createText(state.tree, editorPanel, T("haptics"), 1360, 199, 78, 20, CONTROLLER_FONT, 0)
    local hapticsBorder
    hapticsBorder, state.editorHapticsText = self:cell(
        1440, CONTROLLER_ROW_Y, 70, CONTROLLER_ROW_H, o.colors.button, "", 10, CONTROLLER_FONT)
    state.editorHapticsRect = { x = 1440, y = CONTROLLER_ROW_Y, w = 70, h = CONTROLLER_ROW_H }
    o.updateHapticsText()

    o.createText(state.tree, editorPanel, T("followTarget"), 1520, 199, 120, 20, CONTROLLER_FONT, 0)
    state.editorFollowTargetBorder, state.editorFollowTargetText = self:cell(
        1650, CONTROLLER_ROW_Y, 70, CONTROLLER_ROW_H, o.colors.row, "", 10, CONTROLLER_FONT)
    state.editorFollowTargetRect = { x = 1650, y = CONTROLLER_ROW_Y, w = 70, h = CONTROLLER_ROW_H }
    if type(o.updateFollowTargetText) == "function" then o.updateFollowTargetText() end

    
    
    local columnX = { 180, 487, 794 }
    local tableW, slotW, gap = 292, 50, 4
    local assignmentW = tableW - slotW - gap
    state.editorCountTexts = {}
    state.editorCountDropdownRects = {}

    for page = 1, 3 do
        local x = columnX[page]
        self:cell(x, 254, tableW, 42, o.colors.button,
            T("wheel", { wheel = o.wheelRoman and o.wheelRoman(page) or tostring(page) }),
            14, 17, 0)

        local countX = x + tableW - 118
        local _, countText = self:cell(
            countX, 259, 108, 32, o.colors.row, "", 10, 12)
        state.editorCountTexts[page] = countText
        state.editorCountDropdownRects[page] = {
            x = countX, y = 259, w = 108, h = 32
        }
        o.updateCountText(page)

        self:cell(x, 299, slotW, 34, o.colors.row, T("slot"), 8, 13)
        self:cell(x + slotW + gap, 299, assignmentW, 34, o.colors.row,
            T("functionName"), 10, 12, 0)
    end

    self.progressText = o.createText(state.tree, editorPanel,
        T("preparingMenu", { percent = 0 }), 655, 936, 610, 28, 14)
    o.setVisible(editorPanel, false)
    self.started = true
    self.phase = "rows"
    self:updateProgress()
    o.log("Incremental PalWheel editor frame prepared", true)
    return true
end

function Builder:buildRow(slotIndex)
    local o, state = self.o, self.o.state
    local page = math.floor((slotIndex - 1) / PAGE_SIZE) + 1
    local localSlot = ((slotIndex - 1) % PAGE_SIZE) + 1
    local columnX = { 180, 487, 794 }
    local x = columnX[page]
    local y = 337 + (localSlot - 1) * 46
    local neutral = localSlot % 2 == 0 and o.colors.rowAlt or o.colors.row
    local slotBorder, slotText = self:cell(x, y, 50, 43, neutral,
        string.format("%02d", localSlot), 12, 13)
    local assignmentX = x + 54
    local assignmentBorder, assignmentText = self:cell(
        assignmentX, y, 238, 43, o.colors.empty, "", 10, 13, 0)
    state.editorRows[slotIndex] = {
        slotBorder = slotBorder,
        slotText = slotText,
        assignmentBorder = assignmentBorder,
        assignmentText = assignmentText,
        rect = { x = assignmentX, y = y, w = 238, h = 43 },
    }
    for _, widget in ipairs({
        slotBorder, slotText, assignmentBorder, assignmentText
    }) do
        self.rowWidgets[#self.rowWidgets + 1] = widget
        o.setVisible(widget, false)
    end
    o.updateRow(slotIndex)
end

function Builder:beginPicker()
    local o, state = self.o, self.o.state
    local pickerLayer = o.construct("/Script/UMG.CanvasPanel", state.tree)
    local layerSlot = pickerLayer and o.addToCanvas(self.root, pickerLayer) or nil
    if layerSlot ~= nil then
        o.place(layerSlot, 0, 0,
            tonumber(o.cfg("screenWidth", 1920)) or 1920,
            tonumber(o.cfg("screenHeight", 1080)) or 1080)
        safe(function() layerSlot:SetZOrder(30) end)
        o.setVisible(pickerLayer, false)
        self.editorRoot = self.root
        self.root = pickerLayer
        state.editorPickerLayer = pickerLayer
        state.editorPickerChildrenInitialized = false
    end
    local pickerX, pickerY, pickerW, pickerH = 205, 188, 1510, 690
    state.editorPickerPanelRect = { x = pickerX, y = pickerY, w = pickerW, h = pickerH }
    local panel = o.construct("/Script/UMG.Border", state.tree)
    local slot = panel and o.addToCanvas(self.root, panel) or nil
    if slot ~= nil then
        o.place(slot, pickerX, pickerY, pickerW, pickerH)
        o.setBorderColor(panel, o.colors.panel)
        state.editorPickerPanel = panel
    end
    local pickerOutline = self:outline(pickerX, pickerY, pickerW, pickerH, 2)
    for _, widget in ipairs(pickerOutline) do
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = widget
        o.setVisible(widget, false)
    end
    state.editorPickerTitle = o.createText(state.tree, self.root,
        T("chooseFunction"), pickerX + 38, pickerY + 22,
        pickerW - 76, 42, 18)
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = panel
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = state.editorPickerTitle
    o.setVisible(panel, false)
    o.setVisible(state.editorPickerTitle, false)

    self.picker = {
        { title = T("weapons"), x = 225, width = 220,
            ids = { "weapon1", "weapon2", "weapon3", "weapon4", "weapon5", "weapon6" } },
        { title = T("palwheel"), x = 225, width = 220, headerY = 620, itemStartY = 662,
            ids = { "mercy", "empty" } },
        { title = T("emotes"), x = 951, width = 220,
            ids = { "emote_0", "emote_1", "emote_2", "emote_3", "emote_4",
                "emote_5", "emote_6", "emote_7", "emote_8" } },
    }
    self.groupIndex, self.groupRow = 1, 0
end

function Builder:buildPickerUnit()
    local o, state = self.o, self.o.state
    local group = self.picker and self.picker[self.groupIndex] or nil
    if group == nil then return false end

    if self.groupRow == 0 then
        local border = o.construct("/Script/UMG.Border", state.tree)
        local slot = border and o.addToCanvas(self.root, border) or nil
        if slot ~= nil then
            o.place(slot, group.x, group.headerY or 276, group.width, 36)
            o.setBorderColor(border, o.colors.button)
            safe(function() border:SetVisibility(o.hitTestInvisible) end)
        end
        local text = o.createText(state.tree, self.root, group.title,
            group.x + 12, (group.headerY or 276) + 6, group.width - 24, 26, 14)
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = border
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = text
        o.setVisible(border, false)
        o.setVisible(text, false)
        self.groupRow = 1
        return true
    end

    local functionId = group.ids[self.groupRow]
    if functionId == nil then
        self.groupIndex = self.groupIndex + 1
        self.groupRow = 0
        return self:buildPickerUnit()
    end
    local def = o.byId[functionId]
    if def ~= nil then
        local y = (group.itemStartY or 326) + (self.groupRow - 1) * 48
        local border = o.construct("/Script/UMG.Border", state.tree)
        local slot = border and o.addToCanvas(self.root, border) or nil
        if slot ~= nil then
            o.place(slot, group.x, y, group.width, 42)
            o.setBorderColor(border, o.colorForDefinition(def))
            safe(function() border:SetVisibility(o.hitTestInvisible) end)
        end
        local textInset = 10
        local text = o.createText(state.tree, self.root, def.label,
            group.x + textInset, y + 8, group.width - textInset - 10, 26, 14)
        if def.available == false or def.pending == true then
            styleText(text, { R = 1.00, G = 0.18, B = 0.16, A = 1.0 }, nil, true)
        end
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = border
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = text
        state.editorPickerRects[def.catalogIndex] = {
            x = group.x, y = y, w = group.width, h = 42,
        }
        o.setVisible(border, false)
        o.setVisible(text, false)
    end
    self.groupRow = self.groupRow + 1
    return true
end

function Builder:finish()
    local o, state = self.o, self.o.state
    state.editorPartyWidgets = {}
    state.editorPartyRects = {}
    state.editorPartyRowIds = {}
    local partyX, partyW = 457, 220
    local partyHeaderBorder, partyHeaderText = self:cell(
        partyX, 276, partyW, 36, o.colors.button, T("party"), 12, 14)
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = partyHeaderBorder
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = partyHeaderText
    o.setVisible(partyHeaderBorder, false)
    o.setVisible(partyHeaderText, false)
    for row = 1, 10 do
        local y = 326 + (row - 1) * 48
        local border, label = self:cell(
            partyX, y, partyW, 42, o.colors.pal, "", 10, 13)
        state.editorPartyWidgets[row] = { border = border, text = label }
        state.editorPartyRects[row] = { x = partyX, y = y, w = partyW, h = 42 }
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = border
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = label
        o.setVisible(border, false)
        o.setVisible(label, false)
    end
    local partyPrevBorder, partyPrevText = self:cell(
        partyX, 810, 48, 34, o.colors.button, "<", 17, 12)
    local partyNextBorder, partyNextText = self:cell(
        partyX + partyW - 48, 810, 48, 34, o.colors.button, ">", 17, 12)
    state.editorPartyPrevRect = { x = partyX, y = 810, w = 48, h = 34 }
    state.editorPartyNextRect = {
        x = partyX + partyW - 48, y = 810, w = 48, h = 34
    }
    state.editorPartyPrevWidgets = { partyPrevBorder, partyPrevText }
    state.editorPartyNextWidgets = { partyNextBorder, partyNextText }
    state.editorPartyPageText = o.createText(
        state.tree, self.root, T("page", { page = 1, pages = 1 }), partyX + 48, 815, partyW - 96, 24, 11)
    for _, widget in ipairs({
        partyPrevBorder, partyPrevText, partyNextBorder, partyNextText,
        state.editorPartyPageText
    }) do
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = widget
        o.setVisible(widget, false)
    end

    state.editorPalworldWidgets = {}
    state.editorPalworldRects = {}
    state.editorPalworldRowIds = {}
    local palworldX, palworldW = 689, 250
    local palworldHeaderBorder, palworldHeaderText = self:cell(
        palworldX, 276, palworldW, 36, o.colors.button, T("palworld"), 12, 14)
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = palworldHeaderBorder
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = palworldHeaderText
    o.setVisible(palworldHeaderBorder, false)
    o.setVisible(palworldHeaderText, false)
    for row = 1, 10 do
        local y = 326 + (row - 1) * 48
        local border, label = self:cell(
            palworldX, y, palworldW, 42, o.colors.menu, "", 10, 13)
        state.editorPalworldWidgets[row] = { border = border, text = label }
        state.editorPalworldRects[row] = { x = palworldX, y = y, w = palworldW, h = 42 }
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = border
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = label
        o.setVisible(border, false)
        o.setVisible(label, false)
    end
    local palworldPrevBorder, palworldPrevText = self:cell(
        palworldX, 810, 48, 34, o.colors.button, "<", 17, 12)
    local palworldNextBorder, palworldNextText = self:cell(
        palworldX + palworldW - 48, 810, 48, 34, o.colors.button, ">", 17, 12)
    state.editorPalworldPrevRect = { x = palworldX, y = 810, w = 48, h = 34 }
    state.editorPalworldNextRect = {
        x = palworldX + palworldW - 48, y = 810, w = 48, h = 34
    }
    state.editorPalworldPrevWidgets = { palworldPrevBorder, palworldPrevText }
    state.editorPalworldNextWidgets = { palworldNextBorder, palworldNextText }
    state.editorPalworldPageText = o.createText(
        state.tree, self.root, T("page", { page = 1, pages = 2 }), palworldX + 48, 815, palworldW - 96, 24, 11)
    for _, widget in ipairs({
        palworldPrevBorder, palworldPrevText, palworldNextBorder, palworldNextText,
        state.editorPalworldPageText
    }) do
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = widget
        o.setVisible(widget, false)
    end

    state.editorShortcutWidgets = {}
    state.editorShortcutRects = {}
    state.editorShortcutRowIds = {}
    local shortcutX, shortcutW = 1183, 497
    local shortcutHeaderBorder, shortcutHeaderText = self:cell(
        shortcutX, 276, shortcutW, 36, o.colors.button, T("customShortcuts"), 12, 14)
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = shortcutHeaderBorder
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = shortcutHeaderText
    o.setVisible(shortcutHeaderBorder, false)
    o.setVisible(shortcutHeaderText, false)
    for row = 1, 10 do
        local y = 326 + (row - 1) * 48
        local border, label = self:cell(shortcutX, y, shortcutW, 42, o.colors.shortcut, "", 10, 13)
        state.editorShortcutWidgets[row] = { border = border, text = label }
        state.editorShortcutRects[row] = { x = shortcutX, y = y, w = shortcutW, h = 42 }
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = border
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = label
        o.setVisible(border, false)
        o.setVisible(label, false)
    end
    local shortcutFooterX = shortcutX + math.floor((shortcutW - 220) * 0.5)
    local prevBorder, prevText = self:cell(shortcutFooterX, 810, 48, 34, o.colors.button, "<", 17, 12)
    local nextBorder, nextText = self:cell(shortcutFooterX + 172, 810, 48, 34, o.colors.button, ">", 17, 12)
    state.editorShortcutPrevRect = { x = shortcutFooterX, y = 810, w = 48, h = 34 }
    state.editorShortcutNextRect = { x = shortcutFooterX + 172, y = 810, w = 48, h = 34 }
    state.editorShortcutPrevWidgets = { prevBorder, prevText }
    state.editorShortcutNextWidgets = { nextBorder, nextText }
    state.editorShortcutPageText = o.createText(state.tree, self.root, T("page", { page = 1, pages = 1 }),
        shortcutFooterX + 48, 815, 124, 24, 11)
    for _, widget in ipairs({ prevBorder, prevText, nextBorder, nextText, state.editorShortcutPageText }) do
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = widget
        o.setVisible(widget, false)
    end

    local help = o.createText(state.tree, self.root,
        T("rightClickCancel"),
        710, 850, 500, 22, 11)
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = help
    o.setVisible(help, false)

    if self.editorRoot ~= nil then self.root = self.editorRoot end

    local confirmPanel = o.construct("/Script/UMG.Border", state.tree)
    local confirmSlot = confirmPanel and o.addToCanvas(self.root, confirmPanel) or nil
    if confirmSlot ~= nil then
        o.place(confirmSlot, 465, 365, 990, 260)
        o.setBorderColor(confirmPanel, o.colors.panel)
    end
    local confirmOutline = self:outline(465, 365, 990, 260, 2)
    local confirmTitle = o.createText(state.tree, self.root, T("restorePalwheelDefaultsTitle"),
        515, 395, 890, 36, 18)
    local confirmBody = o.createText(state.tree, self.root,
        T("restorePalwheelDefaultsBody"),
        515, 445, 890, 82, 13)
    local yesBorder, yesText = self:cell(760, 545, 180, 44, o.colors.button, T("restore"), 42, 14)
    local noBorder, noText = self:cell(980, 545, 180, 44, o.colors.row, T("cancel"), 48, 14)
    state.editorResetConfirmWidgets = { confirmPanel, confirmTitle, confirmBody, yesBorder, yesText, noBorder, noText }
    for _, widget in ipairs(confirmOutline) do
        state.editorResetConfirmWidgets[#state.editorResetConfirmWidgets + 1] = widget
    end
    state.editorResetConfirmYesRect = { x = 760, y = 545, w = 180, h = 44 }
    state.editorResetConfirmNoRect = { x = 980, y = 545, w = 180, h = 44 }
    for _, widget in ipairs(state.editorResetConfirmWidgets) do
        safe(function() if widget ~= nil and widget.Slot ~= nil then widget.Slot:SetZOrder(60) end end)
        o.setVisible(widget, false)
    end

    local discardPanel = o.construct("/Script/UMG.Border", state.tree)
    local discardSlot = discardPanel and o.addToCanvas(self.root, discardPanel) or nil
    if discardSlot ~= nil then
        o.place(discardSlot, 515, 382, 890, 235)
        o.setBorderColor(discardPanel, o.colors.panel)
    end
    local discardOutline = self:outline(515, 382, 890, 235, 2)
    local discardTitle = o.createText(state.tree, self.root, T("discardMainTitle"),
        565, 414, 790, 36, 18)
    local discardBody = o.createText(state.tree, self.root,
        T("discardMainBody"),
        565, 466, 790, 52, 13)
    local discardYesBorder, discardYesText = self:cell(
        730, 545, 210, 44, o.colors.unavailable or o.colors.row, T("discard"), 60, 14)
    local discardNoBorder, discardNoText = self:cell(
        980, 545, 210, 44, o.colors.button, T("cancel"), 62, 14)
    state.editorDiscardConfirmWidgets = {
        discardPanel, discardTitle, discardBody,
        discardYesBorder, discardYesText, discardNoBorder, discardNoText,
    }
    for _, widget in ipairs(discardOutline) do
        state.editorDiscardConfirmWidgets[#state.editorDiscardConfirmWidgets + 1] = widget
    end
    state.editorDiscardConfirmYesRect = { x = 730, y = 545, w = 210, h = 44 }
    state.editorDiscardConfirmNoRect = { x = 980, y = 545, w = 210, h = 44 }
    for _, widget in ipairs(state.editorDiscardConfirmWidgets) do
        safe(function() if widget ~= nil and widget.Slot ~= nil then widget.Slot:SetZOrder(60) end end)
        o.setVisible(widget, false)
    end

	createBrandText(o, self.root,
		" v" .. tostring(o.cfg("version", "1.0")),
		1570, 946, 170, 26, 14, false)
	createAuthorText(o, self.root, T("authorBy"), 1570, 970, 170, 22, 11)

    state.editorCountDropdownWidgets = { {}, {}, {} }
    state.editorCountOptionRects = { {}, {}, {} }
    local columnX = { 180, 487, 794 }
    for page = 1, 3 do
        local x = columnX[page] + 174
        for value = 4, 12 do
            local y = 293 + (value - 4) * 38
            local border, label = self:cell(x, y, 108, 36, o.colors.row,
                T("slots", { count = value }), 8, 11)
            state.editorCountDropdownWidgets[page][#state.editorCountDropdownWidgets[page] + 1] = border
            state.editorCountDropdownWidgets[page][#state.editorCountDropdownWidgets[page] + 1] = label
            state.editorCountOptionRects[page][value] = {
                x = x, y = y, w = 108, h = 36
            }
            safe(function() if border ~= nil and border.Slot ~= nil then border.Slot:SetZOrder(20) end end)
            safe(function() if label ~= nil and label.Slot ~= nil then label.Slot:SetZOrder(20) end end)
            o.setVisible(border, false)
            o.setVisible(label, false)
        end
    end

    state.editorWheelCountDropdownWidgets = {}
    state.editorWheelCountOptionRects = {}
    for value = 1, 3 do
        local y = 228 + (value - 1) * 34
        local border, label = self:cell(260, y, 70, 30, o.colors.row,
            T(value == 1 and "countWheelsOne" or "countWheelsMany", { count = value }), 5, 9)
        state.editorWheelCountDropdownWidgets[#state.editorWheelCountDropdownWidgets + 1] = border
        state.editorWheelCountDropdownWidgets[#state.editorWheelCountDropdownWidgets + 1] = label
        state.editorWheelCountOptionRects[value] = { x = 260, y = y, w = 70, h = 30 }
        safe(function() if border ~= nil and border.Slot ~= nil then border.Slot:SetZOrder(20) end end)
        safe(function() if label ~= nil and label.Slot ~= nil then label.Slot:SetZOrder(20) end end)
        o.setVisible(border, false)
        o.setVisible(label, false)
    end

    state.editorSkinDropdownWidgets = {}
    state.editorSkinOptionRects = {}
    local skins = self.o.wheelSkins or { "wheel_01.png", "wheel_02.png" }
    for index, filename in ipairs(skins) do
        
        local y = 868 - (#skins - index) * 34
        local border, label = self:cell(240, y, 190, 30, o.colors.row,
            filename, 8, 10)
        state.editorSkinDropdownWidgets[#state.editorSkinDropdownWidgets + 1] = border
        state.editorSkinDropdownWidgets[#state.editorSkinDropdownWidgets + 1] = label
        state.editorSkinOptionRects[filename] = { x = 240, y = y, w = 190, h = 30 }
        safe(function() if border ~= nil and border.Slot ~= nil then border.Slot:SetZOrder(20) end end)
        safe(function() if label ~= nil and label.Slot ~= nil then label.Slot:SetZOrder(20) end end)
        o.setVisible(border, false)
        o.setVisible(label, false)
    end
    
    
    local summaryLayer = o.construct("/Script/UMG.CanvasPanel", state.tree)
    local summarySlot = summaryLayer and o.addToCanvas(self.root, summaryLayer) or nil
    if summarySlot ~= nil then
        o.place(summarySlot, 0, 0, tonumber(o.cfg("screenWidth", 1920)) or 1920,
            tonumber(o.cfg("screenHeight", 1080)) or 1080)
        safe(function() summarySlot:SetZOrder(10) end)
    else
        summaryLayer = self.root
    end
    state.editorSummaryLayer = summaryLayer

    
    
    if type(o.buildSphereEditor) == "function" then
        o.buildSphereEditor(summaryLayer, summaryLayer)
    end
    
    if type(o.buildAuxEditor) == "function" then
        o.buildAuxEditor(summaryLayer)
    end
    if type(o.buildBindingEditor) == "function" then
        o.buildBindingEditor(self.root, summaryLayer)
    end
    if type(o.buildShortcutEditor) == "function" then
        o.buildShortcutEditor(self.root, summaryLayer)
    end

    local oldRoot = self.root
    self.root = summaryLayer
    local FOOTER_Y = 902
    local FOOTER_H = 34
    local FOOTER_W = 250
    local FOOTER_FONT = 12
    local saveBorder = self:cell(
        1340, FOOTER_Y, 190, FOOTER_H, o.colors.saveIdle or o.colors.row,
        T("saveAndApply"), 38, FOOTER_FONT)
    state.editorSaveBorder = saveBorder
    state.editorSaveRect = { x = 1340, y = FOOTER_Y, w = 190, h = FOOTER_H }
    local closeBorder, closeText = self:cell(
        1550, FOOTER_Y, 190, FOOTER_H, o.colors.row, T("close"), 64, FOOTER_FONT)
    state.editorCloseRect = { x = 1550, y = FOOTER_Y, w = 190, h = FOOTER_H }
    self.root = oldRoot

    if type(o.buildInstructionsPopup) == "function" then o.buildInstructionsPopup(self.root) end
    if state.instructionsPopup ~= nil then
        state.editorInstructionsCloseRect = state.instructionsPopup.closeRect
    end
    state.editorInstructionsOpen = false

    for _, widget in ipairs(self.rowWidgets or {}) do o.setVisible(widget, true) end
    for _, widget in ipairs(state.editorPickerWidgets or {}) do
        o.setVisible(widget, false)
    end
    self.complete = true
    self.phase = "done"
    self.completedUnits = self.totalUnits
    self:updateProgress()
    o.log("Incremental 36-slot / three-wheel editor and dynamic party picker completed", true)
end

function Builder:step(maxUnits)
    if not self.started or self.complete then return false end
    maxUnits = math.max(1, math.floor(tonumber(maxUnits) or 1))
    local worked = false
    for _ = 1, maxUnits do
        if self.phase == "rows" then
            if self.rowIndex <= TOTAL_SLOTS then
                self:buildRow(self.rowIndex)
                self.rowIndex = self.rowIndex + 1
                self.completedUnits = self.completedUnits + 1
                worked = true
            else
                self:beginPicker()
                self.phase = "picker"
            end
        elseif self.phase == "picker" then
            if self.picker[self.groupIndex] == nil then
                self:finish()
                worked = true
                break
            end
            if self:buildPickerUnit() then
                self.completedUnits = self.completedUnits + 1
                worked = true
            else
                self:finish()
                worked = true
                break
            end
        else
            break
        end
    end
    self:updateProgress()
    return worked
end

return Builder
