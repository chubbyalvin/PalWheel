
local Controller = {}
Controller.__index = Controller

local function normalizedKeyName(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^FName%((.*)%)$", "%1")
    text = string.gsub(text, "[^%w]", "")
    return string.lower(text)
end

local function normalizedSet(values)
    local result = {}
    for _, value in ipairs(type(values) == "table" and values or {}) do
        result[normalizedKeyName(value)] = true
    end
    return result
end

local function readAnalog(self, pc, key)
    if not self.o.alive(pc) or key == nil then return nil end
    local ok, value = pcall(function() return pc:GetInputAnalogKeyState(key) end)
    value = ok and tonumber(value) or nil
    if value == nil then return nil end
    return self.o.clamp(value, -1.0, 1.0)
end

function Controller.new(options)
    local self = setmetatable({
        o = options,
        session = false,
        openSawDown = false,
        openLatchDown = false,
        pageWasDown = false,
        axisFailureLogged = false,
        suppressedMappings = {},
        blockedInputKeys = {},
        blockedInputKeyNames = {},
        configuredCancelInputs = {},
        sessionCancelInputs = {},
        cancelInputKeyNames = {},
        cancelWasDown = {},
        gameplayMappingsSuppressed = false,
        gameplayMappingFailureLogged = false,
        inputReleaseGuard = false,
        cameraNeutralGuard = false,
        guardAxisFailureLogged = false,
        peakStickMagnitude = 0.0,
        peakStickSelection = nil,
    }, Controller)

    self.openKeyName = tostring(options.cfg("controllerOpenButton") or "")
    self.pageKeyName = tostring(options.cfg("controllerPageButton") or "")
    self.axisXKeyName = tostring(options.cfg("controllerAxisX") or "")
    self.axisYKeyName = tostring(options.cfg("controllerAxisY") or "")
    self.openKey = options.makeFKey(self.openKeyName)
    self.pageKey = options.makeFKey(self.pageKeyName)
    self.axisXKey = options.makeFKey(self.axisXKeyName)
    self.axisYKey = options.makeFKey(self.axisYKeyName)
    self.openKeyNormalized = normalizedKeyName(self.openKeyName)
    self.pageKeyNormalized = normalizedKeyName(self.pageKeyName)
    self.movementKeyNames = normalizedSet(options.cfg("controllerMovementKeys", {}))
    self.selectionKeyNames = normalizedSet(options.cfg("controllerSelectionAxisKeys"))
    self.selectionKeyNames[normalizedKeyName(self.axisXKeyName)] = true
    self.selectionKeyNames[normalizedKeyName(self.axisYKeyName)] = true
    if self.movementKeyNames[self.openKeyNormalized] then
        options.log("Input conflict: controller Open is also configured as movement; movement pass-through wins", true)
    end
    if self.movementKeyNames[self.pageKeyNormalized] then
        options.log("Input conflict: controller Page is also configured as movement; movement pass-through wins", true)
    end
    for _, name in ipairs(options.cfg("controllerCancelButtons") or {}) do
        local text = tostring(name or "")
        local normalized = normalizedKeyName(text)
        if text ~= "" and normalized ~= self.openKeyNormalized
            and normalized ~= self.pageKeyNormalized
            and self.movementKeyNames[normalized] ~= true
            and self.selectionKeyNames[normalized] ~= true then
            self.configuredCancelInputs[#self.configuredCancelInputs + 1] = {
                name = text,
                normalized = normalized,
                key = options.makeFKey(text),
            }
        end
    end
    self:installAttackGuards()
    return self
end

function Controller:addBlockedInputKey(name, key)
    local normalized = normalizedKeyName(name)
    if normalized == "" or self.blockedInputKeyNames[normalized] == true
        or key == nil then return end
    self.blockedInputKeyNames[normalized] = true
    self.blockedInputKeys[#self.blockedInputKeys + 1] = key
end

function Controller:addSessionCancelInput(name, key)
    local normalized = normalizedKeyName(name)
    if normalized == "" or normalized == self.openKeyNormalized
        or normalized == self.pageKeyNormalized
        or self.movementKeyNames[normalized] == true
        or self.selectionKeyNames[normalized] == true
        or self.cancelInputKeyNames[normalized] == true
        or key == nil then return end
    self.cancelInputKeyNames[normalized] = true
    self.sessionCancelInputs[#self.sessionCancelInputs + 1] = {
        name = tostring(name),
        normalized = normalized,
        key = key,
    }
end

function Controller:seedConfiguredCancelInputs()
    for _, input in ipairs(self.configuredCancelInputs or {}) do
        self:addSessionCancelInput(input.name, input.key)
        self:addBlockedInputKey(input.name, input.key)
    end
end

function Controller:installAttackGuards()
    if type(RegisterHook) ~= "function" then return end

    local function muteTransition(shooter, isShootingParam, canShootOnReleaseParam)
        if (not self.session and not self.gameplayMappingsSuppressed)
            or self.o.cfg("controllerSuppressAllGameplayInput", true) ~= true then
            return
        end
        pcall(function() isShootingParam:set(false) end)
        pcall(function() canShootOnReleaseParam:set(false) end)
        if self.o.alive(shooter) then
            pcall(function() shooter:SetShootingHold(false) end)
        end
    end

    pcall(function()
        RegisterHook("/Script/Pal.PalShooterComponent:ChangeIsShooting_ToServer",
            function(context, _, isShootingParam, canShootOnReleaseParam)
                local shooter = nil
                pcall(function() shooter = context:get() end)
                muteTransition(shooter, isShootingParam, canShootOnReleaseParam)
            end)
    end)
    pcall(function()
        RegisterHook("/Script/Pal.PalPlayerController:ShooterComponent_ChangeIsShooting_ToServer",
            function(_, shooterParam, _, isShootingParam, canShootOnReleaseParam)
                local shooter = nil
                pcall(function() shooter = shooterParam:get() end)
                muteTransition(shooter, isShootingParam, canShootOnReleaseParam)
            end)
    end)
end

function Controller:suppressGameplayMappings(pc)
    self:restoreGameplayMappings()
    self:seedConfiguredCancelInputs()
    if self.o.cfg("controllerSuppressAllGameplayInput", true) ~= true
        or not self.o.alive(pc) then
        return
    end

    local playerInput = nil
    local mappings = nil
    pcall(function() playerInput = pc.PlayerInput end)
    if self.o.alive(playerInput) then
        pcall(function() mappings = playerInput.EnhancedActionMappings end)
    end
    if mappings == nil then
        if not self.gameplayMappingFailureLogged then
            self.gameplayMappingFailureLogged = true
            self.o.log("Controller gameplay mapping suppression unavailable; attack fallback remains active", true)
        end
        return
    end

    local matched = 0
    local ok = pcall(function()
        mappings:ForEach(function(_, element)
            local mapping = element:get()
            if mapping == nil then return end

            local keyText = ""
            pcall(function() keyText = tostring(mapping.Key.KeyName or "") end)
            keyText = string.gsub(keyText, "^FName%((.*)%)$", "%1")
            local keyName = normalizedKeyName(keyText)
            if string.sub(keyName, 1, 7) ~= "gamepad"
                or self.movementKeyNames[keyName] == true then
                return
            end

            local previous = false
            pcall(function() previous = mapping.bShouldBeIgnored == true end)
            local changed = pcall(function() mapping.bShouldBeIgnored = true end)
            local confirmed = false
            pcall(function() confirmed = mapping.bShouldBeIgnored == true end)
            if changed and confirmed then
                self.suppressedMappings[#self.suppressedMappings + 1] = {
                    mapping = mapping,
                    previous = previous,
                }
                if keyText ~= "" then
                    local okKey, key = pcall(self.o.makeFKey, keyText)
                    if okKey and key ~= nil then
                        self:addBlockedInputKey(keyText, key)
                        self:addSessionCancelInput(keyText, key)
                    end
                end
                matched = matched + 1
            end
        end)
    end)

    self.gameplayMappingsSuppressed = ok and matched > 0
    if not self.gameplayMappingsSuppressed and not self.gameplayMappingFailureLogged then
        self.gameplayMappingFailureLogged = true
        self.o.log("Could not mute controller Enhanced Input mappings; attack fallback remains active", true)
    end
end

function Controller:restoreGameplayMappings()
    for _, entry in ipairs(self.suppressedMappings or {}) do
        if entry and entry.mapping ~= nil then
            pcall(function()
                entry.mapping.bShouldBeIgnored = entry.previous == true
            end)
        end
    end
    self.suppressedMappings = {}
    self.blockedInputKeys = {}
    self.blockedInputKeyNames = {}
    self.sessionCancelInputs = {}
    self.cancelInputKeyNames = {}
    self.cancelWasDown = {}
    self.gameplayMappingsSuppressed = false
end

function Controller:anyBlockedInputActive(pc)
    if not self.o.alive(pc) then return false end
    for _, key in ipairs(self.blockedInputKeys or {}) do
        local analog = readAnalog(self, pc, key)
        if analog ~= nil and math.abs(analog) >= 0.10 then return true end
        if self.o.isKeyDown(pc, key) then return true end
    end
    return false
end

function Controller:isCancelInputActive(pc, input)
    if input == nil or input.key == nil then return false end
    if string.find(input.normalized or "", "axis", 1, true) then
        local threshold = self.o.clamp(
            self.o.cfg("controllerCancelAnalogThreshold", 0.18), 0.05, 0.90)
        local analog = readAnalog(self, pc, input.key)
        return analog ~= nil and math.abs(analog) >= threshold
    end
    return self.o.isKeyDown(pc, input.key)
end

function Controller:anyCancelInputActive(pc)
    if not self.o.alive(pc) then return false end
    for _, input in ipairs(self.sessionCancelInputs or {}) do
        if self:isCancelInputActive(pc, input) then return true end
    end
    return false
end

function Controller:primeCancelInputLatches(pc)
    self.cancelWasDown = {}
    for _, input in ipairs(self.sessionCancelInputs or {}) do
        self.cancelWasDown[input.normalized] = self:isCancelInputActive(pc, input)
    end
end

function Controller:newCancelInputPressed(pc)
    local pressedName = nil
    for _, input in ipairs(self.sessionCancelInputs or {}) do
        local down = self:isCancelInputActive(pc, input)
        local wasDown = self.cancelWasDown[input.normalized] == true
        self.cancelWasDown[input.normalized] = down
        if pressedName == nil and down and not wasDown then
            pressedName = input.name
        end
    end
    return pressedName
end

function Controller:isEnabled()
    return self.o.cfg("controllerEnabled", true) == true
end

function Controller:isSession()
    return self.session == true
end

function Controller:isOpenButtonDown(pc)
    return self:isEnabled() and self.o.isKeyDown(pc, self.openKey)
end

function Controller:begin(pc)
    self.session = true
    self.openSawDown = true
    self.openLatchDown = self.o.isKeyDown(pc, self.openKey)
    self.pageWasDown = self.o.isKeyDown(pc, self.pageKey)
    self.axisFailureLogged = false
    self.inputReleaseGuard = false
    self.cameraNeutralGuard = false
    self.guardAxisFailureLogged = false
    self.peakStickMagnitude = 0.0
    self.peakStickSelection = nil
    self:suppressGameplayMappings(pc)
    self:primeCancelInputLatches(pc)
end

function Controller:finish(pc)
    local wasSession = self.session == true
    self.session = false
    self.openSawDown = false
    self.pageWasDown = false
    self.axisFailureLogged = false
    self.peakStickMagnitude = 0.0
    self.peakStickSelection = nil
    if wasSession and self.o.alive(pc) then
        local axisX = readAnalog(self, pc, self.axisXKey)
        local axisY = readAnalog(self, pc, self.axisYKey)
        if axisX ~= nil and axisY ~= nil then
            local deadzone = self.o.clamp(
                self.o.cfg("controllerStickDeadzone", 0.25), 0.05, 0.95)
            self.cameraNeutralGuard = math.sqrt(axisX * axisX + axisY * axisY) >= deadzone
        else
            self.cameraNeutralGuard = false
        end
        self.inputReleaseGuard = self.o.isKeyDown(pc, self.openKey)
            or self.o.isKeyDown(pc, self.pageKey)
            or self:anyBlockedInputActive(pc)
            or self:anyCancelInputActive(pc)
    else
        self.inputReleaseGuard = false
        self.cameraNeutralGuard = false
    end
    if not self.inputReleaseGuard then self:restoreGameplayMappings() end
end

function Controller:reset()
    self.session = false
    self.openSawDown = false
    self.pageWasDown = false
    self.axisFailureLogged = false
    self.inputReleaseGuard = false
    self.cameraNeutralGuard = false
    self.guardAxisFailureLogged = false
    self.peakStickMagnitude = 0.0
    self.peakStickSelection = nil
    self.cancelWasDown = {}
    self:restoreGameplayMappings()
    self.openLatchDown = false
end

function Controller:isCameraNeutralGuardActive()
    return self.cameraNeutralGuard == true
end

function Controller:updateReleaseGuards(pc)
    if self.inputReleaseGuard then
        if not self.o.alive(pc) then
            self.inputReleaseGuard = false
            self:restoreGameplayMappings()
        elseif not self.o.isKeyDown(pc, self.openKey)
            and not self.o.isKeyDown(pc, self.pageKey)
            and not self:anyBlockedInputActive(pc)
            and not self:anyCancelInputActive(pc) then
            self.inputReleaseGuard = false
            self:restoreGameplayMappings()
        end
    end

    if not self.cameraNeutralGuard then return end
    if not self.o.alive(pc) then
        self.cameraNeutralGuard = false
        return
    end

    local axisX = readAnalog(self, pc, self.axisXKey)
    local axisY = readAnalog(self, pc, self.axisYKey)
    if axisX == nil or axisY == nil then
        if not self.guardAxisFailureLogged then
            self.guardAxisFailureLogged = true
            self.o.log("Post-wheel stick guard released because its axes became unavailable", true)
        end
        self.cameraNeutralGuard = false
        return
    end

    local deadzone = self.o.clamp(
        self.o.cfg("controllerStickDeadzone", 0.25), 0.05, 0.95)
    if math.sqrt(axisX * axisX + axisY * axisY) < deadzone then
        self.cameraNeutralGuard = false
        self.guardAxisFailureLogged = false
    end
end

function Controller:updateSelection(pc)
    local axisX = readAnalog(self, pc, self.axisXKey)
    local axisY = readAnalog(self, pc, self.axisYKey)
    if axisX == nil or axisY == nil then
        if not self.axisFailureLogged then
            self.axisFailureLogged = true
            self.o.log("Could not read right-stick axes; controller wheel remains open", true)
        end
        return nil
    end

    if self.o.cfg("controllerInvertY", true) == true then
        axisY = -axisY
    end

    local state = self.o.state
    local magnitude = math.sqrt(axisX * axisX + axisY * axisY)
    local previous = state.selected
    local deadzone = self.o.clamp(
        self.o.cfg("controllerStickDeadzone", 0.25), 0.05, 0.95)
    if type(self.o.updatePointerDirection) == "function" then
        self.o.updatePointerDirection(magnitude >= deadzone
            and math.atan(axisY, axisX) or nil, magnitude, deadzone)
    end
    if magnitude < deadzone then
        state.selected = nil
    else
        local angle = math.atan(axisY, axisX)
        local bestIndex = nil
        local bestDistance = math.huge
        for index = 1, state.visibleSlotCount do
            local slotAngle = math.rad(tonumber(self.o.cfg(
                "wheelSlotOneAngleDegrees", 180)) or 180)
                - ((index - 1) * self.o.twoPi / state.visibleSlotCount)
            local distance = self.o.angularDistance(angle, slotAngle)
            if distance < bestDistance then
                bestDistance = distance
                bestIndex = index
            end
        end
        state.selected = bestIndex
    end

    if previous ~= state.selected then
        local def = state.selected ~= nil
            and self.o.assignmentDefinitionForVisibleIndex(state.selected) or nil
        self.o.previewAssignmentNatively(def, "controller hover")
        self.o.updateHighlight()
    end
    return magnitude
end

function Controller:resetReturnGesture(magnitude)
    self.peakStickMagnitude = 0.0
    self.peakStickSelection = nil
    magnitude = tonumber(magnitude)
    if magnitude ~= nil and self.o.state.selected ~= nil then
        self.peakStickMagnitude = magnitude
        self.peakStickSelection = self.o.state.selected
    end
end

function Controller:shouldActivateOnStickReturn(magnitude)
    if self.o.cfg("controllerEarlyReturnSelect", true) ~= true then return false end
    magnitude = tonumber(magnitude)
    if magnitude == nil then return false end

    local state = self.o.state
    if state.selected ~= nil and magnitude >= self.peakStickMagnitude then
        self.peakStickMagnitude = magnitude
        self.peakStickSelection = state.selected
    end

    local deadzone = self.o.clamp(
        self.o.cfg("controllerStickDeadzone", 0.25), 0.05, 0.95)
    local armMagnitude = self.o.clamp(
        self.o.cfg("controllerEarlyReturnArmMagnitude", 0.60),
        math.min(deadzone + 0.05, 0.95), 1.0)
    if self.peakStickSelection == nil
        or self.peakStickMagnitude < armMagnitude then
        return false
    end

    local returnFraction = self.o.clamp(
        self.o.cfg("controllerEarlyReturnFraction", 0.25), 0.10, 0.70)
    local triggerMagnitude = self.peakStickMagnitude * (1.0 - returnFraction)
    if magnitude > triggerMagnitude then return false end

    state.selected = self.peakStickSelection
    self.o.updateHighlight()
    return true
end

function Controller:captureOpen(pc)
    if not self:isEnabled() or not self.o.alive(pc) then
        self.openLatchDown = false
        return false
    end

    local down = self.o.isKeyDown(pc, self.openKey)
    if self.o.isWheelOpen() then
        self.openLatchDown = down
        return self.session
    end

    if self.o.isEditorOpen() then
        self.openLatchDown = down
        return false
    end

    local pressed = down and not self.openLatchDown
    self.openLatchDown = down
    if not pressed then return false end
    return self.o.openControllerWheel(pc)
end

function Controller:tickOpen(pc)
    if not self.session then return false end

    local cancelInput = self:newCancelInputPressed(pc)
    if cancelInput ~= nil then
        self.o.closeWheel("Controller input " .. tostring(cancelInput)
            .. " cancelled PalWheel")
        return true
    end

    local magnitude = self:updateSelection(pc)

    local pageDown = self.o.isKeyDown(pc, self.pageKey)
    local pageSwitched = false
    if pageDown and not self.pageWasDown then
        self.o.switchActivePage()
        magnitude = self:updateSelection(pc)
        self:resetReturnGesture(magnitude)
        pageSwitched = true
    end
    self.pageWasDown = pageDown

    local down = self.o.isKeyDown(pc, self.openKey)
    if down then self.openSawDown = true end
    self.openLatchDown = down

    if down and not pageSwitched
        and self:shouldActivateOnStickReturn(magnitude) then
        if not self.o.activateSelectedOption("Controller stick return") then
            self.o.closeWheel("Controller stick returned from an empty slot")
        end
        return true
    end

    local grace = self.o.clamp(
        self.o.cfg("releaseGraceSeconds", 0.10), 0.05, 0.40)
    if self.openSawDown and not down
        and (os.clock() - self.o.state.openedAt) >= grace then
        if not self.o.activateSelectedOption("Controller open-button release") then
            self.o.closeWheel("Controller open button released without an assigned selection")
        end
    end
    return true
end

return Controller
