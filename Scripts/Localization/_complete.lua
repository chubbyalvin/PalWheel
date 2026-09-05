local function complete(overrides)
    local english = require("Localization.en")
    local result = {}
    for key, value in pairs(english) do result[key] = value end
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

return complete
