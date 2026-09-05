local TextLayout = {}

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function codepointUnits(codepoint)
    if codepoint == 32 or codepoint == 9 then return 0.34 end
    if codepoint < 128 then
        local char = string.char(codepoint)
        if string.match(char, "[ilI1|!'`.,:;]") then return 0.32 end
        if string.match(char, "[MW@#%%&]") then return 0.88 end
        if string.match(char, "[A-Z0-9]") then return 0.62 end
        return 0.54
    end
    if (codepoint >= 0x0300 and codepoint <= 0x036F)
        or (codepoint >= 0x1AB0 and codepoint <= 0x1AFF)
        or (codepoint >= 0x1DC0 and codepoint <= 0x1DFF)
        or (codepoint >= 0x20D0 and codepoint <= 0x20FF) then
        return 0.0
    end
    if (codepoint >= 0x3040 and codepoint <= 0x30FF)
        or (codepoint >= 0x3400 and codepoint <= 0x9FFF)
        or (codepoint >= 0xAC00 and codepoint <= 0xD7AF)
        or (codepoint >= 0xF900 and codepoint <= 0xFAFF) then
        return 1.0
    end
    if codepoint >= 0x0E00 and codepoint <= 0x0E7F then return 0.82 end
    if codepoint >= 0x0400 and codepoint <= 0x052F then return 0.64 end
    return 0.68
end

local function lineMetrics(value)
    value = tostring(value or "")
    local maximum, current, lines = 0.0, 0.0, 1
    local ok = pcall(function()
        for _, codepoint in utf8.codes(value) do
            if codepoint == 10 or codepoint == 13 then
                maximum = math.max(maximum, current)
                current = 0.0
                if codepoint == 10 then lines = lines + 1 end
            else
                current = current + codepointUnits(codepoint)
            end
        end
    end)
    if not ok then
        current = #value * 0.64
    end
    return math.max(maximum, current, 0.1), math.max(1, lines)
end

function TextLayout.fitFontSize(value, preferredSize, availableWidth, availableHeight, minimumSize)
    local preferred = math.max(1, tonumber(preferredSize) or 12)
    local minimum = clamp(minimumSize or 8, 1, preferred)
    local width = math.max(1, tonumber(availableWidth) or 1)
    local height = math.max(1, tonumber(availableHeight) or preferred * 1.4)
    local units, lines = lineMetrics(value)
    local widthSize = width * 0.92 / units
    local heightSize = height * 0.88 / (lines * 1.34)
    return math.floor(clamp(math.min(preferred, widthSize, heightSize), minimum, preferred))
end

function TextLayout.estimatedWidth(value, fontSize)
    local units = lineMetrics(value)
    return units * (tonumber(fontSize) or 12)
end

return TextLayout
