local ControllerHaptics = {}
ControllerHaptics.__index = ControllerHaptics

local ACTION_START = 0
local ACTION_STOP = 2
local LATENT_UUID = 1346459464

function ControllerHaptics.new(options)
    return setmetatable({
        o = options or {},
        active = false,
        availableLogged = false,
        failureLogged = false,
        lastPulseAt = -math.huge,
    }, ControllerHaptics)
end

function ControllerHaptics:latentInfo(pc)
    return {
        Linkage = 0,
        UUID = LATENT_UUID,
        ExecutionFunction = FName("None"),
        CallbackTarget = pc,
    }
end

function ControllerHaptics:pulse(pc, slot)
    local o = self.o
    local level = math.floor(o.clamp(tonumber(
        o.cfg("controllerHighlightHapticsLevel", 3)) or 3, 0, 3))
    if level == 0 or not o.alive(pc) then return false end

    local now = os.clock()
    local minimumInterval = o.clamp(
        o.cfg("controllerHighlightHapticsMinIntervalSeconds", 0.025),
        0.0, 0.25)
    if now - self.lastPulseAt < minimumInterval then return false end

    local intensities = { 0.06, 0.14, 0.22 }
    local intensity = intensities[level]
    local duration = o.clamp(
        o.cfg("controllerHighlightHapticsDurationSeconds", 0.035),
        0.005, 0.15)
    local dilation = 1.0
    if type(o.effectiveTimeDilation) == "function" then
        dilation = o.clamp(tonumber(o.effectiveTimeDilation()) or 1.0, 0.01, 1.0)
    end
    duration = o.clamp(duration * dilation, 0.001, 0.15)

    local ok, why = pcall(function()
        pc:PlayDynamicForceFeedback(
            intensity, duration,
            true, true, true, true,
            ACTION_START, self:latentInfo(pc))
    end)
    if not ok then
        if not self.failureLogged then
            self.failureLogged = true
            o.log("Controller highlight haptics unavailable: " .. tostring(why), true)
        end
        return false
    end

    self.lastPulseAt = now
    self.active = true
    if not self.availableLogged then
        self.availableLogged = true
        o.log("Controller highlight haptics started successfully", true)
    end
    o.log("Controller highlight haptic level " .. tostring(level)
        .. " pulse requested for slot " .. tostring(slot), false)
    return true
end

function ControllerHaptics:stop(pc)
    if not self.active then return false end
    self.active = false
    if not self.o.alive(pc) then return false end
    return pcall(function()
        pc:PlayDynamicForceFeedback(
            0.0, 0.0,
            true, true, true, true,
            ACTION_STOP, self:latentInfo(pc))
    end)
end

function ControllerHaptics:reset(pc)
    self:stop(pc)
    self.lastPulseAt = -math.huge
    self.failureLogged = false
end

return ControllerHaptics
