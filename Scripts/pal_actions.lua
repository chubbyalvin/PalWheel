local PalActions = {}
PalActions.__index = PalActions

function PalActions.new(options)
    return setmetatable({ options = options or {} }, PalActions)
end

local function valueString(value)
    if value == nil then return "" end
    local ok, result = pcall(function() return value:ToString() end)
    if ok and result ~= nil then return tostring(result) end
    return tostring(value)
end

function PalActions:valueString(value)
    return valueString(value)
end

function PalActions:normalizedName(value)
    return string.lower(valueString(value)):gsub("[^%w]", "")
end

function PalActions:getHolder()
    local o = self.options
    if o.alive(o.state.cachedPartyHolder) then return o.state.cachedPartyHolder end
    local okHolder, holder = pcall(FindFirstOf, "BP_OtomoPalHolderComponent_C")
    if okHolder and o.alive(holder) then
        o.state.cachedPartyHolder = holder
        return holder
    end
    return nil
end

function PalActions:readSelectedSlot(holder)
    local o = self.options
    if not o.alive(holder) then holder = self:getHolder() end
    if not o.alive(holder) then return nil end
    local selected = nil
    local okSelected = pcall(function() selected = holder:GetSelectedOtomoID() end)
    selected = okSelected and tonumber(selected) or nil
    if selected == nil or selected < 0 or selected > 4 then return nil end
    return math.floor(selected)
end

function PalActions:selectSlotNatively(pc, index, source)
    local o = self.options
    if not o.alive(pc) then return false end
    index = math.floor(tonumber(index) or -1)
    if index < 0 or index > 4 then return false end
    local holder = self:getHolder()
    if not o.alive(holder) then
        o.log("Party Pal holder unavailable for native selection", true)
        return false
    end
    local current = self:readSelectedSlot(holder)
    if current == nil then return false end
    if current == index then
        o.state.activePalSlot = index
        return true
    end
    local forward = (index - current) % 5
    local backward = (current - index) % 5
    local direction = backward < forward and -1 or 1
    for _ = 1, 5 do
        local before = self:readSelectedSlot(holder)
        if before == index then
            o.state.activePalSlot = index
            o.log("Party Pal slot " .. tostring(index + 1) .. " selected natively"
                .. (source and (" by " .. tostring(source)) or ""), true)
            return true
        end
        if before == nil then break end
        local okController, controllerErr = pcall(function()
            if direction == 1 then pc:OnOtomoChangeIncrement()
            else pc:OnOtomoChangeDecrement() end
        end)
        local after = self:readSelectedSlot(holder)
        if not okController or after == before then
            if not okController then
                o.log("Native Pal selection handler failed: " .. tostring(controllerErr), true)
            end
            local okHolderStep, holderErr = pcall(function()
                if direction == 1 then holder:IncrementSelectOtomoID()
                else holder:DecrementSelectOtomoID() end
            end)
            if not okHolderStep then
                o.log("Party holder selection fallback failed: " .. tostring(holderErr), true)
                break
            end
            after = self:readSelectedSlot(holder)
        end
        if after == index then
            o.state.activePalSlot = index
            o.log("Party Pal slot " .. tostring(index + 1) .. " selected natively"
                .. (source and (" by " .. tostring(source)) or ""), true)
            return true
        end
        if after == nil or after == before then break end
    end
    o.state.activePalSlot = self:readSelectedSlot(holder) or o.state.activePalSlot
    o.log("Native party selection could not reach slot " .. tostring(index + 1), true)
    return false
end

function PalActions:selectSlot(pc, index, source)
    local o = self.options
    if not o.alive(pc) then return false end
    local okSelect, selectErr = pcall(function() pc:SetOtomoSlot(index) end)
    if not okSelect then
        o.log("PalPlayerController:SetOtomoSlot failed: " .. tostring(selectErr), true)
        return false
    end
    o.state.activePalSlot = self:readSelectedSlot() or index
    o.log("Party Pal slot " .. tostring(index + 1) .. " selected"
        .. (source and (" by " .. tostring(source)) or ""), true)
    return true
end

function PalActions:activateCurrentNearPlayer(pc, index)
    local o = self.options
    local okSummon, summonErr = pcall(function() pc:ActivateCurrentOtomoNearThePlayer() end)
    o.reassertGameplayCursorState(pc)
    if not okSummon then
        o.log("PalPlayerController near-player summon failed: " .. tostring(summonErr), true)
        return false
    end
    o.log("Controller requested party Pal slot " .. tostring(index + 1), true)
    return true
end

function PalActions:summonSlotNearPlayer(index)
    local o = self.options
    if o.cfg("palSelectionEnabled", true) ~= true then return false end
    index = tonumber(index)
    if index == nil or index < 0 or index > 4 then return false end
    local pc = o.state.pc
    if not o.alive(pc) then pc = o.getPlayerController() end
    if not o.alive(pc) then
        o.log("Pal summon failed: local PalPlayerController unavailable", true)
        return false
    end
    o.reassertGameplayCursorState(pc)
    if not self:selectSlotNatively(pc, index, "activation") then
        if not self:selectSlot(pc, index, "activation fallback") then
            o.reassertGameplayCursorState(pc)
            return false
        end
    end
    return self:activateCurrentNearPlayer(pc, index)
end

return PalActions
