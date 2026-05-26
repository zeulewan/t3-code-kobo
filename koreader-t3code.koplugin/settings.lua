local Settings = {}

Settings.base_dir = "/mnt/onboard/.adds/t3code-kobo"
Settings.config_path = Settings.base_dir .. "/settings.lua"

local defaults = {
    transport = "http",
    endpoint = "127.0.0.1:18891",
    target = "",
    target_title = "",
    target_project = "",
    target_model = "",
    target_effort = "",
    pairing_token = "",
}

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function ensureDir()
    os.execute("mkdir -p " .. shellQuote(Settings.base_dir))
end

function Settings.load()
    ensureDir()
    local loaded = {}
    local chunk = loadfile(Settings.config_path)
    if chunk then
        local ok, result = pcall(chunk)
        if ok and type(result) == "table" then
            loaded = result
        end
    end
    for key, value in pairs(defaults) do
        if loaded[key] == nil then
            loaded[key] = value
        end
    end
    return loaded
end

function Settings.save(config)
    ensureDir()
    local file = io.open(Settings.config_path, "w")
    if not file then
        return false
    end
    file:write("return {\n")
    for _, key in ipairs({
        "transport",
        "endpoint",
        "target",
        "target_title",
        "target_project",
        "target_model",
        "target_effort",
        "pairing_token",
        "crash_report_marker",
    }) do
        file:write(string.format("    %s = %q,\n", key, tostring(config[key] or "")))
    end
    file:write("}\n")
    file:close()
    return true
end

local function targetKey(target)
    local value = tostring(target or ""):match("^%s*(.-)%s*$")
    if value == "" then
        value = "default"
    end
    value = value:gsub("[^%w%-_]", "_")
    return value
end

function Settings.transcriptPath(target)
    return Settings.base_dir .. "/transcript-" .. targetKey(target) .. ".txt"
end

function Settings.streamPath(target)
    return Settings.base_dir .. "/stream-" .. targetKey(target) .. ".txt"
end

function Settings.appendTranscript(line, target)
    ensureDir()
    local file = io.open(Settings.transcriptPath(target), "a")
    if not file then
        return false
    end
    file:write(line .. "\n")
    file:close()
    return true
end

function Settings.writeTranscript(text, target)
    ensureDir()
    local file = io.open(Settings.transcriptPath(target), "w")
    if not file then
        return false
    end
    file:write(tostring(text or ""))
    file:close()
    return true
end

function Settings.readTranscript(target)
    local file = io.open(Settings.transcriptPath(target), "r")
    if not file then
        return ""
    end
    local text = file:read("*a") or ""
    file:close()
    return text
end

return Settings
