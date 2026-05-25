local Settings = require("settings")

local Transport = {}
Transport.__index = Transport

local backends = {
    stub = "transports.stub",
    rawtcp = "transports.rawtcp",
    http = "transports.http",
}

local function loadBackend(config)
    local module_name = backends[config.transport] or backends.stub
    local ok, backend = pcall(require, module_name)
    if ok and backend then
        return backend
    end
    return require("transports.stub")
end

function Transport.new()
    local config = Settings.load()
    local backend = loadBackend(config)
    return setmetatable({
        config = config,
        backend = backend,
    }, Transport)
end

function Transport:status()
    return self.backend.status(self.config)
end

function Transport:pair(token)
    self.config.pairing_token = token or ""
    local ok, message = true, "Pairing token saved locally."
    if self.backend.pair then
        ok, message = self.backend.pair(self.config, token)
    end
    Settings.save(self.config)
    return ok, message
end

function Transport:send(message)
    return self.backend.send(self.config, message)
end

function Transport:agents()
    if self.backend.agents then
        return self.backend.agents(self.config)
    end
    return false, ""
end

function Transport:thread(limit)
    if self.backend.thread then
        return self.backend.thread(self.config, limit)
    end
    return false, ""
end

function Transport:startStream(path, limit)
    if self.backend.startStream then
        return self.backend.startStream(self.config, path, limit)
    end
    return false, "Streaming is not supported by this transport."
end

function Transport:stopStream(pid)
    if self.backend.stopStream then
        return self.backend.stopStream(pid)
    end
    return false
end

function Transport:setMode(mode)
    self.config.transport = mode
    Settings.save(self.config)
    self.backend = loadBackend(self.config)
end

return Transport
