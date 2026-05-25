local Stub = {}

function Stub.status(config)
    local paired = config.pairing_token ~= nil and config.pairing_token ~= ""
    if paired then
        return "stub transport, paired locally"
    end
    return "stub transport, not paired"
end

function Stub.pair(_, token)
    if token == nil or token == "" then
        return false, "Pairing token is empty."
    end
    return true, "Pairing token saved. Stub transport does not contact T3 yet."
end

function Stub.send(_, message)
    if message == nil or message == "" then
        return false, "Message is empty."
    end
    return true, "Stub reply: transport is modular; real T3 backend is pending."
end

return Stub
