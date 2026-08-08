local RuntimeLoops = {}
RuntimeLoops.__index = RuntimeLoops

function RuntimeLoops.new(options)
    local self = setmetatable({}, RuntimeLoops)
    self.options = options or {}

    self.selectionGameCallback = function()
        local ok, err = pcall(self.options.selectionTick)
        if not ok then
            self.options.log("Selection tick error: " .. tostring(err), true)
        end
    end

    self.selectionAsyncCallback = function()
        self.options.executeInGameThread(self.selectionGameCallback)
        return false
    end

    self.fastGameCallback = function()
        local ok, err = pcall(self.options.fastTick)
        if not ok and self.options.fastFailureWasLogged() ~= true then
            self.options.markFastFailureLogged()
            self.options.log("Fast sphere/camera tick error: " .. tostring(err), true)
        end
    end

    self.fastAsyncCallback = function()
        self.options.executeInGameThread(self.fastGameCallback)
        return false
    end

    return self
end

function RuntimeLoops:start(selectionInterval, fastInterval)
    if type(LoopInGameThreadWithDelay) == "function" then
        LoopInGameThreadWithDelay(selectionInterval, self.selectionGameCallback)
        LoopInGameThreadWithDelay(fastInterval, self.fastGameCallback)
        return "game-thread"
    end

    if type(LoopAsync) ~= "function"
        or type(self.options.executeInGameThread) ~= "function" then
        return nil, "UE4SS recurring-loop APIs are unavailable"
    end

    LoopAsync(selectionInterval, self.selectionAsyncCallback)
    LoopAsync(fastInterval, self.fastAsyncCallback)
    return "async-fallback"
end

return RuntimeLoops
