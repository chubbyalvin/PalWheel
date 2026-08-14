local InputRuntime = {}
InputRuntime.__index = InputRuntime

local function normalizedKeyName(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^FName%((.*)%)$", "%1")
    text = string.gsub(text, "[^%w]", "")
    return string.lower(text)
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
    self.suppressionFailureLogged = false
    self.openCallback = function()
        ExecuteInGameThread(function() self:handleOpenPressed() end)
    end
    self.settingsCallback = function()
        ExecuteInGameThread(function()
            local o = self.options
            if o.state.open then self:cancel(o.state.settingsKeyName)
            else o.toggleEditor() end
        end)
    end
    self.mouseCallback = function()
        local o = self.options
        if not o.state.open and not o.state.editorOpen then return end
        ExecuteInGameThread(function()
            if o.state.editorOpen then o.handleEditorClick(1)
            else self:cancel(o.state.mouseActivateKeyName) end
        end)
    end
    self.pageCallback = function()
        local o = self.options
        if not o.state.open and not o.state.editorOpen then return end
        ExecuteInGameThread(function()
            if o.state.editorOpen then o.handleEditorClick(-1)
            elseif o.state.open and o.cfg("keyboardPageButtonSwitchesPage", true) == true then
                o.enforcePageAimSuppression()
                o.switchActivePage()
            end
        end)
    end
    self.restartGameCallback = function()
        local o, s = self.options, self.options.state
        self:resetSuppression()
        o.destroyWidget()
        o.destroyCenterNotification()
        s.sessionReady, s.activePalSlot = true, nil
        s.cachedGameInstance, s.cachedFishing, s.cachedPlayer = nil, nil, nil
        s.cachedPartyHolder, s.uiStackBaseline, s.uiStackPending = nil, nil, nil
        s.uiStackLearned, s.uiStackOpen, s.uiStackUnreadableLogged = false, false, false
        s.uiStackCount, s.uiStackLastX, s.uiStackLastY = nil, nil, nil
        s.uiStackNextPoll, s.idlePc = 0.0, nil
        s.keyboardOpenWasDown, s.keyboardOpenHandledAt = false, 0.0
        s.uiPrebuildReadyAt = os.clock() + 5.0
        o.log("PlayerController restarted; stale UI discarded and fresh text-only UI scheduled", true)
    end
    self.restartHookCallback = function()
        ExecuteInGameThread(self.restartGameCallback)
    end
    return self
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
    local pageName = self:canonicalKeyName(o.cfg("keyboardPageButton"))
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
end

function InputRuntime:resetSuppression()
    self:restoreSuppression()
end

function InputRuntime:beginKeyboard(pc)
    local o = self.options
    self:restoreSuppression()
    local movementKeys = self:movementKeySet()
    local openName = self:canonicalKeyName(o.cfg("openKey"))
    local pageName = self:canonicalKeyName(o.cfg("keyboardPageButton"))
    if movementKeys[openName] then
        o.log("Input conflict: keyboard Open is also configured as movement; movement pass-through wins", true)
    end
    if movementKeys[pageName] then
        o.log("Input conflict: keyboard Page is also configured as movement; movement pass-through wins", true)
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

function InputRuntime:finishKeyboard(pc)
    if not self.suppressionActive then return end
    self.suppressionActive = false
    self.releaseGuard = self:anyBlockedInputActive(pc)
    if not self.releaseGuard then self:restoreSuppression() end
end

function InputRuntime:updateReleaseGuard(pc)
    if not self.releaseGuard then return end
    if not self.options.alive(pc) or not self:anyBlockedInputActive(pc) then
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

function InputRuntime:handleOpenPressed()
    local o = self.options
    if os.clock() < o.state.ignoreOpenBindUntil then return end
    local pc = o.getPlayerController()
    if o.state.editorOpen then return end
    if o.state.open and o.state.controller ~= nil and o.state.controller:isSession() then
        self:cancel(o.cfg("openKey"))
        return
    end
    if not o.state.open then
        if string.upper(tostring(o.cfg("openKey") or ""))
            == string.upper(tostring(o.cfg("keyboardToggleStateKey") or "")) then
            o.state.keyboardToggleRestorePending = true
        end
        if not o.openWheel(pc, "keyboard") then o.queueKeyboardToggleRestore() end
        return
    end
    if (os.clock() - o.state.openedAt) >= 0.25 then
        local visibleCount = type(o.visibleSlotCount) == "function"
            and tonumber(o.visibleSlotCount()) or tonumber(o.cfg("visibleSlotCount", 12)) or 12
        if o.state.selected ~= nil and o.state.selected >= 1
            and o.state.selected <= visibleCount then
            if not o.activateSelectedOption("Open-key fallback press") then
                o.closeWheel("Fallback open-key press closed the wheel")
            end
        else
            o.closeWheel("Fallback open-key press closed the wheel")
        end
    end
end

function InputRuntime:pollKeyboardWheel(pc)
    local o = self.options
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
    o.updateSelectionFromCursor(pc)
    local down = o.isKeyDown(pc, o.state.openFKey)
    if down then o.state.openKeySawDown = true end
    local grace = o.clamp(o.cfg("releaseGraceSeconds", 0.10), 0.05, 0.40)
    if o.state.openKeySawDown and not down
        and (os.clock() - o.state.openedAt) >= grace then
        local visibleCount = type(o.visibleSlotCount) == "function"
            and tonumber(o.visibleSlotCount()) or tonumber(o.cfg("visibleSlotCount", 12)) or 12
        if o.state.selected ~= nil and o.state.selected >= 1
            and o.state.selected <= visibleCount then
            if not o.activateSelectedOption("Open-key release") then
                o.closeWheel("Open key released over an empty slot")
            end
        else
            o.closeWheel("Open key released without a selection")
        end
        return true
    end
    return false
end

function InputRuntime:register()
    local o, s = self.options, self.options.state
    s.openKeyName = string.upper(tostring(o.cfg("openKey") or ""))
    if s.openKeyName == "" then o.log("FATAL: mappings.lua has no openKey", true) return false end
    s.openUnrealKeyName = s.openKeyName
    if type(o.cfg("unrealFKeyName", nil)) == "function" then
        s.openUnrealKeyName = o.cfg("unrealFKeyName")(s.openKeyName)
    end
    s.openFKey = o.makeFKey(s.openUnrealKeyName)
    s.keyValue = Key and Key[s.openKeyName] or nil
    if s.keyValue == nil then
        o.log("FATAL: Key table has no entry named " .. s.openKeyName, true)
        return false
    end
    RegisterKeyBind(s.keyValue, self.openCallback)

    s.settingsKeyName = string.upper(tostring(o.cfg("settingsKey") or ""))
    s.settingsKeyValue = Key and Key[s.settingsKeyName] or nil
    if s.settingsKeyValue ~= nil then RegisterKeyBind(s.settingsKeyValue, self.settingsCallback)
    else o.log("WARNING: Key table has no settingsKey named " .. tostring(s.settingsKeyName), true) end

    s.mouseActivateKeyName = string.upper(tostring(o.cfg("mouseActivateButton") or ""))
    s.mouseActivateKeyValue = Key and Key[s.mouseActivateKeyName] or nil
    if s.mouseActivateKeyValue ~= nil then RegisterKeyBind(s.mouseActivateKeyValue, self.mouseCallback)
    else o.log("WARNING: Key table has no mouseActivateButton named "
        .. tostring(s.mouseActivateKeyName), true) end

    s.keyboardPageKeyName = string.upper(tostring(o.cfg("keyboardPageButton") or ""))
    s.keyboardPageKeyValue = Key and Key[s.keyboardPageKeyName] or nil
    if s.keyboardPageKeyValue ~= nil then RegisterKeyBind(s.keyboardPageKeyValue, self.pageCallback)
    else o.log("WARNING: Key table has no keyboardPageButton named " .. s.keyboardPageKeyName
        .. "; keyboard wheel switching and picker cancel are unavailable", true) end

    s.keyboardCancelRegistered, s.keyboardMovementKeyNames = {}, {}
    for _, movementName in ipairs(o.cfg("keyboardMovementKeys", {}) or {}) do
        s.keyboardMovementKeyNames[string.upper(tostring(movementName or ""))] = true
    end
    for _, configuredName in ipairs(o.cfg("keyboardCancelKeys") or {}) do
        local cancelKeyName = string.upper(tostring(configuredName or ""))
        local reserved = cancelKeyName == "" or cancelKeyName == s.openKeyName
            or cancelKeyName == s.keyboardPageKeyName or cancelKeyName == s.settingsKeyName
            or cancelKeyName == s.mouseActivateKeyName
        if not reserved and Key and Key[cancelKeyName] ~= nil
            and s.keyboardCancelRegistered[cancelKeyName] ~= true then
            s.keyboardCancelRegistered[cancelKeyName] = true
            local unrealName = cancelKeyName
            if type(o.cfg("unrealFKeyName", nil)) == "function" then
                unrealName = o.cfg("unrealFKeyName")(cancelKeyName)
            end
            s.keyboardCancelInputs[#s.keyboardCancelInputs + 1] = {
                name = cancelKeyName, key = o.makeFKey(unrealName),
            }
        end
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
