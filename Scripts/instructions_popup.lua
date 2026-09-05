local Popup = {}
Popup.__index = Popup

local L = require("localization")
local TextLayout = require("text_layout")
local function T(key, variables) return L.get(key, variables) end

local ACTION_COLOR = { R = 0.961, G = 0.631, B = 0.102, A = 1.0 }
local BODY_COLOR = { R = 0.98, G = 0.99, B = 1.00, A = 1.0 }
local MUTED_COLOR = { R = 0.74, G = 0.80, B = 0.88, A = 1.0 }
local BRAND_WHITE = { R = 1.00, G = 1.00, B = 1.00, A = 1.0 }
local BRAND_GOLD = { R = 0.961, G = 0.631, B = 0.102, A = 1.0 }
local BRAND_FONT_PATH = "/Game/Pal/Font/Anton-Regular_Font.Anton-Regular_Font"
local BRAND_FONT_PACKAGE = "/Game/Pal/Font/Anton-Regular_Font"
local brandFontObject = nil
local brandFontAttempted = false

local function setTextColor(widget, color)
    if widget == nil or color == nil then return end
    local ok = pcall(function()
        widget:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
    end)
    if not ok then pcall(function() widget:SetColorAndOpacity(color) end) end
end

local function getBrandFont()
    if brandFontAttempted then return brandFontObject end
    brandFontAttempted = true
    if type(StaticFindObject) == "function" then
        local ok, object = pcall(StaticFindObject, BRAND_FONT_PATH)
        if ok and object ~= nil then
            brandFontObject = object
            return brandFontObject
        end
    end
    if type(LoadAsset) == "function" then
        pcall(function() LoadAsset(BRAND_FONT_PACKAGE) end)
        pcall(function() LoadAsset(BRAND_FONT_PATH) end)
    end
    if type(StaticFindObject) == "function" then
        local ok, object = pcall(StaticFindObject, BRAND_FONT_PATH)
        if ok and object ~= nil then brandFontObject = object end
    end
    return brandFontObject
end

local function setTypeface(widget, name)
    if widget == nil or name == nil then return end
    pcall(function()
        local font = widget.Font
        local okName, faceName = pcall(function() return FName(name) end)
        font.TypefaceFontName = (okName and faceName ~= nil) and faceName or name
        widget:SetFont(font)
    end)
end

local function styleBrandText(widget, color, fontSize)
    if widget == nil then return end
    pcall(function()
        local font = widget.Font
        if tonumber(fontSize) ~= nil then font.Size = math.floor(tonumber(fontSize)) end
        local fontObject = getBrandFont()
        if fontObject ~= nil then font.FontObject = fontObject end
        local okName, regularName = pcall(function() return FName("Regular") end)
        font.TypefaceFontName = (okName and regularName ~= nil) and regularName or "Regular"
        widget:SetFont(font)
    end)
    setTextColor(widget, color)
end

local function binding(controller, keyboard)
    return { kind = "dynamic", controller = controller, keyboard = keyboard }
end

local function textBinding(fallbackKey)
    return { kind = "text", fallbackKey = fallbackKey }
end

local function literalBinding(value)
    return { kind = "literal", value = tostring(value or "") }
end

local function fixedBinding(layout)
    return { kind = "fixed", layout = layout }
end

local ROWS = {
    general = {
        
        
        { "instructions.general.openWheel.action", "instructions.general.openWheel.description",
            binding("controllerOpenButton", "openKey") },
        { "instructions.general.nextWheel.action", "instructions.general.nextWheel.description",
            binding("controllerNextWheelButton", "keyboardNextWheelButton") },
        { "instructions.general.sphereWheel.action", "instructions.general.sphereWheel.description",
            textBinding("instructions.binding.sphereThenOpen") },
        { "instructions.general.assign.action", "instructions.general.assign.description" },
        { "saveAndApply", "instructions.general.save.description",
            fixedBinding("saveButton") },
    },
    controls = {
        { "instructions.general.openWheel.action", "instructions.general.openWheel.description",
            binding("controllerOpenButton", "openKey") },
        { "instructions.controls.mode.action", "instructions.controls.mode.description" },
        { "instructions.general.nextWheel.action", "instructions.general.nextWheel.description",
            binding("controllerNextWheelButton", "keyboardNextWheelButton") },
        { "instructions.general.sphereWheel.action", "instructions.general.sphereWheel.description",
            textBinding("instructions.binding.sphereThenOpen") },
        { "instructions.general.aux.action", "instructions.general.aux.description",
            fixedBinding("auxButtons") },
        { "instructions.general.zoom.action", "instructions.general.zoom.description",
            fixedBinding("triggers") },
        { "instructions.general.menu.action", "instructions.general.menu.description",
            binding("controllerPalWheelMenuButton", "settingsKey") },
        { "saveAndApply", "instructions.controls.save.description",
            fixedBinding("saveButton") },
    },
    shortcuts = {
        { "instructions.shortcuts.add.action", "instructions.shortcuts.add.description",
            textBinding("addShortcut") },
        { "instructions.shortcuts.active.action", "instructions.shortcuts.active.description",
            textBinding("active") },
        { "instructions.shortcuts.label.action", "instructions.shortcuts.label.description" },
        { "instructions.shortcuts.id.action", "instructions.shortcuts.id.description" },
        { "instructions.shortcuts.modifier.action", "instructions.shortcuts.modifier.description",
            literalBinding("CTRL  /  SHIFT  /  ALT") },
        { "instructions.shortcuts.duplicate.action", "instructions.shortcuts.duplicate.description",
            textBinding("copy") },
        { "instructions.shortcuts.delete.action", "instructions.shortcuts.delete.description",
            textBinding("delete") },
        { "instructions.shortcuts.reload.action", "instructions.shortcuts.reload.description",
            textBinding("reloadFile") },
        { "instructions.shortcuts.save.action", "instructions.shortcuts.save.description",
            fixedBinding("saveButton") },
        { "instructions.shortcuts.restore.action", "instructions.shortcuts.restore.description",
            textBinding("restorePackaged") },
    },
}

local FIXED_LAYOUTS = {
    
    
    saveButton = {
        glyphs = {
            { device = "controller", key = "Gamepad_FaceButton_Top", x = 124 },
        },
        labels = {
            { text = "/", x = 146, w = 24 },
            { key = "saveAndApply", x = 180, w = 136, j = 0 },
        },
    },
    triggers = {
        glyphs = {
            { device = "controller", key = "Gamepad_LeftTrigger", x = 124 },
            { device = "controller", key = "Gamepad_RightTrigger", x = 192 },
        },
        labels = { { text = "/", x = 146, w = 24 } },
    },
    auxButtons = {
        glyphs = {
            { device = "controller", key = "Gamepad_DPad_Up", x = 30 },
            { device = "controller", key = "Gamepad_DPad_Right", x = 60 },
            { device = "controller", key = "Gamepad_DPad_Down", x = 90 },
            { device = "controller", key = "Gamepad_DPad_Left", x = 120 },
            { device = "controller", key = "Gamepad_FaceButton_Bottom", x = 196 },
            { device = "controller", key = "Gamepad_FaceButton_Right", x = 226 },
            { device = "controller", key = "Gamepad_FaceButton_Left", x = 256 },
            { device = "controller", key = "Gamepad_FaceButton_Top", x = 286 },
        },
        labels = { { text = "/", x = 146, w = 24 } },
    },
}

local KEYBOARD_FALLBACKS = {
    LeftMouseButton = "instructions.binding.leftClick",
    RightMouseButton = "instructions.binding.rightClick",
    MiddleMouseButton = "instructions.binding.middleClick",
}

function Popup.new(options)
    return setmetatable({
        o = options or {}, built = false, open = false, activeContext = "general",
        commonWidgets = {}, contextWidgets = {}, bindingCells = {}, closeRect = nil,
    }, Popup)
end

function Popup:track(group, widget)
    if widget ~= nil then group[#group + 1] = widget end
    return widget
end

function Popup:setVisible(widget, visible)
    if widget ~= nil then self.o.setVisible(widget, visible == true) end
end

function Popup:setGroupVisible(group, visible)
    for _, widget in ipairs(group or {}) do self:setVisible(widget, visible) end
end

function Popup:makeBorder(root, x, y, w, h, color, group)
    local border = self.o.construct("/Script/UMG.Border", self.o.state.tree)
    local slot = border and self.o.addToCanvas(root, border) or nil
    if slot ~= nil then
        self.o.place(slot, x, y, w, h)
        self.o.setBorderColor(border, color)
        pcall(function() border:SetVisibility(self.o.hitTestInvisible) end)
        pcall(function() slot:SetZOrder(70) end)
    end
    return self:track(group, border)
end

function Popup:makeText(root, value, x, y, w, h, size, justification, group, color, wrap)
    if wrap ~= true then
        size = TextLayout.fitFontSize(value, size, w, h, 8)
    end
    local widget = self.o.createText(self.o.state.tree, root, value, x, y, w, h,
        size, justification or 0)
    if widget ~= nil then
        if wrap == true then
            pcall(function() widget:SetAutoWrapText(true) end)
            pcall(function() widget:SetWrapTextAt(math.max(40, w - 8)) end)
        end
        setTextColor(widget, color or BODY_COLOR)
        pcall(function() if widget.Slot ~= nil then widget.Slot:SetZOrder(71) end end)
    end
    return self:track(group, widget)
end

function Popup:makeAuthorSignature(root, x, y, w, h, size, group)
    local box = self.o.construct("/Script/UMG.HorizontalBox", self.o.state.tree)
    local slot = box and self.o.addToCanvas(root, box) or nil
    if slot == nil then return nil end
    self.o.place(slot, x, y, w, h)
    pcall(function() box:SetVisibility(self.o.hitTestInvisible) end)
    pcall(function() slot:SetZOrder(72) end)

    local function addPiece(value, color)
        local text = self.o.construct("/Script/UMG.TextBlock", self.o.state.tree)
        if text == nil then return false end
        local ok, childSlot = pcall(function() return box:AddChildToHorizontalBox(text) end)
        if not ok or childSlot == nil then
            ok, childSlot = pcall(function() return box:AddChild(text) end)
        end
        if not ok or childSlot == nil then return false end
        self.o.setText(text, value)
        styleBrandText(text, color, size)
        pcall(function() text:SetAutoWrapText(false) end)
        pcall(function() text:SetVisibility(self.o.hitTestInvisible) end)
        return true
    end

    if not addPiece("- ", BRAND_WHITE)
        or not addPiece("Chubby", BRAND_WHITE)
        or not addPiece("Alvin", BRAND_GOLD) then
        pcall(function() box:RemoveFromParent() end)
        return nil
    end
    return self:track(group, box)
end

function Popup:makeGlyphPlaceholder(root, centerX, centerY, group)
    local image = self.o.construct("/Script/UMG.Image", self.o.state.tree)
    local slot = image and self.o.addToCanvas(root, image) or nil
    if slot == nil then return nil end
    self.o.place(slot, centerX - 14, centerY - 14, 28, 28)
    pcall(function() slot:SetZOrder(72) end)
    self.o.setVisible(image, false)
    return self:track(group, image)
end

function Popup:controllerFamily()
    return type(self.o.detectControllerGlyphFamily) == "function"
        and self.o.detectControllerGlyphFamily() or "xbox"
end

function Popup:glyphTexture(key, device, family)
    if type(self.o.glyphTextureForKey) ~= "function" then return nil end
    if device == "keyboard" then return self.o.glyphTextureForKey(key, "keyboard") end
    return self.o.glyphTextureForKey(key, family or self:controllerFamily())
end

function Popup:glyphLabel(key, device, family)
    if device == "keyboard" then
        local fallbackKey = KEYBOARD_FALLBACKS[tostring(key or "")]
        if fallbackKey ~= nil then return T(fallbackKey) end
        return self:displayName(key)
    end
    if tostring(key or "") == "Gamepad_DPad_2D" or tostring(key or "") == "Gamepad_DPad" then
        return T("instructions.binding.dpad")
    end
    if type(self.o.glyphLabelForKey) == "function" then
        local ok, value = pcall(self.o.glyphLabelForKey, key, family or self:controllerFamily())
        if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    end
    return self:displayName(key)
end

function Popup:fixedFallback(layoutName, family)
    local layout = FIXED_LAYOUTS[layoutName]
    if layout == nil then return "" end
    if layoutName == "saveButton" then
        return self:glyphLabel("Gamepad_FaceButton_Top", "controller", family)
            .. "  /  " .. T("saveAndApply")
    end
    if layoutName == "auxButtons" then
        return self:glyphLabel("Gamepad_DPad_2D", "controller", family)
            .. "  /  "
            .. self:glyphLabel("Gamepad_FaceButton_Bottom", "controller", family) .. " "
            .. self:glyphLabel("Gamepad_FaceButton_Right", "controller", family) .. " "
            .. self:glyphLabel("Gamepad_FaceButton_Left", "controller", family) .. " "
            .. self:glyphLabel("Gamepad_FaceButton_Top", "controller", family)
    end
    local parts = {}
    for index, item in ipairs(layout.glyphs or {}) do
        if index > 1 then parts[#parts + 1] = "  /  " end
        parts[#parts + 1] = self:glyphLabel(item.key, item.device, family)
    end
    return table.concat(parts)
end

function Popup:buildDynamicCell(root, rowY, rowH, widgets, spec)
    local cell = { spec = spec, glyphs = {}, labels = {} }
    local textY = rowY + math.max(0, math.floor((rowH - 24) * 0.5))
    cell.text = self:makeText(root, "", 547, textY, 316, 24,
        10, 1, widgets, BODY_COLOR, false)
    
    cell.controllerFallback = self:makeText(root, "", 547, textY, 134,
        24, 10, 2, widgets, BODY_COLOR, false)
    cell.slash = self:makeText(root, "/", 693, textY, 24,
        24, 11, 1, widgets, BODY_COLOR, false)
    cell.keyboardFallback = self:makeText(root, "", 729, textY, 134,
        24, 10, 0, widgets, BODY_COLOR, false)
    local centerY = rowY + (rowH - 3) * 0.5
    cell.controllerIcon = self:makeGlyphPlaceholder(root, 671, centerY, widgets)
    cell.keyboardIcon = self:makeGlyphPlaceholder(root, 739, centerY, widgets)
    return cell
end

function Popup:buildFixedCell(root, rowY, rowH, widgets, spec)
    local cell = { spec = spec, glyphs = {}, labels = {} }
    local textY = rowY + math.max(0, math.floor((rowH - 24) * 0.5))
    cell.text = self:makeText(root, "", 547, textY, 316, 24,
        10, 1, widgets, BODY_COLOR, false)
    local layout = FIXED_LAYOUTS[spec.layout]
    if layout == nil then return cell end
    local centerY = rowY + (rowH - 3) * 0.5
    for _, item in ipairs(layout.glyphs or {}) do
        local entry = {
            widget = self:makeGlyphPlaceholder(root, 547 + item.x, centerY, widgets),
            key = item.key, device = item.device,
        }
        cell.glyphs[#cell.glyphs + 1] = entry
    end
    for _, item in ipairs(layout.labels or {}) do
        local value = item.key ~= nil and T(item.key) or tostring(item.text or "")
        local widget = self:makeText(root, value, 547 + item.x, textY,
            item.w or 60, 24, 10, item.j or 1, widgets, BODY_COLOR, false)
        cell.labels[#cell.labels + 1] = widget
    end
    return cell
end

function Popup:build(root)
    if self.built then return true end
    local o = self.o
    local x, y, w, h = 180, 120, 1560, 820
    self:makeBorder(root, x, y, w, h, o.colors.panel, self.commonWidgets)
    self:makeBorder(root, x, y, w, 2, o.colors.button, self.commonWidgets)
    self:makeBorder(root, x, y + h - 2, w, 2, o.colors.button, self.commonWidgets)
    self:makeBorder(root, x, y, 2, h, o.colors.button, self.commonWidgets)
    self:makeBorder(root, x + w - 2, y, 2, h, o.colors.button, self.commonWidgets)

    self.titleText = self:makeText(root, "", 230, 148, 1460, 38, 21, 0,
        self.commonWidgets, BODY_COLOR, false)
    self:makeBorder(root, 230, 198, 1460, 1, o.colors.button, self.commonWidgets)

    local headers = {
        { key = "instructions.columns.action", x = 250, w = 270, j = 0 },
        { key = "instructions.columns.binding", x = 535, w = 340, j = 1 },
        { key = "instructions.columns.description", x = 890, w = 770, j = 0 },
    }
    for _, header in ipairs(headers) do
        self:makeBorder(root, header.x, 215, header.w, 34, o.colors.button, self.commonWidgets)
        self:makeText(root, T(header.key), header.x + 12,
            220, header.w - 24, 24, 13, header.j, self.commonWidgets, BODY_COLOR, false)
    end

    for context, rows in pairs(ROWS) do
        local widgets, cells = {}, {}
        self.contextWidgets[context] = widgets
        self.bindingCells[context] = cells
        local rowH = context == "shortcuts" and 40 or 52
        local rowStartY = 258
        for index, row in ipairs(rows) do
            local rowY = rowStartY + (index - 1) * rowH
            local alternate = index % 2 == 0 and o.colors.rowAlt or o.colors.row
            self:makeBorder(root, 250, rowY, 270, rowH - 3, alternate, widgets)
            self:makeBorder(root, 535, rowY, 340, rowH - 3, alternate, widgets)
            self:makeBorder(root, 890, rowY, 770, rowH - 3, alternate, widgets)
            self:makeText(root, T(row[1]), 262, rowY + 5, 246, rowH - 10,
                context == "shortcuts" and 10 or 12, 0, widgets, ACTION_COLOR, true)
            self:makeText(root, T(row[2]), 902, rowY + 5, 746, rowH - 10,
                context == "shortcuts" and 9 or 11, 0, widgets, BODY_COLOR, true)
            local spec = row[3] or {}
            local cell = nil
            if spec.kind == "dynamic" then
                cell = self:buildDynamicCell(root, rowY, rowH, widgets, spec)
            elseif spec.kind == "fixed" then
                cell = self:buildFixedCell(root, rowY, rowH, widgets, spec)
            elseif (spec.kind == "text" or spec.kind == "literal") and context ~= "general" then
                cell = { spec = spec }
                local bindingTextY = rowY + math.max(0, math.floor((rowH - 24) * 0.5))
                cell.text = self:makeText(root, "", 547, bindingTextY, 316, 24,
                    context == "shortcuts" and 9 or 11, 1, widgets, BODY_COLOR, false)
            else
                cell = { spec = spec }
                cell.text = self:makeText(root, "", 547, rowY + 5, 316, rowH - 10,
                    context == "shortcuts" and 9 or 11, 1, widgets, BODY_COLOR, true)
            end
            cells[index] = cell
        end

        if context == "general" then
            
            local afterRowsY = rowStartY + (#rows * rowH)
            self:makeText(root, T("instructions.general.readmeNote", {
                    path = "Saved\\README.txt"
                }), 262, afterRowsY + 3, 1386, 28, 10, 0, widgets, MUTED_COLOR, true)
            local authorHeadingY = afterRowsY + 36
            local authorHeading = self:makeText(root, T("instructions.general.authorHeader"),
                250, authorHeadingY, 1410, 26, 12, 0, widgets, ACTION_COLOR, false)
            setTypeface(authorHeading, "Bold")
            self:makeBorder(root, 250, authorHeadingY + 30, 1410, 1, o.colors.button, widgets)
            self:makeText(root, T("instructions.general.authorMessageBody"),
                262, authorHeadingY + 40, 1386, 66, 11, 0, widgets, BODY_COLOR, true)
            self:makeAuthorSignature(root, 262, authorHeadingY + 112, 500, 24, 13, widgets)
        end
    end

    
    local closeBorder = self:makeBorder(root, 1360, 875, 300, 46, o.colors.button, self.commonWidgets)
    self:makeText(root, T("close"), 1372, 883, 276, 28, 14, 1,
        self.commonWidgets, BODY_COLOR, false)
    self.closeRect = { x = 1360, y = 875, w = 300, h = 46 }
    self.built = true
    self:setGroupVisible(self.commonWidgets, false)
    for _, group in pairs(self.contextWidgets) do self:setGroupVisible(group, false) end
    return closeBorder ~= nil
end

function Popup:configValue(field, fallback)
    if field == nil then return nil end
    local editor = self.o.state and self.o.state.bindingEditor or nil
    if editor ~= nil and editor.open == true and type(editor.draft) == "table"
        and editor.draft[field] ~= nil then
        return tostring(editor.draft[field])
    end
    return tostring(self.o.cfg(field, fallback or "") or fallback or "")
end

function Popup:displayName(value)
    local display = self.o.cfg("displayName", nil)
    if type(display) == "function" then
        local ok, result = pcall(display, value)
        if ok and result ~= nil and tostring(result) ~= "" then return tostring(result) end
    end
    return tostring(value or "")
end

function Popup:updateDynamicCell(cell, family)
    local spec = cell.spec or {}
    self.o.setText(cell.text, "")
    local controllerKey = self:configValue(spec.controller)
    local keyboardKey = self:configValue(spec.keyboard)
    self.o.setText(cell.controllerFallback, self:glyphLabel(controllerKey, "controller", family))
    self.o.setText(cell.keyboardFallback, self:glyphLabel(keyboardKey, "keyboard", family))

    local controllerTexture = self:glyphTexture(controllerKey, "controller", family)
    local keyboardTexture = self:glyphTexture(keyboardKey, "keyboard", family)
    local controllerGlyphShown = false
    if cell.controllerIcon ~= nil and controllerTexture ~= nil then
        controllerGlyphShown = pcall(function()
            cell.controllerIcon:SetBrushFromTexture(controllerTexture, false)
        end)
    end
    local keyboardGlyphShown = false
    if cell.keyboardIcon ~= nil and keyboardTexture ~= nil then
        keyboardGlyphShown = pcall(function()
            cell.keyboardIcon:SetBrushFromTexture(keyboardTexture, false)
        end)
    end
    self:setVisible(cell.controllerIcon, controllerGlyphShown)
    self:setVisible(cell.controllerFallback, not controllerGlyphShown)
    self:setVisible(cell.keyboardIcon, keyboardGlyphShown)
    self:setVisible(cell.keyboardFallback, not keyboardGlyphShown)
    self:setVisible(cell.slash, true)
end

function Popup:updateFixedCell(cell, family)
    local layout = FIXED_LAYOUTS[(cell.spec or {}).layout]
    if layout == nil then
        self.o.setText(cell.text, "")
        return
    end
    local allGlyphsShown = #cell.glyphs > 0
    for _, entry in ipairs(cell.glyphs or {}) do
        local texture = self:glyphTexture(entry.key, entry.device, family)
        local shown = false
        if entry.widget ~= nil and texture ~= nil then
            shown = pcall(function() entry.widget:SetBrushFromTexture(texture, false) end)
        end
        entry.ready = shown
        if not shown then allGlyphsShown = false end
    end
    if allGlyphsShown then
        self.o.setText(cell.text, "")
        self:setVisible(cell.text, false)
        for _, entry in ipairs(cell.glyphs or {}) do self:setVisible(entry.widget, true) end
        for _, widget in ipairs(cell.labels or {}) do self:setVisible(widget, true) end
    else
        self.o.setText(cell.text, self:fixedFallback((cell.spec or {}).layout, family))
        self:setVisible(cell.text, true)
        for _, entry in ipairs(cell.glyphs or {}) do self:setVisible(entry.widget, false) end
        for _, widget in ipairs(cell.labels or {}) do self:setVisible(widget, false) end
    end
end

function Popup:updateBindings(context)
    local family = self:controllerFamily()
    for _, cell in ipairs(self.bindingCells[context] or {}) do
        local spec = cell.spec or {}
        if spec.kind == "text" then
            self.o.setText(cell.text, T(spec.fallbackKey))
            self:setVisible(cell.text, true)
        elseif spec.kind == "literal" then
            self.o.setText(cell.text, tostring(spec.value or ""))
            self:setVisible(cell.text, true)
        elseif spec.kind == "dynamic" then
            self:updateDynamicCell(cell, family)
        elseif spec.kind == "fixed" then
            self:updateFixedCell(cell, family)
        else
            self.o.setText(cell.text, "")
        end
    end
end

function Popup:show(context)
    if not self.built then return false end
    context = ROWS[context] ~= nil and context or "general"
    self.activeContext = context
    self.open = true
    local titleKey = context == "shortcuts" and "customShortcuts"
        or ("instructions." .. context .. ".title")
    self.o.setText(self.titleText, T(titleKey))
    self:setGroupVisible(self.commonWidgets, true)
    for name, group in pairs(self.contextWidgets) do
        self:setGroupVisible(group, name == context)
    end
    self:updateBindings(context)
    return true
end

function Popup:close()
    self.open = false
    self:setGroupVisible(self.commonWidgets, false)
    for _, group in pairs(self.contextWidgets) do self:setGroupVisible(group, false) end
end

function Popup:isOpen() return self.open == true end

return Popup
