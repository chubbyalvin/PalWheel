local MenuActions = {}
MenuActions.__index = MenuActions

function MenuActions.new(options)
    local self = setmetatable({ options = options or {}, deferredId = nil, deferredAt = 0 }, MenuActions)
    if self.options.cfg("preserveKeyboardToggleState", true) == true then
        self:preloadToggleRestore()
    end
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

function MenuActions:injectableKey(value)
    local key = string.upper(self.options.valueString(value or "")):gsub("^KEY_", "")
    if string.match(key, "^[A-Z0-9]$") then return key end
    local named = {
        TAB=true, SPACE=true, RETURN=true, ESCAPE=true, BACKSPACE=true,
        LEFT_ARROW=true, RIGHT_ARROW=true, UP_ARROW=true, DOWN_ARROW=true,
        HOME=true, END=true, PAGE_UP=true, PAGE_DOWN=true, INS=true, DEL=true,
    }
    return named[key] and key or nil
end

function MenuActions:menuKey(menuId)
    local configured = self.options.cfg("menuShortcutKeys", {})
    return self:injectableKey(type(configured) == "table" and configured[menuId] or nil)
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

function MenuActions:loadInjector(key)
    local o = self.options
    local cached = o.state.keyInjectFunctions[key]
    if type(cached) == "function" then return cached end
    if o.state.keyInjectLoadErrors[key] ~= nil then return nil end
    if package == nil or type(package.loadlib) ~= "function" then
        o.state.keyInjectLoadErrors[key] = "Lua package.loadlib is unavailable"
        o.log("Keyboard injection failed: " .. o.state.keyInjectLoadErrors[key], true)
        return nil
    end
    local symbol = "palwheel_inject_" .. string.lower(key)
    local loader, loadError = package.loadlib(o.state.keyInjectDll, symbol)
    if type(loader) ~= "function" then
        o.state.keyInjectLoadErrors[key] = tostring(loadError or "unknown DLL load error")
        o.log("Keyboard injection DLL failed to load " .. symbol .. ": "
            .. o.state.keyInjectLoadErrors[key], true)
        return nil
    end
    o.state.keyInjectFunctions[key] = loader
    return loader
end

function MenuActions:inject(menuId)
    local o, key = self.options, self:menuKey(menuId)
    if key == nil then o.log("No valid keyboard key configured for " .. tostring(menuId), true) return false end
    local injector = self:loadInjector(key)
    if type(injector) ~= "function" then return false end
    o.state.ignoreOpenBindUntil = os.clock() + 0.35
    local ok, injectError = pcall(injector)
    if not ok then
        o.log("Keyboard injection failed for " .. tostring(menuId) .. ": " .. tostring(injectError), true)
        return false
    end
    o.log("Hidden keyboard injection queued: " .. key .. " -> " .. tostring(menuId), true)
    return true
end

function MenuActions:preloadToggleRestore()
    local o = self.options
    if o.state.keyboardToggleRestoreLoadAttempted then
        return type(o.state.keyboardToggleRestoreFunction) == "function"
    end
    if package == nil or type(package.loadlib) ~= "function" then return false end
    o.state.keyboardToggleRestoreLoadAttempted = true
    local loader, loadError = package.loadlib(o.state.keyInjectDll, "palwheel_restore_caps_lock")
    if type(loader) == "function" then
        o.state.keyboardToggleRestoreFunction = loader
        o.log("Caps Lock restoration bridge preloaded before save entry", true)
        return true
    end
    o.log("Keyboard toggle-state restore unavailable: " .. tostring(loadError), true)
    return false
end

function MenuActions:queueToggleRestore()
    local o = self.options
    if not o.state.keyboardToggleRestorePending then return true end
    o.state.keyboardToggleRestorePending = false
    if o.cfg("preserveKeyboardToggleState", true) ~= true then return true end
    o.state.ignoreOpenBindUntil = os.clock() + 0.40
    if type(o.state.keyboardToggleRestoreFunction) ~= "function" then self:preloadToggleRestore() end
    if type(o.state.keyboardToggleRestoreFunction) ~= "function" then return false end
    local ok, restoreError = pcall(o.state.keyboardToggleRestoreFunction)
    if not ok then
        o.log("Keyboard toggle-state restore failed: " .. tostring(restoreError), true)
        return false
    end
    return true
end

function MenuActions:open(menuId)
    self.deferredId, self.deferredAt = nil, 0
    if menuId == "map" then return self:showNative(3) end
    if menuId == "character" or menuId == "inventory"
        or menuId == "technology" or menuId == "party"
        or menuId == "build" then return self:inject(menuId) end
    self.options.log("Unknown menu assignment: " .. tostring(menuId), true)
    return false
end

function MenuActions:schedule(menuId)
    self.deferredId, self.deferredAt = menuId, os.clock() + 0.06
end

function MenuActions:process()
    if self.deferredId ~= nil and os.clock() >= self.deferredAt then
        local id = self.deferredId
        self.deferredId = nil
        self:open(id)
    end
end

return MenuActions
