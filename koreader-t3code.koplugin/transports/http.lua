local Http = {}

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function urlEncode(value)
    value = tostring(value or "")
    return (value:gsub("([^%w%-_%.~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

function Http.urlEncode(value)
    return urlEncode(value)
end

local function normalizeEndpoint(endpoint)
    endpoint = tostring(endpoint or "")
    if endpoint:match("^https?://") then
        return endpoint:gsub("/+$", "")
    end
    return "http://" .. endpoint:gsub("/+$", "")
end

local function request(url)
    local tmp = os.tmpname()
    local cmd = "wget -q -T 10 -O " .. shellQuote(tmp) .. " " .. shellQuote(url)
    local ok = os.execute(cmd)
    local file = io.open(tmp, "r")
    local body = file and (file:read("*a") or "") or ""
    if file then
        file:close()
    end
    os.remove(tmp)
    if ok == true or ok == 0 then
        return true, body
    end
    return false, body ~= "" and body or "HTTP request failed."
end

function Http.status(config)
    local ok, body = request(normalizeEndpoint(config.endpoint) .. "/status")
    if ok then
        return body
    end
    return "http unavailable at " .. tostring(config.endpoint) .. ": " .. tostring(body)
end

function Http.pair(config, token)
    local input = tostring(token or ""):match("^%s*(.-)%s*$")
    if input == "" then
        return false, "Pairing input is empty. Use: target endpoint"
    end

    for part in input:gmatch("%S+") do
        if part:match("^https?://") or part:match("^%d+%.%d+%.%d+%.%d+:%d+$") or part:match("^[%w%.-]+:%d+$") then
            config.endpoint = part
        else
            config.target = part:gsub("^target=", "")
        end
    end
    return true, "Saved target " .. tostring(config.target) .. " via " .. tostring(config.endpoint)
end

function Http.send(config, message)
    if message == nil or message == "" then
        return false, "Message is empty."
    end
    local url = normalizeEndpoint(config.endpoint)
        .. "/send?target=" .. urlEncode(config.target or "")
        .. "&message=" .. urlEncode(message)
    return request(url)
end

function Http.agents(config)
    return request(normalizeEndpoint(config.endpoint) .. "/agents")
end

function Http.thread(config, limit)
    local url = normalizeEndpoint(config.endpoint)
        .. "/thread?target=" .. urlEncode(config.target or "")
        .. "&limit=" .. urlEncode(limit or 10)
    return request(url)
end

function Http.startStream(config, path, limit)
    local url = normalizeEndpoint(config.endpoint)
        .. "/stream?target=" .. urlEncode(config.target or "")
        .. "&limit=" .. urlEncode(limit or 10)
        .. "&seconds=120&interval_ms=1500"
    os.remove(path)
    local cmd = "wget -q -T 130 -O " .. shellQuote(path) .. " " .. shellQuote(url) .. " >/dev/null 2>&1 & echo $!"
    local handle = io.popen(cmd)
    if not handle then
        return false, "Could not start stream."
    end
    local output = handle:read("*a") or ""
    handle:close()
    local pid = output:match("%d+")
    if not pid then
        return false, "Could not start stream process."
    end
    return true, pid
end

function Http.stopStream(pid)
    if pid and tostring(pid) ~= "" then
        os.execute("kill " .. tostring(pid) .. " >/dev/null 2>&1")
    end
    return true
end

return Http
