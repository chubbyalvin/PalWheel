local okConfig, config = pcall(require, "config")
if not okConfig or type(config) ~= "table" then config = {} end

local okMappings, mappings = pcall(require, "mappings")
if okMappings and type(mappings) == "table" then
    for name, value in pairs(mappings) do config[name] = value end
else
    mappings = {}
end

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
local ASSIGNMENTS_PATH = MOD_DIRECTORY .. "\\Saved\\assignments.lua"
local SHORTCUTS_PATH = MOD_DIRECTORY .. "\\Saved\\shortcuts.tsv"




local settingsLoadNote = nil
local settingsFileLoaded = false
local function loadSavedSettings()
    if type(loadfile) ~= "function" then
        settingsLoadNote = "Saved settings unavailable: loadfile is not exposed"
        return {}
    end

    local chunk, loadError = loadfile(SETTINGS_PATH)
    if type(chunk) ~= "function" then
        if loadError ~= nil and not string.find(string.lower(tostring(loadError)), "no such file", 1, true) then
            settingsLoadNote = "Saved settings ignored: " .. tostring(loadError)
        end
        return {}
    end

    local ok, saved = pcall(chunk)
    if not ok or type(saved) ~= "table" then
        settingsLoadNote = "Saved settings ignored: file did not return a valid table"
        return {}
    end
    settingsFileLoaded = true
    settingsLoadNote = "Saved settings loaded"
    return saved
end

local savedSettings = loadSavedSettings()
local settingsNeedsMigration = settingsFileLoaded
    and (tonumber(savedSettings.settingsFormatVersion or savedSettings.version) or 0) ~= 3

local legacyShortcutKeys = nil
if type(savedSettings.menuShortcutKeys) == "table" then
    legacyShortcutKeys = savedSettings.menuShortcutKeys
else
    local oldKeys = savedSettings.menuFallbackKeys or savedSettings.menuInjectionKeys
    if type(oldKeys) == "table" then
        legacyShortcutKeys = {
            character = "TAB",
            inventory = oldKeys.inventory or "I",
            technology = oldKeys.technology or "T",
            party = oldKeys.party or "P",
            build = oldKeys.build or "B",
        }
    end
end

local SAVED_CONFIG_FIELDS = {
    "openKey", "keyboardPageButton", "settingsKey",
    "controllerOpenButton", "controllerPageButton",
    "wheelOuterMarkerLayer", "controllerInvertY", "controllerStickDeadzone",
    "slowMotionEnabled", "wheelTimeDilation", "wheelFont", "mouseDeadzone",
    "keyboardMovementKeys", "controllerMovementKeys",
}
for _, field in ipairs(SAVED_CONFIG_FIELDS) do
    if savedSettings[field] ~= nil then config[field] = savedSettings[field] end
end
local MOD = "[PalWheel] "
local VIS_SHOW = 0
local VIS_HIDE = 1
local VIS_HIT_TEST_INVISIBLE = 3
local TWO_PI = math.pi * 2.0
local PAGE_SIZE = 12
local PAGE_COUNT = 3
local TOTAL_ASSIGNMENT_SLOTS = PAGE_SIZE * PAGE_COUNT
local MIN_VISIBLE_SLOTS = 4
local MAX_VISIBLE_SLOTS = 12
local DEFAULT_PARTY_CAPACITY = 5
local MAX_DYNAMIC_PARTY_CAPACITY = 4096
local PARTY_PICKER_PAGE_SIZE = 10
local MOUSE_LOCK_DO_NOT_LOCK = 0

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
        label = "Pal " .. tostring(number),
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

local assignmentsFileLoaded = false
local function loadSavedAssignments()
    if type(loadfile) ~= "function" then return nil end
    local chunk = loadfile(ASSIGNMENTS_PATH)
    if type(chunk) ~= "function" then return nil end
    local ok, values = pcall(chunk)
    if not ok or type(values) ~= "table" then return nil end
    assignmentsFileLoaded = true
    return values.assignments or values
end

local savedAssignments = loadSavedAssignments()
if type(savedAssignments) ~= "table" then savedAssignments = savedSettings.assignments end

local function maxReferencedPartySlot(assignments)
    local maximum = DEFAULT_PARTY_CAPACITY
    if type(assignments) ~= "table" then return maximum end
    for _, id in pairs(assignments) do
        local number = partyActionNumber(id)
        if number ~= nil and number > maximum then maximum = number end
    end
    return maximum
end

local INITIAL_PARTY_CATALOG_CAPACITY = maxReferencedPartySlot(savedAssignments)

local COLORS = {
    background = { R = 0.0, G = 0.0, B = 0.0,
        A = clamp(cfg("wheelBackgroundOpacity", 0.68), 0.20, 0.92) },
    weapon = { R = 0.08, G = 0.34, B = 0.76,
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    pal = { R = 0.06, G = 0.56, B = 0.28,
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    menu = { R = 0.42, G = 0.18, B = 0.68,
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    shortcut = { R = 0.42, G = 0.18, B = 0.68,
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    utility = { R = 0.78, G = 0.34, B = 0.08,
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    emote = { R = 0.58, G = 0.38, B = 0.72,
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    sphere = { R = 0.04, G = 0.55, B = 0.68,
        A = clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0) },
    empty = { R = 0.16, G = 0.18, B = 0.22,
        A = math.min(clamp(cfg("wheelBorderOpacity", 0.55), 0.05, 1.0), 0.45) },
    selected = { R = 0.98, G = 0.68, B = 0.08,
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
    text = { R = 0.95, G = 0.97, B = 1.0, A = 1.0 },
    blocker = { R = 0.0, G = 0.0, B = 0.0, A = 0.001 },
}

local BASE_FUNCTION_CATALOG = {
    { id = "empty", label = "Empty", short = "--", kind = "empty" },
    { id = "weapon1", label = "Weapon 1", short = "W1", kind = "weapon", index = 0 },
    { id = "weapon2", label = "Weapon 2", short = "W2", kind = "weapon", index = 1 },
    { id = "weapon3", label = "Weapon 3", short = "W3", kind = "weapon", index = 2 },
    { id = "weapon4", label = "Weapon 4", short = "W4", kind = "weapon", index = 3 },
    { id = "weapon5", label = "Weapon 5", short = "W5", kind = "weapon", index = 4 },
    { id = "weapon6", label = "Weapon 6", short = "W6", kind = "weapon", index = 5 },
    { id = "pal1", label = "Pal 1", short = "P1", kind = "pal", index = 0 },
    { id = "pal2", label = "Pal 2", short = "P2", kind = "pal", index = 1 },
    { id = "pal3", label = "Pal 3", short = "P3", kind = "pal", index = 2 },
    { id = "pal4", label = "Pal 4", short = "P4", kind = "pal", index = 3 },
    { id = "pal5", label = "Pal 5", short = "P5", kind = "pal", index = 4 },
    { id = "mercy", label = "Mercy Toggle", short = "MERCY", kind = "utility" },
    { id = "map", label = "World Map", short = "MAP", kind = "menu" },
    { id = "sphere_pal", label = "Pal Sphere", short = "PAL\nCR07", kind = "sphere", sphereId = "PalSphere", sphereName = "Pal Sphere", sphereShort = "Pal", captureRate = "07" },
    { id = "sphere_mega", label = "Mega Sphere", short = "MEGA\nCR14", kind = "sphere", sphereId = "PalSphere_Mega", sphereName = "Mega Sphere", sphereShort = "Mega", captureRate = "14" },
    { id = "sphere_giga", label = "Giga Sphere", short = "GIGA\nCR20", kind = "sphere", sphereId = "PalSphere_Giga", sphereName = "Giga Sphere", sphereShort = "Giga", captureRate = "20" },
    { id = "sphere_hyper", label = "Hyper Sphere", short = "HYPER\nCR27", kind = "sphere", sphereId = "PalSphere_Tera", sphereName = "Hyper Sphere", sphereShort = "Hyper", captureRate = "27" },
    { id = "sphere_ultra", label = "Ultra Sphere", short = "ULTRA\nCR33", kind = "sphere", sphereId = "PalSphere_Master", sphereName = "Ultra Sphere", sphereShort = "Ultra", captureRate = "33" },
    { id = "sphere_legendary", label = "Legendary Sphere", short = "LEGEND\nCR38", kind = "sphere", sphereId = "PalSphere_Legend", sphereName = "Legendary Sphere", sphereShort = "Legend", captureRate = "38" },
    { id = "sphere_ultimate", label = "Ultimate Sphere", short = "ULTIMATE\nCR44", kind = "sphere", sphereId = "PalSphere_Ultimate", sphereName = "Ultimate Sphere", sphereShort = "Ultimate", captureRate = "44" },
    { id = "sphere_exotic", label = "Exotic Sphere", short = "EXOTIC\nCR50", kind = "sphere", sphereId = "PalSphere_Exotic", sphereName = "Exotic Sphere", sphereShort = "Exotic", captureRate = "50" },
    { id = "sphere_sol", label = "Sol Sphere", short = "SOL\nCR58", kind = "sphere", sphereId = "PalSphere_Ancient_1", sphereName = "Sol Sphere", sphereShort = "Sol", captureRate = "58" },
    { id = "sphere_ancient", label = "Ancient Sphere", short = "ANCIENT\nCR64", kind = "sphere", sphereId = "PalSphere_Ancient_2", sphereName = "Ancient Sphere", sphereShort = "Ancient", captureRate = "64" },
    { id = "emote_0", label = "Beckon", short = "BECKON", kind = "emote", emoteIndex = 0 },
    { id = "emote_1", label = "Dance", short = "DANCE", kind = "emote", emoteIndex = 1 },
    { id = "emote_2", label = "Wave", short = "WAVE", kind = "emote", emoteIndex = 2 },
    { id = "emote_3", label = "Sit in Chair", short = "SIT IN\nCHAIR", kind = "emote", emoteIndex = 3 },
    { id = "emote_4", label = "Sit on Ground", short = "SIT ON\nGROUND", kind = "emote", emoteIndex = 4 },
    { id = "emote_5", label = "Surprised", short = "SURPRISED", kind = "emote", emoteIndex = 5 },
    { id = "emote_6", label = "Hand Over", short = "HAND OVER", kind = "emote", emoteIndex = 6 },
    { id = "emote_7", label = "Sleep", short = "SLEEP", kind = "emote", emoteIndex = 7 },
    { id = "emote_8", label = "Kick", short = "KICK", kind = "emote", emoteIndex = 8 },
}

local FUNCTION_CATALOG = {}
local FUNCTION_BY_ID = {}
local ACTIVE_SHORTCUTS = {}
local SHORTCUT_RESERVED_IDS = {}
for _, def in ipairs(BASE_FUNCTION_CATALOG) do SHORTCUT_RESERVED_IDS[def.id] = true end

local okShortcuts, ShortcutActions = pcall(require, "shortcut_actions")
local shortcutData = nil
if okShortcuts and type(ShortcutActions) == "table"
    and type(ShortcutActions.load) == "function" then
    shortcutData = ShortcutActions.load(SHORTCUTS_PATH, {
        legacyKeys = legacyShortcutKeys,
        reservedIds = SHORTCUT_RESERVED_IDS,
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

local DEFAULT_ASSIGNMENTS = {
    "mercy", "pal1", "pal2", "pal3",
    "pal4", "pal5", "weapon6", "weapon5",
    "weapon4", "weapon3", "weapon2", "weapon1",
    "sphere_giga", "sphere_hyper", "sphere_ultra", "sphere_legendary",
    "sphere_ultimate", "sphere_exotic", "inventory", "party",
    "technology", "map", "sphere_pal", "sphere_mega",
}

local function makeDefaultAssignments()
    local values = {}
    for i = 1, TOTAL_ASSIGNMENT_SLOTS do
        values[i] = DEFAULT_ASSIGNMENTS[i] or "empty"
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
        settingsLoadNote = "Saved settings loaded with " .. tostring(invalid)
            .. " invalid assignment(s) replaced by Empty"
    end
    return values
end

local legacyVisibleSlotCount = savedSettings.visibleSlotCount
if type(legacyVisibleSlotCount) ~= "number" then
    legacyVisibleSlotCount = savedSettings["visibleSli" .. "ceCount"]
end
if type(legacyVisibleSlotCount) ~= "number" then
    legacyVisibleSlotCount = cfg("visibleSlotCount", 12)
end

local initialVisibleSlotCounts = {}
for page = 1, PAGE_COUNT do
    local key = "wheel" .. tostring(page) .. "SlotCount"
    local value = savedSettings[key]
    if type(value) ~= "number" then value = cfg(key, nil) end
    if type(value) ~= "number" then value = legacyVisibleSlotCount end
    initialVisibleSlotCounts[page] = math.floor(clamp(
        value, MIN_VISIBLE_SLOTS, MAX_VISIBLE_SLOTS))
end

local state = {
    open = false,
    editorOpen = false,
    selected = nil,
    lastActivated = nil,
    activePage = 1,
    activeWheelCount = math.floor(clamp(
        tonumber(savedSettings.wheelCount or cfg("wheelCount", 3)) or 3, 1, PAGE_COUNT)),
    visibleSlotCounts = initialVisibleSlotCounts,
    wheelSkin = validWheelSkin(savedSettings.wheelSkin or cfg("wheelSkin", "wheel_02.png")),
    assignments = makeValidatedAssignments(savedAssignments),
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
    moveInputBlocked = false,
    gameplayInputBlocked = false,
    controllerWheelInputSuppressed = false,
    lockedRotation = nil,
    disabledInputActors = {},
    blockedInputComponents = {},

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
    sphereSelectionQueue = nil,
    hoverPreviewKey = nil,
    activePalSlot = nil,
    partyCapacity = DEFAULT_PARTY_CAPACITY,
    partyCatalogCapacity = INITIAL_PARTY_CATALOG_CAPACITY,
    partyCapacityNextPoll = 0.0,
    ignoreOpenBindUntil = 0.0,
    keyboardCancelInputs = {},
    keyboardCancelWasDown = {},

    widget = nil,
    tree = nil,
    root = nil,
    wheelPanel = nil,
    editorPanel = nil,
    clickBlocker = nil,
    clickBlockerSlot = nil,
    pointer = nil,
    pointerSlot = nil,
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
    editorSkinDropdownWidgets = {},
    editorSkinOptionRects = {},
    editorPickerOpen = false,
    editorPickingSlot = nil,
    editorPickerPanel = nil,
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
    editorResetShortcutsText = nil,
    editorResetConfirmOpen = false,
    editorResetConfirmWidgets = {},
    editorResetConfirmYesRect = nil,
    editorResetConfirmNoRect = nil,
    editorMoveBlocked = false,
    editorPawnDisabled = nil,
    editorDisableFlagApplied = false,
    pageText = nil,
    deferredMenuId = nil,
    deferredMenuAt = 0.0,
    aimSuppressionFailureLogged = false,

    notificationWidget = nil,
    notificationText = nil,
    notificationExpiresAt = 0.0,

    visuals = nil,
    editorBuilder = nil,
    keyboardOpenWasDown = false,
    keyboardOpenHandledAt = 0.0,
    keyboardMouseNeutralX = nil,
    keyboardMouseNeutralY = nil,
    keyboardMouseNeutralReady = false,
    hybridControllerSelectionActive = false,
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
    liveMovementKeys = {},
    liveMappingDiagnosticsLogged = {},
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
    if io == nil or type(io.open) ~= "function" then
        log(description .. " save failed: Lua file I/O is unavailable", true)
        return false
    end

    local temporaryPath = path .. ".tmp"
    local file, openError = io.open(temporaryPath, "wb")
    if file == nil then
        log(description .. " save failed: " .. tostring(openError), true)
        return false
    end
    local okWrite, writeError = pcall(function()
        file:write(table.concat(lines, "\r\n"))
        file:flush()
    end)
    pcall(function() file:close() end)
    if not okWrite then
        pcall(os.remove, temporaryPath)
        log(description .. " save failed while writing: " .. tostring(writeError), true)
        return false
    end
    pcall(os.remove, path)
    local renamed, renameError = os.rename(temporaryPath, path)
    if not renamed then
        pcall(os.remove, temporaryPath)
        log(description .. " save failed while finalizing: " .. tostring(renameError), true)
        return false
    end
    return true
end

local function saveAssignments()
    local lines = {
        "return {",
    }
    for i = 1, TOTAL_ASSIGNMENT_SLOTS do
        local id = state.assignments[i]
        if type(id) ~= "string" or FUNCTION_BY_ID[id] == nil then
            id = "empty"
        end
        lines[#lines + 1] = string.format("    [%d] = %q,", i, id)
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    return writeAtomicLua(ASSIGNMENTS_PATH, lines, "Assignments")
end

local function saveSettings()

    local lines = {
        "return {",
        "    settingsFormatVersion = 3,",
        "",
        "    wheel1SlotCount = " .. tostring(math.floor(state.visibleSlotCounts[1])) .. ",",
        "    wheel2SlotCount = " .. tostring(math.floor(state.visibleSlotCounts[2])) .. ",",
        "    wheel3SlotCount = " .. tostring(math.floor(state.visibleSlotCounts[3])) .. ",",
        "    wheelCount = " .. tostring(math.floor(state.activeWheelCount)) .. ",",
        "    wheelSkin = " .. string.format("%q", validWheelSkin(state.wheelSkin)) .. ",",
        "    wheelOuterMarkerLayer = " .. string.format("%q", tostring(cfg("wheelOuterMarkerLayer", "front"))) .. ",",
        "    wheelFont = " .. string.format("%q", tostring(cfg("wheelFont", "Default"))) .. ",",
        "",
        "    openKey = " .. string.format("%q", tostring(cfg("openKey", "CAPS_LOCK"))) .. ",",
        "    keyboardPageButton = " .. string.format("%q", tostring(cfg("keyboardPageButton", "RIGHT_MOUSE_BUTTON"))) .. ",",
        "    settingsKey = " .. string.format("%q", tostring(cfg("settingsKey", "F7"))) .. ",",
        "    mouseDeadzone = " .. tostring(math.floor(tonumber(cfg("mouseDeadzone", 48)) or 48)) .. ",",
        "",
        "    controllerOpenButton = " .. string.format("%q", tostring(cfg("controllerOpenButton", "Gamepad_DPad_Left"))) .. ",",
        "    controllerPageButton = " .. string.format("%q", tostring(cfg("controllerPageButton", "Gamepad_RightShoulder"))) .. ",",
        "    controllerInvertY = " .. tostring(cfg("controllerInvertY", true) == true) .. ",",
        "    controllerStickDeadzone = " .. tostring(clamp(cfg("controllerStickDeadzone", 0.25), 0.05, 0.95)) .. ",",
        "",
        "    slowMotionEnabled = " .. tostring(cfg("slowMotionEnabled", true) == true) .. ",",
        "    wheelTimeDilation = " .. tostring(clamp(cfg("wheelTimeDilation", 0.08), 0.01, 1.0)) .. ",",
        "",
        "    keyboardMovementKeys = {",
    }
    for _, name in ipairs(cfg("keyboardMovementKeys", {}) or {}) do
        lines[#lines + 1] = "        " .. string.format("%q", tostring(name or "")) .. ","
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    controllerMovementKeys = {"
    for _, name in ipairs(cfg("controllerMovementKeys", {}) or {}) do
        lines[#lines + 1] = "        " .. string.format("%q", tostring(name or "")) .. ","
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    local settingsSaved = writeAtomicLua(SETTINGS_PATH, lines, "Settings")
    local assignmentsSaved = saveAssignments()
    if settingsSaved and assignmentsSaved then
        log("Saved user settings and slot assignments", true)
    end
    return settingsSaved and assignmentsSaved
end

if settingsLoadNote ~= nil then log(settingsLoadNote, true) end
if not settingsFileLoaded or settingsNeedsMigration or not assignmentsFileLoaded then saveSettings() end

local function alive(object)
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
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

state.setControllerWheelInputSuppressed = function(enabled)
    enabled = enabled == true
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
    log("Movement input left enabled while wheel is open", true)
    return true
end

local function blockEditorGameplayInput(pc)
    state.disabledInputActors = {}
    state.blockedInputComponents = {}
    state.editorPawnDisabled = nil
    state.editorDisableFlagApplied = false
    state.editorMoveBlocked = false

    if not alive(pc) then return false end

    local okPawn, pawn = pcall(function() return pc.Pawn end)
    if okPawn and alive(pawn) then
        disableActorInput(pawn, pc)
        state.editorPawnDisabled = pawn
    end

    local okMove = pcall(function() pc:SetIgnoreMoveInput(true) end)
    state.moveInputBlocked = okMove
    state.editorMoveBlocked = okMove

    local okFlag = pcall(function()
        pc:SetDisableInputFlag(FName("PalWheelEditor"), true)
    end)
    state.editorDisableFlagApplied = okFlag
    state.gameplayInputBlocked = true
    log("Editor gameplay input fully blocked", true)
    return true
end

local function restoreGameplayInput()
    local pc = state.pc

    if state.controllerWheelInputSuppressed then
        state.setControllerWheelInputSuppressed(false)
    end

    if state.editorDisableFlagApplied and alive(pc) then
        pcall(function() pc:SetDisableInputFlag(FName("PalWheelEditor"), false) end)
    end

    if state.moveInputBlocked and alive(pc) then
        pcall(function() pc:SetIgnoreMoveInput(false) end)
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
    state.editorPawnDisabled = nil
    state.editorDisableFlagApplied = false
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

    log("Requested weapon slot " .. tostring(index + 1), true)
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

local function getLocalInventoryData()
    local pc = state.pc
    if not alive(pc) then pc = getPlayerController() end
    if not alive(pc) then return nil end

    local playerState = nil
    local okState = pcall(function() playerState = pc:GetPalPlayerState() end)
    if not okState or not alive(playerState) then
        pcall(function() playerState = pc.PlayerState end)
    end
    if not alive(playerState) then return nil end

    local inventoryData = nil
    local okInventory = pcall(function() inventoryData = playerState:GetInventoryData() end)
    if not okInventory or not alive(inventoryData) then return nil end
    return inventoryData
end

local function slotStaticId(slot)
    if not alive(slot) then return "" end
    local itemId = nil
    local ok = pcall(function() itemId = slot:GetItemId() end)
    if not ok or itemId == nil then return "" end

    local staticId = nil
    pcall(function() staticId = itemId.StaticId end)
    return normalizedName(staticId)
end

local function scanMercyAccessorySlots(inventoryData)
    local equipped = nil
    local inventoryCandidates = {}
    local helper = nil
    pcall(function() helper = inventoryData.InventoryMultiHelper end)
    if not alive(helper) then return nil, inventoryCandidates, "InventoryMultiHelper unavailable" end

    local containers = nil
    pcall(function() containers = helper.Containers end)
    if containers == nil then return nil, inventoryCandidates, "inventory container list unavailable" end

    local okIterate, iterateErr = pcall(function()
        containers:ForEach(function(_, rawContainer)
            local container = unwrapArrayElement(rawContainer)
            if not alive(container) then return end

            local count = 0
            local okCount, value = pcall(function() return container:Num() end)
            if okCount then count = tonumber(value) or 0 end
            if count <= 0 or count > 500 then return end

            for index = 0, count - 1 do
                local slot = nil
                pcall(function() slot = container:Get(index) end)
                if alive(slot) then
                    local empty = true
                    pcall(function() empty = slot:IsEmpty() == true end)
                    if not empty then
                        local id = slotStaticId(slot)
                        local priority = MERCY_ITEM_PRIORITY[id]
                        if priority ~= nil then
                            local isEquipped = false
                            pcall(function() isEquipped = inventoryData:IsEquipSlot(slot) == true end)
                            local entry = { slot = slot, id = id, priority = priority }
                            if isEquipped then
                                if equipped == nil or priority < equipped.priority then equipped = entry end
                            else
                                inventoryCandidates[#inventoryCandidates + 1] = entry
                            end
                        end
                    end
                end
            end
        end)
    end)

    if not okIterate then return equipped, inventoryCandidates, tostring(iterateErr) end
    table.sort(inventoryCandidates, function(a, b) return a.priority < b.priority end)
    return equipped, inventoryCandidates, nil
end

local function toggleMercyAccessory()
    if cfg("mercyAccessoryToggleEnabled", true) ~= true then
        log("Mercy accessory toggle is disabled in config.lua", true)
        return false
    end

    local inventoryData = getLocalInventoryData()
    if not alive(inventoryData) then
        log("Mercy toggle: local inventory data unavailable", true)
        return false
    end

    local equipped, candidates, scanError = scanMercyAccessorySlots(inventoryData)
    if scanError ~= nil then log("Mercy toggle scan warning: " .. scanError, true) end

    if equipped ~= nil and alive(equipped.slot) then
        local ok, result = pcall(function()
            return inventoryData:TryRemoveEquipment(equipped.slot)
        end)
        if ok and result ~= false then
            log("Unequipped mercy accessory: " .. equipped.id, true)
            return true
        end
        log("Mercy toggle could not unequip accessory (inventory may be full)", true)
        return false
    end

    local candidate = candidates[1]
    if candidate ~= nil and alive(candidate.slot) then
        local ok, result = pcall(function()
            return inventoryData:TryEquipSlot(candidate.slot)
        end)
        if ok and result ~= false then
            log("Equipped mercy accessory: " .. candidate.id, true)
            return true
        end
        log("Mercy toggle could not equip the available accessory", true)
        return false
    end

    log("Mercy toggle: Ring of Mercy or Pal Tamer's Glasses not found in inventory", true)
    return false
end

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

    log("Triggered emote " .. tostring(index), true)
    return true
end

local SphereActions = require("sphere_actions")
state.sphereActions = SphereActions.new({
    cfg = cfg,
    alive = alive,
    normalizedName = normalizedName,
    getLocalInventoryData = getLocalInventoryData,
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

local function makeFKey(name)
    return { KeyName = FName(name) }
end

local function isKeyDown(pc, key)
    if not alive(pc) or key == nil then return false end
    local ok, value = pcall(function() return pc:IsInputKeyDown(key) end)
    return ok and value == true
end

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
    log(string.format("Slow motion applied: %.2fx", target), true)
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
            log(string.format("Game speed restored: %.2fx", restoreValue), true)
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
    if string.upper(tostring(cfg("keyboardPageButton") or ""))
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

    state.lockedRotation = readControlRotation(pc)
    if state.lockedRotation == nil then
        log("Camera lock unavailable: could not read control rotation", true)
        return false
    end

    state.lookInputBlocked = false
    log("Camera rotation captured; temporary hard clamp enabled", true)
    return true
end

local function enforceCameraLock()
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
    state.lookInputBlocked = false
    state.lockedRotation = nil
    state.cameraLockFailureLogged = false
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

    local showHardwareCursor = cfg("hideHardwareCursorWhileOpen", true) ~= true
    setCursorFlags(pc, showHardwareCursor, true)

    local ok, callError = pcall(function()
        wbl:SetInputMode_GameAndUIEx(pc, state.widget,
            MOUSE_LOCK_DO_NOT_LOCK, false, false)
    end)
    if not ok then
        ok, callError = pcall(function()
            wbl:SetInputMode_GameAndUIEx(pc, state.widget,
                MOUSE_LOCK_DO_NOT_LOCK, false)
        end)
    end

    if ok then
        if not showHardwareCursor then
            pcall(function() pc.bShowMouseCursor = false end)
        end
        state.uiInputApplied = true
        if firstApply then log("Game-and-UI cursor input applied; movement remains enabled", true) end
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
        wbl:SetInputMode_UIOnlyEx(pc, state.widget, MOUSE_LOCK_DO_NOT_LOCK, false)
    end)
    if not ok then
        ok = pcall(function()
            wbl:SetInputMode_UIOnlyEx(pc, state.widget, MOUSE_LOCK_DO_NOT_LOCK)
        end)
    end
    if not ok then
        ok = pcall(function() wbl:SetInputMode_UIOnly(pc, state.widget) end)
    end
    if ok then
        state.uiInputApplied = true
        if firstApply then log("UI-only editor input applied", true) end
    end
    return ok
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
    log("Normal game input restored", true)
end

local function centerHardwareCursor(pc)
    if not alive(pc) then return false end

    local centerX = math.floor(tonumber(cfg("centerX", 960)) or 960)
    local centerY = math.floor(tonumber(cfg("centerY", 540)) or 540)

    state.keyboardMouseNeutralReady = false
    state.keyboardMouseNeutralX = nil
    state.keyboardMouseNeutralY = nil

    local ok = pcall(function() pc:SetMouseLocation(centerX, centerY) end)
    if ok then log("Mouse cursor centred for radial selection", true) end

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
    pcall(function() widget:SetVisibility(visible and VIS_SHOW or VIS_HIDE) end)
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
    if type(value) ~= "number" then value = MAX_VISIBLE_SLOTS end
    return math.floor(clamp(value, MIN_VISIBLE_SLOTS, MAX_VISIBLE_SLOTS))
end

local function activeVisibleSlotCount()
    return visibleSlotCountForPage(state.activePage)
end

local function assignmentDefinitionByGlobalSlot(globalSlot)
    local id = state.assignments[globalSlot] or "empty"
    return FUNCTION_BY_ID[id] or FUNCTION_BY_ID.empty
end

local function assignmentDefinitionForVisibleIndex(index)
    return assignmentDefinitionByGlobalSlot(assignmentSlotForVisibleIndex(index))
end

local function colorForDefinition(def)
    if def == nil then return COLORS.empty end
    return COLORS[def.kind] or COLORS.empty
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
                    local pageDef = assignmentDefinitionByGlobalSlot(globalSlot)
                    if alive(layer.label) then
                        setText(layer.label, pageDef.short or pageDef.label)
                        setVisible(layer.label, page == state.activePage)
                    end
                    if alive(layer.detailLabel) then
                        setText(layer.detailLabel, "")
                        setVisible(layer.detailLabel, false)
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
                setBorderColor(markerBack, state.selected == index
                    and COLORS.selected or COLORS.divider)
                setWidgetScale(markerBack, state.selected == index
                    and clamp(cfg("wheelSelectedMarkerScale", 1.18), 1.02, 1.60)
                    or 1.0)
            end
            if markerFront ~= nil then
                setBorderColor(markerFront, state.selected ~= index and activated
                    and COLORS.activated or baseColor)
                setWidgetScale(markerFront, 1.0)
            end
        end
    end
    local selectedLeft = state.selected
    local selectedRight = state.selected ~= nil
        and ((state.selected % activeVisibleSlotCount()) + 1) or nil
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
        setText(state.pageText, wheelRoman(state.activePage))
    end
    if state.callVisual ~= nil then
        local selectedDef = state.selected ~= nil
            and assignmentDefinitionForVisibleIndex(state.selected) or nil
        state.callVisual("updateHighlight", selectedDef, state.selected,
            state.activePage, state.sectors, nil)
    end
end

local rebuildWheelForActivePage

local function switchActivePage()
    if not state.open or state.selectionCommitted then return false end
    local pageCount = math.floor(clamp(state.activeWheelCount or PAGE_COUNT, 1, PAGE_COUNT))
    state.activePage = (state.activePage % pageCount) + 1
    state.selected = nil
    state.lastActivated = nil
    state.hoverPreviewKey = nil

    if type(rebuildWheelForActivePage) ~= "function"
        or not rebuildWheelForActivePage() then
        return false
    end

    if state.controller == nil or not state.controller:isSession() then
        centerHardwareCursor(state.pc)
    end
    log("Switched to Wheel " .. wheelRoman(state.activePage), true)
    return true
end

local function destroyWidget()
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
    state.openedAt = 0.0
    state.selectionCommitted = false
    state.pendingMouseReleaseClose = false
    state.clickCommittedAt = 0.0
    state.pendingPalSlot = nil
    state.pendingMenuId = nil
    state.pendingUtilityId = nil
    state.pendingSphereId = nil
    state.hoverPreviewKey = nil
    state.keyboardCancelWasDown = {}
    state.pc = nil
    state.widget = nil
    state.tree = nil
    state.root = nil
    state.wheelPanel = nil
    state.editorPanel = nil
    state.clickBlocker = nil
    state.clickBlockerSlot = nil
    state.pointer = nil
    state.pointerSlot = nil
    state.sectors = {}
    state.dividers = {}
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
    state.editorSkinDropdownWidgets = {}
    state.editorSkinOptionRects = {}
    state.editorPickerOpen = false
    state.editorPickingSlot = nil
    state.editorPickerPanel = nil
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
    state.editorResetShortcutsText = nil
    state.editorResetConfirmOpen = false
    state.editorResetConfirmWidgets = {}
    state.editorResetConfirmYesRect = nil
    state.editorResetConfirmNoRect = nil
    state.pageText = nil
    if state.callVisual ~= nil then state.callVisual("reset") end
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

local function createCanvasText(tree, root, textValue, x, y, width, height, fontSize, justification)
    local text = construct("/Script/UMG.TextBlock", tree)
    if not alive(text) then return nil end
    local slot = addToCanvas(root, text)
    if slot == nil then return nil end
    place(slot, x, y, width, height)
    setText(text, textValue)
    if tonumber(fontSize) ~= nil then
        pcall(function()
            local font = text.Font
            font.Size = math.floor(tonumber(fontSize))
            local requestedFont = tostring(cfg("wheelFont", "Default"))
            if requestedFont ~= "Default" then
                local okFont, fontObject = pcall(StaticFindObject, requestedFont)
                if okFont and fontObject ~= nil then font.FontObject = fontObject end
            end
            text:SetFont(font)
        end)
    end
    pcall(function() text:SetAutoWrapText(false) end)
    pcall(function() text:SetJustification(tonumber(justification) or 1) end)
    pcall(function() text:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
    return text
end

local function createWheelBackground(tree, root, pc, centerX, centerY, radius)
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
                    A = clamp(cfg("wheelBackgroundOpacity", 0.92), 0.25, 1.0) })
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
            B = 0.03, A = clamp(cfg("wheelBackgroundOpacity", 0.92), 0.25, 1.0) }) end)
    end
    return glyph
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
            log("Animated centre pointer/detail layer loaded", true)
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
end

state.showCenterNotification = function(message)
    local pc = state.pc
    if not alive(pc) then pc = getPlayerController() end
    if not alive(pc) then
        log("Notification unavailable: " .. tostring(message), true)
        return false
    end

    if not alive(state.notificationWidget) or not alive(state.notificationText) then
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

        local text = createCanvasText(tree, root, "", x + 14, y + 7,
            width - 28, height - 14, cfg("notificationFontSize", 24))
        if not alive(text) then
            pcall(function() widget:RemoveFromParent() end)
            log("Notification text construction failed: " .. tostring(message), true)
            return false
        end
        pcall(function() text:SetRenderOpacity(0.98) end)

        local okViewport = pcall(function() widget:AddToViewport(100) end)
        if not okViewport then
            pcall(function() widget:RemoveFromParent() end)
            log("Notification AddToViewport failed: " .. tostring(message), true)
            return false
        end

        state.notificationWidget = widget
        state.notificationText = text
    end

    setText(state.notificationText, tostring(message))
    setVisible(state.notificationWidget, true)
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
    local markerLayer = string.lower(tostring(cfg("wheelOuterMarkerLayer", "front")))
    if markerLayer ~= "front" and markerLayer ~= "back"
        and markerLayer ~= "hidden" then
        markerLayer = "front"
    end
    local markerZOrder = markerLayer == "back" and -10 or 10
    local visibleCount = activeVisibleSlotCount()

    local radialSpan = outerRadius - innerRadius
    local sectorSpan = TWO_PI / visibleCount

    createWheelBackground(tree, root, pc, centerX, centerY, outerRadius)

    state.dividers = {}
    for index = 1, visibleCount do
        local slotOneAngle = math.rad(tonumber(cfg("wheelSlotOneAngleDegrees", 180)) or 180)
        local boundaryAngle = slotOneAngle + sectorSpan * 0.5
            - ((index - 1) * sectorSpan)
        local length = radialSpan - 18
        local radius = innerRadius + 9 + length * 0.5
        local divider = { base = nil, glow = nil }
        local base = construct("/Script/UMG.Border", tree)
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
        local glow = construct("/Script/UMG.Border", tree)
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
        local centerAngle = math.rad(tonumber(cfg("wheelSlotOneAngleDegrees", 180)) or 180)
            - ((index - 1) * sectorSpan)
        local sector = {
            bands = {},
            globalSlot = assignmentSlotForVisibleIndex(index),
            pages = {},
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
                pcall(function() markerSlot:SetZOrder(markerZOrder + 1) end)
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

        local labelRadius = innerRadius + radialSpan * 0.58
        local labelWidth, labelHeight = 74, 28
        local labelX = centerX + math.cos(centerAngle) * labelRadius - labelWidth * 0.5
        local labelY = centerY - math.sin(centerAngle) * labelRadius - labelHeight * 0.5
        for page = 1, PAGE_COUNT do
            local globalSlot = (page - 1) * PAGE_SIZE + index
            local def = assignmentDefinitionByGlobalSlot(globalSlot)
            local layer = {}
            layer.label = createCanvasText(tree, root, def.short or def.label,
                labelX, labelY - 7, labelWidth, labelHeight + 14, 12)
            setVisible(layer.label, false)

            layer.detailLabel = createCanvasText(tree, root, "",
                labelX - 5, labelY + 41, labelWidth + 10, 34, 11)
            setVisible(layer.detailLabel, false)

            sector.pages[page] = layer
        end

        state.sectors[index] = sector
    end

    state.pageText = createCanvasText(tree, root,
        wheelRoman(state.activePage),
        centerX - 45, centerY - 15, 90, 30)
    if state.callVisual ~= nil and state.callVisual("build", tree, root,
        centerX, centerY, clamp(cfg("centerSize", 136), 50, 160)) then
        setVisible(state.pageText, false)
    end

    local displayName = cfg("displayName", nil)
    local settingsKeyLabel = string.upper(tostring(cfg("settingsKey") or ""))
    local keyboardPageLabel = string.upper(tostring(
        cfg("keyboardPageButton") or ""))
    local controllerPageLabel = tostring(
        cfg("controllerPageButton") or "")
    if type(displayName) == "function" then
        settingsKeyLabel = displayName(cfg("settingsKey"))
        keyboardPageLabel = displayName(
            cfg("keyboardPageButton"))
        controllerPageLabel = displayName(
            cfg("controllerPageButton"))
    end
    local settingsHint = createCanvasText(tree, root,
        "Change wheel: " .. keyboardPageLabel .. " / " .. controllerPageLabel
            .. "    |    Settings: " .. settingsKeyLabel,
        centerX - 330, centerY + outerRadius + 24, 660, 24, 13)
    if alive(settingsHint) then
        pcall(function() settingsHint:SetRenderOpacity(0.68) end)
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
    log("Persistent three-page " .. validWheelSkin(state.wheelSkin) .. " "
        .. tostring(visibleCount) .. "-slot wheel built", true)
    return true
end

local function angularDistance(a, b)
    return math.abs((a - b + math.pi) % TWO_PI - math.pi)
end

local function invalidateWheelPanel()
    if alive(state.wheelPanel) then
        pcall(function() state.wheelPanel:RemoveFromParent() end)
    end
    state.wheelPanel = nil
    state.sectors = {}
    state.dividers = {}
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

rebuildWheelForActivePage = function()
    invalidateWheelPanel()
    if not buildWidget(state.pc) then return false end
    setVisible(state.wheelPanel, true)
    setVisible(state.widget, true)
    if state.callVisual ~= nil then
        state.callVisual("begin", state.wheelPanel, state.sectors, state.activePage)
    end
    updateHighlight()
    return true
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


local function createEditorText(tree, root, textValue, x, y, width, height, fontSize, justification)
    return createCanvasText(tree, root, textValue, x, y, width, height, fontSize, justification)
end

local function updateEditorCountText(page)
    if page ~= nil then
        local widget = state.editorCountTexts and state.editorCountTexts[page] or nil
        if alive(widget) then
            setText(widget, tostring(visibleSlotCountForPage(page)) .. " SLOTS  ▼")
        end
        return
    end
    for wheel = 1, PAGE_COUNT do updateEditorCountText(wheel) end
end

local function updateEditorWheelCountText()
    if alive(state.editorWheelCountText) then
        setText(state.editorWheelCountText,
            tostring(math.floor(clamp(state.activeWheelCount or PAGE_COUNT, 1, PAGE_COUNT)))
                .. "  ▼")
    end
end

local function updateEditorSkinText()
    if alive(state.editorSkinText) then
        setText(state.editorSkinText, validWheelSkin(state.wheelSkin) .. "  ▼")
    end
end

local function updateEditorSlowMotionText()
    if alive(state.editorSlowMotionText) then
        setText(state.editorSlowMotionText,
            cfg("slowMotionEnabled", true) == true and "ON" or "OFF")
    end
end

local function updateEditorRow(slotIndex)
    local row = state.editorRows[slotIndex]
    if row == nil then return end
    local def = assignmentDefinitionByGlobalSlot(slotIndex)
    if alive(row.assignmentText) then
        local rowLabel = def.label
        if def.kind == "shortcut" and tostring(def.shortcutDisplay or "") ~= "" then
            local status = def.active == false and "  [INACTIVE]" or ""
            rowLabel = tostring(def.label) .. status
                .. "  [" .. tostring(def.shortcutDisplay) .. "]"
        end
        setText(row.assignmentText, rowLabel)
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
                wheelSkins = WHEEL_SKINS,
                updateRow = updateEditorRow,
                pageSize = PAGE_SIZE,
                pageCount = PAGE_COUNT,
                totalSlots = TOTAL_ASSIGNMENT_SLOTS,
                wheelRoman = wheelRoman,
                hitTestInvisible = VIS_HIT_TEST_INVISIBLE,
                log = log,
            })
        else
            log("F7 editor unavailable: editor_builder.lua could not be loaded: "
                .. tostring(builderModule), true)
            return false
        end
    end
    if state.editorBuilder ~= nil then
        return state.editorBuilder:start(pc)
    end

    local tree = state.tree
    local editorPanel = construct("/Script/UMG.CanvasPanel", tree)
    local editorPanelSlot = alive(editorPanel)
        and addToCanvas(state.root, editorPanel) or nil
    if editorPanelSlot == nil then
        log("Editor build stopped: persistent editor panel unavailable", true)
        return false
    end
    place(editorPanelSlot, 0, 0,
        tonumber(cfg("screenWidth", 1920)) or 1920,
        tonumber(cfg("screenHeight", 1080)) or 1080)
    state.editorPanel = editorPanel
    local root = editorPanel
    local panelX, panelY, panelW, panelH = 130, 82, 1660, 914

    local panel = construct("/Script/UMG.Border", tree)
    if alive(panel) then
        local panelSlot = addToCanvas(root, panel)
        if panelSlot ~= nil then
            place(panelSlot, panelX, panelY, panelW, panelH)
            setBorderColor(panel, COLORS.panel)
            pcall(function() panel:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
        end
    end

    createEditorText(tree, root, "PALWHEEL ASSIGNMENTS", 170, 108, 760, 42)
    local settingsKeyLabel = tostring(cfg("settingsKey") or "settings key")
    if type(cfg("displayName", nil)) == "function" then
        settingsKeyLabel = cfg("displayName")(cfg("settingsKey"))
    end
    createEditorText(tree, root,
        "Click an assigned-function cell to choose directly.  "
            .. settingsKeyLabel .. " closes the editor.",
        190, 148, 1200, 32)

    local minusX, countY, buttonW, buttonH = 700, 188, 58, 42
    local countX, countW = 775, 370
    local plusX = 1160

    local minus = construct("/Script/UMG.Border", tree)
    if alive(minus) then
        local slot = addToCanvas(root, minus)
        if slot ~= nil then
            place(slot, minusX, countY, buttonW, buttonH)
            setBorderColor(minus, COLORS.button)
            pcall(function() minus:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
            createEditorText(tree, root, "-", minusX + 21, countY + 4, 28, 32)
            state.editorMinusRect = { x = minusX, y = countY, w = buttonW, h = buttonH }
        end
    end

    state.editorCountText = createEditorText(tree, root, "", countX, countY + 5, countW, 34)
    updateEditorCountText()

    local plus = construct("/Script/UMG.Border", tree)
    if alive(plus) then
        local slot = addToCanvas(root, plus)
        if slot ~= nil then
            place(slot, plusX, countY, buttonW, buttonH)
            setBorderColor(plus, COLORS.button)
            pcall(function() plus:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
            createEditorText(tree, root, "+", plusX + 18, countY + 4, 32, 32)
            state.editorPlusRect = { x = plusX, y = countY, w = buttonW, h = buttonH }
        end
    end

    createEditorText(tree, root, "SLOW MOTION", 1300, 195, 130, 30, 16)
    local slowMotionBorder = construct("/Script/UMG.Border", tree)
    if alive(slowMotionBorder) then
        local slowMotionSlot = addToCanvas(root, slowMotionBorder)
        if slowMotionSlot ~= nil then
            place(slowMotionSlot, 1430, 188, 150, 42)
            setBorderColor(slowMotionBorder, COLORS.button)
            pcall(function() slowMotionBorder:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
        end
    end
    state.editorSlowMotionText = createEditorText(
        tree, root, "", 1448, 195, 114, 30, 18)
    state.editorSlowMotionRect = { x = 1430, y = 188, w = 150, h = 42 }
    updateEditorSlowMotionText()
    createEditorText(tree, root,
        "Always disabled in multiplayer.",
        1300, 232, 320, 24, 11)

    local tableY = 270
    local leftX, rightX = 190, 985
    local tableW = 745
    local slotW = 105
    local assignmentW = tableW - slotW - 4
    local pieHeaderH, columnHeaderH, rowH, rowGap = 42, 34, 43, 3

    local function makeCell(x, y, w, h, color, textValue, textInset)
        local border = construct("/Script/UMG.Border", tree)
        local borderSlot = alive(border) and addToCanvas(root, border) or nil
        if borderSlot ~= nil then
            place(borderSlot, x, y, w, h)
            setBorderColor(border, color)
            pcall(function() border:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
        end
        local inset = textInset or 10
        local text = createEditorText(tree, root, textValue or "", x + inset, y + 7,
            math.max(10, w - inset * 2), math.max(20, h - 10))
        return border, text
    end

    for pie = 1, 2 do
        local x = pie == 1 and leftX or rightX
        makeCell(x, tableY, tableW, pieHeaderH, COLORS.button,
            pie == 1 and "WHEEL I" or "WHEEL II", 18)
        local headerY = tableY + pieHeaderH + 3
        makeCell(x, headerY, slotW, columnHeaderH, COLORS.row, "SLOT", 18)
        makeCell(x + slotW + 4, headerY, assignmentW, columnHeaderH,
            COLORS.row, "ASSIGNED FUNCTION", 18)

        local rowsY = headerY + columnHeaderH + 4
        for localSlot = 1, PAGE_SIZE do
            local slotIndex = (pie - 1) * PAGE_SIZE + localSlot
            local y = rowsY + (localSlot - 1) * (rowH + rowGap)
            local neutral = (localSlot % 2 == 0) and COLORS.rowAlt or COLORS.row
            local slotBorder, slotText = makeCell(x, y, slotW, rowH, neutral,
                string.format("%02d", localSlot), 30)
            local assignmentX = x + slotW + 4
            local assignmentBorder, assignmentText = makeCell(
                assignmentX, y, assignmentW, rowH, COLORS.empty, "", 18)

            state.editorRows[slotIndex] = {
                slotBorder = slotBorder,
                slotText = slotText,
                assignmentBorder = assignmentBorder,
                assignmentText = assignmentText,
                rect = { x = assignmentX, y = y, w = assignmentW, h = rowH },
            }
            updateEditorRow(slotIndex)
        end
    end

    local pickerX, pickerY, pickerW, pickerH = 205, 188, 1510, 690
    local pickerPanel = construct("/Script/UMG.Border", tree)
    if alive(pickerPanel) then
        local pickerPanelSlot = addToCanvas(root, pickerPanel)
        if pickerPanelSlot ~= nil then
            place(pickerPanelSlot, pickerX, pickerY, pickerW, pickerH)
            setBorderColor(pickerPanel, COLORS.panel)
            state.editorPickerPanel = pickerPanel
        end
    end
    state.editorPickerTitle = createEditorText(tree, root,
        "CHOOSE ASSIGNED FUNCTION", pickerX + 38, pickerY + 22, pickerW - 76, 42)

    local pickerGroups = {
        {
            title = "WEAPONS",
            x = pickerX + 42,
            width = 195,
            ids = {
                "weapon1", "weapon2", "weapon3", "weapon4", "weapon5", "weapon6",
            },
        },
        {
            title = "PARTY",
            x = pickerX + 253,
            width = 190,
            ids = (function()
                local ids = {}
                local count = math.min(
                    tonumber(state.partyCapacity) or DEFAULT_PARTY_CAPACITY,
                    PARTY_PICKER_PAGE_SIZE)
                for number = 1, count do
                    ids[#ids + 1] = "pal" .. tostring(number)
                end
                return ids
            end)(),
        },
        {
            title = "GAME MENUS",
            x = pickerX + 459,
            width = 250,
            ids = {
                "character", "inventory", "map", "technology", "party", "build",
            },
        },
        {
            title = "SPHERES",
            x = pickerX + 725,
            width = 270,
            ids = {
                "sphere_pal", "sphere_mega", "sphere_giga", "sphere_hyper",
                "sphere_ultra", "sphere_legendary", "sphere_ultimate",
                "sphere_exotic", "sphere_sol", "sphere_ancient",
            },
        },
        {
            title = "UTILITY",
            x = pickerX + 1011,
            width = 200,
            ids = { "mercy" },
        },
        {
            title = "GENERAL",
            x = pickerX + 1227,
            width = 170,
            ids = { "empty" },
        },
    }

    local groupHeaderY = pickerY + 88
    local itemStartY = pickerY + 138
    local itemH, gapY = 42, 6

    for _, group in ipairs(pickerGroups) do
        local headerBorder = construct("/Script/UMG.Border", tree)
        local headerSlot = alive(headerBorder) and addToCanvas(root, headerBorder) or nil
        if headerSlot ~= nil then
            place(headerSlot, group.x, groupHeaderY, group.width, 36)
            setBorderColor(headerBorder, COLORS.button)
            pcall(function() headerBorder:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
        end
        local headerText = createEditorText(tree, root, group.title,
            group.x + 12, groupHeaderY + 6, group.width - 24, 26)
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = headerBorder
        state.editorPickerWidgets[#state.editorPickerWidgets + 1] = headerText

        for rowNumber, functionId in ipairs(group.ids) do
            local def = FUNCTION_BY_ID[functionId]
            if def ~= nil then
                local catalogIndex = def.catalogIndex
                local x = group.x
                local y = itemStartY + (rowNumber - 1) * (itemH + gapY)
                local border = construct("/Script/UMG.Border", tree)
                local borderSlot = alive(border) and addToCanvas(root, border) or nil
                if borderSlot ~= nil then
                    place(borderSlot, x, y, group.width, itemH)
                    setBorderColor(border, colorForDefinition(def))
                    pcall(function() border:SetVisibility(VIS_HIT_TEST_INVISIBLE) end)
                end
                local textInset = 10
                local textWidget = createEditorText(tree, root,
                    def.label,
                    x + textInset, y + 8, group.width - textInset - 10, 26)
                state.editorPickerWidgets[#state.editorPickerWidgets + 1] = border
                state.editorPickerWidgets[#state.editorPickerWidgets + 1] = textWidget
                state.editorPickerRects[catalogIndex] = {
                    x = x, y = y, w = group.width, h = itemH
                }
            end
        end
    end

    local pickerHelp = createEditorText(tree, root,
        "Right-click or click outside the panel to cancel",
        pickerX + 505, pickerY + 644, 500, 28)
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = pickerHelp
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = state.editorPickerPanel
    state.editorPickerWidgets[#state.editorPickerWidgets + 1] = state.editorPickerTitle
    for _, widget in ipairs(state.editorPickerWidgets) do setVisible(widget, false) end

    local displayName = cfg("displayName", nil)
    local openKeyboard = tostring(cfg("openKey") or "")
    local pageKeyboard = tostring(cfg("keyboardPageButton") or "")
    local openController = tostring(cfg("controllerOpenButton") or "")
    local pageController = tostring(cfg("controllerPageButton") or "")
    if type(displayName) == "function" then
        openKeyboard = displayName(openKeyboard)
        pageKeyboard = displayName(pageKeyboard)
        openController = displayName(openController)
        pageController = displayName(pageController)
    end
    createEditorText(tree, root,
        "Open Wheel: " .. openKeyboard .. " / " .. openController
            .. "    |    Toggle Page: " .. pageKeyboard .. " / " .. pageController,
        520, 927, 1000, 24, 12)
    createEditorText(tree, root,
        "Assignments, slot count, and wheel skin save automatically.",
        520, 951, 900, 22, 11)
    createEditorText(tree, root,
        "PalWheel v" .. tostring(cfg("version", "1.0")),
        1570, 958, 170, 24, 12)

    setVisible(state.editorPanel, false)
    log("Persistent 36-slot editor and grouped function picker built", true)
    return true
end

local function pointInRect(x, y, rect)
    if rect == nil then return false end
    return x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

local SHORTCUT_PICKER_PAGE_SIZE = 10

local function partyPickerPageCount()
    return math.max(1, math.ceil((tonumber(state.partyCapacity)
        or DEFAULT_PARTY_CAPACITY) / PARTY_PICKER_PAGE_SIZE))
end

local function updatePartyPickerPage()
    local pageCount = partyPickerPageCount()
    state.editorPartyPage = math.floor(clamp(state.editorPartyPage or 1, 1, pageCount))
    local startNumber = (state.editorPartyPage - 1) * PARTY_PICKER_PAGE_SIZE + 1
    state.editorPartyRowIds = {}
    for row = 1, PARTY_PICKER_PAGE_SIZE do
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
        setText(state.editorPartyPageText, tostring(state.editorPartyPage)
            .. "/" .. tostring(pageCount))
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

local function shortcutPickerPageCount()
    return math.max(1, math.ceil(#(ACTIVE_SHORTCUTS or {}) / SHORTCUT_PICKER_PAGE_SIZE))
end

local function updateShortcutPickerPage()
    local pageCount = shortcutPickerPageCount()
    state.editorShortcutPage = math.floor(clamp(state.editorShortcutPage or 1, 1, pageCount))
    local startIndex = (state.editorShortcutPage - 1) * SHORTCUT_PICKER_PAGE_SIZE + 1
    state.editorShortcutRowIds = {}
    for row = 1, SHORTCUT_PICKER_PAGE_SIZE do
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
        setText(state.editorShortcutPageText, "Page " .. tostring(state.editorShortcutPage)
            .. " / " .. tostring(pageCount))
        setVisible(state.editorShortcutPageText, state.editorPickerOpen == true)
    end
    local showPaging = state.editorPickerOpen == true and pageCount > 1
    for _, widget in ipairs(state.editorShortcutPrevWidgets or {}) do setVisible(widget, showPaging) end
    for _, widget in ipairs(state.editorShortcutNextWidgets or {}) do setVisible(widget, showPaging) end
end

local function setPickerVisible(visible)
    state.editorPickerOpen = visible == true
    for _, widget in ipairs(state.editorPickerWidgets or {}) do
        setVisible(widget, visible == true)
    end
    updatePartyPickerPage()
    updateShortcutPickerPage()
end

local function setResetConfirmVisible(visible)
    state.editorResetConfirmOpen = visible == true
    for _, widget in ipairs(state.editorResetConfirmWidgets or {}) do
        setVisible(widget, visible == true)
    end
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
    for slotIndex = 1, TOTAL_ASSIGNMENT_SLOTS do
        updateEditorRow(slotIndex)
    end
    setPickerVisible(state.editorPickerOpen == true)
end

local function openAssignmentPicker(slotIndex)
    closeEditorDropdowns()
    setResetConfirmVisible(false)
    state.editorPickingSlot = slotIndex
    state.editorPartyPage = math.floor(clamp(
        state.editorPartyPage or 1, 1, partyPickerPageCount()))
    state.editorShortcutPage = math.floor(clamp(
        state.editorShortcutPage or 1, 1, shortcutPickerPageCount()))
    if alive(state.editorPickerTitle) then
        local pie = math.floor((slotIndex - 1) / PAGE_SIZE) + 1
        local localSlot = ((slotIndex - 1) % PAGE_SIZE) + 1
        setText(state.editorPickerTitle,
            string.format("Choose function for Wheel %s - Slot %02d",
                wheelRoman(pie), localSlot))
    end
    setPickerVisible(true)
end

local function closeAssignmentPicker()
    setPickerVisible(false)
    state.editorPickingSlot = nil
end

local function assignPickerChoice(catalogIndex)
    local slotIndex = state.editorPickingSlot
    local def = FUNCTION_CATALOG[catalogIndex]
    if slotIndex == nil or def == nil then return false end
    state.assignments[slotIndex] = def.id
    updateEditorRow(slotIndex)
    if alive(state.wheelPanel) then updateHighlight() end
    saveSettings()
    log("Editor assigned slot " .. tostring(slotIndex) .. " = " .. def.label, true)
    closeAssignmentPicker()
    return true
end

local function assignPickerChoiceById(id)
    local def = FUNCTION_BY_ID[id]
    local slotIndex = state.editorPickingSlot
    if slotIndex == nil or type(def) ~= "table" then return false end
    state.assignments[slotIndex] = def.id
    updateEditorRow(slotIndex)
    if alive(state.wheelPanel) then updateHighlight() end
    saveSettings()
    log("Editor assigned slot " .. tostring(slotIndex) .. " = " .. tostring(def.label), true)
    closeAssignmentPicker()
    return true
end

local function resetShortcutsToDefaults()
    if type(ShortcutActions) ~= "table" or type(ShortcutActions.reset) ~= "function" then
        log("Reset shortcuts failed: shortcut_actions.lua is unavailable", true)
        return false
    end
    local reloaded, resetError = ShortcutActions.reset(SHORTCUTS_PATH, {
        reservedIds = SHORTCUT_RESERVED_IDS,
    })
    if reloaded == nil then
        log("Reset shortcuts failed: " .. tostring(resetError), true)
        return false
    end
    shortcutData = reloaded
    rebuildFunctionCatalog(shortcutData, state.partyCatalogCapacity)
    local removed = 0
    for slotIndex = 1, TOTAL_ASSIGNMENT_SLOTS do
        local id = state.assignments[slotIndex]
        if type(id) ~= "string" or FUNCTION_BY_ID[id] == nil then
            state.assignments[slotIndex] = "empty"
            removed = removed + 1
        end
    end
    state.editorShortcutPage = 1
    closeAssignmentPicker()
    setResetConfirmVisible(false)
    refreshEditorRows()
    invalidateWheelPanel()
    updateShortcutPickerPage()
    saveSettings()
    log("Custom shortcuts reset to defaults"
        .. (removed > 0 and ("; " .. tostring(removed) .. " removed slot assignment(s) became Empty") or ""), true)
    return true
end

local function handleEditorClick(direction)
    if not state.editorOpen then return end
    local pc = state.pc
    local x, y = readMousePosition(pc)
    if x == nil or y == nil then return end

    if state.editorResetConfirmOpen then
        if direction < 0 or pointInRect(x, y, state.editorResetConfirmNoRect) then
            setResetConfirmVisible(false)
            return
        end
        if pointInRect(x, y, state.editorResetConfirmYesRect) then
            resetShortcutsToDefaults()
            return
        end
        return
    end

    if state.editorWheelCountDropdownOpen then
        for value, rect in pairs(state.editorWheelCountOptionRects or {}) do
            if pointInRect(x, y, rect) then
                state.activeWheelCount = math.floor(clamp(value, 1, PAGE_COUNT))
                if state.activePage > state.activeWheelCount then
                    state.activePage = state.activeWheelCount
                end
                updateEditorWheelCountText()
                closeEditorDropdowns()
                saveSettings()
                return
            end
        end
        closeEditorDropdowns()
    elseif state.editorCountDropdownOpen then
        local page = state.editorCountDropdownPage
        for value, rect in pairs((state.editorCountOptionRects or {})[page] or {}) do
            if pointInRect(x, y, rect) then
                state.visibleSlotCounts[page] = math.floor(clamp(value,
                    MIN_VISIBLE_SLOTS, MAX_VISIBLE_SLOTS))
                updateEditorCountText(page)
                invalidateWheelPanel()
                closeEditorDropdowns()
                saveSettings()
                return
            end
        end
        closeEditorDropdowns()
    elseif state.editorSkinDropdownOpen then
        for skin, rect in pairs(state.editorSkinOptionRects or {}) do
            if pointInRect(x, y, rect) then
                state.wheelSkin = validWheelSkin(skin)
                updateEditorSkinText()
                invalidateWheelPanel()
                closeEditorDropdowns()
                saveSettings()
                return
            end
        end
        closeEditorDropdowns()
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
        for catalogIndex, rect in ipairs(state.editorPickerRects or {}) do
            if pointInRect(x, y, rect) then
                assignPickerChoice(catalogIndex)
                return
            end
        end
        closeAssignmentPicker()
        return
    end

    if direction < 0 then return end
    if pointInRect(x, y, state.editorWheelCountDropdownRect) then
        setEditorDropdownVisible("count", false, nil)
        setEditorDropdownVisible("skin", false)
        setEditorDropdownVisible("wheelcount", true)
        return
    end

    for page = 1, PAGE_COUNT do
        if pointInRect(x, y, (state.editorCountDropdownRects or {})[page]) then
            setEditorDropdownVisible("wheelcount", false)
            setEditorDropdownVisible("skin", false)
            setEditorDropdownVisible("count", true, page)
            return
        end
    end
    if pointInRect(x, y, state.editorSkinDropdownRect) then
        setEditorDropdownVisible("count", false, nil)
        setEditorDropdownVisible("wheelcount", false)
        setEditorDropdownVisible("skin", true)
        return
    end
    if pointInRect(x, y, state.editorResetShortcutsRect) then
        closeEditorDropdowns()
        closeAssignmentPicker()
        setResetConfirmVisible(true)
        return
    end
    if pointInRect(x, y, state.editorSlowMotionRect) then
        config.slowMotionEnabled = cfg("slowMotionEnabled", true) ~= true
        updateEditorSlowMotionText()
        saveSettings()
        log("Slow motion setting changed to "
            .. (config.slowMotionEnabled and "ON" or "OFF"), true)
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

local function closeEditor(reason)
    if not state.editorOpen then return end
    state.editorOpen = false
    state.editorPickingSlot = nil
    closeEditorDropdowns()
    setPickerVisible(false)
    setResetConfirmVisible(false)
    setVisible(state.editorPanel, false)
    setVisible(state.widget, false)
    releaseCameraLock()
    restoreGameInput()
    restoreGameplayInput()
    restoreTimeDilation()
    log(reason or "Assignment editor closed", true)
end

local function openEditor(pc)
    if refreshPartyCapacity ~= nil then refreshPartyCapacity(true) end
    local allowed, reason = canOpenWheelDuringGameplay(pc)
    if not allowed then
        log("Editor not opened: " .. tostring(reason), true)
        return
    end

    if not buildEditorWidget(pc) then return end

    state.pc = pc
    state.editorOpen = true
    state.inputModeFailureLogged = false
    state.cameraLockFailureLogged = false
    setVisible(state.wheelPanel, false)
    refreshEditorRows()
    setVisible(state.editorPanel, true)
    saveCursorFlags(pc)
    setVisible(state.widget, true)
    applySlowMotion(pc)
    beginCameraLock(pc)
    blockEditorGameplayInput(pc)
    applyEditorInputMode(pc, true)
    centerHardwareCursor(pc)
    enforceCameraLock()
    log("Assignment editor opened with gameplay input disabled", true)
end

local function toggleEditor()
    if state.editorOpen then
        closeEditor(tostring(cfg("settingsKey") or "Settings key")
            .. " closed assignment editor")
    else
        openEditor(getPlayerController())
    end
end

local function updateSelectionFromCursor(pc, preserveSelectionInDeadzone)
    local mouseX, mouseY = readMousePosition(pc)
    if mouseX == nil or mouseY == nil then
        if not state.mouseReadFailureLogged then
            state.mouseReadFailureLogged = true
            log("Could not read UI cursor position; wheel remains open for G close", true)
        end
        return
    end

    local isKeyboardSession = state.controller == nil
        or not state.controller:isSession()

    if isKeyboardSession and state.keyboardMouseNeutralReady ~= true then
        state.selected = nil
        if state.callVisual ~= nil then
            local maxRadius = clamp(cfg("mouseMaxRadius", 220), 60, 800)
            local deadzone = clamp(cfg("mouseDeadzone", 42), 5, maxRadius - 5)
            state.callVisual("setDirection", nil, 0.0, deadzone)
        end
        return
    end

    local centerX = tonumber(cfg("centerX", 960)) or 960
    local centerY = tonumber(cfg("centerY", 540)) or 540
    if isKeyboardSession
        and state.keyboardMouseNeutralX ~= nil
        and state.keyboardMouseNeutralY ~= nil then
        centerX = state.keyboardMouseNeutralX
        centerY = state.keyboardMouseNeutralY
    end

    local dx = mouseX - centerX
    local dyUp = centerY - mouseY
    local magnitude = math.sqrt(dx * dx + dyUp * dyUp)
    local maxRadius = clamp(cfg("mouseMaxRadius", 220), 60, 800)

    local previous = state.selected
    local deadzone = clamp(cfg("mouseDeadzone", 42), 5, maxRadius - 5)

    if magnitude < deadzone then
        if preserveSelectionInDeadzone == true then
            return magnitude
        end
        state.selected = nil
        if state.callVisual ~= nil then
            state.callVisual("setDirection", nil, magnitude, deadzone)
        end
    else
        local angle = math.atan(dyUp, dx)
        if state.callVisual ~= nil then
            state.callVisual("setDirection", angle, magnitude, deadzone)
        end
        local bestIndex = nil
        local bestDistance = math.huge

        for index = 1, activeVisibleSlotCount() do
            local slotAngle = math.rad(tonumber(cfg("wheelSlotOneAngleDegrees", 180)) or 180)
                - ((index - 1) * TWO_PI / activeVisibleSlotCount())
            local distance = angularDistance(angle, slotAngle)
            if distance < bestDistance then
                bestDistance = distance
                bestIndex = index
            end
        end

        state.selected = bestIndex
    end

    if previous ~= state.selected then
        local def = state.selected ~= nil
            and assignmentDefinitionForVisibleIndex(state.selected) or nil
        previewAssignmentNatively(def, "mouse hover")
        updateHighlight()
    end
    return magnitude
end

local function closeWheel(reason)
    if not state.open then return end
    state.open = false
    state.openKeySawDown = false
    if state.controller ~= nil then state.controller:finish(state.pc) end
    if state.inputRuntime ~= nil then state.inputRuntime:finishKeyboard(state.pc) end
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
    setVisible(state.wheelPanel, false)
    setVisible(state.widget, false)
    if state.callVisual ~= nil then
        state.callVisual("setDirection", nil, 0.0, 1.0)
    end
    releaseCameraLock()
    restoreGameInput()
    restoreGameplayInput()
    restoreTimeDilation()
    log(reason or "Wheel hidden", true)
end

local function openWheel(pc, inputSource)
    if state.editorOpen then return false end
    if refreshPartyCapacity ~= nil then refreshPartyCapacity(true) end
    local allowed, reason = canOpenWheelDuringGameplay(pc)
    if not allowed then
        log("Wheel not opened: " .. tostring(reason), true)
        return false
    end

    if not alive(state.widget) or not alive(state.wheelPanel) then
        if not buildWidget(pc) then return false end
    end

    state.pc = pc
    state.open = true
    state.selected = nil
    state.lastActivated = nil
    state.openKeySawDown = inputSource ~= "controller"
    if inputSource ~= "controller" then state.keyboardOpenWasDown = true end
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

    saveCursorFlags(pc)
    updateHighlight()
    setVisible(state.editorPanel, false)
    setVisible(state.wheelPanel, true)
    setVisible(state.widget, true)
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
        refreshMovementKeysAllowedWhileOpen(pc)
        state.inputRuntime:beginKeyboard(pc)
        state.keyboardCancelWasDown = {}
        for _, input in ipairs(state.keyboardCancelInputs or {}) do
            state.keyboardCancelWasDown[input.name] = isKeyDown(pc, input.key)
        end
        centerHardwareCursor(pc)
    end
    enforcePageAimSuppression()
    enforceCameraLock()
    log("Dynamic wheel shown with " .. tostring(activeVisibleSlotCount())
        .. " sectors via " .. (inputSource == "controller" and "controller" or "keyboard"), true)
    return true
end

local function activateSelectedOption(trigger)
    if not state.open or state.selectionCommitted then return false end

    local selected = state.selected
    if selected == nil then
        log(tostring(trigger) .. " ignored: pointer is inside the centre deadzone", true)
        return false
    end

    local def = assignmentDefinitionForVisibleIndex(selected)
    if def == nil or def.kind == "empty" then
        log(tostring(trigger) .. " selected an empty slot", true)
        return false
    end

    state.selectionCommitted = true
    state.lastActivated = selected
    updateHighlight()

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
        if def.id == "mercy" then toggleMercyAccessory() end
        return true
    end

    if def.kind == "menu" then
        closeWheel("Menu assignment selected")
        scheduleAssignedMenu(def.id)
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
        local alreadyPreviewed = state.hoverPreviewKey
            == ("sphere:" .. tostring(def.sphereId))
        closeWheel("Sphere assignment selected")
        if not alreadyPreviewed then
            state.selectSphere(def, { source = "activation", notifyMissing = true })
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

state.controller = require("controller").new({
    cfg = cfg,
    state = state,
    alive = alive,
    makeFKey = makeFKey,
    isKeyDown = isKeyDown,
    clamp = clamp,
    angularDistance = angularDistance,
    visibleSlotCount = activeVisibleSlotCount,
    assignmentDefinitionForVisibleIndex = assignmentDefinitionForVisibleIndex,
    previewAssignmentNatively = previewAssignmentNatively,
    updateHighlight = updateHighlight,
    updatePointerDirection = function(angle, magnitude, deadzone)
        if state.callVisual ~= nil then
            state.callVisual("setDirection", angle, magnitude, deadzone)
        end
    end,
    switchActivePage = switchActivePage,
    setWheelInputSuppressed = state.setControllerWheelInputSuppressed,
    activateSelectedOption = activateSelectedOption,
    closeWheel = closeWheel,
    log = log,
    twoPi = TWO_PI,
    isWheelOpen = function() return state.open end,
    isEditorOpen = function() return state.editorOpen end,
    openControllerWheel = function(pc) return openWheel(pc, "controller") end,
})

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
    destroyWidget = destroyWidget,
    destroyCenterNotification = destroyCenterNotification,
    log = log,
})
state.openFKey = nil

function state.tick()
    processCenterNotification()

    if state.open and state.callVisual ~= nil then state.callVisual("tick") end

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
        if refreshGameUiState(pc, false) then
            closeEditor("Palworld screen opened; editor closed")
            return
        end
        if state.editorBuilder ~= nil then
            state.editorBuilder:step(cfg("editorBuildUnitsPerTick", 2))
        end
        applyEditorInputMode(pc, false)
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
            local keyboardPressed = keyboardDown
                and state.keyboardOpenWasDown ~= true
            state.keyboardOpenWasDown = keyboardDown
            if keyboardPressed and os.clock() >= state.keyboardOpenHandledAt then
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

state.interval = math.floor(clamp(cfg("pollIntervalMs", 40), 25, 150))
state.cameraLockInterval = math.floor(clamp(cfg("cameraLockIntervalMs", 16), 12, 50))
function state.fastTick()
    processSphereSelectionQueue()
    enforcePageAimSuppression()
    state.controller:updateReleaseGuards(state.pc)
    if not state.open and not state.editorOpen
        and not state.controller:isCameraNeutralGuardActive()
        and state.lockedRotation ~= nil then
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
log("v" .. tostring(cfg("version", "1.0"))
    .. " text wheel loaded. Hold " .. state.openKeyName
    .. " or controller " .. tostring(cfg("controllerOpenButton") or "")
    .. " for the hidden-cursor wheel; mouse/configured stick selects; "
    .. "inward stick return or open-button release activates the selected slot; "
    .. state.keyboardPageKeyName .. " or isolated "
    .. tostring(cfg("controllerPageButton") or "")
    .. " cycles Wheel I/II/III; other input is polled only while open and cancels without activation; "
    .. "controller actions stay muted until release and camera resumes after recentering; "
    .. state.settingsKeyName .. " opens the saved assignment editor; Pal, weapon, and sphere slots "
    .. "update Palworld's native HUD selection once per hover change; weapon slots 1-6 are assignable; "
    .. "the selected PalWheel skin supplies the circular background; Caps Lock is edge-polled before background work; the wheel uses adaptive dividers, a rotating direction ring, centre details, selected-text emphasis, and a short non-blocking reveal; F7 builds incrementally with slot-count, skin, and paged custom-shortcut selection; "
    .. "Saved\\shortcuts.tsv supplies configurable keyboard shortcut actions through PalworldKeyInjector; party capacity is detected from Palworld's party holder so expanded-party slots can be exposed dynamically; missing-sphere notices are background-free and expire after three seconds.", true)
