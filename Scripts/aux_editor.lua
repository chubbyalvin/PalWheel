local AuxEditor = {}
AuxEditor.__index = AuxEditor

local L = require("localization")
local TextLayout = require("text_layout")
local function T(key, variables) return L.get(key, variables) end

local KEYS = {
    [1] = {
        "Gamepad_DPad_Left", "Gamepad_DPad_Up",
        "Gamepad_DPad_Right", "Gamepad_DPad_Down",
    },
    [2] = {
        "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
        "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Bottom",
    },
}

function AuxEditor.new(options)
    return setmetatable({
        o = options or {},
        built = false,
        rows = { {}, {} },
        widgets = {},
    }, AuxEditor)
end

local function pointInRect(x, y, rect)
    return rect ~= nil and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

function AuxEditor:track(widget)
    if widget ~= nil then self.widgets[#self.widgets + 1] = widget end
    return widget
end

function AuxEditor:cell(root, x, y, width, height, color, label, fontSize, justification)
    local o = self.o
    local border = o.construct("/Script/UMG.Border", o.state.tree)
    local slot = border and o.addToCanvas(root, border) or nil
    if slot ~= nil then
        o.place(slot, x, y, width, height)
        o.setBorderColor(border, color)
        pcall(function() border:SetVisibility(o.hitTestInvisible) end)
    end
    local size = tonumber(fontSize) or 13
    local centered = tonumber(justification) == 1
    local inset = 10
    local textX = centered and (x + width * 0.5) or (x + inset)
    local textY = y + height * 0.5
    local textWidth = math.max(10, width - inset * 2)
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

function AuxEditor:updateRow(wheel, slotIndex)
    local row = self.rows[wheel] and self.rows[wheel][slotIndex] or nil
    if row == nil then return end
    local assignments = type(self.o.getAssignments) == "function" and self.o.getAssignments() or nil
    local id = assignments and assignments[wheel] and assignments[wheel][slotIndex] or "empty"
    local def = type(self.o.definitionById) == "function" and self.o.definitionById(id) or nil
    if def == nil and type(self.o.definitionById) == "function" then
        def = self.o.definitionById("empty")
    end
    self.o.setText(row.assignmentText, def and (def.label or def.short or id) or tostring(id))
    if type(self.o.colorForDefinition) == "function" then
        self.o.setBorderColor(row.assignmentBorder, self.o.colorForDefinition(def))
    end
    if type(self.o.setDefinitionTextColor) == "function" then
        self.o.setDefinitionTextColor(row.assignmentText, def)
    end
end

function AuxEditor:updateRows()
    for wheel = 1, 2 do
        for slot = 1, 4 do self:updateRow(wheel, slot) end
    end
end

function AuxEditor:build(root)
    if self.built then return true end
    local o = self.o
    
    
    local x, tableW, buttonW, gap = 1101, 300, 46, 4
    local assignmentW = tableW - buttonW - gap
    local headingY = { 254, 532 }
    local headerY = { 299, 577 }
    local firstRowY = { 337, 615 }

    for wheel = 1, 2 do
        local headingBorder, headingText = self:cell(root, x, headingY[wheel],
            tableW, 42, o.colors.button, "AUX " .. (wheel == 1 and "I" or "II"), 17, 0)
        self:track(headingBorder); self:track(headingText)

        local buttonHeaderBorder, buttonHeaderText = self:cell(root, x, headerY[wheel],
            buttonW, 34, o.colors.row, "", 12, 1)
        local assignmentHeaderBorder, assignmentHeaderText = self:cell(root,
            x + buttonW + gap, headerY[wheel], assignmentW, 34, o.colors.row,
            T("functionName"), 12, 0)
        self:track(buttonHeaderBorder); self:track(buttonHeaderText)
        self:track(assignmentHeaderBorder); self:track(assignmentHeaderText)

        for slotIndex = 1, 4 do
            local y = firstRowY[wheel] + (slotIndex - 1) * 46
            local neutral = slotIndex % 2 == 0 and o.colors.rowAlt or o.colors.row
            local glyphBorder = o.construct("/Script/UMG.Border", o.state.tree)
            local glyphSlot = glyphBorder and o.addToCanvas(root, glyphBorder) or nil
            if glyphSlot ~= nil then
                o.place(glyphSlot, x, y, buttonW, 43)
                o.setBorderColor(glyphBorder, neutral)
                pcall(function() glyphBorder:SetVisibility(o.hitTestInvisible) end)
            end
            self:track(glyphBorder)

            local keyName = KEYS[wheel][slotIndex]
            local glyphTexture = type(o.glyphTextureForKey) == "function"
                and o.glyphTextureForKey(keyName) or nil
            local glyphWidget = nil
            if glyphTexture ~= nil and type(o.createIcon) == "function" then
                glyphWidget = o.createIcon(o.state.tree, root, glyphTexture,
                    x + buttonW * 0.5, y + 21.5, 28)
            else
                local fallbackLabel = type(o.glyphLabelForKey) == "function"
                    and o.glyphLabelForKey(keyName) or keyName:gsub("Gamepad_", "")
                glyphWidget = o.createText(o.state.tree, root,
                    fallbackLabel, x + 3, y + 11, buttonW - 6, 21, 7, 1)
            end
            self:track(glyphWidget)

            local assignmentBorder, assignmentText = self:cell(root,
                x + buttonW + gap, y, assignmentW, 43, o.colors.empty, "", 13, 0)
            self:track(assignmentBorder); self:track(assignmentText)
            self.rows[wheel][slotIndex] = {
                assignmentBorder = assignmentBorder,
                assignmentText = assignmentText,
                rect = { x = x, y = y, w = tableW, h = 43 },
            }
        end
    end

    self.built = true
    self:updateRows()
    return true
end

function AuxEditor:handleMainClick(x, y, direction)
    if not self.built or direction <= 0 then return false end
    for wheel = 1, 2 do
        for slot = 1, 4 do
            local row = self.rows[wheel][slot]
            if row ~= nil and pointInRect(x, y, row.rect) then
                if type(self.o.openPicker) == "function" then
                    self.o.openPicker(wheel, slot)
                end
                return true
            end
        end
    end
    return false
end

return AuxEditor
