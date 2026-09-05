local SphereActions = {}
SphereActions.__index = SphereActions

local L = require("localization")
local function T(key, variables) return L.get(key, variables) end

local SPHERE_ORDER = {
    "PalSphere", "PalSphere_Mega", "PalSphere_Giga", "PalSphere_Tera",
    "PalSphere_Master", "PalSphere_Legend", "PalSphere_Ultimate",
    "PalSphere_Exotic", "PalSphere_Ancient_1", "PalSphere_Ancient_2",
}

function SphereActions.new(options)
    return setmetatable({ options = options or {}, queue = nil }, SphereActions)
end

function SphereActions:itemCount(inventoryData, staticItemId)
    local o = self.options
    if not o.alive(inventoryData) or staticItemId == nil then return 0 end
    local count = 0
    local itemName = FName(tostring(staticItemId))
    local ok = pcall(function()
        count = tonumber(inventoryData:CountItemNum(itemName)) or 0
    end)
    if not ok then return 0 end
    return math.max(0, count)
end

function SphereActions:selectedStaticId(loadout)
    local o = self.options
    if not o.alive(loadout) then return "" end
    local selectedId = nil
    local ok = pcall(function() selectedId = loadout.NowEquipBallItemID end)
    if not ok or selectedId == nil then return "" end
    return o.normalizedName(selectedId)
end

function SphereActions:isSelected(sphereDef)
    local o = self.options
    if sphereDef == nil or sphereDef.sphereId == nil then return false end
    local player = o.getLocalPlayerCharacter()
    local loadout = nil
    if o.alive(player) then
        pcall(function() loadout = player.LoadoutSelectorComponent end)
        if not o.alive(loadout) then
            pcall(function() loadout = player:GetLoadoutSelectorComponent() end)
        end
    end
    if not o.alive(loadout) then return false end
    return self:selectedStaticId(loadout) == o.normalizedName(sphereDef.sphereId)
end

function SphereActions:ownedOrder(inventoryData)
    local o, owned = self.options, {}
    for _, staticId in ipairs(SPHERE_ORDER) do
        if self:itemCount(inventoryData, staticId) > 0 then
            owned[#owned + 1] = o.normalizedName(staticId)
        end
    end
    return owned
end

function SphereActions:count(sphereDef)
    if sphereDef == nil or sphereDef.sphereId == nil then return 0 end
    return self:itemCount(self.options.getLocalInventoryData(), sphereDef.sphereId)
end

function SphereActions:isAvailable(sphereDef)
    return self:count(sphereDef) > 0
end

local function indexOfValue(values, wanted)
    for i, value in ipairs(values or {}) do
        if value == wanted then return i end
    end
    return nil
end

local function chooseDirection(owned, currentId, targetId)
    local count = #owned
    local currentIndex = indexOfValue(owned, currentId)
    local targetIndex = indexOfValue(owned, targetId)
    if count < 2 or currentIndex == nil or targetIndex == nil then return "next" end
    local forward = (targetIndex - currentIndex) % count
    local backward = (currentIndex - targetIndex) % count
    return backward < forward and "previous" or "next"
end

function SphereActions:select(sphereDef, options)
    local o = self.options
    options = type(options) == "table" and options or {}
    if o.cfg("sphereSelectionEnabled", true) ~= true then return false end
    if sphereDef == nil or sphereDef.sphereId == nil then return false end
    local inventoryData = o.getLocalInventoryData()
    local displayName = tostring(sphereDef.sphereName or "Selected sphere")
    if not o.alive(inventoryData)
        or self:itemCount(inventoryData, sphereDef.sphereId) <= 0 then
        if options.notifyMissing ~= false then
            o.showCenterNotification(T("sphereMissingInventory", { sphere = displayName }), true)
        end
        o.log(displayName .. " not in local inventory", true)
        return false
    end
    local player = o.getLocalPlayerCharacter()
    local loadout = nil
    if o.alive(player) then
        pcall(function() loadout = player.LoadoutSelectorComponent end)
        if not o.alive(loadout) then
            pcall(function() loadout = player:GetLoadoutSelectorComponent() end)
        end
    end
    if not o.alive(loadout) then
        o.log("Sphere select failed: LoadoutSelectorComponent unavailable", true)
        return false
    end
    local owned = self:ownedOrder(inventoryData)
    local targetId = o.normalizedName(sphereDef.sphereId)
    local currentId = self:selectedStaticId(loadout)
    if currentId == targetId then
        self.queue = nil
        o.log(displayName .. " already selected"
            .. (options.source and (" by " .. tostring(options.source)) or ""), true)
        return true
    end
    self.queue = {
        loadout = loadout, targetId = targetId, displayName = displayName,
        owned = owned, direction = chooseDirection(owned, currentId, targetId),
        nextAt = os.clock(), attempts = 0,
        maxAttempts = math.max(3, #owned + 2), previousUnavailable = false,
    }
    o.log("Cycling natively to " .. displayName .. " from " .. tostring(currentId)
        .. (options.source and (" by " .. tostring(options.source)) or "")
        .. " via " .. tostring(self.queue.direction), true)
    return true
end

function SphereActions:process()
    local o, request = self.options, self.queue
    if request == nil or os.clock() < request.nextAt then return end
    if not o.alive(request.loadout) then self.queue = nil return end
    local currentId = self:selectedStaticId(request.loadout)
    if currentId == request.targetId then
        o.log("Verified selected sphere: " .. tostring(request.displayName))
        self.queue = nil
        return
    end
    if currentId == "" or request.attempts >= request.maxAttempts then
        o.log("Sphere selection could not be verified for " .. tostring(request.displayName), true)
        self.queue = nil
        return
    end
    local ok, err = false, nil
    if request.direction == "previous" and not request.previousUnavailable then
        ok, err = pcall(function() request.loadout:ChangePrevBallLoadout() end)
        if not ok then
            request.previousUnavailable = true
            request.direction = "next"
            request.maxAttempts = math.max(request.maxAttempts, #request.owned + 2)
            o.log("Previous-sphere function unavailable; using forward cycling", true)
        end
    end
    if request.direction ~= "previous" then
        ok, err = pcall(function() request.loadout:ChangeNextBallLoadout() end)
    end
    if not ok then
        o.log("Native sphere cycling failed: " .. tostring(err), true)
        self.queue = nil
        return
    end
    request.attempts = request.attempts + 1
    request.nextAt = os.clock() + 0.012
end

function SphereActions:clear()
    self.queue = nil
end

return SphereActions
