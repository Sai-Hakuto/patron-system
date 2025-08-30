local unpack = table.unpack or unpack

local function error_handler(err)
    local trace = debug.traceback(err, 2)
    if PatronSystemNS and PatronSystemNS.Logger and PatronSystemNS.Logger.Error then
        PatronSystemNS.Logger:Error("SafeCall error: " .. tostring(err))
        PatronSystemNS.Logger:Error(trace)
    else
        print("[SafeCall] Error: " .. tostring(err))
        print(trace)
    end
    return err
end

local function SafeCall(fn, ...)
    local results = { xpcall(fn, error_handler, ...) }
    local ok = results[1]
    if ok then
        return true, unpack(results, 2)
    else
        return false, results[2]
    end
end

PatronSystemNS.SafeCall = SafeCall

