--[[
    PuckAFK Hub | Universal Access Loader v5.3 - Polished UI + Native Link Opener
    Canonical URL: https://puckafk.site/loader.lua

    Default flow:
      1. Choose Free or Premium.
      2. Free -> launch the public PuckAFK route for the current game.
      3. Premium -> join Discord/get a key, enter it, validate server-side,
         then launch the paid Premium source for the current game.

    Premium keys are saved locally only after successful validation.

    v5.3 release polish:
      - Fixes stale Free mode causing later executions to skip the chooser.
      - Adds an explicit Remember My Choice toggle, off by default.
      - Remembered choices get a visible 3-second cancel/change window.
      - Rebuilds the access UI with real Roblox image icons and a denser polished layout.
      - Adds BrowserService + broader executor open-link detection for Discord/site actions.
      - Keeps direct website opening, remember-choice safety, and full UI animations.
      - Idempotent GUI cleanup and executor-safe fallbacks.
]]

local ENV = (type(getgenv) == "function" and getgenv()) or _G
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local FREE_LOADER = "https://puckafk.site/loader-free.lua"
local PREMIUM_API = "https://puckafk.site/api/premium"
local PREMIUM_API_FALLBACK = "https://puckhub-key-api.puckafk.workers.dev/v1/premium"
local DISCORD_INVITE = "https://discord.gg/NFfs8G2WAz"
local PREMIUM_PAGE = "https://puckafk.site/premium/"
local KEY_FILE = "PuckHub/premium.key"
local CHOICE_FILE = "PuckHub/access-choice.txt"

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeKey(value)
    return trim(value):gsub("%s+", "")
end

local function normalizeChoice(value)
    value = string.lower(trim(value))
    if value == "free" or value == "premium" then return value end
    return ""
end

local function readSavedChoice()
    local envChoice = normalizeChoice(rawget(ENV, "PuckHubRememberedAccess"))
    if envChoice ~= "" then return envChoice end

    if type(isfile) == "function" and type(readfile) == "function" then
        local okExists, exists = pcall(isfile, CHOICE_FILE)
        if okExists and exists then
            local okRead, value = pcall(readfile, CHOICE_FILE)
            if okRead then return normalizeChoice(value) end
        end
    end
    return ""
end

local function saveChoice(choice)
    choice = normalizeChoice(choice)
    if choice == "" then return false end
    ENV.PuckHubRememberedAccess = choice
    if type(writefile) ~= "function" then return true end
    if type(makefolder) == "function" then pcall(makefolder, "PuckHub") end
    return pcall(writefile, CHOICE_FILE, choice)
end

local function clearSavedChoice()
    ENV.PuckHubRememberedAccess = nil
    if type(delfile) == "function" and type(isfile) == "function" then
        local okExists, exists = pcall(isfile, CHOICE_FILE)
        if okExists and exists then pcall(delfile, CHOICE_FILE) end
    end
end

local function compiler()
    return loadstring or load
end

local function requestFn()
    if type(request) == "function" then return request end
    if type(http_request) == "function" then return http_request end
    if syn and type(syn.request) == "function" then return syn.request end
    if http and type(http.request) == "function" then return http.request end
    if fluxus and type(fluxus.request) == "function" then return fluxus.request end
    return nil
end

local function decode(text)
    local ok, value = pcall(function()
        return HttpService:JSONDecode(tostring(text or "{}"))
    end)
    return ok and value or nil
end

local function encode(value)
    return HttpService:UrlEncode(tostring(value or ""))
end

local function executorName()
    local probes = {
        function()
            if identifyexecutor then
                local name, version = identifyexecutor()
                if name then
                    return version and (tostring(name) .. " " .. tostring(version)) or tostring(name)
                end
            end
        end,
        function()
            if getexecutorname then return tostring(getexecutorname()) end
        end,
        function()
            if syn then return "Synapse-compatible" end
        end,
    }
    for _, probe in ipairs(probes) do
        local ok, value = pcall(probe)
        if ok and value and tostring(value) ~= "" then
            return tostring(value)
        end
    end
    return "Unknown"
end

local function deviceIdentifier()
    local probes = {
        function() if gethwid then return "hwid:" .. tostring(gethwid()) end end,
        function() if syn and syn.get_hwid then return "syn:" .. tostring(syn.get_hwid()) end end,
        function()
            return "rbxclient:" .. tostring(game:GetService("RbxAnalyticsService"):GetClientId())
        end,
    }
    for _, probe in ipairs(probes) do
        local ok, value = pcall(probe)
        if ok and value and tostring(value) ~= "" then return tostring(value) end
    end
    return nil
end

local function readSavedKey()
    local envKey = normalizeKey(ENV.PuckHubKey)
    if envKey ~= "" then return envKey end

    if type(isfile) == "function" and type(readfile) == "function" then
        local okExists, exists = pcall(isfile, KEY_FILE)
        if okExists and exists then
            local okRead, value = pcall(readfile, KEY_FILE)
            if okRead then return normalizeKey(value) end
        end
    end
    return ""
end

local function saveKey(key)
    key = normalizeKey(key)
    if key == "" then return false end
    ENV.PuckHubKey = key

    if type(writefile) ~= "function" then return true end
    if type(makefolder) == "function" then pcall(makefolder, "PuckHub") end
    local ok = pcall(writefile, KEY_FILE, key)
    return ok
end

local function clearSavedKey()
    ENV.PuckHubKey = nil
    if type(delfile) == "function" and type(isfile) == "function" then
        local okExists, exists = pcall(isfile, KEY_FILE)
        if okExists and exists then pcall(delfile, KEY_FILE) end
    end
end

local function openWebsite(url)
    url = trim(url)
    if url == "" then return false, "empty-url" end

    -- Executors expose native URL opening under different globals/tables.
    -- Search the common environments first and invoke only known URL-opener names.
    local openerNames = {
        "openurl", "open_url", "openUrl", "OpenUrl",
        "openlink", "open_link", "openLink", "OpenLink",
        "launchurl", "launch_url", "launchUrl", "LaunchUrl",
        "openbrowser", "open_browser", "openBrowser", "OpenBrowser",
        "openbrowserwindow", "open_browser_window", "openBrowserWindow", "OpenBrowserWindow",
        "openuri", "open_uri", "openUri", "OpenUri",
        "shellopen", "shell_open", "browse", "browser_open",
        "visiturl", "visit_url",
    }

    local tables = {}
    local seenTables = {}
    local function addTable(value, label)
        if type(value) == "table" and not seenTables[value] then
            seenTables[value] = true
            table.insert(tables, {value = value, label = label})
        end
    end

    addTable(ENV, "executor")
    addTable(_G, "_G")
    addTable(rawget(ENV, "syn"), "syn")
    addTable(rawget(ENV, "fluxus"), "fluxus")
    addTable(rawget(ENV, "krnl"), "krnl")
    addTable(rawget(ENV, "executor"), "executor-table")
    addTable(rawget(ENV, "wave"), "wave")
    addTable(rawget(ENV, "solara"), "solara")
    addTable(rawget(ENV, "swift"), "swift")
    addTable(rawget(ENV, "delta"), "delta")

    if type(getrenv) == "function" then
        local ok, renv = pcall(getrenv)
        if ok then addTable(renv, "getrenv") end
    end
    if type(getfenv) == "function" then
        local ok, fenv = pcall(getfenv, 0)
        if ok then addTable(fenv, "getfenv") end
    end

    local seenFns = {}
    for _, entry in ipairs(tables) do
        local tbl = entry.value
        for _, name in ipairs(openerNames) do
            local okRead, fn = pcall(function() return rawget(tbl, name) end)
            if okRead and type(fn) == "function" and not seenFns[fn] then
                seenFns[fn] = true

                local ok, result = pcall(fn, url)
                if ok and result ~= false then
                    return true, entry.label .. "." .. name
                end

                -- Some executor APIs are methods and expect their owning table.
                ok, result = pcall(fn, tbl, url)
                if ok and result ~= false then
                    return true, entry.label .. ":" .. name
                end
            end
        end
    end

    local function getService(name)
        local ok, service = pcall(game.GetService, game, name)
        if not ok or not service then return nil end
        if type(cloneref) == "function" then
            local cloneOk, cloned = pcall(cloneref, service)
            if cloneOk and cloned then service = cloned end
        end
        return service
    end

    -- LinkingService is Roblox's native external-URL bridge. Executors that
    -- expose RobloxScriptSecurity can call this directly.
    local linking = getService("LinkingService")
    if linking then
        local ok, result = pcall(function()
            return linking:OpenUrl(url)
        end)
        if ok and result ~= false then
            return true, "LinkingService.OpenUrl"
        end
    end

    -- Older executor builds may expose one of these browser bridges instead.
    local serviceAttempts = {
        {
            label = "BrowserService.OpenBrowserWindow",
            run = function()
                local service = getService("BrowserService")
                if not service then error("BrowserService unavailable") end
                return service:OpenBrowserWindow(url)
            end,
        },
        {
            label = "GuiService.OpenBrowserWindow",
            run = function()
                local service = getService("GuiService")
                if not service then error("GuiService unavailable") end
                return service:OpenBrowserWindow(url)
            end,
        },
        {
            label = "BrowserService.OpenNativeOverlay",
            run = function()
                local service = getService("BrowserService")
                if not service then error("BrowserService unavailable") end
                return service:OpenNativeOverlay("PuckAFK", url)
            end,
        },
    }

    for _, attempt in ipairs(serviceAttempts) do
        local ok, result = pcall(attempt.run)
        if ok and result ~= false then
            return true, attempt.label
        end
    end

    -- Last compatibility pass: some executors only allow these protected
    -- services while the current thread identity is elevated.
    local getIdentity = type(getthreadidentity) == "function" and getthreadidentity
        or (type(getidentity) == "function" and getidentity or nil)
    local setIdentity = type(setthreadidentity) == "function" and setthreadidentity
        or (type(setidentity) == "function" and setidentity or nil)

    if getIdentity and setIdentity then
        local oldIdentity
        pcall(function() oldIdentity = getIdentity() end)
        local raised = pcall(setIdentity, 8)
        if raised then
            local elevatedLinking = getService("LinkingService")
            if elevatedLinking then
                local ok, result = pcall(function()
                    return elevatedLinking:OpenUrl(url)
                end)
                if ok and result ~= false then
                    if oldIdentity ~= nil then pcall(setIdentity, oldIdentity) end
                    return true, "LinkingService.OpenUrl/elevated"
                end
            end

            local elevatedBrowser = getService("BrowserService")
            if elevatedBrowser then
                local ok, result = pcall(function()
                    return elevatedBrowser:OpenBrowserWindow(url)
                end)
                if ok and result ~= false then
                    if oldIdentity ~= nil then pcall(setIdentity, oldIdentity) end
                    return true, "BrowserService.OpenBrowserWindow/elevated"
                end
            end
        end
        if oldIdentity ~= nil then pcall(setIdentity, oldIdentity) end
    end

    return false, "no-supported-opener"
end

local function fetchText(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" and #body > 0 then
        return true, body
    end

    local req = requestFn()
    if req then
        local requestOk, response = pcall(req, {Url = url, Method = "GET"})
        if requestOk and type(response) == "table" then
            local status = tonumber(response.StatusCode or response.Status or response.status) or 0
            local responseBody = response.Body or response.body
            if status >= 200 and status < 300 and type(responseBody) == "string" then
                return true, responseBody
            end
        end
    end

    return false, tostring(body or "HTTP request failed")
end

local function launchSource(source, label)
    local compile = compiler()
    if type(compile) ~= "function" then
        return false, "This executor does not provide loadstring/load."
    end
    local chunk, compileError = compile(source)
    if not chunk then
        return false, (label or "Script") .. " compile failed: " .. tostring(compileError)
    end

    local ok, runtimeError = pcall(chunk)
    if not ok then
        return false, (label or "Script") .. " failed: " .. tostring(runtimeError)
    end
    return true
end

local function launchFree(setStatus)
    if setStatus then setStatus("Loading Free access…") end
    ENV.PuckHubCurrentAccessMode = "free"
    ENV.PuckHubAccessMode = "free"

    local ok, source = fetchText(FREE_LOADER)
    if not ok then
        ENV.PuckHubAccessMode = nil
        if setStatus then setStatus("Could not download the Free loader.", true) end
        return false
    end

    local launched, err = launchSource(source, "Free loader")
    ENV.PuckHubAccessMode = nil
    if not launched then
        if setStatus then setStatus(err, true) end
        return false
    end
    return true
end

local function buildResolveUrl(base)
    local player = Players.LocalPlayer
    return base .. "/resolve"
        .. "?placeId=" .. encode(game.PlaceId)
        .. "&universeId=" .. encode(game.GameId)
        .. "&robloxUserId=" .. encode(player and player.UserId or "Unknown")
        .. "&robloxUsername=" .. encode(player and player.Name or "Unknown")
        .. "&executor=" .. encode(executorName())
        .. "&jobId=" .. encode(game.JobId or "")
end

local function resolvePremium()
    local urls = {
        buildResolveUrl(PREMIUM_API),
        buildResolveUrl(PREMIUM_API_FALLBACK),
    }

    local lastError = "Premium service is unavailable."
    for _, url in ipairs(urls) do
        local ok, body = fetchText(url)
        if ok then
            local data = decode(body)
            if data then return true, data end
            lastError = "Premium service returned an invalid response."
        else
            lastError = body
        end
    end
    return false, lastError
end

local function postPremiumSource(base, payload)
    local req = requestFn()
    if type(req) ~= "function" then
        return false, nil, "Premium access requires an executor HTTP request function."
    end

    local ok, response = pcall(req, {
        Url = base .. "/source",
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "text/plain, application/json",
        },
        Body = HttpService:JSONEncode(payload),
    })

    if not ok or type(response) ~= "table" then
        return false, nil, tostring(response or "Premium request failed")
    end

    local status = tonumber(response.StatusCode or response.Status or response.status) or 0
    local body = response.Body or response.body or ""
    if status == 200 and type(body) == "string" and #body > 0 then
        return true, body
    end

    local detail = decode(body)
    local message = detail and (detail.message or detail.error or detail.code)
    return false, status, tostring(message or ("HTTP " .. tostring(status)))
end

local premiumBusy = false
local function launchPremium(key, setStatus)
    if premiumBusy then return false end
    premiumBusy = true

    key = normalizeKey(key)
    if key == "" then
        premiumBusy = false
        setStatus("Enter your PuckHub Premium key first.", true)
        return false
    end
    if #key < 8 or #key > 256 then
        premiumBusy = false
        setStatus("That Premium key format does not look valid.", true)
        return false
    end

    setStatus("Checking Premium support for this game…")
    local resolveOk, info = resolvePremium()
    if not resolveOk then
        premiumBusy = false
        setStatus("Could not reach the Premium service. Try again in a moment.", true)
        return false
    end

    if not info.premium then
        premiumBusy = false
        local gameName = tostring(info.name or "this game")
        setStatus("No Premium release is available for " .. gameName .. ". Use Free access instead.", true)
        return false
    end

    local hwid = deviceIdentifier()
    if not hwid then
        premiumBusy = false
        setStatus("Could not determine a stable device identifier for Premium validation.", true)
        return false
    end

    local player = Players.LocalPlayer
    local payload = {
        key = key,
        hwid = hwid,
        slug = info.slug,
        executor = executorName(),
        script = info.name or info.slug,
        placeId