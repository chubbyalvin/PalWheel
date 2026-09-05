local SphereFollowTarget = {}
SphereFollowTarget.__index = SphereFollowTarget

local BLUEPRINT_PATHS = {
    "/Game/Pal/Blueprint/Weapon/BP_ThrowWeaponBase.BP_ThrowWeaponBase_C:IsEnableAutoAim",
    "/Game/Pal/Blueprint/Weapon/BP_SphereLauncher.BP_SphereLauncher_C:IsEnableAutoAim",
    "/Game/Pal/Blueprint/Weapon/BP_SphereLauncher_OneShot.BP_SphereLauncher_OneShot_C:IsEnableAutoAim",
    "/Game/Pal/Blueprint/Weapon/BP_HomingSphereLauncher.BP_HomingSphereLauncher_C:IsEnableAutoAim",
}
local BASE_PATH = "/Script/Pal.PalWeaponBase:IsEnableAutoAim"

local function unwrap(value)
    if value == nil then return nil end
    local ok, got = pcall(function() return value:get() end)
    if ok and got ~= nil then return got end
    return value
end

local function validObject(object)
    object = unwrap(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

local function fullName(object)
    object = unwrap(object)
    if not validObject(object) then return "" end
    local ok, name = pcall(function() return object:GetFullName() end)
    return ok and name ~= nil and tostring(name) or ""
end

local function isSphereWeapon(object)
    local name = string.lower(fullName(object))
    return name:find("bp_palsphere", 1, true) ~= nil
        or name:find("spherelauncher", 1, true) ~= nil
end

local function retryDelay(attempt)
    attempt = tonumber(attempt) or 1
    if attempt <= 10 then return 0.50 end
    if attempt <= 20 then return 2.0 end
    return 10.0
end

function SphereFollowTarget.new(options)
    options = options or {}
    return setmetatable({
        o = options,
        registered = {},
        retryAttempts = {},
        retryAt = {},
        blueprintCallbacks = {},
        basePreCallback = nil,
        basePostCallback = nil,
        readyLogged = false,
    }, SphereFollowTarget)
end

function SphereFollowTarget:enabled()
    if type(self.o.isEnabled) ~= "function" then return false end
    local ok, enabled = pcall(self.o.isEnabled)
    return ok and enabled == true
end

function SphereFollowTarget:canAttempt(path)
    return os.clock() >= (self.retryAt[path] or 0.0)
end

function SphereFollowTarget:recordFailure(path)
    local attempt = (self.retryAttempts[path] or 0) + 1
    self.retryAttempts[path] = attempt
    self.retryAt[path] = os.clock() + retryDelay(attempt)
end

function SphereFollowTarget:markRegistered(path, preId, postId)
    self.registered[path] = { preId = preId, postId = postId }
    self.retryAttempts[path] = nil
    self.retryAt[path] = nil
end

function SphereFollowTarget:registerBlueprint(path)
    if self.registered[path] then return true end
    if not self:canAttempt(path) then return false end
    if self.blueprintCallbacks[path] == nil then
        self.blueprintCallbacks[path] = function(context)
            if self:enabled() then return true end
            return nil
        end
    end
    local ok, preId, postId = pcall(RegisterHook, path, self.blueprintCallbacks[path])
    if ok and (type(preId) == "number" or type(postId) == "number") then
        self:markRegistered(path, preId, postId)
        return true
    end
    self:recordFailure(path)
    return false, preId or postId
end

function SphereFollowTarget:registerBase()
    if self.registered[BASE_PATH] then return true end
    if not self:canAttempt(BASE_PATH) then return false end
    if self.basePreCallback == nil then self.basePreCallback = function() end end
    if self.basePostCallback == nil then
        self.basePostCallback = function(context)
            if self:enabled() and isSphereWeapon(context) then return true end
            return nil
        end
    end
    local ok, preId, postId = pcall(RegisterHook, BASE_PATH,
        self.basePreCallback, self.basePostCallback)
    if ok and (type(preId) == "number" or type(postId) == "number") then
        self:markRegistered(BASE_PATH, preId, postId)
        return true
    end
    self:recordFailure(BASE_PATH)
    return false, preId or postId
end

function SphereFollowTarget:ensureHooks()
    if type(RegisterHook) ~= "function" then return false end
    local count = 0
    for _, path in ipairs(BLUEPRINT_PATHS) do
        if self.registered[path] or self:registerBlueprint(path) then count = count + 1 end
    end
    if self.registered[BASE_PATH] or self:registerBase() then count = count + 1 end

    if count == #BLUEPRINT_PATHS + 1 then
        if not self.readyLogged and type(self.o.log) == "function" then
            self.readyLogged = true
            self.o.log("Sphere Follow Target native auto-aim hooks ready (Mode 2 implementation)", true)
        end
        return true
    end
    return false
end

function SphereFollowTarget:tick()
    if self.readyLogged then return end
    self:ensureHooks()
end

return SphereFollowTarget
