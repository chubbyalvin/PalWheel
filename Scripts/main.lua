local okConfig, config = pcall(require, "config")
if not okConfig or type(config) ~= "table" then config = {} end

local okMappings, mappings = pcall(require, "mappings")
if okMappings and type(mappings) == "table" then
    for name, value in pairs(mappings) do config[name] = value end
else
    mappings = {}
end

do
    local ok, module = pcall(require, "localization")
    if ok and type(module) == "table" and type(module.get) == "function" then
        config.localization = module
    else
        config.localization = { get = function(key) return "[" .. tostring(key or "") .. "]" end }
    end
end

local function T(key, variables)
    return config.localization.get(key, variables)
end

local TextLayout = require("text_layout")

local function cfg(name, fallback)
    local value = config[name]
    if value == nil then return fallback end
    return value
end

local function clamp(value, lo, hi)
    value = tonumber(value) or lo
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function fileExists(path)
    if io == nil or type(io.open) ~= "function" then return false end
    local ok, file = pcall(io.open, path, "rb")
    if not ok or file == nil then return false end
    pcall(function() file:close() end)
    return true
end

local function looksLikePalWheelScripts(dir)
    if dir == nil or dir == "" then return false end
    dir = tostring(dir):gsub("\\", "/")
    return fileExists(dir .. "/config.lua") and fileExists(dir .. "/main.lua")
end

local function resolveScriptDirectory()
    if type(package) == "table" and type(package.searchpath) == "function"
        and type(package.path) == "string" then
        local ok, found = pcall(package.searchpath, "config", package.path)
        if ok and type(found) == "string" and found ~= "" then
            found = found:gsub("\\", "/")
            local dir = found:match("^(.+)/[^/]+$")
            if looksLikePalWheelScripts(dir) then return dir end
        end
    end

    if debug ~= nil and type(debug.getinfo) == "function" then
        local ok, info = pcall(debug.getinfo, 1, "S")
        if ok and type(info) == "table" and type(info.source) == "string" then
            local source = info.source
            if source:sub(1, 1) == "@" then source = source:sub(2) end
            source = source:gsub("\\", "/")
            local dir = source:match("^(.+)/[^/]+$")
            if looksLikePalWheelScripts(dir) then return dir end
        end
    end

    if type(package) == "table" and type(package.path) == "string" then
        for entry in package.path:gmatch("[^;]+") do
            local normalized = entry:gsub("\\", "/")
            local dir = normalized:match("^(.*)/%?%.lua$")
            if looksLikePalWheelScripts(dir) then return dir end
        end
    end

    local candidates = {
        "Mods/PalWheel/Scripts",
        "ue4ss/Mods/PalWheel/Scripts",
    }
    for _, dir in ipairs(candidates) do
        if looksLikePalWheelScripts(dir) then return dir end
    end

    return "Mods/PalWheel/Scripts"
end

local SCRIPT_DIRECTORY = resolveScriptDirectory()
local MOD_DIRECTORY = SCRIPT_DIRECTORY:gsub("[/\\]Scripts$", "")


local SETTINGS_PATH = MOD_DIRECTORY .. "\\Saved\\settings.lua"
local SHORTCUTS_PATH = MOD_DIRECTORY .. "\\Saved\\shortcuts.tsv"


local settingsLoadState = { notes = {}, status = "unknown" }
local function loadSavedSettings()
    if not fileExists(SETTINGS_PATH) then
        settingsLoadState.status = "missing"
        settingsLoadState.notes[#settingsLoadState.notes + 1] =
            "Saved settings not found; creating defaults"
        return {}
    end
    if type(loadfile) ~= "function" then
        settingsLoadState.status = "unavailable"
        settingsLoadState.notes[#settingsLoadState.notes + 1] =
            "Saved settings unavailable: loadfile is not exposed; existing file left unchanged"
        return {}
    end

    local chunk, loadError = loadfile(SETTINGS_PATH)
    if type(chunk) ~= "function" then
        settingsLoadState.status = "invalid"
        settingsLoadState.notes[#settingsLoadState.notes + 1] =
            "Saved settings ignored and left unchanged: " .. tostring(loadError)
        return {}
    end

    local ok, saved = pcall(chunk)
    if not ok or type(saved) ~= "table" then
        settingsLoadState.status = "invalid"
        settingsLoadState.notes[#settingsLoadState.notes + 1] =
            "Saved settings ignored and left unchanged: file did not return a valid table"
        return {}
    end
    settingsLoadState.status = "valid"
    settingsLoadState.notes[#settingsLoadState.notes + 1] = "Saved settings loaded"
    return saved
end

local savedSettings = loadSavedSettings()

do
    local SAVED_CONFIG_FIELDS = {
        "openKey", "keyboardNextWheelButton", "settingsKey",
        "controllerOpenButton", "controllerNextWheelButton", "controllerPalWheelMenuButton", "openWheelBehavior",
        "controllerInvertY", "controllerZoomEnabled",
        "slowMotionEnabled", "wheelTimeDilation", "mouseDeadzone",
        "keyboardMovementKeys", "controllerMovementKeys",
    }
    local CONTROLLER_BINDING_SET = {}
    for _, name in ipairs(config.controllerBindingKeys or {}) do
        CONTROLLER_BINDING_SET[tostring(name)] = true
    end
    local CONTROLLER_MOVEMENT_SET = {}
    for _, name in ipairs(config.controllerMovementKeys or {}) do
        CONTROLLER_MOVEMENT_SET[tostring(name)] = true
    end
    local function rejectSavedField(field, reason)
        settingsLoadState.notes[#settingsLoadState.notes + 1] =
            "Invalid " .. tostring(field) .. " ignored; " .. tostring(reason)
    end
    local function validateMovementList(field, source)
        if type(source) ~= "table" then return nil end
        local validated, count, maximum = {}, 0, 0
        for index, value in pairs(source) do
            local name = type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
            if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or name == "" then
                return nil
            end
            if field == "keyboardMovementKeys" then
                if type(config.isCanonicalKeyboardBindingKey) == "function"
                    and config.isCanonicalKeyboardBindingKey(name) ~= true then return nil end
            elseif CONTROLLER_MOVEMENT_SET[name] ~= true then
                return nil
            end
            validated[index] = name
            count = count + 1
            if index > maximum then maximum = index end
        end
        if count == 0 or count ~= maximum then return nil end
        return validated
    end
    for _, field in ipairs(SAVED_CONFIG_FIELDS) do
        local value = savedSettings[field]
        if value ~= nil then
            if field == "keyboardMovementKeys" or field == "controllerMovementKeys" then
                local validated = validateMovementList(field, value)
                if validated == nil then
                    rejectSavedField(field, "packaged movement-key list retained")
                else
                    config[field] = validated
                end
            elseif field == "openKey" or field == "keyboardNextWheelButton" or field == "settingsKey" then
                if type(value) ~= "string"
                    or (type(config.isCanonicalKeyboardBindingKey) == "function"
                        and config.isCanonicalKeyboardBindingKey(value) ~= true) then
                    rejectSavedField(field, "expected a current Unreal FKey name")
                else
                    config[field] = value
                end
            elseif field == "controllerOpenButton" or field == "controllerNextWheelButton"
                or field == "controllerPalWheelMenuButton" then
                if type(value) ~= "string" or CONTROLLER_BINDING_SET[value] ~= true then
                    rejectSavedField(field, "expected a supported current controller button")
                else
                    config[field] = value
                end
            elseif field == "openWheelBehavior" then
                if value ~= "hold" and value ~= "toggle" then
                    rejectSavedField(field, "expected hold or toggle")
                else
                    config[field] = value
                end
            elseif field == "controllerInvertY" or field == "controllerZoomEnabled"
                or field == "slowMotionEnabled" then
                if type(value) ~= "boolean" then
                    rejectSavedField(field, "expected a boolean")
                else
                    config[field] = value
                end
            elseif field == "wheelTimeDilation" then
                if type(value) ~= "number" or value < 0.01 or value > 1.0 then
                    rejectSavedField(field, "expected a number from 0.01 to 1.0")
                else
                    config[field] = value
                end
            elseif field == "mouseDeadzone" then
                if type(value) ~= "number" or value < 5 or value > 795 then
                    rejectSavedField(field, "expected a number from 5 to 795")
                else
                    config[field] = value
                end
            end
        end
    end
    config.openWheelBehavior = tostring(config.openWheelBehavior or "hold")
    if config.openWheelBehavior ~= "toggle" then config.openWheelBehavior = "hold" end
    config.controllerStickDeadzone = 0.60
    config.controllerEarlyReturnDistance = 0.15
    if savedSettings.controllerHighlightHapticsEnabled ~= nil then
        if type(savedSettings.controllerHighlightHapticsEnabled) == "boolean" then
            config.controllerHighlightHapticsLevel =
                savedSettings.controllerHighlightHapticsEnabled and 3 or 0
        else
            rejectSavedField("controllerHighlightHapticsEnabled", "expected a boolean")
        end
    end
end
local MOD = "[PalWheel] "
local VIS_HIT_TEST_INVISIBLE = 3
local TWO_PI = math.pi * 2.0
local PAGE_SIZE = 12
local PAGE_COUNT = 3
local TOTAL_ASSIGNMENT_SLOTS = PAGE_SIZE * PAGE_COUNT
local DEFAULT_PARTY_CAPACITY = 5
local MAX_DYNAMIC_PARTY_CAPACITY = 4096

local function partyActionNumber(id)
    if type(id) ~= "string" then return nil end
    local number = tonumber(string.match(string.lower(id), "^pal(%d+)$"))
    if number == nil then return nil end
    number = math.floor(number)
    if number < 1 or number > MAX_DYNAMIC_PARTY_CAPACITY then return nil end
    return number
end

local function makePartyDefinition(number)
    number = math.floor(tonumber(number) or 1)
    return {
        id = "pal" .. tostring(number),
        label = T("palNumber", { number = number }),
        short = "P" .. tostring(number),
        kind = "pal",
        index = number - 1,
    }
end

local function assetFileExists(filename)
    if io == nil or type(io.open) ~= "function" then return false end
    local file = io.open(MOD_DIRECTORY .. "\\Assets\\" .. filename, "rb")
    if file == nil then return false end
    pcall(function() file:close() end)
    return true
end

local function discoverWheelSkins()
    local found = {}
    for index = 0, 99 do
        local filename = string.format("wheel_%02d.png", index)
        if assetFileExists(filename) then found[#found + 1] = filename end
    end
    if #found == 0 then
        found = { "wheel_01.png", "wheel_02.png" }
    end
    return found
end

local WHEEL_SKINS = discoverWheelSkins()
local WHEEL_SKIN_SET = {}
for _, filename in ipairs(WHEEL_SKINS) do WHEEL_SKIN_SET[filename] = true end

local function defaultWheelSkin()
    local configured = tostring(cfg("wheelSkin", "wheel_02.png") or "")
    if string.match(configured, "^wheel_%d%d$") then configured = configured .. ".png" end
    if WHEEL_SKIN_SET[configured] then return configured end
    if WHEEL_SKIN_SET["wheel_02.png"] then return "wheel_02.png" end
    return WHEEL_SKINS[1]
end

local function validWheelSkin(value)
    value = tostring(value or "")
    if string.match(value, "^wheel_%d%d$") then value = value .. ".png" end
    if WHEEL_SKIN_SET[value] then return value end
    return defaultWheelSkin()
end

if savedSettings.wheelSkin ~= nil then
    config.wheelSkin = validWheelSkin(savedSettings.wheelSkin)
end


local function rawSavedPalWheelAssignments(settings)
    if type(settings) ~= "table" then return nil end
    local values, any = {}, false
    for wheel = 1, PAGE_COUNT do
        local source = settings["palWheel" .. tostring(wheel) .. "Assignments"]
        if type(source) == "table" then
            any = true
            for slot = 1, PAGE_SIZE do
                values[((wheel - 1) * PAGE_SIZE) + slot] = source[slot]
            end
        end
    end
    return any and values or nil
end

local savedPalWheelAssignments = rawSavedPalWheelAssignments(savedSettings)

local function maxReferencedPartySlot(assignments, settings)
    local maximum = DEFAULT_PARTY_CAPACITY
    local function consider(values)
        if type(values) ~= "table" then return end
        for _, id in pairs(values) do
            local number = partyActionNumber(id)
            if number ~= nil and number > maximum then maximum = number end
        end
    end
    consider(assignments)
    if type(settings) == "table" then
        consider(settings.auxWheel1Assignments)
        consider(settings.auxWheel2Assignments)
    end
    return maximum
end

local INITIAL_PARTY_CATALOG_CAPACITY =
    maxReferencedPartySlot(savedPalWheelAssignments, savedSettings)

local COLORS = {
    background = { R = 0.0, G = 0.0, B = 0.0,
        A = clamp(cfg("wheelBackgroundOpacity", 0.68), 0.20, 0.92) },
    
    weapon = { R = 0.145, G = 0.388, B = 0.922, 
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    pal = { R = 0.086, G = 0.639, B = 0.290, 
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    menu = { R = 0.486, G = 0.227, B = 0.929, 
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    palworldaction = { R = 0.78, G = 0.34, B = 0.08, 
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    shortcut = { R = 0.000, G = 0.588, B = 0.533, 
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    utility = { R = 0.620, G = 0.106, B = 0.106, 
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    emote = { R = 0.859, G = 0.153, B = 0.467, 
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    sphere = { R = 0.031, G = 0.569, B = 0.698, 
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    empty = { R = 0.16, G = 0.18, B = 0.22,
        A = math.min(clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0), 0.45) },
    selected = { R = 0.98, G = 0.68, B = 0.08,
        A = clamp(cfg("wheelSelectedOpacity", 0.92), 0.10, 1.0) },
    unavailable = { R = 0.88, G = 0.12, B = 0.10,
        A = clamp(cfg("wheelSelectedOpacity", 0.92), 0.10, 1.0) },
    activated = { R = 0.10, G = 0.88, B = 0.92,
        A = clamp(cfg("wheelSelectedOpacity", 0.92), 0.10, 1.0) },
    center = { R = 0.035, G = 0.045, B = 0.065,
        A = clamp(cfg("wheelCenterOpacity", 0.60), 0.05, 1.0) },
    divider = { R = 0.14, G = 0.28, B = 0.38,
        A = clamp(cfg("wheelDividerOpacity", 0.42), 0.05, 1.0) },
    panel = { R = 0.025, G = 0.035, B = 0.055, A = 0.97 },
    row = { R = 0.10, G = 0.12, B = 0.17, A = 0.96 },
    rowAlt = { R = 0.075, G = 0.09, B = 0.13, A = 0.96 },
    button = { R = 0.18, G = 0.23, B = 0.34, A = 1.0 },
    saveIdle = { R = 0.30, G = 0.31, B = 0.33, A = 1.0 },
    saveDirty = { R = 0.133, G = 0.545, B = 0.133, A = 1.0 }, 
    text = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 },
    mercyEquippedText = { R = 0.20, G = 0.90, B = 0.30, A = 1.0 },
    mercyNoneText = { R = 0.95, G = 0.18, B = 0.14, A = 1.0 },
    blocker = { R = 0.0, G = 0.0, B = 0.0, A = 0.001 },
}

local BASE_FUNCTION_CATALOG = {
    { id = "empty", label = T("empty"), short = "--", kind = "empty" },
    { id = "weapon1", label = T("weaponNumber", { number = 1 }), short = "W1", kind = "weapon", index = 0 },
    { id = "weapon2", label = T("weaponNumber", { number = 2 }), short = "W2", kind = "weapon", index = 1 },
    { id = "weapon3", label = T("weaponNumber", { number = 3 }), short = "W3", kind = "weapon", index = 2 },
    { id = "weapon4", label = T("weaponNumber", { number = 4 }), short = "W4", kind = "weapon", index = 3 },
    { id = "weapon5", label = T("weaponNumber", { number = 5 }), short = "W5", kind = "weapon", index = 4 },
    { id = "weapon6", label = T("weaponNumber", { number = 6 }), short = "W6", kind = "weapon", index = 5 },
    { id = "pal1", label = T("palNumber", { number = 1 }), short = "P1", kind = "pal", index = 0 },
    { id = "pal2", label = T("palNumber", { number = 2 }), short = "P2", kind = "pal", index = 1 },
    { id = "pal3", label = T("palNumber", { number = 3 }), short = "P3", kind = "pal", index = 2 },
    { id = "pal4", label = T("palNumber", { number = 4 }), short = "P4", kind = "pal", index = 3 },
    { id = "pal5", label = T("palNumber", { number = 5 }), short = "P5", kind = "pal", index = 4 },
    { id = "mercy", label = T("mercyToggle"), short = T("mercyShort"), kind = "utility" },
    { id = "map", label = T("worldMap"), short = T("worldMapShort"), kind = "menu" },
    { id = "inventory", label = T("characterInventory"), short = T("inventoryShort"), kind = "menu",
        nativeMainMenuType = 8 },
    { id = "party", label = T("partyMenu"), short = T("partyShort"), kind = "menu",
        nativeMainMenuType = 2 },
    { id = "technology", label = T("technology"), short = T("technologyShort"), kind = "menu",
        nativeMainMenuType = 5 },
    { id = "build", label = T("build"), short = T("buildShort"), kind = "menu" },
    { id = "palpedia", label = T("palpedia"), short = T("palpediaShort"), kind = "menu", nativeMainMenuType = 6 },
    { id = "guild", label = T("guild"), short = T("guildShort"), kind = "menu", nativeMainMenuType = 9 },
    { id = "palwheel_options", label = T("options"), short = T("optionsShort"), kind = "menu" },
    { id = "mission", label = T("mission"), short = T("missionShort"), kind = "menu", nativeMainMenuType = 10 },
    { id = "feed_pal", label = T("feedPal"), short = T("feedPalShort"), kind = "palworldaction",
        nativeBranch = "feed", requiresSummonedPal = true },
    { id = "pet_pal", label = T("petPal"), short = T("petPalShort"), kind = "palworldaction",
        nativeBranch = "pet", requiresSummonedPal = true },
    { id = "photo_mode", label = T("photoMode"), short = T("photoModeShort"), kind = "palworldaction",
        nativeCommandId = 6 },
    { id = "pal_command_peaceful", label = T("palCommandPeaceful"), short = T("peacefulShort"),
        kind = "palworldaction", nativeCommandId = 5 },
    { id = "pal_command_defensive", label = T("palCommandDefensive"), short = T("defensiveShort"),
        kind = "palworldaction", nativeCommandId = 4 },
    { id = "pal_command_aggressive", label = T("palCommandAggressive"), short = T("aggressiveShort"),
        kind = "palworldaction", nativeCommandId = 3 },
    { id = "emote_0", label = T("beckon"), short = T("beckonShort"), kind = "emote", emoteIndex = 0 },
    { id = "emote_1", label = T("dance"), short = T("danceShort"), kind = "emote", emoteIndex = 1 },
    { id = "emote_2", label = T("wave"), short = T("waveShort"), kind = "emote", emoteIndex = 2 },
    { id = "emote_3", label = T("sitInChair"), short = T("sitInChairShort"), kind = "emote", emoteIndex = 3 },
    { id = "emote_4", label = T("sitOnGround"), short = T("sitOnGroundShort"), kind = "emote", emoteIndex = 4 },
    { id = "emote_5", label = T("surprised"), short = T("surprisedShort"), kind = "emote", emoteIndex = 5 },
    { id = "emote_6", label = T("handOver"), short = T("handOverShort"), kind = "emote", emoteIndex = 6 },
    { id = "emote_7", label = T("sleep"), short = T("sleepShort"), kind = "emote", emoteIndex = 7 },
    { id = "emote_8", label = T("kick"), short = T("kickShort"), kind = "emote", emoteIndex = 8 },
}

local FUNCTION_CATALOG = {}
local FUNCTION_BY_ID = {}
local ACTIVE_SHORTCUTS = {}
local SHORTCUT_RESERVED_IDS = {}
for _, def in ipairs(BASE_FUNCTION_CATALOG) do SHORTCUT_RESERVED_IDS[def.id] = true end
config.sphereWheelRuntime = require("sphere_wheel")
for _, def in ipairs(config.sphereWheelRuntime.definitions) do
    if type(def.labelKey) == "string" and def.labelKey ~= "" then
        def.label = T(def.labelKey)
        def.sphereName = def.label
    end
    if type(def.shortLabelKey) == "string" and def.shortLabelKey ~= "" then
        def.sphereShort = T(def.shortLabelKey)
    end
    SHORTCUT_RESERVED_IDS[def.id] = true
end

local okShortcuts, ShortcutActions = pcall(require, "shortcut_actions")
local shortcutData = nil
if okShortcuts and type(ShortcutActions) == "table"
    and type(ShortcutActions.load) == "function" then
    shortcutData = ShortcutActions.load(SHORTCUTS_PATH, {
        reservedIds = SHORTCUT_RESERVED_IDS,
        controlKeys = { cfg("openKey"), cfg("keyboardNextWheelButton"), cfg("settingsKey") },
        lastGoodPath = SHORTCUTS_PATH .. ".lastgood",
    })
else
    shortcutData = { definitions = {}, active = {}, notes = {
        "shortcut_actions.lua failed to load: " .. tostring(ShortcutActions)
    } }
end

local function rebuildFunctionCatalog(data, partyCatalogCapacity)
    for key in pairs(FUNCTION_BY_ID) do FUNCTION_BY_ID[key] = nil end
    for index = #FUNCTION_CATALOG, 1, -1 do FUNCTION_CATALOG[index] = nil end
    for _, base in ipairs(BASE_FUNCTION_CATALOG) do
        FUNCTION_CATALOG[#FUNCTION_CATALOG + 1] = base
    end
    local dynamicCapacity = math.floor(clamp(
        tonumber(partyCatalogCapacity) or DEFAULT_PARTY_CAPACITY,
        DEFAULT_PARTY_CAPACITY, MAX_DYNAMIC_PARTY_CAPACITY))
    for number = DEFAULT_PARTY_CAPACITY + 1, dynamicCapacity do
        FUNCTION_CATALOG[#FUNCTION_CATALOG + 1] = makePartyDefinition(number)
    end
    for _, def in ipairs((data and data.definitions) or {}) do
        FUNCTION_CATALOG[#FUNCTION_CATALOG + 1] = def
    end
    for i, def in ipairs(FUNCTION_CATALOG) do
        def.catalogIndex = i
        FUNCTION_BY_ID[def.id] = def
    end
    ACTIVE_SHORTCUTS = (data and data.active) or {}
end

rebuildFunctionCatalog(shortcutData, INITIAL_PARTY_CATALOG_CAPACITY)

local DEFAULT_PAL_WHEEL_ASSIGNMENTS = {
    {
        "pal1", "pal2", "pal3", "pal4",
        "pal5", "party", "weapon6", "weapon5",
        "empty", "empty", "empty", "empty",
    },
    {
        "build", "emote_2", "emote_8", "palwheel_options",
        "inventory", "party", "map", "guild",
        "empty", "empty", "empty", "empty",
    },
    {
        "build", "photo_mode", "feed_pal", "pet_pal",
        "inventory", "pal_command_aggressive", "pal_command_defensive", "pal_command_peaceful",
        "empty", "empty", "empty", "empty",
    },
}

local function makeDefaultAssignments()
    local values = {}
    for wheel = 1, PAGE_COUNT do
        for slot = 1, PAGE_SIZE do
            local index = ((wheel - 1) * PAGE_SIZE) + slot
            values[index] = DEFAULT_PAL_WHEEL_ASSIGNMENTS[wheel][slot] or "empty"
        end
    end
    return values
end


local function makeValidatedAssignments(saved)
    local values = makeDefaultAssignments()
    if type(saved) ~= "table" then return values end

    local invalid = 0
    for i = 1, TOTAL_ASSIGNMENT_SLOTS do
        local id = saved[i]
        if type(id) == "string" and FUNCTION_BY_ID[id] ~= nil then
            values[i] = id
        elseif id ~= nil then
            values[i] = "empty"
            invalid = invalid + 1
        end
    end
    if invalid > 0 then
        settingsLoadState.notes[#settingsLoadState.notes + 1] =
            "Saved settings loaded with " .. tostring(invalid)
            .. " invalid assignment(s) replaced by Empty"
    end
    return values
end

local initialVisibleSlotCounts = {}
for page = 1, PAGE_COUNT do
    local key = "palWheel" .. tostring(page) .. "SlotCount"
    local value = savedSettings[key]
    if type(value) ~= "number" or value % 1 ~= 0 or value < 4 or value > 12 then
        if value ~= nil then
            settingsLoadState.notes[#settingsLoadState.notes + 1] =
                "Invalid " .. key .. " ignored; expected an integer from 4 to 12"
        end
        value = cfg(key, 8)
    end
    initialVisibleSlotCounts[page] = math.floor(value)
end

local initialSphereFollowTargetEnabled = cfg("sphereFollowTargetEnabled", true) == true
if type(savedSettings.sphereFollowTargetEnabled) == "boolean" then
    initialSphereFollowTargetEnabled = savedSettings.sphereFollowTargetEnabled
end

local state = {
    open = false,
    editorOpen = false,
    selected = nil,
    lastActivated = nil,
    activePage = 1,
    mainActivePage = 1,
    wheelMode = "main",
    builtWheelMode = nil,
    activeWheelCount = (function()
        local value = savedSettings.palWheelCount
        if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > PAGE_COUNT then
            if value ~= nil then
                settingsLoadState.notes[#settingsLoadState.notes + 1] =
                    "Invalid palWheelCount ignored; expected an integer from 1 to 3"
            end
            value = cfg("palWheelCount", 3)
        end
        return math.floor(value)
    end)(),
    visibleSlotCounts = initialVisibleSlotCounts,
    sphereVisibleSlotCount = (function()
        local value = savedSettings.sphereWheelSlotCount
        if type(value) ~= "number" or value % 1 ~= 0 or value < 5 or value > 10 then
            if value ~= nil then
                settingsLoadState.notes[#settingsLoadState.notes + 1] =
                    "Invalid sphereWheelSlotCount ignored; expected an integer from 5 to 10"
            end
            value = cfg("sphereWheelSlotCount", 10)
        end
        return math.floor(value)
    end)(),
    sphereFollowTargetEnabled = initialSphereFollowTargetEnabled,
    sphereAssignments = config.sphereWheelRuntime.validatedOrder(savedSettings.sphereWheelAssignments),
    wheelSkin = validWheelSkin(savedSettings.wheelSkin or cfg("wheelSkin", "wheel_02.png")),
    assignments = makeValidatedAssignments(savedPalWheelAssignments),
    auxAssignments = config.auxWheelRuntime.validatedAssignments({
        savedSettings.auxWheel1Assignments, savedSettings.auxWheel2Assignments,
    }, FUNCTION_BY_ID),
    pc = nil,
    previousTimeDilation = nil,
    slowMotionApplied = false,
    uiInputApplied = false,
    previousShowMouseCursor = false,
    previousClickEvents = false,
    previousMouseOverEvents = false,
    inputModeFailureLogged = false,
    mouseReadFailureLogged = false,
    cameraLockFailureLogged = false,
    lookInputBlocked = false,
    sphereFollowLookIsolationApplied = false,
    sphereFollowPreviousLookIgnored = false,
    sphereFollowLookIsolationFailureLogged = false,
    moveInputBlocked = false,
    gameplayInputBlocked = false,
    controllerWheelInputSuppressed = false,
    lockedRotation = nil,
    disabledInputActors = {},
    blockedInputComponents = {},
    mousePointerDisabledActors = {},
    mousePointerBlockedComponents = {},
    mousePointerDisableFlagApplied = false,
    uiFontObject = nil,
    uiFontAttempted = false,

    uiStackBaseline = nil,
    uiStackLearned = false,
    uiStackPending = nil,
    uiStackCount = nil,
    uiStackOpen = false,
    uiStackUnreadableLogged = false,
    uiStackLastX = nil,
    uiStackLastY = nil,
    uiStackNextPoll = 0.0,
    idlePc = nil,

    openKeySawDown = false,
    openedAt = 0.0,
    selectionCommitted = false,
    pendingMouseReleaseClose = false,
    clickCommittedAt = 0.0,
    pendingPalSlot = nil,
    pendingMenuId = nil,
    pendingUtilityId = nil,
    pendingSphereId = nil,
    hoverPreviewKey = nil,
    activePalSlot = nil,
    partyCapacity = DEFAULT_PARTY_CAPACITY,
    partyCatalogCapacity = INITIAL_PARTY_CATALOG_CAPACITY,
    partyCapacityDetected = false,
    partyCapacityStableSince = nil,
    partyCapacityNextPoll = 0.0,
    ignoreOpenBindUntil = 0.0,
    keyboardCancelInputs = {},
    keyboardCancelWasDown = {},
    keyboardPageWasDown = false,
    keyboardPagePressLocked = false,
    keyboardPageReleaseSince = nil,
    keyboardPageFKey = nil,

    widget = nil,
    tree = nil,
    root = nil,
    wheelPanel = nil,
    wheelPanelCache = {},
    mainGeometryPrewarmComplete = false,
    mainGeometryPrewarmLogged = false,
    editorPanel = nil,
    clickBlocker = nil,
    clickBlockerSlot = nil,
    sectors = {},
    dividers = {},

    editorRows = {},
    editorCountTexts = {},
    editorCountDropdownRects = {},
    editorCountDropdownOpen = false,
    editorCountDropdownPage = nil,
    editorCountDropdownWidgets = {},
    editorCountOptionRects = {},
    editorWheelCountText = nil,
    editorWheelCountDropdownRect = nil,
    editorWheelCountDropdownOpen = false,
    editorWheelCountDropdownWidgets = {},
    editorWheelCountOptionRects = {},
    editorSkinText = nil,
    editorSkinDropdownRect = nil,
    editorSkinDropdownOpen = false,
    editorSlowMotionText = nil,
    editorSlowMotionRect = nil,
    editorHapticsText = nil,
    editorHapticsRect = nil,
    editorZoomBorder = nil,
    editorZoomText = nil,
    editorZoomRect = nil,
    editorFollowTargetBorder = nil,
    editorFollowTargetText = nil,
    editorFollowTargetRect = nil,
    editorSaveBorder = nil,
    editorSaveRect = nil,
    editorCloseRect = nil,
    editorDraft = nil,
    editorDiscardConfirmOpen = false,
    editorDiscardConfirmWidgets = {},
    editorDiscardConfirmYesRect = nil,
    editorDiscardConfirmNoRect = nil,
    editorSkinDropdownWidgets = {},
    editorSkinOptionRects = {},
    editorPickerOpen = false,
    editorPickingSlot = nil,
    editorPickerLayer = nil,
    editorPickerChildrenInitialized = false,
    editorPickerPanel = nil,
    editorPickerPanelRect = nil,
    editorPickerTitle = nil,
    editorPickerWidgets = {},
    editorPickerRects = {},
    editorPartyWidgets = {},
    editorPartyRects = {},
    editorPartyRowIds = {},
    editorPartyPage = 1,
    editorPartyPageText = nil,
    editorPartyPrevRect = nil,
    editorPartyNextRect = nil,
    editorPartyPrevWidgets = {},
    editorPartyNextWidgets = {},
    editorPalworldWidgets = {},
    editorPalworldRects = {},
    editorPalworldRowIds = {},
    editorPalworldPage = 1,
    editorPalworldPageText = nil,
    editorPalworldPrevRect = nil,
    editorPalworldNextRect = nil,
    editorPalworldPrevWidgets = {},
    editorPalworldNextWidgets = {},
    palworldPickerPages = {
        { "inventory", "party", "technology", "mission", "palpedia", "guild", "palwheel_options", "build", "map" },
        { "feed_pal", "pet_pal", "photo_mode", "pal_command_peaceful", "pal_command_defensive", "pal_command_aggressive" },
    },
    editorShortcutWidgets = {},
    editorShortcutRects = {},
    editorShortcutRowIds = {},
    editorShortcutPage = 1,
    editorShortcutPageText = nil,
    editorShortcutPrevRect = nil,
    editorShortcutNextRect = nil,
    editorShortcutPrevWidgets = {},
    editorShortcutNextWidgets = {},
    editorResetShortcutsRect = nil,
    editorResetConfirmOpen = false,
    editorResetConfirmWidgets = {},
    editorResetConfirmYesRect = nil,
    editorResetConfirmNoRect = nil,
    editorInstructionsRect = nil,
    editorInstructionsOpen = false,
    editorInstructionsCloseRect = nil,
    editorPickingAuxWheel = nil,
    editorPickingAuxSlot = nil,
    editorReturnToAux = false,
    editorMoveBlocked = false,
    editorPreviousMoveIgnored = false,
    editorPawnDisabled = nil,
    editorDisableFlagApplied = false,
    editorCaptureInputMode = false,
    editorCaptureDisableReleased = false,
    editorCaptureDevice = nil,
    editorKeyboard = nil,
    editorClicksReadyAt = 0.0,
    pageText = nil,
    aimSuppressionFailureLogged = false,

    notificationWidget = nil,
    notificationText = nil,
    notificationExpiresAt = 0.0,
    notificationCompact = false,

    mercyAccessoryEquipped = nil,
    zoomHelpWidgets = {},
    zoomHelpPercent = nil,

    visuals = nil,
    editorBuilder = nil,
    instructionsPopup = nil,
    bindingEditor = nil,
    shortcutEditor = nil,
    sphereEditor = nil,
    auxEditor = nil,
    controllerUiNavigation = nil,
    keyboardOpenWasDown = false,
    keyboardOpenHandledAt = 0.0,
    keyboardToggleOpenArmed = false,
    keyboardToggleCloseArmed = false,
    keyboardMouseNeutralX = nil,
    keyboardMouseNeutralY = nil,
    keyboardMouseNeutralReady = false,
    hybridControllerSelectionActive = false,
    openInputSource = nil,
    mousePointerMode = false,
    
    
    
    mousePresentationRemembered = false,
    mousePointerLastX = nil,
    mousePointerLastY = nil,
    uiPrebuildReadyAt = math.huge,
    sessionReady = false,

    classCache = {},
    cachedGameInstance = nil,
    cachedFishing = nil,
    cachedPlayer = nil,
    playerCacheNextPoll = 0.0,
    cachedPartyHolder = nil,
    keyInjectDll = SCRIPT_DIRECTORY .. "\\PalworldKeyInjector.dll",
    wheelBackgroundTexture = nil,
    iconRuntime = nil,
    glyphRuntime = nil,
    controllerGlyphCommonInputSubsystem = nil,
    controllerGlyphBroadScanNextAt = 0.0,
    controllerGlyphPlatformSettingsScanned = false,
    keyboardGlyphRuntime = nil,
    auxiliaryRuntime = nil,
}

local function log(message, force)
    if force or cfg("verboseLogging", false) then
        print(MOD .. tostring(message) .. "\n")
    end
end

for _, note in ipairs((shortcutData and shortcutData.notes) or {}) do
    log(note, true)
end

local function writeAtomicLua(path, lines, description)
    local okStore, fileStore = pcall(require, "file_store")
    if not okStore or type(fileStore) ~= "table"
        or type(fileStore.writeText) ~= "function" then
        log(description .. " save failed: file_store.lua is unavailable", true)
        return false
    end
    local ok, why = fileStore.writeText(path, table.concat(lines, "\r\n"), {
        backupPath = path .. ".lastgood",
        keepBackup = true,
    })
    if not ok then log(description .. " save failed: " .. tostring(why), true) end
    return ok == true
end

local function appendAssignmentBlock(lines, name, values, count)
    lines[#lines + 1] = "    " .. tostring(name) .. " = {"
    for slot = 1, count do
        local id = values and values[slot] or "empty"
        if type(id) ~= "string" or FUNCTION_BY_ID[id] == nil then id = "empty" end
        lines[#lines + 1] = "        " .. string.format("%q", id) .. ","
    end
    lines[#lines + 1] = "    },"
end

local function saveSettings()
    local lines = {
        "return {",
        "    palWheelCount = " .. tostring(math.floor(state.activeWheelCount)) .. ",",
        "    palWheel1SlotCount = " .. tostring(math.floor(state.visibleSlotCounts[1])) .. ",",
        "    palWheel2SlotCount = " .. tostring(math.floor(state.visibleSlotCounts[2])) .. ",",
        "    palWheel3SlotCount = " .. tostring(math.floor(state.visibleSlotCounts[3])) .. ",",
        "",
    }

    for wheel = 1, PAGE_COUNT do
        local values = {}
        for slot = 1, PAGE_SIZE do
            values[slot] = state.assignments[((wheel - 1) * PAGE_SIZE) + slot]
        end
        appendAssignmentBlock(lines, "palWheel" .. tostring(wheel) .. "Assignments", values, PAGE_SIZE)
        lines[#lines + 1] = ""
    end

    lines[#lines + 1] = "    sphereWheelSlotCount = " .. tostring(math.floor(state.sphereVisibleSlotCount)) .. ","
    lines[#lines + 1] = "    sphereFollowTargetEnabled = " .. tostring(state.sphereFollowTargetEnabled == true) .. ","
    lines[#lines + 1] = "    sphereWheelAssignments = {"
    for index = 1, 10 do
        lines[#lines + 1] = "        " .. string.format("%q", tostring(
            state.sphereAssignments[index] or config.sphereWheelRuntime.defaultOrder[index])) .. ","
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = ""

    appendAssignmentBlock(lines, "auxWheel1Assignments", state.auxAssignments[1], 4)
    lines[#lines + 1] = ""
    appendAssignmentBlock(lines, "auxWheel2Assignments", state.auxAssignments[2], 4)
    lines[#lines + 1] = ""

    lines[#lines + 1] = "    keyboardMovementKeys = {"
    for _, name in ipairs(cfg("keyboardMovementKeys", {}) or {}) do
        lines[#lines + 1] = "        " .. string.format("%q", tostring(name or "")) .. ","
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    controllerMovementKeys = {"
    for _, name in ipairs(cfg("controllerMovementKeys", {}) or {}) do
        lines[#lines + 1] = "        " .. string.format("%q", tostring(name or "")) .. ","
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = ""

    lines[#lines + 1] = "    wheelSkin = " .. string.format("%q", validWheelSkin(state.wheelSkin)) .. ","
    lines[#lines + 1] = "    mouseDeadzone = " .. tostring(math.floor(tonumber(cfg("mouseDeadzone", 48)) or 48)) .. ","
    lines[#lines + 1] = ""

    lines[#lines + 1] = "    openKey = " .. string.format("%q", tostring(cfg("openKey", "CapsLock"))) .. ","
    lines[#lines + 1] = "    keyboardNextWheelButton = " .. string.format("%q", tostring(cfg("keyboardNextWheelButton", "MiddleMouseButton"))) .. ","
    lines[#lines + 1] = "    settingsKey = " .. string.format("%q", tostring(cfg("settingsKey", "F7"))) .. ","
    lines[#lines + 1] = ""

    lines[#lines + 1] = "    controllerOpenButton = " .. string.format("%q", tostring(cfg("controllerOpenButton", "Gamepad_LeftShoulder"))) .. ","
    lines[#lines + 1] = "    controllerNextWheelButton = " .. string.format("%q", tostring(cfg("controllerNextWheelButton", "Gamepad_RightShoulder"))) .. ","
    lines[#lines + 1] = "    controllerPalWheelMenuButton = " .. string.format("%q", tostring(cfg("controllerPalWheelMenuButton", "Gamepad_RightThumbstick"))) .. ","
    lines[#lines + 1] = "    openWheelBehavior = " .. string.format("%q", tostring(cfg("openWheelBehavior", "hold"))) .. ","
    lines[#lines + 1] = "    controllerInvertY = " .. tostring(cfg("controllerInvertY", true) == true) .. ","
    lines[#lines + 1] = "    controllerZoomEnabled = " .. tostring(cfg("controllerZoomEnabled", true) == true) .. ","
    lines[#lines + 1] = "    controllerHighlightHapticsEnabled = " .. tostring(math.floor(clamp(cfg("controllerHighlightHapticsLevel", 3), 0, 3)) > 0) .. ","
    lines[#lines + 1] = ""

    lines[#lines + 1] = "    slowMotionEnabled = " .. tostring(cfg("slowMotionEnabled", true) == true) .. ","
    lines[#lines + 1] = "    wheelTimeDilation = " .. tostring(clamp(cfg("wheelTimeDilation", 0.08), 0.01, 1.0)) .. ","
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""

    local settingsSaved = writeAtomicLua(SETTINGS_PATH, lines, "Settings")
    if settingsSaved then
        log("Saved user settings and all wheel assignments")
    end
    return settingsSaved
end

for _, note in ipairs(settingsLoadState.notes) do log(note, true) end
if settingsLoadState.status == "missing" then saveSettings() end

local function alive(object)
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

do
    local okIcons, IconRuntime = pcall(require, "icon_runtime")
    if okIcons and type(IconRuntime) == "table" and type(IconRuntime.new) == "function" then
        local okNew, runtime = pcall(IconRuntime.new, { alive = alive, log = log })
        if okNew and type(runtime) == "table" then
            state.iconRuntime = runtime
            log("Runtime Pal/Weapon/Sphere icon layer loaded")
        else
            log("Runtime icon layer unavailable: " .. tostring(runtime), true)
        end
    else
        log("Runtime icon layer unavailable: " .. tostring(IconRuntime), true)
    end
end

do
    local okGlyphs, GamepadGlyphs = pcall(require, "gamepad_glyphs")
    if okGlyphs and type(GamepadGlyphs) == "table" and type(GamepadGlyphs.new) == "function" then
        local okNew, runtime = pcall(GamepadGlyphs.new, {
            log = log,
            familyProvider = function()
                if type(state.detectControllerGlyphFamily) == "function" then
                    return state.detectControllerGlyphFamily(state.pc)
                end
                return nil
            end,
            fallbackFamily = function()
                return cfg("controllerGlyphFallbackFamily", "xbox")
            end,
        })
        if okNew and type(runtime) == "table" then
            state.glyphRuntime = runtime
            log("Native gamepad glyph resolver loaded")
        else
            log("Native gamepad glyph resolver unavailable: " .. tostring(runtime), true)
        end
    else
        log("Native gamepad glyph resolver unavailable: " .. tostring(GamepadGlyphs), true)
    end
end

do
    local okGlyphs, KeyboardGlyphs = pcall(require, "keyboard_glyphs")
    if okGlyphs and type(KeyboardGlyphs) == "table" and type(KeyboardGlyphs.new) == "function" then
        local okNew, runtime = pcall(KeyboardGlyphs.new, { log = log })
        if okNew and type(runtime) == "table" then
            state.keyboardGlyphRuntime = runtime
            log("Native keyboard glyph resolver loaded")
        else
            log("Native keyboard glyph resolver unavailable: " .. tostring(runtime), true)
        end
    else
        log("Native keyboard glyph resolver unavailable: " .. tostring(KeyboardGlyphs), true)
    end
end

local function cls(path)
    local cached = state.classCache[path]
    if alive(cached) then return cached end

    local ok, object = pcall(StaticFindObject, path)
    if ok and alive(object) then
        state.classCache[path] = object
        return object
    end
    return nil
end

local function construct(path, outer)
    local classObject = cls(path)
    if not alive(classObject) or outer == nil then return nil end

    local ok, object = pcall(StaticConstructObject, classObject, outer)
    if ok and alive(object) then return object end
    return nil
end

local function getPlayerController()
    if UEHelpers ~= nil and type(UEHelpers.GetPlayerController) == "function" then
        local ok, pc = pcall(function() return UEHelpers:GetPlayerController() end)
        if ok and alive(pc) then return pc end
    end

    local ok, pc = pcall(FindFirstOf, "PalPlayerController")
    if ok and alive(pc) then return pc end
    return nil
end


local function arrayCount(arr)
    if arr == nil then return nil end

    local ok, value = pcall(function() return arr:GetArrayNum() end)
    if ok and type(value) == "number" and value >= 0 then return value end

    ok, value = pcall(function() return #arr end)
    if ok and type(value) == "number" and value >= 0 then return value end

    local count = 0
    ok = pcall(function()
        arr:ForEach(function() count = count + 1 end)
    end)
    if ok then return count end
    return nil
end

local function getPalHUD(pc)
    if alive(pc) then
        local ok, hud = pcall(function() return pc.MyHUD end)
        if ok and alive(hud) then return hud end
    end

    local ok, hud = pcall(FindFirstOf, "PalHUDInGame")
    if ok and alive(hud) then return hud end
    return nil
end

local function getUiStackCount(pc)
    local hud = getPalHUD(pc)
    if not alive(hud) then return nil end

    local ok, stack = pcall(function() return hud.StackableUIWidgets end)
    if not ok then return nil end
    return arrayCount(stack)
end

local function readPawnXY(pc)
    if not alive(pc) then return nil, nil end
    local okPawn, pawn = pcall(function() return pc.Pawn end)
    if not okPawn or not alive(pawn) then return nil, nil end

    local ok, pos = pcall(function() return pawn:K2_GetActorLocation() end)
    if not ok or pos == nil then
        ok, pos = pcall(function() return pawn:GetActorLocation() end)
    end
    if not ok or pos == nil then return nil, nil end

    local okValues, x, y = pcall(function()
        return tonumber(pos.X), tonumber(pos.Y)
    end)
    if not okValues then return nil, nil end
    return x, y
end

local function ensureUiFallbackBaseline()
    if state.uiStackBaseline ~= nil then return end
    state.uiStackBaseline = math.floor(clamp(cfg("uiStackFallbackBaseline", 1), 0, 20))
end

local function refreshGameUiState(pc, force)
    ensureUiFallbackBaseline()

    local now = os.clock()
    local pollSeconds = clamp(cfg("uiStackPollMs", 200), 50, 1000) / 1000.0
    if not force and now < state.uiStackNextPoll then
        return state.uiStackOpen
    end
    state.uiStackNextPoll = now + pollSeconds

    if not alive(pc) then
        state.uiStackOpen = true
        return true
    end

    local count = getUiStackCount(pc)
    state.uiStackCount = count
    if count == nil then
        if not state.uiStackUnreadableLogged then
            state.uiStackUnreadableLogged = true
            log("WARNING: PalHUD StackableUIWidgets is unreadable; menu guard cannot classify game screens", true)
        end
        state.uiStackOpen = false
        return false
    end

    local x, y = readPawnXY(pc)
    local moved = 0.0
    if x ~= nil and y ~= nil and state.uiStackLastX ~= nil and state.uiStackLastY ~= nil then
        local dx, dy = x - state.uiStackLastX, y - state.uiStackLastY
        local d2 = dx * dx + dy * dy
        local teleport = clamp(cfg("uiCalibrationTeleportDistance", 20000), 1000, 100000)
        if d2 <= teleport * teleport then moved = math.sqrt(d2) end
    end
    if x ~= nil and y ~= nil then
        state.uiStackLastX, state.uiStackLastY = x, y
    end

    local moveMin = clamp(cfg("uiCalibrationMoveDistance", 25), 1, 1000)
    if moved > moveMin and not state.open then
        if state.uiStackPending == count then
            if state.uiStackBaseline ~= count or not state.uiStackLearned then
                state.uiStackBaseline = count
                state.uiStackLearned = true
                log("Game UI stack calibrated at " .. tostring(count)
                    .. "; higher counts block PalWheel", true)
            end
        else
            state.uiStackPending = count
        end
        state.uiStackOpen = false
        return false
    end

    state.uiStackPending = nil
    state.uiStackOpen = count > state.uiStackBaseline
    return state.uiStackOpen
end

local function canOpenWheelDuringGameplay(pc)
    if not alive(pc) then return false, "no local PlayerController" end

    local okPawn, pawn = pcall(function() return pc.Pawn end)
    if not okPawn or not alive(pawn) then
        return false, "no playable pawn"
    end

    if refreshGameUiState(pc, true) then
        return false, "a Palworld screen is already open (UI stack "
            .. tostring(state.uiStackCount) .. "/" .. tostring(state.uiStackBaseline) .. ")"
    end
    return true, nil
end

local function hasLoadout(pawn)
    if not alive(pawn) then return false end
    local ok, loadout = pcall(function() return pawn.LoadoutSelectorComponent end)
    return ok and alive(loadout)
end

local function getGameInstance()
    if alive(state.cachedGameInstance) then return state.cachedGameInstance end
    local ok, gameInstance = pcall(FindFirstOf, "GameInstance")
    if ok and alive(gameInstance) then
        state.cachedGameInstance = gameInstance
        return gameInstance
    end
    return nil
end

local function getFishingComponent()
    if alive(state.cachedFishing) then return state.cachedFishing end
    local ok, fishing = pcall(FindFirstOf, "PalFishingComponent")
    if ok and alive(fishing) then
        state.cachedFishing = fishing
        return fishing
    end
    return nil
end

local function getLocalPlayerCharacter()
    local pc = state.pc
    if not alive(pc) then pc = getPlayerController() end

    if alive(pc) then
        local okPawn, pawn = pcall(function() return pc.Pawn end)
        if okPawn and hasLoadout(pawn) then
            state.cachedPlayer = pawn
            return pawn
        end
    end

    local gameInstance = getGameInstance()
    if alive(gameInstance) then
        local ok, player = pcall(function()
            local localPlayers = gameInstance.LocalPlayers
            if localPlayers == nil or #localPlayers == 0 then return nil end
            local localPc = localPlayers[1].PlayerController
            if not alive(localPc) then return nil end
            local pawn = localPc.Pawn
            if hasLoadout(pawn) then return pawn end
            return nil
        end)
        if ok and alive(player) then
            state.cachedPlayer = player
            return player
        end
    end

    if alive(state.cachedPlayer) and hasLoadout(state.cachedPlayer) then
        return state.cachedPlayer
    end
    return nil
end

local function flushPressedKeys(pc)
    if not alive(pc) then return end
    pcall(function()
        local playerInput = pc.PlayerInput
        if alive(playerInput) then playerInput:FlushPressedKeys() end
    end)
end

local function rememberAndBlockInputComponent(actor)
    if not alive(actor) then return end
    local ok, component = pcall(function() return actor.InputComponent end)
    if not ok or not alive(component) then return end

    local previous = false
    local okPrevious, value = pcall(function() return component.bBlockInput end)
    if okPrevious then previous = value == true end

    state.blockedInputComponents[#state.blockedInputComponents + 1] = {
        component = component,
        previous = previous,
    }
    pcall(function() component.bBlockInput = true end)
end

local function actorAlreadyListed(actor)
    for _, existing in ipairs(state.disabledInputActors) do
        if existing == actor then return true end
    end
    return false
end

local function disableActorInput(actor, pc)
    if not alive(actor) or not alive(pc) or actorAlreadyListed(actor) then return end

    rememberAndBlockInputComponent(actor)
    local ok = pcall(function() actor:DisableInput(pc) end)
    if ok then state.disabledInputActors[#state.disabledInputActors + 1] = actor end
end


state.setMousePointerGameplaySuppressed = function(enabled)
    enabled = enabled == true
    local pc = state.pc
    if not alive(pc) then return not enabled end

    if enabled then
        if state.mousePointerDisableFlagApplied
            or #(state.mousePointerDisabledActors or {}) > 0 then return true end

        state.mousePointerDisabledActors = {}
        state.mousePointerBlockedComponents = {}

        local okFlag = pcall(function()
            pc:SetDisableInputFlag(FName("PalWheelMousePointer"), true)
        end)
        state.mousePointerDisableFlagApplied = okFlag

        local candidates = {}
        local pawn = nil
        pcall(function() pawn = pc.Pawn end)
        if alive(pawn) then candidates[#candidates + 1] = pawn end
        local player = getLocalPlayerCharacter()
        if alive(player) and player ~= pawn then candidates[#candidates + 1] = player end

        for _, actor in ipairs(candidates) do
            local component = nil
            pcall(function() component = actor.InputComponent end)
            if alive(component) then
                local previous = false
                pcall(function() previous = component.bBlockInput == true end)
                state.mousePointerBlockedComponents[#state.mousePointerBlockedComponents + 1] = {
                    component = component, previous = previous,
                }
                pcall(function() component.bBlockInput = true end)
            end
            local okDisable = pcall(function() actor:DisableInput(pc) end)
            if okDisable then
                state.mousePointerDisabledActors[#state.mousePointerDisabledActors + 1] = actor
            end
        end
        flushPressedKeys(pc)
        log("Mouse direct-click gameplay input suppressed before LMB handling")
        return state.mousePointerDisableFlagApplied
            or #state.mousePointerDisabledActors > 0
    end

    if state.mousePointerDisableFlagApplied then
        pcall(function() pc:SetDisableInputFlag(FName("PalWheelMousePointer"), false) end)
    end
    for _, actor in ipairs(state.mousePointerDisabledActors or {}) do
        if alive(actor) then pcall(function() actor:EnableInput(pc) end) end
    end
    for _, entry in ipairs(state.mousePointerBlockedComponents or {}) do
        if entry ~= nil and alive(entry.component) then
            pcall(function() entry.component.bBlockInput = entry.previous == true end)
        end
    end
    state.mousePointerDisabledActors = {}
    state.mousePointerBlockedComponents = {}
    state.mousePointerDisableFlagApplied = false
    return true
end

state.setControllerWheelInputSuppressed = function(enabled)
    enabled = enabled == true
    if not enabled then state.sphereWheelNativeInputPassthrough = false end
    if enabled and state.wheelMode ~= "main" then
        if state.controllerWheelInputSuppressed then
            local pc = state.pc
            if not alive(pc) then pc = getPlayerController() end
            if alive(pc) then
                pcall(function()
                    pc:SetDisableInputFlag(FName("PalWheelPageButton"), false)
                end)
            end
            state.controllerWheelInputSuppressed = false
        end
        state.sphereWheelNativeInputPassthrough = true
        log("Sphere wheel preserving native R1/L2 stance input")
        return true
    end
    if state.controllerWheelInputSuppressed == enabled then return true end

    local pc = state.pc
    if not alive(pc) then pc = getPlayerController() end
    if not alive(pc) then return false end

    local ok, err = pcall(function()
        pc:SetDisableInputFlag(FName("PalWheelPageButton"), enabled)
    end)
    if not ok then
        log("Controller wheel input suppression failed: " .. tostring(err), true)
        return false
    end

    state.controllerWheelInputSuppressed = enabled
    return true
end

local function blockGameplayInput(pc)
    state.disabledInputActors = {}
    state.blockedInputComponents = {}
    state.moveInputBlocked = false
    state.gameplayInputBlocked = false
    log("Movement input left enabled while wheel is open")
    return true
end

local function blockEditorGameplayInput(pc)
    state.disabledInputActors = {}
    state.blockedInputComponents = {}
    state.editorPawnDisabled = nil
    state.editorDisableFlagApplied = false
    state.editorMoveBlocked = false
    state.editorPreviousMoveIgnored = false
    state.editorLookBlocked = false
    state.editorPreviousLookIgnored = false
    state.editorCaptureInputMode = false
    state.editorCaptureDisableReleased = false
    state.editorCaptureDevice = nil

    if not alive(pc) then return false end

    
    
    
    
    
    
    rememberAndBlockInputComponent(pc)

    local okPawn, pawn = pcall(function() return pc.Pawn end)
    if okPawn and alive(pawn) then
        disableActorInput(pawn, pc)
        state.editorPawnDisabled = pawn
    end

    
    
    local player = getLocalPlayerCharacter()
    if alive(player) and player ~= pawn then
        disableActorInput(player, pc)
    end

    state.editorPreviousMoveIgnored = false
    pcall(function() state.editorPreviousMoveIgnored = pc:IsMoveInputIgnored() == true end)
    local okMove = pcall(function() pc:SetIgnoreMoveInput(true) end)
    state.moveInputBlocked = okMove
    state.editorMoveBlocked = okMove

    
    
    
    
    
    
    state.editorPreviousLookIgnored = false
    pcall(function() state.editorPreviousLookIgnored = pc:IsLookInputIgnored() == true end)
    local okLook = pcall(function() pc:SetIgnoreLookInput(true) end)
    state.editorLookBlocked = okLook

    local okFlag = pcall(function()
        pc:SetDisableInputFlag(FName("PalWheelEditor"), true)
    end)
    state.editorDisableFlagApplied = okFlag
    state.gameplayInputBlocked = true
    log("Editor gameplay input blocked with PalWheelEditor disable flag, move/look guards, and InputComponent fallback while raw GameOnly polling remains enabled")
    return true
end

local function restoreGameplayInput()
    local pc = state.pc

    local keepMouseSuppressed = state.inputRuntime ~= nil
        and state.inputRuntime.mouseActivationReleaseGuard == true
    if type(state.setMousePointerGameplaySuppressed) == "function"
        and not keepMouseSuppressed then
        state.setMousePointerGameplaySuppressed(false)
    end

    if state.controllerWheelInputSuppressed then
        state.setControllerWheelInputSuppressed(false)
    end

    if state.editorDisableFlagApplied and alive(pc) then
        pcall(function() pc:SetDisableInputFlag(FName("PalWheelEditor"), false) end)
    end

    if state.moveInputBlocked and alive(pc) then
        local restoreIgnored = state.editorPreviousMoveIgnored == true
        pcall(function() pc:SetIgnoreMoveInput(restoreIgnored) end)
    end

    if state.editorLookBlocked and alive(pc) then
        local restoreIgnored = state.editorPreviousLookIgnored == true
        pcall(function() pc:SetIgnoreLookInput(restoreIgnored) end)
    end

    for _, actor in ipairs(state.disabledInputActors or {}) do
        if alive(actor) and alive(pc) then
            pcall(function() actor:EnableInput(pc) end)
        end
    end

    for _, entry in ipairs(state.blockedInputComponents or {}) do
        if entry and alive(entry.component) then
            pcall(function() entry.component.bBlockInput = entry.previous == true end)
        end
    end

    state.disabledInputActors = {}
    state.blockedInputComponents = {}
    state.moveInputBlocked = false
    state.gameplayInputBlocked = false
    state.editorMoveBlocked = false
    state.editorPreviousMoveIgnored = false
    state.editorLookBlocked = false
    state.editorPreviousLookIgnored = false
    state.editorPawnDisabled = nil
    state.editorDisableFlagApplied = false
    state.editorCaptureInputMode = false
    state.editorCaptureDisableReleased = false
    state.editorCaptureDevice = nil
end

local function equipWeaponSlot(index)
    if cfg("weaponSelectionEnabled", true) ~= true then return false end
    index = tonumber(index)
    if index == nil or index < 0 or index > 5 then return false end

    local player = getLocalPlayerCharacter()
    if not alive(player) then
        log("Weapon select failed: local PalPlayerCharacter not found", true)
        return false
    end

    local okLoadout, loadout = pcall(function() return player.LoadoutSelectorComponent end)
    if not okLoadout or not alive(loadout) then
        log("Weapon select failed: LoadoutSelectorComponent unavailable", true)
        return false
    end

    local fishing = getFishingComponent()
    if alive(fishing) then
        local okFishing, isFishing = pcall(function() return fishing:IsFishing() end)
        if okFishing and isFishing == true then
            log("Weapon select blocked while fishing", true)
            return false
        end
    end

    local okEquip, err = pcall(function() loadout:SetWeaponLoadoutIndex(index) end)
    if not okEquip then
        log("Weapon slot call failed: " .. tostring(err), true)
        return false
    end

    log("Requested weapon slot " .. tostring(index + 1))
    return true
end

local function reassertGameplayCursorState(pc)
    if not alive(pc) then return end
    local wbl = cls("/Script/UMG.Default__WidgetBlueprintLibrary")
    if alive(wbl) then
        local ok = pcall(function() wbl:SetInputMode_GameOnly(pc, false) end)
        if not ok then
            pcall(function() wbl:SetInputMode_GameOnly(pc) end)
        end
        pcall(function() wbl:SetFocusToGameViewport() end)
    end
    pcall(function() pc.bShowMouseCursor = state.previousShowMouseCursor end)
    pcall(function() pc.bEnableClickEvents = state.previousClickEvents end)
    pcall(function() pc.bEnableMouseOverEvents = state.previousMouseOverEvents end)
end

local PalActions = require("pal_actions")
state.palActions = PalActions.new({
    cfg = cfg,
    state = state,
    alive = alive,
    getPlayerController = getPlayerController,
    reassertGameplayCursorState = reassertGameplayCursorState,
    log = log,
})
local function readSelectedPartyPalSlot(holder)
    return state.palActions:readSelectedSlot(holder)
end
local function selectPartyPalSlotNatively(pc, index, source)
    return state.palActions:selectSlotNatively(pc, index, source)
end
local function valueString(value)
    return state.palActions:valueString(value)
end
local function normalizedName(value)
    return state.palActions:normalizedName(value)
end

local refreshPartyCapacity = nil

local function previewAssignmentNatively(def, source)
    local key = nil
    if def ~= nil and (def.kind == "pal" or def.kind == "weapon"
        or def.kind == "sphere") then
        key = tostring(def.kind) .. ":"
            .. tostring(def.kind == "sphere" and def.sphereId or def.index)
    end

    if state.hoverPreviewKey == key then return true end
    state.hoverPreviewKey = nil
    if key == nil or not state.open or state.selectionCommitted then return false end

    local pc = state.pc
    if not alive(pc) then pc = getPlayerController() end
    if not alive(pc) then return false end

    if def.kind == "pal" then
        if cfg("palSelectionEnabled", true) ~= true then return false end
        if selectPartyPalSlotNatively(pc, def.index,
            source or "Pal slot hover") then
            state.hoverPreviewKey = key
            return true
        end
        return false
    end
    if def.kind == "weapon" then
        if equipWeaponSlot(def.index) then
            state.hoverPreviewKey = key
            return true
        end
        return false
    end
    if def.kind == "sphere" then
        if state.selectSphere(def, {
            source = source or "sphere slot hover",
            notifyMissing = false,
        }) then
            state.hoverPreviewKey = key
            return true
        end
        return false
    end
    return false
end

local function summonPalSlotNearPlayer(index)
    return state.palActions:summonSlotNearPlayer(index)
end

state.mercyAccessory = require("mercy_accessory").new({
    state = state,
    cfg = cfg,
    alive = alive,
    getPlayerController = getPlayerController,
    normalizedName = normalizedName,
    colors = COLORS,
    log = log,
})

local function playEmoteIndex(index)
    index = math.floor(tonumber(index) or -1)
    if index < 0 or index > 8 then return false end

    local pc = getPlayerController()
    if not alive(pc) then
        log("Emote " .. tostring(index) .. ": PlayerController unavailable", true)
        return false
    end

    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not alive(pawn) then
        log("Emote " .. tostring(index) .. ": player Pawn unavailable", true)
        return false
    end

    local path = "/Game/Pal/Blueprint/Action/Palmi/Emote/BP_Action_Emote_"
        .. tostring(index) .. ".BP_Action_Emote_" .. tostring(index) .. "_C"
    local okClass, emoteClass = pcall(StaticFindObject, path)
    if not okClass or not alive(emoteClass) then
        log("Emote " .. tostring(index) .. ": action class not found", true)
        return false
    end

    local ok, result = pcall(function()
        return pc:ActionComponent_PlayAction_ToServer_ForPlayer(pawn, {}, emoteClass, 0)
    end)
    if not ok then
        log("Emote " .. tostring(index) .. " failed: " .. tostring(result), true)
        return false
    end

    log("Triggered emote " .. tostring(index))
    return true
end

local SphereFollowTarget = require("sphere_follow_target")
state.sphereFollowTarget = SphereFollowTarget.new({
    isEnabled = function() return state.sphereFollowTargetEnabled == true end,
    log = log,
})
state.sphereFollowTarget:ensureHooks()

local SphereActions = require("sphere_actions")
state.sphereActions = SphereActions.new({
    cfg = cfg,
    alive = alive,
    normalizedName = normalizedName,
    getLocalInventoryData = function()
        return state.mercyAccessory:getLocalInventoryData()
    end,
    getLocalPlayerCharacter = getLocalPlayerCharacter,
    showCenterNotification = function(message)
        if type(state.showCenterNotification) == "function" then
            state.showCenterNotification(message)
        end
    end,
    log = log,
})
state.selectSphere = function(sphereDef, options)
    return state.sphereActions:select(sphereDef, options)
end
state.sphereSelected = function(sphereDef)
    return state.sphereActions:isSelected(sphereDef)
end
state.sphereAvailable = function(sphereDef)
    return state.sphereActions:isAvailable(sphereDef)
end
local function processSphereSelectionQueue()
    state.sphereActions:process()
end

local MenuActions = require("menu_actions")
state.menuActions = MenuActions.new({
    cfg = cfg,
    state = state,
    alive = alive,
    cls = cls,
    getPlayerController = getPlayerController,
    valueString = valueString,
    normalizedName = normalizedName,
    definitionById = function(id) return FUNCTION_BY_ID[id] end,
    log = log,
})
local function refreshMovementKeysAllowedWhileOpen(pc)
    state.menuActions:refreshMovementKeys(pc)
end
local function scheduleAssignedMenu(menuId)
    state.menuActions:schedule(menuId)
end
local function processDeferredMenuActions()
    state.menuActions:process()
end

state.palCommandActions = require("pal_command_actions").new({
    alive = alive,
    getPlayerController = getPlayerController,
    log = log,
})
state.palCommandActions:refreshAvailability(FUNCTION_BY_ID)

local function makeFKey(name)
    return { KeyName = FName(name) }
end

local function isKeyDown(pc, key)
    if not alive(pc) or key == nil then return false end
    local ok, value = pcall(function() return pc:IsInputKeyDown(key) end)
    return ok and value == true
end

state.isInputActive = function(pc, key)
    if isKeyDown(pc, key) then return true end
    if not alive(pc) or key == nil then return false end
    local ok, value = pcall(function() return pc:GetInputAnalogKeyState(key) end)
    return ok and math.abs(tonumber(value) or 0) >= 0.10
end


state.cameraZoom = require("camera_zoom").new({
    alive = alive,
    makeFKey = makeFKey,
    isKeyDown = isKeyDown,
    getPlayerController = function()
        return alive(state.pc) and state.pc or state.idlePc
    end,
    isZoomEnabled = function()
        return cfg("controllerZoomEnabled", true) == true
            and state.open and state.wheelMode == "main"
            and state.openInputSource == "controller"
    end,
    log = log,
})

local function getGameplayStatics()
    return cls("/Script/Engine.Default__GameplayStatics")
end

local function getWidgetBlueprintLibrary()
    return cls("/Script/UMG.Default__WidgetBlueprintLibrary")
end

local function getWidgetLayoutLibrary()
    return cls("/Script/UMG.Default__WidgetLayoutLibrary")
end

local function getServerMode(pc)
    if not alive(pc) then return "unknown" end

    local world = nil
    pcall(function() world = pc:GetWorld() end)
    if not alive(world) then return "unknown" end

    local netDriver = nil
    pcall(function() netDriver = world.NetDriver end)
    if not alive(netDriver) then return "singleplayer" end

    local serverConnection = nil
    pcall(function() serverConnection = netDriver.ServerConnection end)
    if alive(serverConnection) then return "coop_client" end

    local palUtility = cls("/Script/Pal.Default__PalUtility")
    if alive(palUtility) then
        local okMode, netModeString = pcall(function()
            return palUtility:GetNetMode(world)
        end)
        if okMode then
            local mode = tostring(netModeString or ""):lower()
            if mode:find("dedicated") then return "dedicated" end
        end
    end

    return "coop_host"
end

local function isMultiplayer(pc)
    local mode = getServerMode(pc)
    return mode == "coop_client" or mode == "coop_host" or mode == "dedicated", mode
end

local function applySlowMotion(pc)
    if cfg("slowMotionEnabled", true) ~= true or not alive(pc) then return false end

    local multiplayer, mode = isMultiplayer(pc)
    if multiplayer then
        log("Multiplayer detected (" .. tostring(mode)
            .. ") - slow motion disabled.", true)
        return false
    end

    local gameplayStatics = getGameplayStatics()
    if not alive(gameplayStatics) then
        log("Slow motion unavailable: GameplayStatics not found", true)
        return false
    end

    local target = clamp(cfg("wheelTimeDilation", 0.08), 0.02, 1.0)
    local previous = 1.0
    local okGet, current = pcall(function()
        return gameplayStatics:GetGlobalTimeDilation(pc)
    end)
    if okGet and tonumber(current) ~= nil then previous = tonumber(current) end

    local okSet = pcall(function()
        gameplayStatics:SetGlobalTimeDilation(pc, target)
    end)
    if not okSet then
        log("Slow motion call failed; wheel will continue at normal speed", true)
        return false
    end

    state.previousTimeDilation = previous
    state.slowMotionApplied = true
    log(string.format("Slow motion applied: %.2fx", target))
    return true
end

local function restoreTimeDilation()
    if not state.slowMotionApplied then
        state.previousTimeDilation = nil
        return
    end

    local pc = state.pc
    local gameplayStatics = getGameplayStatics()
    local restoreValue = clamp(state.previousTimeDilation or 1.0, 0.02, 20.0)

    if alive(pc) and alive(gameplayStatics) then
        local okSet = pcall(function()
            gameplayStatics:SetGlobalTimeDilation(pc, restoreValue)
        end)
        if okSet then
            log(string.format("Game speed restored: %.2fx", restoreValue))
        else
            log("WARNING: could not restore game speed automatically", true)
        end
    end

    state.slowMotionApplied = false
    state.previousTimeDilation = nil
end

local function saveCursorFlags(pc)
    local ok, value = pcall(function() return pc.bShowMouseCursor end)
    state.previousShowMouseCursor = ok and value == true or false

    ok, value = pcall(function() return pc.bEnableClickEvents end)
    state.previousClickEvents = ok and value == true or false

    ok, value = pcall(function() return pc.bEnableMouseOverEvents end)
    state.previousMouseOverEvents = ok and value == true or false
end

local function setCursorFlags(pc, showCursor, enableEvents)
    if not alive(pc) then return end
    if enableEvents == nil then enableEvents = showCursor end
    pcall(function() pc.bShowMouseCursor = showCursor == true end)
    pcall(function() pc.bEnableClickEvents = enableEvents == true end)
    pcall(function() pc.bEnableMouseOverEvents = enableEvents == true end)
end

local function enforcePageAimSuppression()
    if not state.open or cfg("blockPageMouseAim", true) ~= true then return end
    if state.wheelMode ~= "main" then return end
    if string.upper(tostring(cfg("keyboardNextWheelButton") or ""))
        ~= string.upper(tostring(cfg("aimMouseButton") or "")) then return end

    local pc = state.pc
    if not alive(pc) then return end
    local player = nil
    pcall(function() player = pc.Pawn end)
    if not alive(player) then player = getLocalPlayerCharacter() end
    if not alive(player) then return end

    local shooter = nil
    pcall(function() shooter = player.ShooterComponent end)
    if not alive(shooter) then return end

    local okAiming, aiming = pcall(function() return shooter:IsAiming() end)
    if okAiming and aiming ~= true then return end

    local okEnd, endError = pcall(function() shooter:EndAim(true) end)
    if not okEnd and not state.aimSuppressionFailureLogged then
        state.aimSuppressionFailureLogged = true
        log("Right-click aim suppression failed: " .. tostring(endError), true)
    end
end

local function readControlRotation(pc)
    if not alive(pc) then return nil end

    local ok, rotation = pcall(function() return pc:GetControlRotation() end)
    if not ok or rotation == nil then return nil end

    local okValues, pitch, yaw, roll = pcall(function()
        return tonumber(rotation.Pitch), tonumber(rotation.Yaw), tonumber(rotation.Roll)
    end)
    if not okValues or pitch == nil or yaw == nil then return nil end

    return {
        Pitch = pitch,
        Yaw = yaw,
        Roll = roll or 0.0,
    }
end

state.controllerMovementBridge = {
    leftXKey = nil,
    leftYKey = nil,
    failureLogged = false,
}

function state.controllerMovementBridge.readAxis(pc, key)
    if not alive(pc) or key == nil then return 0.0 end
    local ok, value = pcall(function() return pc:GetInputAnalogKeyState(key) end)
    value = ok and tonumber(value) or 0.0
    return clamp(value, -1.0, 1.0)
end

function state.controllerMovementBridge.player(pc)
    local player = nil
    if alive(pc) then pcall(function() player = pc.Pawn end) end
    if not alive(player) then player = getLocalPlayerCharacter() end
    return player
end

function state.controllerMovementBridge.vectorXY(vector)
    if vector == nil then return nil, nil end
    local x, y = nil, nil
    pcall(function() x = tonumber(vector.X) end)
    pcall(function() y = tonumber(vector.Y) end)
    if x == nil or y == nil then
        pcall(function()
            local raw = vector:get()
            if raw ~= nil then
                x = tonumber(raw.X)
                y = tonumber(raw.Y)
            end
        end)
    end
    return x, y
end

function state.controllerMovementBridge.forward()
    if not state.open or state.controller == nil
        or not state.controller:isSession()
        or not state.controllerWheelInputSuppressed then
        return
    end

    local pc = state.pc
    if not alive(pc) then pc = getPlayerController() end
    if not alive(pc) then return end

    if state.controllerMovementBridge.leftXKey == nil then
        state.controllerMovementBridge.leftXKey = makeFKey("Gamepad_LeftX")
        state.controllerMovementBridge.leftYKey = makeFKey("Gamepad_LeftY")
    end

    local x = state.controllerMovementBridge.readAxis(
        pc, state.controllerMovementBridge.leftXKey)
    local y = state.controllerMovementBridge.readAxis(
        pc, state.controllerMovementBridge.leftYKey)
    local magnitude = math.sqrt(x * x + y * y)
    if magnitude <= 0.08 then return end
    if magnitude > 1.0 then
        x = x / magnitude
        y = y / magnitude
    end

    local player = state.controllerMovementBridge.player(pc)
    if not alive(player) then return end

    local forward, right = nil, nil
    pcall(function() forward = player:GetActorForwardVector() end)
    pcall(function() right = player:GetActorRightVector() end)
    if forward == nil or right == nil then return end

    local fx, fy = state.controllerMovementBridge.vectorXY(forward)
    local rotation = readControlRotation(pc)
    local controlYaw = rotation ~= nil and tonumber(rotation.Yaw) or nil
    if fx == nil or fy == nil or controlYaw == nil then return end

    local actorYaw = math.deg(math.atan(fy, fx))
    local delta = math.rad(controlYaw - actorYaw)
    local c = math.cos(delta)
    local s = math.sin(delta)
    local localForward = y * c - x * s
    local localRight = y * s + x * c

    local okForward = pcall(function()
        player:AddMovementInput(forward, localForward, true)
    end)
    local okRight = pcall(function()
        player:AddMovementInput(right, localRight, true)
    end)
    if (not okForward or not okRight)
        and not state.controllerMovementBridge.failureLogged then
        state.controllerMovementBridge.failureLogged = true
        log("Controller movement pass-through failed", true)
    end
end

local function beginCameraLock(pc)
    if not alive(pc) then return false end

    if state.open
        and state.wheelMode ~= "main"
        and state.sphereFollowTargetEnabled == true then
        
        
        
        
        if state.sphereFollowLookIsolationApplied ~= true then
            state.sphereFollowPreviousLookIgnored = false
            pcall(function()
                state.sphereFollowPreviousLookIgnored = pc:IsLookInputIgnored() == true
            end)
        end
        local okIgnore = pcall(function() pc:SetIgnoreLookInput(true) end)
        if okIgnore then
            state.sphereFollowLookIsolationApplied = true
            state.lockedRotation = nil
            state.lookInputBlocked = true
            log("Sphere wheel manual look input isolated; native Follow Target camera pass-through enabled")
            return true
        end

        if not state.sphereFollowLookIsolationFailureLogged then
            state.sphereFollowLookIsolationFailureLogged = true
            log("Sphere wheel look-input isolation unavailable; falling back to hard camera clamp", true)
        end
    end

    if state.sphereFollowLookIsolationApplied == true then
        local releasePc = state.pc
        if alive(releasePc) then
            local restoreIgnored = state.sphereFollowPreviousLookIgnored == true
            pcall(function() releasePc:SetIgnoreLookInput(restoreIgnored) end)
        end
        state.sphereFollowLookIsolationApplied = false
        state.sphereFollowPreviousLookIgnored = false
    end
    state.lockedRotation = readControlRotation(pc)
    if state.lockedRotation == nil then
        log("Camera lock unavailable: could not read control rotation", true)
        return false
    end

    state.lookInputBlocked = false
    log("Camera rotation captured; temporary hard clamp enabled")
    return true
end

local function enforceCameraLock()
    if state.sphereFollowLookIsolationApplied == true then return end

    local postControllerGuard = state.controller ~= nil
        and state.controller:isCameraNeutralGuardActive()
    if (not state.open and not state.editorOpen and not postControllerGuard)
        or state.lockedRotation == nil then return end

    local pc = state.pc
    if not alive(pc) then return end

    local ok = pcall(function()
        pc:SetControlRotation(state.lockedRotation)
    end)

    if not ok and not state.cameraLockFailureLogged then
        state.cameraLockFailureLogged = true
        log("Hard camera rotation clamp failed", true)
    end
end

local function releaseCameraLock()
    if state.controller ~= nil and state.controller:isCameraNeutralGuardActive() then
        
        
        return
    end
    if state.sphereFollowLookIsolationApplied == true then
        local releasePc = state.pc
        if alive(releasePc) then
            local restoreIgnored = state.sphereFollowPreviousLookIgnored == true
            pcall(function() releasePc:SetIgnoreLookInput(restoreIgnored) end)
        end
        state.sphereFollowLookIsolationApplied = false
        state.sphereFollowPreviousLookIgnored = false
    end
    state.lookInputBlocked = false
    state.lockedRotation = nil
    state.cameraLockFailureLogged = false
    state.sphereFollowLookIsolationFailureLogged = false
end

local function applyUIOnlyInput(pc, firstApply)
    if not alive(pc) or not alive(state.widget) then return false end

    local wbl = getWidgetBlueprintLibrary()
    if not alive(wbl) then
        if not state.inputModeFailureLogged then
            state.inputModeFailureLogged = true
            log("Game-and-UI input unavailable: WidgetBlueprintLibrary not found", true)
        end
        return false
    end

    local showHardwareCursor = state.open and state.mousePointerMode == true
    if not state.open then
        showHardwareCursor = cfg("hideHardwareCursorWhileOpen", true) ~= true
    end
    setCursorFlags(pc, showHardwareCursor, true)

    local ok, callError = pcall(function()
        wbl:SetInputMode_GameAndUIEx(pc, state.widget,
            0, false, false)
    end)
    if not ok then
        ok, callError = pcall(function()
            wbl:SetInputMode_GameAndUIEx(pc, state.widget,
                0, false)
        end)
    end

    if ok then
        if not showHardwareCursor then
            pcall(function() pc.bShowMouseCursor = false end)
        end
        state.uiInputApplied = true
        if firstApply then log("Game-and-UI cursor input applied; movement remains enabled") end
        return true
    end

    if not state.inputModeFailureLogged then
        state.inputModeFailureLogged = true
        log("Game-and-UI input-mode call failed; cursor flags only / "
            .. tostring(callError), true)
    end
    return false
end

local function applyEditorInputMode(pc, firstApply)
    if not alive(pc) or not alive(state.widget) then return false end

    local wbl = getWidgetBlueprintLibrary()
    if not alive(wbl) then return false end

    setCursorFlags(pc, true, true)
    local ok = pcall(function()
        wbl:SetInputMode_UIOnlyEx(pc, state.widget, 0, false)
    end)
    if not ok then
        ok = pcall(function()
            wbl:SetInputMode_UIOnlyEx(pc, state.widget, 0)
        end)
    end
    if not ok then
        ok = pcall(function() wbl:SetInputMode_UIOnly(pc, state.widget) end)
    end
    if ok then
        state.uiInputApplied = true
        if firstApply then log("UI-only editor input applied") end
    end
    return ok
end

state.applyEditorControllerUiInputMode = function(pc, firstApply)
    if not alive(pc) or not alive(state.widget) then return false end

    local wbl = getWidgetBlueprintLibrary()
    if not alive(wbl) then return false end

    
    
    
    
    
    
    
    
    local ok = pcall(function() wbl:SetInputMode_GameOnly(pc, false) end)
    if not ok then
        ok = pcall(function() wbl:SetInputMode_GameOnly(pc) end)
    end
    if ok then
        pcall(function() wbl:SetFocusToGameViewport() end)
        local showEditorCursor = state.controllerUiNavigation == nil
            or state.controllerUiNavigation.controllerPresentation ~= true
        setCursorFlags(pc, showEditorCursor, true)
        state.uiInputApplied = true
        if firstApply then
            log("Game-only editor input applied for raw controller face-button polling; manual mouse cursor remains enabled")
        end
    elseif firstApply then
        log("Controller-navigation GameOnly input-mode call failed", true)
    end
    return ok
end

local function applyEditorCaptureInputMode(pc, firstApply)
    if not alive(pc) or not alive(state.widget) then return false end

    local wbl = getWidgetBlueprintLibrary()
    if not alive(wbl) then return false end

    setCursorFlags(pc, true, true)
    local ok = pcall(function()
        wbl:SetInputMode_GameAndUIEx(pc, state.widget,
            0, false, false)
    end)
    if not ok then
        ok = pcall(function()
            wbl:SetInputMode_GameAndUIEx(pc, state.widget,
                0, false)
        end)
    end
    if ok then
        state.uiInputApplied = true
        if firstApply then
            log("Controlled Game-and-UI input enabled for binding capture")
        end
    end
    return ok
end

local function setEditorCaptureInputMode(active, device)
    active = active == true
    device = tostring(device or state.editorCaptureDevice or "keyboard")
    local pc = state.pc
    if not state.editorOpen or not alive(pc) then return not active end

    if active then
        if state.editorCaptureInputMode and state.editorCaptureDevice == device then
            return true
        end
        if device == "keyboard" then
            if state.editorKeyboard == nil or not state.editorKeyboard:isAvailable() then
                log("UMG editor keyboard input is unavailable", true)
                return false
            end
            if state.inputRuntime ~= nil and not state.inputRuntime.suppressionActive then
                local isolated = state.inputRuntime:beginEditorKeyboardIsolation(pc)
                if not isolated then
                    log("Keyboard mapping isolation unavailable; continuing capture with editor gameplay input disabled", true)
                end
            end
            state.editorCaptureInputMode = true
            state.editorCaptureDevice = "keyboard"
            state.editorCaptureDisableReleased = false
            if state.editorDisableFlagApplied then
                pcall(function()
                    pc:SetDisableInputFlag(FName("PalWheelEditor"), true)
                end)
            end
            
            
            pcall(function() state.widget.bIsFocusable = true end)
            applyEditorInputMode(pc, false)
            pcall(function() state.widget:SetUserFocus(pc) end)
            pcall(function() state.widget:SetKeyboardFocus() end)
            state.editorKeyboard:clear()
            return true
        end
        if state.inputRuntime == nil
            or not state.inputRuntime:beginEditorControllerCapture(pc) then
            return false
        end
        
        
        
        state.editorCaptureDisableReleased = false
        if not applyEditorCaptureInputMode(pc, true) then
            log("Binding capture Game-and-UI mode unavailable; continuing with direct controller polling", true)
        end
        state.editorCaptureInputMode = true
        state.editorCaptureDevice = device
        return true
    end

    local previousDevice = state.editorCaptureDevice
    state.editorCaptureInputMode = false
    state.editorCaptureDevice = nil
    if state.editorKeyboard ~= nil then state.editorKeyboard:clear() end
    flushPressedKeys(pc)
    state.keyboardOpenWasDown = false
    state.keyboardPageWasDown = false
    if state.controller ~= nil then
        state.controller.openLatchDown = false
        state.controller.pageWasDown = false
    end
    state.editorCaptureDisableReleased = false
    if state.inputRuntime ~= nil and state.controllerUiNavigation ~= nil
        and type(state.inputRuntime.beginEditorControllerUiIsolation) == "function" then
        if previousDevice == "controller" then state.inputRuntime:endEditorControllerCapture() end
        state.inputRuntime:beginEditorControllerUiIsolation(pc)
    elseif previousDevice == "controller" and state.inputRuntime ~= nil then
        state.inputRuntime:endEditorControllerCapture()
        state.inputRuntime:beginEditorKeyboardIsolation(pc)
    elseif previousDevice == "text" and state.inputRuntime ~= nil then
        state.inputRuntime:beginEditorKeyboardIsolation(pc)
    end
    if state.controllerUiNavigation ~= nil then
        state.applyEditorControllerUiInputMode(pc, false)
    else
        applyEditorInputMode(pc, false)
    end
    state.ignoreOpenBindUntil = os.clock() + 0.20
    return true
end

local function restoreGameInput()
    local pc = state.pc
    local wbl = getWidgetBlueprintLibrary()

    if alive(pc) and alive(wbl) then
        local ok = pcall(function() wbl:SetInputMode_GameOnly(pc, false) end)
        if not ok then
            ok = pcall(function() wbl:SetInputMode_GameOnly(pc) end)
        end
        if not ok then
            pcall(function() wbl:SetFocusToGameViewport() end)
        end
    end

    if alive(pc) then
        pcall(function() pc.bShowMouseCursor = state.previousShowMouseCursor end)
        pcall(function() pc.bEnableClickEvents = state.previousClickEvents end)
        pcall(function() pc.bEnableMouseOverEvents = state.previousMouseOverEvents end)
    end

    state.uiInputApplied = false
    log("Normal game input restored")
end

local function centerHardwareCursor(pc)
    if not alive(pc) then return false end

    local centerX = math.floor(tonumber(cfg("centerX", 960)) or 960)
    local centerY = math.floor(tonumber(cfg("centerY", 540)) or 540)

    state.keyboardMouseNeutralReady = false
    state.keyboardMouseNeutralX = nil
    state.keyboardMouseNeutralY = nil

    local ok = pcall(function() pc:SetMouseLocation(centerX, centerY) end)
    if ok then log("Mouse cursor centred for radial selection") end

    local function captureNeutral()
        if not state.open or not alive(state.pc) then return end
        if state.controller ~= nil and state.controller:isSession() then return end

        local layout = getWidgetLayoutLibrary()
        if not alive(layout) then return end

        local okPos, pos = pcall(function()
            return layout:GetMousePositionOnViewport(state.pc)
        end)
        if not okPos or pos == nil then return end

        local x, y = nil, nil
        pcall(function()
            x = tonumber(pos.X)
            y = tonumber(pos.Y)
        end)
        if x == nil or y == nil then return end

        state.keyboardMouseNeutralX = x
        state.keyboardMouseNeutralY = y
        state.keyboardMouseNeutralReady = true
        state.selected = nil
        state.hoverPreviewKey = nil
        if state.callVisual ~= nil then
            state.callVisual("setDirection", nil, 0.0,
                clamp(cfg("mouseDeadzone", 42), 5,
                    clamp(cfg("mouseMaxRadius", 220), 60, 800) - 5))
        end
    end

    if type(ExecuteWithDelay) == "function" then
        ExecuteWithDelay(12, captureNeutral)
    else
        captureNeutral()
    end

    return ok
end

local VEC = { X = 0.0, Y = 0.0 }
local function setPosition(slot, x, y)
    if slot == nil then return false end
    VEC.X, VEC.Y = x, y
    return pcall(function() slot:SetPosition(VEC) end)
end

local function setSize(slot, width, height)
    if slot == nil then return false end
    VEC.X, VEC.Y = width, height
    return pcall(function() slot:SetSize(VEC) end)
end

local function place(slot, x, y, width, height)
    setPosition(slot, x, y)
    setSize(slot, width, height)
end

local function setVisible(widget, visible)
    if not alive(widget) then return end
    pcall(function() widget:SetVisibility(visible and 0 or 1) end)
end

local function setBorderColor(border, color)
    if not alive(border) then return end
    pcall(function() border:SetBrushColor(color) end)
end

local function setImageColor(image, color)
    if not alive(image) then return end
    pcall(function() image:SetColorAndOpacity(color) end)
end

local function setWidgetRotation(widget, degrees)
    if not alive(widget) then return end
    pcall(function() widget:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
    pcall(function() widget:SetRenderTransformAngle(degrees) end)
end

local function setWidgetScale(widget, scale)
    if not alive(widget) then return end
    pcall(function() widget:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
    pcall(function() widget:SetRenderScale({ X = scale, Y = scale }) end)
end

local function setText(widget, value)
    if not alive(widget) then return false end
    local okText, textValue = pcall(FText, tostring(value or ""))
    if not okText or textValue == nil then return false end
    return pcall(function() widget:SetText(textValue) end)
end

local function addToCanvas(canvas, child)
    if not alive(canvas) or not alive(child) then return nil end
    local ok, slot = pcall(function() return canvas:AddChildToCanvas(child) end)
    if not ok or slot == nil then return nil end
    pcall(function() slot:SetAutoSize(false) end)
    return slot
end

local function assignmentSlotForVisibleIndex(index)
    return (state.activePage - 1) * PAGE_SIZE + index
end

local function wheelRoman(page)
    if page == 1 then return "I" end
    if page == 2 then return "II" end
    return "III"
end

local function visibleSlotCountForPage(page)
    page = math.floor(clamp(tonumber(page) or 1, 1, PAGE_COUNT))
    local value = state.visibleSlotCounts and state.visibleSlotCounts[page] or nil
    if type(value) ~= "number" then value = 12 end
    return math.floor(clamp(value, 4, 12))
end

local function activeVisibleSlotCount()
    if state.wheelMode ~= "main" then
        return math.floor(clamp(state.sphereVisibleSlotCount or 10, 5, 10))
    end
    return visibleSlotCountForPage(state.activePage)
end


local function sphereWheelGeometry(visibleCount)
    visibleCount = math.floor(clamp(tonumber(visibleCount) or 10, 5, 10))
    local layoutByVisible = {
        [10] = { virtualCount = 12, hidden = { 11, 12 } },
        [9]  = { virtualCount = 11, hidden = { 10, 11 } },
        [8]  = { virtualCount = 10, hidden = { 9, 10 } },
        [7]  = { virtualCount = 9,  hidden = { 8, 9 } },
        [6]  = { virtualCount = 8,  hidden = { 7, 8 } },
        [5]  = { virtualCount = 7,  hidden = { 6, 7 } },
    }
    local layout = layoutByVisible[visibleCount] or layoutByVisible[10]
    local virtualCount = layout.virtualCount
    local hiddenLookup = {}
    for _, virtualIndex in ipairs(layout.hidden) do
        hiddenLookup[virtualIndex] = true
    end

    local positions = {}
    local logicalByVirtual = {}
    for virtualIndex = 1, virtualCount do
        if not hiddenLookup[virtualIndex] then
            positions[#positions + 1] = virtualIndex
            logicalByVirtual[virtualIndex] = #positions
        end
    end

    local skippedDividers = {}
    if #layout.hidden >= 2 then
        for i = 2, #layout.hidden do
            local previous = layout.hidden[i - 1]
            local current = layout.hidden[i]
            if current == previous + 1 then
                
                
                
                skippedDividers[current] = true
            end
        end
    end

    return {
        virtualCount = virtualCount,
        positions = positions,
        logicalByVirtual = logicalByVirtual,
        hidden = layout.hidden,
        hiddenLookup = hiddenLookup,
        skippedDividers = skippedDividers,
    }
end

local function assignmentDefinitionByGlobalSlot(globalSlot)
    local id = state.assignments[globalSlot] or "empty"
    return FUNCTION_BY_ID[id] or FUNCTION_BY_ID.empty
end

local function assignmentDefinitionForVisibleIndex(index)
    if state.wheelMode ~= "main" then
        return config.sphereWheelRuntime.byId[state.sphereAssignments[index]]
    end
    return assignmentDefinitionByGlobalSlot(assignmentSlotForVisibleIndex(index))
end

local function colorForDefinition(def)
    if def == nil then return COLORS.empty end
    if def.available == false or def.pending == true then return COLORS.unavailable end
    return COLORS[def.kind] or COLORS.empty
end

local function setDefinitionTextColor(widget, def)
    if not alive(widget) then return end
    
    local color = COLORS.text
    local ok = pcall(function()
        widget:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
    end)
    if ok then return end
    pcall(function() widget:SetColorAndOpacity(color) end)
end

local function setTextColor(widget, color)
    if not alive(widget) or type(color) ~= "table" then return end
    local ok = pcall(function()
        widget:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
    end)
    if ok then return end
    pcall(function() widget:SetColorAndOpacity(color) end)
end

local function updateHighlight()
    for index = 1, activeVisibleSlotCount() do
        local sector = state.sectors[index]
        if sector then
            local def = assignmentDefinitionForVisibleIndex(index)
            sector.globalSlot = assignmentSlotForVisibleIndex(index)

            for page = 1, PAGE_COUNT do
                local layer = sector.pages and sector.pages[page] or nil
                if layer ~= nil then
                    local globalSlot = (page - 1) * PAGE_SIZE + index
                    local pageDef = state.wheelMode ~= "main"
                        and (page == 1 and assignmentDefinitionForVisibleIndex(index)
                            or FUNCTION_BY_ID.empty)
                        or assignmentDefinitionByGlobalSlot(globalSlot)
                    if alive(layer.icon) then
                        setVisible(layer.icon, page == state.activePage)
                    end
                    if alive(layer.label) then
                        setText(layer.label, pageDef.short or pageDef.label)
                        setDefinitionTextColor(layer.label, pageDef)
                        setVisible(layer.label, page == state.activePage)
                    end
                    if alive(layer.detailLabel) then
                        if state.wheelMode == "main" and pageDef.id == "mercy" then
                            local equipped = state.mercyAccessoryEquipped == true
                            setText(layer.detailLabel, T(equipped and "equipped" or "none"))
                            setTextColor(layer.detailLabel, equipped
                                and COLORS.mercyEquippedText or COLORS.mercyNoneText)
                            setVisible(layer.detailLabel, page == state.activePage)
                        else
                            setText(layer.detailLabel, "")
                            setVisible(layer.detailLabel, false)
                        end
                    end
                end
            end

            local bands = sector.bands or {}
            local baseColor = colorForDefinition(def)
            local activated = def.kind == "pal" and state.activePalSlot == def.index
                or state.lastActivated == index
            local markerBack = bands[1]
            local markerFront = bands[2]
            if markerBack ~= nil then
                local selectedColor = COLORS.selected
                if state.selected == index and def ~= nil
                    and (def.available == false or def.pending == true) then
                    selectedColor = COLORS.unavailable
                elseif state.wheelMode ~= "main" and state.selected == index
                    and not state.sphereAvailable(def) then
                    selectedColor = COLORS.unavailable
                end
                setBorderColor(markerBack, state.selected == index
                    and selectedColor or COLORS.divider)
                setWidgetScale(markerBack, state.selected == index
                    and clamp(cfg("wheelSelectedMarkerScale", 1.18), 1.02, 1.60)
                    or 1.0)
            end
            if markerFront ~= nil then
                local frontColor = state.selected ~= index and activated
                    and COLORS.activated or baseColor
                
                
                
                
                if state.selected == index then
                    frontColor = {
                        R = frontColor.R,
                        G = frontColor.G,
                        B = frontColor.B,
                        A = 1.0,
                    }
                end
                setBorderColor(markerFront, frontColor)
                setWidgetScale(markerFront, 1.0)
            end
        end
    end
    local selectedSector = state.selected ~= nil and state.sectors[state.selected] or nil
    local selectedLeft = selectedSector ~= nil and selectedSector.leftDividerIndex or nil
    local selectedRight = selectedSector ~= nil and selectedSector.rightDividerIndex or nil
    for dividerIndex, divider in ipairs(state.dividers or {}) do
        if divider.base ~= nil then setBorderColor(divider.base, COLORS.divider) end
        if divider.glow ~= nil then
            local highlighted = dividerIndex == selectedLeft
                or dividerIndex == selectedRight
            setBorderColor(divider.glow, {
                R = 0.70,
                G = 0.92,
                B = 1.00,
                A = highlighted and 0.88 or 0.0,
            })
        end
    end
    if alive(state.pageText) then
        setText(state.pageText,
            state.wheelMode == "main" and wheelRoman(state.activePage) or "S")
    end
    if state.callVisual ~= nil then
        local selectedDef = state.selected ~= nil
            and assignmentDefinitionForVisibleIndex(state.selected) or nil
        state.callVisual("updateHighlight", selectedDef, state.selected,
            state.activePage, state.sectors, nil, state.wheelMode)
    end
end

local function readMousePosition(pc)
    local layout = getWidgetLayoutLibrary()
    if not alive(layout) or not alive(pc) then return nil, nil end

    local ok, pos = pcall(function()
        return layout:GetMousePositionOnViewport(pc)
    end)
    if not ok or pos == nil then return nil, nil end

    local okValues, x, y = pcall(function()
        return tonumber(pos.X), tonumber(pos.Y)
    end)
    if not okValues or x == nil or y == nil then return nil, nil end
    return x, y
end

local switchWheelPanelForPage

local function switchActivePage()
    if not state.open or state.selectionCommitted or state.wheelMode ~= "main" then
        return false
    end
    local pageCount = math.floor(clamp(state.activeWheelCount or PAGE_COUNT, 1, PAGE_COUNT))
    local targetPage = (state.activePage % pageCount) + 1
    state.selected = nil
    state.lastActivated = nil
    state.hoverPreviewKey = nil

    if type(switchWheelPanelForPage) ~= "function"
        or not switchWheelPanelForPage(targetPage) then
        return false
    end
    state.mainActivePage = state.activePage

    if state.controller == nil or not state.controller:isSession() then
        local mouseX, mouseY = readMousePosition(state.pc)
        state.mousePointerLastX = mouseX
        state.mousePointerLastY = mouseY
    end
    log("Switched to Wheel " .. wheelRoman(state.activePage))
    return true
end

local function destroyWidget()
    if state.haptics ~= nil then state.haptics:reset(state.pc) end
    if state.controller ~= nil then state.controller:reset() end
    if state.inputRuntime ~= nil then state.inputRuntime:resetSuppression() end
    releaseCameraLock()
    restoreGameplayInput()
    if state.open or state.editorOpen then restoreGameInput() end
    restoreTimeDilation()

    if alive(state.widget) then
        pcall(function() state.widget:RemoveFromParent() end)
    end

    state.open = false
    state.editorOpen = false
    state.selected = nil
    state.lastActivated = nil
    state.openKeySawDown = false
    state.keyboardToggleOpenArmed = false
    state.keyboardToggleCloseArmed = false
    state.openedAt = 0.0
    state.openInputSource = nil
    state.mousePointerMode = false
    state.mousePointerLastX = nil
    state.mousePointerLastY = nil
    state.selectionCommitted = false
    state.pendingMouseReleaseClose = false
    state.clickCommittedAt = 0.0
    state.pendingPalSlot = nil
    state.pendingMenuId = nil
    state.pendingUtilityId = nil
    state.pendingSphereId = nil
    state.hoverPreviewKey = nil
    state.keyboardCancelWasDown = {}
    state.keyboardPageWasDown = false
    state.pc = nil
    state.widget = nil
    state.tree = nil
    state.root = nil
    state.wheelPanel = nil
    state.wheelPanelCache = {}
    state.mainGeometryPrewarmComplete = false
    state.mainGeometryPrewarmLogged = false
    state.builtWheelMode = nil
    state.editorPanel = nil
    state.clickBlocker = nil
    state.clickBlockerSlot = nil
    state.sectors = {}
    state.dividers = {}
    state.zoomHelpWidgets = {}
    state.zoomHelpPercent = nil
    if state.auxiliaryRuntime ~= nil then state.auxiliaryRuntime:reset() end
    state.wheelBackgroundTexture = nil
    state.editorRows = {}
    state.editorCountTexts = {}
    state.editorCountDropdownRects = {}
    state.editorCountDropdownOpen = false
    state.editorCountDropdownPage = nil
    state.editorCountDropdownWidgets = {}
    state.editorCountOptionRects = {}
    state.editorWheelCountText = nil
    state.editorWheelCountDropdownRect = nil
    state.editorWheelCountDropdownOpen = false
    state.editorWheelCountDropdownWidgets = {}
    state.editorWheelCountOptionRects = {}
    state.editorSkinText = nil
    state.editorSkinDropdownRect = nil
    state.editorSkinDropdownOpen = false
    state.editorSlowMotionText = nil
    state.editorSlowMotionRect = nil
    state.editorHapticsText = nil
    state.editorHapticsRect = nil
    state.editorZoomBorder = nil
    state.editorZoomText = nil
    state.editorZoomRect = nil
    state.editorFollowTargetBorder = nil
    state.editorFollowTargetText = nil
    state.editorFollowTargetRect = nil
    state.editorSaveBorder = nil
    state.editorSaveRect = nil
    state.editorCloseRect = nil
    state.editorDraft = nil
    state.editorDiscardConfirmOpen = false
    state.editorDiscardConfirmWidgets = {}
    state.editorDiscardConfirmYesRect = nil
    state.editorDiscardConfirmNoRect = nil
    state.editorSkinDropdownWidgets = {}
    state.editorSkinOptionRects = {}
    state.editorPickerOpen = false
    state.editorPickingSlot = nil
    state.editorPickerLayer = nil
    state.editorPickerChildrenInitialized = false
    state.editorPickerPanel = nil
    state.editorPickerPanelRect = nil
    state.editorPickerTitle = nil
    state.editorPickerWidgets = {}
    state.editorPickerRects = {}
    state.editorPartyWidgets = {}
    state.editorPartyRects = {}
    state.editorPartyRowIds = {}
    state.editorPartyPage = 1
    state.editorPartyPageText = nil
    state.editorPartyPrevRect = nil
    state.editorPartyNextRect = nil
    state.editorPartyPrevWidgets = {}
    state.editorPartyNextWidgets = {}
    state.editorPalworldWidgets = {}
    state.editorPalworldRects = {}
    state.editorPalworldRowIds = {}
    state.editorPalworldPage = 1
    state.editorPalworldPageText = nil
    state.editorPalworldPrevRect = nil
    state.editorPalworldNextRect = nil
    state.editorPalworldPrevWidgets = {}
    state.editorPalworldNextWidgets = {}
    state.editorShortcutWidgets = {}
    state.editorShortcutRects = {}
    state.editorShortcutRowIds = {}
    state.editorShortcutPage = 1
    state.editorShortcutPageText = nil
    state.editorShortcutPrevRect = nil
    state.editorShortcutNextRect = nil
    state.editorShortcutPrevWidgets = {}
    state.editorShortcutNextWidgets = {}
    state.editorResetShortcutsRect = nil
    state.editorResetConfirmOpen = false
    state.editorResetConfirmWidgets = {}
    state.editorResetConfirmYesRect = nil
    state.editorResetConfirmNoRect = nil
    state.editorInstructionsRect = nil
    state.editorInstructionsOpen = false
    state.editorInstructionsCloseRect = nil
    state.editorPickingAuxWheel = nil
    state.editorPickingAuxSlot = nil
    state.editorReturnToAux = false
    state.pageText = nil
    if state.callVisual ~= nil then state.callVisual("reset") end
    if state.bindingEditor ~= nil then state.bindingEditor:closePanel(true) end
    if state.shortcutEditor ~= nil then state.shortcutEditor:closePanel(true) end
    if state.sphereEditor ~= nil then state.sphereEditor:closePanel() end
    state.bindingEditor = nil
    state.shortcutEditor = nil
    state.sphereEditor = nil
    state.auxEditor = nil
    state.instructionsPopup = nil
    state.editorBuilder = nil
end

local function createBaseWidget(pc)
    if not alive(pc) then return false end

    local wbl = getWidgetBlueprintLibrary()
    local userWidgetClass = cls("/Script/UMG.UserWidget")
    if not alive(wbl) or not alive(userWidgetClass) then
        log("UI build stopped: UMG classes unavailable", true)
        return false
    end

    local okWorld, world = pcall(function() return pc:GetWorld() end)
    if not okWorld or world == nil then
        log("UI build stopped: world unavailable", true)
        return false
    end

    local okWidget, widget = pcall(function()
        return wbl:Create(world, userWidgetClass, pc)
    end)
    if not okWidget or not alive(widget) then
        log("UI build stopped: UserWidget creation failed", true)
        return false
    end
    state.widget = widget

    local okTree, tree = pcall(function() return widget.WidgetTree end)
    if not okTree or tree == nil then
        log("UI build stopped: WidgetTree unavailable", true)
        destroyWidget()
        return false
    end
    state.tree = tree

    local root = construct("/Script/UMG.CanvasPanel", tree)
    if not alive(root) then
        log("UI build stopped: CanvasPanel construction failed", true)
        destroyWidget()
        return false
    end
    state.root = root

    local okRoot = pcall(function() tree.RootWidget = root end)
    if not okRoot then
        log("UI build stopped: could not assign RootWidget", true)
        destroyWidget()
        return false
    end

    local blocker = construct("/Script/UMG.Button", tree)
    if not alive(blocker) then
        log("UI build stopped: click shield Button could not be constructed", true)
        destroyWidget()
        return false
    end

    local blockerSlot = addToCanvas(root, blocker)
    if blockerSlot == nil then
        log("UI build stopped: click shield could not be added to Canvas", true)
        destroyWidget()
        return false
    end

    local screenW = tonumber(cfg("screenWidth", 1920)) or 1920
    local screenH = tonumber(cfg("screenHeight", 1080)) or 1080
    place(blockerSlot, 0, 0, screenW, screenH)
    pcall(function() blocker:SetRenderOpacity(0.001) end)
    pcall(function() blocker:SetBackgroundColor(COLORS.blocker) end)
    pcall(function() blocker:SetIsFocusable(false) end)
    state.clickBlocker = blocker
    state.clickBlockerSlot = blockerSlot
    return true
end

state.getUIFont = function()
    if state.uiFontAttempted then return state.uiFontObject end
    state.uiFontAttempted = true
    local fontPath = "/Game/Pal/Font/Ft_PalDefaultFont.Ft_PalDefaultFont"
    local fontPackage = "/Game/Pal/Font/Ft_PalDefaultFont"
    local ok, object = pcall(StaticFindObject, fontPath)
    if ok and object ~= nil then
        state.uiFontObject = object
        return object
    end
    if type(LoadAsset) == "function" then
        pcall(function() LoadAsset(fontPackage) end)
        pcall(function() LoadAsset(fontPath) end)
    end
    ok, object = pcall(StaticFindObject, fontPath)
    if ok and object ~= nil then state.uiFontObject = object end
    if state.uiFontObject == nil then
        log("PalDefaultFont unavailable; retaining widget default font", true)
    else
        log("PalDefaultFont loaded for PalWheel UI text")
    end
    return state.uiFontObject
end

local function createCanvasText(tree, root, textValue, x, y, width, height, fontSize, justification,
    minimumFontSize)
    local text = construct("/Script/UMG.TextBlock", tree)
    if not alive(text) then return nil end
    local slot = addToCanvas(root, text)
    if slot == nil then return nil end
    place(slot, x, y, width, height)
    setText(text, textValue)
    if tonumber(fontSize) ~= nil then
        local fittedSize = minimumFontSize ~= nil
            and TextLayout.fitFontSize(textValue, fontSize, width, height, minimumFontSize)
            or tonumber(fontSize)
        pcall(function()
            local font = text.Font
            font.Size = math.floor(fittedSize)
            local fontObject = state.getUIFont()
            if fontObject ~= nil then font.FontObject = fontObject end
            text:SetFont(font)
        end)
    end
    pcall(function() text:SetAutoWrapText(false) end)
    pcall(function() text:SetJustification(tonumber(justification) or 1) end)
    pcall(function() text:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
    return text
end

local function createCenteredCanvasText(tree, root, textValue, centerX, centerY, fontSize,
    maximumWidth, minimumFontSize)
    local text = construct("/Script/UMG.TextBlock", tree)
    if not alive(text) then return nil end
    local slot = addToCanvas(root, text)
    if slot == nil then return nil end
    setText(text, textValue)
    if tonumber(fontSize) ~= nil then
        local fittedSize = maximumWidth ~= nil
            and TextLayout.fitFontSize(textValue, fontSize, maximumWidth,
                math.max(24, tonumber(fontSize) * 2.4), minimumFontSize or 8)
            or tonumber(fontSize)
        pcall(function()
            local font = text.Font
            font.Size = math.floor(tonumber(fittedSize))
            local fontObject = state.getUIFont()
            if fontObject ~= nil then font.FontObject = fontObject end
            text:SetFont(font)
        end)
    end
    pcall(function() slot:SetAutoSize(true) end)
    pcall(function() slot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
    setPosition(slot, centerX, centerY)
    pcall(function() text:SetAutoWrapText(false) end)
    pcall(function() text:SetJustification(1) end)
    pcall(function() text:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
    pcall(function() text:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
    return text
end

state.setWheelTextShadow = function(text, enabled)
    if not alive(text) then return end
    if enabled == true then
        pcall(function() text:SetShadowOffset({ X = 2.0, Y = 2.0 }) end)
        pcall(function() text:SetShadowColorAndOpacity({
            R = 0.0, G = 0.0, B = 0.0, A = 0.88
        }) end)
    else
        pcall(function() text:SetShadowOffset({ X = 0.0, Y = 0.0 }) end)
        pcall(function() text:SetShadowColorAndOpacity({
            R = 0.0, G = 0.0, B = 0.0, A = 0.0
        }) end)
    end
end

local function createCachedIcon(tree, root, texture, centerX, centerY, size)
    if texture == nil then return nil end
    local image = construct("/Script/UMG.Image", tree)
    if not alive(image) then return nil end
    local slot = addToCanvas(root, image)
    if slot == nil then return nil end
    place(slot, centerX - size * 0.5, centerY - size * 0.5, size, size)
    local okBrush = pcall(function() image:SetBrushFromTexture(texture, false) end)
    if not okBrush then
        pcall(function() image:RemoveFromParent() end)
        return nil
    end
    setImageColor(image, { R = 1.0, G = 1.0, B = 1.0, A = 1.0 })
    pcall(function() image:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
    return image
end

local function createWheelBackground(tree, root, pc, centerX, centerY, radius)
    local backgroundOpacity = state.wheelMode == "main"
        and clamp(cfg("wheelBackgroundOpacity", 0.92), 0.25, 1.0)
        or (1.0 - clamp(cfg("sphereWheelBackgroundTransparencyPercent", 70),
            0, 100) / 100.0)
    local image = construct("/Script/UMG.Image", tree)
    local imageSlot = alive(image) and addToCanvas(root, image) or nil
    if imageSlot ~= nil then
        place(imageSlot, centerX - radius, centerY - radius, radius * 2, radius * 2)
        local library = cls("/Script/Engine.Default__KismetRenderingLibrary")
        local world = nil
        pcall(function() world = pc:GetWorld() end)
        local texture = nil
        local skin = validWheelSkin(state.wheelSkin)
        local assetPath = MOD_DIRECTORY .. "/Assets/" .. skin
        if alive(library) and world ~= nil then
            pcall(function()
                texture = library:ImportFileAsTexture2D(world, assetPath)
            end)
        end
        if alive(texture) then
            local okBrush = pcall(function() image:SetBrushFromTexture(texture, false) end)
            if okBrush then
                state.wheelBackgroundTexture = texture
                setImageColor(image, { R = 1.0, G = 1.0, B = 1.0,
                    A = backgroundOpacity })
                pcall(function() image:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
                return image
            end
        end
        pcall(function() image:RemoveFromParent() end)
    end

    local size = radius * 2 + 32
    local glyph = createCanvasText(tree, root, "●", centerX - size * 0.5,
        centerY - size * 0.59, size, size * 1.12, math.floor(radius * 2.02))
    if alive(glyph) then
        pcall(function() glyph:SetColorAndOpacity({ R = 0.01, G = 0.018,
            B = 0.03, A = backgroundOpacity }) end)
    end
    return glyph
end


do
    local okAux, AuxiliaryWheels = pcall(require, "auxiliary_wheels")
    if okAux and type(AuxiliaryWheels) == "table"
        and type(AuxiliaryWheels.new) == "function" then
        local okNew, runtime = pcall(AuxiliaryWheels.new, {
            cfg = cfg,
            clamp = clamp,
            alive = alive,
            construct = construct,
            addToCanvas = addToCanvas,
            place = place,
            setVisible = setVisible,
            setImageColor = setImageColor,
            createCenteredText = createCenteredCanvasText,
            createIcon = createCachedIcon,
            setTextShadow = state.setWheelTextShadow,
            setDefinitionTextColor = setDefinitionTextColor,
            setText = setText,
            setTextColor = setTextColor,
            mercyEquippedLabel = T("equipped"),
            mercyNoneLabel = T("none"),
            mercyEquippedText = COLORS.mercyEquippedText,
            mercyNoneText = COLORS.mercyNoneText,
            mercyEquipped = function() return state.mercyAccessoryEquipped == true end,
            auxDefinition = function(wheel, slot)
                local source = state.auxAssignments
                if state.editorOpen and type(state.editorDraft) == "table"
                    and type(state.editorDraft.auxAssignments) == "table" then
                    source = state.editorDraft.auxAssignments
                end
                local id = source[wheel] and source[wheel][slot] or "empty"
                return FUNCTION_BY_ID[id] or FUNCTION_BY_ID.empty
            end,
            emptyDefinition = function() return FUNCTION_BY_ID.empty end,
            iconTextureForDefinition = function(def)
                return state.iconRuntime ~= nil
                    and state.iconRuntime:textureForDefinition(def) or nil
            end,
            glyphTextureForKey = function(key)
                return state.glyphRuntime ~= nil
                    and state.glyphRuntime:textureForKey(key) or nil
            end,
            glyphLabelForKey = function(key)
                return state.glyphRuntime ~= nil
                    and type(state.glyphRuntime.labelForKey) == "function"
                    and state.glyphRuntime:labelForKey(key) or tostring(key or "")
            end,
            prepareGlyphs = function()
                if state.glyphRuntime ~= nil then state.glyphRuntime:prepare() end
            end,
            wheelBackgroundTexture = function() return state.wheelBackgroundTexture end,
            hitTestInvisible = VIS_HIT_TEST_INVISIBLE,
            pageSize = PAGE_SIZE,
        })
        if okNew and type(runtime) == "table" then
            state.auxiliaryRuntime = runtime
            log("Controller auxiliary-wheel layer loaded")
        else
            log("Controller auxiliary-wheel layer unavailable: " .. tostring(runtime), true)
        end
    else
        log("Controller auxiliary-wheel layer unavailable: " .. tostring(AuxiliaryWheels), true)
    end
end

do
    local okVisuals, visuals = pcall(require, "wheel_visuals")
    if okVisuals and type(visuals) == "table" and type(visuals.new) == "function" then
        local okNew, instance = pcall(visuals.new, {
            cfg = cfg,
            construct = construct,
            addToCanvas = addToCanvas,
            place = place,
            setVisible = setVisible,
            setBorderColor = setBorderColor,
            setRotation = setWidgetRotation,
            setText = setText,
            createText = createCanvasText,
            createCenteredText = createCenteredCanvasText,
            setTextShadow = state.setWheelTextShadow,
            hitTestInvisible = VIS_HIT_TEST_INVISIBLE,
        })
        if okNew and type(instance) == "table" then
            state.visuals = instance
            state.callVisual = function(method, ...)
                if state.visuals == nil then return false end
                local callback = state.visuals[method]
                if type(callback) ~= "function" then
                    log("Animated centre disabled: missing method " .. tostring(method), true)
                    state.visuals = nil
                    if alive(state.pageText) then setVisible(state.pageText, true) end
                    return false
                end
                local okCall, result = pcall(callback, state.visuals, ...)
                if not okCall then
                    log("Animated centre disabled after " .. tostring(method)
                        .. " error: " .. tostring(result), true)
                    state.visuals = nil
                    if alive(state.pageText) then setVisible(state.pageText, true) end
                    return false
                end
                return result ~= false
            end
            log("Animated centre pointer/detail layer loaded")
        else
            log("Animated centre layer unavailable; classic centre remains active: "
                .. tostring(instance), true)
        end
    else
        log("Animated centre layer unavailable; classic centre remains active: "
            .. tostring(visuals), true)
    end
end

local function destroyCenterNotification()
    if alive(state.notificationWidget) then
        pcall(function() state.notificationWidget:RemoveFromParent() end)
    end
    state.notificationWidget = nil
    state.notificationText = nil
    state.notificationExpiresAt = 0.0
    state.notificationCompact = false
end

state.showCenterNotification = function(message, compact)
    local pc = state.pc
    if not alive(pc) then pc = getPlayerController() end
    if not alive(pc) then
        log("Notification unavailable: " .. tostring(message), true)
        return false
    end

    if not alive(state.notificationWidget) or not alive(state.notificationText)
        or state.notificationCompact ~= (compact == true) then
        destroyCenterNotification()

        local wbl = getWidgetBlueprintLibrary()
        local userWidgetClass = cls("/Script/UMG.UserWidget")
        local world = nil
        pcall(function() world = pc:GetWorld() end)
        if not alive(wbl) or not alive(userWidgetClass) or world == nil then
            log("Notification UI classes or world unavailable: " .. tostring(message), true)
            return false
        end

        local widget = nil
        local okWidget = pcall(function()
            widget = wbl:Create(world, userWidgetClass, pc)
        end)
        if not okWidget or not alive(widget) then
            log("Notification UserWidget creation failed: " .. tostring(message), true)
            return false
        end

        local tree = nil
        pcall(function() tree = widget.WidgetTree end)
        local root = tree and construct("/Script/UMG.CanvasPanel", tree) or nil
        if tree == nil or not alive(root) then
            pcall(function() widget:RemoveFromParent() end)
            log("Notification Canvas construction failed: " .. tostring(message), true)
            return false
        end
        local okRoot = pcall(function() tree.RootWidget = root end)
        if not okRoot then
            pcall(function() widget:RemoveFromParent() end)
            log("Notification root assignment failed: " .. tostring(message), true)
            return false
        end

        local screenW = tonumber(cfg("screenWidth", 1920)) or 1920
        local screenH = tonumber(cfg("screenHeight", 1080)) or 1080
        local width = clamp(cfg("notificationWidth", 760), 360, screenW - 40)
        local height = clamp(cfg("notificationHeight", 58), 38, 100)
        local yRatio = clamp(cfg("notificationScreenYRatio", 0.333), 0.15, 0.60)
        local x = (screenW - width) * 0.5
        local y = screenH * yRatio - height * 0.5

        local fontSize = compact == true
            and math.max(12, (tonumber(cfg("notificationFontSize", 24)) or 24) - 4)
            or cfg("notificationFontSize", 24)
        local text = createCanvasText(tree, root, "", x + 14, y + 7,
            width - 28, height - 14, fontSize)
        if not alive(text) then
            pcall(function() widget:RemoveFromParent() end)
            log("Notification text construction failed: " .. tostring(message), true)
            return false
        end
        pcall(function() text:SetRenderOpacity(0.98) end)
        if compact == true then state.setWheelTextShadow(text, true) end

        local okViewport = pcall(function() widget:AddToViewport(100) end)
        if not okViewport then
            pcall(function() widget:RemoveFromParent() end)
            log("Notification AddToViewport failed: " .. tostring(message), true)
            return false
        end

        state.notificationWidget = widget
        state.notificationText = text
        state.notificationCompact = compact == true
    end

    setText(state.notificationText, tostring(message))
    setVisible(state.notificationWidget, true)
    state.notificationExpiresAt = os.clock()
        + clamp(cfg("notificationDurationSeconds", 3.0), 0.5, 10.0)
    return true
end

state.showCenterNotificationStyled = function(prefix, accent, suffix, accentColor, compact)
    local pc = state.pc
    if not alive(pc) then pc = getPlayerController() end
    local plainMessage = tostring(prefix or "") .. tostring(accent or "") .. tostring(suffix or "")
    if not alive(pc) then
        log("Notification unavailable: " .. plainMessage, true)
        return false
    end

    destroyCenterNotification()
    local wbl = getWidgetBlueprintLibrary()
    local userWidgetClass = cls("/Script/UMG.UserWidget")
    local world = nil
    pcall(function() world = pc:GetWorld() end)
    if not alive(wbl) or not alive(userWidgetClass) or world == nil then
        log("Notification UI classes or world unavailable: " .. plainMessage, true)
        return false
    end

    local widget = nil
    local okWidget = pcall(function() widget = wbl:Create(world, userWidgetClass, pc) end)
    if not okWidget or not alive(widget) then
        log("Notification UserWidget creation failed: " .. plainMessage, true)
        return false
    end

    local tree = nil
    pcall(function() tree = widget.WidgetTree end)
    local root = tree and construct("/Script/UMG.CanvasPanel", tree) or nil
    if tree == nil or not alive(root) then
        pcall(function() widget:RemoveFromParent() end)
        return false
    end
    local okRoot = pcall(function() tree.RootWidget = root end)
    if not okRoot then
        pcall(function() widget:RemoveFromParent() end)
        return false
    end

    local screenW = tonumber(cfg("screenWidth", 1920)) or 1920
    local screenH = tonumber(cfg("screenHeight", 1080)) or 1080
    local height = clamp(cfg("notificationHeight", 58), 38, 100)
    local yRatio = clamp(cfg("notificationScreenYRatio", 0.333), 0.15, 0.60)
    local y = screenH * yRatio - height * 0.5
    local box = construct("/Script/UMG.HorizontalBox", tree)
    local boxSlot = alive(box) and addToCanvas(root, box) or nil
    if boxSlot == nil then
        pcall(function() widget:RemoveFromParent() end)
        return false
    end
    pcall(function() boxSlot:SetAutoSize(true) end)
    pcall(function() boxSlot:SetAlignment({ X = 0.5, Y = 0.0 }) end)
    setPosition(boxSlot, screenW * 0.5, y + 7)
    pcall(function() box:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)

    local fontSize = compact == true
        and math.max(12, (tonumber(cfg("notificationFontSize", 24)) or 24) - 4)
        or cfg("notificationFontSize", 24)
    local function addPiece(textValue, color)
        if tostring(textValue or "") == "" then return true end
        local text = construct("/Script/UMG.TextBlock", tree)
        if not alive(text) then return false end
        local childSlot = nil
        local okAdd = pcall(function() childSlot = box:AddChildToHorizontalBox(text) end)
        if not okAdd or childSlot == nil then
            pcall(function() childSlot = box:AddChild(text) end)
        end
        if childSlot == nil then return false end
        setText(text, tostring(textValue))
        pcall(function()
            local font = text.Font
            font.Size = math.floor(tonumber(fontSize) or 24)
            local fontObject = state.getUIFont()
            if fontObject ~= nil then font.FontObject = fontObject end
            text:SetFont(font)
        end)
        setTextColor(text, color or COLORS.text)
        pcall(function() text:SetAutoWrapText(false) end)
        pcall(function() text:SetRenderOpacity(0.98) end)
        if compact == true then state.setWheelTextShadow(text, true) end
        pcall(function() text:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
        return true
    end

    if not addPiece(prefix, COLORS.text)
        or not addPiece(accent, accentColor or COLORS.text)
        or not addPiece(suffix, COLORS.text) then
        pcall(function() widget:RemoveFromParent() end)
        return false
    end

    local okViewport = pcall(function() widget:AddToViewport(100) end)
    if not okViewport then
        pcall(function() widget:RemoveFromParent() end)
        return false
    end
    state.notificationWidget = widget
    state.notificationText = nil
    state.notificationCompact = compact == true
    state.notificationExpiresAt = os.clock()
        + clamp(cfg("notificationDurationSeconds", 3.0), 0.5, 10.0)
    return true
end

local function processCenterNotification()
    if state.notificationExpiresAt > 0.0
        and os.clock() >= state.notificationExpiresAt then
        destroyCenterNotification()
    end
end

local function zoomPercentText()
    local multiplier = state.cameraZoom ~= nil and state.cameraZoom:getMultiplier() or 1.0
    return tostring(math.floor((tonumber(multiplier) or 1.0) * 100.0 + 0.5)) .. "%"
end

local function refreshZoomHelp(show)
    local visible = show == true and cfg("controllerZoomEnabled", true) == true
        and state.wheelMode == "main" and state.openInputSource == "controller"
    for _, widget in ipairs(state.zoomHelpWidgets or {}) do
        if alive(widget) then setVisible(widget, visible) end
    end
    if alive(state.zoomHelpPercent) then
        setText(state.zoomHelpPercent, zoomPercentText())
        setVisible(state.zoomHelpPercent, visible)
    end
end

local function buildWidget(pc)
    if not alive(pc) then
        log("Open key received, but PlayerController is not ready", true)
        return false
    end
    if alive(state.widget) and alive(state.wheelPanel) then return true end

    local newMaster = false
    if not alive(state.widget) then
        destroyWidget()
        if not createBaseWidget(pc) then return false end
        newMaster = true
    end

    local tree = state.tree
    local masterRoot = state.root
    local wheelPanel = construct("/Script/UMG.CanvasPanel", tree)
    local wheelPanelSlot = alive(wheelPanel)
        and addToCanvas(masterRoot, wheelPanel) or nil
    if wheelPanelSlot == nil then
        log("Wheel build stopped: persistent wheel panel unavailable", true)
        destroyWidget()
        return false
    end
    place(wheelPanelSlot, 0, 0,
        tonumber(cfg("screenWidth", 1920)) or 1920,
        tonumber(cfg("screenHeight", 1080)) or 1080)
    state.wheelPanel = wheelPanel
    local root = wheelPanel
    local centerX = tonumber(cfg("centerX", 960)) or 960
    local centerY = tonumber(cfg("centerY", 540)) or 540
    local innerRadius = clamp(cfg("wheelInnerRadius", 82), 45, 180)
    local outerRadius = clamp(cfg("wheelOuterRadius", 270), innerRadius + 80, 420)
    local dividerThickness = clamp(cfg("wheelDividerThickness", 2), 1, 5)
    local highlightThickness = clamp(cfg("wheelDividerHighlightThickness", 4),
        dividerThickness + 1, 10)
    local markerSize = clamp(cfg("wheelOuterMarkerSize", 30), 8, 64)
    local markerBorderPadding = clamp(cfg("wheelOuterMarkerBorderPadding", 4), 2, 12)
    local markerAspect = clamp(cfg("wheelOuterMarkerAspect", 1.0), 1.0, 1.0)
    local markerZOrder = 10
    local visibleCount = activeVisibleSlotCount()
    local sphereGeometry = state.wheelMode ~= "main"
        and sphereWheelGeometry(visibleCount) or nil
    local geometryCount = sphereGeometry ~= nil
        and sphereGeometry.virtualCount or visibleCount

    local radialSpan = outerRadius - innerRadius
    local sectorSpan = TWO_PI / geometryCount

    createWheelBackground(tree, root, pc, centerX, centerY, outerRadius)

    state.dividers = {}
    for index = 1, geometryCount do
        local slotOneAngle = sphereGeometry ~= nil
            and math.rad(90)
            or math.rad(tonumber(cfg("wheelSlotOneAngleDegrees", 180)) or 180)
        local boundaryAngle
        if sphereGeometry ~= nil then
            
            
            boundaryAngle = slotOneAngle - sectorSpan * 0.5
                + ((index - 1) * sectorSpan)
        else
            boundaryAngle = slotOneAngle + sectorSpan * 0.5
                - ((index - 1) * sectorSpan)
        end
        local length = radialSpan - 18
        local radius = innerRadius + 9 + length * 0.5
        local divider = { base = nil, glow = nil }
        local skipDivider = sphereGeometry ~= nil
            and sphereGeometry.skippedDividers[index] == true
        local base = not skipDivider and construct("/Script/UMG.Border", tree) or nil
        local baseSlot = alive(base) and addToCanvas(root, base) or nil
        if baseSlot ~= nil then
            place(baseSlot,
                centerX + math.cos(boundaryAngle) * radius - length * 0.5,
                centerY - math.sin(boundaryAngle) * radius - dividerThickness * 0.5,
                length, dividerThickness)
            setWidgetRotation(base, -math.deg(boundaryAngle))
            setBorderColor(base, COLORS.divider)
            pcall(function() base:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
            divider.base = base
        end
        local glow = not skipDivider and construct("/Script/UMG.Border", tree) or nil
        local glowSlot = alive(glow) and addToCanvas(root, glow) or nil
        if glowSlot ~= nil then
            local glowLength = math.min(54, radialSpan * 0.34)
            local glowRadius = outerRadius - 15 - glowLength * 0.5
            place(glowSlot,
                centerX + math.cos(boundaryAngle) * glowRadius - glowLength * 0.5,
                centerY - math.sin(boundaryAngle) * glowRadius - highlightThickness * 0.5,
                glowLength, highlightThickness)
            setWidgetRotation(glow, -math.deg(boundaryAngle))
            setBorderColor(glow, { R = COLORS.selected.R, G = COLORS.selected.G,
                B = COLORS.selected.B, A = 0.0 })
            pcall(function() glow:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
            divider.glow = glow
        end
        state.dividers[index] = divider
    end

    for index = 1, visibleCount do
        local virtualIndex = sphereGeometry ~= nil
            and sphereGeometry.positions[index] or index
        local centerAngle
        if sphereGeometry ~= nil then
            centerAngle = math.rad(90) + ((virtualIndex - 1) * sectorSpan)
        else
            centerAngle = math.rad(tonumber(cfg("wheelSlotOneAngleDegrees", 180)) or 180)
                - ((virtualIndex - 1) * sectorSpan)
        end
        local sector = {
            bands = {},
            globalSlot = assignmentSlotForVisibleIndex(index),
            pages = {},
            virtualIndex = virtualIndex,
            leftDividerIndex = virtualIndex,
            rightDividerIndex = (virtualIndex % geometryCount) + 1,
        }
        local baseColor = colorForDefinition(assignmentDefinitionForVisibleIndex(index))

        local markerBack = markerLayer ~= "hidden"
            and construct("/Script/UMG.Border", tree) or nil
        if alive(markerBack) then
            local backSlot = addToCanvas(root, markerBack)
            if backSlot ~= nil then
                pcall(function() backSlot:SetZOrder(markerZOrder) end)
                local radius = outerRadius - 13
                local backSize = markerSize + markerBorderPadding
                place(backSlot,
                    centerX + math.cos(centerAngle) * radius - backSize * 0.5,
                    centerY - math.sin(centerAngle) * radius - backSize * 0.5,
                    backSize, backSize)
                setWidgetRotation(markerBack, 45.0 - math.deg(centerAngle))
                setBorderColor(markerBack, COLORS.divider)
                pcall(function() markerBack:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
                sector.bands[1] = markerBack
            end
        end

        local marker = markerLayer ~= "hidden"
            and construct("/Script/UMG.Border", tree) or nil
        if alive(marker) then
            local markerSlot = addToCanvas(root, marker)
            if markerSlot ~= nil then
                pcall(function() markerSlot:SetZOrder(markerZOrder + 100) end)
                local radius = outerRadius - 13
                local markerHeight = markerSize * markerAspect
                place(markerSlot,
                    centerX + math.cos(centerAngle) * radius - markerSize * 0.5,
                    centerY - math.sin(centerAngle) * radius - markerHeight * 0.5,
                    markerSize, markerHeight)
                setWidgetRotation(marker, 45.0 - math.deg(centerAngle))
                setBorderColor(marker, baseColor)
                pcall(function() marker:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
                sector.bands[2] = marker
            end
        end

        local outerContentRadius = innerRadius + radialSpan * 0.58
        local innerContentRadius = innerRadius + radialSpan *
            clamp(cfg("wheelRuntimeLabelRadiusFactor", 0.29), 0.24, 0.48)
        local labelWidth, labelHeight = 74, 28
        for page = 1, PAGE_COUNT do
            local globalSlot = (page - 1) * PAGE_SIZE + index
            local def = state.wheelMode ~= "main"
                and (page == 1 and assignmentDefinitionForVisibleIndex(index)
                    or FUNCTION_BY_ID.empty)
                or assignmentDefinitionByGlobalSlot(globalSlot)
            local layer = {}
            local texture = state.iconRuntime ~= nil
                and state.iconRuntime:textureForDefinition(def) or nil

            
            
            
            local labelRadius = texture ~= nil and innerContentRadius
                or outerContentRadius
            local labelX = centerX + math.cos(centerAngle) * labelRadius
                - labelWidth * 0.5
            local labelY = centerY - math.sin(centerAngle) * labelRadius
                - labelHeight * 0.5

            if texture ~= nil then
                local iconSize = clamp(cfg("wheelRuntimeIconSize", 55), 28, 72)
                layer.icon = createCachedIcon(tree, root, texture,
                    centerX + math.cos(centerAngle) * outerContentRadius,
                    centerY - math.sin(centerAngle) * outerContentRadius, iconSize)
                setVisible(layer.icon, false)
            end
            layer.label = createCenteredCanvasText(tree, root,
                def.short or def.label,
                centerX + math.cos(centerAngle) * labelRadius,
                centerY - math.sin(centerAngle) * labelRadius, 12, 96, 8)
            state.setWheelTextShadow(layer.label, true)
            setVisible(layer.label, false)

            layer.detailLabel = createCenteredCanvasText(tree, root, "",
                centerX + math.cos(centerAngle) * labelRadius,
                centerY - math.sin(centerAngle) * labelRadius + 18, 7, 96, 6)
            state.setWheelTextShadow(layer.detailLabel, true)
            setVisible(layer.detailLabel, false)

            sector.pages[page] = layer
        end

        state.sectors[index] = sector
    end

    state.pageText = createCenteredCanvasText(tree, root,
        wheelRoman(state.activePage), centerX, centerY, 30)
    state.setWheelTextShadow(state.pageText, state.wheelMode == "main")
    if state.wheelMode ~= "main" then
        setVisible(state.pageText, false)
    elseif state.callVisual ~= nil and state.callVisual("build", tree, root,
        centerX, centerY, clamp(cfg("centerSize", 136), 50, 160)) then
        setVisible(state.pageText, false)
    end

    local displayName = cfg("displayName", nil)
    local settingsKeyLabel = string.upper(tostring(cfg("settingsKey") or ""))
    local keyboardPageLabel = string.upper(tostring(
        cfg("keyboardNextWheelButton") or ""))
    local controllerPageLabel = tostring(
        cfg("controllerNextWheelButton") or "")
    if type(displayName) == "function" then
        settingsKeyLabel = displayName(cfg("settingsKey"))
        keyboardPageLabel = displayName(
            cfg("keyboardNextWheelButton"))
        controllerPageLabel = displayName(
            cfg("controllerNextWheelButton"))
    end
    local hintY = centerY + outerRadius + 24
    local function styleHintText(widget)
        if not alive(widget) then return end
        pcall(function() widget:SetRenderOpacity(0.68) end)
        if state.wheelMode == "main" then
            pcall(function() widget:SetShadowOffset({ X = 2.0, Y = 2.0 }) end)
            pcall(function() widget:SetShadowColorAndOpacity({
                R = 0.0, G = 0.0, B = 0.0, A = 0.90
            }) end)
        end
    end

    if state.wheelMode == "main" then
        
        
        local function hintGlyph(key, device, x, fallback, rowY)
            rowY = tonumber(rowY) or hintY
            local iconY = rowY + 11
            local texture = nil
            if device == "controller" and state.glyphRuntime ~= nil
                and type(state.glyphRuntime.textureForKey) == "function" then
                local family = type(state.detectControllerGlyphFamily) == "function"
                    and state.detectControllerGlyphFamily(state.pc)
                    or cfg("controllerGlyphFallbackFamily", "xbox")
                texture = state.glyphRuntime:textureForKey(key, family)
                if texture == nil and type(state.glyphRuntime.labelForKey) == "function" then
                    fallback = state.glyphRuntime:labelForKey(key, family)
                end
            elseif device == "keyboard" and state.keyboardGlyphRuntime ~= nil
                and type(state.keyboardGlyphRuntime.textureForKey) == "function" then
                texture = state.keyboardGlyphRuntime:textureForKey(key)
            end
            local icon = texture ~= nil and createCachedIcon(tree, root, texture, x, iconY, 30) or nil
            if alive(icon) then
                pcall(function() icon:SetRenderOpacity(0.82) end)
                return icon
            end
            local text = createCenteredCanvasText(tree, root,
                tostring(fallback or key or ""), x, rowY + 12, 11)
            styleHintText(text)
            return text
        end

        local nextControllerKey = tostring(cfg("controllerNextWheelButton") or "")
        local nextKeyboardKey = tostring(cfg("keyboardNextWheelButton") or "")
        local menuControllerKey = tostring(cfg("controllerPalWheelMenuButton") or "Gamepad_RightThumbstick")
        local menuKeyboardKey = tostring(cfg("settingsKey") or "F7")

        
        
        
        local nextLabelW, nextGlyphGapW, glyphBoxW, slashW, menuLabelW = 96, 8, 34, 20, 160
        local helpGroupW = nextLabelW + nextGlyphGapW + glyphBoxW + slashW + glyphBoxW
            + menuLabelW + glyphBoxW + slashW + glyphBoxW
        local cursor = centerX - helpGroupW * 0.5

        local nextLabel = createCanvasText(tree, root, T("nextWheelColon"),
            cursor, hintY, nextLabelW, 24, 13, 0, 8)
        styleHintText(nextLabel)
        cursor = cursor + nextLabelW + nextGlyphGapW
        hintGlyph(nextControllerKey, "controller", cursor + glyphBoxW * 0.5, controllerPageLabel)
        cursor = cursor + glyphBoxW
        local nextSlash = createCanvasText(tree, root, "/", cursor, hintY, slashW, 24, 13, 1)
        styleHintText(nextSlash)
        cursor = cursor + slashW
        hintGlyph(nextKeyboardKey, "keyboard", cursor + glyphBoxW * 0.5, keyboardPageLabel)
        cursor = cursor + glyphBoxW

        local menuLabel = createCanvasText(tree, root, T("palwheelMenuColon"),
            cursor, hintY, menuLabelW, 24, 13, 0, 8)
        styleHintText(menuLabel)
        cursor = cursor + menuLabelW
        hintGlyph(menuControllerKey, "controller", cursor + glyphBoxW * 0.5, menuControllerKey)
        cursor = cursor + glyphBoxW
        local menuSlash = createCanvasText(tree, root, "/", cursor, hintY, slashW, 24, 13, 1)
        styleHintText(menuSlash)
        cursor = cursor + slashW
        hintGlyph(menuKeyboardKey, "keyboard", cursor + glyphBoxW * 0.5, settingsKeyLabel)

        
        
        
        local zoomY = hintY + 30
        local zoomLabelW, zoomGlyphW, zoomSlashW, zoomGapW, zoomPercentW = 112, 34, 20, 18, 50
        local zoomGroupW = zoomLabelW + zoomGlyphW + zoomSlashW
            + zoomGlyphW + zoomGapW + zoomPercentW
        local zoomCursor = centerX - zoomGroupW * 0.5
        state.zoomHelpWidgets = {}
        local function rememberZoomWidget(widget)
            if alive(widget) then
                state.zoomHelpWidgets[#state.zoomHelpWidgets + 1] = widget
                setVisible(widget, false)
            end
            return widget
        end

        local zoomLabel = rememberZoomWidget(createCanvasText(tree, root, T("zoomInOut"),
            zoomCursor, zoomY, zoomLabelW, 24, 13, 0, 8))
        styleHintText(zoomLabel)
        zoomCursor = zoomCursor + zoomLabelW
        local zoomLeftGlyph = rememberZoomWidget(hintGlyph("Gamepad_LeftTrigger", "controller",
            zoomCursor + zoomGlyphW * 0.5, nil, zoomY))
        zoomCursor = zoomCursor + zoomGlyphW
        local zoomSlash = rememberZoomWidget(createCanvasText(tree, root, "/",
            zoomCursor, zoomY, zoomSlashW, 24, 13, 1))
        styleHintText(zoomSlash)
        zoomCursor = zoomCursor + zoomSlashW
        local zoomRightGlyph = rememberZoomWidget(hintGlyph("Gamepad_RightTrigger", "controller",
            zoomCursor + zoomGlyphW * 0.5, nil, zoomY))
        zoomCursor = zoomCursor + zoomGlyphW + zoomGapW
        state.zoomHelpPercent = rememberZoomWidget(createCanvasText(tree, root, "100%",
            zoomCursor, zoomY, zoomPercentW, 24, 13, 1))
        styleHintText(state.zoomHelpPercent)
    end

    if state.auxiliaryRuntime ~= nil and state.wheelMode == "main"
        and (type(state.auxiliaryRuntime.isBuilt) ~= "function"
            or not state.auxiliaryRuntime:isBuilt()) then
        state.auxiliaryRuntime:build(tree, masterRoot, centerX, centerY, outerRadius)
    end

    if newMaster then
        local okViewport = pcall(function() state.widget:AddToViewport(0) end)
        if not okViewport then
            log("UI build stopped: AddToViewport failed", true)
            destroyWidget()
            return false
        end
    end

    setVisible(state.wheelPanel, false)
    if newMaster then setVisible(state.widget, false) end
    state.builtWheelMode = state.wheelMode
    log("Persistent " .. tostring(state.wheelMode) .. " "
        .. validWheelSkin(state.wheelSkin) .. " " .. tostring(visibleCount)
        .. "-slot wheel built", true)
    return true
end

local function angularDistance(a, b)
    return math.abs((a - b + math.pi) % TWO_PI - math.pi)
end

state.wheelModeCacheKey = function(mode, page)
    if mode == "main" then
        local geometryPage = math.floor(clamp(page or state.activePage or 1, 1, PAGE_COUNT))
        return "main:" .. tostring(visibleSlotCountForPage(geometryPage))
    end
    return "sphere"
end

state.visualCacheFields = {
    "ring", "pointer", "pointerTip", "centerDiamond", "title", "subtitle",
    "centerX", "centerY", "directionActive", "directionDegrees",
}

state.captureVisualWidgets = function()
    if type(state.visuals) ~= "table" then return nil end
    local snapshot = {}
    for _, field in ipairs(state.visualCacheFields) do
        snapshot[field] = state.visuals[field]
    end
    return snapshot
end

state.restoreVisualWidgets = function(snapshot)
    if type(state.visuals) ~= "table" or type(snapshot) ~= "table" then return end
    for _, field in ipairs(state.visualCacheFields) do
        state.visuals[field] = snapshot[field]
    end
end


state.stashWheelPanel = function()
    if not alive(state.wheelPanel) then return false end
    local key = state.wheelModeCacheKey(state.wheelMode)
    local old = state.wheelPanelCache[key]
    if type(old) == "table" and alive(old.panel) and old.panel ~= state.wheelPanel then
        pcall(function() old.panel:RemoveFromParent() end)
    end
    setVisible(state.wheelPanel, false)
    state.wheelPanelCache[key] = {
        panel = state.wheelPanel,
        sectors = state.sectors,
        dividers = state.dividers,
        pageText = state.pageText,
        wheelBackgroundTexture = state.wheelBackgroundTexture,
        zoomHelpWidgets = state.zoomHelpWidgets,
        zoomHelpPercent = state.zoomHelpPercent,
        visualWidgets = state.wheelMode == "main" and state.captureVisualWidgets() or nil,
    }
    state.wheelPanel = nil
    state.builtWheelMode = nil
    state.sectors = {}
    state.dividers = {}
    state.pageText = nil
    state.wheelBackgroundTexture = nil
    state.zoomHelpWidgets = {}
    state.zoomHelpPercent = nil
    return true
end

state.restoreWheelPanel = function(mode, page)
    local key = state.wheelModeCacheKey(mode, page)
    local cached = state.wheelPanelCache[key]
    if type(cached) ~= "table" or not alive(cached.panel) then
        state.wheelPanelCache[key] = nil
        if mode == "main" then
            state.mainGeometryPrewarmComplete = false
            state.mainGeometryPrewarmLogged = false
        end
        return false
    end
    state.wheelPanelCache[key] = nil
    state.wheelPanel = cached.panel
    state.builtWheelMode = mode
    state.sectors = cached.sectors or {}
    state.dividers = cached.dividers or {}
    state.pageText = cached.pageText
    state.wheelBackgroundTexture = cached.wheelBackgroundTexture
    state.zoomHelpWidgets = cached.zoomHelpWidgets or {}
    state.zoomHelpPercent = cached.zoomHelpPercent
    if mode == "main" then state.restoreVisualWidgets(cached.visualWidgets) end
    setVisible(state.wheelPanel, false)
    return true
end


state.invalidateWheelMode = function(mode, preserveAux)
    local invalidatingMain = mode == "main"
    local activeMatches = alive(state.wheelPanel)
        and ((invalidatingMain and state.wheelMode == "main")
            or (not invalidatingMain and state.wheelMode ~= "main"))
    if activeMatches then
        pcall(function() state.wheelPanel:RemoveFromParent() end)
        state.wheelPanel = nil
        state.builtWheelMode = nil
        state.sectors = {}
        state.dividers = {}
        state.pageText = nil
        state.wheelBackgroundTexture = nil
        state.zoomHelpWidgets = {}
        state.zoomHelpPercent = nil
    end
    for key, cached in pairs(state.wheelPanelCache or {}) do
        local keyIsMain = tostring(key):sub(1, 5) == "main:"
        if (invalidatingMain and keyIsMain) or (not invalidatingMain and key == "sphere") then
            if type(cached) == "table" and alive(cached.panel) then
                pcall(function() cached.panel:RemoveFromParent() end)
            end
            state.wheelPanelCache[key] = nil
        end
    end
    if invalidatingMain then
        state.mainGeometryPrewarmComplete = false
        state.mainGeometryPrewarmLogged = false
        if state.callVisual ~= nil then state.callVisual("reset") end
        if state.auxiliaryRuntime ~= nil and preserveAux ~= true then
            if type(state.auxiliaryRuntime.destroy) == "function" then
                state.auxiliaryRuntime:destroy()
            else
                state.auxiliaryRuntime:reset()
            end
        end
    end
end

local function invalidateWheelPanel(preserveAux)
    if alive(state.wheelPanel) then
        pcall(function() state.wheelPanel:RemoveFromParent() end)
    end
    for _, cached in pairs(state.wheelPanelCache or {}) do
        if type(cached) == "table" and alive(cached.panel) then
            pcall(function() cached.panel:RemoveFromParent() end)
        end
    end
    state.wheelPanel = nil
    state.wheelPanelCache = {}
    state.mainGeometryPrewarmComplete = false
    state.mainGeometryPrewarmLogged = false
    state.builtWheelMode = nil
    state.sectors = {}
    state.dividers = {}
    state.zoomHelpWidgets = {}
    state.zoomHelpPercent = nil
    if state.auxiliaryRuntime ~= nil and preserveAux ~= true then
        if type(state.auxiliaryRuntime.destroy) == "function" then
            state.auxiliaryRuntime:destroy()
        else
            state.auxiliaryRuntime:reset()
        end
    end
    state.wheelBackgroundTexture = nil
    state.pageText = nil
    if state.callVisual ~= nil then state.callVisual("reset") end
end

refreshPartyCapacity = function(force)
    local now = os.clock()
    if force ~= true and now < (state.partyCapacityNextPoll or 0.0) then
        return false
    end
    state.partyCapacityNextPoll = now + 1.0

    local holder = state.palActions and state.palActions:getHolder() or nil
    local detected = state.palActions and state.palActions:getPartyCapacity(holder) or nil
    if detected == nil then return false end
    detected = math.floor(clamp(detected, 1, MAX_DYNAMIC_PARTY_CAPACITY))

    local changed = detected ~= state.partyCapacity
    local catalogGrew = detected > (state.partyCatalogCapacity or DEFAULT_PARTY_CAPACITY)
    if state.partyCapacityDetected ~= true or changed then
        state.partyCapacityStableSince = os.time()
    end
    state.partyCapacityDetected = true
    if catalogGrew then
        state.partyCatalogCapacity = detected
        rebuildFunctionCatalog(shortcutData, state.partyCatalogCapacity)
        invalidateWheelPanel()
    end
    if changed then
        state.partyCapacity = detected
        state.editorPartyPage = 1
        log("Party capacity detected: " .. tostring(detected)
            .. (detected > DEFAULT_PARTY_CAPACITY and " (expanded party support active)" or ""), true)
    end
    return changed or catalogGrew
end

switchWheelPanelForPage = function(targetPage)
    if state.wheelMode ~= "main" then return false end
    local previousPage = math.floor(clamp(state.activePage or 1, 1, PAGE_COUNT))
    targetPage = math.floor(clamp(targetPage or previousPage, 1, state.activeWheelCount))
    local previousKey = state.wheelModeCacheKey("main", previousPage)
    local targetKey = state.wheelModeCacheKey("main", targetPage)

    if targetKey ~= previousKey then
        if not state.stashWheelPanel() then return false end
        state.activePage = targetPage
        if not state.restoreWheelPanel("main", targetPage)
            and not buildWidget(state.pc) then
            state.activePage = previousPage
            state.restoreWheelPanel("main", previousPage)
            if alive(state.wheelPanel) then setVisible(state.wheelPanel, true) end
            return false
        end
    else
        state.activePage = targetPage
    end

    setVisible(state.wheelPanel, true)
    setVisible(state.widget, true)
    refreshZoomHelp(true)
    if state.auxiliaryRuntime ~= nil then
        state.auxiliaryRuntime:setVisible(state.wheelMode == "main")
        if type(state.auxiliaryRuntime.setGlyphsVisible) == "function" then
            state.auxiliaryRuntime:setGlyphsVisible(state.mousePresentationRemembered ~= true)
        end
    end
    if state.callVisual ~= nil then
        state.callVisual("beginPageFade", state.wheelPanel, state.sectors, state.activePage)
    end
    updateHighlight()
    return true
end


state.prewarmNextMainGeometry = function(pc)
    if state.mainGeometryPrewarmComplete == true or state.open or state.editorOpen
        or state.wheelMode ~= "main" or not alive(state.wheelPanel)
        or not alive(pc) then
        return false
    end

    local originalPage = math.floor(clamp(state.activePage or 1, 1, PAGE_COUNT))
    local originalKey = state.wheelModeCacheKey("main", originalPage)
    local targetPage = nil
    for page = 1, math.floor(clamp(state.activeWheelCount or PAGE_COUNT, 1, PAGE_COUNT)) do
        local key = state.wheelModeCacheKey("main", page)
        local cached = state.wheelPanelCache[key]
        if type(cached) == "table" and not alive(cached.panel) then
            state.wheelPanelCache[key] = nil
            cached = nil
        end
        if key ~= originalKey and cached == nil then
            targetPage = page
            break
        end
    end

    if targetPage == nil then
        state.mainGeometryPrewarmComplete = true
        if state.mainGeometryPrewarmLogged ~= true then
            state.mainGeometryPrewarmLogged = true
            log("All Main Wheel page geometries are warm")
        end
        return false
    end

    if not state.stashWheelPanel() then return false end
    state.activePage = targetPage
    local built = buildWidget(pc)
    if built then state.stashWheelPanel() end
    state.activePage = originalPage
    local restored = state.restoreWheelPanel("main", originalPage)
    if restored and alive(state.wheelPanel) then setVisible(state.wheelPanel, false) end
    if alive(state.widget) then setVisible(state.widget, false) end

    if not built or not restored then return false end
    log("Prewarmed Main Wheel " .. tostring(visibleSlotCountForPage(targetPage))
        .. "-slot page geometry", true)
    return true
end

local function updateEditorCountText(page)
    if page ~= nil then
        local widget = state.editorCountTexts and state.editorCountTexts[page] or nil
        if alive(widget) then
            local value = state.editorDraft and state.editorDraft.visibleSlotCounts
                and state.editorDraft.visibleSlotCounts[page] or visibleSlotCountForPage(page)
            setText(widget, T("slotsDropdown", {
                count = math.floor(clamp(value or 12, 4, 12)) }))
        end
        return
    end
    for wheel = 1, PAGE_COUNT do updateEditorCountText(wheel) end
end

local function updateEditorWheelCountText()
    if alive(state.editorWheelCountText) then
        local value = state.editorDraft and state.editorDraft.activeWheelCount or state.activeWheelCount
        setText(state.editorWheelCountText,
            tostring(math.floor(clamp(value or PAGE_COUNT, 1, PAGE_COUNT))) .. "  ▼")
    end
end

local function updateEditorSkinText()
    if alive(state.editorSkinText) then
        local value = state.editorDraft and state.editorDraft.wheelSkin or state.wheelSkin
        setText(state.editorSkinText, validWheelSkin(value) .. "  ▼")
    end
end

local function updateEditorSlowMotionText()
    if alive(state.editorSlowMotionText) then
        local value = cfg("slowMotionEnabled", true) == true
        if state.editorDraft ~= nil then value = state.editorDraft.slowMotionEnabled == true end
        setText(state.editorSlowMotionText, T(value == true and "on" or "off"))
    end
end

local function updateEditorHapticsText()
    if alive(state.editorHapticsText) then
        local value = math.floor(clamp(cfg("controllerHighlightHapticsLevel", 3), 0, 3)) > 0
        if state.editorDraft ~= nil then value = state.editorDraft.hapticsEnabled == true end
        setText(state.editorHapticsText, T(value == true and "on" or "off"))
    end
end

state.updateEditorZoomText = function()
    if alive(state.editorZoomText) then
        local value = cfg("controllerZoomEnabled", true) == true
        if state.editorDraft ~= nil then value = state.editorDraft.controllerZoomEnabled == true end
        setText(state.editorZoomText, T(value == true and "on" or "off"))
        if alive(state.editorZoomBorder) then
            setBorderColor(state.editorZoomBorder, value == true and COLORS.button or COLORS.row)
        end
    end
end

state.updateEditorFollowTargetText = function()
    if alive(state.editorFollowTargetText) then
        local value = state.sphereFollowTargetEnabled == true
        if state.editorDraft ~= nil then value = state.editorDraft.sphereFollowTargetEnabled == true end
        setText(state.editorFollowTargetText, T(value == true and "on" or "off"))
        if alive(state.editorFollowTargetBorder) then
            setBorderColor(state.editorFollowTargetBorder, value == true and COLORS.button or COLORS.row)
        end
    end
end

local function updateEditorRow(slotIndex)
    local row = state.editorRows[slotIndex]
    if row == nil then return end
    local def = assignmentDefinitionByGlobalSlot(slotIndex)
    if state.editorDraft ~= nil and type(state.editorDraft.assignments) == "table" then
        local draftId = state.editorDraft.assignments[slotIndex] or "empty"
        def = FUNCTION_BY_ID[draftId] or FUNCTION_BY_ID.empty
    end
    if alive(row.assignmentText) then
        local rowLabel = def.label
        if def.kind == "shortcut" and tostring(def.shortcutDisplay or "") ~= "" then
            local status = def.active == false and T("shortcutInactiveStatus") or ""
            rowLabel = tostring(def.label) .. status
                .. "  [" .. tostring(def.shortcutDisplay) .. "]"
        end
        setText(row.assignmentText, rowLabel)
        setDefinitionTextColor(row.assignmentText, def)
    end
    if alive(row.assignmentBorder) then
        setBorderColor(row.assignmentBorder, colorForDefinition(def))
    end
end

local function buildEditorWidget(pc)
    if not alive(pc) then return false end
    if alive(state.editorPanel) then return true end
    if not alive(state.widget) and not buildWidget(pc) then return false end

    if state.editorBuilder == nil then
        
        
        if state.editorKeyboard == nil then
            local okKeyboard, keyboardModule = pcall(require, "editor_keyboard")
            if okKeyboard and type(keyboardModule) == "table"
                and type(keyboardModule.new) == "function" then
                state.editorKeyboard = keyboardModule.new({
                    state = state,
                    cfg = cfg,
                    cls = cls,
                    log = log,
                })
                state.editorKeyboard:register()
            else
                log("Editor keyboard UMG bridge unavailable: "
                    .. tostring(keyboardModule), true)
            end
        end
        local okBindings, bindingModule = pcall(require, "binding_editor")
        if okBindings and type(bindingModule) == "table"
            and type(bindingModule.new) == "function" then
            local function applyRuntimeBindings()
                if type(state.applyRuntimeBindings) ~= "function" then
                    return false, "PalWheel input runtime is not ready"
                end
                return state.applyRuntimeBindings(state.pc)
            end

            state.bindingEditor = bindingModule.new({
                state = state,
                cfg = cfg,
                alive = alive,
                construct = construct,
                addToCanvas = addToCanvas,
                place = place,
                setVisible = setVisible,
                setBorderColor = setBorderColor,
                setText = setText,
                createText = createCanvasText,
                createIcon = createCachedIcon,
                glyphTextureForKey = function(key, family)
                    if family == "keyboard" then
                        return state.keyboardGlyphRuntime ~= nil
                            and state.keyboardGlyphRuntime:textureForKey(key) or nil
                    end
                    return state.glyphRuntime ~= nil
                        and state.glyphRuntime:textureForKey(key, family) or nil
                end,
                colors = COLORS,
                hitTestInvisible = VIS_HIT_TEST_INVISIBLE,
                openInstructions = function(context)
                    return type(state.openEditorInstructions) == "function"
                        and state.openEditorInstructions(context) or false
                end,
                makeFKey = makeFKey,
                isKeyDown = isKeyDown,
                captureStateChanged = function(active, device)
                    return setEditorCaptureInputMode(active, device)
                end,
                controllerZoomEnabled = function()
                    if state.editorDraft ~= nil then
                        return state.editorDraft.controllerZoomEnabled == true
                    end
                    return cfg("controllerZoomEnabled", true) == true
                end,
                shortcutKeyConflict = function(value)
                    if type(ShortcutActions) == "table"
                        and type(ShortcutActions.primaryConflict) == "function" then
                        return ShortcutActions.primaryConflict(shortcutData, value)
                    end
                    return nil
                end,
                applyDraft = function(draft)
                    if type(draft) ~= "table" then return false, "control draft is missing" end
                    local fields = {
                        "openKey", "keyboardNextWheelButton", "settingsKey",
                        "controllerOpenButton", "controllerNextWheelButton", "controllerPalWheelMenuButton", "openWheelBehavior",
                    }
                    for _, field in ipairs({ "openKey", "keyboardNextWheelButton", "settingsKey" }) do
                        local def = type(ShortcutActions) == "table"
                            and type(ShortcutActions.primaryConflict) == "function"
                            and ShortcutActions.primaryConflict(shortcutData, draft[field]) or nil
                        if def ~= nil then
                            return false, tostring(draft[field]) .. " is used by active shortcut "
                                .. tostring(def.id or def.label or "unknown")
                        end
                    end
                    local previous = {}
                    for _, field in ipairs(fields) do
                        previous[field] = config[field]
                        config[field] = draft[field]
                    end
                    config.openWheelBehavior = tostring(config.openWheelBehavior or "hold") == "toggle"
                        and "toggle" or "hold"
                    local applied, applyError = applyRuntimeBindings()
                    if not applied or not saveSettings() then
                        for _, field in ipairs(fields) do config[field] = previous[field] end
                        applyRuntimeBindings()
                        return false, applyError or "settings.lua could not be saved"
                    end
                    state.keyboardToggleOpenArmed = false
                    state.keyboardToggleCloseArmed = false
                    log("PalWheel control draft saved and applied")
                    return true
                end,
                onBindingChanged = function(field)
                    if field == "settingsKey" and state.editorBuilder ~= nil
                        and type(state.editorBuilder.updateMenuHint) == "function" then
                        state.editorBuilder:updateMenuHint()
                    end
                end,
                log = log,
            })
        else
            state.bindingEditor = nil
            log("Controls editor unavailable: binding_editor.lua could not be loaded: "
                .. tostring(bindingModule), true)
        end

        local okShortcutEditor, shortcutEditorModule = pcall(require, "shortcut_editor")
        if okShortcutEditor and type(shortcutEditorModule) == "table"
            and type(shortcutEditorModule.new) == "function" then
            state.shortcutEditor = shortcutEditorModule.new({
                state = state,
                cfg = cfg,
                alive = alive,
                construct = construct,
                addToCanvas = addToCanvas,
                place = place,
                setVisible = setVisible,
                setBorderColor = setBorderColor,
                setText = setText,
                createText = createCanvasText,
                createIcon = createCachedIcon,
                glyphTextureForKey = function(key)
                    return state.keyboardGlyphRuntime ~= nil
                        and state.keyboardGlyphRuntime:textureForKey(key) or nil
                end,
                colors = COLORS,
                hitTestInvisible = VIS_HIT_TEST_INVISIBLE,
                openInstructions = function(context)
                    return type(state.openEditorInstructions) == "function"
                        and state.openEditorInstructions(context) or false
                end,
                fileInvalid = function()
                    return shortcutData ~= nil and shortcutData.fileInvalid == true
                end,
                currentCounts = function()
                    return #((shortcutData and shortcutData.active) or {}),
                        #((shortcutData and shortcutData.definitions) or {})
                end,
                readDraft = function()
                    return ShortcutActions.readDraft(SHORTCUTS_PATH)
                end,
                validateRows = function(rows)
                    return ShortcutActions.validateRows(rows, {
                        reservedIds = SHORTCUT_RESERVED_IDS,
                        controlKeys = { cfg("openKey"), cfg("keyboardNextWheelButton"),
                            cfg("settingsKey") },
                        headerValid = true,
                    })
                end,
                defaultRows = function()
                    return ShortcutActions.defaultRows()
                end,
                assignedSlots = function(id)
                    local result = {}
                    for slotIndex = 1, TOTAL_ASSIGNMENT_SLOTS do
                        if state.assignments[slotIndex] == id then
                            local wheel = math.floor((slotIndex - 1) / PAGE_SIZE) + 1
                            local localSlot = ((slotIndex - 1) % PAGE_SIZE) + 1
                            result[#result + 1] = wheelRoman(wheel) .. "-"
                                .. string.format("%02d", localSlot)
                        end
                    end
                    for auxWheel = 1, 2 do
                        for auxSlot = 1, 4 do
                            if (state.auxAssignments[auxWheel] or {})[auxSlot] == id then
                                result[#result + 1] = "AUX " .. (auxWheel == 1 and "I" or "II")
                                    .. "-" .. string.format("%02d", auxSlot)
                            end
                        end
                    end
                    return result
                end,
                applyDraft = function(rows, expectedText)
                    if type(state.applyShortcutDraft) ~= "function" then
                        return false, nil, "shortcut runtime is not ready"
                    end
                    return state.applyShortcutDraft(rows, expectedText)
                end,
                log = log,
            })
        else
            state.shortcutEditor = nil
            log("Shortcut editor unavailable: shortcut_editor.lua could not be loaded: "
                .. tostring(shortcutEditorModule), true)
        end

        local okSphereEditor, sphereEditorModule = pcall(require, "sphere_editor")
        if okSphereEditor and type(sphereEditorModule) == "table"
            and type(sphereEditorModule.new) == "function" then
            state.sphereEditor = sphereEditorModule.new({
                state = state,
                cfg = cfg,
                alive = alive,
                construct = construct,
                addToCanvas = addToCanvas,
                place = place,
                setVisible = setVisible,
                setBorderColor = setBorderColor,
                setText = setText,
                createText = createCanvasText,
                colors = COLORS,
                hitTestInvisible = VIS_HIT_TEST_INVISIBLE,
                definitions = config.sphereWheelRuntime.definitions,
                byId = config.sphereWheelRuntime.byId,
                getOrder = function()
                    return state.editorDraft and state.editorDraft.sphereAssignments
                        or state.sphereAssignments
                end,
                getVisibleCount = function()
                    return state.editorDraft and state.editorDraft.sphereVisibleSlotCount
                        or state.sphereVisibleSlotCount
                end,
                setVisibleCount = function(value)
                    if state.editorDraft ~= nil then
                        state.editorDraft.sphereVisibleSlotCount = math.floor(clamp(value, 5, 10))
                    end
                end,
                onChanged = function()
                    if type(state.updateMainEditorSaveVisual) == "function" then
                        state.updateMainEditorSaveVisual()
                    end
                end,
            })
        else
            state.sphereEditor = nil
            log("Sphere Wheel editor unavailable: sphere_editor.lua could not be loaded: "
                .. tostring(sphereEditorModule), true)
        end

        local okAuxEditor, auxEditorModule = pcall(require, "aux_editor")
        if okAuxEditor and type(auxEditorModule) == "table"
            and type(auxEditorModule.new) == "function" then
            state.auxEditor = auxEditorModule.new({
                state = state, alive = alive, construct = construct, addToCanvas = addToCanvas,
                place = place, setVisible = setVisible, setBorderColor = setBorderColor,
                setText = setText, createText = createCanvasText, colors = COLORS,
                hitTestInvisible = VIS_HIT_TEST_INVISIBLE,
                definitionById = function(id) return FUNCTION_BY_ID[id] or FUNCTION_BY_ID.empty end,
                colorForDefinition = colorForDefinition,
                setDefinitionTextColor = setDefinitionTextColor,
                getAssignments = function()
                    return state.editorDraft and state.editorDraft.auxAssignments or state.auxAssignments
                end,
                glyphTextureForKey = function(key)
                    if state.glyphRuntime ~= nil then return state.glyphRuntime:textureForKey(key) end
                    return nil
                end,
                glyphLabelForKey = function(key)
                    return state.glyphRuntime ~= nil
                        and type(state.glyphRuntime.labelForKey) == "function"
                        and state.glyphRuntime:labelForKey(key) or tostring(key or "")
                end,
                createIcon = createCachedIcon,
                openPicker = function(wheel, slot)
                    if type(state.openAuxAssignmentPicker) == "function" then
                        return state.openAuxAssignmentPicker(wheel, slot)
                    end
                    return false
                end,
            })
        else
            state.auxEditor = nil
            log("AUX editor unavailable: aux_editor.lua could not be loaded: "
                .. tostring(auxEditorModule), true)
        end

        local okInstructions, instructionsModule = pcall(require, "instructions_popup")
        if okInstructions and type(instructionsModule) == "table"
            and type(instructionsModule.new) == "function" then
            state.instructionsPopup = instructionsModule.new({
                state = state, cfg = cfg, construct = construct, addToCanvas = addToCanvas,
                place = place, setVisible = setVisible, setBorderColor = setBorderColor,
                setText = setText, createText = createCanvasText, colors = COLORS,
                hitTestInvisible = VIS_HIT_TEST_INVISIBLE,
                glyphTextureForKey = function(key, family)
                    if family == "keyboard" then
                        return state.keyboardGlyphRuntime ~= nil
                            and state.keyboardGlyphRuntime:textureForKey(key) or nil
                    end
                    return state.glyphRuntime ~= nil
                        and state.glyphRuntime:textureForKey(key, family or "xbox") or nil
                end,
                glyphLabelForKey = function(key, family)
                    return state.glyphRuntime ~= nil
                        and type(state.glyphRuntime.labelForKey) == "function"
                        and state.glyphRuntime:labelForKey(key, family or "xbox")
                        or tostring(key or "")
                end,
                detectControllerGlyphFamily = function()
                    return type(state.detectControllerGlyphFamily) == "function"
                        and state.detectControllerGlyphFamily(state.pc) or "xbox"
                end,
            })
        else
            state.instructionsPopup = nil
            log("Context instructions unavailable: instructions_popup.lua could not be loaded: "
                .. tostring(instructionsModule), true)
        end

        local okBuilder, builderModule = pcall(require, "editor_builder")
        if okBuilder and type(builderModule) == "table"
            and type(builderModule.new) == "function" then
            state.editorBuilder = builderModule.new({
                state = state,
                cfg = cfg,
                alive = alive,
                construct = construct,
                addToCanvas = addToCanvas,
                place = place,
                setVisible = setVisible,
                setBorderColor = setBorderColor,
                setText = setText,
                createText = createCanvasText,
                colors = COLORS,
                byId = FUNCTION_BY_ID,
                activeShortcuts = function() return ACTIVE_SHORTCUTS end,
                colorForDefinition = colorForDefinition,
                updateCountText = updateEditorCountText,
                updateWheelCountText = updateEditorWheelCountText,
                updateSkinText = updateEditorSkinText,
                updateSlowMotionText = updateEditorSlowMotionText,
                updateHapticsText = updateEditorHapticsText,
                updateZoomText = state.updateEditorZoomText,
                updateFollowTargetText = state.updateEditorFollowTargetText,
                wheelSkins = WHEEL_SKINS,
                updateRow = updateEditorRow,
                pageSize = PAGE_SIZE,
                pageCount = PAGE_COUNT,
                totalSlots = TOTAL_ASSIGNMENT_SLOTS,
                wheelRoman = wheelRoman,
                hitTestInvisible = VIS_HIT_TEST_INVISIBLE,
                buildBindingEditor = function(root, summaryRoot)
                    if state.bindingEditor == nil then return false end
                    return state.bindingEditor:build(root, summaryRoot)
                end,
                buildShortcutEditor = function(root, summaryRoot)
                    if state.shortcutEditor == nil then return false end
                    return state.shortcutEditor:build(root, summaryRoot)
                end,
                buildSphereEditor = function(root)
                    if state.sphereEditor == nil then return false end
                    return state.sphereEditor:build(root)
                end,
                buildAuxEditor = function(root)
                    if state.auxEditor == nil then return false end
                    return state.auxEditor:build(root)
                end,
                buildInstructionsPopup = function(root)
                    if state.instructionsPopup == nil then return false end
                    local built = state.instructionsPopup:build(root)
                    state.editorInstructionsCloseRect = state.instructionsPopup.closeRect
                    return built
                end,
                log = log,
            })
        else
            log("PalWheel editor unavailable: editor_builder.lua could not be loaded: "
                .. tostring(builderModule), true)
            return false
        end
    end
    if state.editorBuilder ~= nil then
        return state.editorBuilder:start(pc)
    end
    return false
end

state.handleEditorKeyboardEvent = function(name, ctrl, shift, alt)
    if not state.editorOpen then return false end
    if state.bindingEditor ~= nil and state.bindingEditor:isOpen()
        and state.bindingEditor:isCapturing() then
        return state.bindingEditor:handleKeyboardEvent(name, ctrl, shift, alt)
    end
    return false
end

local function pointInRect(x, y, rect)
    if rect == nil then return false end
    return x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

local function partyPickerPageCount()
    return math.max(1, math.ceil((tonumber(state.partyCapacity)
        or DEFAULT_PARTY_CAPACITY) / 10))
end

local function updatePartyPickerPage()
    local pageCount = partyPickerPageCount()
    state.editorPartyPage = math.floor(clamp(state.editorPartyPage or 1, 1, pageCount))
    local startNumber = (state.editorPartyPage - 1) * 10 + 1
    state.editorPartyRowIds = {}
    for row = 1, 10 do
        local widgets = (state.editorPartyWidgets or {})[row]
        local number = startNumber + row - 1
        local id = number <= (tonumber(state.partyCapacity) or DEFAULT_PARTY_CAPACITY)
            and ("pal" .. tostring(number)) or nil
        local def = id and FUNCTION_BY_ID[id] or nil
        local rowVisible = state.editorPickerOpen == true and def ~= nil
        if type(widgets) == "table" then
            setVisible(widgets.border, rowVisible)
            setVisible(widgets.text, rowVisible)
            if def ~= nil then
                setBorderColor(widgets.border, colorForDefinition(def))
                setText(widgets.text, tostring(def.label))
            end
        end
        state.editorPartyRowIds[row] = def and def.id or nil
    end
    if alive(state.editorPartyPageText) then
        setText(state.editorPartyPageText, T("page", {
            page = state.editorPartyPage, pages = pageCount }))
        setVisible(state.editorPartyPageText,
            state.editorPickerOpen == true and pageCount > 1)
    end
    local showPaging = state.editorPickerOpen == true and pageCount > 1
    for _, widget in ipairs(state.editorPartyPrevWidgets or {}) do
        setVisible(widget, showPaging)
    end
    for _, widget in ipairs(state.editorPartyNextWidgets or {}) do
        setVisible(widget, showPaging)
    end
end

state.palworldPickerPageCount = function()
    return math.max(1, #(state.palworldPickerPages or {}))
end

state.updatePalworldPickerPage = function()
    if state.palCommandActions ~= nil then
        state.palCommandActions:refreshAvailability(FUNCTION_BY_ID)
    end
    local pageCount = state.palworldPickerPageCount()
    state.editorPalworldPage = math.floor(clamp(state.editorPalworldPage or 1, 1, pageCount))
    local ids = (state.palworldPickerPages or {})[state.editorPalworldPage] or {}
    state.editorPalworldRowIds = {}
    for row = 1, 10 do
        local widgets = (state.editorPalworldWidgets or {})[row]
        local id = ids[row]
        local def = id and FUNCTION_BY_ID[id] or nil
        local rowVisible = state.editorPickerOpen == true and def ~= nil
        if type(widgets) == "table" then
            setVisible(widgets.border, rowVisible)
            setVisible(widgets.text, rowVisible)
            if def ~= nil then
                setBorderColor(widgets.border, colorForDefinition(def))
                setText(widgets.text, tostring(def.label))
                setDefinitionTextColor(widgets.text, def)
            end
        end
        state.editorPalworldRowIds[row] = def and def.id or nil
    end
    if alive(state.editorPalworldPageText) then
        setText(state.editorPalworldPageText, T("page", {
            page = state.editorPalworldPage, pages = pageCount }))
        setVisible(state.editorPalworldPageText,
            state.editorPickerOpen == true and pageCount > 1)
    end
    local showPaging = state.editorPickerOpen == true and pageCount > 1
    for _, widget in ipairs(state.editorPalworldPrevWidgets or {}) do setVisible(widget, showPaging) end
    for _, widget in ipairs(state.editorPalworldNextWidgets or {}) do setVisible(widget, showPaging) end
end

local function shortcutPickerPageCount()
    return math.max(1, math.ceil(#(ACTIVE_SHORTCUTS or {}) / 10))
end

local function updateShortcutPickerPage()
    local pageCount = shortcutPickerPageCount()
    state.editorShortcutPage = math.floor(clamp(state.editorShortcutPage or 1, 1, pageCount))
    local startIndex = (state.editorShortcutPage - 1) * 10 + 1
    state.editorShortcutRowIds = {}
    for row = 1, 10 do
        local widgets = (state.editorShortcutWidgets or {})[row]
        local def = (ACTIVE_SHORTCUTS or {})[startIndex + row - 1]
        local rowVisible = state.editorPickerOpen == true and def ~= nil
        if type(widgets) == "table" then
            setVisible(widgets.border, rowVisible)
            setVisible(widgets.text, rowVisible)
            if def ~= nil then
                setBorderColor(widgets.border, colorForDefinition(def))
                setText(widgets.text, tostring(def.label) .. "    ["
                    .. tostring(def.shortcutDisplay or def.shortcutSpec or "") .. "]")
            end
        end
        state.editorShortcutRowIds[row] = def and def.id or nil
    end
    if alive(state.editorShortcutPageText) then
        setText(state.editorShortcutPageText, T("page", {
            page = state.editorShortcutPage, pages = pageCount }))
        setVisible(state.editorShortcutPageText,
            state.editorPickerOpen == true and pageCount > 1)
    end
    local showPaging = state.editorPickerOpen == true and pageCount > 1
    for _, widget in ipairs(state.editorShortcutPrevWidgets or {}) do setVisible(widget, showPaging) end
    for _, widget in ipairs(state.editorShortcutNextWidgets or {}) do setVisible(widget, showPaging) end
end

local function setPickerVisible(visible)
    state.editorPickerOpen = visible == true
    if alive(state.editorPickerLayer) then
        if visible == true then
            if state.editorPickerChildrenInitialized ~= true then
                for _, widget in ipairs(state.editorPickerWidgets or {}) do
                    setVisible(widget, true)
                end
                state.editorPickerChildrenInitialized = true
            end
            updatePartyPickerPage()
            state.updatePalworldPickerPage()
            updateShortcutPickerPage()
        end
        setVisible(state.editorPickerLayer, visible == true)
        return
    end
    for _, widget in ipairs(state.editorPickerWidgets or {}) do
        setVisible(widget, visible == true)
    end
    updatePartyPickerPage()
    state.updatePalworldPickerPage()
    updateShortcutPickerPage()
end

local function setResetConfirmVisible(visible)
    state.editorResetConfirmOpen = visible == true
    for _, widget in ipairs(state.editorResetConfirmWidgets or {}) do
        setVisible(widget, visible == true)
    end
end

local function setInstructionsVisible(visible, context)
    local requested = visible == true
    local changed = state.editorInstructionsOpen ~= requested
    state.editorInstructionsOpen = requested
    if state.instructionsPopup ~= nil then
        if requested then
            state.instructionsPopup:show(context or state.instructionsPopup.activeContext or "general")
            state.editorInstructionsCloseRect = state.instructionsPopup.closeRect
        else
            state.instructionsPopup:close()
        end
    end
    if changed then
        log(requested and ("PalWheel " .. tostring(context or "general") .. " instructions opened")
            or "PalWheel Menu instructions closed", true)
    end
end

state.openEditorInstructions = function(context)
    setInstructionsVisible(true, context or "general")
    return true
end

local function setEditorDropdownVisible(kind, visible, page)
    if kind == "count" then
        for wheel = 1, PAGE_COUNT do
            for _, widget in ipairs((state.editorCountDropdownWidgets or {})[wheel] or {}) do
                setVisible(widget, visible == true and page == wheel)
            end
        end
        state.editorCountDropdownOpen = visible == true
        state.editorCountDropdownPage = visible == true and page or nil
        return
    end

    if kind == "wheelcount" then
        state.editorWheelCountDropdownOpen = visible == true
        for _, widget in ipairs(state.editorWheelCountDropdownWidgets or {}) do
            setVisible(widget, visible == true)
        end
        return
    end

    state.editorSkinDropdownOpen = visible == true
    for _, widget in ipairs(state.editorSkinDropdownWidgets or {}) do
        setVisible(widget, visible == true)
    end
end

local function closeEditorDropdowns()
    setEditorDropdownVisible("count", false, nil)
    setEditorDropdownVisible("wheelcount", false)
    setEditorDropdownVisible("skin", false)
end

local function refreshEditorRows()
    updateEditorCountText()
    updateEditorWheelCountText()
    updateEditorSkinText()
    updateEditorSlowMotionText()
    updateEditorHapticsText()
    state.updateEditorZoomText()
    state.updateEditorFollowTargetText()
    if state.sphereEditor ~= nil then state.sphereEditor:update() end
    
    
    
    if state.auxEditor ~= nil then state.auxEditor:updateRows() end
    if state.editorBuilder ~= nil and type(state.editorBuilder.updateMenuHint) == "function" then
        state.editorBuilder:updateMenuHint()
    end
    for slotIndex = 1, TOTAL_ASSIGNMENT_SLOTS do
        updateEditorRow(slotIndex)
    end
    setPickerVisible(state.editorPickerOpen == true)
end

state.setMainEditorDiscardConfirmVisible = function(visible)
    state.editorDiscardConfirmOpen = visible == true
    for _, widget in ipairs(state.editorDiscardConfirmWidgets or {}) do
        setVisible(widget, state.editorDiscardConfirmOpen)
    end
end

state.snapshotMainEditorDraft = function()
    local assignments = {}
    for index = 1, TOTAL_ASSIGNMENT_SLOTS do
        assignments[index] = state.assignments[index] or "empty"
    end
    local spheres = {}
    for index = 1, 10 do
        spheres[index] = state.sphereAssignments[index]
            or config.sphereWheelRuntime.defaultOrder[index]
    end
    local aux = { {}, {} }
    for wheel = 1, 2 do
        for slot = 1, 4 do
            aux[wheel][slot] = state.auxAssignments[wheel][slot] or "empty"
        end
    end
    state.editorDraft = {
        assignments = assignments,
        auxAssignments = aux,
        visibleSlotCounts = {
            state.visibleSlotCounts[1], state.visibleSlotCounts[2], state.visibleSlotCounts[3],
        },
        activeWheelCount = state.activeWheelCount,
        sphereAssignments = spheres,
        sphereVisibleSlotCount = state.sphereVisibleSlotCount,
        sphereFollowTargetEnabled = state.sphereFollowTargetEnabled == true,
        wheelSkin = validWheelSkin(state.wheelSkin),
        slowMotionEnabled = cfg("slowMotionEnabled", true) == true,
        controllerZoomEnabled = cfg("controllerZoomEnabled", true) == true,
        hapticsEnabled = math.floor(clamp(
            cfg("controllerHighlightHapticsLevel", 3), 0, 3)) > 0,
    }
end

state.mainEditorHasUnsavedChanges = function()
    local draft = state.editorDraft
    if type(draft) ~= "table" then return false end
    if math.floor(clamp(draft.activeWheelCount or 3, 1, 3))
        ~= math.floor(clamp(state.activeWheelCount or 3, 1, 3)) then return true end
    for index = 1, 3 do
        local fallback = index == 1 and 8 or 12
        if math.floor(clamp((draft.visibleSlotCounts or {})[index] or fallback, 4, 12))
            ~= math.floor(clamp(state.visibleSlotCounts[index] or fallback, 4, 12)) then return true end
    end
    if math.floor(clamp(draft.sphereVisibleSlotCount or 10, 5, 10))
        ~= math.floor(clamp(state.sphereVisibleSlotCount or 10, 5, 10)) then return true end
    if (draft.sphereFollowTargetEnabled == true) ~= (state.sphereFollowTargetEnabled == true) then
        return true
    end
    if validWheelSkin(draft.wheelSkin) ~= validWheelSkin(state.wheelSkin) then return true end
    if (draft.slowMotionEnabled == true) ~= (cfg("slowMotionEnabled", true) == true) then return true end
    if (draft.controllerZoomEnabled == true) ~= (cfg("controllerZoomEnabled", true) == true) then return true end
    local liveHaptics = math.floor(clamp(cfg("controllerHighlightHapticsLevel", 3), 0, 3)) > 0
    if (draft.hapticsEnabled == true) ~= liveHaptics then return true end
    for index = 1, TOTAL_ASSIGNMENT_SLOTS do
        if ((draft.assignments or {})[index] or "empty") ~= (state.assignments[index] or "empty") then
            return true
        end
    end
    for wheel = 1, 2 do
        for slot = 1, 4 do
            if ((((draft.auxAssignments or {})[wheel] or {})[slot]) or "empty")
                ~= ((state.auxAssignments[wheel] or {})[slot] or "empty") then return true end
        end
    end
    for index = 1, 10 do
        if ((draft.sphereAssignments or {})[index] or "")
            ~= (state.sphereAssignments[index] or "") then return true end
    end
    return false
end

state.updateMainEditorSaveVisual = function()
    if alive(state.editorSaveBorder) then
        setBorderColor(state.editorSaveBorder,
            state.mainEditorHasUnsavedChanges() and COLORS.saveDirty or COLORS.saveIdle)
    end
end

state.applyMainEditorDraft = function()
    local draft = state.editorDraft
    if type(draft) ~= "table" then return false end
    if not state.mainEditorHasUnsavedChanges() then
        state.updateMainEditorSaveVisual()
        return true
    end

    local previous = {
        assignments = {}, sphereAssignments = {}, auxAssignments = { {}, {} },
        visibleSlotCounts = {
            state.visibleSlotCounts[1], state.visibleSlotCounts[2], state.visibleSlotCounts[3],
        },
        activeWheelCount = state.activeWheelCount,
        sphereVisibleSlotCount = state.sphereVisibleSlotCount,
        sphereFollowTargetEnabled = state.sphereFollowTargetEnabled,
        wheelSkin = state.wheelSkin,
        slowMotionEnabled = config.slowMotionEnabled,
        controllerZoomEnabled = config.controllerZoomEnabled,
        hapticsLevel = config.controllerHighlightHapticsLevel,
    }
    for index = 1, TOTAL_ASSIGNMENT_SLOTS do previous.assignments[index] = state.assignments[index] end
    for wheel = 1, 2 do
        for slot = 1, 4 do previous.auxAssignments[wheel][slot] = state.auxAssignments[wheel][slot] end
    end
    for index = 1, 10 do previous.sphereAssignments[index] = state.sphereAssignments[index] end

    for index = 1, TOTAL_ASSIGNMENT_SLOTS do
        local id = (draft.assignments or {})[index] or "empty"
        state.assignments[index] = FUNCTION_BY_ID[id] ~= nil and id or "empty"
    end
    for wheel = 1, 2 do
        for slot = 1, 4 do
            local id = (((draft.auxAssignments or {})[wheel] or {})[slot]) or "empty"
            state.auxAssignments[wheel][slot] = FUNCTION_BY_ID[id] ~= nil and id or "empty"
        end
    end
    for index = 1, 3 do
        local fallback = index == 1 and 8 or 12
        state.visibleSlotCounts[index] = math.floor(clamp(
            (draft.visibleSlotCounts or {})[index] or fallback, 4, 12))
    end
    state.activeWheelCount = math.floor(clamp(draft.activeWheelCount or 3, 1, 3))
    if state.activePage > state.activeWheelCount then state.activePage = state.activeWheelCount end
    state.sphereAssignments = config.sphereWheelRuntime.validatedOrder(draft.sphereAssignments)
    state.sphereVisibleSlotCount = math.floor(clamp(draft.sphereVisibleSlotCount or 10, 5, 10))
    state.sphereFollowTargetEnabled = draft.sphereFollowTargetEnabled == true
    state.wheelSkin = validWheelSkin(draft.wheelSkin)
    config.slowMotionEnabled = draft.slowMotionEnabled == true
    config.controllerZoomEnabled = draft.controllerZoomEnabled == true
    config.controllerHighlightHapticsLevel = draft.hapticsEnabled == true and 3 or 0
    if config.controllerHighlightHapticsLevel == 0 and state.haptics ~= nil then
        state.haptics:stop(state.pc)
    end

    if not saveSettings() then
        for index = 1, TOTAL_ASSIGNMENT_SLOTS do state.assignments[index] = previous.assignments[index] end
        state.auxAssignments = previous.auxAssignments
        for index = 1, 3 do state.visibleSlotCounts[index] = previous.visibleSlotCounts[index] end
        state.activeWheelCount = previous.activeWheelCount
        state.sphereAssignments = previous.sphereAssignments
        state.sphereVisibleSlotCount = previous.sphereVisibleSlotCount
        state.sphereFollowTargetEnabled = previous.sphereFollowTargetEnabled
        state.wheelSkin = previous.wheelSkin
        config.slowMotionEnabled = previous.slowMotionEnabled
        config.controllerZoomEnabled = previous.controllerZoomEnabled
        config.controllerHighlightHapticsLevel = previous.hapticsLevel
        refreshEditorRows()
        if state.auxEditor ~= nil then state.auxEditor:updateRows() end
        state.updateMainEditorSaveVisual()
        log("PalWheel Menu draft could not be saved; runtime values restored", true)
        return false
    end

    local mainWheelChanged = previous.wheelSkin ~= state.wheelSkin
        or previous.activeWheelCount ~= state.activeWheelCount
    local sphereWheelChanged = previous.wheelSkin ~= state.wheelSkin
        or previous.sphereVisibleSlotCount ~= state.sphereVisibleSlotCount
    for index = 1, 3 do
        if previous.visibleSlotCounts[index] ~= state.visibleSlotCounts[index] then
            mainWheelChanged = true
        end
    end
    for index = 1, TOTAL_ASSIGNMENT_SLOTS do
        if previous.assignments[index] ~= state.assignments[index] then mainWheelChanged = true end
    end
    for wheel = 1, 2 do
        for slot = 1, 4 do
            if previous.auxAssignments[wheel][slot] ~= state.auxAssignments[wheel][slot] then
                mainWheelChanged = true
            end
        end
    end
    for index = 1, 10 do
        if previous.sphereAssignments[index] ~= state.sphereAssignments[index] then
            sphereWheelChanged = true
        end
    end
    if mainWheelChanged then state.invalidateWheelMode("main") end
    if sphereWheelChanged then state.invalidateWheelMode("sphere") end

    refreshEditorRows()
    if state.auxEditor ~= nil then state.auxEditor:updateRows() end
    state.updateMainEditorSaveVisual()
    log("PalWheel Menu draft saved and applied")
    return true
end

local function openAssignmentPicker(slotIndex)
    closeEditorDropdowns()
    if state.sphereEditor ~= nil then state.sphereEditor:closePanel() end
    setResetConfirmVisible(false)
    if type(state.setMainEditorDiscardConfirmVisible) == "function" then
        state.setMainEditorDiscardConfirmVisible(false)
    end
    state.editorPickingSlot = slotIndex
    state.editorPickingAuxWheel = nil
    state.editorPickingAuxSlot = nil
    state.editorReturnToAux = false
    state.editorPartyPage = math.floor(clamp(
        state.editorPartyPage or 1, 1, partyPickerPageCount()))
    state.editorShortcutPage = math.floor(clamp(
        state.editorShortcutPage or 1, 1, shortcutPickerPageCount()))
    state.editorPalworldPage = math.floor(clamp(
        state.editorPalworldPage or 1, 1, state.palworldPickerPageCount()))
    if alive(state.editorPickerTitle) then
        local pie = math.floor((slotIndex - 1) / PAGE_SIZE) + 1
        local localSlot = ((slotIndex - 1) % PAGE_SIZE) + 1
        setText(state.editorPickerTitle,
            T("chooseWheelSlot", {
                wheel = wheelRoman(pie), slot = string.format("%02d", localSlot) }))
    end
    setPickerVisible(true)
end

state.openAuxAssignmentPicker = function(wheel, slotIndex)
    closeEditorDropdowns()
    if state.sphereEditor ~= nil then state.sphereEditor:closePanel() end
    setResetConfirmVisible(false)
    state.editorPickingSlot = nil
    state.editorReturnToAux = false
    state.editorPickingAuxWheel = math.floor(clamp(wheel or 1, 1, 2))
    state.editorPickingAuxSlot = math.floor(clamp(slotIndex or 1, 1, 4))
    state.editorPartyPage = math.floor(clamp(state.editorPartyPage or 1, 1, partyPickerPageCount()))
    state.editorShortcutPage = math.floor(clamp(state.editorShortcutPage or 1, 1, shortcutPickerPageCount()))
    state.editorPalworldPage = math.floor(clamp(state.editorPalworldPage or 1, 1, state.palworldPickerPageCount()))
    if alive(state.editorPickerTitle) then
        setText(state.editorPickerTitle, T("chooseAuxSlot", {
            wheel = state.editorPickingAuxWheel == 1 and "I" or "II",
            slot = string.format("%02d", state.editorPickingAuxSlot) }))
    end
    setPickerVisible(true)
end

local function closeAssignmentPicker()
    setPickerVisible(false)
    state.editorPickingSlot = nil
    state.editorPickingAuxWheel = nil
    state.editorPickingAuxSlot = nil
    state.editorReturnToAux = false
end

local function assignPickerChoice(catalogIndex)
    local slotIndex = state.editorPickingSlot
    local auxWheel, auxSlot = state.editorPickingAuxWheel, state.editorPickingAuxSlot
    local def = FUNCTION_CATALOG[catalogIndex]
    if def == nil or type(state.editorDraft) ~= "table" then return false end
    if auxWheel ~= nil and auxSlot ~= nil then
        state.editorDraft.auxAssignments[auxWheel][auxSlot] = def.id
        if state.auxEditor ~= nil then state.auxEditor:updateRow(auxWheel, auxSlot) end
        log("Editor draft assigned AUX " .. tostring(auxWheel) .. " slot "
            .. tostring(auxSlot) .. " = " .. tostring(def.label), true)
    elseif slotIndex ~= nil then
        state.editorDraft.assignments[slotIndex] = def.id
        updateEditorRow(slotIndex)
        log("Editor draft assigned slot " .. tostring(slotIndex) .. " = " .. def.label)
    else
        return false
    end
    state.updateMainEditorSaveVisual()
    closeAssignmentPicker()
    return true
end

local function assignPickerChoiceById(id)
    local def = FUNCTION_BY_ID[id]
    local slotIndex = state.editorPickingSlot
    local auxWheel, auxSlot = state.editorPickingAuxWheel, state.editorPickingAuxSlot
    if type(def) ~= "table" or type(state.editorDraft) ~= "table" then return false end
    if auxWheel ~= nil and auxSlot ~= nil then
        state.editorDraft.auxAssignments[auxWheel][auxSlot] = def.id
        if state.auxEditor ~= nil then state.auxEditor:updateRow(auxWheel, auxSlot) end
        log("Editor draft assigned AUX " .. tostring(auxWheel) .. " slot "
            .. tostring(auxSlot) .. " = " .. tostring(def.label), true)
    elseif slotIndex ~= nil then
        state.editorDraft.assignments[slotIndex] = def.id
        updateEditorRow(slotIndex)
        log("Editor draft assigned slot " .. tostring(slotIndex) .. " = " .. tostring(def.label))
    else
        return false
    end
    state.updateMainEditorSaveVisual()
    closeAssignmentPicker()
    return true
end

local function restoreDefaultAssignments()
    if type(state.editorDraft) ~= "table" then state.snapshotMainEditorDraft() end
    local defaults = makeDefaultAssignments()
    for slotIndex = 1, TOTAL_ASSIGNMENT_SLOTS do
        state.editorDraft.assignments[slotIndex] = defaults[slotIndex] or "empty"
    end
    state.editorDraft.visibleSlotCounts = {
        8, 8, 8,
    }
    state.editorDraft.activeWheelCount = 3
    state.editorDraft.auxAssignments = config.auxWheelRuntime.defaultAssignments()
    state.editorDraft.sphereAssignments = config.sphereWheelRuntime.validatedOrder(nil)
    state.editorDraft.sphereVisibleSlotCount = 10
    state.editorDraft.sphereFollowTargetEnabled = true
    state.editorDraft.wheelSkin = "wheel_02.png"
    state.editorDraft.slowMotionEnabled = true
    state.editorDraft.controllerZoomEnabled = true
    state.editorDraft.hapticsEnabled = true
    closeAssignmentPicker()
    if state.sphereEditor ~= nil then state.sphereEditor:closePanel() end
    setResetConfirmVisible(false)
    refreshEditorRows()
    if state.auxEditor ~= nil then state.auxEditor:updateRows() end
    state.updateMainEditorSaveVisual()
    log("PalWheel Menu packaged defaults loaded into draft")
    return true
end

local function handleEditorClick(direction, overrideX, overrideY)
    if not state.editorOpen then return end
    if state.editorBuilder ~= nil and state.editorBuilder.complete ~= true then
        return
    end
    if os.clock() < (state.editorClicksReadyAt or 0.0) then return end
    local pc = state.pc
    local controllerDispatch = tonumber(overrideX) ~= nil and tonumber(overrideY) ~= nil
    if not controllerDispatch and state.controllerUiNavigation ~= nil then
        state.controllerUiNavigation:setControllerPresentation(false)
    end
    local x, y = tonumber(overrideX), tonumber(overrideY)
    if x == nil or y == nil then x, y = readMousePosition(pc) end
    if x == nil or y == nil then return end

    if state.editorDiscardConfirmOpen then
        if direction < 0 or pointInRect(x, y, state.editorDiscardConfirmNoRect) then
            state.setMainEditorDiscardConfirmVisible(false)
            return
        end
        if pointInRect(x, y, state.editorDiscardConfirmYesRect) then
            state.setMainEditorDiscardConfirmVisible(false)
            if type(state.closeEditorNow) == "function" then state.closeEditorNow("Unsaved PalWheel Menu changes discarded") end
            return
        end
        return
    end

    if state.editorInstructionsOpen then
        if direction < 0 or pointInRect(x, y, state.editorInstructionsCloseRect) then
            setInstructionsVisible(false)
        end
        return
    end

    if direction > 0 and state.bindingEditor ~= nil
        and state.bindingEditor:isSummaryHit(x, y) then
        closeEditorDropdowns()
        closeAssignmentPicker()
        setResetConfirmVisible(false)
        setInstructionsVisible(false)
        if state.shortcutEditor ~= nil then state.shortcutEditor:closePanel(true) end
        if state.sphereEditor ~= nil then state.sphereEditor:closePanel() end
        state.bindingEditor:openPanel()
        return
    end
    if direction > 0 and state.shortcutEditor ~= nil
        and state.shortcutEditor:isSummaryHit(x, y) then
        closeEditorDropdowns()
        closeAssignmentPicker()
        setResetConfirmVisible(false)
        setInstructionsVisible(false)
        if state.bindingEditor ~= nil then state.bindingEditor:closePanel(true) end
        if state.sphereEditor ~= nil then state.sphereEditor:closePanel() end
        state.shortcutEditor:openPanel()
        return
    end
    if direction > 0 and pointInRect(x, y, state.editorInstructionsRect)
        and not (state.bindingEditor ~= nil and state.bindingEditor:isOpen())
        and not (state.shortcutEditor ~= nil and state.shortcutEditor:isOpen()) then
        closeEditorDropdowns()
        closeAssignmentPicker()
        setResetConfirmVisible(false)
        if state.bindingEditor ~= nil then state.bindingEditor:closePanel(true) end
        if state.shortcutEditor ~= nil then state.shortcutEditor:closePanel(true) end
        if state.sphereEditor ~= nil then state.sphereEditor:closePanel() end
        setInstructionsVisible(true, "general")
        return
    end

    if state.bindingEditor ~= nil and state.bindingEditor:isOpen() then
        state.bindingEditor:handleClick(x, y, direction)
        return
    end
    if state.shortcutEditor ~= nil and state.shortcutEditor:isOpen() then
        state.shortcutEditor:handleClick(x, y, direction)
        return
    end
    if state.sphereEditor ~= nil and state.sphereEditor:isBusy() then
        state.sphereEditor:handleClick(x, y, direction)
        return
    end

    if state.editorResetConfirmOpen then
        if direction < 0 or pointInRect(x, y, state.editorResetConfirmNoRect) then
            setResetConfirmVisible(false)
            return
        end
        if pointInRect(x, y, state.editorResetConfirmYesRect) then
            restoreDefaultAssignments()
            return
        end
        return
    end

    if state.editorWheelCountDropdownOpen then
        for value, rect in pairs(state.editorWheelCountOptionRects or {}) do
            if pointInRect(x, y, rect) then
                if state.editorDraft ~= nil then
                    state.editorDraft.activeWheelCount = math.floor(clamp(value, 1, PAGE_COUNT))
                end
                updateEditorWheelCountText()
                closeEditorDropdowns()
                state.updateMainEditorSaveVisual()
                return
            end
        end
        closeEditorDropdowns()
        if direction < 0 then return end
    elseif state.editorCountDropdownOpen then
        local page = state.editorCountDropdownPage
        for value, rect in pairs((state.editorCountOptionRects or {})[page] or {}) do
            if pointInRect(x, y, rect) then
                if state.editorDraft ~= nil then
                    state.editorDraft.visibleSlotCounts[page] = math.floor(clamp(value, 4, 12))
                end
                updateEditorCountText(page)
                closeEditorDropdowns()
                state.updateMainEditorSaveVisual()
                return
            end
        end
        closeEditorDropdowns()
        if direction < 0 then return end
    elseif state.editorSkinDropdownOpen then
        for skin, rect in pairs(state.editorSkinOptionRects or {}) do
            if pointInRect(x, y, rect) then
                if state.editorDraft ~= nil then state.editorDraft.wheelSkin = validWheelSkin(skin) end
                updateEditorSkinText()
                closeEditorDropdowns()
                state.updateMainEditorSaveVisual()
                return
            end
        end
        closeEditorDropdowns()
        if direction < 0 then return end
    end

    if state.editorPickerOpen then
        if direction < 0 then
            closeAssignmentPicker()
            return
        end
        local partyPageCount = partyPickerPageCount()
        if partyPageCount > 1 and pointInRect(x, y, state.editorPartyPrevRect) then
            state.editorPartyPage = state.editorPartyPage - 1
            if state.editorPartyPage < 1 then state.editorPartyPage = partyPageCount end
            updatePartyPickerPage()
            return
        end
        if partyPageCount > 1 and pointInRect(x, y, state.editorPartyNextRect) then
            state.editorPartyPage = state.editorPartyPage + 1
            if state.editorPartyPage > partyPageCount then state.editorPartyPage = 1 end
            updatePartyPickerPage()
            return
        end
        for row, rect in ipairs(state.editorPartyRects or {}) do
            local id = state.editorPartyRowIds and state.editorPartyRowIds[row] or nil
            if id ~= nil and pointInRect(x, y, rect) then
                assignPickerChoiceById(id)
                return
            end
        end

        local palworldPageCount = state.palworldPickerPageCount()
        if palworldPageCount > 1 and pointInRect(x, y, state.editorPalworldPrevRect) then
            state.editorPalworldPage = state.editorPalworldPage - 1
            if state.editorPalworldPage < 1 then state.editorPalworldPage = palworldPageCount end
            state.updatePalworldPickerPage()
            return
        end
        if palworldPageCount > 1 and pointInRect(x, y, state.editorPalworldNextRect) then
            state.editorPalworldPage = state.editorPalworldPage + 1
            if state.editorPalworldPage > palworldPageCount then state.editorPalworldPage = 1 end
            state.updatePalworldPickerPage()
            return
        end
        for row, rect in ipairs(state.editorPalworldRects or {}) do
            local id = state.editorPalworldRowIds and state.editorPalworldRowIds[row] or nil
            if id ~= nil and pointInRect(x, y, rect) then
                assignPickerChoiceById(id)
                return
            end
        end

        local pageCount = shortcutPickerPageCount()
        if pageCount > 1 and pointInRect(x, y, state.editorShortcutPrevRect) then
            state.editorShortcutPage = state.editorShortcutPage - 1
            if state.editorShortcutPage < 1 then state.editorShortcutPage = pageCount end
            updateShortcutPickerPage()
            return
        end
        if pageCount > 1 and pointInRect(x, y, state.editorShortcutNextRect) then
            state.editorShortcutPage = state.editorShortcutPage + 1
            if state.editorShortcutPage > pageCount then state.editorShortcutPage = 1 end
            updateShortcutPickerPage()
            return
        end
        for row, rect in ipairs(state.editorShortcutRects or {}) do
            local id = state.editorShortcutRowIds and state.editorShortcutRowIds[row] or nil
            if id ~= nil and pointInRect(x, y, rect) then
                assignPickerChoiceById(id)
                return
            end
        end
        for catalogIndex, rect in pairs(state.editorPickerRects or {}) do
            if pointInRect(x, y, rect) then
                assignPickerChoice(catalogIndex)
                return
            end
        end
        if not pointInRect(x, y, state.editorPickerPanelRect) then
            closeAssignmentPicker()
        end
        return
    end

    if state.sphereEditor ~= nil and state.sphereEditor:handleClick(x, y, direction) then
        closeEditorDropdowns()
        return
    end

    if direction < 0 then
        if not controllerDispatch then return end
        if state.mainEditorHasUnsavedChanges() then
            closeEditorDropdowns()
            closeAssignmentPicker()
            if state.sphereEditor ~= nil then state.sphereEditor:closePanel() end
            setResetConfirmVisible(false)
            setInstructionsVisible(false)
            state.setMainEditorDiscardConfirmVisible(true)
        elseif type(state.closeEditorNow) == "function" then
            state.closeEditorNow("Controller Back closed PalWheel Menu")
        end
        return
    end
    if pointInRect(x, y, state.editorWheelCountDropdownRect) then
        if state.sphereEditor ~= nil then state.sphereEditor:closeDropdown() end
        setEditorDropdownVisible("count", false, nil)
        setEditorDropdownVisible("skin", false)
        setEditorDropdownVisible("wheelcount", true)
        return
    end

    for page = 1, PAGE_COUNT do
        if pointInRect(x, y, (state.editorCountDropdownRects or {})[page]) then
            if state.sphereEditor ~= nil then state.sphereEditor:closeDropdown() end
            setEditorDropdownVisible("wheelcount", false)
            setEditorDropdownVisible("skin", false)
            setEditorDropdownVisible("count", true, page)
            return
        end
    end
    if pointInRect(x, y, state.editorSkinDropdownRect) then
        if state.sphereEditor ~= nil then state.sphereEditor:closeDropdown() end
        setEditorDropdownVisible("count", false, nil)
        setEditorDropdownVisible("wheelcount", false)
        setEditorDropdownVisible("skin", true)
        return
    end
    if pointInRect(x, y, state.editorResetShortcutsRect) then
        closeEditorDropdowns()
        closeAssignmentPicker()
        setInstructionsVisible(false)
        setResetConfirmVisible(true)
        return
    end
    if pointInRect(x, y, state.editorSlowMotionRect) then
        if state.editorDraft ~= nil then
            state.editorDraft.slowMotionEnabled = not (state.editorDraft.slowMotionEnabled == true)
        end
        updateEditorSlowMotionText()
        state.updateMainEditorSaveVisual()
        return
    end
    if pointInRect(x, y, state.editorHapticsRect) then
        if state.editorDraft ~= nil then
            state.editorDraft.hapticsEnabled = not (state.editorDraft.hapticsEnabled == true)
        end
        updateEditorHapticsText()
        state.updateMainEditorSaveVisual()
        return
    end
    if pointInRect(x, y, state.editorZoomRect) then
        if state.editorDraft ~= nil then
            state.editorDraft.controllerZoomEnabled = not (state.editorDraft.controllerZoomEnabled == true)
        end
        state.updateEditorZoomText()
        state.updateMainEditorSaveVisual()
        return
    end
    if pointInRect(x, y, state.editorFollowTargetRect) then
        if state.editorDraft ~= nil then
            state.editorDraft.sphereFollowTargetEnabled = not (state.editorDraft.sphereFollowTargetEnabled == true)
        end
        state.updateEditorFollowTargetText()
        state.updateMainEditorSaveVisual()
        return
    end
    if pointInRect(x, y, state.editorSaveRect) then
        state.applyMainEditorDraft()
        return
    end
    if pointInRect(x, y, state.editorCloseRect) then
        if state.mainEditorHasUnsavedChanges() then
            closeEditorDropdowns()
            closeAssignmentPicker()
            if state.sphereEditor ~= nil then state.sphereEditor:closePanel() end
            setResetConfirmVisible(false)
            setInstructionsVisible(false)
            state.setMainEditorDiscardConfirmVisible(true)
        elseif type(state.closeEditorNow) == "function" then
            state.closeEditorNow("CLOSE button closed assignment editor")
        end
        return
    end
    if state.auxEditor ~= nil and type(state.auxEditor.handleMainClick) == "function"
        and state.auxEditor:handleMainClick(x, y, direction) then
        return
    end
    for slotIndex = 1, TOTAL_ASSIGNMENT_SLOTS do
        local row = state.editorRows[slotIndex]
        if row ~= nil and pointInRect(x, y, row.rect) then
            openAssignmentPicker(slotIndex)
            return
        end
    end
end

local function addControllerUiItem(items, id, rect, enabled)
    if type(rect) ~= "table" then return end
    items[#items + 1] = {
        id = tostring(id), rect = rect, enabled = enabled ~= false,
    }
end

state.controllerUiContext = function()
    local context = {
        path = { "main" }, items = {}, defaultId = "main.wheel.1",
        hints = {}, saveAllowed = false,
    }
    local items = context.items

    if state.editorDiscardConfirmOpen then
        context.path = { "main", "discard" }
        addControllerUiItem(items, "main.discard", state.editorDiscardConfirmYesRect)
        addControllerUiItem(items, "main.keep", state.editorDiscardConfirmNoRect)
        context.defaultId, context.safeId = "main.keep", "main.keep"
        context.hints.back = state.editorDiscardConfirmNoRect
        return context
    end

    if state.editorInstructionsOpen then
        local instructionContext = state.instructionsPopup ~= nil
            and state.instructionsPopup.activeContext or "general"
        context.path = { "main", "instructions", tostring(instructionContext) }
        addControllerUiItem(items, "instructions.close", state.editorInstructionsCloseRect)
        context.defaultId = "instructions.close"
        context.hints.back = state.editorInstructionsCloseRect
        return context
    end

    local bindings = state.bindingEditor
    if bindings ~= nil and bindings:isOpen() then
        context.path = { "main", "controls" }
        if bindings.confirmOpen then
            context.path[3] = "discard"
            addControllerUiItem(items, "controls.discard", bindings.confirmDiscardRect)
            addControllerUiItem(items, "controls.keep", bindings.confirmCancelRect)
            context.defaultId, context.safeId = "controls.keep", "controls.keep"
            context.hints.back = bindings.confirmCancelRect
            return context
        end
        if bindings.capture ~= nil then
            context.path[3] = "automatic_capture"
            addControllerUiItem(items, "controls.capture.cancel", bindings.captureCancelRect)
            context.defaultId, context.safeId = "controls.capture.cancel", "controls.capture.cancel"
            context.hints.back = bindings.captureCancelRect
            context.rawCapture = true
            return context
        end
        if bindings.pickerField ~= nil then
            local device = tostring(bindings.pickerDevice or "keyboard")
            context.path[3] = device .. "_picker"
            local choices = device == "controller" and bindings.controllerChoiceRects
                or bindings.keyboardChoiceRects
            for name, rect in pairs(choices or {}) do
                addControllerUiItem(items, "controls.choice." .. tostring(name), rect)
            end
            local confirmRect = device == "controller" and bindings.controllerPickerConfirmRect
                or bindings.keyboardPickerConfirmRect
            local autoRect = device == "controller" and bindings.controllerAutoRect
                or bindings.keyboardAutoRect
            local cancelRect = device == "controller" and bindings.controllerPickerCancelRect
                or bindings.keyboardPickerCancelRect
            addControllerUiItem(items, "controls.picker.confirm", confirmRect)
            addControllerUiItem(items, "controls.picker.auto", autoRect)
            addControllerUiItem(items, "controls.picker.cancel", cancelRect)
            context.defaultId = "controls.choice." .. tostring(bindings.pickerPendingValue or "")
            context.hints.back = cancelRect
            context.saveAllowed = true
            context.saveRect = confirmRect
            context.hints.save = confirmRect
            return context
        end
        addControllerUiItem(items, "controls.mode", bindings.openModeRect)
        for field, rect in pairs(bindings.changeRects or {}) do
            addControllerUiItem(items, "controls.change." .. tostring(field), rect)
        end
        addControllerUiItem(items, "controls.restore", bindings.resetRect)
        addControllerUiItem(items, "controls.instructions", bindings.instructionsRect)
        addControllerUiItem(items, "controls.save", bindings.saveRect)
        addControllerUiItem(items, "controls.close", bindings.closeRect)
        context.defaultId = "controls.change.openKey"
        context.saveAllowed = true
        context.saveRect = bindings.saveRect
        context.hints.back = bindings.closeRect
        context.hints.save = bindings.saveRect
        return context
    end

    local shortcuts = state.shortcutEditor
    if shortcuts ~= nil and shortcuts:isOpen() then
        context.path = { "main", "shortcuts" }
        if shortcuts.confirmOpen then
            context.path[3] = "discard"
            addControllerUiItem(items, "shortcuts.discard", shortcuts.confirmDiscardRect)
            addControllerUiItem(items, "shortcuts.keep", shortcuts.confirmCancelRect)
            context.defaultId, context.safeId = "shortcuts.keep", "shortcuts.keep"
            context.hints.back = shortcuts.confirmCancelRect
            return context
        end
        if shortcuts.textEdit ~= nil then
            context.path[3] = "virtual_keyboard"
            local idMode = shortcuts.textEdit.field == "id"
            for index, choice in ipairs(shortcuts.textChoices or {}) do
                if not idMode or choice.idAllowed == true then
                    addControllerUiItem(items, "shortcuts.text.key." .. tostring(index), choice.rect)
                end
            end
            if not idMode then addControllerUiItem(items, "shortcuts.text.case", shortcuts.textCaseRect) end
            addControllerUiItem(items, "shortcuts.text.backspace", shortcuts.textBackspaceRect)
            addControllerUiItem(items, "shortcuts.text.clear", shortcuts.textClearRect)
            addControllerUiItem(items, "shortcuts.text.restore", shortcuts.textRestoreRect)
            addControllerUiItem(items, "shortcuts.text.apply", shortcuts.textApplyRect)
            addControllerUiItem(items, "shortcuts.text.cancel", shortcuts.textCancelRect)
            context.defaultId = idMode and "shortcuts.text.key.13" or "shortcuts.text.key.25"
            context.hints.back = shortcuts.textCancelRect
            context.saveAllowed = true
            context.saveRect = shortcuts.textApplyRect
            context.hints.save = shortcuts.textApplyRect
            return context
        end
        if shortcuts.capture ~= nil then
            context.path[3] = "binding_picker"
            for modifier, rect in pairs(shortcuts.modifierRects or {}) do
                addControllerUiItem(items, "shortcuts.modifier." .. tostring(modifier), rect)
            end
            for spec, rect in pairs(shortcuts.pickerChoiceRects or {}) do
                addControllerUiItem(items, "shortcuts.binding." .. tostring(spec), rect)
            end
            addControllerUiItem(items, "shortcuts.binding.confirm", shortcuts.captureConfirmRect)
            addControllerUiItem(items, "shortcuts.binding.cancel", shortcuts.captureCancelRect)
            context.defaultId = "shortcuts.binding." .. tostring(shortcuts.capture.pendingKey or "")
            context.hints.back = shortcuts.captureCancelRect
            context.saveAllowed = true
            context.saveRect = shortcuts.captureConfirmRect
            context.hints.save = shortcuts.captureConfirmRect
            return context
        end

        local first = (math.floor(tonumber(shortcuts.page) or 1) - 1) * 8 + 1
        for displayRow, rects in ipairs(shortcuts.rowRects or {}) do
            if shortcuts.rows[first + displayRow - 1] ~= nil then
                for _, field in ipairs({ "active", "label", "id", "binding", "duplicate", "delete" }) do
                    addControllerUiItem(items,
                        "shortcuts.row." .. tostring(displayRow) .. "." .. field, rects[field])
                end
            end
        end
        addControllerUiItem(items, "shortcuts.prev", shortcuts.prevRect)
        addControllerUiItem(items, "shortcuts.next", shortcuts.nextRect)
        addControllerUiItem(items, "shortcuts.add", shortcuts.addRect)
        addControllerUiItem(items, "shortcuts.reload", shortcuts.reloadRect)
        addControllerUiItem(items, "shortcuts.restore", shortcuts.restoreRect)
        addControllerUiItem(items, "shortcuts.instructions", shortcuts.instructionsRect)
        addControllerUiItem(items, "shortcuts.save", shortcuts.saveRect)
        addControllerUiItem(items, "shortcuts.close", shortcuts.closeRect)
        context.defaultId = shortcuts.rows[first] ~= nil and "shortcuts.row.1.label" or "shortcuts.add"
        context.saveAllowed, context.saveRect = true, shortcuts.saveRect
        context.hints.back = shortcuts.closeRect
        context.hints.save = shortcuts.saveRect
        return context
    end

    local spheres = state.sphereEditor
    if spheres ~= nil and spheres:isBusy() then
        context.path = { "main", spheres.pickerOpen and "sphere_picker" or "sphere_count" }
        if spheres.pickerOpen then
            for id, rect in pairs(spheres.pickerRects or {}) do
                addControllerUiItem(items, "sphere.choice." .. tostring(id), rect)
            end
            local order = state.editorDraft and state.editorDraft.sphereAssignments or state.sphereAssignments
            local current = order and order[spheres.pickingSlot or 1] or nil
            context.defaultId = "sphere.choice." .. tostring(current or "")
        else
            for value, rect in pairs(spheres.countOptionRects or {}) do
                addControllerUiItem(items, "sphere.count." .. tostring(value), rect)
            end
            context.defaultId = "sphere.count." .. tostring(state.editorDraft
                and state.editorDraft.sphereVisibleSlotCount or state.sphereVisibleSlotCount)
        end
        return context
    end

    if state.editorResetConfirmOpen then
        context.path = { "main", "restore_confirm" }
        addControllerUiItem(items, "main.restore.confirm", state.editorResetConfirmYesRect)
        addControllerUiItem(items, "main.restore.cancel", state.editorResetConfirmNoRect)
        context.defaultId, context.safeId = "main.restore.cancel", "main.restore.cancel"
        context.hints.back = state.editorResetConfirmNoRect
        return context
    end

    if state.editorPickerOpen then
        context.path = { "main", "assignment_picker" }
        for index, rect in pairs(state.editorPickerRects or {}) do
            addControllerUiItem(items, "assignment.catalog." .. tostring(index), rect)
        end
        if partyPickerPageCount() > 1 then
            addControllerUiItem(items, "assignment.party.prev", state.editorPartyPrevRect)
            addControllerUiItem(items, "assignment.party.next", state.editorPartyNextRect)
        end
        for row, rect in ipairs(state.editorPartyRects or {}) do
            if state.editorPartyRowIds and state.editorPartyRowIds[row] ~= nil then
                addControllerUiItem(items, "assignment.party." .. tostring(row), rect)
            end
        end
        if state.palworldPickerPageCount() > 1 then
            addControllerUiItem(items, "assignment.palworld.prev", state.editorPalworldPrevRect)
            addControllerUiItem(items, "assignment.palworld.next", state.editorPalworldNextRect)
        end
        for row, rect in ipairs(state.editorPalworldRects or {}) do
            if state.editorPalworldRowIds and state.editorPalworldRowIds[row] ~= nil then
                addControllerUiItem(items, "assignment.palworld." .. tostring(row), rect)
            end
        end
        if shortcutPickerPageCount() > 1 then
            addControllerUiItem(items, "assignment.shortcut.prev", state.editorShortcutPrevRect)
            addControllerUiItem(items, "assignment.shortcut.next", state.editorShortcutNextRect)
        end
        for row, rect in ipairs(state.editorShortcutRects or {}) do
            if state.editorShortcutRowIds and state.editorShortcutRowIds[row] ~= nil then
                addControllerUiItem(items, "assignment.shortcut." .. tostring(row), rect)
            end
        end
        context.defaultId = "assignment.catalog.1"
        return context
    end

    if state.editorWheelCountDropdownOpen then
        context.path = { "main", "wheel_count" }
        for value, rect in pairs(state.editorWheelCountOptionRects or {}) do
            addControllerUiItem(items, "wheel.count." .. tostring(value), rect)
        end
        context.defaultId = "wheel.count." .. tostring(state.editorDraft and state.editorDraft.activeWheelCount or 3)
        return context
    end
    if state.editorCountDropdownOpen then
        local page = state.editorCountDropdownPage
        context.path = { "main", "slot_count_" .. tostring(page) }
        for value, rect in pairs((state.editorCountOptionRects or {})[page] or {}) do
            addControllerUiItem(items, "slot.count." .. tostring(value), rect)
        end
        local value = state.editorDraft and state.editorDraft.visibleSlotCounts
            and state.editorDraft.visibleSlotCounts[page] or 12
        context.defaultId = "slot.count." .. tostring(value)
        return context
    end
    if state.editorSkinDropdownOpen then
        context.path = { "main", "skin" }
        for skin, rect in pairs(state.editorSkinOptionRects or {}) do
            addControllerUiItem(items, "skin." .. tostring(skin), rect)
        end
        context.defaultId = "skin." .. tostring(state.editorDraft and state.editorDraft.wheelSkin or state.wheelSkin)
        return context
    end

    addControllerUiItem(items, "main.wheel.count", state.editorWheelCountDropdownRect)
    addControllerUiItem(items, "main.skin", state.editorSkinDropdownRect)
    addControllerUiItem(items, "main.slowmotion", state.editorSlowMotionRect)
    addControllerUiItem(items, "main.zoom", state.editorZoomRect)
    addControllerUiItem(items, "main.haptics", state.editorHapticsRect)
    addControllerUiItem(items, "main.follow", state.editorFollowTargetRect)
    addControllerUiItem(items, "main.restore", state.editorResetShortcutsRect)
    for page = 1, 3 do
        addControllerUiItem(items, "main.slotcount." .. tostring(page),
            (state.editorCountDropdownRects or {})[page])
    end
    for slot, row in pairs(state.editorRows or {}) do
        addControllerUiItem(items, "main.wheel." .. tostring(slot), row and row.rect)
    end
    if state.auxEditor ~= nil then
        for wheel = 1, 2 do
            for slot = 1, 4 do
                local row = state.auxEditor.rows[wheel] and state.auxEditor.rows[wheel][slot] or nil
                addControllerUiItem(items, "main.aux." .. tostring(wheel) .. "." .. tostring(slot), row and row.rect)
            end
        end
    end
    if spheres ~= nil then
        addControllerUiItem(items, "main.sphere.count", spheres.countRect)
        for slot, rect in ipairs(spheres.rowRects or {}) do
            addControllerUiItem(items, "main.sphere." .. tostring(slot), rect)
        end
    end
    if bindings ~= nil then addControllerUiItem(items, "main.controls", bindings.summaryRect) end
    if shortcuts ~= nil then addControllerUiItem(items, "main.shortcuts", shortcuts.summaryRect) end
    addControllerUiItem(items, "main.instructions", state.editorInstructionsRect)
    addControllerUiItem(items, "main.save", state.editorSaveRect)
    addControllerUiItem(items, "main.close", state.editorCloseRect)
    context.saveAllowed = true
    context.saveRect = state.editorSaveRect
    context.hints.back = state.editorCloseRect
    context.hints.save = state.editorSaveRect
    return context
end

state.controllerUiRectAction = function(rect, direction)
    if type(rect) ~= "table" then return false end
    return handleEditorClick(direction or 1,
        rect.x + rect.w * 0.5, rect.y + rect.h * 0.5)
end

state.detectControllerGlyphFamily = function(pc)
    local requested = string.lower(tostring(cfg("controllerGlyphFamily", "auto")))
    if requested ~= "" and requested ~= "auto" then
        if requested:find("playstation", 1, true) or requested:find("dual", 1, true)
            or requested == "ps" or requested == "ps4" or requested == "ps5" then
            return "dualsense"
        end
        if requested:find("xbox", 1, true) or requested:find("xinput", 1, true) then
            return "xbox"
        end
    end

    local now = os.clock()
    if state.controllerGlyphFamilyCheckedAt ~= nil
        and now < state.controllerGlyphFamilyCheckedAt then
        return state.controllerGlyphFamilyDetected
    end
    state.controllerGlyphFamilyCheckedAt = now + 0.50

    local strongNames, weakNames = {}, {}
    local function asText(value)
        if value == nil then return "" end
        local text = ""
        local ok, converted = pcall(function() return value:ToString() end)
        if ok and converted ~= nil then text = tostring(converted) else text = tostring(value or "") end
        return string.lower(text)
    end
    local function remember(bucket, label, value)
        local text = asText(value)
        if text ~= "" and text ~= "none" and text ~= "<nil>" then
            bucket[#bucket + 1] = label .. "=" .. text
        end
    end
    local function readCommonInput(subsystem, label)
        if subsystem == nil then return end
        
        
        pcall(function() remember(strongNames, label .. ".GamepadInputType", subsystem.GamepadInputType) end)
        pcall(function() remember(strongNames, label .. ".GetCurrentGamepadName", subsystem:GetCurrentGamepadName()) end)
        
        pcall(function() remember(strongNames, label .. ".CurrentGamepadName", subsystem.CurrentGamepadName) end)
        pcall(function() remember(strongNames, label .. ".GamepadName", subsystem.GamepadName) end)
    end

    if alive(pc) then
        local localPlayer = nil
        pcall(function() localPlayer = pc:GetLocalPlayer() end)
        if alive(localPlayer) then
            local commonInputClass = cls("/Script/CommonInput.CommonInputSubsystem")
            if alive(commonInputClass) then
                local subsystem = nil
                pcall(function() subsystem = localPlayer:GetSubsystem(commonInputClass) end)
                if alive(subsystem) then
                    state.controllerGlyphCommonInputSubsystem = subsystem
                    readCommonInput(subsystem, "LocalPlayer.CommonInput")
                end
            end
        end
        
        
        for _, method in ipairs({ "GetCurrentGamepadName", "GetGamepadName", "GetControllerType" }) do
            pcall(function()
                local callback = pc[method]
                if type(callback) == "function" then remember(weakNames, "PC." .. method, callback(pc)) end
            end)
        end
    end

    
    
    
    if #strongNames == 0 and alive(state.controllerGlyphCommonInputSubsystem) then
        readCommonInput(state.controllerGlyphCommonInputSubsystem, "CachedCommonInput")
    end
    if #strongNames == 0 and type(FindAllOf) == "function"
        and now >= (state.controllerGlyphBroadScanNextAt or 0.0) then
        state.controllerGlyphBroadScanNextAt = now + 5.0
        pcall(function()
            local subsystems = FindAllOf("CommonInputSubsystem")
            if type(subsystems) == "table" then
                for index, subsystem in pairs(subsystems) do
                    if alive(subsystem) then
                        local full = ""
                        pcall(function() full = tostring(subsystem:GetFullName()) end)
                        if not string.lower(full):find("default__", 1, true) then
                            if not alive(state.controllerGlyphCommonInputSubsystem) then
                                state.controllerGlyphCommonInputSubsystem = subsystem
                            end
                            readCommonInput(subsystem, "FoundCommonInput[" .. tostring(index) .. "]")
                        end
                    end
                end
            end
        end)
    end

    local function classify(entries)
        local joined = table.concat(entries, " ")
        if joined:find("dualsense", 1, true) or joined:find("dualshock", 1, true)
            or joined:find("playstation", 1, true) or joined:find("sony", 1, true)
            or joined:find("ps5", 1, true) or joined:find("ps4", 1, true)
            or joined:find("gamepad_ps", 1, true) then
            return "dualsense"
        end
        if joined:find("xbox", 1, true) or joined:find("xinput", 1, true) then
            return "xbox"
        end
        return nil
    end

    
    local detected = classify(strongNames) or classify(weakNames)

    
    
    if detected == nil and type(FindAllOf) == "function"
        and state.controllerGlyphPlatformSettingsScanned ~= true then
        state.controllerGlyphPlatformSettingsScanned = true
        pcall(function()
            local settings = FindAllOf("CommonInputPlatformSettings")
            if type(settings) == "table" then
                for index, object in pairs(settings) do
                    if object ~= nil then
                        pcall(function() remember(weakNames,
                            "PlatformSettings[" .. tostring(index) .. "].DefaultGamepadName",
                            object.DefaultGamepadName) end)
                    end
                end
            end
        end)
        detected = classify(weakNames)
    end

    local signalText = table.concat(strongNames, " | ")
    if signalText == "" then signalText = table.concat(weakNames, " | ") end
    if detected ~= nil then
        if detected ~= state.controllerGlyphFamilyDetected then
            log("Controller glyph family auto-detected: " .. detected
                .. (signalText ~= "" and (" [" .. signalText .. "]") or ""), true)
        end
        state.controllerGlyphFamilyDetected = detected
        return detected
    end

    if state.controllerGlyphUnknownLogged ~= true then
        state.controllerGlyphUnknownLogged = true
        log("Controller glyph family not reported by CommonInput"
            .. (signalText ~= "" and (" [" .. signalText .. "]") or "")
            .. "; using configured fallback", true)
    end
    return state.controllerGlyphFamilyDetected
end

local function closeEditor(reason)
    if not state.editorOpen then return end
    if state.bindingEditor ~= nil then state.bindingEditor:closePanel(true) end
    if state.shortcutEditor ~= nil then state.shortcutEditor:closePanel(true) end
    if state.sphereEditor ~= nil then state.sphereEditor:closePanel() end
    state.editorOpen = false
    if state.controllerUiNavigation ~= nil then state.controllerUiNavigation:reset() end
    if state.inputRuntime ~= nil then state.inputRuntime:resetSuppression() end
    state.editorPickingSlot = nil
    closeEditorDropdowns()
    setPickerVisible(false)
    setResetConfirmVisible(false)
    if type(state.setMainEditorDiscardConfirmVisible) == "function" then
        state.setMainEditorDiscardConfirmVisible(false)
    end
    setInstructionsVisible(false)
    state.editorDraft = nil
    setVisible(state.editorPanel, false)
    setVisible(state.widget, false)
    releaseCameraLock()
    restoreGameInput()
    restoreGameplayInput()
    restoreTimeDilation()

    
    
    
    
    
    if state.inputRuntime ~= nil and type(state.applyRuntimeBindings) == "function" then
        local rebound, reboundError = state.applyRuntimeBindings(state.pc)
        if not rebound then
            log("Runtime binding refresh after editor close failed: "
                .. tostring(reboundError), true)
        end
    end

    log(reason or "Assignment editor closed")
end

state.closeEditorNow = closeEditor

local function openEditor(pc, inputSource)
    if refreshPartyCapacity ~= nil then refreshPartyCapacity(true) end
    if state.palCommandActions ~= nil then
        state.palCommandActions:refreshAvailability(FUNCTION_BY_ID)
    end
    local allowed, reason = canOpenWheelDuringGameplay(pc)
    if not allowed then
        log("Editor not opened: " .. tostring(reason), true)
        return
    end

    if not buildEditorWidget(pc) then return end

    state.pc = pc
    state.editorOpen = true
    state.snapshotMainEditorDraft()
    state.editorClicksReadyAt = os.clock() + 0.20
    state.inputModeFailureLogged = false
    state.cameraLockFailureLogged = false
    setVisible(state.wheelPanel, false)
    refreshEditorRows()
    state.updateMainEditorSaveVisual()
    if state.bindingEditor ~= nil then state.bindingEditor:updateTexts() end
    if state.shortcutEditor ~= nil then state.shortcutEditor:updateSummary() end
    if state.sphereEditor ~= nil then state.sphereEditor:update() end
    setVisible(state.editorPanel, true)
    saveCursorFlags(pc)
    setVisible(state.widget, true)
    applySlowMotion(pc)
    beginCameraLock(pc)
    blockEditorGameplayInput(pc)
    if state.inputRuntime ~= nil then
        if state.controllerUiNavigation ~= nil
            and type(state.inputRuntime.beginEditorControllerUiIsolation) == "function" then
            state.inputRuntime:beginEditorControllerUiIsolation(pc)
        else
            state.inputRuntime:beginEditorKeyboardIsolation(pc)
        end
    end
    
    
    
    if state.controllerUiNavigation ~= nil then
        state.controllerUiNavigation:reset()
        state.controllerUiNavigation:prime(pc)
        state.controllerUiNavigation:setControllerPresentation(inputSource == "controller")
        state.applyEditorControllerUiInputMode(pc, true)
    else
        applyEditorInputMode(pc, true)
    end
    centerHardwareCursor(pc)
    enforceCameraLock()
    log("Assignment editor opened with gameplay input disabled")
end

local function toggleEditor()
    if state.editorOpen then
        if state.bindingEditor ~= nil
            and state.bindingEditor:handleReservedSettingsKey() then
            return
        end
        if state.shortcutEditor ~= nil
            and state.shortcutEditor:handleReservedSettingsKey() then
            return
        end
        if state.bindingEditor ~= nil and state.bindingEditor:isOpen()
            and type(state.bindingEditor.hasUnsavedChanges) == "function"
            and state.bindingEditor:hasUnsavedChanges() then
            state.bindingEditor:requestClose()
            return
        end
        if state.shortcutEditor ~= nil and state.shortcutEditor:isOpen()
            and type(state.shortcutEditor.hasUnsavedChanges) == "function"
            and state.shortcutEditor:hasUnsavedChanges() then
            state.shortcutEditor:requestClose()
            return
        end
        if state.bindingEditor ~= nil and state.bindingEditor:isOpen() then
            state.bindingEditor:closePanel(true)
        end
        if state.shortcutEditor ~= nil and state.shortcutEditor:isOpen() then
            state.shortcutEditor:closePanel(true)
        end
        if state.mainEditorHasUnsavedChanges() then
            closeEditorDropdowns()
            closeAssignmentPicker()
            if state.sphereEditor ~= nil then state.sphereEditor:closePanel() end
            setResetConfirmVisible(false)
            setInstructionsVisible(false)
            state.setMainEditorDiscardConfirmVisible(true)
            return
        end
        closeEditor(tostring(cfg("settingsKey") or "Settings key")
            .. " closed assignment editor")
    else
        openEditor(getPlayerController())
    end
end

state.setMousePointerMode = function(active, rememberPresentation)
    active = active == true
    state.mousePointerMode = active
    if rememberPresentation ~= false then
        state.mousePresentationRemembered = active
    end
    if state.auxiliaryRuntime ~= nil
        and type(state.auxiliaryRuntime.setGlyphsVisible) == "function" then
        state.auxiliaryRuntime:setGlyphsVisible(state.mousePresentationRemembered ~= true)
    end
    setCursorFlags(state.pc, active, true)
    if active then
        state.setMousePointerGameplaySuppressed(true)
    else
        local keepSuppressed = state.inputRuntime ~= nil
            and state.inputRuntime.mouseActivationReleaseGuard == true
        if not keepSuppressed then state.setMousePointerGameplaySuppressed(false) end
        local x, y = readMousePosition(state.pc)
        state.mousePointerLastX, state.mousePointerLastY = x, y
    end
end

local function updateSelectionFromCursor(pc)
    local mouseX, mouseY = readMousePosition(pc)
    if mouseX == nil or mouseY == nil then
        if not state.mouseReadFailureLogged then
            state.mouseReadFailureLogged = true
            log("Could not read UI cursor position; mouse selection unavailable", true)
        end
        return nil
    end

    local previousX = state.mousePointerLastX
    local previousY = state.mousePointerLastY
    state.mousePointerLastX = mouseX
    state.mousePointerLastY = mouseY

    local moved = 0.0
    if previousX ~= nil and previousY ~= nil then
        local mdx, mdy = mouseX - previousX, mouseY - previousY
        moved = math.sqrt(mdx * mdx + mdy * mdy)
    end

    if moved >= 2.0 and state.mousePointerMode ~= true then
        state.setMousePointerMode(true)
        state.hybridControllerSelectionActive = false
        if state.callVisual ~= nil then
            state.callVisual("setDirection", nil, 0.0, 1.0)
        end
        log("Mouse movement detected; native cursor direct-click mode enabled")
    end

    if state.mousePointerMode ~= true then return moved end

    local centerX = tonumber(cfg("centerX", 960)) or 960
    local centerY = tonumber(cfg("centerY", 540)) or 540
    local dx = mouseX - centerX
    local dyUp = centerY - mouseY
    local radius = math.sqrt(dx * dx + dyUp * dyUp)
    local innerRadius = clamp(cfg("wheelInnerRadius", 82), 45, 180)
    local outerRadius = clamp(cfg("wheelOuterRadius", 270), innerRadius + 80, 420)
    local previous = state.selected

    state.selected = nil
    if radius >= innerRadius and radius <= outerRadius then
        local angle = math.atan(dyUp, dx)
        local visibleCount = activeVisibleSlotCount()
        if state.wheelMode ~= "main" then
            local geometry = sphereWheelGeometry(visibleCount)
            local bestVirtual = nil
            local bestDistance = math.huge
            local span = TWO_PI / geometry.virtualCount
            local slotOneAngle = math.rad(90)
            for virtualIndex = 1, geometry.virtualCount do
                local slotAngle = slotOneAngle + ((virtualIndex - 1) * span)
                local distance = angularDistance(angle, slotAngle)
                if distance < bestDistance then
                    bestDistance = distance
                    bestVirtual = virtualIndex
                end
            end
            state.selected = geometry.logicalByVirtual[bestVirtual]
        else
            local bestIndex = nil
            local bestDistance = math.huge
            for index = 1, visibleCount do
                local slotAngle = math.rad(tonumber(
                    cfg("wheelSlotOneAngleDegrees", 180)) or 180)
                    - ((index - 1) * TWO_PI / visibleCount)
                local distance = angularDistance(angle, slotAngle)
                if distance < bestDistance then
                    bestDistance = distance
                    bestIndex = index
                end
            end
            state.selected = bestIndex
        end
    end

    if state.callVisual ~= nil then
        state.callVisual("setDirection", nil, 0.0, 1.0)
    end
    if previous ~= state.selected then
        local def = state.selected ~= nil
            and assignmentDefinitionForVisibleIndex(state.selected) or nil
        previewAssignmentNatively(def, "mouse hover")
        updateHighlight()
    end
    return moved
end

local function closeWheel(reason)
    if not state.open then return end
    state.open = false
    state.openKeySawDown = false
    state.keyboardToggleOpenArmed = false
    state.keyboardToggleCloseArmed = false
    if state.haptics ~= nil then state.haptics:stop(state.pc) end
    if state.controller ~= nil then state.controller:finish(state.pc) end
    if state.inputRuntime ~= nil then state.inputRuntime:finishKeyboard(state.pc) end
    if type(state.setMousePointerMode) == "function" then
        
        
        state.setMousePointerMode(false, false)
    else
        state.mousePointerMode = false
    end
    state.selectionCommitted = false
    state.pendingMouseReleaseClose = false
    state.clickCommittedAt = 0.0
    state.pendingPalSlot = nil
    state.pendingMenuId = nil
    state.pendingUtilityId = nil
    state.pendingSphereId = nil
    state.hoverPreviewKey = nil
    state.keyboardCancelWasDown = {}
    state.keyboardMouseNeutralX = nil
    state.keyboardMouseNeutralY = nil
    state.keyboardMouseNeutralReady = false
    state.hybridControllerSelectionActive = false
    state.openInputSource = nil
    state.mousePointerMode = false
    state.mousePointerLastX = nil
    state.mousePointerLastY = nil
    setVisible(state.wheelPanel, false)
    if state.auxiliaryRuntime ~= nil then state.auxiliaryRuntime:setVisible(false) end
    setVisible(state.widget, false)
    if state.callVisual ~= nil then
        state.callVisual("setDirection", nil, 0.0, 1.0)
    end
    releaseCameraLock()
    restoreGameInput()
    restoreGameplayInput()
    restoreTimeDilation()
    log(reason or "Wheel hidden")
end

local SPHERE_LAUNCHER_ITEM_IDS = {
    spherelauncheronce = true,
    spherelauncher = true,
    homingspherelauncher = true,
}

local function currentHeldWeaponStaticId(pc)
    
    
    
    local player = getLocalPlayerCharacter()
    if not alive(player) and alive(pc) then
        pcall(function() player = pc.Pawn end)
    end
    if not alive(player) then return "", "" end

    local shooter = nil
    pcall(function() shooter = player.ShooterComponent end)
    if not alive(shooter) then return "", "" end

    local weapon = nil
    local okWeapon = pcall(function() weapon = shooter:GetHasWeapon() end)
    if not okWeapon or not alive(weapon) then return "", "" end

    local itemId = nil
    local okItem = pcall(function() itemId = weapon:GetItemId() end)
    if not okItem or itemId == nil then return "", "" end

    local staticId = nil
    pcall(function() staticId = itemId.StaticId end)
    if staticId == nil then return "", "" end

    return valueString(staticId), normalizedName(staticId)
end

state.isSphereLauncherEquipped = function(pc)
    local rawId, normalizedId = currentHeldWeaponStaticId(pc)
    return SPHERE_LAUNCHER_ITEM_IDS[normalizedId] == true, rawId
end

state.isSphereLauncherChordHeld = function(pc, inputSource)
    local button = inputSource == "controller"
        and cfg("controllerSphereLauncherAimButton", "Gamepad_LeftTrigger")
        or cfg("keyboardSphereLauncherAimButton", "RightMouseButton")
    local translate = cfg("unrealFKeyName", nil)
    if inputSource == "keyboard" and type(translate) == "function" then
        button = translate(button)
    end
    return state.isInputActive(pc, makeFKey(button))
end

state.requestedWheelMode = function(pc, inputSource)
    if state.isSphereLauncherChordHeld(pc, inputSource) then
        local isLauncher, weaponId = state.isSphereLauncherEquipped(pc)
        if isLauncher then
            log("Sphere Launcher detected: " .. tostring(weaponId))
            return "sphere_launcher"
        end
        log("Launcher aim chord ignored for held weapon: "
            .. (weaponId ~= "" and tostring(weaponId) or "<unavailable>"), true)
    end
    local button = inputSource == "controller"
        and cfg("controllerSphereThrowButton", "Gamepad_RightShoulder")
        or cfg("keyboardSphereThrowButton", "Q")
    local translate = cfg("unrealFKeyName", nil)
    if inputSource == "keyboard" and type(translate) == "function" then
        button = translate(button)
    end
    if state.isInputActive(pc, makeFKey(button)) then return "sphere_throw" end
    return "main"
end

local function openWheel(pc, inputSource)
    if state.editorOpen then return false end
    if refreshPartyCapacity ~= nil then refreshPartyCapacity(true) end
    local allowed, reason = canOpenWheelDuringGameplay(pc)
    if not allowed then
        log("Wheel not opened: " .. tostring(reason), true)
        return false
    end

    if state.palCommandActions ~= nil then
        state.palCommandActions:refreshAvailability(FUNCTION_BY_ID)
    end

    local requestedMode = state.requestedWheelMode(pc, inputSource)
    if state.iconRuntime ~= nil then
        local okPrepare, iconChanged = pcall(function()
            return state.iconRuntime:prepare(pc, requestedMode,
                config.sphereWheelRuntime.definitions, getLocalPlayerCharacter())
        end)
        if not okPrepare then
            log("Runtime icon preparation failed: " .. tostring(iconChanged), true)
        elseif iconChanged == true then
            state.invalidateWheelMode(requestedMode)
        end
    end

    local requestedPage = requestedMode == "main"
        and math.floor(clamp(state.mainActivePage or 1, 1, state.activeWheelCount)) or 1
    local requestedCacheKey = state.wheelModeCacheKey(requestedMode, requestedPage)
    local currentCacheKey = state.wheelModeCacheKey(state.wheelMode, state.activePage)
    if requestedCacheKey ~= currentCacheKey then
        if state.wheelMode == "main" then state.mainActivePage = state.activePage end
        state.stashWheelPanel()
        state.wheelMode = requestedMode
        state.activePage = requestedPage
        state.restoreWheelPanel(requestedMode, requestedPage)
    else
        state.wheelMode = requestedMode
        if alive(state.wheelPanel) then state.builtWheelMode = requestedMode end
    end

    if not alive(state.widget) or not alive(state.wheelPanel) then
        if not buildWidget(pc) then return false end
    end

    state.pc = pc
    state.open = true
    state.openInputSource = inputSource
    
    
    
    state.mousePointerMode = false
    state.mousePointerLastX = nil
    state.mousePointerLastY = nil
    state.selected = nil
    state.lastActivated = nil
    local toggleBehavior = string.lower(tostring(cfg("openWheelBehavior", "hold")))
        == "toggle"
    state.openKeySawDown = inputSource ~= "controller" and not toggleBehavior
    if inputSource ~= "controller" then
        state.keyboardOpenWasDown = isKeyDown(pc, state.openFKey)
        state.keyboardToggleOpenArmed = false
        state.keyboardToggleCloseArmed = false
    end
    state.openedAt = os.clock()
    state.selectionCommitted = false
    state.pendingMouseReleaseClose = false
    state.clickCommittedAt = 0.0
    state.pendingPalSlot = nil
    state.pendingMenuId = nil
    state.pendingUtilityId = nil
    state.pendingSphereId = nil
    state.hoverPreviewKey = nil
    state.inputModeFailureLogged = false
    state.mouseReadFailureLogged = false
    state.cameraLockFailureLogged = false
    state.aimSuppressionFailureLogged = false
    state.keyboardMouseNeutralX = nil
    state.keyboardMouseNeutralY = nil
    state.keyboardMouseNeutralReady = false
    state.hybridControllerSelectionActive = false

    state.activePalSlot = readSelectedPartyPalSlot() or state.activePalSlot
    if state.wheelMode == "main" then
        local _, _, _, mercyScanError = state.mercyAccessory:refresh()
        if mercyScanError ~= nil then
            log("Mercy status scan warning: " .. tostring(mercyScanError), true)
        end
        if state.auxiliaryRuntime ~= nil
            and type(state.auxiliaryRuntime.refreshMercyStatus) == "function" then
            state.auxiliaryRuntime:refreshMercyStatus(state.mercyAccessoryEquipped == true)
        end
    end

    saveCursorFlags(pc)
    updateHighlight()
    setVisible(state.editorPanel, false)
    setVisible(state.wheelPanel, true)
    setVisible(state.widget, true)
    refreshZoomHelp(true)
    if state.auxiliaryRuntime ~= nil then
        local showAux = state.wheelMode == "main"
        state.auxiliaryRuntime:setVisible(showAux)
        if type(state.auxiliaryRuntime.setGlyphsVisible) == "function" then
            state.auxiliaryRuntime:setGlyphsVisible(state.mousePresentationRemembered ~= true)
        end
        if showAux and type(state.auxiliaryRuntime.begin) == "function" then
            state.auxiliaryRuntime:begin()
        end
    end
    if state.callVisual ~= nil then
        state.callVisual("begin", state.wheelPanel, state.sectors, state.activePage)
    end
    applySlowMotion(pc)
    beginCameraLock(pc)
    blockGameplayInput(pc)
    if inputSource == "controller" then
        state.keyboardCancelWasDown = {}
        state.controller:begin(pc)
    else
        applyUIOnlyInput(pc, true)
        state.controller:finish(pc)
        if type(state.controller.primeDirectInputLatches) == "function" then
            state.controller:primeDirectInputLatches(pc)
        end
        refreshMovementKeysAllowedWhileOpen(pc)
        state.inputRuntime:beginKeyboard(pc)
        state.keyboardCancelWasDown = {}
        for _, input in ipairs(state.keyboardCancelInputs or {}) do
            state.keyboardCancelWasDown[input.name] = isKeyDown(pc, input.key)
        end
        local initialMouseX, initialMouseY = readMousePosition(pc)
        state.mousePointerLastX = initialMouseX
        state.mousePointerLastY = initialMouseY
        setCursorFlags(pc, false, true)
    end
    enforcePageAimSuppression()
    enforceCameraLock()
    if state.wheelMode ~= "main" then
        local geometry = sphereWheelGeometry(activeVisibleSlotCount())
        log("Dynamic sphere wheel shown with " .. tostring(activeVisibleSlotCount())
            .. " spheres on " .. tostring(geometry.virtualCount)
            .. "-position geometry (2-slot capture-rate gap) via "
            .. (inputSource == "controller" and "controller" or "keyboard"), true)
    else
        log("Dynamic main wheel shown with " .. tostring(activeVisibleSlotCount())
            .. " sectors via "
            .. (inputSource == "controller" and "controller" or "keyboard"), true)
    end
    return true
end

state.activateDefinition = function(def, trigger, selectedMarker)
    if not state.open or state.selectionCommitted then return false end
    if def == nil or def.kind == "empty" then
        log(tostring(trigger) .. " selected an empty slot", true)
        return false
    end

    state.selectionCommitted = true
    state.lastActivated = selectedMarker
    if selectedMarker ~= nil then updateHighlight() end

    if def.kind == "weapon" then
        local alreadyPreviewed = state.hoverPreviewKey
            == ("weapon:" .. tostring(def.index))
        if not alreadyPreviewed and not equipWeaponSlot(def.index) then
            state.selectionCommitted = false
            return false
        end
        closeWheel("Weapon assignment activated")
        return true
    end

    if def.kind == "pal" then
        closeWheel("Pal assignment selected; wheel closed before summon")
        summonPalSlotNearPlayer(def.index)
        return true
    end

    if def.kind == "utility" then
        closeWheel("Utility assignment selected")
        if def.id == "mercy" then state.mercyAccessory:toggle() end
        return true
    end

    if def.kind == "menu" then
        closeWheel("Menu assignment selected")
        if def.available == false or def.pending == true then
            if type(state.showCenterNotification) == "function" then
                state.showCenterNotification(T("actionUnavailable", { action = def.label }))
            end
            log("Pending menu assignment not executed: " .. tostring(def.id), true)
            return true
        end
        scheduleAssignedMenu(def.id)
        return true
    end

    if def.kind == "palworldaction" then
        if state.palCommandActions ~= nil then
            state.palCommandActions:refreshAvailability(FUNCTION_BY_ID)
        end
        if def.available == false then
            state.selectionCommitted = false
            state.lastActivated = nil
            updateHighlight()
            if type(state.showCenterNotification) == "function" then
                state.showCenterNotification(T("requiresSummonedPal", { action = def.label }))
            end
            log(tostring(trigger) .. " ignored: " .. tostring(def.label)
                .. " requires a summoned Pal", true)
            return false
        end
        closeWheel("Palworld action selected")
        local okAction, actionError = false, "Pal command action module unavailable"
        if state.palCommandActions ~= nil then
            okAction, actionError = state.palCommandActions:execute(def)
        end
        if not okAction then
            if type(state.showCenterNotification) == "function" then
                state.showCenterNotification(T("actionFailed", { action = def.label }))
            end
            log("Palworld action failed: " .. tostring(def.id) .. " -> "
                .. tostring(actionError), true)
        end
        return true
    end

    if def.kind == "shortcut" then
        if def.active == false then
            closeWheel("Inactive shortcut assignment selected")
            log("Inactive shortcut not executed: " .. tostring(def.id)
                .. " -> " .. tostring(def.label), true)
            return true
        end
        closeWheel("Shortcut assignment selected")
        scheduleAssignedMenu(def.id)
        return true
    end

    if def.kind == "sphere" then
        local verifiedSelected = type(state.sphereSelected) == "function"
            and state.sphereSelected(def) == true
        closeWheel("Sphere assignment selected")
        if not verifiedSelected then
            state.selectSphere(def, { source = "activation verification", notifyMissing = true })
        end
        return true
    end

    if def.kind == "emote" then
        closeWheel("Emote assignment selected")
        return playEmoteIndex(def.emoteIndex)
    end

    state.selectionCommitted = false
    return false
end

local function activateSelectedOption(trigger)
    if not state.open or state.selectionCommitted then return false end

    local selected = state.selected
    if selected == nil then
        local reason = state.wheelMode ~= "main"
            and "pointer is inside the centre deadzone or reserved capture-rate gap"
            or "pointer is inside the centre deadzone"
        log(tostring(trigger) .. " ignored: " .. reason, true)
        return false
    end

    return state.activateDefinition(assignmentDefinitionForVisibleIndex(selected), trigger, selected)
end

state.activateAuxShortcut = function(auxWheel, auxSlot, buttonName, triggerPrefix)
    if not state.open or state.wheelMode ~= "main" then return false end
    auxWheel = math.floor(tonumber(auxWheel) or 0)
    auxSlot = math.floor(tonumber(auxSlot) or 0)
    if auxWheel < 1 or auxWheel > 2 or auxSlot < 1 or auxSlot > 4 then return false end
    local id = state.auxAssignments[auxWheel] and state.auxAssignments[auxWheel][auxSlot] or "empty"
    local def = FUNCTION_BY_ID[id] or FUNCTION_BY_ID.empty
    local trigger = tostring(triggerPrefix or "Direct AUX shortcut")
        .. (buttonName ~= nil and (" " .. tostring(buttonName)) or "")
    if def == nil or def.kind == "empty" then
        log(trigger .. " points to an empty AUX slot", true)
        return true
    end
    return state.activateDefinition(def, trigger,
        "aux" .. tostring(auxWheel) .. ":" .. tostring(auxSlot))
end

state.haptics = require("controller_haptics").new({
    cfg = cfg,
    alive = alive,
    clamp = clamp,
    log = log,
    effectiveTimeDilation = function()
        if state.slowMotionApplied then
            return clamp(cfg("wheelTimeDilation", 0.08), 0.01, 1.0)
        end
        return 1.0
    end,
})

state.controller = require("controller").new({
    cfg = cfg,
    state = state,
    alive = alive,
    makeFKey = makeFKey,
    isKeyDown = isKeyDown,
    clamp = clamp,
    angularDistance = angularDistance,
    visibleSlotCount = activeVisibleSlotCount,
    selectionIndexForAngle = function(angle, visibleCount)
        visibleCount = math.floor(clamp(tonumber(visibleCount) or 12, 4, 12))
        if state.wheelMode ~= "main" then
            local geometry = sphereWheelGeometry(visibleCount)
            local span = TWO_PI / geometry.virtualCount
            local slotOneAngle = math.rad(90)
            local bestVirtual = nil
            local bestDistance = math.huge
            for virtualIndex = 1, geometry.virtualCount do
                local slotAngle = slotOneAngle + ((virtualIndex - 1) * span)
                local distance = angularDistance(angle, slotAngle)
                if distance < bestDistance then
                    bestDistance = distance
                    bestVirtual = virtualIndex
                end
            end
            return geometry.logicalByVirtual[bestVirtual]
        end

        local bestIndex = nil
        local bestDistance = math.huge
        for index = 1, visibleCount do
            local slotAngle = math.rad(tonumber(
                cfg("wheelSlotOneAngleDegrees", 180)) or 180)
                - ((index - 1) * TWO_PI / visibleCount)
            local distance = angularDistance(angle, slotAngle)
            if distance < bestDistance then
                bestDistance = distance
                bestIndex = index
            end
        end
        return bestIndex
    end,
    assignmentDefinitionForVisibleIndex = assignmentDefinitionForVisibleIndex,
    previewAssignmentNatively = previewAssignmentNatively,
    shouldPulseHighlight = function(def)
        return state.wheelMode == "main" or def == nil
            or def.kind ~= "sphere" or state.sphereAvailable(def)
    end,
    pulseHighlight = function(pc, slot)
        return state.haptics:pulse(pc, slot)
    end,
    updateHighlight = updateHighlight,
    updatePointerDirection = function(angle, magnitude, deadzone)
        if state.callVisual ~= nil then
            state.callVisual("setDirection", angle, magnitude, deadzone)
        end
    end,
    switchActivePage = switchActivePage,
    canSwitchPage = function() return state.wheelMode == "main" end,
    canOpenPalWheelMenu = function() return state.wheelMode == "main" end,
    isReservedCancelInput = function(name)
        if cfg("controllerZoomEnabled", true) ~= true
            or not state.open or state.wheelMode ~= "main"
            or state.openInputSource ~= "controller" then return false end
        name = tostring(name or "")
        return name == "Gamepad_LeftTrigger" or name == "Gamepad_RightTrigger"
    end,
    setWheelInputSuppressed = state.setControllerWheelInputSuppressed,
    activateSelectedOption = activateSelectedOption,
    directShortcutButtons = state.auxiliaryRuntime ~= nil
        and state.auxiliaryRuntime:directButtons() or {},
    activateDirectShortcut = function(auxWheel, auxSlot, buttonName)
        return state.activateAuxShortcut(auxWheel, auxSlot, buttonName, "Direct AUX shortcut")
    end,
    isMousePointerMode = function() return state.mousePointerMode == true end,
    isMousePresentationRemembered = function()
        return state.mousePresentationRemembered == true
    end,
    setMousePointerMode = state.setMousePointerMode,
    updateMousePointerSelection = updateSelectionFromCursor,
    openPalWheelMenuFromWheel = function(pc, buttonName)
        if not state.open or state.openInputSource ~= "controller"
            or state.wheelMode ~= "main" then return false end
        closeWheel(tostring(buttonName or cfg("controllerPalWheelMenuButton", "Gamepad_RightThumbstick"))
            .. " opened the PalWheel Menu")
        openEditor(pc, "controller")
        return state.editorOpen == true
    end,
    closeWheel = closeWheel,
    log = log,
    twoPi = TWO_PI,
    isWheelOpen = function() return state.open end,
    isEditorOpen = function() return state.editorOpen end,
    openControllerWheel = function(pc) return openWheel(pc, "controller") end,
})

do
    local okNavigation, navigationModule = pcall(require, "controller_ui_navigation")
    if okNavigation and type(navigationModule) == "table"
        and type(navigationModule.new) == "function" then
        local okNew, navigation = pcall(navigationModule.new, {
            state = state,
            cfg = cfg,
            alive = alive,
            makeFKey = makeFKey,
            isKeyDown = isKeyDown,
            construct = construct,
            addToCanvas = addToCanvas,
            place = place,
            setVisible = setVisible,
            setBorderColor = setBorderColor,
            createIcon = createCachedIcon,
            hitTestInvisible = VIS_HIT_TEST_INVISIBLE,
            root = function() return state.editorPanel end,
            readMousePosition = readMousePosition,
            context = state.controllerUiContext,
            detectGlyphFamily = state.detectControllerGlyphFamily,
            glyphTextureForKey = function(key, family)
                return state.glyphRuntime ~= nil
                    and state.glyphRuntime:textureForKey(key, family) or nil
            end,
            presentationChanged = function(controllerActive)
                state.mousePresentationRemembered = controllerActive ~= true
                if state.editorOpen and alive(state.pc) then
                    setCursorFlags(state.pc, controllerActive ~= true, true)
                end
                if state.auxiliaryRuntime ~= nil
                    and type(state.auxiliaryRuntime.setGlyphsVisible) == "function" then
                    state.auxiliaryRuntime:setGlyphsVisible(controllerActive == true)
                end
            end,
            dispatchConfirm = function(item)
                return state.controllerUiRectAction(item and item.rect, 1)
            end,
            dispatchBack = function()
                return handleEditorClick(-1, 0, 0)
            end,
            dispatchSave = function(context)
                return state.controllerUiRectAction(context and context.saveRect, 1)
            end,
            log = log,
        })
        if okNew and type(navigation) == "table" then
            state.controllerUiNavigation = navigation
            log("Shared controller UI navigation layer loaded")
        else
            log("Controller UI navigation layer could not initialize: "
                .. tostring(navigation), true)
        end
    else
        log("Controller UI navigation unavailable: " .. tostring(navigationModule), true)
    end
end

_G.PalWheelControllerCaptureInput = function(pc)
    return state.controller:captureOpen(pc)
end

local InputRuntime = require("input_runtime")
state.inputRuntime = InputRuntime.new({
    cfg = cfg, state = state, clamp = clamp, alive = alive,
    getPlayerController = getPlayerController, makeFKey = makeFKey,
    isKeyDown = isKeyDown, openWheel = openWheel, closeWheel = closeWheel,
    activateSelectedOption = activateSelectedOption,
    flushPressedKeys = flushPressedKeys, toggleEditor = toggleEditor,
    handleEditorClick = handleEditorClick,
    handleWheelPointerClick = function()
        if not state.open then return false end
        if state.mousePointerMode ~= true then
            state.setMousePointerMode(true)
            state.hybridControllerSelectionActive = false
            if state.callVisual ~= nil then state.callVisual("setDirection", nil, 0.0, 1.0) end
            log("Mouse click detected; native cursor direct-click mode enabled")
        end
        updateSelectionFromCursor(state.pc)
        if state.wheelMode == "main" and state.auxiliaryRuntime ~= nil
            and type(state.auxiliaryRuntime.slotAt) == "function" then
            local mouseX, mouseY = readMousePosition(state.pc)
            local auxWheel, auxSlot, auxKey = state.auxiliaryRuntime:slotAt(mouseX, mouseY)
            if auxWheel ~= nil then
                if state.inputRuntime ~= nil
                    and type(state.inputRuntime.armMouseActivationReleaseGuard) == "function" then
                    state.inputRuntime:armMouseActivationReleaseGuard(state.pc)
                end
                return state.activateAuxShortcut(auxWheel, auxSlot, auxKey, "Mouse AUX click")
            end
        end
        if state.selected == nil then
            log("Mouse click outside a wheel slot ignored", true)
            return false
        end
        if state.inputRuntime ~= nil
            and type(state.inputRuntime.armMouseActivationReleaseGuard) == "function" then
            state.inputRuntime:armMouseActivationReleaseGuard(state.pc)
        end
        return activateSelectedOption("Mouse slot click")
    end,
    pollHybridDirectShortcut = function(pc)
        if not state.open or state.wheelMode ~= "main" or state.controller == nil then return false end
        local input = state.controller:newDirectInputPressed(pc)
        if input == nil then return false end
        state.setMousePointerMode(false)
        return state.activateAuxShortcut(input.auxWheel, input.auxSlot, input.name,
            "Hybrid controller AUX shortcut")
    end,
    setMousePointerMode = state.setMousePointerMode,
    isMousePresentationRemembered = function()
        return state.mousePresentationRemembered == true
    end,
    setMouseGameplaySuppressed = function(active)
        return state.setMousePointerGameplaySuppressed(active)
    end,
    enforcePageAimSuppression = enforcePageAimSuppression,
    switchActivePage = switchActivePage,
    visibleSlotCount = activeVisibleSlotCount,
    updateSelectionFromCursor = updateSelectionFromCursor,
    controllerSelectionMagnitude = function(pc)
        if state.controller == nil then return nil end
        return state.controller:selectionMagnitude(pc)
    end,
    updateSelectionFromController = function(pc)
        if state.controller == nil then return nil end
        return state.controller:updateSelection(pc)
    end,
    controllerShouldActivateOnStickReturn = function(magnitude)
        if state.controller == nil then return false end
        return state.controller:shouldActivateOnStickReturn(magnitude)
    end,
    destroyWidget = destroyWidget,
    destroyCenterNotification = destroyCenterNotification,
    log = log,
})
state.openFKey = nil

function state.applyRuntimeBindings(pc)
    if not alive(pc) then pc = getPlayerController() end
    local runtimeOk, runtimeError = state.inputRuntime:applyBindings(pc)
    if not runtimeOk then return false, runtimeError end
    if state.controller ~= nil and not state.controller:rebind(pc) then
        return false, "Controller bindings are empty"
    end
    if state.bindingEditor ~= nil then state.bindingEditor:updateTexts() end
    if state.shortcutEditor ~= nil then state.shortcutEditor:updateSummary() end
    return true
end

function state.snapshotShortcutState()
    local snapshot = {
        shortcutData = shortcutData,
        assignments = {},
        auxAssignments = { {}, {} },
    }
    for index = 1, TOTAL_ASSIGNMENT_SLOTS do
        snapshot.assignments[index] = state.assignments[index]
    end
    for wheel = 1, 2 do
        for slot = 1, 4 do
            snapshot.auxAssignments[wheel][slot] = state.auxAssignments[wheel][slot]
        end
    end
    return snapshot
end

function state.restoreShortcutState(snapshot)
    shortcutData = snapshot.shortcutData
    for index = 1, TOTAL_ASSIGNMENT_SLOTS do
        state.assignments[index] = snapshot.assignments[index]
    end
    for wheel = 1, 2 do
        for slot = 1, 4 do
            state.auxAssignments[wheel][slot] = snapshot.auxAssignments[wheel][slot]
        end
    end
    rebuildFunctionCatalog(shortcutData, state.partyCatalogCapacity)
    refreshEditorRows()
    if state.auxEditor ~= nil then state.auxEditor:updateRows() end
    invalidateWheelPanel()
    updateShortcutPickerPage()
    if state.shortcutEditor ~= nil then state.shortcutEditor:updateSummary() end
end

function state.applyShortcutDraft(rows, expectedText)
    if type(ShortcutActions) ~= "table"
        or type(ShortcutActions.saveRows) ~= "function" then
        return false, nil, "shortcut_actions.lua cannot save mappings"
    end
    local previousText, readError = ShortcutActions.readSourceText(SHORTCUTS_PATH)
    if previousText == nil then return false, nil, tostring(readError) end
    local previous = state.snapshotShortcutState()
    local data, saveError, changed, errors, warnings = ShortcutActions.saveRows(
        SHORTCUTS_PATH, rows, {
            expectedText = expectedText,
            reservedIds = SHORTCUT_RESERVED_IDS,
            controlKeys = { cfg("openKey"), cfg("keyboardNextWheelButton"),
                cfg("settingsKey") },
            lastGoodPath = SHORTCUTS_PATH .. ".lastgood",
        })
    if data == nil then
        local detail = saveError
        if errors ~= nil and errors[1] ~= nil then
            detail = "Line " .. tostring(errors[1].line or "?") .. ": "
                .. tostring(errors[1].message or saveError)
        end
        return false, nil, detail, warnings
    end
    local oldIds, newIds, renames = {}, {}, {}
    for _, def in ipairs((shortcutData and shortcutData.definitions) or {}) do
        oldIds[def.id] = true
    end
    for _, def in ipairs(data.definitions or {}) do newIds[def.id] = true end
    for _, row in ipairs(data.rows or {}) do
        local original = tostring(row.originalId or "")
        if original ~= "" and original ~= row.id then renames[original] = row.id end
    end
    for slotIndex = 1, TOTAL_ASSIGNMENT_SLOTS do
        local id = state.assignments[slotIndex]
        if renames[id] ~= nil then state.assignments[slotIndex] = renames[id]
        elseif oldIds[id] and not newIds[id] then state.assignments[slotIndex] = "empty" end
    end
    for auxWheel = 1, 2 do
        for auxSlot = 1, 4 do
            local id = state.auxAssignments[auxWheel][auxSlot]
            if renames[id] ~= nil then state.auxAssignments[auxWheel][auxSlot] = renames[id]
            elseif oldIds[id] and not newIds[id] then state.auxAssignments[auxWheel][auxSlot] = "empty" end
        end
    end
    shortcutData = data
    rebuildFunctionCatalog(shortcutData, state.partyCatalogCapacity)
    refreshEditorRows()
    if state.auxEditor ~= nil then state.auxEditor:updateRows() end
    invalidateWheelPanel()
    updateShortcutPickerPage()
    if not saveSettings() then
        state.restoreShortcutState(previous)
        local restored, restoreError = ShortcutActions.restoreText(
            SHORTCUTS_PATH, previousText, data.sourceText,
            SHORTCUTS_PATH .. ".lastgood")
        local detail = "settings.lua could not be saved; shortcut changes were rolled back"
        if not restored then
            detail = detail .. ", but shortcuts.tsv rollback failed: "
                .. tostring(restoreError)
        elseif restoreError ~= nil then
            detail = detail .. " (" .. tostring(restoreError) .. ")"
        end
        log(detail, true)
        return false, nil, detail, warnings
    end
    log("PalWheel Menu shortcut draft validated"
        .. (changed == true and ", saved, and applied" or " and reapplied"), true)
    return true, data, nil, warnings
end

function state.tick()
    processCenterNotification()

    
    
    
    if state.inputRuntime ~= nil then state.inputRuntime:drainPointerEvents() end

    if state.sphereFollowTarget ~= nil then state.sphereFollowTarget:tick() end

    if state.open and state.callVisual ~= nil then state.callVisual("tick") end
    if state.open and state.auxiliaryRuntime ~= nil
        and type(state.auxiliaryRuntime.tick) == "function" then
        state.auxiliaryRuntime:tick()
    end

    if state.editorOpen then
        local pc = state.pc
        if not alive(pc) then
            pc = getPlayerController()
            state.pc = pc
        end
        if not alive(pc) then
            closeEditor("Controller lost; editor closed")
            return
        end
        if state.editorKeyboard ~= nil then
            state.editorKeyboard:drain(state.handleEditorKeyboardEvent)
        end
        if refreshGameUiState(pc, false) then
            closeEditor("Palworld screen opened; editor closed")
            return
        end
        if state.editorBuilder ~= nil then
            state.editorBuilder:step(cfg("editorBuildUnitsPerTick", 2))
        end
        if state.controllerUiNavigation ~= nil and state.editorBuilder ~= nil
            and state.editorBuilder.complete == true then
            state.controllerUiNavigation:tick(pc)
            if not state.editorOpen then return end
        end
        if state.bindingEditor ~= nil and state.bindingEditor:isOpen() then
            state.bindingEditor:tick(pc)
        end
        if state.shortcutEditor ~= nil and state.shortcutEditor:isOpen() then
            state.shortcutEditor:tick(pc)
        end
        
        
        
        
        
        if state.bindingEditor ~= nil and state.bindingEditor:isCapturing() then
            if state.editorCaptureDevice == "controller" then
                applyEditorCaptureInputMode(pc, false)
            else
                applyEditorInputMode(pc, false)
            end
        else
            if state.controllerUiNavigation ~= nil then
                state.applyEditorControllerUiInputMode(pc, false)
            else
                applyEditorInputMode(pc, false)
            end
        end
        return
    end

    if not state.open then
        processDeferredMenuActions()
        if not alive(state.idlePc) then
            state.idlePc = getPlayerController()
        end
        if alive(state.idlePc) then
            if os.clock() >= (state.playerCacheNextPoll or 0.0) then
                state.playerCacheNextPoll = os.clock() + 1.0
                getLocalPlayerCharacter()
            end
            if refreshPartyCapacity ~= nil then refreshPartyCapacity(false) end
            state.inputRuntime:updateReleaseGuard(state.idlePc)
            local keyboardDown = isKeyDown(state.idlePc, state.openFKey)
            local keyboardWasDown = state.keyboardOpenWasDown == true
            local keyboardPressed = keyboardDown and not keyboardWasDown
            local keyboardReleased = keyboardWasDown and not keyboardDown
            state.keyboardOpenWasDown = keyboardDown
            local toggleBehavior = string.lower(tostring(
                cfg("openWheelBehavior", "hold"))) == "toggle"
            if toggleBehavior then
                if keyboardPressed then
                    state.keyboardToggleOpenArmed = true
                elseif keyboardReleased and state.keyboardToggleOpenArmed
                    and os.clock() >= state.keyboardOpenHandledAt then
                    state.keyboardToggleOpenArmed = false
                    state.keyboardOpenHandledAt = os.clock() + 0.12
                    state.ignoreOpenBindUntil = state.keyboardOpenHandledAt
                    if openWheel(state.idlePc, "keyboard") then return end
                end
            elseif keyboardPressed and os.clock() >= state.keyboardOpenHandledAt then
                state.keyboardToggleOpenArmed = false
                state.keyboardOpenHandledAt = os.clock() + 0.12
                state.ignoreOpenBindUntil = state.keyboardOpenHandledAt
                if openWheel(state.idlePc, "keyboard") then return end
            end
            if state.controller:captureOpen(state.idlePc) then return end
            if os.clock() >= state.uiStackNextPoll then
                refreshGameUiState(state.idlePc, false)
            end

            if state.sessionReady == true and state.uiStackOpen ~= true
                and os.clock() >= (state.uiPrebuildReadyAt or 0.0) then
                if not alive(state.wheelPanel) then buildWidget(state.idlePc) end
                if alive(state.wheelPanel) and state.wheelMode == "main" then
                    state.prewarmNextMainGeometry(state.idlePc)
                end
                if alive(state.wheelPanel) and not alive(state.editorPanel) then
                    buildEditorWidget(state.idlePc)
                end
                if state.editorBuilder ~= nil then
                    state.editorBuilder:step(cfg("editorBuildUnitsPerTick", 2))
                end
            end
        end
        return
    end

    local pc = state.pc
    if not alive(pc) then
        pc = getPlayerController()
        state.pc = pc
    end

    if not alive(pc) then
        closeWheel("Controller lost; wheel closed")
        return
    end

    if refreshGameUiState(pc, false) then
        closeWheel("Palworld screen opened; wheel closed without selection")
        return
    end

    if state.selectionCommitted then return end

    if state.controller:isSession() then
        state.controller:tickOpen(pc)
        return
    end

    applyUIOnlyInput(pc, false)
    state.inputRuntime:pollKeyboardWheel(pc)
end

if cfg("enabled", true) ~= true then
    log("Disabled in config.lua", true)
    return
end

if not state.inputRuntime:register() then return end

state.inputRuntime:registerRestartHook()

if state.cameraZoom:startRealtimeLoop() then
    log("Camera zoom uses retained once-per-frame game-thread sampler")
else
    log("Camera zoom frame sampler unavailable; using normal fast-loop fallback", true)
end

state.interval = math.floor(clamp(cfg("pollIntervalMs", 40), 25, 150))
state.cameraLockInterval = math.floor(clamp(cfg("cameraLockIntervalMs", 16), 12, 50))
function state.fastTick()
    processSphereSelectionQueue()
    if state.cameraZoom ~= nil then
        if state.cameraZoom:isRealtimeLoopStarted() ~= true then
            state.cameraZoom:tick(alive(state.pc) and state.pc or state.idlePc,
                state.open and state.wheelMode == "main"
                    and state.openInputSource == "controller")
        end
        if alive(state.zoomHelpPercent) then
            setText(state.zoomHelpPercent, zoomPercentText())
        end
    end
    enforcePageAimSuppression()
    state.controller:updateReleaseGuards(state.pc)
    if not state.open and not state.editorOpen
        and not state.controller:isCameraNeutralGuardActive()
        and (state.lockedRotation ~= nil
            or state.sphereFollowLookIsolationApplied == true) then
        releaseCameraLock()
    end
    enforceCameraLock()
end

function state.fastCameraTick()
    state.controllerMovementBridge.forward()

    if state.open
        and state.controller:isSession()
        and state.slowMotionApplied ~= true then
        enforceCameraLock()
    end
end

function state.startRuntimeLoops()
    local okRuntime, RuntimeLoops = pcall(require, "runtime_loops")
    if not okRuntime or type(RuntimeLoops) ~= "table"
        or type(RuntimeLoops.new) ~= "function" then
        log("FATAL: runtime_loops.lua could not be loaded: "
            .. tostring(RuntimeLoops), true)
        return false
    end

    state.runtimeLoops = RuntimeLoops.new({
        selectionTick = state.tick,
        fastTick = state.fastTick,
        fastCameraTick = state.fastCameraTick,
        executeInGameThread = ExecuteInGameThread,
        log = log,
        fastFailureWasLogged = function()
            return state.cameraLockFailureLogged == true
        end,
        markFastFailureLogged = function()
            state.cameraLockFailureLogged = true
        end,
    })
    local loopMode, loopError = state.runtimeLoops:start(
        state.interval, state.cameraLockInterval, 4)
    if loopMode == nil then
        log("FATAL: PalWheel runtime loops did not start: "
            .. tostring(loopError), true)
        return false
    end
    state.runtimeLoopMode = loopMode
    log("Recurring callbacks retained by runtime_loops.lua ("
        .. tostring(loopMode) .. ")", true)
    return true
end

if not state.startRuntimeLoops() then return end

ensureUiFallbackBaseline()
log("Localization culture=" .. tostring(config.localization.culture and config.localization.culture() or "")
    .. "; language=" .. tostring(config.localization.language and config.localization.language() or "en")
    .. "; method=" .. tostring(config.localization.detectionMethod
        and config.localization.detectionMethod() or "fallback"), true)
local startupOpenBehavior = tostring(cfg("openWheelBehavior", "hold")) == "toggle"
    and "Toggle" or "Hold"
log("v" .. tostring(cfg("version", "1.0"))
    .. " text wheel loaded. Open Wheel behavior=" .. startupOpenBehavior
    .. "; keyboard/mouse=" .. state.openKeyName
    .. "; controller=" .. tostring(cfg("controllerOpenButton") or "")
    .. "; controller-opened Main Wheel shows independent D-pad/face AUX direct slots; "
    .. "keyboard-opened wheels hide auxiliaries and keep the native cursor hidden until mouse movement; "
    .. "mouse hover selects only inside the actual wheel annulus and LeftMouseButton activates by direct click; "
    .. "keyboard Open release closes without activation while hybrid controller-stick inward return still activates; "
    .. state.keyboardPageKeyName .. " or isolated "
    .. tostring(cfg("controllerNextWheelButton") or "")
    .. " cycles Wheel I/II/III; RMB cancels unless explicitly bound as Next Wheel; "
    .. "controller actions stay muted until release and camera resumes after recentering; "
    .. state.settingsKeyName .. " opens the PalWheel Menu; "
    .. tostring(cfg("controllerPalWheelMenuButton", "Gamepad_RightThumbstick")) .. " also opens it while the controller Main Wheel is active; "
    .. "native keyboard/mouse and controller glyphs use exact cached LoadAsset object paths; active Xbox/XInput vs DualSense presentation is auto-detected from Palworld CommonInput.GamepadInputType (with live-subsystem fallback), with Xbox only as the unknown fallback; Xbox FKey mappings still come from DT_PalGamepadButtonImage; "
    .. "Pal and weapon slots update Palworld's native HUD selection once per hover change; holding R1 or L2 before Open Wheel opens the separate Sphere Wheel; weapon slots 1-6 are assignable; "
    .. "the selected PalWheel skin supplies the circular background; the wheel uses adaptive dividers, a rotating direction ring, centre details, selected-text emphasis, and a short non-blocking reveal; the editor builds incrementally with slot-count, skin, and paged custom-shortcut selection; "
    .. "Saved\\shortcuts.tsv supplies configurable keyboard shortcut actions through PalworldKeyInjector; party capacity is detected from Palworld's party holder so expanded-party slots can be exposed dynamically; missing-sphere notices are background-free and expire after three seconds.", true)
