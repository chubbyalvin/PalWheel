local MenuActions = {}
MenuActions.__index = MenuActions

local MAIN_MENU_TYPES = {
    inventory = 8,
    party = 2,
    technology = 5,
    palpedia = 6,
    guild = 9,
}


local POST_CONSTRUCTION_DELAY = 0.06
local TRANSITION_TIMEOUT = 1.50
local QUEST_INPUT_LISTENER_CLASS_NAME = "WBP_PalHUD_InGame_InputListener_C"
local QUEST_INPUT_LISTENER_CLASS = "/Game/Pal/Blueprint/UI/WBP_PalHUD_InGame_InputListener.WBP_PalHUD_InGame_InputListener_C"
local INGAME_MENU_PACKAGE = "/Game/Pal/Blueprint/UI/InGameMainMenu/WBP_InGameMainMenu"
local INGAME_MENU_CLASS = "/Game/Pal/Blueprint/UI/InGameMainMenu/WBP_InGameMainMenu.WBP_InGameMainMenu_C"
local INGAME_MENU_CONSTRUCT = INGAME_MENU_CLASS .. ":Construct"

local function unwrap(value)
    if value == nil then return nil end
    local ok, got = pcall(function() return value:get() end)
    if ok and got ~= nil then return got end
    return value
end

local function objectName(obj)
    obj = unwrap(obj)
    if obj == nil then return "<nil>" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    ok, value = pcall(function() return obj:GetName() end)
    if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    return tostring(obj)
end

local function exactClassName(obj)
    obj = unwrap(obj)
    if obj == nil then return nil end
    local ok, classObject = pcall(function() return obj:GetClass() end)
    classObject = unwrap(ok and classObject or nil)
    if classObject == nil then return nil end
    local okName, value = pcall(function() return classObject:GetName() end)
    if okName and value ~= nil then return tostring(value) end
    local okFull, full = pcall(function() return classObject:GetFullName() end)
    if okFull and full ~= nil then
        local text = tostring(full)
        return text:match("([^%s%.]+)$") or text
    end
    return nil
end

local function pathPart(fullName)
    local text = tostring(fullName or "")
    return text:match("^[^%s]+%s+(.+)$") or text
end

function MenuActions.new(options)
    local self = setmetatable({
        options = options or {},
        deferredId = nil,
        deferredAt = 0,
        injector = nil,
        injectorLoadAttempted = false,
        mainMenuTransition = nil,
        constructHookRegistered = false,
        constructHookCallback = nil,
        missionCursorGeneration = 0,
        mainMenuChildFallbackNextAt = 0.0,
    }, MenuActions)
    self:loadInjector()
    local o = self.options or {}
    if type(o.log) == "function" then
        o.log("Native main-menu IDs ready; Inventory seed enabled", true)
        o.log("Mission ByMap route ready with cursor-only suppression", true)
    end
    return self
end

function MenuActions:setMainMenuOpacity(wrapper, opacity)
    local o = self.options
    wrapper = unwrap(wrapper)
    if wrapper == nil then return false end
    local value = tonumber(opacity)
    if value == nil then return false end

    local ok, err = pcall(function() wrapper:SetRenderOpacity(value) end)
    if not ok then
        ok, err = pcall(function() wrapper.RenderOpacity = value end)
    end
    if not ok then
        o.log("Could not set native main-menu render opacity to " .. tostring(value)
            .. ": " .. tostring(err), true)
        return false
    end
    return true
end

function MenuActions:hideTransitionWrapper(wrapper, source)
    local transition = self.mainMenuTransition
    if transition == nil or transition.hideSeed ~= true then return false end
    wrapper = unwrap(wrapper)
    if wrapper == nil or exactClassName(wrapper) ~= "WBP_InGameMainMenu_C" then return false end

    if not self:setMainMenuOpacity(wrapper, 0.0) then return false end
    transition.hiddenWrapper = wrapper
    transition.hiddenByPalWheel = true
    if transition.hideLogged ~= true then
        transition.hideLogged = true
        self.options.log("Temporary native main-menu seed hidden during "
            .. tostring(transition.actionId) .. " transition (" .. tostring(source) .. ")", true)
    end
    return true
end

function MenuActions:restoreTransitionWrapper(reason)
    local transition = self.mainMenuTransition
    if transition == nil or transition.hiddenByPalWheel ~= true then return false end
    local wrapper = unwrap(transition.hiddenWrapper)
    if wrapper == nil then
        transition.hiddenByPalWheel = false
        transition.hiddenWrapper = nil
        return false
    end
    if self:setMainMenuOpacity(wrapper, 1.0) then
        self.options.log("Native main menu revealed after " .. tostring(transition.actionId)
            .. " transition (" .. tostring(reason or "complete") .. ")", true)
        transition.hiddenByPalWheel = false
        transition.hiddenWrapper = nil
        return true
    end
    return false
end

function MenuActions:ensureConstructHook()
    if self.constructHookRegistered then return true end
    local o = self.options
    if type(RegisterHook) ~= "function" then
        o.log("Native main-menu Construct hook unavailable; transition will use polling hide fallback", true)
        return false
    end

    
    
    if type(LoadAsset) == "function" then
        pcall(function() LoadAsset(INGAME_MENU_PACKAGE) end)
        pcall(function() LoadAsset(INGAME_MENU_CLASS) end)
    end

    if self.constructHookCallback == nil then
        self.constructHookCallback = function(...)
            local args = { ... }
            local wrapper = nil
            for i = 1, math.min(#args, 4) do
                local candidate = unwrap(args[i])
                if candidate ~= nil and exactClassName(candidate) == "WBP_InGameMainMenu_C" then
                    wrapper = candidate
                    break
                end
            end
            if wrapper ~= nil then
                local ok, err = pcall(function()
                    self:hideTransitionWrapper(wrapper, "Construct hook")
                end)
                if not ok then
                    o.log("Native main-menu Construct hide callback failed: " .. tostring(err), true)
                end
            end
        end
    end

    local ok, result = pcall(function()
        return RegisterHook(INGAME_MENU_CONSTRUCT, self.constructHookCallback)
    end)
    if not ok then
        o.log("Native main-menu Construct hook registration failed; transition will use polling hide fallback: "
            .. tostring(result), true)
        return false
    end
    self.constructHookRegistered = true
    o.log("Native main-menu Construct hide hook registered", true)
    return true
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

function MenuActions:openBuildNativeTrigger()
    local o = self.options
    local pc = o.state.pc
    if not o.alive(pc) then pc = o.getPlayerController() end
    if not o.alive(pc) then
        o.log("Build native trigger failed: PlayerController unavailable", true)
        return false
    end

    
    
    
    
    
    local ok, result = pcall(function()
        local delegate = pc.OnPressConstructionMenuButtonDelegate
        if delegate == nil then error("construction-menu delegate unavailable") end
        return delegate:Broadcast()
    end)
    if not ok then
        o.log("Build native construction-menu delegate failed: " .. tostring(result), true)
        return false
    end
    o.log("Build submitted via PlayerController construction-menu delegate", true)
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

function MenuActions:getPalHUD(pc)
    local o = self.options
    if o.alive(pc) then
        local ok, hud = pcall(function() return pc.MyHUD end)
        if ok and o.alive(hud) then return hud end
    end
    local ok, hud = pcall(FindFirstOf, "PalHUDInGame")
    if ok and o.alive(hud) then return hud end
    return nil
end

function MenuActions:readStackValue(stack, first, second)
    if second ~= nil then return unwrap(second) end
    local direct = unwrap(first)
    if direct ~= nil and type(direct) ~= "number" then
        local text = tostring(direct)
        if not text:match("^%d+$") then return direct end
    end
    local index = tonumber(first)
    if index == nil then index = tonumber(tostring(first)) end
    if index == nil then return direct end
    local ok, value = pcall(function() return stack:Get(index) end)
    if ok and value ~= nil then return unwrap(value) end
    if index > 0 then
        ok, value = pcall(function() return stack:Get(index - 1) end)
        if ok and value ~= nil then return unwrap(value) end
    end
    return direct
end

function MenuActions:findQuestInputListener()
    local o = self.options
    local pc = o.state.pc
    if not o.alive(pc) then pc = o.getPlayerController() end
    local hud = self:getPalHUD(pc)
    if not o.alive(hud) then return nil, "HUD unavailable" end

    local ok, stack = pcall(function() return hud.StackableUIWidgets end)
    if ok and stack ~= nil then
        local found = nil
        local iterOk, iterErr = pcall(function()
            stack:ForEach(function(first, second)
                local value = unwrap(self:readStackValue(stack, first, second))
                if value ~= nil and exactClassName(value) == QUEST_INPUT_LISTENER_CLASS_NAME then
                    found = value
                end
            end)
        end)
        if iterOk and found ~= nil then return found, nil end
        if not iterOk then
            o.log("Quest input-listener stack scan failed: " .. tostring(iterErr), true)
        end
    end

    if type(FindAllOf) == "function" then
        local allOk, objects = pcall(FindAllOf, QUEST_INPUT_LISTENER_CLASS_NAME)
        if allOk and objects ~= nil then
            for _, object in pairs(objects) do
                object = unwrap(object)
                if o.alive(object) then return object, nil end
            end
        end
    end
    return nil, "no live WBP_PalHUD_InGame_InputListener_C found"
end

function MenuActions:openInventoryNativeTrigger()
    local o = self.options
    local listener, findErr = self:findQuestInputListener()
    if listener == nil then
        o.log("Character/Inventory native HUD listener unavailable: " .. tostring(findErr), true)
        return false
    end

    
    
    
    
    local okMember, member = pcall(function()
        return listener["On Trigger Open Inventory Menu"]
    end)
    if not okMember or member == nil then
        o.log("Character/Inventory native HUD member unavailable: " .. tostring(member), true)
        return false
    end

    local ok, result = pcall(function()
        return member()
    end)
    if not ok then
        o.log("Character/Inventory native HUD trigger failed: " .. tostring(result), true)
        return false
    end

    o.log("Character/Inventory submitted via HUD On Trigger Open Inventory Menu", true)
    return true
end

function MenuActions:openMissionByMap()
    local o = self.options
    local listener, findErr = self:findQuestInputListener()
    if listener == nil then
        o.log("Mission ByMap handler unavailable: " .. tostring(findErr), true)
        return false
    end

    
    
    
    
    
    local okName, questName = pcall(function()
        return FName("None")
    end)
    if not okName or questName == nil then
        o.log("Mission ByMap FName construction failed: " .. tostring(questName), true)
        return false
    end

    local ok, result = pcall(function()
        return listener:OnRequestOpenQuest_ByMap(questName)
    end)
    if not ok then
        o.log("Mission HUD OnRequestOpenQuest_ByMap failed: " .. tostring(result), true)
        return false
    end

    o.log("Mission submitted via HUD OnRequestOpenQuest_ByMap(FName(None))", true)

    
    
    
    
    local missionGeneration = self.missionCursorGeneration
    local function hideMissionCursor(pass)
        if missionGeneration ~= self.missionCursorGeneration then return end
        if o.state ~= nil and (o.state.open == true or o.state.editorOpen == true) then return end
        local pc = o.state and o.state.pc or nil
        if not o.alive(pc) then pc = o.getPlayerController() end
        if not o.alive(pc) then return end
        local okHide, errHide = pcall(function() pc.bShowMouseCursor = false end)
        if okHide then
            if pass == 1 then o.log("Mission cursor suppression applied", true) end
        elseif pass == 1 then
            o.log("Mission cursor suppression failed: " .. tostring(errHide), true)
        end
    end

    hideMissionCursor(1)
    if type(ExecuteWithDelay) == "function" then
        ExecuteWithDelay(20, function() hideMissionCursor(2) end)
        ExecuteWithDelay(60, function() hideMissionCursor(3) end)
        ExecuteWithDelay(140, function() hideMissionCursor(4) end)
    end
    return true
end

function MenuActions:findActiveInGameMainMenu()
    local o = self.options
    local pc = o.state.pc
    if not o.alive(pc) then pc = o.getPlayerController() end
    local hud = self:getPalHUD(pc)
    if not o.alive(hud) then return nil, "HUD unavailable" end
    local ok, stack = pcall(function() return hud.StackableUIWidgets end)
    if not ok or stack == nil then return nil, "StackableUIWidgets unavailable" end

    local found = nil
    local iterOk, iterErr = pcall(function()
        stack:ForEach(function(first, second)
            local value = self:readStackValue(stack, first, second)
            value = unwrap(value)
            if value ~= nil and exactClassName(value) == "WBP_InGameMainMenu_C" then
                found = value
            end
        end)
    end)
    if not iterOk then return nil, "UI stack iteration failed: " .. tostring(iterErr) end
    if found == nil then return nil, "no active WBP_InGameMainMenu_C on UI stack" end
    return found, nil
end

function MenuActions:findMainMenuChild(parent)
    local o = self.options
    parent = unwrap(parent)
    if parent == nil then return nil, "active InGameMainMenu unavailable" end

    local okDirect, direct = pcall(function() return parent.WBP_MainMenu end)
    direct = unwrap(okDirect and direct or nil)
    if direct ~= nil and exactClassName(direct) == "WBP_MainMenu_C" then
        return direct, nil
    end

    if type(FindAllOf) ~= "function" then return nil, "FindAllOf unavailable" end
    local now = os.clock()
    if now < (self.mainMenuChildFallbackNextAt or 0.0) then
        return nil, "active WBP_MainMenu_C child not ready"
    end
    self.mainMenuChildFallbackNextAt = now + 0.12
    local ok, widgets = pcall(FindAllOf, "UserWidget")
    if not ok or widgets == nil then
        return nil, "FindAllOf(UserWidget) failed: " .. tostring(widgets)
    end

    local parentPath = pathPart(objectName(parent))
    local match = nil
    local scanOk, scanErr = pcall(function()
        for _, widget in pairs(widgets) do
            widget = unwrap(widget)
            if widget ~= nil and exactClassName(widget) == "WBP_MainMenu_C" then
                local full = objectName(widget)
                if full:find("/Engine/Transient", 1, true) ~= nil
                    and full:find(parentPath, 1, true) ~= nil then
                    match = widget
                    break
                end
            end
        end
    end)
    if not scanOk then return nil, "WBP_MainMenu_C scan failed: " .. tostring(scanErr) end
    if match == nil then return nil, "active WBP_MainMenu_C child not ready" end
    return unwrap(match), nil
end

function MenuActions:selectMainMenuType(actionId, menuType)
    local o = self.options
    if menuType == 10 then
        o.log("Mission native selector blocked: type 10 is not safe from an ordinary main menu", true)
        return false, "mission selector intentionally blocked"
    end

    local wrapper, wrapperErr = self:findActiveInGameMainMenu()
    if wrapper == nil then return false, wrapperErr end
    local mainMenu, menuErr = self:findMainMenuChild(wrapper)
    if mainMenu == nil then return false, menuErr end

    local ok, result = pcall(function()
        return mainMenu:SelectByMainMenuType(menuType)
    end)
    if not ok then
        o.log("Native " .. tostring(actionId) .. " tab selection failed: " .. tostring(result), true)
        return false, tostring(result)
    end
    o.log("Native " .. tostring(actionId) .. " tab selected via SelectByMainMenuType("
        .. tostring(menuType) .. ")", true)
    return true, nil
end

function MenuActions:openOptions()
    local o = self.options
    if self.injector == nil and not self:loadInjector() then return false end
    o.state.ignoreOpenBindUntil = os.clock() + 0.45
    local ok, detail = self.injector:inject("ESCAPE")
    if not ok then
        o.log("PalWheel Options menu request failed: " .. tostring(detail), true)
        return false
    end
    o.log("PalWheel Options menu submitted via Escape: " .. tostring(detail), true)
    return true
end

function MenuActions:seedMainMenu()
    local o = self.options

    
    
    
    
    local listener, findErr = self:findQuestInputListener()
    if listener == nil then
        o.log("Native Inventory main-menu seed listener unavailable: " .. tostring(findErr), true)
        return false
    end

    local okMember, member = pcall(function()
        return listener["On Trigger Open Inventory Menu"]
    end)
    if not okMember or member == nil then
        o.log("Native Inventory main-menu seed member unavailable: " .. tostring(member), true)
        return false
    end

    local ok, result = pcall(function()
        return member()
    end)
    if not ok then
        o.log("Native Inventory main-menu seed trigger failed: " .. tostring(result), true)
        return false
    end

    o.log("Native main-menu seed submitted via HUD On Trigger Open Inventory Menu", true)
    return true
end

function MenuActions:beginMainMenuTransition(actionId, menuType)
    local o = self.options
    local selected = self:selectMainMenuType(actionId, menuType)
    if selected then return true end

    
    
    local now = os.clock()
    self.mainMenuChildFallbackNextAt = 0.0
    self.mainMenuTransition = {
        actionId = actionId,
        menuType = menuType,
        startedAt = now,
        timeoutAt = now + TRANSITION_TIMEOUT,
        nextPollAt = now + 0.02,
        wrapperSeenAt = nil,
        hideSeed = true,
        hiddenWrapper = nil,
        hiddenByPalWheel = false,
    }
    self:ensureConstructHook()

    if not self:seedMainMenu() then
        self:restoreTransitionWrapper("seed failure")
        self.mainMenuTransition = nil
        return false
    end
    o.log("Waiting for hidden native Inventory wrapper before selecting " .. tostring(actionId), true)
    return true
end

function MenuActions:processMainMenuTransition()
    local transition = self.mainMenuTransition
    if transition == nil then return end
    local now = os.clock()
    if now < (transition.nextPollAt or 0) then return end
    transition.nextPollAt = now + 0.04

    if now >= transition.timeoutAt then
        self.options.log("Native " .. tostring(transition.actionId)
            .. " transition timed out waiting for the main menu", true)
        self:restoreTransitionWrapper("timeout")
        self.mainMenuTransition = nil
        return
    end

    local wrapper = self:findActiveInGameMainMenu()
    if wrapper == nil then return end

    
    
    
    self:hideTransitionWrapper(wrapper, "poll fallback")

    if transition.wrapperSeenAt == nil then
        transition.wrapperSeenAt = now
        transition.nextPollAt = now + POST_CONSTRUCTION_DELAY
        return
    end
    if now < transition.wrapperSeenAt + POST_CONSTRUCTION_DELAY then return end

    
    
    
    local selected, err = self:selectMainMenuType(transition.actionId, transition.menuType)
    if selected then
        
        
        
        self:restoreTransitionWrapper("target selected")
        self.mainMenuTransition = nil
        return
    end
    if tostring(err or ""):find("not ready", 1, true) == nil then
        transition.lastError = tostring(err or "")
    end
end

function MenuActions:open(actionId)
    self.missionCursorGeneration = (self.missionCursorGeneration or 0) + 1
    self.deferredId, self.deferredAt = nil, 0
    if actionId == "palwheel_options" then return self:openOptions() end
    if actionId == "map" then return self:showNative(3) end
    if actionId == "inventory" then
        return self:openInventoryNativeTrigger()
    end
    if actionId == "build" then
        return self:openBuildNativeTrigger()
    end
    if MAIN_MENU_TYPES[actionId] ~= nil then
        return self:beginMainMenuTransition(actionId, MAIN_MENU_TYPES[actionId])
    end
    if actionId == "mission" then
        return self:openMissionByMap()
    end
    local def = type(self.options.definitionById) == "function"
        and self.options.definitionById(actionId) or nil
    if type(def) == "table" and def.kind == "shortcut" then
        return self:injectShortcut(def)
    end
    self.options.log("Unknown deferred menu/shortcut assignment: " .. tostring(actionId), true)
    return false
end

function MenuActions:schedule(actionId)
    self.missionCursorGeneration = (self.missionCursorGeneration or 0) + 1
    self.deferredId, self.deferredAt = actionId, os.clock() + 0.06
end

function MenuActions:process()
    if self.deferredId ~= nil and os.clock() >= self.deferredAt then
        local id = self.deferredId
        self.deferredId = nil
        self:open(id)
    end
    self:processMainMenuTransition()
end

return MenuActions
