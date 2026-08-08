
local Builder = {}
Builder.__index = Builder

local PAGE_SIZE = 12
local TOTAL_SLOTS = 24

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
        totalUnits = 57,
        completedUnits = 0,
    }, Builder)
end

function Builder:cell(x, y, width, height, color, textValue, textInset)
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
        math.max(10, width - inset * 2), math.max(20, height - 10))
    return border, text
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

    o.createText(state.tree, editorPanel, "PALWHEEL ASSIGNMENTS", 170, 108, 760, 42)
    local settingsKey = tostring(o.cfg("settingsKey") or "settings key")
    local displayName = o.cfg("displayName", nil)
    if type(displayName) == "function" then settingsKey = displayName(settingsKey) end
    o.createText(state.tree, editorPanel,
        "Click an assigned-function cell to choose directly.  "
            .. settingsKey .. " closes the editor.",
        190, 148, 1200, 32)

    o.createText(state.tree, editorPanel, "SLOTS PER WHEEL", 500, 195, 210, 30, 16)
    local countBorder
    countBorder, state.editorCountText = self:cell(
        700, 188, 190, 42, o.colors.button, "", 18)
    state.editorCountDropdownRect = { x = 700, y = 188, w = 190, h = 42 }
    o.updateCountText()

    o.createText(state.tree, editorPanel, "WHEEL SKIN", 980, 195, 150, 30, 16)
    local skinBorder
    skinBorder, state.editorSkinText = self:cell(
        1120, 188, 250, 42, o.colors.button, "", 18)
    state.editorSkinDropdownRect = { x = 1120, y = 188, w = 250, h = 42 }
    o.updateSkinText()

    for page = 1, 2 do
        local x = page == 1 and 190 or 985
        self:cell(x, 270, 745, 42, o.colors.button,
            page == 1 and "WHEEL I" or "WHEEL II", 18)
        self:cell(x, 315, 105, 34, o.colors.row, "SLOT", 18)
        self:cell(x + 109, 315, 636, 34, o.colors.row,
            "ASSIGNED FUNCTION", 18)
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
    local x = page == 1 and 190 or 985
    local y = 353 + (localSlot - 1) * 46
    local neutral = localSlot % 2 == 0 and o.colors.rowAlt or o.colors.row
    local slotBorder, slotText = self:cell(x, y, 105, 43, neutral,
        string.format("%02d", localSlot), 30)
    local assignmentX = x + 109
    local assignmentBorder, assignmentText = self:cell(
        assignmentX, y, 636, 43, o.colors.empty, "", 18)
    state.editorRows[slotIndex] = {
        slotBorder = slotBorder,
        slotText = slotText,
        assignmentBorder = assignmentBorder,
        assignmentText = assignmentText,
        rect = { x = assignmentX, y = y, w = 636, h = 43 },
    }
    o.updateRow(slotIndex)
end

function Builder:beginPicker()
    local o, state = self.o, self.o.state
    local pickerX, pickerY, pickerW, pickerH = 205, 188, 1510, 690
    local panel = o.construct("/Script/UMG.Border", state.tree)
    local slot = panel and o.addToCanvas(self.root, panel) or nil
    if slot ~= nil then
        o.place(slot, pickerX, pickerY, pickerW, pickerH)
        o.setBorderColor(panel, o.colors.panel)
        state.editorPickerPanel = panel
    end
    state.editorPickerTitle = o.createText(state.tree, self.root,
        "CHOOSE ASSIGNED FUNCTION", pickerX + 38, pickerY + 22,
        pickerW - 76, 42)
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = panel
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = state.editorPickerTitle

    self.picker = {
        { title = "WEAPONS", x = 247, width = 195,
            ids = { "weapon1", "weapon2", "weapon3", "weapon4", "weapon5", "weapon6" } },
        { title = "PARTY", x = 458, width = 190,
            ids = { "pal1", "pal2", "pal3", "pal4", "pal5" } },
        { title = "GAME MENUS", x = 664, width = 250,
            ids = { "character", "inventory", "map", "technology", "party", "build" } },
        { title = "SPHERES", x = 930, width = 270,
            ids = { "sphere_pal", "sphere_mega", "sphere_giga", "sphere_hyper",
                "sphere_ultra", "sphere_legendary", "sphere_ultimate",
                "sphere_exotic", "sphere_sol", "sphere_ancient" } },
        { title = "UTILITY", x = 1216, width = 200, ids = { "mercy" } },
        { title = "GENERAL", x = 1432, width = 170, ids = { "empty" } },
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
            group.x + 12, 282, group.width - 24, 26)
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
            group.x + textInset, y + 8, group.width - textInset - 10, 26)
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
    local help = o.createText(state.tree, self.root,
        "Right-click or click outside the panel to cancel",
        710, 832, 500, 28)
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = help
    o.setVisible(help, false)
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
        520, 927, 1000, 24, 12)
    o.createText(state.tree, self.root,
        "Assignments, slot count, and wheel skin save automatically.",
        520, 951, 900, 22, 11)
	o.createText(state.tree, self.root,
		"PalWheel v" .. tostring(o.cfg("version", "1.0")),
		1570, 946, 170, 26, 14)
	o.createText(state.tree, self.root,
		"by CHUBBYALVIN",
		1570, 970, 170, 22, 11)

    state.editorCountDropdownWidgets = {}
    state.editorCountOptionRects = {}
    for value = 4, 12 do
        local y = 232 + (value - 4) * 42
        local border, label = self:cell(700, y, 190, 40, o.colors.row,
            tostring(value) .. " slots", 18)
        state.editorCountDropdownWidgets[#state.editorCountDropdownWidgets + 1] = border
        state.editorCountDropdownWidgets[#state.editorCountDropdownWidgets + 1] = label
        state.editorCountOptionRects[value] = { x = 700, y = y, w = 190, h = 40 }
        o.setVisible(border, false)
        o.setVisible(label, false)
    end

    state.editorSkinDropdownWidgets = {}
    state.editorSkinOptionRects = {}
    local skins = self.o.wheelSkins or { "wheel_01.png", "wheel_02.png" }
    for index, filename in ipairs(skins) do
        local y = 232 + (index - 1) * 42
        local border, label = self:cell(1120, y, 250, 40, o.colors.row,
            filename, 18)
        state.editorSkinDropdownWidgets[#state.editorSkinDropdownWidgets + 1] = border
        state.editorSkinDropdownWidgets[#state.editorSkinDropdownWidgets + 1] = label
        state.editorSkinOptionRects[filename] = { x = 1120, y = y, w = 250, h = 40 }
        o.setVisible(border, false)
        o.setVisible(label, false)
    end
    self.complete = true
    self.phase = "done"
    self.completedUnits = self.totalUnits
    self:updateProgress()
    o.log("Incremental 24-slot editor and grouped picker completed", true)
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
