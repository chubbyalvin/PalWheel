local MercyAccessory = {}
MercyAccessory.__index = MercyAccessory

local L = require("localization")
local function T(key, variables) return L.get(key, variables) end

local MERCY_ITEM_PRIORITY = {
    accessorynonkchecker1 = 1,
    accessorynonkilling = 2,
}

local function unwrapArrayElement(element)
    if element == nil then return nil end
    local ok, value = pcall(function() return element:get() end)
    if ok and value ~= nil then return value end
    return element
end

function MercyAccessory.new(deps)
    deps = deps or {}
    return setmetatable({
        state = deps.state,
        cfg = deps.cfg,
        alive = deps.alive,
        getPlayerController = deps.getPlayerController,
        normalizedName = deps.normalizedName,
        colors = deps.colors or {},
        log = deps.log,
    }, MercyAccessory)
end

function MercyAccessory:_log(message, important)
    if type(self.log) == "function" then
        self.log(message, important)
    end
end

function MercyAccessory:_getLocalInventoryData()
    local state = self.state or {}
    local pc = state.pc
    if not self.alive(pc) then pc = self.getPlayerController() end
    if not self.alive(pc) then return nil end

    local playerState = nil
    local okState = pcall(function() playerState = pc:GetPalPlayerState() end)
    if not okState or not self.alive(playerState) then
        pcall(function() playerState = pc.PlayerState end)
    end
    if not self.alive(playerState) then return nil end

    local inventoryData = nil
    local okInventory = pcall(function() inventoryData = playerState:GetInventoryData() end)
    if not okInventory or not self.alive(inventoryData) then return nil end
    return inventoryData
end

function MercyAccessory:getLocalInventoryData()
    return self:_getLocalInventoryData()
end

function MercyAccessory:_slotStaticId(slot)
    if not self.alive(slot) then return "" end
    local itemId = nil
    local ok = pcall(function() itemId = slot:GetItemId() end)
    if not ok or itemId == nil then return "" end

    local staticId = nil
    pcall(function() staticId = itemId.StaticId end)
    return self.normalizedName(staticId)
end

function MercyAccessory:_scanSlots(inventoryData)
    local equippedCandidates = {}
    local inventoryCandidates = {}
    local helper = nil
    pcall(function() helper = inventoryData.InventoryMultiHelper end)
    if not self.alive(helper) then
        return equippedCandidates, inventoryCandidates, "InventoryMultiHelper unavailable"
    end

    local containers = nil
    pcall(function() containers = helper.Containers end)
    if containers == nil then
        return equippedCandidates, inventoryCandidates, "inventory container list unavailable"
    end

    local okIterate, iterateErr = pcall(function()
        containers:ForEach(function(_, rawContainer)
            local container = unwrapArrayElement(rawContainer)
            if not self.alive(container) then return end

            local count = 0
            local okCount, value = pcall(function() return container:Num() end)
            if okCount then count = tonumber(value) or 0 end
            if count <= 0 or count > 500 then return end

            for index = 0, count - 1 do
                local slot = nil
                pcall(function() slot = container:Get(index) end)
                if self.alive(slot) then
                    local empty = true
                    pcall(function() empty = slot:IsEmpty() == true end)
                    if not empty then
                        local id = self:_slotStaticId(slot)
                        local priority = MERCY_ITEM_PRIORITY[id]
                        if priority ~= nil then
                            local isEquipped = false
                            pcall(function() isEquipped = inventoryData:IsEquipSlot(slot) == true end)
                            local entry = { slot = slot, id = id, priority = priority }
                            if isEquipped then
                                equippedCandidates[#equippedCandidates + 1] = entry
                            else
                                inventoryCandidates[#inventoryCandidates + 1] = entry
                            end
                        end
                    end
                end
            end
        end)
    end)

    if not okIterate then
        return equippedCandidates, inventoryCandidates, tostring(iterateErr)
    end
    table.sort(equippedCandidates, function(a, b) return a.priority < b.priority end)
    table.sort(inventoryCandidates, function(a, b) return a.priority < b.priority end)
    return equippedCandidates, inventoryCandidates, nil
end

function MercyAccessory:refresh(inventoryData)
    inventoryData = inventoryData or self:_getLocalInventoryData()
    if not self.alive(inventoryData) then
        self.state.mercyAccessoryEquipped = nil
        return nil, nil, {}, "local inventory data unavailable"
    end

    local equippedCandidates, candidates, scanError = self:_scanSlots(inventoryData)
    local equipped = equippedCandidates[1]
    self.state.mercyAccessoryEquipped = equipped ~= nil and self.alive(equipped.slot)
    return self.state.mercyAccessoryEquipped, equipped, candidates, scanError, equippedCandidates
end

function MercyAccessory:toggle()
    if self.cfg("mercyAccessoryToggleEnabled", true) ~= true then
        self:_log("Mercy accessory toggle is disabled in config.lua", true)
        return false
    end

    local inventoryData = self:_getLocalInventoryData()
    if not self.alive(inventoryData) then
        self.state.mercyAccessoryEquipped = nil
        self:_log("Mercy toggle: local inventory data unavailable", true)
        return false
    end

    local wasEquipped, equipped, candidates, scanError, equippedCandidates = self:refresh(inventoryData)
    if scanError ~= nil then
        self:_log("Mercy toggle scan warning: " .. scanError, true)
    end

    if wasEquipped == true and equipped ~= nil and self.alive(equipped.slot) then
        local removedCount = 0
        for _, entry in ipairs(equippedCandidates or {}) do
            if self.alive(entry.slot) then
                local ok, result = pcall(function()
                    return inventoryData:TryRemoveEquipment(entry.slot)
                end)
                if ok then
                    removedCount = removedCount + 1
                else
                    self:_log("Mercy toggle unequip call failed for " .. tostring(entry.id)
                        .. ": " .. tostring(result), true)
                end
            end
        end

        local stillEquipped = self:refresh(inventoryData) == true
        if not stillEquipped then
            if type(self.state.showCenterNotificationStyled) == "function" then
                self.state.showCenterNotificationStyled(T("mercyAccessory"), T("removed"), "",
                    self.colors.mercyNoneText, true)
            end
            self:_log("Unequipped all equipped mercy accessories; attempted "
                .. tostring(removedCount), true)
            return true
        end

        self.state.mercyAccessoryEquipped = true
        if type(self.state.showCenterNotificationStyled) == "function" then
            self.state.showCenterNotificationStyled("",
                T("mercyInventoryFull"), "", self.colors.mercyNoneText, true)
        elseif type(self.state.showCenterNotification) == "function" then
            self.state.showCenterNotification(T("mercyInventoryFull"), true)
        end
        self:_log("Mercy toggle left one or more compatible accessories equipped; inventory full assumed", true)
        return false
    end

    local candidate = candidates[1]
    if candidate ~= nil and self.alive(candidate.slot) then
        local ok, result = pcall(function()
            return inventoryData:TryEquipSlot(candidate.slot)
        end)
        local nowEquipped = self:refresh(inventoryData) == true
        if nowEquipped then
            if type(self.state.showCenterNotificationStyled) == "function" then
                self.state.showCenterNotificationStyled(T("mercyAccessory"), T("equippedWord"), "",
                    self.colors.mercyEquippedText, true)
            end
            self:_log("Equipped mercy accessory: " .. candidate.id, true)
            return true
        end
        self:_log("Mercy toggle could not equip the available accessory (call="
            .. tostring(ok) .. "/" .. tostring(result) .. ")", true)
        return false
    end

    self.state.mercyAccessoryEquipped = false
    self:_log("Mercy toggle: Ring of Mercy or Pal Tamer's Glasses not found in inventory", true)
    return false
end

return MercyAccessory
