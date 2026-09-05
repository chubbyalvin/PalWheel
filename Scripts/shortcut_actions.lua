local Shortcuts = {}

local L = require("localization")
local function T(key, variables) return L.get(key, variables) end

local MAX_ACTIVE = 36
local MAX_DEFINITIONS = 256
local MAX_ID_LENGTH = 40
local MAX_LABEL_LENGTH = 20
local HEADER = { "id", "label", "key", "ctrl", "shift", "alt", "active" }

local Injector = require("palworld_keyinjector")
local FileStore = require("file_store")

local DEFAULT_ROWS = {
    { id = "kb_inventory", label = "INVENTORY", key = "I", ctrl = false, shift = false, alt = false, active = true },
    { id = "kb_party", label = "PARTY", key = "P", ctrl = false, shift = false, alt = false, active = true },
    { id = "kb_technology", label = "TECHNOLOGY", key = "T", ctrl = false, shift = false, alt = false, active = true },
    { id = "kb_build", label = "BUILD", key = "B", ctrl = false, shift = false, alt = false, active = true },
    { id = "kb_map", label = "MAP", key = "M", ctrl = false, shift = false, alt = false, active = true },
}


local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function utf8Length(value)
    value = tostring(value or "")
    if utf8 ~= nil and type(utf8.len) == "function" then
        local ok, length = pcall(utf8.len, value)
        if ok and length ~= nil then return length end
    end
    return #value
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

local function splitLines(text)
    local lines = {}
    text = tostring(text or "")
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        if string.sub(line, -1) == "\r" then line = string.sub(line, 1, -2) end
        lines[#lines + 1] = line
    end
    return lines
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

local function canonicalParts(canonical)
    local key, ctrl, shift, alt = nil, false, false, false
    for token in string.gmatch(tostring(canonical or ""), "[^+]+") do
        if token == "CTRL" then ctrl = true
        elseif token == "SHIFT" then shift = true
        elseif token == "ALT" then alt = true
        else key = token end
    end
    return key, ctrl, shift, alt
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

local function compactLabel(value)
    value = tostring(value or "")
    if utf8Length(value) <= 10 then return value end
    local characters = {}
    if utf8 ~= nil and type(utf8.codes) == "function"
        and type(utf8.char) == "function" then
        local ok = pcall(function()
            for _, code in utf8.codes(value) do
                characters[#characters + 1] = utf8.char(code)
            end
        end)
        if not ok then characters = {} end
    end
    if #characters == 0 then
        for index = 1, #value do characters[index] = string.sub(value, index, index) end
    end
    local splitAt = nil
    for index = math.min(11, #characters), 2, -1 do
        if characters[index] == " " then
            splitAt = index
            break
        end
    end
    if splitAt == nil then
        for index = 12, #characters do
            if characters[index] == " " then
                splitAt = index
                break
            end
        end
    end
    if splitAt ~= nil then
        return trim(table.concat(characters, "", 1, splitAt - 1)) .. "\n"
            .. trim(table.concat(characters, "", splitAt + 1))
    end
    return table.concat(characters, "", 1, 10) .. "\n"
        .. table.concat(characters, "", 11)
end

local function copyRow(source)
    return {
        id = tostring(source.id or ""),
        label = tostring(source.label or ""),
        key = tostring(source.key or ""),
        ctrl = source.ctrl,
        shift = source.shift,
        alt = source.alt,
        active = source.active,
        sourceLine = source.sourceLine,
        originalId = source.originalId or source.id,
        rawColumnCount = source.rawColumnCount,
    }
end

local function makeRows()
    local rows = {}
    for index, source in ipairs(DEFAULT_ROWS) do
        local row = copyRow(source)
        row.sourceLine = index + 1
        row.originalId = row.id
        rows[index] = row
    end
    return rows
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

local function readText(path)
    return FileStore.readText(path)
end

local function writeTextAtomic(path, text, options)
    return FileStore.writeText(path, text, options)
end

local function serializeRows(rows)
    local lines = { table.concat(HEADER, "\t") }
    for _, row in ipairs(rows or {}) do
        lines[#lines + 1] = table.concat({
            trim(row.id), trim(row.label), trim(row.key),
            tostring(row.ctrl == true), tostring(row.shift == true),
            tostring(row.alt == true), tostring(row.active == true),
        }, "\t")
    end
    lines[#lines + 1] = ""
    return table.concat(lines, "\r\n")
end

local function draftFromText(text)
    local lines = splitLines(text)
    local rows = {}
    for lineNumber = 2, #lines do
        local line = lines[lineNumber]
        if trim(line) ~= "" then
            local fields = splitTabs(line)
            rows[#rows + 1] = {
                id = trim(fields[1]),
                label = trim(fields[2]),
                key = trim(fields[3]),
                ctrl = parseBool(fields[4]),
                shift = parseBool(fields[5]),
                alt = parseBool(fields[6]),
                active = parseBool(fields[7]),
                sourceLine = lineNumber,
                originalId = trim(fields[1]),
                rawColumnCount = #fields,
            }
        end
    end
    return { rows = rows, sourceText = tostring(text or ""),
        headerValid = validateHeader(lines[1]) }
end

local function reservedSet(values)
    local result = {}
    for id, reserved in pairs(values or {}) do
        if reserved == true then result[string.lower(trim(id))] = true end
    end
    return result
end

local function controlSet(values)
    local result = {}
    for _, value in ipairs(values or {}) do
        local request = Injector.parse(tostring(value or ""))
        if request ~= nil then
            local key = canonicalParts(request.canonical)
            if key ~= nil then result[key] = tostring(value) end
        end
    end
    return result
end

local function makeError(rowIndex, sourceLine, message)
    return { row = rowIndex, line = sourceLine or rowIndex + 1, message = message }
end

local function definitionsFromRows(rows, warnings)
    local definitions, active = {}, {}
    local activeOverflow = 0
    for index, row in ipairs(rows) do
        local request = assert(Injector.parse(composeSpec(row.key, row.ctrl, row.shift, row.alt)))
        local display = displaySpec(request.canonical)
        local def = {
            id = row.id, label = row.label, short = compactLabel(row.label), kind = "shortcut",
            shortcutSpec = request.canonical, shortcutDisplay = display,
            detail = row.active and display or T("inactiveShortcutDetail", { binding = display }),
            active = row.active, sourceLine = row.sourceLine or index + 1,
            key = row.key, ctrl = row.ctrl, shift = row.shift, alt = row.alt,
        }
        definitions[#definitions + 1] = def
        if row.active then
            if #active < MAX_ACTIVE then active[#active + 1] = def
            else activeOverflow = activeOverflow + 1 end
        end
    end
    if activeOverflow > 0 then
        warnings[#warnings + 1] = T("shortcutActiveLimitWarning", {
            count = activeOverflow, limit = MAX_ACTIVE })
    end
    return definitions, active
end

function Shortcuts.readDraft(path)
    local text, why = readText(path)
    if text == nil then return nil, why end
    return draftFromText(text)
end

function Shortcuts.validateRows(rows, options)
    options = options or {}
    local errors, warnings, normalized = {}, {}, {}
    local seenIds, seenSpecs = {}, {}
    local reserved = reservedSet(options.reservedIds)
    local controls = controlSet(options.controlKeys)
    if options.headerValid == false then
        errors[#errors + 1] = makeError(0, 1,
            T("shortcutHeaderRequired", { header = table.concat(HEADER, " TAB ") }))
    end
    if #(rows or {}) > MAX_DEFINITIONS then
        errors[#errors + 1] = makeError(MAX_DEFINITIONS + 1,
            MAX_DEFINITIONS + 2, T("shortcutDefinitionLimit", { limit = MAX_DEFINITIONS }))
    end
    for index, source in ipairs(rows or {}) do
        local row = copyRow(source)
        row.id, row.label, row.key = trim(row.id), trim(row.label), trim(row.key)
        row.sourceLine = row.sourceLine or index + 1
        row.originalId = source.originalId or source.id
        local rejection = nil
        if row.rawColumnCount ~= nil and row.rawColumnCount ~= 7 then
            rejection = T("shortcutColumnsExpected", { count = row.rawColumnCount })
        elseif row.id == "" or not string.match(row.id, "^[A-Za-z0-9_-]+$") then
            rejection = T("shortcutIdCharacters")
        elseif #row.id > MAX_ID_LENGTH then
            rejection = T("shortcutIdTooLong", { limit = MAX_ID_LENGTH })
        elseif string.match(string.lower(row.id), "^pal%d+$") then
            rejection = T("shortcutPartyIdConflict", { id = row.id })
        elseif reserved[string.lower(row.id)] then
            rejection = T("shortcutActionIdConflict", { id = row.id })
        elseif seenIds[string.lower(row.id)] ~= nil then
            rejection = T("shortcutDuplicateId", { id = row.id })
        elseif row.label == "" then
            rejection = T("shortcutLabelBlank")
        elseif utf8Length(row.label) > MAX_LABEL_LENGTH then
            rejection = T("shortcutLabelTooLong", { limit = MAX_LABEL_LENGTH })
        elseif string.find(row.label, "\t", 1, true)
            or string.find(row.label, "\r", 1, true)
            or string.find(row.label, "\n", 1, true) then
            rejection = T("shortcutLabelLineBreak")
        elseif row.key == "" then
            rejection = T("shortcutKeyBlank")
        elseif type(row.ctrl) ~= "boolean" or type(row.shift) ~= "boolean"
            or type(row.alt) ~= "boolean" or type(row.active) ~= "boolean" then
            rejection = T("shortcutBooleanFields")
        end
        local request, parseError
        if rejection == nil then
            request, parseError = Injector.parse(composeSpec(row.key, row.ctrl, row.shift, row.alt))
            if request == nil then rejection = tostring(parseError) end
        end
        if rejection == nil then
            local primary, ctrl, shift, alt = canonicalParts(request.canonical)
            
            
            
            if row.active == true and not ctrl and not shift and not alt
                and controls[primary] ~= nil then
                rejection = T("shortcutControlKeyConflict", { binding = request.canonical })
            end
        end
        if rejection ~= nil then
            errors[#errors + 1] = makeError(index, row.sourceLine, rejection)
        else
            seenIds[string.lower(row.id)] = index
            local earlier = seenSpecs[request.canonical]
            if earlier ~= nil then
                warnings[#warnings + 1] = T("shortcutDuplicateBinding", {
                    first = earlier, second = index, binding = request.canonical })
            else
                seenSpecs[request.canonical] = index
            end
            local primary, ctrl, shift, alt = canonicalParts(request.canonical)
            row.key, row.ctrl, row.shift, row.alt = primary, ctrl, shift, alt
            normalized[#normalized + 1] = row
        end
    end
    if #errors > 0 then return nil, errors, warnings end
    local definitions, active = definitionsFromRows(normalized, warnings)
    return { rows = normalized, definitions = definitions, active = active,
        notes = {}, usingDefaults = false }, errors, warnings
end

local function notesForValidation(errors, warnings)
    local notes = {}
    for _, entry in ipairs(errors or {}) do
        notes[#notes + 1] = T("shortcutRejectedNote", {
            line = entry.line, message = entry.message })
    end
    for _, warning in ipairs(warnings or {}) do
        notes[#notes + 1] = T("shortcutWarningNote", { message = warning })
    end
    return notes
end

local function loadValidatedText(text, options)
    local draft = draftFromText(text)
    local data, errors, warnings = Shortcuts.validateRows(draft.rows, {
        reservedIds = options.reservedIds, controlKeys = options.controlKeys,
        headerValid = draft.headerValid,
    })
    if data ~= nil then
        data.sourceText, data.headerValid = draft.sourceText, true
        data.notes = notesForValidation({}, warnings)
    end
    return data, errors, warnings, draft
end

local function fallbackData(options)
    local attempts = { makeRows(), {} }
    local controls = controlSet(options.controlKeys)
    for _, rows in ipairs(attempts) do
        for _, row in ipairs(rows) do
            if row.active == true then
                local request = Injector.parse(composeSpec(
                    row.key, row.ctrl, row.shift, row.alt))
                local primary = request ~= nil and canonicalParts(request.canonical) or nil
                if primary ~= nil and controls[primary] ~= nil then row.active = false end
            end
        end
        local data = Shortcuts.validateRows(rows, options)
        if data ~= nil then return data end
    end
    return {
        rows = {}, definitions = {}, active = {}, notes = {},
        usingDefaults = true, fileInvalid = true,
    }
end

function Shortcuts.load(path, options)
    options = options or {}
    local text, why = readText(path)
    if text == nil then
        local defaults = fallbackData(options)
        local defaultText = serializeRows(defaults.rows)
        local created, createError = writeTextAtomic(path, defaultText)
        if created then text = defaultText
        else
            local data = defaults
            data.usingDefaults, data.fileInvalid = true, true
            data.notes = { T("shortcutCannotCreateFile", {
                reason = createError or why }) }
            return data
        end
    end
    local data, errors, warnings = loadValidatedText(text, options)
    if data ~= nil then
        data.notes[#data.notes + 1] = T("shortcutLoadedSummary", {
            defined = #data.definitions, active = #data.active })
        if options.lastGoodPath ~= nil then
            local ok, writeError = writeTextAtomic(options.lastGoodPath, serializeRows(data.rows))
            if not ok then
                data.notes[#data.notes + 1] = T("shortcutLastGoodUpdateFailed", {
                    reason = writeError })
            end
        end
        return data
    end
    local failureNotes = notesForValidation(errors, warnings)
    failureNotes[#failureNotes + 1] = T("shortcutInvalidUseLastGood")
    if options.lastGoodPath ~= nil then
        local backupText = readText(options.lastGoodPath)
        if backupText ~= nil then
            local backup = loadValidatedText(backupText, options)
            if backup ~= nil then
                backup.fileInvalid, backup.usingLastGood = true, true
                backup.notes = failureNotes
                backup.notes[#backup.notes + 1] = T("shortcutUsingLastGood")
                return backup
            end
        end
    end
    local fallback = fallbackData(options)
    fallback.fileInvalid, fallback.usingDefaults = true, true
    fallback.notes = failureNotes
    fallback.notes[#fallback.notes + 1] = T("shortcutNoValidBackup")
    return fallback
end

function Shortcuts.saveRows(path, rows, options)
    options = options or {}
    local current, readError = readText(path)
    if current == nil then return nil, tostring(readError) end
    if options.expectedText ~= nil and current ~= options.expectedText then
        return nil, T("shortcutChangedOutside")
    end
    local data, errors, warnings = Shortcuts.validateRows(rows, options)
    if data == nil then return nil, T("validationFailed"), false, errors, warnings end
    local text = serializeRows(data.rows)
    local ok, why = writeTextAtomic(path, text, { expectedText = current })
    if not ok then return nil, tostring(why), false, errors, warnings end
    if options.lastGoodPath ~= nil then
        local backupOk, backupError = writeTextAtomic(options.lastGoodPath, text)
        if not backupOk then
            warnings[#warnings + 1] = T("shortcutLastGoodCopyFailed", {
                reason = backupError })
        end
    end
    data.sourceText = text
    data.notes = notesForValidation({}, warnings)
    return data, nil, current ~= text, errors, warnings
end

function Shortcuts.update(path, changes, options)
    options = options or {}
    if type(changes) ~= "table" then return nil, T("shortcutChangesInvalid") end
    local draft, why = Shortcuts.readDraft(path)
    if draft == nil then return nil, tostring(why) end
    if not draft.headerValid then return nil, T("shortcutHeaderInvalid") end
    local remaining = {}
    for id in pairs(changes) do remaining[id] = true end
    local changed = false
    for _, row in ipairs(draft.rows) do
        local requested = changes[row.id]
        if requested ~= nil then
            local spec = requested.spec
            if spec == nil then spec = composeSpec(row.key, row.ctrl == true,
                row.shift == true, row.alt == true) end
            local parsed, parseError = Injector.parse(spec)
            if parsed == nil then return nil, row.id .. ": " .. tostring(parseError) end
            local key, ctrl, shift, alt = canonicalParts(parsed.canonical)
            row.key, row.ctrl, row.shift, row.alt = key, ctrl, shift, alt
            if requested.active ~= nil then
                if type(requested.active) ~= "boolean" then
                    return nil, row.id .. ": " .. T("shortcutActiveBoolean")
                end
                row.active = requested.active
            end
            remaining[row.id], changed = nil, true
        end
    end
    for id in pairs(remaining) do
        return nil, T("shortcutIdNotFound", { id = id })
    end
    if not changed then return Shortcuts.load(path, options), nil, false end
    options.expectedText = draft.sourceText
    return Shortcuts.saveRows(path, draft.rows, options)
end

function Shortcuts.reset(path, options)
    options = options or {}
    options.expectedText = readText(path)
    return Shortcuts.saveRows(path, makeRows(), options)
end

function Shortcuts.primaryConflict(data, name)
    local request = Injector.parse(tostring(name or ""))
    if request == nil then return nil end
    local primary = canonicalParts(request.canonical)
    for _, def in ipairs((data and data.definitions) or {}) do
        local defPrimary, ctrl, shift, alt = canonicalParts(def.shortcutSpec)
        if def.active == true and not ctrl and not shift and not alt
            and defPrimary == primary then
            return def
        end
    end
    return nil
end

function Shortcuts.defaultRows() return makeRows() end
function Shortcuts.defaultsText() return serializeRows(makeRows()) end
function Shortcuts.readSourceText(path) return readText(path) end
function Shortcuts.restoreText(path, text, expectedText, lastGoodPath)
    local ok, why = writeTextAtomic(path, text, { expectedText = expectedText })
    if not ok then return false, why end
    if lastGoodPath ~= nil then
        local backupOk, backupError = writeTextAtomic(lastGoodPath, text)
        if not backupOk then
            return true, T("shortcutRestoreBackupFailed", { reason = backupError })
        end
    end
    return true
end
function Shortcuts.displaySpec(value)
    local request = Injector.parse(value)
    return request ~= nil and displaySpec(request.canonical) or tostring(value or "")
end
function Shortcuts.maxActive() return MAX_ACTIVE end
function Shortcuts.maxDefinitions() return MAX_DEFINITIONS end
function Shortcuts.maxLabelLength() return MAX_LABEL_LENGTH end
function Shortcuts.maxIdLength() return MAX_ID_LENGTH end

return Shortcuts
