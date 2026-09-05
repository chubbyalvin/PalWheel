local FileStore = {}

local function closeQuietly(file)
    if file ~= nil then pcall(function() file:close() end) end
end

function FileStore.exists(path)
    if io == nil or type(io.open) ~= "function" then return false end
    local ok, file = pcall(io.open, path, "rb")
    if not ok or file == nil then return false end
    closeQuietly(file)
    return true
end

function FileStore.readText(path)
    if io == nil or type(io.open) ~= "function" then
        return nil, "Lua file I/O is unavailable"
    end
    local file, why = io.open(path, "rb")
    if file == nil then return nil, tostring(why or "file is unavailable") end
    local ok, text, readError = pcall(function() return file:read("*a") end)
    closeQuietly(file)
    if not ok or text == nil then return nil, tostring(readError or text or "read failed") end
    return tostring(text or "")
end

function FileStore.writeText(path, text, options)
    options = options or {}
    if io == nil or type(io.open) ~= "function" then
        return false, "Lua file I/O is unavailable"
    end
    if os == nil or type(os.rename) ~= "function" or type(os.remove) ~= "function" then
        return false, "Lua file replacement functions are unavailable"
    end

    local temporary = path .. ".tmp"
    local backup = tostring(options.backupPath or (path .. ".bak"))
    local file, openError = io.open(temporary, "wb")
    if file == nil then return false, tostring(openError or "could not open temporary file") end

    local okWrite, writeError = pcall(function()
        local wrote, whyWrite = file:write(tostring(text or ""))
        if wrote == nil then error(tostring(whyWrite or "write failed")) end
        local flushed, whyFlush = file:flush()
        if flushed == nil then error(tostring(whyFlush or "flush failed")) end
        local closed, whyClose = file:close()
        file = nil
        if closed == nil then error(tostring(whyClose or "close failed")) end
    end)
    closeQuietly(file)
    if not okWrite then
        pcall(os.remove, temporary)
        return false, "temporary write failed: " .. tostring(writeError)
    end

    if options.expectedText ~= nil then
        local current = FileStore.readText(path)
        if current ~= options.expectedText then
            pcall(os.remove, temporary)
            return false, "file changed before commit", "conflict"
        end
    end

    local existed = FileStore.exists(path)
    if existed then
        if FileStore.exists(backup) then
            local removed, removeError = os.remove(backup)
            if not removed then
                pcall(os.remove, temporary)
                return false, "could not replace previous backup: " .. tostring(removeError)
            end
        end
        local parked, parkError = os.rename(path, backup)
        if not parked then
            pcall(os.remove, temporary)
            return false, "could not preserve previous file: " .. tostring(parkError)
        end
    end

    local installed, installError = os.rename(temporary, path)
    if not installed then
        local rollbackError = nil
        if existed then
            local restored, whyRestore = os.rename(backup, path)
            if not restored then rollbackError = whyRestore or "rollback failed" end
        end
        pcall(os.remove, temporary)
        local message = "could not install new file: " .. tostring(installError)
        if rollbackError ~= nil then
            message = message .. "; previous file remains at " .. backup
                .. " because rollback failed: " .. tostring(rollbackError)
        end
        return false, message
    end

    if existed and options.keepBackup ~= true then pcall(os.remove, backup) end
    return true
end

return FileStore
