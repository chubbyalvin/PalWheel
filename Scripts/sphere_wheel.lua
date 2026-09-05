local SphereWheel = {}

SphereWheel.definitions = {
    { id = "sphere_pal", labelKey = "sphereNamePal", shortLabelKey = "sphereShortPal", label = "Pal Sphere", short = "PAL\nCR07", kind = "sphere", sphereId = "PalSphere", sphereName = "Pal Sphere", sphereShort = "Pal", captureRate = "07" },
    { id = "sphere_mega", labelKey = "sphereNameMega", shortLabelKey = "sphereShortMega", label = "Mega Sphere", short = "MEGA\nCR14", kind = "sphere", sphereId = "PalSphere_Mega", sphereName = "Mega Sphere", sphereShort = "Mega", captureRate = "14" },
    { id = "sphere_giga", labelKey = "sphereNameGiga", shortLabelKey = "sphereShortGiga", label = "Giga Sphere", short = "GIGA\nCR20", kind = "sphere", sphereId = "PalSphere_Giga", sphereName = "Giga Sphere", sphereShort = "Giga", captureRate = "20" },
    { id = "sphere_hyper", labelKey = "sphereNameHyper", shortLabelKey = "sphereShortHyper", label = "Hyper Sphere", short = "HYPER\nCR27", kind = "sphere", sphereId = "PalSphere_Tera", sphereName = "Hyper Sphere", sphereShort = "Hyper", captureRate = "27" },
    { id = "sphere_ultra", labelKey = "sphereNameUltra", shortLabelKey = "sphereShortUltra", label = "Ultra Sphere", short = "ULTRA\nCR33", kind = "sphere", sphereId = "PalSphere_Master", sphereName = "Ultra Sphere", sphereShort = "Ultra", captureRate = "33" },
    { id = "sphere_legendary", labelKey = "sphereNameLegendary", shortLabelKey = "sphereShortLegendary", label = "Legendary Sphere", short = "LEGEND\nCR38", kind = "sphere", sphereId = "PalSphere_Legend", sphereName = "Legendary Sphere", sphereShort = "Legend", captureRate = "38" },
    { id = "sphere_ultimate", labelKey = "sphereNameUltimate", shortLabelKey = "sphereShortUltimate", label = "Ultimate Sphere", short = "ULTIMATE\nCR44", kind = "sphere", sphereId = "PalSphere_Ultimate", sphereName = "Ultimate Sphere", sphereShort = "Ultimate", captureRate = "44" },
    { id = "sphere_exotic", labelKey = "sphereNameExotic", shortLabelKey = "sphereShortExotic", label = "Exotic Sphere", short = "EXOTIC\nCR50", kind = "sphere", sphereId = "PalSphere_Exotic", sphereName = "Exotic Sphere", sphereShort = "Exotic", captureRate = "50" },
    { id = "sphere_sol", labelKey = "sphereNameSol", shortLabelKey = "sphereShortSol", label = "Sol Sphere", short = "SOL\nCR58", kind = "sphere", sphereId = "PalSphere_Ancient_1", sphereName = "Sol Sphere", sphereShort = "Sol", captureRate = "58" },
    { id = "sphere_ancient", labelKey = "sphereNameAncient", shortLabelKey = "sphereShortAncient", label = "Ancient Sphere", short = "ANCIENT\nCR64", kind = "sphere", sphereId = "PalSphere_Ancient_2", sphereName = "Ancient Sphere", sphereShort = "Ancient", captureRate = "64" },
}

SphereWheel.byId = {}
SphereWheel.defaultOrder = {}
for index, definition in ipairs(SphereWheel.definitions) do
    SphereWheel.byId[definition.id] = definition
    SphereWheel.defaultOrder[index] = definition.id
end

function SphereWheel.validatedOrder(saved)
    local result, used = {}, {}
    if type(saved) == "table" then
        for _, id in ipairs(saved) do
            id = tostring(id or "")
            if SphereWheel.byId[id] ~= nil and not used[id] then
                result[#result + 1] = id
                used[id] = true
            end
        end
    end
    for _, id in ipairs(SphereWheel.defaultOrder) do
        if not used[id] then result[#result + 1] = id end
    end
    return result
end

return SphereWheel
