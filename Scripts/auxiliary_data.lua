local AuxData = {}

local DEFAULTS = {
    { "mercy", "mission", "palpedia", "technology" },
    { "weapon1", "weapon2", "weapon3", "weapon4" },
}

function AuxData.defaultAssignments()
    local values = { {}, {} }
    for wheel = 1, 2 do
        for slot = 1, 4 do
            values[wheel][slot] = DEFAULTS[wheel][slot] or "empty"
        end
    end
    return values
end

function AuxData.validatedAssignments(saved, byId)
    local values = AuxData.defaultAssignments()
    if type(saved) ~= "table" then return values end
    byId = type(byId) == "table" and byId or {}
    for wheel = 1, 2 do
        local source = type(saved[wheel]) == "table" and saved[wheel] or {}
        for slot = 1, 4 do
            local id = source[slot]
            if type(id) == "string" and byId[id] ~= nil then
                values[wheel][slot] = id
            elseif id ~= nil then
                values[wheel][slot] = "empty"
            end
        end
    end
    return values
end

return AuxData
