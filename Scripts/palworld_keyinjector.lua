local Module = {}
local Client = {}
Client.__index = Client

local L = require("localization")
local function T(key, variables) return L.get(key, variables) end

local KEYS = {}
for code = string.byte("A"), string.byte("Z") do
    local name = string.char(code)
    KEYS[name] = string.lower(name)
end
for digit = 0, 9 do
    KEYS[tostring(digit)] = tostring(digit)
    KEYS["NUMPAD_" .. tostring(digit)] = "numpad_" .. tostring(digit)
end
for number = 1, 24 do
    KEYS["F" .. tostring(number)] = "f" .. tostring(number)
end

local NAMED_KEYS = {
    GRAVE = "grave",
    MINUS = "minus",
    EQUALS = "equals",
    LEFT_BRACKET = "left_bracket",
    RIGHT_BRACKET = "right_bracket",
    BACKSLASH = "backslash",
    SEMICOLON = "semicolon",
    APOSTROPHE = "apostrophe",
    COMMA = "comma",
    PERIOD = "period",
    SLASH = "slash",
    SPACE = "space",
    TAB = "tab",
    ENTER = "enter",
    BACKSPACE = "backspace",
    ESCAPE = "escape",
    CAPS_LOCK = "caps_lock",
    UP = "up",
    DOWN = "down",
    LEFT = "left",
    RIGHT = "right",
    INSERT = "insert",
    DELETE = "delete",
    HOME = "home",
    END = "end",
    PAGE_UP = "page_up",
    PAGE_DOWN = "page_down",
    NUMPAD_ADD = "numpad_add",
    NUMPAD_SUBTRACT = "numpad_subtract",
    NUMPAD_MULTIPLY = "numpad_multiply",
    NUMPAD_DIVIDE = "numpad_divide",
    NUMPAD_DECIMAL = "numpad_decimal",
    NUMPAD_ENTER = "numpad_enter",
}
for name, token in pairs(NAMED_KEYS) do KEYS[name] = token end

local ALIASES = {
    RETURN = "ENTER",
    ESC = "ESCAPE",
    TILDE = "GRAVE",
    HYPHEN = "MINUS",
    EQUAL = "EQUALS",
    LEFT_ARROW = "LEFT",
    RIGHT_ARROW = "RIGHT",
    UP_ARROW = "UP",
    DOWN_ARROW = "DOWN",
    INS = "INSERT",
    DEL = "DELETE",
    PAGEUP = "PAGE_UP",
    PAGEDOWN = "PAGE_DOWN",
    PGUP = "PAGE_UP",
    PGDN = "PAGE_DOWN",
    ADD = "NUMPAD_ADD",
    SUBTRACT = "NUMPAD_SUBTRACT",
    MULTIPLY = "NUMPAD_MULTIPLY",
    DIVIDE = "NUMPAD_DIVIDE",
    DECIMAL = "NUMPAD_DECIMAL",
}

local FORBIDDEN_MODIFIERS = {
    WIN = true, WINDOWS = true, LWIN = true, RWIN = true,
    META = true, SUPER = true,
}

local function normalize_key(value)
    local key = string.upper(tostring(value or "")):gsub("^KEY_", "")
    key = ALIASES[key] or key
    if string.match(key, "^NUMPAD%d$") then
        key = "NUMPAD_" .. string.sub(key, -1)
    end
    return key
end

local function blocked_combination(key, ctrl, shift, alt)
    if alt and key == "F4" then return T("shortcutBlocked", { binding = "ALT+F4" }) end
    if alt and key == "TAB" then return T("shortcutBlocked", { binding = "ALT+TAB" }) end
    if alt and key == "ESCAPE" then return T("shortcutBlocked", { binding = "ALT+ESCAPE" }) end
    if alt and key == "SPACE" then return T("shortcutBlocked", { binding = "ALT+SPACE" }) end
    if ctrl and shift and key == "ESCAPE" then
        return T("shortcutBlocked", { binding = "CTRL+SHIFT+ESCAPE" })
    end
    if ctrl and key == "ESCAPE" then return T("shortcutBlocked", { binding = "CTRL+ESCAPE" }) end
    if ctrl and alt and key == "DELETE" then
        return T("shortcutBlocked", { binding = "CTRL+ALT+DELETE" })
    end
    return nil
end

local function parse_specification(specification)
    local text = string.upper(tostring(specification or ""))
    text = text:gsub("%s+", "")
    if text == "" then return nil, T("shortcutEmpty") end

    local ctrl, shift, alt = false, false, false
    local key = nil
    local part_count = 0
    for part in string.gmatch(text, "[^+]+") do
        part_count = part_count + 1
        if part == "CTRL" or part == "CONTROL" then
            if ctrl then return nil, T("modifierRepeated", { modifier = "CTRL" }) end
            ctrl = true
        elseif part == "SHIFT" then
            if shift then return nil, T("modifierRepeated", { modifier = "SHIFT" }) end
            shift = true
        elseif part == "ALT" then
            if alt then return nil, T("modifierRepeated", { modifier = "ALT" }) end
            alt = true
        elseif FORBIDDEN_MODIFIERS[part] then
            return nil, T("windowsKeyUnsupported")
        else
            if key ~= nil then
                return nil, T("oneOrdinaryKeyAllowed")
            end
            key = normalize_key(part)
        end
    end

    if part_count == 0 or key == nil then
        return nil, T("oneOrdinaryKeyRequired")
    end
    local key_token = KEYS[key]
    if key_token == nil then
        return nil, T("unsupportedKey", { key = key })
    end
    local blocked = blocked_combination(key, ctrl, shift, alt)
    if blocked ~= nil then return nil, blocked end

    local modifier_token = "none"
    if ctrl and shift and alt then modifier_token = "ctrl_shift_alt"
    elseif ctrl and shift then modifier_token = "ctrl_shift"
    elseif ctrl and alt then modifier_token = "ctrl_alt"
    elseif shift and alt then modifier_token = "shift_alt"
    elseif ctrl then modifier_token = "ctrl"
    elseif shift then modifier_token = "shift"
    elseif alt then modifier_token = "alt"
    end

    local canonical = {}
    if ctrl then canonical[#canonical + 1] = "CTRL" end
    if shift then canonical[#canonical + 1] = "SHIFT" end
    if alt then canonical[#canonical + 1] = "ALT" end
    canonical[#canonical + 1] = key
    return {
        canonical = table.concat(canonical, "+"),
        modifierToken = modifier_token,
        keyToken = key_token,
    }
end

local function default_dll_path()
    if debug == nil or type(debug.getinfo) ~= "function" then
        return "PalworldKeyInjector.dll"
    end
    local ok, info = pcall(debug.getinfo, 1, "S")
    if not ok or type(info) ~= "table" or type(info.source) ~= "string" then
        return "PalworldKeyInjector.dll"
    end
    local source = info.source
    if string.sub(source, 1, 1) == "@" then source = string.sub(source, 2) end
    local directory = source:gsub("/", "\\"):match("^(.+)\\[^\\]+$")
    return directory and (directory .. "\\PalworldKeyInjector.dll")
        or "PalworldKeyInjector.dll"
end

function Client:load_symbol(symbol)
    if self.cache[symbol] ~= nil then
        return self.cache[symbol], self.errors[symbol]
    end
    local loader, load_error = package.loadlib(self.dllPath, symbol)
    if type(loader) ~= "function" then
        self.cache[symbol] = false
        self.errors[symbol] = tostring(load_error or "unknown DLL load error")
        return nil, self.errors[symbol]
    end
    self.cache[symbol] = loader
    return loader
end

function Client:inject(specification)
    local request, parse_error = parse_specification(specification)
    if request == nil then return false, parse_error end

    local reset, reset_error = self:load_symbol("palworld_mod_none")
    if type(reset) ~= "function" then return false, reset_error end
    local modifier, modifier_error = self:load_symbol(
        "palworld_mod_" .. request.modifierToken)
    if type(modifier) ~= "function" then return false, modifier_error end
    local inject, inject_error = self:load_symbol(
        "palworld_inject_" .. request.keyToken)
    if type(inject) ~= "function" then return false, inject_error end

    local ok, call_error = pcall(reset)
    if not ok then return false, tostring(call_error) end
    if request.modifierToken ~= "none" then
        ok, call_error = pcall(modifier)
        if not ok then
            pcall(reset)
            return false, tostring(call_error)
        end
    end
    ok, call_error = pcall(inject)
    if not ok then
        pcall(reset)
        return false, tostring(call_error)
    end
    return true, request.canonical
end

function Module.new(dll_path)
    if package == nil or type(package.loadlib) ~= "function" then
        return nil, T("luaLoadlibUnavailable")
    end
    local client = setmetatable({
        dllPath = tostring(dll_path or default_dll_path()),
        cache = {},
        errors = {},
    }, Client)
    local api, load_error = client:load_symbol("palworld_api_v1")
    if type(api) ~= "function" then return nil, load_error end
    local ok, call_error = pcall(api)
    if not ok then return nil, tostring(call_error) end
    return client
end

function Module.parse(specification)
    return parse_specification(specification)
end

return Module
