local Navigation = {}
Navigation.__index = Navigation

local FOCUS_COLOR = { R = 0.72, G = 0.94, B = 1.00, A = 1.0 }

local INPUTS = {
    up = "Gamepad_DPad_Up",
    down = "Gamepad_DPad_Down",
    left = "Gamepad_DPad_Left",
    right = "Gamepad_DPad_Right",
    confirm = "Gamepad_FaceButton_Bottom",
    back = "Gamepad_FaceButton_Right",
    save = "Gamepad_FaceButton_Top",
    touchpad = "Gamepad_Touchpad_Button",
    axisX = "Gamepad_LeftX",
    axisY = "Gamepad_LeftY",
}

local HINT_KEYS = {
    back = "Gamepad_FaceButton_Right",
    save = "Gamepad_FaceButton_Top",
}

local function center(rect)
    if rect == nil then return 0, 0 end
    return (tonumber(rect.x) or 0) + (tonumber(rect.w) or 0) * 0.5,
        (tonumber(rect.y) or 0) + (tonumber(rect.h) or 0) * 0.5
end

local function samePath(a, b)
    if #(a or {}) ~= #(b or {}) then return false end
    for index, value in ipairs(a or {}) do
        if value ~= b[index] then return false end
    end
    return true
end

local function copyPath(path)
    local result = {}
    for index, value in ipairs(path or {}) do result[index] = value end
    return result
end

local function pathKey(path)
    return table.concat(path or {}, "/")
end

function Navigation.new(options)
    local self = setmetatable({
        o = options or {},
        keys = {},
        down = {},
        blockedUntilRelease = {},
        focusId = nil,
        focusByLevel = {},
        currentPath = {},
        controllerPresentation = false,
        directionHeld = nil,
        directionRepeatAt = 0.0,
        mouseX = nil,
        mouseY = nil,
        focusWidgets = {},
        hintWidgets = {},
        builtForRoot = nil,
        glyphFamily = nil,
        glyphFamilyCheckedAt = 0.0,
        lastContext = nil,
    }, Navigation)
    for id, name in pairs(INPUTS) do self.keys[id] = self.o.makeFKey(name) end
    return self
end

function Navigation:log(message)
    if type(self.o.log) == "function" then self.o.log(message, true) end
end

function Navigation:keyDown(pc, id)
    local key = self.keys[id]
    if key == nil or not self.o.alive(pc) then return false end
    if type(self.o.isKeyDown) == "function" and self.o.isKeyDown(pc, key) then return true end

    
    
    
    
    local okTime, timeDown = pcall(function() return pc:GetInputKeyTimeDown(key) end)
    if okTime and (tonumber(timeDown) or 0) > 0.0 then return true end

    local ok, value = pcall(function() return pc:GetInputAnalogKeyState(key) end)
    return ok and math.abs(tonumber(value) or 0) >= 0.50
end

function Navigation:axis(pc, id)
    local key = self.keys[id]
    if key == nil or not self.o.alive(pc) then return 0.0 end
    local ok, value = pcall(function() return pc:GetInputAnalogKeyState(key) end)
    return ok and tonumber(value) or 0.0
end

function Navigation:justPressed(pc, id)
    local key = self.keys[id]
    if key == nil or not self.o.alive(pc) then return false end
    local ok, value = pcall(function() return pc:WasInputKeyJustPressed(key) end)
    return ok and value == true
end

function Navigation:pressed(pc, id)
    local active = self:keyDown(pc, id)
    local previous = self.down[id] == true
    local edge = self:justPressed(pc, id) or (active and not previous)
    if not active then self.blockedUntilRelease[id] = false end
    local allowed = self.blockedUntilRelease[id] ~= true
    self.down[id] = active
    return allowed and edge
end

function Navigation:blockUntilReleased(id)
    self.blockedUntilRelease[id] = true
    self.down[id] = true
end

function Navigation:prime(pc)
    for _, id in ipairs({ "up", "down", "left", "right", "confirm", "back",
        "save", "touchpad" }) do
        self.down[id] = self:keyDown(pc, id)
        self.blockedUntilRelease[id] = self.down[id]
    end
    self.directionHeld = nil
    self.directionRepeatAt = 0.0
end

function Navigation:detectGlyphFamily(pc, force)
    local now = os.clock()
    if not force and self.glyphFamily ~= nil and now < self.glyphFamilyCheckedAt then
        return self.glyphFamily
    end
    self.glyphFamilyCheckedAt = now + 1.0
    local family = ""
    if type(self.o.detectGlyphFamily) == "function" then
        local ok, value = pcall(self.o.detectGlyphFamily, pc)
        if ok then family = string.lower(tostring(value or "")) end
    end
    if family:find("playstation", 1, true) or family:find("dual", 1, true)
        or family == "ps" or family == "ps4" or family == "ps5" then
        family = "dualsense"
    elseif family:find("xbox", 1, true) or family == "xinput" then
        family = "xbox"
    else
        family = string.lower(tostring(self.o.cfg("controllerGlyphFallbackFamily", "xbox")))
        family = (family == "xbox") and "xbox" or "dualsense"
    end
    
    if self:keyDown(pc, "touchpad") then family = "dualsense" end
    self.glyphFamily = family
    return family
end

function Navigation:makeBorder(root)
    local border = self.o.construct("/Script/UMG.Border", self.o.state.tree)
    local slot = border and self.o.addToCanvas(root, border) or nil
    if slot == nil then return nil end
    self.o.place(slot, 0, 0, 1, 1)
    self.o.setBorderColor(border, FOCUS_COLOR)
    pcall(function() slot:SetZOrder(100) end)
    pcall(function() border:SetVisibility(self.o.hitTestInvisible) end)
    self.o.setVisible(border, false)
    return border
end

function Navigation:buildVisuals(root)
    if root == nil or not self.o.alive(root) then return false end
    if self.builtForRoot == root and #self.focusWidgets == 4 then return true end
    self.focusWidgets = {}
    self.hintWidgets = {}
    self.builtForRoot = root
    for _ = 1, 4 do
        local widget = self:makeBorder(root)
        if widget ~= nil then self.focusWidgets[#self.focusWidgets + 1] = widget end
    end
    for action, key in pairs(HINT_KEYS) do
        self.hintWidgets[action] = {}
        for _, family in ipairs({ "dualsense", "xbox" }) do
            local texture = type(self.o.glyphTextureForKey) == "function"
                and self.o.glyphTextureForKey(key, family) or nil
            local widget = texture ~= nil and type(self.o.createIcon) == "function"
                and self.o.createIcon(self.o.state.tree, root, texture, 0, 0, 24) or nil
            if widget ~= nil then
                pcall(function() if widget.Slot ~= nil then widget.Slot:SetZOrder(101) end end)
                self.o.setVisible(widget, false)
                self.hintWidgets[action][family] = widget
            end
        end
    end
    return #self.focusWidgets == 4
end

function Navigation:setControllerPresentation(active)
    active = active == true
    if self.controllerPresentation == active then return end
    self.controllerPresentation = active
    if type(self.o.presentationChanged) == "function" then
        pcall(self.o.presentationChanged, active)
    end
    if not active then self:hideFocus() end
end

function Navigation:hideFocus()
    for _, widget in ipairs(self.focusWidgets or {}) do self.o.setVisible(widget, false) end
    for _, families in pairs(self.hintWidgets or {}) do
        for _, widget in pairs(families or {}) do self.o.setVisible(widget, false) end
    end
end

function Navigation:setDecorativeVisible(widget, visible)
    if widget == nil then return end
    if visible == true then
        
        
        local ok = pcall(function() widget:SetVisibility(self.o.hitTestInvisible) end)
        if not ok then self.o.setVisible(widget, true) end
    else
        self.o.setVisible(widget, false)
    end
end

function Navigation:itemById(context, id)
    for _, item in ipairs((context and context.items) or {}) do
        if item.id == id and item.enabled ~= false and item.rect ~= nil then return item end
    end
    return nil
end

function Navigation:selectDefault(context)
    local key = pathKey(context.path)
    local remembered = self.focusByLevel[key]
    local preferred = context.safeId or remembered or context.defaultId
    local item = self:itemById(context, preferred)
    if item == nil then
        for _, candidate in ipairs(context.items or {}) do
            if candidate.enabled ~= false and candidate.rect ~= nil then item = candidate; break end
        end
    end
    self.focusId = item and item.id or nil
    if self.focusId ~= nil then self.focusByLevel[key] = self.focusId end
end

function Navigation:updateContext(context)
    context = context or { path = { "main" }, items = {} }
    context.path = context.path or { "main" }
    if not samePath(self.currentPath, context.path) then
        local oldKey = pathKey(self.currentPath)
        if oldKey ~= "" and self.focusId ~= nil then self.focusByLevel[oldKey] = self.focusId end
        self.currentPath = copyPath(context.path)
        self.focusId = nil
        self:selectDefault(context)
        
        for _, id in ipairs({ "confirm", "back", "save", "restore" }) do
            if self.down[id] == true then self:blockUntilReleased(id) end
        end
    elseif self:itemById(context, self.focusId) == nil then
        self:selectDefault(context)
    end
    self.lastContext = context
    return context
end

function Navigation:renderFocus(context, pc)
    self:hideFocus()
    if not self.controllerPresentation or #self.focusWidgets ~= 4 then return end
    local item = self:itemById(context, self.focusId)
    if item == nil then return end
    local rect = item.rect
    local x, y, w, h = rect.x - 3, rect.y - 3, rect.w + 6, rect.h + 6
    local thickness = 3
    local positions = {
        { x, y, w, thickness }, { x, y + h - thickness, w, thickness },
        { x, y, thickness, h }, { x + w - thickness, y, thickness, h },
    }
    for index, widget in ipairs(self.focusWidgets) do
        local p = positions[index]
        pcall(function()
            if widget ~= nil and widget.Slot ~= nil then
                self.o.place(widget.Slot, p[1], p[2], p[3], p[4])
            end
        end)
        self:setDecorativeVisible(widget, true)
    end

    local family = self:detectGlyphFamily(pc, false)
    for action, rectValue in pairs(context.hints or {}) do
        local families = self.hintWidgets[action]
        local widget = families and families[family] or nil
        if widget ~= nil and rectValue ~= nil then
            local size = math.min(24, math.max(18, (rectValue.h or 24) - 10))
            local cx = rectValue.x + 17
            local cy = rectValue.y + rectValue.h * 0.5
            pcall(function()
                if widget.Slot ~= nil then
                    self.o.place(widget.Slot, cx - size * 0.5, cy - size * 0.5, size, size)
                end
            end)
            self:setDecorativeVisible(widget, true)
        end
    end
end

function Navigation:move(context, direction)
    local current = self:itemById(context, self.focusId)
    if current == nil then self:selectDefault(context); return self.focusId ~= nil end
    local cx, cy = center(current.rect)
    local dx, dy = 0, 0
    if direction == "left" then dx = -1 elseif direction == "right" then dx = 1
    elseif direction == "up" then dy = -1 else dy = 1 end

    local alignedBest, alignedScore = nil, nil
    local fallbackBest, fallbackScore = nil, nil
    local cr = current.rect
    for _, candidate in ipairs(context.items or {}) do
        if candidate.enabled ~= false and candidate.rect ~= nil and candidate.id ~= current.id then
            local tx, ty = center(candidate.rect)
            local vx, vy = tx - cx, ty - cy
            local primary = vx * dx + vy * dy
            if primary > 2 then
                local perpendicular = math.abs(vx * dy - vy * dx)
                local euclidean = math.sqrt(vx * vx + vy * vy)
                local rr = candidate.rect
                local overlap
                if direction == "left" or direction == "right" then
                    overlap = math.min((cr.y or 0) + (cr.h or 0), (rr.y or 0) + (rr.h or 0))
                        - math.max(cr.y or 0, rr.y or 0)
                else
                    overlap = math.min((cr.x or 0) + (cr.w or 0), (rr.x or 0) + (rr.w or 0))
                        - math.max(cr.x or 0, rr.x or 0)
                end

                
                
                
                if overlap >= -3 then
                    local score = primary + perpendicular * 0.30 + euclidean * 0.02
                    if alignedScore == nil or score < alignedScore then
                        alignedBest, alignedScore = candidate, score
                    end
                end

                
                local score = primary + perpendicular * 2.35 + euclidean * 0.08
                if fallbackScore == nil or score < fallbackScore then
                    fallbackBest, fallbackScore = candidate, score
                end
            end
        end
    end
    local best = alignedBest or fallbackBest
    if best == nil then return false end
    local previousId = self.focusId
    self.focusId = best.id
    self.focusByLevel[pathKey(context.path)] = best.id
    self:log("Controller UI focus " .. tostring(previousId) .. " -> "
        .. tostring(best.id) .. " via " .. tostring(direction))
    if type(self.o.focusChanged) == "function" then pcall(self.o.focusChanged, best) end
    return true
end

function Navigation:direction(pc, now)
    local direction = nil
    if self:keyDown(pc, "up") then direction = "up"
    elseif self:keyDown(pc, "down") then direction = "down"
    elseif self:keyDown(pc, "left") then direction = "left"
    elseif self:keyDown(pc, "right") then direction = "right"
    else
        local x, y = self:axis(pc, "axisX"), self:axis(pc, "axisY")
        local threshold = tonumber(self.o.cfg("controllerUiStickThreshold", 0.62)) or 0.62
        if math.abs(x) >= threshold or math.abs(y) >= threshold then
            if math.abs(x) > math.abs(y) then direction = x < 0 and "left" or "right"
            else direction = y > 0 and "up" or "down" end
        end
    end
    if direction == nil then
        self.directionHeld = nil
        self.directionRepeatAt = 0.0
        return nil
    end
    if direction ~= self.directionHeld then
        self.directionHeld = direction
        self.directionRepeatAt = now + (tonumber(self.o.cfg("controllerUiRepeatDelay", 0.38)) or 0.38)
        return direction
    end
    if now >= self.directionRepeatAt then
        self.directionRepeatAt = now + (tonumber(self.o.cfg("controllerUiRepeatRate", 0.11)) or 0.11)
        return direction
    end
    return nil
end

function Navigation:updateMousePresentation(pc)
    if type(self.o.readMousePosition) ~= "function" then return end
    local x, y = self.o.readMousePosition(pc)
    if x == nil or y == nil then return end
    if self.mouseX ~= nil and self.mouseY ~= nil then
        local dx, dy = x - self.mouseX, y - self.mouseY
        local threshold = tonumber(self.o.cfg("controllerUiMouseThreshold", 3.0)) or 3.0
        if dx * dx + dy * dy >= threshold * threshold then
            self:setControllerPresentation(false)
        end
    end
    self.mouseX, self.mouseY = x, y
end

function Navigation:anyControllerActivity(pc)
    for _, id in ipairs({ "up", "down", "left", "right", "confirm", "back",
        "save", "touchpad" }) do
        if self:keyDown(pc, id) then return true end
    end
    return math.abs(self:axis(pc, "axisX")) >= 0.35
        or math.abs(self:axis(pc, "axisY")) >= 0.35
end

function Navigation:tick(pc)
    if not self.o.alive(pc) then return false end
    local root = type(self.o.root) == "function" and self.o.root() or nil
    if not self:buildVisuals(root) then return false end
    local context = type(self.o.context) == "function" and self.o.context() or nil
    context = self:updateContext(context)

    self:updateMousePresentation(pc)
    if self:anyControllerActivity(pc) then self:setControllerPresentation(true) end

    local now = os.clock()
    local move = context.rawCapture ~= true and self:direction(pc, now) or nil
    if context.rawCapture == true then
        self.directionHeld, self.directionRepeatAt = nil, 0.0
    elseif move ~= nil then
        self:move(context, move)
    end

    local backPressed = self:pressed(pc, "back")
    local confirmPressed = self:pressed(pc, "confirm")
    local savePressed = self:pressed(pc, "save")

    if backPressed then
        self:log("Controller UI Back")
        self:blockUntilReleased("back")
        if type(self.o.dispatchBack) == "function" then
            local ok, why = pcall(self.o.dispatchBack, context)
            if not ok then self:log("Controller UI Back failed: " .. tostring(why)) end
        end
    elseif context.rawCapture ~= true and confirmPressed then
        self:blockUntilReleased("confirm")
        local item = self:itemById(context, self.focusId)
        if item ~= nil and type(self.o.dispatchConfirm) == "function" then
            self:log("Controller UI Confirm -> " .. tostring(item.id))
            local ok, why = pcall(self.o.dispatchConfirm, item, context)
            if not ok then self:log("Controller UI Confirm failed: " .. tostring(why)) end
        else
            self:log("Controller UI Confirm detected with no focusable target")
        end
    elseif context.rawCapture ~= true and context.saveAllowed == true and savePressed then
        self:log("Controller UI Save")
        self:blockUntilReleased("save")
        if type(self.o.dispatchSave) == "function" then
            local ok, why = pcall(self.o.dispatchSave, context)
            if not ok then self:log("Controller UI Save failed: " .. tostring(why)) end
        end
    end

    
    
    if type(self.o.context) == "function" then context = self:updateContext(self.o.context()) end
    self:renderFocus(context, pc)
    return true
end

function Navigation:reset()
    self:hideFocus()
    self.focusId = nil
    self.currentPath = {}
    self.lastContext = nil
    self.directionHeld = nil
    self.directionRepeatAt = 0.0
    self.mouseX, self.mouseY = nil, nil
end

return Navigation
