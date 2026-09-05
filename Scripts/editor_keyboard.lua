local EditorKeyboard = {}
EditorKeyboard.__index = EditorKeyboard

local MODIFIER_NAMES = {
    LeftControl = "ctrl",
    RightControl = "ctrl",
    LeftShift = "shift",
    RightShift = "shift",
    LeftAlt = "alt",
    RightAlt = "alt",
}

local function cleanName(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^FName%((.*)%)$", "%1")
    text = string.gsub(text, '^"(.*)"$', "%1")
    return text
end

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function()
        if type(value.get) == "function" then return value:get() end
        return value
    end)
    if ok and result ~= nil then return result end
    return value
end

function EditorKeyboard.new(options)
    return setmetatable({
        o = options or {},
        order = {},
        installed = false,
        available = false,
        downPreId = nil,
        downPostId = nil,
        upPreId = nil,
        upPostId = nil,
        downCallback = nil,
        upCallback = nil,
        modifiers = { ctrl = false, shift = false, alt = false },
        kismetInput = nil,
        extractFailureLogged = false,
    }, EditorKeyboard)
end

function EditorKeyboard:log(message)
    if type(self.o.log) == "function" then self.o.log(message, true) end
end

function EditorKeyboard:isCaptureActive()
    local state = self.o.state
    return state ~= nil and state.editorOpen == true
        and state.editorCaptureDevice == "keyboard"
end

function EditorKeyboard:sameWidget(context)
    local state = self.o.state
    if state == nil or state.widget == nil then return false end
    local source = unwrap(context)
    if source == state.widget then return true end
    local sourceAddress, widgetAddress = nil, nil
    pcall(function() sourceAddress = source:GetAddress() end)
    pcall(function() widgetAddress = state.widget:GetAddress() end)
    return sourceAddress ~= nil and widgetAddress ~= nil
        and sourceAddress == widgetAddress
end

function EditorKeyboard:getKismetInputLibrary()
    if self.kismetInput ~= nil then return self.kismetInput end
    local finder = self.o.cls
    if type(finder) == "function" then
        local ok, value = pcall(finder, "/Script/Engine.Default__KismetInputLibrary")
        if ok and value ~= nil then self.kismetInput = value end
    end
    if self.kismetInput == nil and type(StaticFindObject) == "function" then
        local ok, value = pcall(StaticFindObject, "/Script/Engine.Default__KismetInputLibrary")
        if ok and value ~= nil then self.kismetInput = value end
    end
    return self.kismetInput
end

function EditorKeyboard:keyNameFromKey(key)
    key = unwrap(key)
    if key == nil then return "" end
    local name = nil
    pcall(function() name = key.KeyName end)
    if name ~= nil then return cleanName(name) end
    local text = cleanName(key)
    local embedded = string.match(text, "KeyName%s*=%s*FName%((.-)%)")
        or string.match(text, "KeyName%s*=%s*([^,%}%s]+)")
    return embedded or text
end

function EditorKeyboard:keyNameFromEvent(eventParam)
    local event = unwrap(eventParam)
    local lib = self:getKismetInputLibrary()
    if lib ~= nil then
        local key = nil
        local ok = pcall(function() key = lib:KeyEvent_GetKey(event) end)
        if not ok or key == nil then
            ok = pcall(function() key = lib:KeyEvent_GetKey(eventParam) end)
        end
        if ok and key ~= nil then
            local name = self:keyNameFromKey(key)
            if name ~= "" then return name end
        end
    end

    local key = nil
    pcall(function() key = event.Key end)
    if key == nil then pcall(function() key = event.InKey end) end
    if key ~= nil then
        local name = self:keyNameFromKey(key)
        if name ~= "" then return name end
    end
    return ""
end

function EditorKeyboard:eventFlag(eventParam, methodName, fallback)
    local lib = self:getKismetInputLibrary()
    if lib ~= nil then
        local event = unwrap(eventParam)
        local value = nil
        local ok = pcall(function() value = lib[methodName](lib, event) end)
        if not ok then
            ok = pcall(function() value = lib[methodName](lib, eventParam) end)
        end
        if ok and value ~= nil then return value == true end
    end
    return fallback == true
end

function EditorKeyboard:canonicalName(unrealName)
    
    return cleanName(unrealName)
end

function EditorKeyboard:updateModifier(name, down)
    local modifier = MODIFIER_NAMES[name]
    if modifier ~= nil then self.modifiers[modifier] = down == true end
    return modifier ~= nil
end

function EditorKeyboard:queue(name, ctrl, shift, alt)
    if not self:isCaptureActive() then return end
    local event = {
        name = name,
        ctrl = ctrl == true,
        shift = shift == true,
        alt = alt == true,
    }
    self.order[#self.order + 1] = event
end

function EditorKeyboard:handleHook(context, eventParam, down)
    if not self:isCaptureActive() then return end
    if not self:sameWidget(context) then return end

    local unrealName = self:keyNameFromEvent(eventParam)
    if unrealName == "" then
        if not self.extractFailureLogged then
            self.extractFailureLogged = true
            self:log("UMG editor keyboard hook fired but FKey extraction failed")
        end
        return
    end
    local name = self:canonicalName(unrealName)
    if name == "" then return end

    if self:updateModifier(name, down) then return end
    if not down then return end

    local ctrl = self:eventFlag(eventParam, "InputEvent_IsControlDown", self.modifiers.ctrl)
    local shift = self:eventFlag(eventParam, "InputEvent_IsShiftDown", self.modifiers.shift)
    local alt = self:eventFlag(eventParam, "InputEvent_IsAltDown", self.modifiers.alt)
    self:queue(name, ctrl, shift, alt)
end

function EditorKeyboard:register()
    if self.installed then return self.available end
    self.installed = true
    if type(RegisterHook) ~= "function" then
        self:log("UMG editor keyboard bridge unavailable: RegisterHook missing")
        return false
    end

    self.downCallback = function(context, _, eventParam)
        self:handleHook(context, eventParam, true)
    end
    self.upCallback = function(context, _, eventParam)
        self:handleHook(context, eventParam, false)
    end

    local okDown, downPre, downPost = pcall(RegisterHook,
        "/Script/UMG.UserWidget:OnKeyDown", self.downCallback)
    local okUp, upPre, upPost = pcall(RegisterHook,
        "/Script/UMG.UserWidget:OnKeyUp", self.upCallback)
    if okDown then self.downPreId, self.downPostId = downPre, downPost end
    if okUp then self.upPreId, self.upPostId = upPre, upPost end
    self.available = okDown == true and downPre ~= nil
    if self.available then
        self:log("Editor keyboard UMG bridge installed: 1 OnKeyDown hook"
            .. (okUp and " + 1 OnKeyUp hook" or "; modifier key-up hook unavailable"))
    else
        self:log("Editor keyboard UMG bridge unavailable: UserWidget OnKeyDown hook registration failed")
    end
    return self.available
end

function EditorKeyboard:isAvailable()
    return self.available == true
end

function EditorKeyboard:clear()
    self.order = {}
    self.modifiers = { ctrl = false, shift = false, alt = false }
end

function EditorKeyboard:drain(handler)
    if type(handler) ~= "function" or #self.order == 0 then return false end
    local events = self.order
    self.order = {}
    local handled = false
    for _, event in ipairs(events) do
        local ok, result = pcall(handler, event.name,
            event.ctrl, event.shift, event.alt)
        if ok and result == true then handled = true end
    end
    return handled
end

return EditorKeyboard
