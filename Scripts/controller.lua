
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
        toggleOpenArmed = false,
        toggleCloseArmed = false,
        pageWasDown = false,
        menuKeyName = tostring(options.cfg("controllerPalWheelMenuButton") or "Gamepad_RightThumbstick"),
        menuKey = options.makeFKey(tostring(options.cfg("controllerPalWheelMenuButton") or "Gamepad_RightThumbstick")),
        menuWasDown = false,
        axisFailureLogged = false,
        configuredCancelInputs = {},
        sessionCancelInputs = {},
        cancelInputKeyNames = {},
        cancelWasDown = {},
        cameraNeutralGuard = false,
        guardAxisFailureLogged = false,
        peakStickMagnitude = 0.0,
        peakStickSelection = nil,
        directInputs = {},
        directKeyNames = {},
        directWasDown = {},
    }, Controller)

    self.axisXKeyName = tostring(options.cfg("controllerAxisX") or "")
    self.axisYKeyName = tostring(options.cfg("controllerAxisY") or "")
    self.axisXKey = options.makeFKey(self.axisXKeyName)
    self.axisYKey = options.makeFKey(self.axisYKeyName)
    self.movementKeyNames = normalizedSet(options.cfg("controllerMovementKeys", {}))
    self.selectionKeyNames = normalizedSet(options.cfg("controllerSelectionAxisKeys"))
    self.selectionKeyNames[normalizedKeyName(self.axisXKeyName)] = true
    self.selectionKeyNames[normalizedKeyName(self.axisYKeyName)] = true
    for _, mapping in ipairs(options.directShortcutButtons or {}) do
        local name = tostring(mapping.key or "")
        local normalized = normalizedKeyName(name)
        if name ~= "" and normalized ~= "" and self.directKeyNames[normalized] ~= true then
            self.directKeyNames[normalized] = true
            self.directInputs[#self.directInputs + 1] = {
                name = name,
                normalized = normalized,
                slot = math.floor(tonumber(mapping.slot) or 0),
                auxWheel = math.floor(tonumber(mapping.auxWheel) or 0),
                auxSlot = math.floor(tonumber(mapping.auxSlot) or 0),
                key = options.makeFKey(name),
            }
        end
    end
    self:rebind()
    return self
end

function Controller:rebuildConfiguredCancelInputs()
    local options = self.o
    self.configuredCancelInputs = {}
    if self.movementKeyNames[self.openKeyNormalized] then
        options.log("Input conflict: controller Open is also configured as movement; movement pass-through wins", true)
    end
    if self.movementKeyNames[self.pageKeyNormalized] then
        options.log("Input conflict: controller Next Wheel is also configured as movement; movement pass-through wins", true)
    end
    if self.movementKeyNames[self.menuKeyNormalized] then
        options.log("Input conflict: controller PalWheel Menu is also configured as movement; movement pass-through wins", true)
    end
    for _, name in ipairs(options.cfg("controllerCancelButtons") or {}) do
        local text = tostring(name or "")
        local normalized = normalizedKeyName(text)
        if text ~= "" and normalized ~= self.openKeyNormalized
            and normalized ~= self.pageKeyNormalized
            and normalized ~= self.menuKeyNormalized
            and self.movementKeyNames[normalized] ~= true
            and self.selectionKeyNames[normalized] ~= true then
            self.configuredCancelInputs[#self.configuredCancelInputs + 1] = {
                name = text,
                normalized = normalized,
                key = options.makeFKey(text),
            }
        end
    end
end

function Controller:rebind(pc)
    local options = self.o
    self.openKeyName = tostring(options.cfg("controllerOpenButton") or "")
    self.pageKeyName = tostring(options.cfg("controllerNextWheelButton") or "")
    self.openKey = options.makeFKey(self.openKeyName)
    self.pageKey = options.makeFKey(self.pageKeyName)
    self.menuKeyName = tostring(options.cfg("controllerPalWheelMenuButton") or "Gamepad_RightThumbstick")
    self.menuKey = options.makeFKey(self.menuKeyName)
    self.openKeyNormalized = normalizedKeyName(self.openKeyName)
    self.pageKeyNormalized = normalizedKeyName(self.pageKeyName)
    self.menuKeyNormalized = normalizedKeyName(self.menuKeyName)
    self:rebuildConfiguredCancelInputs()
    self:clearCancelInputs()
    self.toggleOpenArmed = false
    self.toggleCloseArmed = false
    self.openLatchDown = options.alive(pc) and options.isKeyDown(pc, self.openKey) or false
    self.pageWasDown = options.alive(pc) and options.isKeyDown(pc, self.pageKey) or false
    self.menuWasDown = options.alive(pc) and options.isKeyDown(pc, self.menuKey) or false
    return self.openKeyName ~= "" and self.pageKeyName ~= "" and self.menuKeyName ~= ""
end


function Controller:addSessionCancelInput(name, key)
    local normalized = normalizedKeyName(name)
    if normalized == "" or normalized == self.openKeyNormalized
        or normalized == self.pageKeyNormalized
        or normalized == self.menuKeyNormalized
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
    end
end


function Controller:prepareCancelInputs()
    self.sessionCancelInputs = {}
    self.cancelInputKeyNames = {}
    self.cancelWasDown = {}
    self:seedConfiguredCancelInputs()
end

function Controller:clearCancelInputs()
    self.sessionCancelInputs = {}
    self.cancelInputKeyNames = {}
    self.cancelWasDown = {}
end

function Controller:isCancelInputActive(pc, input)
    if input == nil or input.key == nil then return false end
    local threshold = self.o.clamp(
        self.o.cfg("controllerCancelAnalogThreshold", 0.18), 0.05, 0.90)
    if string.find(input.normalized or "", "axis", 1, true) then
        local analog = readAnalog(self, pc, input.key)
        return analog ~= nil and math.abs(analog) >= threshold
    end
    if self.o.isKeyDown(pc, input.key) then return true end
    local analog = readAnalog(self, pc, input.key)
    return analog ~= nil and math.abs(analog) >= 0.50
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
        local reserved = type(self.o.isReservedCancelInput) == "function"
            and self.o.isReservedCancelInput(input.name) == true
        if not reserved and pressedName == nil and down and not wasDown then
            pressedName = input.name
        end
    end
    return pressedName
end

function Controller:primeDirectInputLatches(pc)
    self.directWasDown = {}
    for _, input in ipairs(self.directInputs or {}) do
        self.directWasDown[input.normalized] = self:isCancelInputActive(pc, input)
    end
end

function Controller:newDirectInputPressed(pc)
    local pressed = nil
    for _, input in ipairs(self.directInputs or {}) do
        local down = self:isCancelInputActive(pc, input)
        local wasDown = self.directWasDown[input.normalized] == true
        self.directWasDown[input.normalized] = down
        if pressed == nil and down and not wasDown then pressed = input end
    end
    return pressed
end

function Controller:isEnabled()
    return self.o.cfg("controllerEnabled", true) == true
end

function Controller:isToggleOpenMode()
    return string.lower(tostring(self.o.cfg("openWheelBehavior", "hold")))
        == "toggle"
end

function Controller:isSession()
    return self.session == true
end

function Controller:begin(pc)
    self.session = true
    self.openSawDown = not self:isToggleOpenMode()
    self.toggleOpenArmed = false
    self.toggleCloseArmed = false
    self.openLatchDown = self.o.isKeyDown(pc, self.openKey)
    self.pageWasDown = self.o.isKeyDown(pc, self.pageKey)
    self.menuWasDown = self.o.isKeyDown(pc, self.menuKey)
    self.axisFailureLogged = false
    self.cameraNeutralGuard = false
    self.guardAxisFailureLogged = false
    self.peakStickMagnitude = 0.0
    self.peakStickSelection = nil
    self:prepareCancelInputs()
    self:primeCancelInputLatches(pc)
    self:primeDirectInputLatches(pc)
    if type(self.o.setWheelInputSuppressed) == "function" then
        self.o.setWheelInputSuppressed(true)
    end
end

function Controller:finish(pc)
    local wasSession = self.session == true
    if type(self.o.setWheelInputSuppressed) == "function" then
        self.o.setWheelInputSuppressed(false)
    end
    self.session = false
    self.openSawDown = false
    self.toggleOpenArmed = false
    self.toggleCloseArmed = false
    self.pageWasDown = false
    self.menuWasDown = false
    self.axisFailureLogged = false
    self.peakStickMagnitude = 0.0
    self.peakStickSelection = nil

    if wasSession and self.o.alive(pc) then
        local axisX = readAnalog(self, pc, self.axisXKey)
        local axisY = readAnalog(self, pc, self.axisYKey)
        if axisX ~= nil and axisY ~= nil then
            local deadzone = self.o.clamp(
                self.o.cfg("controllerStickDeadzone", 0.60), 0.05, 0.95)
            self.cameraNeutralGuard = math.sqrt(axisX * axisX + axisY * axisY) >= deadzone
        else
            self.cameraNeutralGuard = false
        end
    else
        self.cameraNeutralGuard = false
    end

    self:clearCancelInputs()
    self.directWasDown = {}
end

function Controller:reset()
    if type(self.o.setWheelInputSuppressed) == "function" then
        self.o.setWheelInputSuppressed(false)
    end
    self.session = false
    self.openSawDown = false
    self.toggleOpenArmed = false
    self.toggleCloseArmed = false
    self.pageWasDown = false
    self.menuWasDown = false
    self.axisFailureLogged = false
    self.cameraNeutralGuard = false
    self.guardAxisFailureLogged = false
    self.peakStickMagnitude = 0.0
    self.peakStickSelection = nil
    self.cancelWasDown = {}
    self.directWasDown = {}
    self:clearCancelInputs()
    self.openLatchDown = false
end


function Controller:isCameraNeutralGuardActive()
    return self.cameraNeutralGuard == true
end

function Controller:updateReleaseGuards(pc)
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
        self.o.cfg("controllerStickDeadzone", 0.60), 0.05, 0.95)
    if math.sqrt(axisX * axisX + axisY * axisY) < deadzone then
        self.cameraNeutralGuard = false
        self.guardAxisFailureLogged = false
    end
end

function Controller:selectionMagnitude(pc)
    local axisX = readAnalog(self, pc, self.axisXKey)
    local axisY = readAnalog(self, pc, self.axisYKey)
    if axisX == nil or axisY == nil then return nil end
    return math.sqrt(axisX * axisX + axisY * axisY)
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
        self.o.cfg("controllerStickDeadzone", 0.60), 0.05, 0.95)
    if type(self.o.updatePointerDirection) == "function" then
        self.o.updatePointerDirection(magnitude >= deadzone
            and math.atan(axisY, axisX) or nil, magnitude, deadzone)
    end
    if magnitude < deadzone then
        state.selected = nil
    else
        local angle = math.atan(axisY, axisX)
        local visibleCount = type(self.o.visibleSlotCount) == "function"
            and tonumber(self.o.visibleSlotCount()) or nil
        visibleCount = math.floor(self.o.clamp(
            visibleCount or 12, 4, 12))

        if type(self.o.selectionIndexForAngle) == "function" then
            
            
            
            state.selected = self.o.selectionIndexForAngle(angle, visibleCount)
        else
            local bestIndex = nil
            local bestDistance = math.huge
            for index = 1, visibleCount do
                local slotAngle = math.rad(tonumber(self.o.cfg(
                    "wheelSlotOneAngleDegrees", 180)) or 180)
                    - ((index - 1) * self.o.twoPi / visibleCount)
                local distance = self.o.angularDistance(angle, slotAngle)
                if distance < bestDistance then
                    bestDistance = distance
                    bestIndex = index
                end
            end
            state.selected = bestIndex
        end
    end

    if previous ~= state.selected then
        local def = state.selected ~= nil
            and self.o.assignmentDefinitionForVisibleIndex(state.selected) or nil
        self.o.previewAssignmentNatively(def, "controller hover")
        local pulseAllowed = type(self.o.shouldPulseHighlight) ~= "function"
            or self.o.shouldPulseHighlight(def, state.selected) == true
        if state.selected ~= nil and pulseAllowed
            and type(self.o.pulseHighlight) == "function" then
            self.o.pulseHighlight(pc, state.selected)
        end
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
        self.o.cfg("controllerStickDeadzone", 0.60), 0.05, 0.95)
    local armMagnitude = deadzone
    if self.peakStickSelection == nil
        or self.peakStickMagnitude < armMagnitude then
        return false
    end

    local returnDistance = self.o.clamp(
        self.o.cfg("controllerEarlyReturnDistance", 0.15), 0.05, 0.40)
    local activateMagnitude = math.max(0.0, self.peakStickMagnitude - returnDistance)
    if magnitude > activateMagnitude then return false end

    state.selected = self.peakStickSelection
    self.o.updateHighlight()
    return true
end

function Controller:captureOpen(pc)
    if not self:isEnabled() or not self.o.alive(pc) then
        self.openLatchDown = false
        self.toggleOpenArmed = false
        return false
    end

    local down = self.o.isKeyDown(pc, self.openKey)
    if self.o.isWheelOpen() then
        self.openLatchDown = down
        return self.session
    end

    if self.o.isEditorOpen() then
        self.openLatchDown = down
        self.toggleOpenArmed = false
        return false
    end

    local wasDown = self.openLatchDown == true
    self.openLatchDown = down

    if self:isToggleOpenMode() then
        if down and not wasDown then
            self.toggleOpenArmed = true
            return false
        end
        if self.toggleOpenArmed and wasDown and not down then
            self.toggleOpenArmed = false
            return self.o.openControllerWheel(pc)
        end
        return false
    end

    self.toggleOpenArmed = false
    local pressed = down and not wasDown
    if not pressed then return false end
    return self.o.openControllerWheel(pc)
end

function Controller:leaveMousePointerMode()
    local active = type(self.o.isMousePointerMode) == "function"
        and self.o.isMousePointerMode() == true
    local remembered = type(self.o.isMousePresentationRemembered) == "function"
        and self.o.isMousePresentationRemembered() == true
    if (active or remembered) and type(self.o.setMousePointerMode) == "function" then
        
        
        self.o.setMousePointerMode(false)
    end
end

function Controller:tickOpen(pc)
    if not self.session then return false end

    
    
    if type(self.o.updateMousePointerSelection) == "function" then
        self.o.updateMousePointerSelection(pc)
    end

    local menuDown = self.o.isKeyDown(pc, self.menuKey)
    local menuPressed = menuDown and not self.menuWasDown
    self.menuWasDown = menuDown
    local menuAllowed = type(self.o.canOpenPalWheelMenu) ~= "function"
        or self.o.canOpenPalWheelMenu() == true
    if menuAllowed and menuPressed and type(self.o.openPalWheelMenuFromWheel) == "function" then
        self:leaveMousePointerMode()
        self.o.openPalWheelMenuFromWheel(pc, self.menuKeyName)
        return true
    end

    
    
    
    local pageDown = self.o.isKeyDown(pc, self.pageKey)
    local pageAllowed = type(self.o.canSwitchPage) ~= "function"
        or self.o.canSwitchPage() == true
    if pageAllowed and pageDown and not self.pageWasDown then
        self.pageWasDown = pageDown
        self.directWasDown[self.pageKeyNormalized] = true
        self:leaveMousePointerMode()
        self.o.switchActivePage()
        local magnitude = self:updateSelection(pc)
        self:resetReturnGesture(magnitude)
        return true
    end
    self.pageWasDown = pageDown

    local directInput = self:newDirectInputPressed(pc)
    if directInput ~= nil and type(self.o.activateDirectShortcut) == "function" then
        self:leaveMousePointerMode()
        if self.o.activateDirectShortcut(directInput.auxWheel, directInput.auxSlot, directInput.name) then
            self.cancelWasDown[directInput.normalized] = true
            return true
        end
    end

    local cancelInput = self:newCancelInputPressed(pc)
    if cancelInput ~= nil then
        self:leaveMousePointerMode()
        self.o.closeWheel("Controller input " .. tostring(cancelInput)
            .. " cancelled PalWheel")
        return true
    end

    local controllerDeadzone = self.o.clamp(
        self.o.cfg("controllerStickDeadzone", 0.60), 0.05, 0.95)
    local rawMagnitude = self:selectionMagnitude(pc)
    local pointerMode = type(self.o.isMousePointerMode) == "function"
        and self.o.isMousePointerMode() == true
    local magnitude = rawMagnitude
    if rawMagnitude ~= nil and rawMagnitude >= controllerDeadzone then
        
        
        
        self:leaveMousePointerMode()
        pointerMode = false
    end
    if not pointerMode then
        magnitude = self:updateSelection(pc)
    end

    local pageSwitched = false

    local down = self.o.isKeyDown(pc, self.openKey)
    local wasDown = self.openLatchDown == true
    if down then self.openSawDown = true end
    self.openLatchDown = down

    if self:isToggleOpenMode() then
        if down and not wasDown then
            self.toggleCloseArmed = true
        end

        if self.toggleCloseArmed then
            if wasDown and not down then
                self.toggleCloseArmed = false
                self.o.closeWheel("Controller Open second press released; wheel closed without activation")
            end
            return true
        end

        if not pointerMode and not pageSwitched and self:shouldActivateOnStickReturn(magnitude) then
            if not self.o.activateSelectedOption("Controller stick return") then
                self.o.closeWheel("Controller stick returned from an empty slot")
            end
            return true
        end
        return true
    end

    if down and not pointerMode and not pageSwitched
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
        if pointerMode then
            self.o.closeWheel("Controller Open button released while mouse pointer mode was active")
        elseif not self.o.activateSelectedOption("Controller open-button release") then
            self.o.closeWheel("Controller open button released without an assigned selection")
        end
    end
    return true
end

return Controller
