local PalCommandActions = {}
PalCommandActions.__index = PalCommandActions

local RADIAL_CLASS_FRAGMENT = "/Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu.WBP_PlayerRadialMenu_C"

local function visitCollection(collection, callback)
    if collection == nil or type(callback) ~= "function" then return false end
    if type(collection) == "table" then
        for _, object in pairs(collection) do callback(object) end
        return true
    end
    return pcall(function()
        collection:ForEach(function(object) callback(object) end)
    end)
end

function PalCommandActions.new(options)
    return setmetatable({
        options = options or {},
        radialWidget = nil,
        lastPalAvailable = nil,
        getterFailureLogged = false,
    }, PalCommandActions)
end

function PalCommandActions:alive(object)
    local callback = self.options.alive
    if type(callback) == "function" then return callback(object) end
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

function PalCommandActions:log(message)
    if type(self.options.log) == "function" then
        self.options.log("Pal command action: " .. tostring(message), true)
    end
end

function PalCommandActions:objectName(object)
    if not self:alive(object) then return "<invalid>" end
    local ok, value = pcall(function() return object:GetFullName() end)
    if ok and value ~= nil then return tostring(value) end
    return "<name unavailable>"
end

function PalCommandActions:classFullName(object)
    if not self:alive(object) then return nil end
    local classObject = nil
    local ok = pcall(function() classObject = object:GetClass() end)
    if not ok or not self:alive(classObject) then return nil end
    return self:objectName(classObject)
end

function PalCommandActions:resolveRadialWidget()
    if self:alive(self.radialWidget) then return self.radialWidget end
    self.radialWidget = nil
    if type(FindAllOf) ~= "function" then
        self:log("FindAllOf unavailable; native radial widget cannot be resolved")
        return nil
    end

    local best, bestScore = nil, -1
    local ok, widgets = pcall(FindAllOf, "UserWidget")
    if not ok or widgets == nil then
        self:log("FindAllOf(UserWidget) failed")
        return nil
    end

    visitCollection(widgets, function(object)
        if not self:alive(object) then return end
        local classFull = self:classFullName(object) or ""
        if string.find(classFull, RADIAL_CLASS_FRAGMENT, 1, true) == nil then return end

        local full = self:objectName(object)
        local score = 0
        if string.find(full, "/Engine/Transient.", 1, true) ~= nil then score = score + 1000 end
        if string.find(full, "WBP_PalHUD_InGame_InputListener_C", 1, true) ~= nil then score = score + 500 end
        if string.find(full, "WBP_PalOverallUILayout_C", 1, true) ~= nil then score = score + 250 end
        if string.find(full, ":WidgetTree.", 1, true) ~= nil then score = score + 50 end
        local inViewport = false
        pcall(function() inViewport = object:IsInViewport() == true end)
        if inViewport then score = score + 10 end

        if score > bestScore then
            best, bestScore = object, score
        end
    end)

    if self:alive(best) and bestScore >= 1000 then
        self.radialWidget = best
        self:log("resolved persistent runtime WBP_PlayerRadialMenu_C (score="
            .. tostring(bestScore) .. ")")
        return best
    end

    self:log("persistent runtime WBP_PlayerRadialMenu_C not found")
    return nil
end

function PalCommandActions:hasSummonedPal()
    local pc = nil
    if type(self.options.getPlayerController) == "function" then
        pc = self.options.getPlayerController()
    end
    if not self:alive(pc) then return nil end

    local pal = nil
    local ok, err = pcall(function() pal = pc:GetControlPalCharacter() end)
    if not ok then
        if not self.getterFailureLogged then
            self.getterFailureLogged = true
            self:log("GetControlPalCharacter unavailable; Feed/Pet availability will remain permissive: "
                .. tostring(err))
        end
        return nil
    end
    self.getterFailureLogged = false
    return self:alive(pal)
end

function PalCommandActions:refreshAvailability(definitionById)
    if type(definitionById) ~= "table" then return nil end
    local available = self:hasSummonedPal()
    local effective = available ~= false
    for _, id in ipairs({ "feed_pal", "pet_pal" }) do
        local def = definitionById[id]
        if type(def) == "table" then def.available = effective end
    end
    if available ~= nil and available ~= self.lastPalAvailable then
        self.lastPalAvailable = available
        self:log("Feed/Pet contextual availability = " .. tostring(available))
    end
    return available
end

function PalCommandActions:execute(definition)
    if type(definition) ~= "table" then return false, "invalid action definition" end

    if definition.requiresSummonedPal == true then
        local available = self:hasSummonedPal()
        if available == false then return false, "requires a summoned Pal" end
    end

    local widget = self:resolveRadialWidget()
    if not self:alive(widget) then
        return false, "native Command Pal radial widget is unavailable"
    end

    local ok, err
    if definition.nativeBranch == "feed" then
        local out = {}
        ok, err = pcall(function() widget:OnDecidedInstruction_Feed(out) end)
        if ok then
            self:log("Feed invoked; ShouldClose=" .. tostring(out.ShouldClose))
            return true
        end
    elseif definition.nativeBranch == "pet" then
        local out = {}
        ok, err = pcall(function()
            local care = widget["On Decided Instruction Care"]
            if care == nil then error("exact Care callback lookup returned nil") end
            care(widget, out)
        end)
        if ok then
            self:log("Pet invoked; ShouldClose=" .. tostring(out.ShouldClose))
            return true
        end
    elseif tonumber(definition.nativeCommandId) ~= nil then
        ok, err = pcall(function()
            widget:OnDecidedPlayerActionMenu(math.floor(tonumber(definition.nativeCommandId)))
        end)
        if ok then
            self:log(tostring(definition.label) .. " invoked with native id "
                .. tostring(definition.nativeCommandId))
            return true
        end
    else
        return false, "native route is not configured"
    end

    self:log(tostring(definition.label) .. " failed: " .. tostring(err))
    return false, tostring(err)
end

return PalCommandActions
