local InputRuntime = {}
InputRuntime.__index = InputRuntime

local function normalizedKeyName(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^FName%((.*)%)$", "%1")
    text = string.gsub(text, "[^%w]", "")
    return string.lower(text)
end

local function ue4ssKeyEnumName(options, unrealName)
    local name = tostring(unrealName or "")
    local convert = type(options) == "table" and options.cfg or nil
    if type(convert) == "function" then
        local mapped = convert("ue4ssKeyName", nil)
        if type(mapped) == "function" then
            local ok, value = pcall(mapped, name)
            if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
        end
    end
    return string.upper(name)
end

function InputRuntime.new(options)
    local self = setmetatable({ options = options or {} }, InputRuntime)
    self.suppressedMappings = {}
    self.blockedInputKeys = {}
    self.blockedInputKeyNames = {}
    self.sessionCancelInputs = {}
    self.sessionCancelKeyNames = {}
    self.suppressionActive = false
    self.releaseGuard = false
    self.mouseActivationReleaseGuard = false
    self.mouseActivationReleaseEarliest = 0.0
    self.mouseActivationReleaseKey = nil
    self.suppressionFailureLogged = false
    self.settingsCallbacks = {}
    
    
    
    
    self.pendingSettingsEvents = {}
    self.pendingPointerEvents = {}
    self.mouseCallback = function()
        local o = self.options
        if not o.state.open and not o.state.editorOpen then return end
        self.pendingPointerEvents[#self.pendingPointerEvents + 1] = 1
    end
    self.editorCancelCallback = function()
        local o = self.options
        if not o.state.editorOpen then return end
        self.pendingPointerEvents[#self.pendingPointerEvents + 1] = -1
    end
    self.restartGameCallback = function()
        local o, s = self.options, self.options.state
        self:resetSuppression()
        local playerCacheRetained = o.alive(s.cachedPlayer)
        local retainPersistentUi = false
        if not s.open and not s.editorOpen and o.alive(s.widget)
            and type(s.iconRuntime) == "table"
            and type(s.iconRuntime.currentWorldKey) == "function"
            and tostring(s.iconRuntime.worldKey or "") ~= "" then
            local restartPc = o.getPlayerController()
            local okWorld, currentWorldKey = pcall(function()
                return s.iconRuntime:currentWorldKey(restartPc)
            end)
            retainPersistentUi = okWorld and tostring(currentWorldKey or "") ~= ""
                and tostring(currentWorldKey) == tostring(s.iconRuntime.worldKey)
        end
        if not retainPersistentUi then o.destroyWidget() end
        o.destroyCenterNotification()
        s.sessionReady, s.activePalSlot = true, nil
        s.pc = nil
        s.cachedGameInstance, s.cachedFishing = nil, nil
        if not playerCacheRetained then s.cachedPlayer = nil end
        s.playerCacheNextPoll = 0.0
        s.cachedPartyHolder, s.uiStackBaseline, s.uiStackPending = nil, nil, nil
        s.partyCapacityNextPoll = 0.0
        s.uiStackLearned, s.uiStackOpen, s.uiStackUnreadableLogged = false, false, false
        s.uiStackCount, s.uiStackLastX, s.uiStackLastY = nil, nil, nil
        s.uiStackNextPoll, s.idlePc = 0.0, nil
        s.keyboardOpenWasDown, s.keyboardOpenHandledAt = false, 0.0
        s.uiPrebuildReadyAt = retainPersistentUi and math.huge or (os.clock() + 5.0)
        o.log("PlayerController restarted; "
            .. (retainPersistentUi and "same-world persistent UI retained"
                or "stale UI discarded and fresh text-only UI scheduled")
            .. ", player loadout cache "
            .. (playerCacheRetained and "retained" or "unavailable"), true)
    end
    self.restartHookCallback = function()
        ExecuteInGameThread(self.restartGameCallback)
    end
    return self
end

function InputRuntime:registerSettingsBinding()
    local o, s = self.options, self.options.state
    local name = tostring(o.cfg("settingsKey") or "")
    if name == "" then return false, "PalWheel Menu key is empty" end
    local enumName = ue4ssKeyEnumName(o, name)
    local keyValue = Key and Key[enumName] or nil
    if keyValue == nil then
        return false, "UE4SS Key table has no PalWheel Menu key for Unreal FKey " .. name
    end
    s.settingsKeyName, s.settingsKeyValue = name, keyValue
    local callbackId = normalizedKeyName(name)
    if self.settingsCallbacks[callbackId] == nil then
        local registeredName = name
        local callback = function()
            if normalizedKeyName(o.cfg("settingsKey")) ~= normalizedKeyName(registeredName) then
                return
            end
            self.pendingSettingsEvents[#self.pendingSettingsEvents + 1] = registeredName
        end
        self.settingsCallbacks[callbackId] = callback
        RegisterKeyBind(keyValue, callback)
    end
    return true
end

function InputRuntime:drainPointerEvents()
    local handled = false

    
    
    
    if #self.pendingSettingsEvents > 0 then
        local settingsPending = self.pendingSettingsEvents
        self.pendingSettingsEvents = {}
        for _, registeredName in ipairs(settingsPending) do
            local o = self.options
            if normalizedKeyName(o.cfg("settingsKey")) == normalizedKeyName(registeredName) then
                local ok, result = pcall(function()
                    if o.state.open then self:cancel(registeredName)
                    else o.toggleEditor() end
                end)
                if ok then handled = true
                elseif type(o.log) == "function" then
                    o.log("Queued PalWheel Menu event failed: " .. tostring(result), true)
                end
            end
        end
    end

    if #self.pendingPointerEvents == 0 then return handled end

    
    
    
    local pending = self.pendingPointerEvents
    self.pendingPointerEvents = {}
    for _, direction in ipairs(pending) do
        local o = self.options
        if o.state.editorOpen then
            local ok, result = pcall(o.handleEditorClick, direction)
            if ok and result ~= false then handled = true end
            if not ok and type(o.log) == "function" then
                o.log("Queued editor pointer event failed: " .. tostring(result), true)
            end
        elseif o.state.open then
            if direction > 0 then
                local ok, result = pcall(function()
                    if type(o.handleWheelPointerClick) == "function" then
                        return o.handleWheelPointerClick()
                    end
                    return false
                end)
                if ok and result == true then handled = true end
                if not ok and type(o.log) == "function" then
                    o.log("Queued wheel pointer click failed: " .. tostring(result), true)
                end
            else
                local pageIsRightMouse = self:canonicalKeyName(
                    o.cfg("keyboardNextWheelButton"))
                    == self:canonicalKeyName("RightMouseButton")
                if not pageIsRightMouse then
                    self:cancel("RightMouseButton")
                    handled = true
                end
            end
        end
    end
    return handled
end

function InputRuntime:canonicalKeyName(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^FName%((.*)%)$", "%1")
    local converter = self.options.cfg("ue4ssKeyName", nil)
    if type(converter) == "function" then text = converter(text) end
    return normalizedKeyName(text)
end

function InputRuntime:movementKeySet()
    local result = {}
    for _, value in ipairs(self.options.cfg("keyboardMovementKeys", {}) or {}) do
        result[self:canonicalKeyName(value)] = true
    end
    return result
end

function InputRuntime:addBlockedKey(name, key)
    local normalized = self:canonicalKeyName(name)
    if normalized == "" or key == nil or self.blockedInputKeyNames[normalized] then return end
    self.blockedInputKeyNames[normalized] = true
    self.blockedInputKeys[#self.blockedInputKeys + 1] = key
end

function InputRuntime:addSessionCancelInput(name, key, movementKeys)
    local o, normalized = self.options, self:canonicalKeyName(name)
    local openName = self:canonicalKeyName(o.cfg("openKey"))
    local pageName = self:canonicalKeyName(o.cfg("keyboardNextWheelButton"))
    local settingsName = self:canonicalKeyName(o.cfg("settingsKey"))
    local activateName = self:canonicalKeyName(o.cfg("mouseActivateButton"))
    if normalized == "" or key == nil or movementKeys[normalized]
        or normalized == openName or normalized == pageName
        or normalized == settingsName or normalized == activateName
        or self.sessionCancelKeyNames[normalized] then return end
    self.sessionCancelKeyNames[normalized] = true
    self.sessionCancelInputs[#self.sessionCancelInputs + 1] = {
        name = tostring(name), key = key,
    }
end

function InputRuntime:isInputActive(pc, key)
    local o = self.options
    if not o.alive(pc) or key == nil then return false end
    if o.isKeyDown(pc, key) then return true end

    
    
    
    
    local okTime, timeDown = pcall(function() return pc:GetInputKeyTimeDown(key) end)
    if okTime and (tonumber(timeDown) or 0) > 0.0 then return true end

    local ok, value = pcall(function() return pc:GetInputAnalogKeyState(key) end)
    return ok and math.abs(tonumber(value) or 0) >= 0.10
end

function InputRuntime:anyBlockedInputActive(pc)
    for _, key in ipairs(self.blockedInputKeys or {}) do
        if self:isInputActive(pc, key) then return true end
    end
    return false
end

function InputRuntime:restoreSuppression()
    for _, entry in ipairs(self.suppressedMappings or {}) do
        if entry ~= nil and entry.mapping ~= nil then
            pcall(function() entry.mapping.bShouldBeIgnored = entry.previous == true end)
        end
    end
    self.suppressedMappings = {}
    self.blockedInputKeys = {}
    self.blockedInputKeyNames = {}
    self.sessionCancelInputs = {}
    self.sessionCancelKeyNames = {}
    self.suppressionActive = false
    self.releaseGuard = false
    self.mouseActivationReleaseGuard = false
    self.mouseActivationReleaseEarliest = 0.0
    self.mouseActivationReleaseKey = nil
    if type(self.options.setMouseGameplaySuppressed) == "function" then
        pcall(self.options.setMouseGameplaySuppressed, false)
    end
end

function InputRuntime:resetSuppression()
    self:restoreSuppression()
end

function InputRuntime:beginKeyboard(pc)
    local o = self.options
    self:restoreSuppression()
    o.state.keyboardPageWasDown = self:isInputActive(
        pc, o.state.keyboardPageFKey)
    
    
    
    o.state.keyboardPagePressLocked = o.state.keyboardPageWasDown == true
    o.state.keyboardPageReleaseSince = nil
    local movementKeys = self:movementKeySet()
    local openName = self:canonicalKeyName(o.cfg("openKey"))
    local pageName = self:canonicalKeyName(o.cfg("keyboardNextWheelButton"))
    if movementKeys[openName] then
        o.log("Input conflict: keyboard Open is also configured as movement; movement pass-through wins", true)
    end
    if movementKeys[pageName] then
        o.log("Input conflict: keyboard Next Wheel is also configured as movement; movement pass-through wins", true)
    end
    local playerInput, mappings = nil, nil
    pcall(function() playerInput = pc.PlayerInput end)
    if o.alive(playerInput) then
        pcall(function() mappings = playerInput.EnhancedActionMappings end)
    end
    if mappings == nil then
        if not self.suppressionFailureLogged then
            self.suppressionFailureLogged = true
            o.log("Keyboard/mouse gameplay suppression unavailable; cancel detection remains active", true)
        end
        return false
    end

    local matched = 0
    local ok = pcall(function()
        mappings:ForEach(function(_, element)
            local mapping = element:get()
            if mapping == nil then return end
            local keyText = ""
            pcall(function() keyText = tostring(mapping.Key.KeyName or "") end)
            keyText = string.gsub(keyText, "^FName%((.*)%)$", "%1")
            local normalized = self:canonicalKeyName(keyText)
            if normalized == "" or string.sub(normalized, 1, 7) == "gamepad"
                or movementKeys[normalized] then return end

            local previous = false
            pcall(function() previous = mapping.bShouldBeIgnored == true end)
            local changed = pcall(function() mapping.bShouldBeIgnored = true end)
            local confirmed = false
            pcall(function() confirmed = mapping.bShouldBeIgnored == true end)
            if changed and confirmed then
                self.suppressedMappings[#self.suppressedMappings + 1] = {
                    mapping = mapping, previous = previous,
                }
                local okKey, key = pcall(o.makeFKey, keyText)
                if okKey and key ~= nil then
                    self:addBlockedKey(keyText, key)
                    self:addSessionCancelInput(keyText, key, movementKeys)
                end
                matched = matched + 1
            end
        end)
    end)
    self.suppressionActive = ok and matched > 0
    if not self.suppressionActive and not self.suppressionFailureLogged then
        self.suppressionFailureLogged = true
        o.log("Could not mute keyboard/mouse Enhanced Input mappings; cancel detection remains active", true)
    elseif self.suppressionActive then
        o.log("Keyboard/mouse gameplay mappings suppressed except configured movement keys", true)
    end
    return self.suppressionActive
end

function InputRuntime:armMouseActivationReleaseGuard(pc)
    local o = self.options
    local key = o.state.mouseActivateFKey
    if key == nil then
        local ok, value = pcall(o.makeFKey, o.state.mouseActivateKeyName or "LeftMouseButton")
        if ok then key = value end
    end
    self.mouseActivationReleaseGuard = true
    self.mouseActivationReleaseEarliest = os.clock() + 0.08
    self.mouseActivationReleaseKey = key
    if key ~= nil then
        self:addBlockedKey(o.state.mouseActivateKeyName or "LeftMouseButton", key)
    end
end

function InputRuntime:finishKeyboard(pc)
    self.options.state.keyboardPageWasDown = false
    self.options.state.keyboardPagePressLocked = false
    self.options.state.keyboardPageReleaseSince = nil
    if not self.suppressionActive and not self.mouseActivationReleaseGuard then return end
    self.suppressionActive = false
    self.releaseGuard = self.mouseActivationReleaseGuard or self:anyBlockedInputActive(pc)
    if not self.releaseGuard then self:restoreSuppression() end
end

function InputRuntime:beginEditorKeyboardIsolation(pc)
    local o = self.options
    self:restoreSuppression()
    local playerInput, mappings = nil, nil
    pcall(function() playerInput = pc.PlayerInput end)
    if o.alive(playerInput) then
        pcall(function() mappings = playerInput.EnhancedActionMappings end)
    end
    if mappings == nil then
        o.log("Editor cannot isolate keyboard menu actions", true)
        return false
    end
    local matched = 0
    local ok = pcall(function()
        mappings:ForEach(function(_, element)
            local mapping = element:get()
            if mapping == nil then return end
            local keyText = ""
            pcall(function() keyText = tostring(mapping.Key.KeyName or "") end)
            local normalized = self:canonicalKeyName(keyText)
            if normalized == "" or string.sub(normalized, 1, 7) == "gamepad" then
                return
            end
            local previous = false
            pcall(function() previous = mapping.bShouldBeIgnored == true end)
            local changed = pcall(function() mapping.bShouldBeIgnored = true end)
            local confirmed = false
            pcall(function() confirmed = mapping.bShouldBeIgnored == true end)
            if changed and confirmed then
                self.suppressedMappings[#self.suppressedMappings + 1] = {
                    mapping = mapping, previous = previous,
                }
                local okKey, key = pcall(o.makeFKey, keyText)
                if okKey and key ~= nil then self:addBlockedKey(keyText, key) end
                matched = matched + 1
            end
        end)
    end)
    self.suppressionActive = ok and matched > 0
    if self.suppressionActive then
        o.log("Keyboard menu mappings isolated while PalWheel editor is open", true)
    else
        o.log("PalWheel editor could not isolate keyboard menu mappings", true)
    end
    return self.suppressionActive
end

function InputRuntime:beginEditorControllerUiIsolation(pc)
    
    
    
    
    
    self:restoreSuppression()
    self.suppressionActive = false
    return true
end

function InputRuntime:beginEditorControllerCapture(pc)
    local isolated = self:beginEditorKeyboardIsolation(pc)
    if not isolated then
        self.options.log("Controller binding capture continuing without keyboard mapping isolation", true)
    end
    
    
    return true
end

function InputRuntime:endEditorControllerCapture()
    self:restoreSuppression()
end

function InputRuntime:updateReleaseGuard(pc)
    if not self.releaseGuard then return end
    if not self.options.alive(pc) then
        self:restoreSuppression()
        return
    end

    if self.mouseActivationReleaseGuard then
        if os.clock() < (self.mouseActivationReleaseEarliest or 0.0) then return end
        local key = self.mouseActivationReleaseKey
        if key ~= nil and self:isInputActive(pc, key) then return end
        self.mouseActivationReleaseGuard = false
        self.mouseActivationReleaseKey = nil
        self.mouseActivationReleaseEarliest = 0.0
    end

    if not self:anyBlockedInputActive(pc) then
        self:restoreSuppression()
    end
end

function InputRuntime:cancel(inputName)
    local o = self.options
    if not o.state.open then return false end
    local pc = o.state.pc
    o.closeWheel(tostring(inputName or "Other input")
        .. " cancelled PalWheel without activating a slot")
    o.flushPressedKeys(pc)
    return true
end

function InputRuntime:pollKeyboardWheel(pc)
    local o = self.options

    
    
    if type(o.pollHybridDirectShortcut) == "function"
        and o.pollHybridDirectShortcut(pc) == true then
        return true
    end

    local pageDown = self:isInputActive(pc, o.state.keyboardPageFKey)
    local pageJustPressed, pageJustReleased = false, false
    if o.alive(pc) and o.state.keyboardPageFKey ~= nil then
        local okPressed, pressed = pcall(function()
            return pc:WasInputKeyJustPressed(o.state.keyboardPageFKey)
        end)
        if okPressed and type(pressed) == "boolean" then
            pageJustPressed = pressed == true
        end
        local okReleased, released = pcall(function()
            return pc:WasInputKeyJustReleased(o.state.keyboardPageFKey)
        end)
        if okReleased and type(released) == "boolean" then
            pageJustReleased = released == true
        end
    end

    
    
    
    
    if o.state.keyboardPagePressLocked == true then
        if pageJustReleased then
            o.state.keyboardPagePressLocked = false
            o.state.keyboardPageReleaseSince = nil
        elseif not pageDown then
            if o.state.keyboardPageReleaseSince == nil then
                o.state.keyboardPageReleaseSince = os.clock()
            elseif (os.clock() - o.state.keyboardPageReleaseSince) >= 0.12 then
                o.state.keyboardPagePressLocked = false
                o.state.keyboardPageReleaseSince = nil
            end
        else
            o.state.keyboardPageReleaseSince = nil
        end
    end

    
    
    
    
    local pagePressed = pageJustPressed
        or (pageDown and o.state.keyboardPageWasDown ~= true)

    
    
    
    o.state.keyboardPageWasDown = pageDown
    if o.state.keyboardPagePressLocked ~= true and pagePressed
        and o.cfg("keyboardNextWheelButtonSwitchesWheel", true) == true then
        o.state.keyboardPagePressLocked = true
        o.state.keyboardPageReleaseSince = nil
        o.enforcePageAimSuppression()
        local okSwitch, switchResult = pcall(o.switchActivePage)
        if not okSwitch then
            o.log("Next Wheel page switch failed: " .. tostring(switchResult), true)
        end
    end

    for _, input in ipairs(o.state.keyboardCancelInputs or {}) do
        local down = o.isKeyDown(pc, input.key)
        local wasDown = o.state.keyboardCancelWasDown[input.name] == true
        o.state.keyboardCancelWasDown[input.name] = down
        if o.state.keyboardMovementKeyNames[input.name] ~= true and down and not wasDown then
            self:cancel(input.name)
            return true
        end
    end
    for _, input in ipairs(self.sessionCancelInputs or {}) do
        local down = self:isInputActive(pc, input.key)
        local latchName = "session:" .. normalizedKeyName(input.name)
        local wasDown = o.state.keyboardCancelWasDown[latchName] == true
        o.state.keyboardCancelWasDown[latchName] = down
        if down and not wasDown then
            self:cancel(input.name)
            return true
        end
    end

    local controllerMagnitude = nil
    if type(o.controllerSelectionMagnitude) == "function" then
        controllerMagnitude = tonumber(o.controllerSelectionMagnitude(pc))
    end
    local controllerDeadzone = o.clamp(
        o.cfg("controllerStickDeadzone", 0.60), 0.05, 0.95)

    if controllerMagnitude ~= nil and controllerMagnitude >= controllerDeadzone
        and type(o.updateSelectionFromController) == "function" then
        local rememberedMousePresentation = type(o.isMousePresentationRemembered) == "function"
            and o.isMousePresentationRemembered() == true
        if (o.state.mousePointerMode == true or rememberedMousePresentation)
            and type(o.setMousePointerMode) == "function" then
            o.setMousePointerMode(false)
        end
        o.state.hybridControllerSelectionActive = true
        o.updateSelectionFromController(pc)
    else
        o.updateSelectionFromCursor(pc)
        if o.state.mousePointerMode == true then
            o.state.hybridControllerSelectionActive = false
        end
    end

    
    
    
    if o.state.hybridControllerSelectionActive == true
        and controllerMagnitude ~= nil
        and type(o.controllerShouldActivateOnStickReturn) == "function"
        and o.controllerShouldActivateOnStickReturn(controllerMagnitude) then
        if not o.activateSelectedOption("Hybrid controller stick return") then
            o.state.hybridControllerSelectionActive = false
        end
        return true
    end

    
    
    
    local down = self:isInputActive(pc, o.state.openFKey)
    local wasDown = o.state.keyboardOpenWasDown == true
    o.state.keyboardOpenWasDown = down
    local toggleBehavior = string.lower(tostring(
        o.cfg("openWheelBehavior", "hold"))) == "toggle"

    if toggleBehavior then
        if down and not wasDown then
            o.state.keyboardToggleCloseArmed = true
        end
        if o.state.keyboardToggleCloseArmed and wasDown and not down then
            o.state.keyboardToggleCloseArmed = false
            o.closeWheel("Keyboard Open Wheel toggle release closed without activation")
            return true
        end
        return false
    end

    if down then o.state.openKeySawDown = true end
    local grace = o.clamp(o.cfg("releaseGraceSeconds", 0.10), 0.05, 0.40)
    if o.state.openKeySawDown and not down
        and (os.clock() - o.state.openedAt) >= grace then
        o.closeWheel("Open key released without activation")
        return true
    end
    return false
end

function InputRuntime:applyBindings(pc)
    local o, s = self.options, self.options.state
    local settingsOk, settingsError = self:registerSettingsBinding()
    if not settingsOk then return false, settingsError end
    s.openKeyName = tostring(o.cfg("openKey") or "")
    if s.openKeyName == "" then return false, "Open Wheel key is empty" end
    s.openUnrealKeyName = s.openKeyName
    s.openFKey = o.makeFKey(s.openUnrealKeyName)
    s.keyboardPageKeyName = tostring(o.cfg("keyboardNextWheelButton") or "")
    if s.keyboardPageKeyName == "" then return false, "Next Wheel key is empty" end
    s.keyboardPageFKey = o.makeFKey(s.keyboardPageKeyName)

    s.keyboardCancelInputs = {}
    s.keyboardCancelRegistered, s.keyboardMovementKeyNames = {}, {}
    for _, movementName in ipairs(o.cfg("keyboardMovementKeys", {}) or {}) do
        s.keyboardMovementKeyNames[normalizedKeyName(movementName)] = true
    end
    for _, configuredName in ipairs(o.cfg("keyboardCancelKeys") or {}) do
        local cancelKeyName = tostring(configuredName or "")
        local cancelId = normalizedKeyName(cancelKeyName)
        local reserved = cancelId == "" or cancelId == normalizedKeyName(s.openKeyName)
            or cancelId == normalizedKeyName(s.keyboardPageKeyName)
            or cancelId == normalizedKeyName(s.settingsKeyName)
            or cancelId == normalizedKeyName(s.mouseActivateKeyName)
        if not reserved and s.keyboardCancelRegistered[cancelId] ~= true then
            s.keyboardCancelRegistered[cancelId] = true
            s.keyboardCancelInputs[#s.keyboardCancelInputs + 1] = {
                name = cancelKeyName, key = o.makeFKey(cancelKeyName),
            }
        end
    end
    s.keyboardOpenWasDown = o.alive(pc) and o.isKeyDown(pc, s.openFKey) or false
    s.keyboardToggleOpenArmed = false
    s.keyboardToggleCloseArmed = false
    s.keyboardPageWasDown = o.alive(pc)
        and self:isInputActive(pc, s.keyboardPageFKey) or false
    s.keyboardPagePressLocked = s.keyboardPageWasDown == true
    s.keyboardPageReleaseSince = nil
    return true
end

function InputRuntime:register()
    local o, s = self.options, self.options.state
    s.mouseActivateKeyName = tostring(o.cfg("mouseActivateButton") or "")
    local okMouseFKey, mouseFKey = pcall(o.makeFKey, s.mouseActivateKeyName)
    s.mouseActivateFKey = okMouseFKey and mouseFKey or nil
    local mouseActivateEnum = ue4ssKeyEnumName(o, s.mouseActivateKeyName)
    s.mouseActivateKeyValue = Key and Key[mouseActivateEnum] or nil
    if s.mouseActivateKeyValue ~= nil then RegisterKeyBind(s.mouseActivateKeyValue, self.mouseCallback)
    else o.log("WARNING: Key table has no mouseActivateButton named "
        .. tostring(s.mouseActivateKeyName), true) end

    local bindingsOk, bindingsError = self:applyBindings(o.getPlayerController())
    if not bindingsOk then
        o.log("FATAL: " .. tostring(bindingsError), true)
        return false
    end

    local rightMouseValue = Key and Key.RIGHT_MOUSE_BUTTON or nil
    if rightMouseValue ~= nil and rightMouseValue ~= s.mouseActivateKeyValue then
        RegisterKeyBind(rightMouseValue, self.editorCancelCallback)
    end
    return true
end

function InputRuntime:registerRestartHook()
    local ok, err = pcall(function()
        RegisterHook("/Script/Engine.PlayerController:ClientRestart", self.restartHookCallback)
    end)
    if not ok then
        self.options.log("PlayerController restart hook unavailable: " .. tostring(err), true)
        return false
    end
    return true
end

return InputRuntime
