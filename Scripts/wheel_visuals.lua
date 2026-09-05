local Visuals = {}
Visuals.__index = Visuals

local L = require("localization")
local TextLayout = require("text_layout")
local function T(key, variables) return L.get(key, variables) end

local function safe(callback)
    return pcall(callback)
end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function setOpacity(widget, value)
    if widget == nil then return end
    safe(function() widget:SetRenderOpacity(clamp(value, 0.0, 1.0)) end)
end

local function setScale(widget, value)
    if widget == nil then return end
    safe(function() widget:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
    safe(function() widget:SetRenderScale({ X = value, Y = value }) end)
end

local function setFontSize(widget, size)
    if widget == nil then return end
    safe(function()
        local font = widget.Font
        font.Size = math.floor(tonumber(size) or font.Size or 12)
        widget:SetFont(font)
    end)
end

local function setCanvasPosition(widget, x, y)
    if widget == nil or widget.Slot == nil then return end
    safe(function() widget.Slot:SetPosition({ X = x, Y = y }) end)
end

function Visuals.new(options)
    return setmetatable({
        o = options,
        panel = nil,
        ring = nil,
        pointer = nil,
        pointerTip = nil,
        centerDiamond = nil,
        title = nil,
        subtitle = nil,
        sectors = nil,
        page = 1,
        selected = nil,
        directionActive = false,
        directionDegrees = 0.0,
        openedAt = 0.0,
        opening = false,
        transition = "open",
        centerX = 0.0,
        centerY = 0.0,
        duration = clamp(options.cfg("wheelOpenAnimationSeconds", 0.15), 0.08, 0.30),
        pageFadeDuration = clamp(options.cfg("wheelPageFadeSeconds", 0.11), 0.06, 0.24),
        cascade = clamp(options.cfg("wheelSlotCascadeSeconds", 0.11), 0.04, 0.24),
    }, Visuals)
end

function Visuals:build(tree, root, centerX, centerY, centerSize)
    local o = self.o
    self.centerX, self.centerY = centerX, centerY
    local ringSize = clamp(centerSize * 0.88, 72, 138)

    local diamondSize = clamp(centerSize * 0.70, 58, 104)
    local diamond = o.construct("/Script/UMG.Border", tree)
    local diamondSlot = diamond and o.addToCanvas(root, diamond) or nil
    if diamondSlot ~= nil then
        o.place(diamondSlot, centerX - diamondSize * 0.5,
            centerY - diamondSize * 0.5, diamondSize, diamondSize)
        o.setRotation(diamond, 45.0)
        o.setBorderColor(diamond,
            { R = 0.055, G = 0.075, B = 0.105, A = 0.78 })
        safe(function() diamond:SetVisibility(o.hitTestInvisible) end)
    end
    self.centerDiamond = diamond

    local ring = o.construct("/Script/UMG.CanvasPanel", tree)
    local ringSlot = ring and o.addToCanvas(root, ring) or nil
    if ringSlot ~= nil then
        o.place(ringSlot, centerX - ringSize * 0.5, centerY - ringSize * 0.5,
            ringSize, ringSize)
        safe(function() ring:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
        for index = 1, 12 do
            local angle = math.pi * 0.5 - (index - 1) * math.pi * 2.0 / 12.0
            local dash = o.construct("/Script/UMG.Border", tree)
            local dashSlot = dash and o.addToCanvas(ring, dash) or nil
            if dashSlot ~= nil then
                local radius = ringSize * 0.42
                local width, height = 13, 3
                o.place(dashSlot,
                    ringSize * 0.5 + math.cos(angle) * radius - width * 0.5,
                    ringSize * 0.5 - math.sin(angle) * radius - height * 0.5,
                    width, height)
                o.setRotation(dash, 90.0 - math.deg(angle))
                o.setBorderColor(dash, index % 3 == 1
                    and { R = 0.98, G = 0.72, B = 0.16, A = 0.92 }
                    or { R = 0.30, G = 0.72, B = 0.94, A = 0.62 })
                safe(function() dash:SetVisibility(o.hitTestInvisible) end)
            end
        end
        safe(function() ring:SetVisibility(o.hitTestInvisible) end)
    end
    self.ring = ring

    local pointerSize = ringSize
    local pointer = o.construct("/Script/UMG.CanvasPanel", tree)
    local pointerSlot = pointer and o.addToCanvas(root, pointer) or nil
    if pointerSlot ~= nil then
        o.place(pointerSlot, centerX - pointerSize * 0.5,
            centerY - pointerSize * 0.5, pointerSize, pointerSize)
        safe(function() pointer:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)

        local stem = o.construct("/Script/UMG.Border", tree)
        local stemSlot = stem and o.addToCanvas(pointer, stem) or nil
        if stemSlot ~= nil then
            o.place(stemSlot, pointerSize * 0.5 + 12, pointerSize * 0.5 - 1,
                pointerSize * 0.27, 2)
            o.setBorderColor(stem, { R = 1.0, G = 0.78, B = 0.20, A = 0.95 })
            safe(function() stem:SetVisibility(o.hitTestInvisible) end)
        end

        local tip = o.construct("/Script/UMG.Border", tree)
        local tipSlot = tip and o.addToCanvas(pointer, tip) or nil
        if tipSlot ~= nil then
            o.place(tipSlot, pointerSize * 0.82, pointerSize * 0.5 - 4, 8, 8)
            o.setBorderColor(tip, { R = 1.0, G = 0.82, B = 0.22, A = 1.0 })
            o.setRotation(tip, 45.0)
            safe(function() tip:SetVisibility(o.hitTestInvisible) end)
        end
        self.pointerTip = tip
        safe(function() pointer:SetVisibility(o.hitTestInvisible) end)
    end
    self.pointer = pointer

    if type(o.createCenteredText) == "function" then
        self.title = o.createCenteredText(tree, root, "I", centerX, centerY, 30)
        self.subtitle = o.createCenteredText(tree, root, "", centerX, centerY + 16, 12)
    else
        self.title = o.createText(tree, root, "I",
            centerX - 70, centerY - 18, 140, 36, 30, 1)
        self.subtitle = o.createText(tree, root, "",
            centerX - 78, centerY + 1, 156, 24, 12, 1)
    end
    setOpacity(self.subtitle, 0.82)
    self:setDirection(nil, 0.0, 1.0)
end

function Visuals:setDirection(angle, magnitude, deadzone)
    magnitude = tonumber(magnitude) or 0.0
    deadzone = tonumber(deadzone) or 0.0
    self.directionActive = angle ~= nil and magnitude >= deadzone
    if self.directionActive then
        self.directionDegrees = -math.deg(angle)
        if self.pointer ~= nil then
            self.o.setRotation(self.pointer, self.directionDegrees)
            self.o.setVisible(self.pointer, true)
        end
    else
        self.o.setVisible(self.pointer, false)
    end
end

function Visuals:details(definition, palName)
    if type(definition) ~= "table" then return "", "" end
    if definition.kind == "sphere" then
        return tostring(definition.sphereShort or definition.sphereName or definition.label),
            T("captureRateShort") .. tostring(definition.captureRate or "--")
    end

    local title = tostring(definition.label or definition.short or "")
    if definition.kind == "pal" or definition.kind == "weapon" then
        return title, definition.kind == "pal"
            and (tostring(palName or "") ~= "" and tostring(palName) or T("partyPal"))
            or T("equippedWeapon")
    end
    return title, definition.kind == "empty" and "" or tostring(definition.detail or "")
end

function Visuals:updateHighlight(definition, selected, page, sectors, palName, wheelMode)
    self.selected = selected
    self.page = page or 1
    self.sectors = sectors
    local isMain = wheelMode == nil or wheelMode == "main"
    if selected == nil then
        local pageLabel = isMain
            and (self.page == 1 and "I" or (self.page == 2 and "II" or "III"))
            or T("sphereCenter")
        self.o.setText(self.title, pageLabel)
        self.o.setText(self.subtitle, "")
        setFontSize(self.title, isMain and 30 or 15)
        setCanvasPosition(self.title, self.centerX, self.centerY)
        setCanvasPosition(self.subtitle, self.centerX, self.centerY + 16)
    else
        local title, subtitle = self:details(definition, palName)
        self.o.setText(self.title, title)
        self.o.setText(self.subtitle, subtitle)
        setFontSize(self.title, TextLayout.fitFontSize(title, 15, 150, 34, 8))
        setFontSize(self.subtitle, TextLayout.fitFontSize(subtitle, 12, 156, 24, 7))
        setCanvasPosition(self.title, self.centerX, self.centerY - 10)
        setCanvasPosition(self.subtitle, self.centerX, self.centerY + 15)
    end

    if type(self.o.setTextShadow) == "function" then
        self.o.setTextShadow(self.title, isMain)
        self.o.setTextShadow(self.subtitle, isMain)
    end

    for index, sector in ipairs(sectors or {}) do
        for layerPage, layer in pairs(sector.pages or {}) do
            local scale = index == selected and layerPage == self.page
                and clamp(self.o.cfg("wheelSelectedContentScale", 1.58), 1.02, 1.80)
                or 1.0
            setScale(layer.icon, scale)
            setScale(layer.label, scale)
            setScale(layer.detailLabel, scale)
        end
    end
end

function Visuals:begin(panel, sectors, page)
    self.panel = panel
    self.sectors = sectors
    self.page = page or 1
    self.openedAt = os.clock()
    self.opening = true
    self.transition = "open"
    setOpacity(panel, 0.02)
    setScale(panel, 0.92)
    for _, sector in ipairs(sectors or {}) do
        local layer = sector.pages and sector.pages[self.page] or nil
        if layer ~= nil then
            setOpacity(layer.label, 0.0)
            setOpacity(layer.detailLabel, 0.0)
        end
    end
end

function Visuals:beginPageFade(panel, sectors, page)
    self.panel = panel
    self.sectors = sectors
    self.page = page or 1
    self.openedAt = os.clock()
    self.opening = true
    self.transition = "page"
    setScale(panel, 1.0)
    setOpacity(panel, 0.04)
end

function Visuals:tick()
    if not self.opening then
        if self.ring ~= nil then
            self.o.setRotation(self.ring, (os.clock() * 42.0) % 360.0)
        end
        return
    end

    local elapsed = math.max(0.0, os.clock() - self.openedAt)
    if self.transition == "page" then
        local progress = clamp(elapsed / self.pageFadeDuration, 0.0, 1.0)
        local eased = 1.0 - (1.0 - progress) * (1.0 - progress)
        setOpacity(self.panel, eased)
        setScale(self.panel, 1.0)
        if self.ring ~= nil then
            self.o.setRotation(self.ring, (os.clock() * 42.0) % 360.0)
        end
        if progress >= 1.0 then
            self.opening = false
            setOpacity(self.panel, 1.0)
        end
        return
    end

    local progress = clamp(elapsed / self.duration, 0.0, 1.0)
    local eased = 1.0 - (1.0 - progress) * (1.0 - progress)
    setOpacity(self.panel, eased)
    setScale(self.panel, 0.92 + 0.08 * eased)
    if self.ring ~= nil then
        self.o.setRotation(self.ring, (elapsed * 220.0) % 360.0)
    end

    local count = math.max(1, #(self.sectors or {}))
    for index, sector in ipairs(self.sectors or {}) do
        local delay = (index - 1) / count * self.cascade
        local alpha = clamp((elapsed - delay) / 0.055, 0.0, 1.0)
        local layer = sector.pages and sector.pages[self.page] or nil
        if layer ~= nil then
            setOpacity(layer.label, alpha)
            setOpacity(layer.detailLabel, alpha)
        end
    end

    if progress >= 1.0 and elapsed >= self.cascade + 0.06 then
        self.opening = false
        setOpacity(self.panel, 1.0)
        setScale(self.panel, 1.0)
    end
end

function Visuals:reset()
    self.panel = nil
    self.ring = nil
    self.pointer = nil
    self.pointerTip = nil
    self.centerDiamond = nil
    self.title = nil
    self.subtitle = nil
    self.sectors = nil
    self.opening = false
    self.transition = "open"
end

return Visuals
