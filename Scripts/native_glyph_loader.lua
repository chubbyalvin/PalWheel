local NativeGlyphLoader = {}


local CACHE = {}

local function alive(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

local function fullName(obj)
    if not alive(obj) then return "" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and tostring(value or "") or ""
end

local function isTexture2D(obj)
    return alive(obj) and fullName(obj):find("Texture2D", 1, true) ~= nil
end

local function exactObjectPath(path)
    local text = tostring(path or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("^Texture2D['\"]", ""):gsub("['\"]$", "")
    if text == "" then return "" end
    if text:find("%.") then return text end
    local tail = text:match("([^/]+)$") or ""
    if tail == "" then return "" end
    return text .. "." .. tail
end

function NativeGlyphLoader.texture(path)
    local objectPath = exactObjectPath(path)
    if objectPath == "" then return nil end

    local cached = CACHE[objectPath]
    if isTexture2D(cached) then return cached end
    CACHE[objectPath] = nil

    
    
    local object = nil
    pcall(function() object = StaticFindObject(objectPath) end)
    if isTexture2D(object) then
        CACHE[objectPath] = object
        return object
    end

    
    
    if type(LoadAsset) == "function" then
        local loaded = nil
        local ok = pcall(function() loaded = LoadAsset(objectPath) end)
        if ok and isTexture2D(loaded) then
            CACHE[objectPath] = loaded
            return loaded
        end
    end

    
    
    object = nil
    pcall(function() object = StaticFindObject(objectPath) end)
    if isTexture2D(object) then
        CACHE[objectPath] = object
        return object
    end
    return nil
end

function NativeGlyphLoader.objectPath(path)
    return exactObjectPath(path)
end

function NativeGlyphLoader.isTexture2D(obj)
    return isTexture2D(obj)
end

return NativeGlyphLoader
