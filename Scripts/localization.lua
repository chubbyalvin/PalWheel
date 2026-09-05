local Localization = {}

local LANGUAGE_MODULES = {
    en = "Localization.en",
    ja = "Localization.ja",
    ["zh-Hans"] = "Localization.zh_Hans",
    ["zh-Hant"] = "Localization.zh_Hant",
    ko = "Localization.ko",
    fr = "Localization.fr",
    de = "Localization.de",
    it = "Localization.it",
    ["es-ES"] = "Localization.es_ES",
    ["es-419"] = "Localization.es_419",
    ["pt-BR"] = "Localization.pt_BR",
    ru = "Localization.ru",
    id = "Localization.id",
    th = "Localization.th",
    tr = "Localization.tr",
    vi = "Localization.vi",
    pl = "Localization.pl",
}

local CULTURE_ALIASES = {
    en = "en", ja = "ja", ko = "ko", fr = "fr", de = "de", it = "it",
    ru = "ru", id = "id", ["in"] = "id", th = "th", tr = "tr", vi = "vi", pl = "pl",
    ["zh-hans"] = "zh-Hans", ["zh-hans-cn"] = "zh-Hans", ["zh-cn"] = "zh-Hans",
    ["zh-sg"] = "zh-Hans", ["schinese"] = "zh-Hans",
    ["zh-hant"] = "zh-Hant", ["zh-hant-tw"] = "zh-Hant", ["zh-tw"] = "zh-Hant",
    ["zh-hk"] = "zh-Hant", ["zh-mo"] = "zh-Hant", ["tchinese"] = "zh-Hant",
    ["es-es"] = "es-ES", ["es"] = "es-ES",
    ["es-419"] = "es-419", ["es-mx"] = "es-419", ["es-ar"] = "es-419",
    ["es-cl"] = "es-419", ["es-co"] = "es-419", ["es-pe"] = "es-419",
    ["pt-br"] = "pt-BR", ["pt"] = "pt-BR",
}

local english = {}
local selected = english
local activeLanguage = "en"
local detectedCulture = ""
local detectionMethod = "fallback"

local function normalizeTag(value)
    local tag = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    tag = tag:gsub("_", "-")
    local lower = string.lower(tag)
    if CULTURE_ALIASES[lower] ~= nil then return CULTURE_ALIASES[lower] end
    local language = lower:match("^([a-z][a-z])[-%s]") or lower:match("^([a-z][a-z])$")
    if language == "zh" then
        if lower:find("hant", 1, true) or lower:find("-tw", 1, true)
            or lower:find("-hk", 1, true) or lower:find("-mo", 1, true) then
            return "zh-Hant"
        end
        return "zh-Hans"
    end
    if language == "es" then
        if lower == "es-es" or lower == "es" then return "es-ES" end
        return "es-419"
    end
    if language == "pt" then return "pt-BR" end
    if language ~= nil and LANGUAGE_MODULES[language] ~= nil then return language end
    return "en"
end

local function findInternationalizationLibrary()
    if type(StaticFindObject) ~= "function" then return nil end
    local ok, object = pcall(StaticFindObject,
        "/Script/Engine.Default__KismetInternationalizationLibrary")
    if ok and object ~= nil then return object end
    return nil
end

local function detectCulture()
    local library = findInternationalizationLibrary()
    if library == nil then return "", "fallback" end
    local okValue, value = pcall(function() return library:GetCurrentLanguage() end)
    if not okValue or value == nil then return "", "fallback" end
    local okText, text = pcall(function() return value:ToString() end)
    if not okText or text == nil then return "", "fallback" end
    text = tostring(text)
    if text == "" then return "", "fallback" end
    return text, "UKismetInternationalizationLibrary.GetCurrentLanguage"
end

local function loadTable(language)
    local moduleName = LANGUAGE_MODULES[language]
    if moduleName == nil then return nil end
    local ok, values = pcall(require, moduleName)
    if ok and type(values) == "table" then return values end
    return nil
end

local function substitute(value, variables)
    if type(variables) ~= "table" then return value end
    return (value:gsub("{{([%w_]+)}}", function(name)
        local replacement = variables[name]
        return replacement == nil and ("{{" .. name .. "}}") or tostring(replacement)
    end))
end

function Localization.normalizeCulture(value)
    return normalizeTag(value)
end

function Localization.get(key, variables)
    key = tostring(key or "")
    local value = selected[key]
    if type(value) ~= "string" then value = english[key] end
    if type(value) ~= "string" then value = "[" .. key .. "]" end
    return substitute(value, variables)
end

function Localization.language()
    return activeLanguage
end

function Localization.culture()
    return detectedCulture
end

function Localization.detectionMethod()
    return detectionMethod
end

function Localization.supportedLanguages()
    return {
        "en", "ja", "zh-Hans", "zh-Hant", "ko", "fr", "de", "it",
        "es-ES", "es-419", "pt-BR", "ru", "id", "th", "tr", "vi", "pl",
    }
end

english = loadTable("en") or {}
detectedCulture, detectionMethod = detectCulture()
activeLanguage = normalizeTag(detectedCulture)
selected = activeLanguage == "en" and english or (loadTable(activeLanguage) or {})

return Localization
