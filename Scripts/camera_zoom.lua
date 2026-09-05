local CameraZoom = {}
CameraZoom.__index = CameraZoom

local WALK_FIELD = "WalkCameraArmLength"
local FLY_FIELD = "FlyCameraArmLength"
local CAMERA_FIELDS = {
    WALK_FIELD,
    "HipShootCameraArmLength",
    "AimCameraArmLength",
    "AirCameraArmLength",
    "AirHipShootCameraArmLength",
    FLY_FIELD,
    "FlyHipShootCameraArmLength",
    "FlyAimCameraArmLength",
    "CrouchCameraArmLength",
    "CrouchHipShootCameraArmLength",
    "CrouchAimCameraArmLength",
    "SlidingCameraArmLength",
    "SlidingHipShootCameraArmLength",
    "SlidingAimCameraArmLength",
}
local TARGET_FIELD = "TargetArmLength"
local INTERP_FIELD = "CameraInterpTime"

local MIN_MULTIPLIER = 0.80
local MAX_MULTIPLIER = 1.50
local DEFAULT_MULTIPLIER = 1.00

local HELD_RATE_PER_SECOND = 1.00
local TRIGGER_DEADZONE = 0.08
local MAX_ZOOM_DT = 0.033333
local HANDOFF_MIN_TIME = 0.20
local HANDOFF_MAX_TIME = 0.70
local HANDOFF_TOLERANCE = 0.50
local HANDOFF_STABLE_FRAMES = 3

local function safeFullName(object)
    if object == nil then return nil end
    local text = nil
    pcall(function() text = object:GetFullName() end)
    if type(text) == "string" and text ~= "" then return text end
    return nil
end

local function safeAddress(object)
    if object == nil then return nil end
    local address = nil
    pcall(function() address = object:GetAddress() end)
    return type(address) == "number" and address or nil
end

local function safeUniqueId(object)
    if object == nil then return nil end
    local value = nil
    pcall(function() value = object:GetUniqueID() end)
    return type(value) == "number" and value or nil
end

function CameraZoom.new(options)
    local self = setmetatable({
        o = options or {},
        multiplier = DEFAULT_MULTIPLIER,
        baselines = {},
        touched = {},
        currentPawn = nil,
        currentPawnAddress = nil,
        currentPawnName = nil,
        currentPawnUniqueId = nil,
        currentArms = {},
        lastTickAt = nil,
        leftTrigger = nil,
        rightTrigger = nil,
        armClass = nil,
        nextClassLookupAt = 0.0,
        nextBroadArmScanAt = 0.0,
        lastAppliedMultiplier = nil,
        nextResolveAttempt = 0.0,
        worldAddress = nil,
        worldObject = nil,
        worldName = nil,
        worldUniqueId = nil,
        realtimeLoopStarted = false,
        realtimeGameCallback = nil,
        realtimeLoopHandle = nil,
        targetOwned = false,
        handoffActive = false,
        handoffStartedAt = nil,
        handoffStableFrames = 0,
        handoffFrames = 0,
    }, CameraZoom)

    if type(self.o.makeFKey) == "function" then
        self.leftTrigger = self.o.makeFKey("Gamepad_LeftTrigger")
        self.rightTrigger = self.o.makeFKey("Gamepad_RightTrigger")
    end
    return self
end

function CameraZoom:getMultiplier()
    return self.multiplier
end

function CameraZoom:isRealtimeLoopStarted()
    return self.realtimeLoopStarted == true
end

function CameraZoom:startRealtimeLoop()
    if self.realtimeLoopStarted == true then return true end
    if type(LoopInGameThreadAfterFrames) ~= "function"
        or EngineTickAvailable ~= true
        or type(self.o.getPlayerController) ~= "function"
        or type(self.o.isZoomEnabled) ~= "function" then
        return false
    end

    self.realtimeGameCallback = function()
        local pc = self.o.getPlayerController()
        self:tick(pc, self.o.isZoomEnabled() == true)
    end
    self.realtimeLoopHandle = LoopInGameThreadAfterFrames(1, self.realtimeGameCallback)
    self.realtimeLoopStarted = self.realtimeLoopHandle ~= nil
    return self.realtimeLoopStarted
end

function CameraZoom:clampMultiplier(value)
    value = tonumber(value) or DEFAULT_MULTIPLIER
    if value < MIN_MULTIPLIER then value = MIN_MULTIPLIER end
    if value > MAX_MULTIPLIER then value = MAX_MULTIPLIER end
    return value
end

function CameraZoom:readNumber(component, field)
    if not self.o.alive(component) then return nil end
    local value = nil
    local ok = pcall(function() value = component[field] end)
    return ok and type(value) == "number" and value or nil
end

function CameraZoom:writeNumber(component, field, value)
    if not self.o.alive(component) or type(value) ~= "number" then return false end
    return pcall(function() component[field] = value end)
end

function CameraZoom:refreshArm(component)
    if not self.o.alive(component) then return false end
    return pcall(function() component:ChangeArmParameter_forBP() end)
end

function CameraZoom:getArmClass()
    if self.o.alive(self.armClass) then return self.armClass end
    local now = os.clock()
    if now < (self.nextClassLookupAt or 0.0) then return nil end
    self.nextClassLookupAt = now + 5.0
    local object = nil
    pcall(function()
        object = StaticFindObject("/Script/Pal.PalShooterSpringArmComponent")
    end)
    if self.o.alive(object) then
        self.armClass = object
        return object
    end
    return nil
end

function CameraZoom:addUnique(list, seen, component)
    if not self.o.alive(component) then return end
    local hasCameraField = false
    for _, field in ipairs(CAMERA_FIELDS) do
        if self:readNumber(component, field) ~= nil then
            hasCameraField = true
            break
        end
    end
    if not hasCameraField then return end
    local address = safeAddress(component)
    local key = address ~= nil and tostring(address) or safeFullName(component)
    if key == nil or seen[key] then return end
    seen[key] = true
    list[#list + 1] = component
end

function CameraZoom:findOwnedCameraArms(pawn, now)
    local result, seen = {}, {}
    if not self.o.alive(pawn) then return result end

    local direct = nil
    pcall(function() direct = pawn.CameraBoom end)
    self:addUnique(result, seen, direct)

    local armClass = self:getArmClass()
    if self.o.alive(armClass) then
        local byClass = nil
        pcall(function() byClass = pawn:GetComponentByClass(armClass) end)
        self:addUnique(result, seen, byClass)
    end

    now = tonumber(now) or os.clock()
    if #result == 0 and now >= (self.nextBroadArmScanAt or 0.0) then
        self.nextBroadArmScanAt = now + 1.0
        local pawnName = safeFullName(pawn)
        local all = nil
        pcall(function() all = FindAllOf("PalShooterSpringArmComponent") end)
        if all ~= nil and pawnName ~= nil then
            for _, component in pairs(all) do
                if self.o.alive(component) then
                    local owner = nil
                    pcall(function() owner = component:GetOwner() end)
                    if self.o.alive(owner) and safeFullName(owner) == pawnName then
                        self:addUnique(result, seen, component)
                    end
                end
            end
        end
    end
    return result
end

function CameraZoom:rememberBaseline(component, field)
    local address = safeAddress(component)
    if address == nil then return nil end
    local fullName = safeFullName(component)
    local uniqueId = safeUniqueId(component)
    local bucket = self.baselines[address]
    local sameObject = type(bucket) == "table"
        and self.o.alive(bucket._component)
        and safeAddress(bucket._component) == address
        and bucket._fullName == fullName
        and (bucket._uniqueId == nil or uniqueId == nil or bucket._uniqueId == uniqueId)
    if not sameObject then
        bucket = {
            _component = component,
            _fullName = fullName,
            _uniqueId = uniqueId,
        }
        self.baselines[address] = bucket
    end
    if bucket[field] == nil then
        local value = self:readNumber(component, field)
        if type(value) ~= "number" then return nil end
        bucket[field] = value
    end
    self.touched[address] = component
    return bucket[field]
end

function CameraZoom:captureCurrentBaselines()
    for _, component in ipairs(self.currentArms) do
        for _, field in ipairs(CAMERA_FIELDS) do
            self:rememberBaseline(component, field)
        end
        self:rememberBaseline(component, INTERP_FIELD)
    end
end

function CameraZoom:applySourceMultiplier(force, refreshNative)
    local multiplier = self.multiplier
    if not force and self.lastAppliedMultiplier ~= nil
        and math.abs(multiplier - self.lastAppliedMultiplier) < 0.000001 then
        return false
    end

    local wroteAny = false
    for _, component in ipairs(self.currentArms) do
        local wroteComponent = false
        for _, field in ipairs(CAMERA_FIELDS) do
            local baseline = self:rememberBaseline(component, field)
            if type(baseline) == "number" then
                if self:writeNumber(component, field, baseline * multiplier) then
                    wroteAny = true
                    wroteComponent = true
                end
            end
        end
        if wroteComponent and refreshNative == true then self:refreshArm(component) end
    end
    self.lastAppliedMultiplier = multiplier
    return wroteAny
end

function CameraZoom:clearTargetBases()
    for _, component in ipairs(self.currentArms or {}) do
        local address = safeAddress(component)
        local bucket = address ~= nil and self.baselines[address] or nil
        if type(bucket) == "table" then bucket._targetBase = nil end
    end
end

function CameraZoom:clearTargetOwnership()
    self.targetOwned = false
    self.handoffActive = false
    self.handoffStartedAt = nil
    self.handoffStableFrames = 0
    self.handoffFrames = 0
    self:clearTargetBases()
end

function CameraZoom:beginTargetOwnership()
    self.handoffActive = false
    self.handoffStartedAt = nil
    self.handoffStableFrames = 0
    self.handoffFrames = 0
    local captured = false
    local divisor = math.abs(self.multiplier) > 0.000001 and self.multiplier or DEFAULT_MULTIPLIER
    for _, component in ipairs(self.currentArms) do
        local address = safeAddress(component)
        local bucket = address ~= nil and self.baselines[address] or nil
        if type(bucket) == "table" then
            local currentTarget = self:readNumber(component, TARGET_FIELD)
            if type(currentTarget) == "number" then
                bucket._targetBase = currentTarget / divisor
                captured = true
            elseif type(bucket[WALK_FIELD]) == "number" then
                bucket._targetBase = bucket[WALK_FIELD]
                captured = true
            end
        end
    end
    self.targetOwned = captured
    return captured
end

function CameraZoom:desiredTarget(component)
    local address = safeAddress(component)
    local bucket = address ~= nil and self.baselines[address] or nil
    if type(bucket) ~= "table" or type(bucket._targetBase) ~= "number" then return nil end
    return bucket._targetBase * self.multiplier
end

function CameraZoom:maintainOwnedTargets()
    if self.targetOwned ~= true then return false end
    local wroteAny = false
    for _, component in ipairs(self.currentArms) do
        local target = self:desiredTarget(component)
        if type(target) == "number" and self:writeNumber(component, TARGET_FIELD, target) then
            wroteAny = true
        end
    end
    return wroteAny
end

function CameraZoom:startHandoff(now)
    if self.targetOwned ~= true then return false end
    self.targetOwned = false
    self.handoffActive = true
    self.handoffStartedAt = tonumber(now) or os.clock()
    self.handoffStableFrames = 0
    self.handoffFrames = 0
    for _, component in ipairs(self.currentArms) do
        self:refreshArm(component)
        local target = self:desiredTarget(component)
        if type(target) == "number" then self:writeNumber(component, TARGET_FIELD, target) end
    end
    return true
end

function CameraZoom:finishHandoff()
    self.handoffActive = false
    self.handoffStartedAt = nil
    self.handoffStableFrames = 0
    self.handoffFrames = 0
    self:clearTargetBases()
end

function CameraZoom:tickHandoff(now)
    if self.handoffActive ~= true then return false end
    local elapsed = math.max(0.0, (tonumber(now) or os.clock()) - (self.handoffStartedAt or 0.0))
    local allStable = #self.currentArms > 0
    self.handoffFrames = self.handoffFrames + 1

    for _, component in ipairs(self.currentArms) do
        local target = self:desiredTarget(component)
        local nativeTarget = self:readNumber(component, TARGET_FIELD)
        if type(target) ~= "number" or type(nativeTarget) ~= "number"
            or math.abs(nativeTarget - target) > HANDOFF_TOLERANCE then
            allStable = false
        end
        if type(target) == "number" then self:writeNumber(component, TARGET_FIELD, target) end
    end

    if allStable and elapsed >= HANDOFF_MIN_TIME then
        self.handoffStableFrames = self.handoffStableFrames + 1
    else
        self.handoffStableFrames = 0
    end

    if self.handoffStableFrames >= HANDOFF_STABLE_FRAMES or elapsed >= HANDOFF_MAX_TIME then
        self:finishHandoff()
        return false
    end
    return true
end

function CameraZoom:restoreAndForgetCurrentArms()
    self:clearTargetOwnership()
    for _, component in ipairs(self.currentArms or {}) do
        local address = safeAddress(component)
        local bucket = address ~= nil and self.baselines[address] or nil
        if self.o.alive(component) and type(bucket) == "table" then
            local wrote = false
            for _, field in ipairs(CAMERA_FIELDS) do
                local baseline = bucket[field]
                if type(baseline) == "number" and self:writeNumber(component, field, baseline) then
                    wrote = true
                end
            end
            local interpBaseline = bucket[INTERP_FIELD]
            if type(interpBaseline) == "number" then
                self:writeNumber(component, INTERP_FIELD, interpBaseline)
            end
            if wrote then self:refreshArm(component) end
        end
        if address ~= nil then
            self.baselines[address] = nil
            self.touched[address] = nil
        end
    end
    self.currentArms = {}
end

function CameraZoom:resolvePawn(pc)
    if not self.o.alive(pc) then return false end
    local pawn = nil
    pcall(function() pawn = pc:GetPawn() end)
    if not self.o.alive(pawn) then pcall(function() pawn = pc.Pawn end) end
    if not self.o.alive(pawn) then return false end

    local now = os.clock()
    local address = safeAddress(pawn)
    local name = safeFullName(pawn)
    local uniqueId = safeUniqueId(pawn)
    local samePawn = address ~= nil and address == self.currentPawnAddress
        and self.o.alive(self.currentPawn)
        and self.currentPawnName == name
        and (self.currentPawnUniqueId == nil or uniqueId == nil
            or self.currentPawnUniqueId == uniqueId)
    if samePawn and #self.currentArms > 0 then
        local anyAlive = false
        for _, component in ipairs(self.currentArms) do
            if self.o.alive(component) then anyAlive = true break end
        end
        if anyAlive then return true end
    end
    if samePawn and now < (self.nextResolveAttempt or 0.0) then return false end

    self:restoreAndForgetCurrentArms()
    self.currentPawn = pawn
    self.currentPawnAddress = address
    self.currentPawnName = name
    self.currentPawnUniqueId = uniqueId
    self.nextBroadArmScanAt = 0.0
    self.currentArms = self:findOwnedCameraArms(pawn, now)
    self.nextResolveAttempt = now + (#self.currentArms > 0 and 1.0 or 0.10)
    self.lastAppliedMultiplier = nil
    self:captureCurrentBaselines()
    self:applySourceMultiplier(true, true)
    return #self.currentArms > 0
end

function CameraZoom:readAnalog(pc, key)
    if not self.o.alive(pc) or key == nil then return 0.0 end
    local value = nil
    local ok = pcall(function() value = pc:GetInputAnalogKeyState(key) end)
    if not ok or type(value) ~= "number" then return 0.0 end
    return value
end

function CameraZoom:realNow(pc)
    if self.o.alive(pc) then
        local world = nil
        pcall(function() world = pc:GetWorld() end)
        if self.o.alive(world) then
            local value = nil
            pcall(function() value = world.RealTimeSeconds end)
            if type(value) == "number" then return value end
        end
    end
    return os.clock()
end

function CameraZoom:adjust(delta, refreshNative)
    delta = tonumber(delta) or 0.0
    if math.abs(delta) < 0.000001 then return false end
    local nextValue = self:clampMultiplier(self.multiplier + delta)
    if math.abs(nextValue - self.multiplier) < 0.000001 then return false end
    self.multiplier = nextValue
    self:applySourceMultiplier(true, refreshNative == true)
    if self.targetOwned then self:maintainOwnedTargets() end
    return true
end

function CameraZoom:pollZoomInput(pc, dt)
    local left = math.max(0.0, self:readAnalog(pc, self.leftTrigger))
    local right = math.max(0.0, self:readAnalog(pc, self.rightTrigger))
    if left < TRIGGER_DEADZONE then left = 0.0 end
    if right < TRIGGER_DEADZONE then right = 0.0 end

    local active = left > 0.0 or right > 0.0
    if active and self.targetOwned ~= true then self:beginTargetOwnership() end

    local triggerDelta = (right - left) * HELD_RATE_PER_SECOND * dt
    if math.abs(triggerDelta) >= 0.000001 then
        self:adjust(triggerDelta, self.targetOwned ~= true)
    end
    if self.targetOwned then self:maintainOwnedTargets() end
    return active
end

function CameraZoom:updateWorldSession(pc)
    if not self.o.alive(pc) then return end
    local world = nil
    pcall(function() world = pc:GetWorld() end)
    if not self.o.alive(world) then return end
    local address = safeAddress(world)
    if address == nil then return end
    local name = safeFullName(world)
    local uniqueId = safeUniqueId(world)
    if self.worldAddress == nil then
        self.worldAddress = address
        self.worldObject = world
        self.worldName = name
        self.worldUniqueId = uniqueId
        return
    end
    local sameWorld = address == self.worldAddress
        and self.o.alive(self.worldObject)
        and self.worldName == name
        and (self.worldUniqueId == nil or uniqueId == nil or self.worldUniqueId == uniqueId)
    if not sameWorld then
        self:restoreTouchedBaselines()
        self.multiplier = DEFAULT_MULTIPLIER
        self.baselines = {}
        self.touched = {}
        self.currentPawn = nil
        self.currentPawnAddress = nil
        self.currentPawnName = nil
        self.currentPawnUniqueId = nil
        self.currentArms = {}
        self.lastAppliedMultiplier = nil
        self.nextResolveAttempt = 0.0
        self.nextBroadArmScanAt = 0.0
        self:clearTargetOwnership()
        self.worldAddress = address
        self.worldObject = world
        self.worldName = name
        self.worldUniqueId = uniqueId
    end
end

function CameraZoom:tick(pc, zoomInputEnabled)
    self:updateWorldSession(pc)

    local now = self:realNow(pc)
    local dt = self.lastTickAt ~= nil and (now - self.lastTickAt) or 0.0
    self.lastTickAt = now
    if dt < 0.0 then dt = 0.0 end
    if dt > MAX_ZOOM_DT then dt = MAX_ZOOM_DT end

    if not self:resolvePawn(pc) then return end

    if zoomInputEnabled == true then
        if self.handoffActive then
            self.handoffActive = false
            self.handoffStartedAt = nil
            self.handoffStableFrames = 0
            self.handoffFrames = 0
        end
        self:pollZoomInput(pc, dt)
    else
        if self.targetOwned then self:startHandoff(now) end
        if self.handoffActive then self:tickHandoff(now) end
    end
end

function CameraZoom:restoreTouchedBaselines()
    self:clearTargetOwnership()
    for address, component in pairs(self.touched) do
        if self.o.alive(component) then
            local bucket = self.baselines[address]
            local wrote = false
            if type(bucket) == "table" then
                for _, field in ipairs(CAMERA_FIELDS) do
                    local baseline = bucket[field]
                    if type(baseline) == "number" and self:writeNumber(component, field, baseline) then
                        wrote = true
                    end
                end
                local interpBaseline = bucket[INTERP_FIELD]
                if type(interpBaseline) == "number" then
                    self:writeNumber(component, INTERP_FIELD, interpBaseline)
                end
            end
            if wrote then self:refreshArm(component) end
        end
    end
end

function CameraZoom:resetSession()
    self:restoreTouchedBaselines()
    self.multiplier = DEFAULT_MULTIPLIER
    self.baselines = {}
    self.touched = {}
    self.currentPawn = nil
    self.currentPawnAddress = nil
    self.currentPawnName = nil
    self.currentPawnUniqueId = nil
    self.currentArms = {}
    self.lastAppliedMultiplier = nil
    self.nextResolveAttempt = 0.0
    self.nextBroadArmScanAt = 0.0
    self:clearTargetOwnership()
    self.worldAddress = nil
    self.worldObject = nil
    self.worldName = nil
    self.worldUniqueId = nil
    self.lastTickAt = nil
end

return CameraZoom
