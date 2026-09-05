local PalworldBindings = {}
PalworldBindings.__index = PalworldBindings

local UI_DEFAULT_ROWS = {
    "OpenCHaracterMenu_Another",
    "OpenCharacterMenu_Another",
    "OpenPalStatus",
    "OpenTechnologyMenu",
    "OpenCharacterMenu",
    "OpenWorldMap",
}

local ACTION_LABELS = {
    AutoRun = "Auto-Run",
    Coop = "Partner Skill",
    Crouch = "Crouch / Slide",
    Dash = "Sprint",
    DashController = "Sprint",
    DirectAttackOrder = "Command Pal (Attack that enemy!)",
    Interact2 = "UI Interaction 2",
    Jump = "Jump",
    OpenConstructionMenu = "Build Menu",
    OtomoChangeDecrement = "Change Pal Left",
    OtomoChangeIncrement = "Change Pal Right",
    PartnerPalInstructions = "Command Pal",
    Reload = "Reload",
    ReloadAndCoop = "Partner Skill / Reload",
    RidingSkill1 = "Riding Skill 1",
    RidingSkill2 = "Riding Skill 2",
    RidingSkill3 = "Riding Skill 3",
    RidingSkill3_GamePad = "Riding Skill 3",
    Rolling = "Roll",
    RollingAndCrouch = "Roll / Crouch",
    SphereChange = "Change Sphere",
    ThrowObject = "Throw Pal Sphere",
    ThrowPal = "Summon Pal",
    VoiceChatPushToTalk = "Push-to-Talk",
    ChangeWeaponNext_GamePad = "Change Weapon",
    WeaponReady = "Aim",
    WeaponUse = "Attack / Riding Skill 1",

    OpenCHaracterMenu_Another = "Inventory",
    OpenCharacterMenu_Another = "Inventory",
    OpenPalStatus = "Pal Stats",
    OpenTechnologyMenu = "Technology Menu",
    OpenCharacterMenu = "Character Menu",
    OpenWorldMap = "World Map",
}

local function normalized(value)
    return string.lower(string.gsub(tostring(value or ""), "[^%w]", ""))
end

local function unwrap(value)
    if value == nil then return nil end
    local ok, got = pcall(function() return value:get() end)
    if ok and got ~= nil then return got end
    return value
end

local function safeGet(object, field)
    object = unwrap(object)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[field] end)
    if ok then return unwrap(value) end
    return nil
end

local function safeText(value)
    value = unwrap(value)
    if value == nil then return "" end
    if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
        return tostring(value)
    end
    local ok, text = pcall(function() return value:ToString() end)
    if ok and text ~= nil then return tostring(text) end
    local okText, fallback = pcall(tostring, value)
    if not okText then return "" end
    fallback = tostring(fallback or "")
    return fallback:match("^FName%((.*)%)$") or fallback
end

local function keyText(value)
    value = unwrap(value)
    if value == nil then return "None" end
    local keyName = safeGet(value, "KeyName")
    if keyName ~= nil then
        local text = safeText(keyName)
        if text ~= "" then return text end
    end
    local text = safeText(value)
    if text == "" then return "None" end
    return text
end

local function decodeKeyPair(value)
    value = unwrap(value)
    if value == nil then return "None", "None" end
    local main = safeGet(value, "MainKey")
    local secondary = safeGet(value, "SecondaryKey")
    if main ~= nil or secondary ~= nil then
        return keyText(main), keyText(secondary)
    end
    local direct = safeGet(value, "Key")
    if direct ~= nil then return keyText(direct), "None" end
    local directName = safeGet(value, "KeyName")
    if directName ~= nil then return safeText(directName), "None" end
    return "None", "None"
end

local function cleanUiActionName(value)
    local text = safeText(value)
    local prefix = "Legacy_DT_UIInputAction_"
    if string.sub(text, 1, #prefix) == prefix then
        text = string.sub(text, #prefix + 1)
    end
    if text == "OpenCharacterMenu_Another" then text = "OpenCHaracterMenu_Another" end
    return text
end

local function friendlyActionName(action)
    action = tostring(action or "")
    if ACTION_LABELS[action] ~= nil then return ACTION_LABELS[action] end

    
    
    
    if action == "MoveForward (+)" then return "Movement: Forward" end
    if action == "MoveForward (-)" then return "Movement: Backward" end
    if action == "MoveRight (+)" then return "Movement: Right" end
    if action == "MoveRight (-)" then return "Movement: Left" end
    if action == "MoveForward (all)" then return "Movement: Forward / Backward" end
    if action == "MoveRight (all)" then return "Movement: Left / Right" end

    local text = action:gsub("_GamePad$", "")
    text = text:gsub("_", " ")
    text = text:gsub("(%l)(%u)", "%1 %2")
    text = text:gsub("(%a)(%d)", "%1 %2")
    text = text:gsub("(%d)(%a)", "%1 %2")
    if text == "" then return "Palworld action" end
    return text
end

local function appendUnique(list, seen, value)
    value = tostring(value or "")
    if value == "" or seen[value] then return end
    seen[value] = true
    list[#list + 1] = value
end

function PalworldBindings.new(options)
    return setmetatable({
        o = options or {},
        keyboard = {},
        controller = {},
        keyboardMovement = {},
        controllerMovement = {},
        available = false,
        lastError = nil,
        fingerprint = "",
        uiDataTable = nil,
        uiDataTableAttempted = false,
    }, PalworldBindings)
end

function PalworldBindings:log(message)
    if type(self.o.log) == "function" then self.o.log(message, true) end
end

function PalworldBindings:getPalOptionSubsystem()
    if type(FindFirstOf) == "function" then
        for _, className in ipairs({ "BP_PalOptionSubsystem_C", "PalOptionSubsystem" }) do
            local ok, object = pcall(FindFirstOf, className)
            if ok and object ~= nil then return object end
        end
    end
    if type(FindAllOf) == "function" then
        for _, className in ipairs({ "BP_PalOptionSubsystem_C", "PalOptionSubsystem" }) do
            local ok, objects = pcall(FindAllOf, className)
            if ok and type(objects) == "table" then
                for _, object in pairs(objects) do
                    if object ~= nil then return object end
                end
            end
        end
    end
    return nil
end

function PalworldBindings:getUiDataTable()
    if self.uiDataTableAttempted then return self.uiDataTable end
    self.uiDataTableAttempted = true

    if type(StaticFindObject) == "function" then
        local candidates = {
            "/Game/Pal/DataTable/UI/DT_UIInputAction.DT_UIInputAction",
            "DataTable /Game/Pal/DataTable/UI/DT_UIInputAction.DT_UIInputAction",
        }
        for _, path in ipairs(candidates) do
            local ok, object = pcall(StaticFindObject, path)
            if ok and object ~= nil then
                self.uiDataTable = object
                return object
            end
        end
    end

    if type(FindAllOf) == "function" then
        local ok, objects = pcall(FindAllOf, "DataTable")
        if ok and type(objects) == "table" then
            for _, object in pairs(objects) do
                local full = ""
                pcall(function() full = tostring(object:GetFullName()) end)
                if string.find(full, "DT_UIInputAction", 1, true) ~= nil then
                    self.uiDataTable = object
                    return object
                end
            end
        end
    end
    return nil
end

function PalworldBindings:readUiDefault(actionName, device)
    local dataTable = self:getUiDataTable()
    if dataTable == nil then return nil end
    local row = nil
    local ok = pcall(function() row = dataTable:FindRow(actionName) end)
    if not ok or row == nil then return nil end

    local fieldName = device == "controller" and "GamepadInputTypeInfo" or "KeyboardInputTypeInfo"
    local inputInfo = safeGet(row, fieldName)
    if inputInfo == nil and device == "controller" then
        inputInfo = safeGet(row, "GamePadInputTypeInfo")
    end
    if inputInfo == nil then return nil end
    local key = safeGet(inputInfo, "Key")
    if key == nil then return nil end
    local text = keyText(key)
    if text == "" or text == "None" then return nil end
    return text
end

function PalworldBindings:addBinding(device, keyName, action, kind, movement)
    keyName = tostring(keyName or "")
    if keyName == "" or keyName == "None" or keyName == "<nil>" then return end
    local id = normalized(keyName)
    if id == "" then return end

    local target = device == "controller" and self.controller or self.keyboard
    local bucket = target[id]
    if bucket == nil then
        bucket = { key = keyName, actions = {}, seen = {}, movement = false }
        target[id] = bucket
    end

    action = tostring(action or "")
    local label = friendlyActionName(action)
    local signature = tostring(kind or "action") .. "|" .. action .. "|" .. label
    if not bucket.seen[signature] then
        bucket.seen[signature] = true
        bucket.actions[#bucket.actions + 1] = {
            action = action,
            label = label,
            kind = kind or "action",
            movement = movement == true,
        }
    end
    if movement == true then
        bucket.movement = true
        if device == "controller" then
            self.controllerMovement[id] = keyName
        else
            self.keyboardMovement[id] = keyName
        end
    end
end

function PalworldBindings:readActionMap(settings, fieldName, device, kind)
    local container = settings[fieldName]
    if type(container) ~= "table" then return end
    for actionParam, valueParam in pairs(container) do
        local action = safeText(actionParam)
        local main, secondary = decodeKeyPair(valueParam)
        self:addBinding(device, main, action, kind or "gameplay", false)
        if normalized(secondary) ~= normalized(main) then
            self:addBinding(device, secondary, action, kind or "gameplay", false)
        end
    end
end

function PalworldBindings:readAxisMap(settings, fieldName, device)
    local container = settings[fieldName]
    if type(container) ~= "table" then return end
    for _, valueParam in pairs(container) do
        local value = unwrap(valueParam)
        local axis = safeText(safeGet(value, "AxisName"))
        local filter = safeText(safeGet(value, "FilterType"))
        local main, secondary = decodeKeyPair(value)
        local movement = string.sub(axis, 1, 4) == "Move"
        local action = axis
        local filterLabel = filter == "1" and "+" or filter == "2" and "-"
            or filter == "0" and "all" or filter
        if filterLabel ~= "" and filterLabel ~= "nil" then
            action = action .. " (" .. filterLabel .. ")"
        end
        self:addBinding(device, main, action, "axis", movement)
        if normalized(secondary) ~= normalized(main) then
            self:addBinding(device, secondary, action, "axis", movement)
        end
    end
end

function PalworldBindings:readCurrentUiMap(settings, device)
    local current = {}

    for _, actionName in ipairs(UI_DEFAULT_ROWS) do
        local defaultKey = self:readUiDefault(actionName, device)
        if defaultKey ~= nil then
            local canonical = cleanUiActionName(actionName)
            current[canonical] = { main = defaultKey, secondary = "None" }
        end
    end

    local fieldName = device == "controller"
        and "GamePadUIInputMappings" or "MouseAndKeyboardUIInputMappings"
    local overrides = settings[fieldName]
    if type(overrides) == "table" then
        for actionParam, valueParam in pairs(overrides) do
            local action = cleanUiActionName(actionParam)
            local main, secondary = decodeKeyPair(valueParam)
            current[action] = { main = main, secondary = secondary }
        end
    end

    for action, keys in pairs(current) do
        self:addBinding(device, keys.main, action, "ui", false)
        if normalized(keys.secondary) ~= normalized(keys.main) then
            self:addBinding(device, keys.secondary, action, "ui", false)
        end
    end
end

function PalworldBindings:sortBuckets(target)
    for _, bucket in pairs(target) do
        table.sort(bucket.actions, function(a, b)
            if a.label == b.label then return a.action < b.action end
            return a.label < b.label
        end)
    end
end

function PalworldBindings:scan()
    self.keyboard = {}
    self.controller = {}
    self.keyboardMovement = {}
    self.controllerMovement = {}
    self.available = false
    self.lastError = nil

    local subsystem = self:getPalOptionSubsystem()
    if subsystem == nil then
        self.lastError = "Palworld controls are not available yet"
        return false, self.lastError
    end

    local settings = nil
    local ok, err = pcall(function() settings = subsystem:GetKeyConfigSettings() end)
    settings = unwrap(settings)
    if not ok or type(settings) ~= "table" then
        self.lastError = "Palworld current key settings could not be read"
        return false, self.lastError
    end

    self:readActionMap(settings, "MouseAndKeyboardActionMappings", "keyboard", "gameplay")
    self:readAxisMap(settings, "MouseAndKeyboardAxisMappings", "keyboard")
    self:readCurrentUiMap(settings, "keyboard")

    self:readActionMap(settings, "GamePadActionMappings", "controller", "gameplay")
    self:readAxisMap(settings, "GamePadAxisMappings", "controller")
    self:readCurrentUiMap(settings, "controller")

    self:sortBuckets(self.keyboard)
    self:sortBuckets(self.controller)
    self.available = true

    local parts = {}
    local function collect(prefix, source)
        for id, bucket in pairs(source) do
            local labels = {}
            for _, action in ipairs(bucket.actions) do labels[#labels + 1] = action.label end
            parts[#parts + 1] = prefix .. id .. "=" .. table.concat(labels, ",")
        end
    end
    collect("K:", self.keyboard)
    collect("G:", self.controller)
    table.sort(parts)
    local fingerprint = table.concat(parts, "|")
    if fingerprint ~= self.fingerprint then
        self.fingerprint = fingerprint
        local keyboardCount, controllerCount, movementCount = 0, 0, 0
        for _ in pairs(self.keyboard) do keyboardCount = keyboardCount + 1 end
        for _ in pairs(self.controller) do controllerCount = controllerCount + 1 end
        for _ in pairs(self.keyboardMovement) do movementCount = movementCount + 1 end
        self:log("Live Palworld bindings refreshed: keyboard/mouse=" .. tostring(keyboardCount)
            .. " controller=" .. tostring(controllerCount)
            .. " movementKeys=" .. tostring(movementCount))
        local rows = {}
        for _, bucket in pairs(self.keyboard) do
            local labels, seenLabels = {}, {}
            for _, item in ipairs(bucket.actions or {}) do appendUnique(labels, seenLabels, item.label) end
            rows[#rows + 1] = tostring(bucket.key) .. " -> " .. table.concat(labels, ", ")
                .. (bucket.movement and " [MOVEMENT]" or "")
        end
        table.sort(rows)
        for _, row in ipairs(rows) do self:log("Palworld keyboard binding: " .. row) end
    end
    return true
end

function PalworldBindings:bucket(device, keyName)
    local source = device == "controller" and self.controller or self.keyboard
    return source[normalized(keyName)]
end

function PalworldBindings:isMovement(device, keyName)
    local source = device == "controller" and self.controllerMovement or self.keyboardMovement
    return source[normalized(keyName)] ~= nil
end

function PalworldBindings:labels(device, keyName)
    local bucket = self:bucket(device, keyName)
    if bucket == nil then return {} end
    local result, seen = {}, {}
    for _, item in ipairs(bucket.actions or {}) do appendUnique(result, seen, item.label) end
    return result
end

function PalworldBindings:menuBindings(device)
    local target = device == "controller" and self.controller or self.keyboard
    local rows = {}
    for _, bucket in pairs(target or {}) do
        local labels, seen = {}, {}
        for _, item in ipairs(bucket.actions or {}) do
            if item.kind == "ui" then appendUnique(labels, seen, item.label) end
        end
        if #labels > 0 then
            table.sort(labels)
            rows[#rows + 1] = { key = tostring(bucket.key or ""), labels = labels }
        end
    end
    table.sort(rows, function(a, b) return tostring(a.key) < tostring(b.key) end)
    return rows
end

return PalworldBindings
