local IconRuntime = {}
IconRuntime.__index = IconRuntime

local PAL_ICON_TABLE = "/Game/Pal/DataTable/Character/DT_PalCharacterIconDataTable.DT_PalCharacterIconDataTable"
local ITEM_TABLE = "/Game/Pal/DataTable/Item/DT_ItemDataTable.DT_ItemDataTable"
local ITEM_ICON_TABLE = "/Game/Pal/DataTable/Item/DT_ItemIconDataTable.DT_ItemIconDataTable"

local function defaultAlive(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

local function valueString(v)
    if v == nil then return "" end
    if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
        return tostring(v)
    end
    local ok, result = pcall(function() return v:ToString() end)
    if ok and result ~= nil then
        local s = tostring(result)
        s = s:gsub('^FName%(%"(.-)%"%)$', '%1')
        s = s:gsub('^Name%(%"(.-)%"%)$', '%1')
        s = s:gsub('^%"(.-)%"$', '%1')
        return s
    end
    return tostring(v)
end

local function cleanId(v)
    local s = valueString(v):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "None" or s == "nil" then return "" end
    return s
end

local function extractGamePath(v)
    local s = tostring(v or "")
    local path = s:match("(/Game/[%w_/%-%.]+)")
    if path == nil then return "" end
    return path:gsub('[%"%)%],}]+$', "")
end

local function packageAndObject(path)
    path = extractGamePath(path)
    if path == "" then return "", "" end
    local tail = path:match("([^/]+)$") or ""
    if tail:find("%.") then
        local packagePath = path:match("^(.-)%.[^%.]+$") or ""
        return packagePath, path
    end
    return path, path .. "." .. tail
end

function IconRuntime.new(options)
    local self = setmetatable({}, IconRuntime)
    self.options = options or {}
    self.alive = self.options.alive or defaultAlive
    self.log = self.options.log or function() end
    self.textureCache = {}
    self.partyCharacterIds = {}
    self.partyPaths = {}
    self.spherePaths = {}
    self.weaponItemIds = {}
    self.weaponPaths = {}
    self.worldKey = nil
    self.partySignature = ""
    self.weaponSignature = ""
    self.weaponContainerIndex = nil
    self.palIconTable = nil
    self.itemTable = nil
    self.itemIconTable = nil
    self.tablesReady = false
    self.spherePrepared = false
    self.loggedFailures = {}
    self.loggedWeaponContainer = false
    self.loggedWeaponSlots = false
    return self
end

function IconRuntime:safeFullName(obj)
    if not self.alive(obj) then return "" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and value ~= nil and tostring(value) or ""
end

function IconRuntime:isTexture2D(obj)
    if not self.alive(obj) then return false end
    local full = self:safeFullName(obj)
    if full:find("Texture2D ", 1, true) then return true end
    local class = nil
    pcall(function() class = obj:GetClass() end)
    return self.alive(class) and self:safeFullName(class):find("Texture2D", 1, true) ~= nil
end

function IconRuntime:softPath(v)
    if v == nil then return "" end
    local direct = extractGamePath(valueString(v))
    if direct ~= "" then return direct end

    local objectId = nil
    local okObjectId = pcall(function() objectId = v:GetObjectID() end)
    if okObjectId and objectId ~= nil then
        local assetPathName = nil
        local okAsset = pcall(function() assetPathName = objectId:GetAssetPathName() end)
        if okAsset and assetPathName ~= nil then
            local s = valueString(assetPathName)
            local okName, nameString = pcall(function() return assetPathName:ToString() end)
            if okName and nameString ~= nil then s = tostring(nameString) end
            local path = extractGamePath(s)
            if path ~= "" then return path end
        end
    end

    local object = nil
    local okGet = pcall(function() object = v:Get() end)
    if okGet and self.alive(object) then
        return extractGamePath(self:safeFullName(object))
    end
    return ""
end

function IconRuntime:findOrLoadDataTable(path)
    local packagePath, objectPath = packageAndObject(path)
    if objectPath == "" then return nil end
    local ok, object = pcall(StaticFindObject, objectPath)
    if ok and self.alive(object) then return object end
    if type(LoadAsset) == "function" then pcall(LoadAsset, packagePath) end
    ok, object = pcall(StaticFindObject, objectPath)
    if ok and self.alive(object) then return object end
    return nil
end

function IconRuntime:ensureTables()
    if self.tablesReady then return end
    self.tablesReady = true
    self.palIconTable = self:findOrLoadDataTable(PAL_ICON_TABLE)
    self.itemTable = self:findOrLoadDataTable(ITEM_TABLE)
    self.itemIconTable = self:findOrLoadDataTable(ITEM_ICON_TABLE)
end

function IconRuntime:findRow(dt, wanted)
    if not self.alive(dt) or wanted == nil or wanted == "" then return nil end
    local ok, row = pcall(function() return dt:FindRow(wanted) end)
    if ok and row ~= nil then return row end
    local wantedLower = string.lower(tostring(wanted))
    local names = nil
    pcall(function() names = dt:GetRowNames() end)
    if type(names) ~= "table" then return nil end
    for _, name in ipairs(names) do
        local id = cleanId(name)
        if string.lower(id) == wantedLower then
            local found = nil
            pcall(function() found = dt:FindRow(id) end)
            if found ~= nil then return found end
        end
    end
    return nil
end

function IconRuntime:resolvePalIcon(characterId)
    characterId = cleanId(characterId)
    if characterId == "" then return "" end
    self:ensureTables()

    local candidates = { characterId }
    local seen = { [string.lower(characterId)] = true }
    local function addCandidate(candidate)
        candidate = cleanId(candidate)
        local key = string.lower(candidate)
        if candidate ~= "" and not seen[key] then
            seen[key] = true
            candidates[#candidates + 1] = candidate
        end
    end

    
    
    
    
    
    addCandidate(characterId:gsub("^BOSS_", ""))
    addCandidate(characterId:match("^[A-Z][A-Z0-9]*_(.+)$"))

    if self.alive(self.palIconTable) then
        for _, candidate in ipairs(candidates) do
            local row = self:findRow(self.palIconTable, candidate)
            if row ~= nil then
                local value = nil
                pcall(function() value = row.Icon end)
                if value == nil then pcall(function() value = row.IconTexture end) end
                local path = self:softPath(value)
                if path ~= "" then return path end
            end
        end
    end

    local fallbackId = candidates[#candidates] or characterId
    local safe = fallbackId:gsub("[^%w_]", "")
    if safe == "" then return "" end
    local asset = "T_" .. safe .. "_icon_normal"
    return "/Game/Pal/Texture/PalIcon/Normal/" .. asset .. "." .. asset
end

function IconRuntime:resolveItemIcon(itemId)
    itemId = cleanId(itemId)
    if itemId == "" then return "" end
    self:ensureTables()
    if not self.alive(self.itemTable) then return "" end
    local row = self:findRow(self.itemTable, itemId)
    if row == nil then return "" end

    local direct = nil
    pcall(function() direct = row.IconTexture end)
    if direct == nil then pcall(function() direct = row.Icon end) end
    local path = self:softPath(direct)
    if path ~= "" then return path end

    local iconName = nil
    pcall(function() iconName = row.IconName end)
    iconName = cleanId(iconName)
    if iconName == "" or not self.alive(self.itemIconTable) then return "" end
    local iconRow = self:findRow(self.itemIconTable, iconName)
    if iconRow == nil then return "" end

    local texture = nil
    pcall(function() texture = iconRow.Icon end)
    if texture == nil then pcall(function() texture = iconRow.IconTexture end) end
    if texture == nil then pcall(function() texture = iconRow.Texture end) end
    if texture == nil then pcall(function() texture = iconRow.Texture2D end) end
    return self:softPath(texture)
end

function IconRuntime:loadTexture(path, label)
    if path == nil or path == "" then return nil end
    local cached = self.textureCache[path]
    if self:isTexture2D(cached) then return cached, false end

    local _, objectPath = packageAndObject(path)
    if objectPath == "" then return nil end
    if type(LoadAsset) == "function" then pcall(LoadAsset, objectPath) end
    local ok, texture = pcall(StaticFindObject, objectPath)
    if ok and self:isTexture2D(texture) then
        self.textureCache[path] = texture
        return texture, true
    end

    local key = tostring(label or path)
    if not self.loggedFailures[key] then
        self.loggedFailures[key] = true
        self.log("Icon texture unavailable: " .. key .. " | " .. tostring(path), true)
    end
    return nil, false
end

function IconRuntime:currentWorldKey(pc)
    if not self.alive(pc) then return "" end
    local world = nil
    pcall(function() world = pc:GetWorld() end)
    if not self.alive(world) then return "" end

    local address = nil
    local okAddress = pcall(function() address = world:GetAddress() end)
    if okAddress and type(address) == "number" and address ~= 0 then
        return string.format("0x%X", address)
    end

    local fullName = nil
    pcall(function() fullName = world:GetFullName() end)
    if fullName ~= nil and tostring(fullName) ~= "" then
        return tostring(fullName)
    end

    return tostring(world)
end

function IconRuntime:resetForWorld(worldKey)
    self.textureCache = {}
    self.partyCharacterIds = {}
    self.partyPaths = {}
    self.spherePaths = {}
    self.weaponItemIds = {}
    self.weaponPaths = {}
    self.partySignature = ""
    self.weaponSignature = ""
    self.weaponContainerIndex = nil
    self.palIconTable = nil
    self.itemTable = nil
    self.itemIconTable = nil
    self.tablesReady = false
    self.spherePrepared = false
    self.loggedFailures = {}
    self.loggedWeaponContainer = false
    self.loggedWeaponSlots = false
    self.worldKey = worldKey
    self.log("Icon runtime cache reset for new world/session", true)
end

function IconRuntime:scanParty(pc)
    local ids = {}
    if not self.alive(pc) then return ids end
    local holder = nil
    pcall(function() holder = pc.BP_OtomoPalHolderComponent end)
    if not self.alive(holder) then
        local ok, found = pcall(FindFirstOf, "BP_OtomoPalHolderComponent_C")
        if ok and self.alive(found) then holder = found end
    end
    if not self.alive(holder) then return ids end

    local capacity = 5
    pcall(function() capacity = tonumber(holder:GetMaxOtomoNum()) or 5 end)
    capacity = math.max(1, math.min(math.floor(capacity), 100))
    for index = 0, capacity - 1 do
        local handle, parameter, characterId = nil, nil, ""
        pcall(function() handle = holder:GetOtomoIndividualHandle(index) end)
        if handle ~= nil then pcall(function() parameter = handle:TryGetIndividualParameter() end) end
        if parameter ~= nil then
            local value = nil
            pcall(function() value = parameter:GetCharacterID() end)
            characterId = cleanId(value)
        end
        ids[index] = characterId
    end
    return ids
end

function IconRuntime:prepareParty(pc)
    local ids = self:scanParty(pc)
    local pieces = {}
    for index = 0, 99 do
        if ids[index] == nil then break end
        pieces[#pieces + 1] = tostring(index) .. "=" .. tostring(ids[index] or "")
    end
    local signature = table.concat(pieces, "|")
    local changed = signature ~= self.partySignature
    self.partySignature = signature
    self.partyCharacterIds = ids
    self.partyPaths = {}

    local ready, total = 0, 0
    for index, characterId in pairs(ids) do
        if characterId ~= "" then
            total = total + 1
            local path = self:resolvePalIcon(characterId)
            self.partyPaths[index] = path
            local texture, loaded = self:loadTexture(path,
                "party " .. tostring(index + 1) .. " " .. characterId)
            if loaded == true then changed = true end
            if self:isTexture2D(texture) then ready = ready + 1 end
        end
    end
    self.log("Icon cache prepared for party: " .. tostring(ready) .. "/" .. tostring(total), true)
    return changed
end

local function unwrapArrayElement(element)
    if element == nil then return nil end
    local ok, value = pcall(function() return element:get() end)
    if ok and value ~= nil then return value end
    return element
end

local function weaponSlotStaticId(slot)
    if slot == nil then return "" end
    local itemId = nil
    pcall(function() itemId = slot:GetItemId() end)
    if itemId == nil then pcall(function() itemId = slot.ItemId end) end
    if itemId == nil then return "" end
    local staticId = nil
    pcall(function() staticId = itemId.StaticId end)
    if staticId ~= nil then return cleanId(staticId) end
    return cleanId(itemId)
end

local function heldWeaponStaticId(player, aliveFn)
    if not aliveFn(player) then return "" end
    local shooter = nil
    pcall(function() shooter = player.ShooterComponent end)
    if not aliveFn(shooter) then return "" end
    local weapon = nil
    local okWeapon = pcall(function() weapon = shooter:GetHasWeapon() end)
    if not okWeapon or not aliveFn(weapon) then return "" end
    local itemId = nil
    local okItem = pcall(function() itemId = weapon:GetItemId() end)
    if not okItem or itemId == nil then return "" end
    local staticId = nil
    pcall(function() staticId = itemId.StaticId end)
    return cleanId(staticId ~= nil and staticId or itemId)
end

function IconRuntime:scanWeaponLoadout(pc, player)
    local ids = {}
    for index = 0, 5 do ids[index] = "" end
    if not self.alive(pc) then return ids end

    local playerState = nil
    pcall(function() playerState = pc:GetPalPlayerState() end)
    if not self.alive(playerState) then pcall(function() playerState = pc.PlayerState end) end
    if not self.alive(playerState) then return ids end

    local inventoryData = nil
    pcall(function() inventoryData = playerState:GetInventoryData() end)
    if not self.alive(inventoryData) then return ids end

    local helper = nil
    pcall(function() helper = inventoryData.InventoryMultiHelper end)
    if not self.alive(helper) then return ids end

    local containers = nil
    pcall(function() containers = helper.Containers end)
    if containers == nil then return ids end

    
    
    
    
    
    local groups = {}
    pcall(function()
        containers:ForEach(function(rawContainerIndex, rawContainer)
            local containerIndex = tonumber(rawContainerIndex)
            local container = unwrapArrayElement(rawContainer)
            if containerIndex == nil or not self.alive(container) then return end
            local count = 0
            pcall(function() count = tonumber(container:Num()) or 0 end)
            if count < 0 or count > 500 then return end
            local entries = {}
            for slotIndex = 0, count - 1 do
                local slot = nil
                pcall(function() slot = container:Get(slotIndex) end)
                if self.alive(slot) then
                    local empty = true
                    pcall(function() empty = slot:IsEmpty() == true end)
                    if not empty then
                        local equipped = false
                        pcall(function() equipped = inventoryData:IsEquipSlot(slot) == true end)
                        if equipped then
                            local id = weaponSlotStaticId(slot)
                            if id ~= "" then
                                entries[#entries + 1] = {
                                    slotIndex = slotIndex,
                                    id = id,
                                }
                            end
                        end
                    end
                end
            end
            if #entries > 0 then groups[containerIndex] = entries end
        end)
    end)

    local heldId = heldWeaponStaticId(player, self.alive)
    local selectedIndex = nil

    if heldId ~= "" then
        for containerIndex, entries in pairs(groups) do
            for _, entry in ipairs(entries) do
                if entry.id == heldId then
                    selectedIndex = containerIndex
                    break
                end
            end
            if selectedIndex ~= nil then break end
        end
    end

    
    
    if selectedIndex == nil and self.weaponContainerIndex ~= nil
        and groups[self.weaponContainerIndex] ~= nil then
        selectedIndex = self.weaponContainerIndex
    end

    
    
    
    if selectedIndex == nil and groups[1] ~= nil then
        local plausible = true
        for _, entry in ipairs(groups[1]) do
            local slotIndex = tonumber(entry.slotIndex)
            if slotIndex == nil or slotIndex < 0 or slotIndex > 5 then
                plausible = false
                break
            end
        end
        if plausible then selectedIndex = 1 end
    end

    if self.loggedWeaponContainer ~= true then
        self.loggedWeaponContainer = true
        local parts = {}
        local keys = {}
        for k in pairs(groups) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, containerIndex in ipairs(keys) do
            local entries = groups[containerIndex]
            local eparts = {}
            for _, entry in ipairs(entries) do
                eparts[#eparts + 1] = "S" .. tostring(entry.slotIndex)
                    .. "=" .. tostring(entry.id)
            end
            parts[#parts + 1] = "C" .. tostring(containerIndex)
                .. "[" .. table.concat(eparts, ",") .. "]"
        end
        self.log("Equipped icon scan: held="
            .. (heldId ~= "" and heldId or "<none>") .. " groups="
            .. (#parts > 0 and table.concat(parts, " ") or "<none>"), true)
    end

    if selectedIndex == nil then
        return ids
    end

    self.weaponContainerIndex = selectedIndex
    local entries = groups[selectedIndex] or {}
    for _, entry in ipairs(entries) do
        local slotIndex = tonumber(entry.slotIndex)
        if slotIndex ~= nil and slotIndex >= 0 and slotIndex <= 5 then
            ids[slotIndex] = entry.id
        end
    end

    if self.loggedWeaponSlots ~= true then
        self.loggedWeaponSlots = true
        self.log("Weapon icon container selected from equipped scan: C"
            .. tostring(selectedIndex) .. " held="
            .. (heldId ~= "" and heldId or "<none>"), true)
    end
    return ids
end

function IconRuntime:prepareWeapons(pc, player)
    local ids = self:scanWeaponLoadout(pc, player)
    local pieces = {}
    for index = 0, 5 do
        pieces[#pieces + 1] = tostring(index) .. "=" .. tostring(ids[index] or "")
    end
    local signature = table.concat(pieces, "|")
    local changed = signature ~= self.weaponSignature
    self.weaponSignature = signature
    self.weaponItemIds = ids
    self.weaponPaths = {}
    if changed then
        local labels = {}
        for index = 0, 5 do
            labels[#labels + 1] = "W" .. tostring(index + 1) .. "=" .. tostring(ids[index] or "")
        end
        self.log("Weapon icon loadout scan: " .. table.concat(labels, ", "), true)
    end

    local ready, total = 0, 0
    for index = 0, 5 do
        local itemId = ids[index] or ""
        if itemId ~= "" then
            total = total + 1
            local path = self:resolveItemIcon(itemId)
            self.weaponPaths[index] = path
            local texture, loaded = self:loadTexture(path,
                "weapon " .. tostring(index + 1) .. " " .. itemId)
            if loaded == true then changed = true end
            if self:isTexture2D(texture) then ready = ready + 1 end
        end
    end
    self.log("Icon cache prepared for weapons: " .. tostring(ready) .. "/" .. tostring(total), true)
    return changed
end

function IconRuntime:prepareSpheres(definitions)
    local ready, total = 0, 0
    local changed = false
    if not self.spherePrepared then self.spherePaths = {} end
    for _, definition in ipairs(definitions or {}) do
        if definition ~= nil and definition.sphereId ~= nil then
            total = total + 1
            local path = self.spherePaths[definition.sphereId]
            if path == nil or path == "" then
                path = self:resolveItemIcon(definition.sphereId)
                self.spherePaths[definition.sphereId] = path
            end
            local texture, loaded = self:loadTexture(path,
                "sphere " .. tostring(definition.sphereId))
            if loaded == true then changed = true end
            if self:isTexture2D(texture) then ready = ready + 1 end
        end
    end
    self.spherePrepared = true
    self.log("Icon cache prepared for spheres: " .. tostring(ready) .. "/" .. tostring(total), true)
    return changed
end

function IconRuntime:prepare(pc, wheelMode, sphereDefinitions, player)
    local changed = false
    local worldKey = self:currentWorldKey(pc)
    if worldKey ~= "" and worldKey ~= self.worldKey then
        self:resetForWorld(worldKey)
        changed = true
    end
    if wheelMode == "main" then
        if self:prepareParty(pc) then changed = true end
        if self:prepareWeapons(pc, player) then changed = true end
    else
        if self:prepareSpheres(sphereDefinitions) then changed = true end
    end
    return changed
end

function IconRuntime:textureForDefinition(definition)
    if definition == nil then return nil end
    if definition.kind == "pal" then
        local path = self.partyPaths[tonumber(definition.index)]
        local texture = path ~= nil and self.textureCache[path] or nil
        return self:isTexture2D(texture) and texture or nil
    end
    if definition.kind == "weapon" then
        local path = self.weaponPaths[tonumber(definition.index)]
        local texture = path ~= nil and self.textureCache[path] or nil
        return self:isTexture2D(texture) and texture or nil
    end
    if definition.kind == "sphere" then
        local path = self.spherePaths[tostring(definition.sphereId or "")]
        local texture = path ~= nil and self.textureCache[path] or nil
        return self:isTexture2D(texture) and texture or nil
    end
    return nil
end

return IconRuntime
