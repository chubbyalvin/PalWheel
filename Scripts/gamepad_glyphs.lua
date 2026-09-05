local GamepadGlyphs = {}
GamepadGlyphs.__index = GamepadGlyphs

local NativeGlyphLoader = require("native_glyph_loader")

local TABLE_PATH = "/Game/Pal/DataTable/UI/DT_PalGamepadButtonImage.DT_PalGamepadButtonImage"
local EXPECTED_ROW_STRUCT = "/Script/Pal.PalGamepadButtonImageDatabaseRow"
local DUALSENSE_DIR = "/Game/Pal/Texture/UI/KeyGuide/DualSense/"

local function alive(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

local function safeGet(obj, field)
    if obj == nil then return nil end
    local ok, value = pcall(function() return obj[field] end)
    return ok and value or nil
end

local function cleanText(value)
    if value == nil then return "" end
    local ok, text = pcall(function() return value:ToString() end)
    local s = ok and tostring(text or "") or tostring(value or "")
    s = s:gsub('^FName%(["\'](.-)["\']%)$', '%1')
    s = s:gsub('^Name%(["\'](.-)["\']%)$', '%1')
    s = s:gsub('^["\'](.-)["\']$', '%1')
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "None" or s == "nil" then return "" end
    return s
end

local function safeFullName(obj)
    if not alive(obj) then return "" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and tostring(value or "") or ""
end

local function extractGamePath(value)
    local path = tostring(value or ""):match("(/Game/[%w_/%-%.]+)")
    if path == nil then return "" end
    return path:gsub('[%"%)%],}]+$', '')
end

local function softPath(value)
    if value == nil then return "" end
    if alive(value) then
        local path = extractGamePath(safeFullName(value))
        if path ~= "" then return NativeGlyphLoader.objectPath(path) end
    end
    local direct = extractGamePath(cleanText(value))
    if direct ~= "" then return NativeGlyphLoader.objectPath(direct) end

    local objectId = nil
    if pcall(function() objectId = value:GetObjectID() end) and objectId ~= nil then
        local assetPathName = nil
        if pcall(function() assetPathName = objectId:GetAssetPathName() end)
            and assetPathName ~= nil then
            local path = extractGamePath(cleanText(assetPathName))
            if path ~= "" then return NativeGlyphLoader.objectPath(path) end
        end
    end

    local object = nil
    if pcall(function() object = value:Get() end) and alive(object) then
        local path = extractGamePath(safeFullName(object))
        if path ~= "" then return NativeGlyphLoader.objectPath(path) end
    end
    return ""
end

local function keyText(value)
    if value == nil then return "" end
    local keyName = safeGet(value, "KeyName")
    if keyName ~= nil then
        local s = cleanText(keyName)
        if s ~= "" then return s end
    end
    local s = cleanText(value)
    if s:find("table:", 1, true) or s:find("userdata:", 1, true) then return "" end
    return s
end

local function ds(asset)
    return DUALSENSE_DIR .. asset .. "." .. asset
end


local XBOX_EXACT_FALLBACKS = {
    
    
    Gamepad_DPad_2D = "/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_Cross.T_KeyGuide_Cross",
    Gamepad_DPad = "/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_Cross.T_KeyGuide_Cross",
}

local XBOX_LABELS = {
    Gamepad_FaceButton_Bottom = "A",
    Gamepad_FaceButton_Right = "B",
    Gamepad_FaceButton_Left = "X",
    Gamepad_FaceButton_Top = "Y",
    Gamepad_LeftShoulder = "LB",
    Gamepad_RightShoulder = "RB",
    Gamepad_LeftTrigger = "LT",
    Gamepad_RightTrigger = "RT",
    Gamepad_LeftThumbstick = "LS",
    Gamepad_RightThumbstick = "RS",
    Gamepad_DPad_Up = "D-Pad Up",
    Gamepad_DPad_Down = "D-Pad Down",
    Gamepad_DPad_Left = "D-Pad Left",
    Gamepad_DPad_Right = "D-Pad Right",
    Gamepad_Special_Left = "View",
    Gamepad_Special_Right = "Menu",
}

local DUALSENSE_LABELS = {
    Gamepad_FaceButton_Bottom = "Cross",
    Gamepad_FaceButton_Right = "Circle",
    Gamepad_FaceButton_Left = "Square",
    Gamepad_FaceButton_Top = "Triangle",
    Gamepad_LeftShoulder = "L1",
    Gamepad_RightShoulder = "R1",
    Gamepad_LeftTrigger = "L2",
    Gamepad_RightTrigger = "R2",
    Gamepad_LeftThumbstick = "L3",
    Gamepad_RightThumbstick = "R3",
    Gamepad_DPad_Up = "D-Pad Up",
    Gamepad_DPad_Down = "D-Pad Down",
    Gamepad_DPad_Left = "D-Pad Left",
    Gamepad_DPad_Right = "D-Pad Right",
    Gamepad_Special_Left = "Create",
    Gamepad_Special_Right = "Options",
    Gamepad_Touchpad_Button = "Touchpad",
}

local DUALSENSE_PATHS = {
    
    
    Gamepad_DPad_2D = "/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_Cross.T_KeyGuide_Cross",
    Gamepad_DPad = "/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_Cross.T_KeyGuide_Cross",
    Gamepad_FaceButton_Bottom = ds("T_KeyGuide_DualSense_Cross"),
    Gamepad_FaceButton_Right = ds("T_KeyGuide_DualSense_Circle"),
    Gamepad_FaceButton_Left = ds("T_KeyGuide_DualSense_Square"),
    Gamepad_FaceButton_Top = ds("T_KeyGuide_DualSense_Triangle"),
    Gamepad_LeftShoulder = ds("T_KeyGuide_DualSense_L1"),
    Gamepad_RightShoulder = ds("T_KeyGuide_DualSense_R1"),
    Gamepad_LeftTrigger = ds("T_KeyGuide_DualSense_L2"),
    Gamepad_RightTrigger = ds("T_KeyGuide_DualSense_R2"),
    Gamepad_LeftThumbstick = ds("T_KeyGuide_DualSense_L3"),
    Gamepad_RightThumbstick = ds("T_KeyGuide_DualSense_R3"),
    Gamepad_DPad_Down = ds("T_KeyGuide_DualSense_DirectionalD"),
    Gamepad_DPad_Left = ds("T_KeyGuide_DualSense_DirectionalL"),
    Gamepad_DPad_Right = ds("T_KeyGuide_DualSense_DirectionalR"),
    Gamepad_DPad_Up = ds("T_KeyGuide_DualSense_DirectionalU"),
    
    
    Gamepad_Special_Left = "/Game/Pal/Texture/UI/KeyGuide/T_KeyGuide_View.T_KeyGuide_View",
    Gamepad_Special_Right = ds("T_KeyGuide_DualSense_Options"),
    Gamepad_Touchpad_Button = ds("T_KeyGuide_DualSense_Touch"),

    Gamepad_LeftStick_Down = ds("T_KeyGuide_DualSense_StickL_D"),
    Gamepad_LeftStick_Left = ds("T_KeyGuide_DualSense_StickL_L"),
    Gamepad_LeftStick_Right = ds("T_KeyGuide_DualSense_StickL_R"),
    Gamepad_LeftStick_Up = ds("T_KeyGuide_DualSense_StickL_U"),
    Gamepad_RightStick_Down = ds("T_KeyGuide_DualSense_StickR_D"),
    Gamepad_RightStick_Left = ds("T_KeyGuide_DualSense_StickR_L"),
    Gamepad_RightStick_Right = ds("T_KeyGuide_DualSense_StickR_R"),
    Gamepad_RightStick_Up = ds("T_KeyGuide_DualSense_StickR_U"),
}

local function normalizeFamily(value)
    local family = string.lower(cleanText(value))
    if family:find("playstation", 1, true) or family:find("dual", 1, true)
        or family == "ps" or family == "ps4" or family == "ps5" then
        return "dualsense"
    end
    if family:find("xbox", 1, true) or family:find("xinput", 1, true) then
        return "xbox"
    end
    return nil
end

function GamepadGlyphs.new(options)
    return setmetatable({
        o = options or {},
        table = nil,
        xboxPaths = {},
        prepared = false,
        failed = false,
    }, GamepadGlyphs)
end

function GamepadGlyphs:family(family)
    local resolved = normalizeFamily(family)
    if resolved ~= nil then return resolved end
    if type(self.o.familyProvider) == "function" then
        local ok, value = pcall(self.o.familyProvider)
        if ok then
            resolved = normalizeFamily(value)
            if resolved ~= nil then return resolved end
        end
    end
    local fallback = self.o.fallbackFamily
    if type(fallback) == "function" then
        local ok, value = pcall(fallback)
        fallback = ok and value or nil
    end
    return normalizeFamily(fallback) or "xbox"
end

function GamepadGlyphs:findTable()
    if alive(self.table) then return self.table end
    
    
    local object = nil
    pcall(function() object = StaticFindObject(TABLE_PATH) end)
    if not alive(object) and type(LoadAsset) == "function" then
        pcall(function() object = LoadAsset(TABLE_PATH) end)
        if not alive(object) then
            local packagePath = TABLE_PATH:match("^(.-)%.[^%.]+$") or TABLE_PATH
            pcall(LoadAsset, packagePath)
            pcall(function() object = StaticFindObject(TABLE_PATH) end)
        end
    end
    if alive(object) then self.table = object end
    return self.table
end

function GamepadGlyphs:prepare()
    if self.prepared then return true end
    if self.failed then return false end
    local dt = self:findTable()
    if not alive(dt) then
        self.failed = true
        if type(self.o.log) == "function" then self.o.log("Native gamepad glyph table unavailable", true) end
        return false
    end

    local rowStruct = nil
    pcall(function() rowStruct = dt:GetRowStruct() end)
    if not alive(rowStruct) then rowStruct = safeGet(dt, "RowStruct") end
    local rowStructName = alive(rowStruct) and safeFullName(rowStruct) or ""
    if rowStructName ~= "" and not rowStructName:find(EXPECTED_ROW_STRUCT, 1, true) then
        self.failed = true
        if type(self.o.log) == "function" then
            self.o.log("Native gamepad glyph row structure changed: " .. rowStructName, true)
        end
        return false
    end

    local names = nil
    pcall(function() names = dt:GetRowNames() end)
    if type(names) ~= "table" then self.failed = true return false end

    local mapped = 0
    for _, rowName in ipairs(names) do
        local row = nil
        pcall(function() row = dt:FindRow(rowName) end)
        if row ~= nil then
            local key = keyText(safeGet(row, "Key"))
            local path = softPath(safeGet(row, "XboxButtonImage"))
            if key ~= "" and path ~= "" then
                self.xboxPaths[key] = path
                mapped = mapped + 1
            end
        end
    end

    self.prepared = mapped > 0
    self.failed = not self.prepared
    if type(self.o.log) == "function" then
        self.o.log("Native Xbox gamepad glyph paths mapped: " .. tostring(mapped)
            .. "/" .. tostring(#names) .. "; exact-load cache active", true)
    end
    return self.prepared
end

function GamepadGlyphs:pathForKey(key, family)
    key = tostring(key or "")
    local resolvedFamily = self:family(family)
    if resolvedFamily == "dualsense" then
        return DUALSENSE_PATHS[key]
    end
    if not self.prepared and not self:prepare() then return nil end
    return self.xboxPaths[key] or XBOX_EXACT_FALLBACKS[key]
end

function GamepadGlyphs:labelForKey(key, family)
    key = tostring(key or "")
    if self:family(family) == "dualsense" then
        return DUALSENSE_LABELS[key] or key
    end
    return XBOX_LABELS[key] or key
end

function GamepadGlyphs:textureForKey(key, family)
    local path = self:pathForKey(key, family)
    if path == nil or path == "" then return nil end
    return NativeGlyphLoader.texture(path)
end

return GamepadGlyphs
