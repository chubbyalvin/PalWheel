
local Builder = {}
Builder.__index = Builder

local PAGE_SIZE = 12
local TOTAL_SLOTS = 36

local function safe(callback)
    return pcall(callback)
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
        picker = nil,
        totalUnits = 69,
        completedUnits = 0,
        editorRoot = nil,
    }, Builder)
end

function Builder:cell(x, y, width, height, color, textValue, textInset, fontSize)
    local o, root = self.o, self.root
    local border = o.construct("/Script/UMG.Border", o.state.tree)
    local slot = border and o.addToCanvas(root, border) or nil
    if slot ~= nil then
        o.place(slot, x, y, width, height)
        o.setBorderColor(border, color)
        safe(function() border:SetVisibility(o.hitTestInvisible) end)
    end
    local inset = textInset or 10
    local text = o.createText(o.state.tree, root, textValue or "", x + inset, y + 7,
        math.max(10, width - inset * 2), math.max(20, height - 10), fontSize)
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

function Builder:updateProgress()
    if self.progressText == nil then return end
    if self.complete then
        self.o.setVisible(self.progressText, false)
        return
    end
    local percent = math.floor(self.completedUnits / self.totalUnits * 100)
    self.o.setText(self.progressText, "Preparing editor  " .. tostring(percent) .. "%")
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

    o.createText(state.tree, editorPanel, "PALWHEEL ASSIGNMENTS", 180, 108, 760, 42, nil, 0)
    local settingsKey = tostring(o.cfg("settingsKey") or "settings key")
    local displayName = o.cfg("displayName", nil)
    if type(displayName) == "function" then settingsKey = displayName(settingsKey) end
    o.createText(state.tree, editorPanel,
        "Click an assigned-function cell to choose directly.  "
            .. settingsKey .. " closes the editor.",
        180, 148, 1200, 32, 14, 0)

    -- Keep the settings row compact so the multiplayer note and shortcut reset
    -- control can remain visible together at common 16:9 resolutions.
    o.createText(state.tree, editorPanel, "WHEELS", 180, 195, 100, 30, 15)
    local wheelCountBorder
    wheelCountBorder, state.editorWheelCountText = self:cell(
        280, 188, 120, 42, o.colors.button, "", 14, 15)
    state.editorWheelCountDropdownRect = { x = 280, y = 188, w = 120, h = 42 }
    o.updateWheelCountText()

    o.createText(state.tree, editorPanel, "WHEEL SKIN", 445, 195, 125, 30, 15)
    local skinBorder
    skinBorder, state.editorSkinText = self:cell(
        570, 188, 230, 42, o.colors.button, "", 14, 15)
    state.editorSkinDropdownRect = { x = 570, y = 188, w = 230, h = 42 }
    o.updateSkinText()

    o.createText(state.tree, editorPanel, "SLOW MOTION", 835, 195, 130, 30, 15)
    local slowMotionBorder
    slowMotionBorder, state.editorSlowMotionText = self:cell(
        975, 188, 105, 42, o.colors.button, "", 14, 16)
    state.editorSlowMotionRect = { x = 975, y = 188, w = 105, h = 42 }
    o.updateSlowMotionText()
    o.createText(state.tree, editorPanel,
        "Always disabled in multiplayer.",
        1095, 195, 220, 24, 10)

    local resetBorder, resetText = self:cell(
        1330, 188, 240, 42, o.colors.button, "RESET SHORTCUTS", 14, 14)
    state.editorResetShortcutsRect = { x = 1330, y = 188, w = 240, h = 42 }
    state.editorResetShortcutsText = resetText

    local columnX = { 180, 700, 1220 }
    local tableW, slotW, gap = 500, 66, 4
    local assignmentW = tableW - slotW - gap
    state.editorCountTexts = {}
    state.editorCountDropdownRects = {}

    for page = 1, 3 do
        local x = columnX[page]
        self:cell(x, 270, tableW, 42, o.colors.button,
            "WHEEL " .. (o.wheelRoman and o.wheelRoman(page) or tostring(page)),
            14, 17)

        local countX = x + tableW - 142
        local _, countText = self:cell(
            countX, 275, 132, 32, o.colors.row, "", 10, 13)
        state.editorCountTexts[page] = countText
        state.editorCountDropdownRects[page] = {
            x = countX, y = 275, w = 132, h = 32
        }
        o.updateCountText(page)

        self:cell(x, 315, slotW, 34, o.colors.row, "SLOT", 12, 13)
        self:cell(x + slotW + gap, 315, assignmentW, 34, o.colors.row,
            "ASSIGNED FUNCTION", 12, 13)
    end

    self.progressText = o.createText(state.tree, editorPanel,
        "Preparing editor  0%", 655, 952, 610, 28, 14)
    o.setVisible(editorPanel, false)
    self.started = true
    self.phase = "rows"
    self:updateProgress()
    o.log("Incremental F7 editor frame prepared", true)
    return true
end

function Builder:buildRow(slotIndex)
    local o, state = self.o, self.o.state
    local page = math.floor((slotIndex - 1) / PAGE_SIZE) + 1
    local localSlot = ((slotIndex - 1) % PAGE_SIZE) + 1
    local columnX = { 180, 700, 1220 }
    local x = columnX[page]
    local y = 353 + (localSlot - 1) * 46
    local neutral = localSlot % 2 == 0 and o.colors.rowAlt or o.colors.row
    local slotBorder, slotText = self:cell(x, y, 66, 43, neutral,
        string.format("%02d", localSlot), 18, 14)
    local assignmentX = x + 70
    local assignmentBorder, assignmentText = self:cell(
        assignmentX, y, 430, 43, o.colors.empty, "", 12, 14)
    state.editorRows[slotIndex] = {
        slotBorder = slotBorder,
        slotText = slotText,
        assignmentBorder = assignmentBorder,
        assignmentText = assignmentText,
        rect = { x = assignmentX, y = y, w = 430, h = 43 },
    }
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
        o.setVisible(pickerLayer, false)
        self.editorRoot = self.root
        self.root = pickerLayer
        state.editorPickerLayer = pickerLayer
        state.editorPickerChildrenInitialized = false
    end
    local pickerX, pickerY, pickerW, pickerH = 205, 188, 1510, 690
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
    end
    state.editorPickerTitle = o.createText(state.tree, self.root,
        "CHOOSE ASSIGNED FUNCTION", pickerX + 38, pickerY + 22,
        pickerW - 76, 42, 18)
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = panel
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = state.editorPickerTitle

    self.picker = {
        { title = "WEAPONS", x = 225, width = 170,
            ids = { "weapon1", "weapon2", "weapon3", "weapon4", "weapon5", "weapon6" } },
        { title = "SPHERES", x = 574, width = 220,
            ids = { "sphere_pal", "sphere_mega", "sphere_giga", "sphere_hyper",
                "sphere_ultra", "sphere_legendary", "sphere_ultimate",
                "sphere_exotic", "sphere_sol", "sphere_ancient" } },
        { title = "EMOTES", x = 806, width = 180,
            ids = { "emote_0", "emote_1", "emote_2", "emote_3", "emote_4",
                "emote_5", "emote_6", "emote_7", "emote_8" } },
        { title = "PALWHEEL", x = 998, width = 180, ids = { "map", "mercy", "empty" } },
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
            o.place(slot, group.x, 276, group.width, 36)
            o.setBorderColor(border, o.colors.button)
            safe(function() border:SetVisibility(o.hitTestInvisible) end)
        end
        local text = o.createText(state.tree, self.root, group.title,
            group.x + 12, 282, group.width - 24, 26, 14)
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
        local y = 326 + (self.groupRow - 1) * 48
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
    local partyX, partyW = 407, 155
    local partyHeaderBorder, partyHeaderText = self:cell(
        partyX, 276, partyW, 36, o.colors.button, "PARTY", 12, 14)
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
        state.tree, self.root, "1/1", partyX + 52, 815, partyW - 104, 24, 11)
    for _, widget in ipairs({
        partyPrevBorder, partyPrevText, partyNextBorder, partyNextText,
        state.editorPartyPageText
    }) do
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = widget
        o.setVisible(widget, false)
    end

    state.editorShortcutWidgets = {}
    state.editorShortcutRects = {}
    state.editorShortcutRowIds = {}
    local shortcutX, shortcutW = 1190, 490
    local shortcutHeaderBorder, shortcutHeaderText = self:cell(
        shortcutX, 276, shortcutW, 36, o.colors.button, "CUSTOM SHORTCUTS", 12, 14)
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = shortcutHeaderBorder
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = shortcutHeaderText
    o.setVisible(shortcutHeaderBorder, false)
    o.setVisible(shortcutHeaderText, false)
    for row = 1, 10 do
        local y = 326 + (row - 1) * 48
        local border, label = self:cell(shortcutX, y, shortcutW, 42, o.colors.menu, "", 10, 13)
        state.editorShortcutWidgets[row] = { border = border, text = label }
        state.editorShortcutRects[row] = { x = shortcutX, y = y, w = shortcutW, h = 42 }
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = border
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = label
        o.setVisible(border, false)
        o.setVisible(label, false)
    end
    local prevBorder, prevText = self:cell(shortcutX, 810, 105, 34, o.colors.button, "< PREV", 12, 12)
    local nextBorder, nextText = self:cell(shortcutX + shortcutW - 105, 810, 105, 34, o.colors.button, "NEXT >", 12, 12)
    state.editorShortcutPrevRect = { x = shortcutX, y = 810, w = 105, h = 34 }
    state.editorShortcutNextRect = { x = shortcutX + shortcutW - 105, y = 810, w = 105, h = 34 }
    state.editorShortcutPrevWidgets = { prevBorder, prevText }
    state.editorShortcutNextWidgets = { nextBorder, nextText }
    state.editorShortcutPageText = o.createText(state.tree, self.root, "Page 1 / 1",
        shortcutX + 120, 815, shortcutW - 240, 24, 12)
    for _, widget in ipairs({ prevBorder, prevText, nextBorder, nextText, state.editorShortcutPageText }) do
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = widget
        o.setVisible(widget, false)
    end

    local confirmPanel = o.construct("/Script/UMG.Border", state.tree)
    local confirmSlot = confirmPanel and o.addToCanvas(self.root, confirmPanel) or nil
    if confirmSlot ~= nil then
        o.place(confirmSlot, 625, 365, 670, 260)
        o.setBorderColor(confirmPanel, o.colors.panel)
    end
    local confirmOutline = self:outline(625, 365, 670, 260, 2)
    local confirmTitle = o.createText(state.tree, self.root, "RESET CUSTOM SHORTCUTS?",
        665, 395, 590, 36, 18)
    local confirmBody = o.createText(state.tree, self.root,
        "Restore Character, Inventory, Party, Technology, and Build to their default shortcuts?\nCustom shortcut definitions will be removed. Affected wheel slots become Unassigned.",
        665, 445, 590, 72, 13)
    local yesBorder, yesText = self:cell(760, 545, 180, 44, o.colors.button, "RESET", 50, 14)
    local noBorder, noText = self:cell(980, 545, 180, 44, o.colors.row, "CANCEL", 48, 14)
    state.editorResetConfirmWidgets = { confirmPanel, confirmTitle, confirmBody, yesBorder, yesText, noBorder, noText }
    for _, widget in ipairs(confirmOutline) do
        state.editorResetConfirmWidgets[#state.editorResetConfirmWidgets + 1] = widget
    end
    state.editorResetConfirmYesRect = { x = 760, y = 545, w = 180, h = 44 }
    state.editorResetConfirmNoRect = { x = 980, y = 545, w = 180, h = 44 }
    for _, widget in ipairs(state.editorResetConfirmWidgets) do o.setVisible(widget, false) end

    local help = o.createText(state.tree, self.root,
        "Right-click or click outside the panel to cancel",
        710, 832, 500, 28, 12)
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = help
    o.setVisible(help, false)
    if self.editorRoot ~= nil then self.root = self.editorRoot end
    local displayName = o.cfg("displayName", nil)
    local openKeyboard = tostring(o.cfg("openKey") or "")
    local pageKeyboard = tostring(o.cfg("keyboardPageButton") or "")
    local openController = tostring(o.cfg("controllerOpenButton") or "")
    local pageController = tostring(o.cfg("controllerPageButton") or "")
    if type(displayName) == "function" then
        openKeyboard = displayName(openKeyboard)
        pageKeyboard = displayName(pageKeyboard)
        openController = displayName(openController)
        pageController = displayName(pageController)
    end
    o.createText(state.tree, self.root,
        "Open Wheel: " .. openKeyboard .. " / " .. openController
            .. "    |    Toggle Page: " .. pageKeyboard .. " / " .. pageController,
        180, 927, 1200, 24, 12, 0)
    o.createText(state.tree, self.root,
        "Assignments save automatically. Edit Saved\\shortcuts.tsv to add or disable shortcut actions.",
        180, 951, 1000, 22, 11, 0)
	o.createText(state.tree, self.root,
		"PalWheel v" .. tostring(o.cfg("version", "1.0")),
		1570, 946, 170, 26, 14)
	o.createText(state.tree, self.root,
		"by CHUBBYALVIN",
		1570, 970, 170, 22, 11)

    state.editorCountDropdownWidgets = { {}, {}, {} }
    state.editorCountOptionRects = { {}, {}, {} }
    local columnX = { 180, 700, 1220 }
    for page = 1, 3 do
        local x = columnX[page] + 358
        for value = 4, 12 do
            local y = 309 + (value - 4) * 38
            local border, label = self:cell(x, y, 132, 36, o.colors.row,
                tostring(value) .. " slots", 10, 12)
            state.editorCountDropdownWidgets[page][#state.editorCountDropdownWidgets[page] + 1] = border
            state.editorCountDropdownWidgets[page][#state.editorCountDropdownWidgets[page] + 1] = label
            state.editorCountOptionRects[page][value] = {
                x = x, y = y, w = 132, h = 36
            }
            o.setVisible(border, false)
            o.setVisible(label, false)
        end
    end

    state.editorWheelCountDropdownWidgets = {}
    state.editorWheelCountOptionRects = {}
    for value = 1, 3 do
        local y = 232 + (value - 1) * 42
        local border, label = self:cell(360, y, 120, 40, o.colors.row,
            tostring(value) .. (value == 1 and " wheel" or " wheels"), 12, 13)
        state.editorWheelCountDropdownWidgets[#state.editorWheelCountDropdownWidgets + 1] = border
        state.editorWheelCountDropdownWidgets[#state.editorWheelCountDropdownWidgets + 1] = label
        state.editorWheelCountOptionRects[value] = { x = 360, y = y, w = 120, h = 40 }
        o.setVisible(border, false)
        o.setVisible(label, false)
    end

    state.editorSkinDropdownWidgets = {}
    state.editorSkinOptionRects = {}
    local skins = self.o.wheelSkins or { "wheel_01.png", "wheel_02.png" }
    for index, filename in ipairs(skins) do
        local y = 232 + (index - 1) * 42
        local border, label = self:cell(650, y, 230, 40, o.colors.row,
            filename, 14, 13)
        state.editorSkinDropdownWidgets[#state.editorSkinDropdownWidgets + 1] = border
        state.editorSkinDropdownWidgets[#state.editorSkinDropdownWidgets + 1] = label
        state.editorSkinOptionRects[filename] = { x = 650, y = y, w = 230, h = 40 }
        o.setVisible(border, false)
        o.setVisible(label, false)
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

function Builder:isComplete()
    return self.complete == true
end

return Builder
