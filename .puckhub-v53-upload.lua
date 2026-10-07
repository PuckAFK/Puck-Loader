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
        placeId = tostring(game.PlaceId),
        universeId = tostring(game.GameId),
        jobId = tostring(game.JobId or ""),
        robloxUserId = player and tostring(player.UserId) or "Unknown",
        robloxUsername = player and tostring(player.Name) or "Unknown",
    }

    setStatus("Validating your PuckHub key…")
    local okSource, source, reason = postPremiumSource(PREMIUM_API, payload)
    if not okSource then
        okSource, source, reason = postPremiumSource(PREMIUM_API_FALLBACK, payload)
    end

    if not okSource then
        premiumBusy = false
        setStatus("Premium key rejected: " .. tostring(reason or "validation failed"), true)
        return false
    end

    setStatus("Key accepted. Launching Premium…")
    ENV.PuckHubCurrentAccessMode = "premium"
    ENV.PuckHubAccessMode = "premium"
    ENV.PuckHubKey = key
    saveKey(key)

    local launched, runtimeError = launchSource(source, tostring(info.name or "Premium script"))
    ENV.PuckHubAccessMode = nil
    premiumBusy = false
    if not launched then
        setStatus(runtimeError, true)
        return false
    end

    setStatus("Premium loaded successfully.")
    return true
end

-- ============================================================================
-- PuckAFK access gate v5.3
-- Custom interface (not PuckUI) with Roblox image icons, responsive layout,
-- animated cards, explicit remember-choice control, and compact Premium flow.
-- ============================================================================

local ACCESS_GUI_NAME = "PuckAFKAccessLoader"

local THEME = {
    Backdrop = Color3.fromRGB(4, 6, 10),
    Main = Color3.fromRGB(11, 13, 18),
    Main2 = Color3.fromRGB(15, 18, 25),
    Surface = Color3.fromRGB(18, 22, 31),
    Surface2 = Color3.fromRGB(23, 28, 39),
    SurfaceHover = Color3.fromRGB(29, 35, 48),
    Stroke = Color3.fromRGB(48, 57, 74),
    StrokeSoft = Color3.fromRGB(34, 41, 55),
    Text = Color3.fromRGB(235, 239, 248),
    Muted = Color3.fromRGB(148, 158, 178),
    Faint = Color3.fromRGB(91, 101, 122),
    Accent = Color3.fromRGB(73, 132, 255),
    Accent2 = Color3.fromRGB(109, 91, 255),
    AccentSoft = Color3.fromRGB(24, 43, 80),
    Premium = Color3.fromRGB(244, 196, 77),
    PremiumSoft = Color3.fromRGB(55, 45, 21),
    Success = Color3.fromRGB(83, 201, 126),
    SuccessSoft = Color3.fromRGB(22, 53, 36),
    Danger = Color3.fromRGB(239, 95, 105),
    DangerSoft = Color3.fromRGB(61, 28, 34),
    Discord = Color3.fromRGB(88, 101, 242),
    DiscordSoft = Color3.fromRGB(31, 34, 62),
}

-- Real Roblox image assets. General controls use Lucide icon assets; Discord uses
-- a dedicated Discord logo image asset rather than a shape approximation.
local ICON = {
    Discord = "rbxassetid://18977771125",
    Crown = "rbxassetid://7733765398",
    Gamepad = "rbxassetid://7733799795",
    ShieldCheck = "rbxassetid://7734056411",
    ExternalLink = "rbxassetid://7743866903",
    Globe = "rbxassetid://7733954760",
    Key = "rbxassetid://7733965118",
    Trash = "rbxassetid://7743873772",
    Back = "rbxassetid://7733717651",
    Check = "rbxassetid://7733715400",
    Lock = "rbxassetid://7733992528",
    Loader = "rbxassetid://7733989869",
    Close = "rbxassetid://7743878496",
    Info = "rbxassetid://7733964719",
    Gift = "rbxassetid://7733946818",
}

local function accessCreate(className, properties)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    return object
end

local function accessTween(object, duration, properties, style, direction)
    if not object or not object.Parent then return nil end
    local tween = TweenService:Create(
        object,
        TweenInfo.new(duration or 0.14, style or Enum.EasingStyle.Quart, direction or Enum.EasingDirection.Out),
        properties
    )
    tween:Play()
    return tween
end

local function corner(parent, radius)
    return accessCreate("UICorner", {CornerRadius = UDim.new(0, radius or 10), Parent = parent})
end

local function stroke(parent, color, transparency, thickness)
    return accessCreate("UIStroke", {
        Color = color or THEME.Stroke,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function label(parent, text, size, color, font, z)
    return accessCreate("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = tostring(text or ""),
        TextColor3 = color or THEME.Text,
        TextSize = size or 13,
        Font = font or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = z or 20,
        Parent = parent,
    })
end

local function image(parent, asset, position, size, color, z)
    return accessCreate("ImageLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = asset,
        ImageColor3 = color or THEME.Text,
        Position = position,
        Size = size,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = z or 20,
        Parent = parent,
    })
end

local function accessGuiParent(screenGui)
    local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
    local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
    if playerGui then
        local ok = pcall(function() screenGui.Parent = playerGui end)
        if ok and screenGui.Parent == playerGui then return playerGui end
    end
    if type(gethui) == "function" then
        local ok, target = pcall(gethui)
        if ok and target then
            local parented = pcall(function() screenGui.Parent = target end)
            if parented then return target end
        end
    end
    local ok = pcall(function() screenGui.Parent = CoreGui end)
    if ok then return CoreGui end
    return nil
end

local function destroyOldAccessGui()
    local parents = {CoreGui}
    local player = Players.LocalPlayer
    if player then
        local playerGui = player:FindFirstChildOfClass("PlayerGui")
        if playerGui then table.insert(parents, playerGui) end
    end
    if type(gethui) == "function" then
        local ok, target = pcall(gethui)
        if ok and target then table.insert(parents, target) end
    end
    for _, parent in ipairs(parents) do
        pcall(function()
            local old = parent:FindFirstChild(ACCESS_GUI_NAME)
            if old then old:Destroy() end
        end)
    end
end

local function makeIconButton(parent, config)
    config = config or {}
    local button = accessCreate("TextButton", {
        Name = config.Name or "IconButton",
        Position = config.Position or UDim2.fromOffset(0, 0),
        Size = config.Size or UDim2.fromOffset(36, 36),
        BackgroundColor3 = config.BackgroundColor3 or THEME.Surface,
        BackgroundTransparency = config.BackgroundTransparency or 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        ZIndex = config.ZIndex or 30,
        Parent = parent,
    })
    corner(button, config.CornerRadius or 9)
    local outline = stroke(button, config.StrokeColor3 or THEME.StrokeSoft, config.StrokeTransparency or 0, 1)
    local icon = image(
        button,
        config.Icon or ICON.Info,
        UDim2.fromScale(0.5, 0.5),
        config.IconSize or UDim2.fromOffset(17, 17),
        config.IconColor3 or THEME.Muted,
        button.ZIndex + 1
    )
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    local scale = accessCreate("UIScale", {Scale = 1, Parent = button})

    button.MouseEnter:Connect(function()
        accessTween(button, 0.12, {BackgroundColor3 = config.HoverColor3 or THEME.SurfaceHover})
        accessTween(outline, 0.12, {Color = config.HoverStrokeColor3 or THEME.Stroke})
        accessTween(icon, 0.12, {ImageColor3 = config.HoverIconColor3 or THEME.Text})
        accessTween(scale, 0.12, {Scale = 1.04})
    end)
    button.MouseLeave:Connect(function()
        accessTween(button, 0.12, {BackgroundColor3 = config.BackgroundColor3 or THEME.Surface})
        accessTween(outline, 0.12, {Color = config.StrokeColor3 or THEME.StrokeSoft})
        accessTween(icon, 0.12, {ImageColor3 = config.IconColor3 or THEME.Muted})
        accessTween(scale, 0.12, {Scale = 1})
    end)
    button.MouseButton1Down:Connect(function() accessTween(scale, 0.06, {Scale = 0.94}) end)
    button.MouseButton1Up:Connect(function() accessTween(scale, 0.08, {Scale = 1.04}) end)
    button.Activated:Connect(function()
        if config.Callback then config.Callback() end
    end)
    return button, icon
end

local function makeButton(parent, config)
    config = config or {}
    local base = config.BackgroundColor3 or THEME.Surface2
    local hover = config.HoverColor3 or THEME.SurfaceHover
    local button = accessCreate("TextButton", {
        Name = config.Name or "Button",
        Position = config.Position or UDim2.fromOffset(0, 0),
        Size = config.Size or UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = base,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        ZIndex = config.ZIndex or 25,
        Parent = parent,
    })
    corner(button, config.CornerRadius or 11)
    local outline = stroke(button, config.StrokeColor3 or THEME.StrokeSoft, config.StrokeTransparency or 0, 1)
    local scale = accessCreate("UIScale", {Scale = 1, Parent = button})

    local icon
    if config.Icon then
        icon = image(button, config.Icon, UDim2.fromOffset(14, 0), UDim2.fromOffset(config.IconPixels or 18, config.IconPixels or 18), config.IconColor3 or config.TextColor3 or THEME.Text, button.ZIndex + 1)
        icon.AnchorPoint = Vector2.new(0, 0.5)
        icon.Position = UDim2.new(0, 14, 0.5, 0)
    end

    local text = label(button, config.Text or "Button", config.TextSize or 12, config.TextColor3 or THEME.Text, config.Font or Enum.Font.GothamMedium, button.ZIndex + 1)
    text.Position = config.Icon and UDim2.fromOffset(44, 0) or UDim2.fromOffset(14, 0)
    text.Size = config.RightIcon and UDim2.new(1, config.Icon and -82 or -52, 1, 0) or UDim2.new(1, config.Icon and -58 or -28, 1, 0)
    text.TextXAlignment = config.TextXAlignment or Enum.TextXAlignment.Left

    local rightIcon
    if config.RightIcon then
        rightIcon = image(button, config.RightIcon, UDim2.new(1, -14, 0.5, 0), UDim2.fromOffset(16, 16), config.RightIconColor3 or THEME.Muted, button.ZIndex + 1)
        rightIcon.AnchorPoint = Vector2.new(1, 0.5)
    end

    local function setHover(on)
        accessTween(button, 0.12, {BackgroundColor3 = on and hover or base})
        accessTween(outline, 0.12, {Color = on and (config.HoverStrokeColor3 or config.AccentColor3 or THEME.Stroke) or (config.StrokeColor3 or THEME.StrokeSoft)})
        accessTween(scale, 0.12, {Scale = on and 1.012 or 1})
        if icon then accessTween(icon, 0.12, {ImageColor3 = on and (config.HoverIconColor3 or config.AccentColor3 or config.IconColor3 or config.TextColor3 or THEME.Text) or (config.IconColor3 or config.TextColor3 or THEME.Text)}) end
        if rightIcon then accessTween(rightIcon, 0.12, {ImageColor3 = on and THEME.Text or (config.RightIconColor3 or THEME.Muted)}) end
    end
    button.MouseEnter:Connect(function() setHover(true) end)
    button.MouseLeave:Connect(function() setHover(false) end)
    button.MouseButton1Down:Connect(function() accessTween(scale, 0.06, {Scale = 0.975}) end)
    button.MouseButton1Up:Connect(function() accessTween(scale, 0.08, {Scale = 1.012}) end)
    button.Activated:Connect(function()
        accessTween(scale, 0.055, {Scale = 0.965})
        task.delay(0.06, function() if scale.Parent then accessTween(scale, 0.10, {Scale = 1}) end end)
        if config.Callback then config.Callback() end
    end)
    return button, text, icon, outline
end

local function makeStatus(parent, position, size)
    local pill = accessCreate("Fr