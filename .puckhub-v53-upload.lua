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
    local ok = pcall(writefile