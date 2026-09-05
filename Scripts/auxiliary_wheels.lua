local AuxiliaryWheels = {}
AuxiliaryWheels.__index = AuxiliaryWheels


local GROUPS = {
    {
        side = "left",
        wheel = 1,
        keys = {
            { key = "Gamepad_DPad_Left", slot = 1 },
            { key = "Gamepad_DPad_Up", slot = 2 },
            { key = "Gamepad_DPad_Right", slot = 3 },
            { key = "Gamepad_DPad_Down", slot = 4 },
        },
    },
    {
        side = "right",
        wheel = 2,
        keys = {
            { key = "Gamepad_FaceButton_Left", slot = 1 },
            { key = "Gamepad_FaceButton_Top", slot = 2 },
            { key = "Gamepad_FaceButton_Right", slot = 3 },
            { key = "Gamepad_FaceButton_Bottom", slot = 4 },
        },
    },
}

local DIRECT_BUTTONS = {}
for _, group in ipairs(GROUPS) do
    for _, mapping in ipairs(group.keys) do
        DIRECT_BUTTONS[#DIRECT_BUTTONS + 1] = {
            key = mapping.key,
            auxWheel = group.wheel,
            auxSlot = mapping.slot,
        }
    end
end

local function setScale(widget, value)
    if widget == nil then return end
    pcall(function() widget:SetRenderScale({ X = value, Y = value }) end)
end

local function setOpacity(widget, value)
    if widget == nil then return end
    pcall(function() widget:SetRenderOpacity(value) end)
end

function AuxiliaryWheels.new(options)
    return setmetatable({
        o = options or {},
        panels = {},
        glyphWidgets = {},
        mercyStatusWidgets = {},
        geometry = {},
        glyphsVisible = true,
        opening = false,
        openedAt = 0.0,
        duration = math.max(0.08, math.min(0.30,
            tonumber((options or {}).cfg and options.cfg("wheelOpenAnimationSeconds", 0.15)) or 0.15)),
    }, AuxiliaryWheels)
end

function AuxiliaryWheels:directButtons()
    return DIRECT_BUTTONS
end

function AuxiliaryWheels:reset()
    self.panels = {}
    self.glyphWidgets = {}
    self.mercyStatusWidgets = {}
    self.geometry = {}
    self.glyphsVisible = true
    self.opening = false
    self.openedAt = 0.0
end

function AuxiliaryWheels:destroy()
    for _, panel in pairs(self.panels or {}) do
        pcall(function() panel:RemoveFromParent() end)
    end
    self:reset()
end

function AuxiliaryWheels:isBuilt()
    return self.o.alive(self.panels.left) and self.o.alive(self.panels.right)
end

function AuxiliaryWheels:setVisible(visible)
    visible = visible == true
    for _, panel in pairs(self.panels or {}) do
        self.o.setVisible(panel, visible)
    end
    if not visible then
        self.opening = false
        for _, panel in pairs(self.panels or {}) do
            setOpacity(panel, 1.0)
            setScale(panel, 1.0)
        end
    end
end


function AuxiliaryWheels:setGlyphsVisible(visible)
    self.glyphsVisible = visible == true
    for _, widget in ipairs(self.glyphWidgets or {}) do
        if self.o.alive(widget) then
            self.o.setVisible(widget, self.glyphsVisible)
        end
    end
end

function AuxiliaryWheels:refreshMercyStatus(equipped)
    local o = self.o
    local text = equipped == true
        and tostring(o.mercyEquippedLabel or "[Equipped]")
        or tostring(o.mercyNoneLabel or "[None]")
    local color = equipped == true and o.mercyEquippedText or o.mercyNoneText
    for _, widget in ipairs(self.mercyStatusWidgets or {}) do
        if o.alive(widget) then
            if type(o.setText) == "function" then o.setText(widget, text) end
            if type(o.setTextColor) == "function" and type(color) == "table" then
                o.setTextColor(widget, color)
            end
            o.setVisible(widget, true)
        end
    end
end

function AuxiliaryWheels:slotAt(x, y)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return nil end
    local slotAngles = { math.rad(180), math.rad(90), math.rad(0), math.rad(-90) }
    for wheel = 1, 2 do
        local g = self.geometry and self.geometry[wheel] or nil
        if g ~= nil then
            local dx = x - g.x
            local dyUp = g.y - y
            local radius = math.sqrt(dx * dx + dyUp * dyUp)
            if radius >= (g.innerRadius or 24) and radius <= (g.outerRadius or 180) then
                local angle = math.atan(dyUp, dx)
                local bestSlot, bestDistance = nil, math.huge
                for slot, slotAngle in ipairs(slotAngles) do
                    local diff = math.abs(math.atan(math.sin(angle - slotAngle), math.cos(angle - slotAngle)))
                    if diff < bestDistance then
                        bestDistance, bestSlot = diff, slot
                    end
                end
                if bestSlot ~= nil then
                    local group = GROUPS[wheel]
                    local mapping = group and group.keys and group.keys[bestSlot] or nil
                    return wheel, bestSlot, mapping and mapping.key or nil
                end
            end
        end
    end
    return nil
end

function AuxiliaryWheels:begin()
    if not self:isBuilt() then return false end
    self.openedAt = os.clock()
    self.opening = true
    for _, panel in pairs(self.panels or {}) do
        setOpacity(panel, 0.02)
        setScale(panel, 0.92)
    end
    return true
end

function AuxiliaryWheels:tick()
    if not self.opening then return end
    local elapsed = math.max(0.0, os.clock() - self.openedAt)
    local progress = math.max(0.0, math.min(1.0, elapsed / self.duration))
    local eased = 1.0 - (1.0 - progress) * (1.0 - progress)
    for _, panel in pairs(self.panels or {}) do
        setOpacity(panel, eased)
        setScale(panel, 0.92 + 0.08 * eased)
    end
    if progress >= 1.0 then
        self.opening = false
        for _, panel in pairs(self.panels or {}) do
            setOpacity(panel, 1.0)
            setScale(panel, 1.0)
        end
    end
end

function AuxiliaryWheels:createBackground(tree, panel, centerX, centerY, radius)
    local o = self.o
    local texture = type(o.wheelBackgroundTexture) == "function"
        and o.wheelBackgroundTexture() or nil
    if not o.alive(texture) then return nil end
    local image = o.construct("/Script/UMG.Image", tree)
    local slot = o.alive(image) and o.addToCanvas(panel, image) or nil
    if slot == nil then return nil end
    o.place(slot, centerX - radius, centerY - radius, radius * 2, radius * 2)
    local ok = pcall(function() image:SetBrushFromTexture(texture, false) end)
    if not ok then
        pcall(function() image:RemoveFromParent() end)
        return nil
    end
    o.setImageColor(image, { R = 1.0, G = 1.0, B = 1.0, A = 0.58 })
    pcall(function() image:SetVisibility(o.hitTestInvisible) end)
    return image
end

function AuxiliaryWheels:build(tree, masterRoot, centerX, centerY, outerRadius)
    local o = self.o
    if self:isBuilt() then return true end
    self:destroy()
    if type(o.prepareGlyphs) == "function" then pcall(o.prepareGlyphs) end

    local auxRadius = math.floor(o.clamp(outerRadius * 0.49, 112, 148))
    
    local horizontalOffset = outerRadius * 2.0
    local centers = {
        left = { x = centerX - horizontalOffset, y = centerY },
        right = { x = centerX + horizontalOffset, y = centerY },
    }

    
    
    local glyphRadiusByWheel = { [1] = 150, [2] = 150 }
    local glyphSizeByWheel = { [1] = 40, [2] = 40 }
    local iconRadius = 90
    local iconSize = 44
    local labelRadius = 58
    local textOnlyRadius = 82
    local labelWithIconFontSize = 12
    local labelOnlyFontSize = 10
    self.geometry = {
        [1] = { x = centers.left.x, y = centers.left.y,
            innerRadius = math.max(24, auxRadius * 0.20), outerRadius = auxRadius + 32 },
        [2] = { x = centers.right.x, y = centers.right.y,
            innerRadius = math.max(24, auxRadius * 0.20), outerRadius = auxRadius + 32 },
    }
    local slotAngles = { math.rad(180), math.rad(90), math.rad(0), math.rad(-90) }
    local screenW = tonumber(o.cfg("screenWidth", 1920)) or 1920
    local screenH = tonumber(o.cfg("screenHeight", 1080)) or 1080

    for _, group in ipairs(GROUPS) do
        local panel = o.construct("/Script/UMG.CanvasPanel", tree)
        local panelSlot = o.alive(panel) and o.addToCanvas(masterRoot, panel) or nil
        if panelSlot ~= nil then
            o.place(panelSlot, 0, 0, screenW, screenH)
            local c = centers[group.side]
            
            
            pcall(function()
                panel:SetRenderTransformPivot({
                    X = math.max(0.0, math.min(1.0, c.x / screenW)),
                    Y = math.max(0.0, math.min(1.0, c.y / screenH)),
                })
            end)
            self:createBackground(tree, panel, c.x, c.y, auxRadius)

            for pos, mapping in ipairs(group.keys) do
                local angle = slotAngles[pos]
                local def = type(o.auxDefinition) == "function"
                    and o.auxDefinition(group.wheel, mapping.slot) or o.emptyDefinition()
                if def == nil then def = o.emptyDefinition() end

                local glyphRadius = glyphRadiusByWheel[group.wheel]
                local glyphX = c.x + math.cos(angle) * glyphRadius
                local glyphY = c.y - math.sin(angle) * glyphRadius
                local actionTexture = type(o.iconTextureForDefinition) == "function"
                    and o.iconTextureForDefinition(def) or nil

                if actionTexture ~= nil then
                    local iconX = c.x + math.cos(angle) * iconRadius
                    local iconY = c.y - math.sin(angle) * iconRadius
                    o.createIcon(tree, panel, actionTexture, iconX, iconY, iconSize)
                    local labelX = c.x + math.cos(angle) * labelRadius
                    local labelY = c.y - math.sin(angle) * labelRadius
                    local label = o.createCenteredText(tree, panel,
                        def.short or def.label, labelX, labelY, labelWithIconFontSize)
                    o.setDefinitionTextColor(label, def)
                    if type(o.setTextShadow) == "function" then o.setTextShadow(label, true) end
                    if def.id == "mercy" then
                        local status = o.createCenteredText(tree, panel,
                            tostring(o.mercyNoneLabel or "[None]"),
                            labelX, labelY + 15, 7)
                        if o.alive(status) then
                            self.mercyStatusWidgets[#self.mercyStatusWidgets + 1] = status
                            if type(o.setTextShadow) == "function" then o.setTextShadow(status, true) end
                        end
                    end
                else
                    local actionX = c.x + math.cos(angle) * textOnlyRadius
                    local actionY = c.y - math.sin(angle) * textOnlyRadius
                    local label = o.createCenteredText(tree, panel,
                        def.short or def.label, actionX, actionY, labelOnlyFontSize)
                    o.setDefinitionTextColor(label, def)
                    if type(o.setTextShadow) == "function" then o.setTextShadow(label, true) end
                    if def.id == "mercy" then
                        local status = o.createCenteredText(tree, panel,
                            tostring(o.mercyNoneLabel or "[None]"),
                            actionX, actionY + 14, 7)
                        if o.alive(status) then
                            self.mercyStatusWidgets[#self.mercyStatusWidgets + 1] = status
                            if type(o.setTextShadow) == "function" then o.setTextShadow(status, true) end
                        end
                    end
                end

                local glyphTexture = type(o.glyphTextureForKey) == "function"
                    and o.glyphTextureForKey(mapping.key) or nil
                if glyphTexture ~= nil then
                    local glyphSize = glyphSizeByWheel[group.wheel] or 40
                    local glyph = o.createIcon(tree, panel, glyphTexture, glyphX, glyphY, glyphSize)
                    if o.alive(glyph) then self.glyphWidgets[#self.glyphWidgets + 1] = glyph end
                else
                    local fallbackLabel = type(o.glyphLabelForKey) == "function"
                        and o.glyphLabelForKey(mapping.key) or mapping.key:gsub("Gamepad_", "")
                    local fallback = o.createCenteredText(tree, panel,
                        fallbackLabel, glyphX, glyphY, 8)
                    if o.alive(fallback) then
                        self.glyphWidgets[#self.glyphWidgets + 1] = fallback
                        pcall(function() fallback:SetRenderOpacity(0.72) end)
                        if type(o.setTextShadow) == "function" then o.setTextShadow(fallback, true) end
                    end
                end
            end
            o.setVisible(panel, false)
            self.panels[group.side] = panel
        end
    end
    self:setGlyphsVisible(self.glyphsVisible)
    local equipped = type(self.o.mercyEquipped) == "function"
        and self.o.mercyEquipped() == true
    self:refreshMercyStatus(equipped)
    return self:isBuilt()
end

return AuxiliaryWheels
