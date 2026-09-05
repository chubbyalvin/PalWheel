local SphereEditor = {}
SphereEditor.__index = SphereEditor

local L = require("localization")
local TextLayout = require("text_layout")
local function T(key, variables) return L.get(key, variables) end

local function pointInRect(x, y, rect)
    return rect ~= nil and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end


local function captureRateColor(definition)
    local value = tonumber(definition and definition.captureRate) or 7
    local t = math.max(0, math.min(1, (value - 7) / (64 - 7)))
    local low = { R = 0.52, G = 0.16, B = 0.15, A = 0.96 }
    local mid = { R = 0.52, G = 0.43, B = 0.12, A = 0.96 }
    local high = { R = 0.12, G = 0.45, B = 0.20, A = 0.96 }
    local a, b, u
    if t <= 0.5 then
        a, b, u = low, mid, t * 2
    else
        a, b, u = mid, high, (t - 0.5) * 2
    end
    return {
        R = a.R + (b.R - a.R) * u,
        G = a.G + (b.G - a.G) * u,
        B = a.B + (b.B - a.B) * u,
        A = 0.96,
    }
end

local function swapOrder(order, slot, id)
    slot = tonumber(slot)
    if type(order) ~= "table" or slot == nil or slot < 1 or slot > #order or id == nil then
        return false
    end
    local found = nil
    for index, value in ipairs(order) do
        if value == id then found = index; break end
    end
    if found == nil then return false end
    order[slot], order[found] = order[found], order[slot]
    return true
end

function SphereEditor.new(options)
    return setmetatable({
        o = options or {}, built = false,
        rows = {}, rowRects = {}, pickerRects = {},
        pickerOpen = false, pickingSlot = nil,
        countDropdownOpen = false, countDropdownWidgets = {}, countOptionRects = {},
    }, SphereEditor)
end

function SphereEditor:cell(root, x, y, width, height, color, label, inset, fontSize, justification)
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
    local textWidth = math.max(10, width - padding * 2)
    local textHeight = math.max(18, height - 4)
    size = TextLayout.fitFontSize(label or "", size, textWidth, textHeight, 8)
    local text = o.createText(o.state.tree, root, label or "",
        textX, textY, textWidth,
        textHeight, size, centered and 1 or 0)
    pcall(function()
        if text ~= nil and text.Slot ~= nil then
            text.Slot:SetAutoSize(false)
            text.Slot:SetAlignment({ X = centered and 0.5 or 0.0, Y = 0.5 })
            text.Slot:SetPosition({ X = textX, Y = textY })
        end
    end)
    return border, text
end

function SphereEditor:outline(root, x, y, width, height)
    local o = self.o
    local function edge(ex, ey, ew, eh)
        local border = o.construct("/Script/UMG.Border", o.state.tree)
        local slot = border and o.addToCanvas(root, border) or nil
        if slot ~= nil then
            o.place(slot, ex, ey, ew, eh)
            o.setBorderColor(border, o.colors.button)
            pcall(function() border:SetVisibility(o.hitTestInvisible) end)
        end
    end
    edge(x, y, width, 2)
    edge(x, y + height - 2, width, 2)
    edge(x, y, 2, height)
    edge(x + width - 2, y, 2, height)
end

function SphereEditor:newLayer(root)
    local o = self.o
    local layer = o.construct("/Script/UMG.CanvasPanel", o.state.tree)
    local slot = layer and o.addToCanvas(root, layer) or nil
    if slot == nil then return nil end
    o.place(slot, 0, 0, tonumber(o.cfg("screenWidth", 1920)) or 1920,
        tonumber(o.cfg("screenHeight", 1080)) or 1080)
    pcall(function() slot:SetZOrder(30) end)
    o.setVisible(layer, false)
    return layer
end

function SphereEditor:setCountDropdownVisible(visible)
    self.countDropdownOpen = visible == true
    for _, widget in ipairs(self.countDropdownWidgets or {}) do
        self.o.setVisible(widget, self.countDropdownOpen)
    end
end

function SphereEditor:closeDropdown()
    self:setCountDropdownVisible(false)
end

function SphereEditor:build(root)
    if self.built then return true end
    local o = self.o
    
    local x, tableW, slotW, gap, crW = 1416, 324, 54, 4, 58
    local typeX = x + slotW + gap
    local typeW = tableW - slotW - gap - gap - crW
    local crX = typeX + typeW + gap

    
    self:cell(root, x, 254, tableW, 42, o.colors.button,
        T("sphereWheelTitle"), 14, 17, 0)
    local countW = 100
    local countX = x + tableW - countW - 10
    local _, countText = self:cell(root, countX, 259, countW, 32,
        o.colors.row, "", 6, 12, 1)
    self.countText = countText
    self.countRect = { x = countX, y = 259, w = countW, h = 32 }

    self:cell(root, x, 299, slotW, 34, o.colors.row, T("slot"), 8, 13, 1)
    self:cell(root, typeX, 299, typeW, 34, o.colors.row,
        T("sphereType"), 10, 12, 0)
    self:cell(root, crX, 299, crW, 34, o.colors.row, T("captureRateShort"), 8, 12, 1)

    for index = 1, 10 do
        local y = 337 + (index - 1) * 46
        local neutral = index % 2 == 0 and o.colors.rowAlt or o.colors.row
        self:cell(root, x, y, slotW, 43, neutral,
            string.format("%02d", index), 8, 13, 1)
        local border, text = self:cell(root, typeX, y, typeW, 43,
            o.colors.sphere, "", 10, 13, 0)
        local crBorder, crText = self:cell(root, crX, y, crW, 43,
            neutral, "", 8, 13, 1)
        self.rows[index] = {
            border = border, text = text, crBorder = crBorder, crText = crText,
        }
        self.rowRects[index] = {
            x = typeX, y = y, w = typeW + gap + crW, h = 43,
        }
    end

    local quickUseNote = o.createText(o.state.tree, root,
        T("sphereHelp"),
        x + 4, 796, tableW - 8, 44, 11, 0)
    if quickUseNote ~= nil then
        pcall(function() quickUseNote:SetAutoWrapText(true) end)
        pcall(function() quickUseNote:SetWrapTextAt(tableW - 16) end)
    end
    if quickUseNote ~= nil then
        pcall(function() quickUseNote:SetRenderOpacity(0.72) end)
    end

    self.countDropdownLayer = o.construct("/Script/UMG.CanvasPanel", o.state.tree)
    local dropSlot = self.countDropdownLayer and o.addToCanvas(root, self.countDropdownLayer) or nil
    if dropSlot ~= nil then
        o.place(dropSlot, 0, 0, tonumber(o.cfg("screenWidth", 1920)) or 1920,
            tonumber(o.cfg("screenHeight", 1080)) or 1080)
        pcall(function() dropSlot:SetZOrder(20) end)
    end
    local dropRoot = self.countDropdownLayer or root
    for value = 5, 10 do
        local y = 293 + (value - 5) * 38
        local border, label = self:cell(dropRoot, countX, y, countW, 36,
            o.colors.row, T("slots", { count = value }), 6, 11, 1)
        self.countDropdownWidgets[#self.countDropdownWidgets + 1] = border
        self.countDropdownWidgets[#self.countDropdownWidgets + 1] = label
        self.countOptionRects[value] = { x = countX, y = y, w = countW, h = 36 }
        o.setVisible(border, false)
        o.setVisible(label, false)
    end

    self.pickerLayer = self:newLayer(root)
    if self.pickerLayer == nil then return false end
    local pickerX, pickerY, pickerW, pickerH = 615, 188, 690, 690
    self.pickerPanelRect = { x = pickerX, y = pickerY, w = pickerW, h = pickerH }
    local pickerPanel = o.construct("/Script/UMG.Border", o.state.tree)
    local pickerSlot = pickerPanel and o.addToCanvas(self.pickerLayer, pickerPanel) or nil
    if pickerSlot ~= nil then
        o.place(pickerSlot, pickerX, pickerY, pickerW, pickerH)
        o.setBorderColor(pickerPanel, o.colors.panel)
    end
    self:outline(self.pickerLayer, pickerX, pickerY, pickerW, pickerH)
    self.pickerTitle = o.createText(o.state.tree, self.pickerLayer,
        T("chooseSphere"), pickerX + 38, pickerY + 22, pickerW - 76, 42, 18, 0)

    local listX, typeW, pickerGap, pickerCrW = pickerX + 42, 500, 4, 92
    local pickerCrX = listX + typeW + pickerGap
    self:cell(self.pickerLayer, listX, pickerY + 88, typeW, 36,
        o.colors.button, T("sphereType"), 12, 14)
    self:cell(self.pickerLayer, pickerCrX, pickerY + 88, pickerCrW, 36,
        o.colors.button, T("captureRateShort"), 30, 14)

    for index, definition in ipairs(o.definitions or {}) do
        local py = pickerY + 138 + (index - 1) * 48
        self:cell(self.pickerLayer, listX, py, typeW, 42, o.colors.sphere,
            definition.label, 12, 14)
        self:cell(self.pickerLayer, pickerCrX, py, pickerCrW, 42,
            captureRateColor(definition), tostring(definition.captureRate or ""), 30, 14)
        self.pickerRects[definition.id] = {
            x = listX, y = py, w = typeW + pickerGap + pickerCrW, h = 42,
        }
    end

    self.pickerHelp = o.createText(o.state.tree, self.pickerLayer,
        T("rightClickCancel"),
        pickerX + 95, pickerY + pickerH - 46, pickerW - 190, 28, 12, 0)

    self.built = true
    self:update()
    return true
end

function SphereEditor:update()
    if not self.built then return end
    local o = self.o
    local order = type(o.getOrder) == "function" and o.getOrder() or {}
    local visible = type(o.getVisibleCount) == "function" and o.getVisibleCount() or 10
    visible = math.floor(tonumber(visible) or 10)
    o.setText(self.countText, T("slotsDropdown", { count = visible }))
    for index, row in ipairs(self.rows) do
        local definition = o.byId and o.byId[order[index]] or nil
        o.setText(row.text, definition and definition.label or T("unknown"))
        o.setBorderColor(row.border, o.colors.sphere)
        o.setText(row.crText, definition and tostring(definition.captureRate or "") or "")
        o.setBorderColor(row.crBorder, definition and captureRateColor(definition) or o.colors.row)
    end
end

function SphereEditor:isOpen()
    return self.pickerOpen == true
end

function SphereEditor:isBusy()
    return self.pickerOpen == true or self.countDropdownOpen == true
end

function SphereEditor:openPicker(slot)
    self:setCountDropdownVisible(false)
    self.pickingSlot = slot
    self.pickerOpen = true
    self.o.setText(self.pickerTitle,
        T("chooseSphereSlot", { slot = string.format("%02d", slot) }))
    self.o.setVisible(self.pickerLayer, true)
end

function SphereEditor:closePicker()
    self.pickerOpen = false
    self.pickingSlot = nil
    if self.pickerLayer ~= nil then self.o.setVisible(self.pickerLayer, false) end
end

function SphereEditor:closePanel()
    self:closePicker()
    self:setCountDropdownVisible(false)
end

function SphereEditor:handleClick(x, y, direction)
    if not self.built then return false end
    local o = self.o

    if self.pickerOpen then
        if direction < 0 then
            self:closePicker()
            return true
        end
        for id, rect in pairs(self.pickerRects) do
            if pointInRect(x, y, rect) then
                local order = type(o.getOrder) == "function" and o.getOrder() or nil
                if swapOrder(order, self.pickingSlot, id) then
                    self:update()
                    if type(o.onChanged) == "function" then o.onChanged("sphere assignment") end
                end
                self:closePicker()
                return true
            end
        end
        if not pointInRect(x, y, self.pickerPanelRect) then
            self:closePicker()
        end
        return true
    end

    if self.countDropdownOpen then
        if direction < 0 then
            self:setCountDropdownVisible(false)
            return true
        end
        for value, rect in pairs(self.countOptionRects or {}) do
            if pointInRect(x, y, rect) then
                if type(o.setVisibleCount) == "function" then o.setVisibleCount(value) end
                self:setCountDropdownVisible(false)
                self:update()
                if type(o.onChanged) == "function" then o.onChanged("sphere slot count") end
                return true
            end
        end
        self:setCountDropdownVisible(false)
        return true
    end

    if direction < 0 then return false end
    if pointInRect(x, y, self.countRect) then
        self:setCountDropdownVisible(true)
        return true
    end
    for slot, rect in ipairs(self.rowRects) do
        if pointInRect(x, y, rect) then
            self:openPicker(slot)
            return true
        end
    end
    return false
end

return SphereEditor
