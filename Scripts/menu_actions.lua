local MenuActions = {}
MenuActions.__index = MenuActions

function MenuActions.new(options)
    local self = setmetatable({
        options = options or {},
        deferredId = nil,
        deferredAt = 0,
        injector = nil,
        injectorLoadAttempted = false,
    }, MenuActions)
    self:loadInjector()
    return self
end

function MenuActions:showNative(widgetType)
    local o = self.options
    local pc = o.state.pc
    if not o.alive(pc) then pc = o.getPlayerController() end
    local utility = o.cls("/Script/Pal.Default__PalUtility")
    if not o.alive(pc) or not o.alive(utility) then
        o.log("Menu shortcut failed: PalUtility or PlayerController unavailable", true)
        return false
    end
    local ok, err = pcall(function() utility:ShowUI(pc, widgetType, nil) end)
    if not ok then
        o.log("PalUtility:ShowUI failed: " .. tostring(err), true)
        return false
    end
    return true
end

function MenuActions:refreshMovementKeys(pc)
    local o = self.options
    o.state.keyboardMovementKeyNames = {}
    local names = {}
    for _, name in ipairs(o.cfg("keyboardMovementKeys", {}) or {}) do
        names[#names + 1] = string.upper(tostring(name or ""))
        o.state.keyboardMovementKeyNames[string.upper(tostring(name or ""))] = true
    end
    o.log("Using configured keyboard movement keys while wheel is open: "
        .. table.concat(names, ", "), true)
end

function MenuActions:loadInjector()
    if self.injectorLoadAttempted then return self.injector ~= nil end
    self.injectorLoadAttempted = true
    local o = self.options
    local okModule, module = pcall(require, "palworld_keyinjector")
    if not okModule or type(module) ~= "table" or type(module.new) ~= "function" then
        o.log("PalworldKeyInjector wrapper failed to load: " .. tostring(module), true)
        return false
    end
    local client, loadError = module.new(o.state.keyInjectDll)
    if client == nil then
        o.log("PalworldKeyInjector DLL failed to load: " .. tostring(loadError), true)
        return false
    end
    self.injector = client
    o.log("PalworldKeyInjector API loaded for configurable shortcut actions", true)
    return true
end

function MenuActions:injectShortcut(definition)
    local o = self.options
    if type(definition) ~= "table" or definition.kind ~= "shortcut" then
        o.log("Shortcut action unavailable: invalid definition", true)
        return false
    end
    if definition.active == false then
        o.log("Inactive shortcut not executed: " .. tostring(definition.id)
            .. " -> " .. tostring(definition.label), true)
        return false
    end
    if self.injector == nil and not self:loadInjector() then return false end
    o.state.ignoreOpenBindUntil = os.clock() + 0.35
    local ok, detail = self.injector:inject(definition.shortcutSpec)
    if not ok then
        o.log("Keyboard shortcut request failed for " .. tostring(definition.label)
            .. ": " .. tostring(detail), true)
        return false
    end
    o.log("Keyboard shortcut submitted: " .. tostring(detail)
        .. " -> " .. tostring(definition.label), true)
    return true
end

function MenuActions:open(actionId)
    self.deferredId, self.deferredAt = nil, 0
    if actionId == "map" then return self:showNative(3) end
    local def = type(self.options.definitionById) == "function"
        and self.options.definitionById(actionId) or nil
    if type(def) == "table" and def.kind == "shortcut" then
        return self:injectShortcut(def)
    end
    self.options.log("Unknown deferred menu/shortcut assignment: " .. tostring(actionId), true)
    return false
end

function MenuActions:schedule(actionId)
    self.deferredId, self.deferredAt = actionId, os.clock() + 0.06
end

function MenuActions:process()
    if self.deferredId ~= nil and os.clock() >= self.deferredAt then
        local id = self.deferredId
        self.deferredId = nil
        self:open(id)
    end
end

return MenuActions
