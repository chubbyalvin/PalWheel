local Shortcuts = {}

local MAX_ACTIVE = 36
local MAX_DEFINITIONS = 256
local HEADER = { "id", "label", "key", "ctrl", "shift", "alt", "active" }

local Injector = require("palworld_keyinjector")

local DEFAULT_ROWS = {
    { "character", "Character", "TAB", false, false, false, true },
    { "inventory", "Inventory", "I", false, false, false, true },
    { "party", "Party", "P", false, false, false, true },
    { "technology", "Technology", "T", false, false, false, true },
    { "build", "Build", "B", false, false, false, true },
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function splitTabs(line)
    local values = {}
    local startAt = 1
    while true do
        local tabAt = string.find(line, "\t", startAt, true)
        if tabAt == nil then
            values[#values + 1] = string.sub(line, startAt)
            break
        end
        values[#values + 1] = string.sub(line, startAt, tabAt - 1)
        startAt = tabAt + 1
    end
    return values
end

local function parseBool(value)
    local normalized = string.lower(trim(value))
    if normalized == "true" then return true end
    if normalized == "false" then return false end
    return nil
end

local function composeSpec(key, ctrl, shift, alt)
    local parts = {}
    if ctrl then parts[#parts + 1] = "CTRL" end
    if shift then parts[#parts + 1] = "SHIFT" end
    if alt then parts[#parts + 1] = "ALT" end
    parts[#parts + 1] = trim(key)
    return table.concat(parts, "+")
end

local function displaySpec(canonical)
    local parts = {}
    for token in string.gmatch(tostring(canonical or ""), "[^+]+") do
        local friendly = token
        if token == "CTRL" then friendly = "Ctrl"
        elseif token == "SHIFT" then friendly = "Shift"
        elseif token == "ALT" then friendly = "Alt"
        elseif token == "CAPS_LOCK" then friendly = "Caps Lock"
        elseif token == "PAGE_UP" then friendly = "Page Up"
        elseif token == "PAGE_DOWN" then friendly = "Page Down"
        elseif token == "BACKSPACE" then friendly = "Backspace"
        elseif token == "ESCAPE" then friendly = "Esc"
        elseif token == "ENTER" then friendly = "Enter"
        elseif token == "SPACE" then friendly = "Space"
        elseif token == "LEFT" then friendly = "Left"
        elseif token == "RIGHT" then friendly = "Right"
        elseif token == "UP" then friendly = "Up"
        elseif token == "DOWN" then friendly = "Down"
        else friendly = string.gsub(token, "_", " ") end
        parts[#parts + 1] = friendly
    end
    return table.concat(parts, " + ")
end

local function makeRows(legacyKeys)
    local rows = {}
    for index, source in ipairs(DEFAULT_ROWS) do
        local row = {}
        for column = 1, #source do row[column] = source[column] end
        if type(legacyKeys) == "table" and legacyKeys[row[1]] ~= nil then
            row[3] = tostring(legacyKeys[row[1]])
        end
        rows[index] = row
    end
    return rows
end

local function serializeRows(rows)
    local lines = { table.concat(HEADER, "\t") }
    for _, row in ipairs(rows) do
        lines[#lines + 1] = table.concat({
            tostring(row[1]), tostring(row[2]), tostring(row[3]),
            tostring(row[4] == true), tostring(row[5] == true),
            tostring(row[6] == true), tostring(row[7] == true),
        }, "\t")
    end
    lines[#lines + 1] = ""
    return table.concat(lines, "\r\n")
end

local function writeTextAtomic(path, text)
    if io == nil or type(io.open) ~= "function" then
        return false, "Lua file I/O is unavailable"
    end
    local temporary = path .. ".tmp"
    local file, openError = io.open(temporary, "wb")
    if file == nil then return false, tostring(openError) end
    local ok, writeError = pcall(function()
        file:write(text)
        file:flush()
    end)
    pcall(function() file:close() end)
    if not ok then
        pcall(os.remove, temporary)
        return false, tostring(writeError)
    end
    pcall(os.remove, path)
    local renamed, renameError = os.rename(temporary, path)
    if not renamed then
        pcall(os.remove, temporary)
        return false, tostring(renameError)
    end
    return true
end

local function defaultData(legacyKeys, note)
    local rows = makeRows(legacyKeys)
    local definitions, active = {}, {}
    for index, row in ipairs(rows) do
        local request, parseError = Injector.parse(composeSpec(row[3], row[4], row[5], row[6]))
        if request ~= nil then
            local def = {
                id = row[1], label = row[2], short = row[2], kind = "shortcut",
                shortcutSpec = request.canonical,
                shortcutDisplay = displaySpec(request.canonical),
                detail = displaySpec(request.canonical), active = true,
                sourceLine = index + 1,
            }
            definitions[#definitions + 1] = def
            active[#active + 1] = def
        elseif note ~= nil then
            note("Default shortcut " .. tostring(row[1]) .. " ignored: " .. tostring(parseError))
        end
    end
    return definitions, active
end

local function validateHeader(line)
    line = tostring(line or "")
    if string.sub(line, 1, 3) == "\239\187\191" then line = string.sub(line, 4) end
    local fields = splitTabs(line)
    if #fields ~= #HEADER then return false end
    for index, expected in ipairs(HEADER) do
        if string.lower(trim(fields[index])) ~= expected then return false end
    end
    return true
end

function Shortcuts.load(path, options)
    options = options or {}
    local notes = {}
    local function note(message) notes[#notes + 1] = tostring(message) end
    local reserved = options.reservedIds or {}
    local legacyKeys = options.legacyKeys

    if io == nil or type(io.open) ~= "function" then
        note("shortcuts.tsv unavailable: Lua file I/O is unavailable; using defaults in memory")
        local definitions, active = defaultData(legacyKeys, note)
        return { definitions = definitions, active = active, notes = notes, usingDefaults = true }
    end

    local file = io.open(path, "rb")
    if file == nil then
        local ok, writeError = writeTextAtomic(path, serializeRows(makeRows(legacyKeys)))
        if ok then
            note("Created Saved\\shortcuts.tsv")
            file = io.open(path, "rb")
        else
            note("Could not create shortcuts.tsv: " .. tostring(writeError) .. "; using defaults in memory")
            local definitions, active = defaultData(legacyKeys, note)
            return { definitions = definitions, active = active, notes = notes, usingDefaults = true }
        end
    end

    local lines = {}
    for line in file:lines() do lines[#lines + 1] = line end
    pcall(function() file:close() end)

    if not validateHeader(lines[1]) then
        note("shortcuts.tsv header is invalid; existing file was left unchanged and defaults are being used")
        local definitions, active = defaultData(legacyKeys, note)
        return { definitions = definitions, active = active, notes = notes, usingDefaults = true, headerInvalid = true }
    end

    local definitions, active = {}, {}
    local seen = {}
    local validCount = 0
    local activeOverflow = 0

    for lineNumber = 2, #lines do
        local line = lines[lineNumber]
        if trim(line) ~= "" then
            if validCount >= MAX_DEFINITIONS then
                note("shortcuts.tsv definition limit reached (" .. tostring(MAX_DEFINITIONS) .. "); remaining rows were ignored")
                break
            end

            local fields = splitTabs(line)
            local rejection = nil
            if #fields ~= 7 then
                rejection = "expected 7 tab-separated columns, found " .. tostring(#fields)
            end

            local id, label, key
            local ctrl, shift, alt, enabled
            if rejection == nil then
                id, label, key = trim(fields[1]), trim(fields[2]), trim(fields[3])
                ctrl, shift, alt, enabled = parseBool(fields[4]), parseBool(fields[5]), parseBool(fields[6]), parseBool(fields[7])
                if id == "" or not string.match(id, "^[A-Za-z0-9_-]+$") then
                    rejection = "id must contain only letters, numbers, underscore, or hyphen"
                elseif reserved[id] == true then
                    rejection = "id conflicts with a PalWheel action: " .. id
                elseif seen[id] then
                    rejection = "duplicate id: " .. id
                elseif label == "" then
                    rejection = "label is blank"
                elseif key == "" then
                    rejection = "key is blank"
                elseif ctrl == nil or shift == nil or alt == nil or enabled == nil then
                    rejection = "ctrl, shift, alt, and active must be true or false"
                end
            end

            local request, parseError
            if rejection == nil then
                request, parseError = Injector.parse(composeSpec(key, ctrl, shift, alt))
                if request == nil then rejection = tostring(parseError) end
            end

            if rejection ~= nil then
                note("shortcuts.tsv line " .. tostring(lineNumber) .. " rejected: " .. rejection)
            else
                seen[id] = true
                validCount = validCount + 1
                local display = displaySpec(request.canonical)
                local def = {
                    id = id,
                    label = label,
                    short = label,
                    kind = "shortcut",
                    shortcutSpec = request.canonical,
                    shortcutDisplay = display,
                    detail = enabled and display or ("INACTIVE - " .. display),
                    active = enabled,
                    sourceLine = lineNumber,
                }
                definitions[#definitions + 1] = def
                if enabled then
                    if #active < MAX_ACTIVE then
                        active[#active + 1] = def
                    else
                        activeOverflow = activeOverflow + 1
                    end
                end
            end
        end
    end

    if activeOverflow > 0 then
        note("Custom shortcut active limit reached (" .. tostring(MAX_ACTIVE) .. "); "
            .. tostring(activeOverflow) .. " later active shortcut(s) remain defined but are not selectable")
    end
    note("Loaded " .. tostring(#definitions) .. " valid shortcut definition(s); "
        .. tostring(#active) .. " active/selectable")

    return { definitions = definitions, active = active, notes = notes, usingDefaults = false }
end

function Shortcuts.reset(path, options)
    options = options or {}
    local ok, writeError = writeTextAtomic(path, serializeRows(makeRows(nil)))
    if not ok then return nil, tostring(writeError) end
    return Shortcuts.load(path, { reservedIds = options.reservedIds or {} })
end

function Shortcuts.defaultsText()
    return serializeRows(makeRows(nil))
end

function Shortcuts.maxActive()
    return MAX_ACTIVE
end

return Shortcuts
