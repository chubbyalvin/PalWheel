local ControllerHaptics = {}
ControllerHaptics.__index = ControllerHaptics

local ACTION_START = 0
local ACTION_STOP = 2
local LATENT_UUID = 1346459464
local INTENSITY = 0.14
local DURATION_SECONDS = 0.035
local MINIMUM_INTERVAL_SECONDS = 0.025

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
    if o.cfg("controllerHighlightHapticsEnabled", true) ~= true
        or not o.alive(pc) then
        return false
    end
    local now = os.clock()
    if now - self.lastPulseAt < MINIMUM_INTERVAL_SECONDS then return false end
    local dilation = 1.0
    if type(o.effectiveTimeDilation) == "function" then
        dilation = o.clamp(tonumber(o.effectiveTimeDilation()) or 1.0, 0.01, 1.0)
    end
    local duration = o.clamp(DURATION_SECONDS * dilation, 0.001, 0.15)
    local ok, why = pcall(function()
        pc:PlayDynamicForceFeedback(
            INTENSITY, duration,
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
    o.log("Controller highlight haptic pulse requested for slot "
        .. tostring(slot), false)
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
