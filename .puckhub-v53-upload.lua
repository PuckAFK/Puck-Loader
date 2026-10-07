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
    local pill = accessCreate("Frame", {
        Position = position,
        Size = size,
        BackgroundColor3 = THEME.Surface,
        BorderSizePixel = 0,
        ZIndex = 28,
        Parent = parent,
    })
    corner(pill, 9)
    local outline = stroke(pill, THEME.StrokeSoft, 0.15, 1)
    local dot = accessCreate("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = THEME.Faint,
        BorderSizePixel = 0,
        ZIndex = 29,
        Parent = pill,
    })
    corner(dot, 99)
    local text = label(pill, "Ready", 10, THEME.Muted, Enum.Font.Gotham, 29)
    text.Position = UDim2.fromOffset(28, 0)
    text.Size = UDim2.new(1, -40, 1, 0)
    text.TextTruncate = Enum.TextTruncate.AtEnd

    local function setStatus(message, isError, isSuccess)
        local color = isError and THEME.Danger or (isSuccess and THEME.Success or THEME.Accent)
        local soft = isError and THEME.DangerSoft or (isSuccess and THEME.SuccessSoft or THEME.AccentSoft)
        text.Text = tostring(message or "")
        text.TextColor3 = isError and Color3.fromRGB(255, 179, 185) or (isSuccess and Color3.fromRGB(175, 246, 199) or THEME.Muted)
        accessTween(pill, 0.16, {BackgroundColor3 = soft})
        accessTween(dot, 0.16, {BackgroundColor3 = color})
        accessTween(outline, 0.16, {Color = color, Transparency = 0.35})
        text.TextTransparency = 0.25
        accessTween(text, 0.16, {TextTransparency = 0})
        task.delay(1.2, function()
            if pill.Parent and not isError and not isSuccess then
                accessTween(pill, 0.22, {BackgroundColor3 = THEME.Surface})
                accessTween(outline, 0.22, {Color = THEME.StrokeSoft, Transparency = 0.15})
            end
        end)
    end

    return pill, text, setStatus
end

local function makeToggle(parent, position, width, initial, callback)
    local enabled = initial and true or false
    local button = accessCreate("TextButton", {
        Position = position,
        Size = UDim2.fromOffset(width, 42),
        BackgroundColor3 = THEME.Surface,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        ZIndex = 25,
        Parent = parent,
    })
    corner(button, 10)
    local outline = stroke(button, THEME.StrokeSoft, 0, 1)

    local title = label(button, "Remember my choice", 11, THEME.Text, Enum.Font.GothamMedium, 27)
    title.Position = UDim2.fromOffset(13, 2)
    title.Size = UDim2.new(1, -74, 0, 22)
    local sub = label(button, "Skip repeated setup next time", 9, THEME.Faint, Enum.Font.Gotham, 27)
    sub.Position = UDim2.fromOffset(13, 20)
    sub.Size = UDim2.new(1, -74, 0, 16)

    local track = accessCreate("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(39, 22),
        BackgroundColor3 = THEME.StrokeSoft,
        BorderSizePixel = 0,
        ZIndex = 27,
        Parent = button,
    })
    corner(track, 99)
    local knob = accessCreate("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BackgroundColor3 = THEME.Muted,
        BorderSizePixel = 0,
        ZIndex = 28,
        Parent = track,
    })
    corner(knob, 99)
    local check = image(knob, ICON.Check, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(11, 11), Color3.new(1, 1, 1), 29)
    check.AnchorPoint = Vector2.new(0.5, 0.5)
    check.ImageTransparency = 1

    local function render(animated)
        local duration = animated and 0.16 or 0
        accessTween(track, duration, {BackgroundColor3 = enabled and THEME.Accent or THEME.StrokeSoft})
        accessTween(knob, duration, {
            Position = enabled and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            BackgroundColor3 = enabled and Color3.new(1, 1, 1) or THEME.Muted,
        })
        accessTween(check, duration, {ImageTransparency = enabled and 0 or 1, ImageColor3 = THEME.Accent})
        accessTween(outline, duration, {Color = enabled and THEME.Accent or THEME.StrokeSoft, Transparency = enabled and 0.45 or 0})
    end
    render(false)

    button.MouseEnter:Connect(function() accessTween(button, 0.12, {BackgroundColor3 = THEME.SurfaceHover}) end)
    button.MouseLeave:Connect(function() accessTween(button, 0.12, {BackgroundColor3 = THEME.Surface}) end)
    button.Activated:Connect(function()
        enabled = not enabled
        render(true)
        if callback then callback(enabled) end
    end)

    return button, function(value)
        enabled = value and true or false
        render(true)
    end, function() return enabled end
end

local function makeAccessCard(parent, config)
    local card = accessCreate("TextButton", {
        Name = config.Name or "AccessCard",
        Position = config.Position,
        Size = config.Size,
        BackgroundColor3 = config.BackgroundColor3 or THEME.Surface,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        ZIndex = 20,
        Parent = parent,
    })
    corner(card, 14)
    local outline = stroke(card, config.StrokeColor3 or THEME.StrokeSoft, 0, 1)
    local scale = accessCreate("UIScale", {Scale = 1, Parent = card})

    local iconBack = accessCreate("Frame", {
        Position = UDim2.fromOffset(14, 14),
        Size = UDim2.fromOffset(38, 38),
        BackgroundColor3 = config.IconBackground or THEME.AccentSoft,
        BorderSizePixel = 0,
        ZIndex = 22,
        Parent = card,
    })
    corner(iconBack, 10)
    local icon = image(iconBack, config.Icon, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(21, 21), config.AccentColor or THEME.Accent, 23)
    icon.AnchorPoint = Vector2.new(0.5, 0.5)

    local tag = label(card, config.Tag or "ACCESS", 9, config.AccentColor or THEME.Accent, Enum.Font.GothamBold, 23)
    tag.Position = UDim2.fromOffset(64, 12)
    tag.Size = UDim2.new(1, -78, 0, 16)
    local title = label(card, config.Title or "Access", 18, THEME.Text, Enum.Font.GothamBold, 23)
    title.Position = UDim2.fromOffset(64, 27)
    title.Size = UDim2.new(1, -78, 0, 25)
    local desc = label(card, config.Description or "", 10, THEME.Muted, Enum.Font.Gotham, 23)
    desc.Position = UDim2.fromOffset(14, 61)
    desc.Size = UDim2.new(1, -28, 0, 34)
    desc.TextWrapped = true
    desc.TextYAlignment = Enum.TextYAlignment.Top

    local action = accessCreate("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 14, 1, -13),
        Size = UDim2.new(1, -28, 0, 33),
        BackgroundColor3 = config.ActionColor or THEME.Accent,
        BorderSizePixel = 0,
        ZIndex = 22,
        Parent = card,
    })
    corner(action, 9)
    local actionText = label(action, config.ActionText or "Continue", 11, config.ActionTextColor or Color3.new(1, 1, 1), Enum.Font.GothamBold, 23)
    actionText.Size = UDim2.new(1, -44, 1, 0)
    actionText.Position = UDim2.fromOffset(13, 0)
    local arrow = image(action, ICON.ExternalLink, UDim2.new(1, -13, 0.5, 0), UDim2.fromOffset(15, 15), config.ActionTextColor or Color3.new(1, 1, 1), 23)
    arrow.AnchorPoint = Vector2.new(1, 0.5)

    card.MouseEnter:Connect(function()
        accessTween(card, 0.14, {BackgroundColor3 = config.HoverColor3 or THEME.SurfaceHover})
        accessTween(outline, 0.14, {Color = config.AccentColor or THEME.Accent, Transparency = 0.25})
        accessTween(scale, 0.14, {Scale = 1.015})
        accessTween(action, 0.14, {BackgroundColor3 = config.ActionHoverColor or config.ActionColor or THEME.Accent})
    end)
    card.MouseLeave:Connect(function()
        accessTween(card, 0.14, {BackgroundColor3 = config.BackgroundColor3 or THEME.Surface})
        accessTween(outline, 0.14, {Color = config.StrokeColor3 or THEME.StrokeSoft, Transparency = 0})
        accessTween(scale, 0.14, {Scale = 1})
        accessTween(action, 0.14, {BackgroundColor3 = config.ActionColor or THEME.Accent})
    end)
    card.MouseButton1Down:Connect(function() accessTween(scale, 0.06, {Scale = 0.98}) end)
    card.MouseButton1Up:Connect(function() accessTween(scale, 0.08, {Scale = 1.015}) end)
    card.Activated:Connect(function() if config.Callback then config.Callback() end end)
    return card
end

local function runAccessGate(openPremiumImmediately, rememberedChoice)
    destroyOldAccessGui()

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local phoneLayout = UserInputService.TouchEnabled and math.min(viewport.X, viewport.Y) <= 720
    local windowWidth = phoneLayout and 360 or 550
    local chooserHeight = phoneLayout and 520 or 390
    local premiumHeight = phoneLayout and 565 or 455
    local currentHeight = openPremiumImmediately and premiumHeight or chooserHeight
    local cancelled = false
    local busy = false
    ENV.PuckHubLoaderVersion = "5.3.0"

    local fitScale = math.min((viewport.X - 20) / windowWidth, (viewport.Y - 20) / premiumHeight)
    local uiScaleValue = math.max(0.68, math.min(1, fitScale))

    local gui = accessCreate("ScreenGui", {
        Name = ACCESS_GUI_NAME,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 10001,
    })
    accessGuiParent(gui)

    local dim = accessCreate("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = THEME.Backdrop,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = gui,
    })

    local shell = accessCreate("CanvasGroup", {
        Name = "Shell",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 14),
        Size = UDim2.fromOffset(windowWidth, currentHeight - 12),
        BackgroundColor3 = THEME.Main,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Active = true,
        ZIndex = 10,
        Parent = gui,
    })
    corner(shell, 16)
    local shellStroke = stroke(shell, THEME.Stroke, 0.1, 1)
    local shellScale = accessCreate("UIScale", {Scale = uiScaleValue, Parent = shell})

    accessCreate("UIGradient", {
        Rotation = 120,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, THEME.Main2),
            ColorSequenceKeypoint.new(0.55, THEME.Main),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 14, 23)),
        }),
        Parent = shell,
    })

    local glow = accessCreate("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.new(0.62, 0, 0, 2),
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ZIndex = 13,
        Parent = shell,
    })
    corner(glow, 99)
    accessCreate("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.25, 0),
            NumberSequenceKeypoint.new(0.75, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = glow,
    })

    local topbar = accessCreate("Frame", {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 15,
        Parent = shell,
    })

    local brandIconBack = accessCreate("Frame", {
        Position = UDim2.fromOffset(14, 11),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = THEME.AccentSoft,
        BorderSizePixel = 0,
        ZIndex = 16,
        Parent = topbar,
    })
    corner(brandIconBack, 8)
    local brandIcon = image(brandIconBack, ICON.Gamepad, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(17, 17), THEME.Accent, 17)
    brandIcon.AnchorPoint = Vector2.new(0.5, 0.5)

    local brand = label(topbar, "PuckAFK Hub", 13, THEME.Text, Enum.Font.GothamBold, 17)
    brand.Position = UDim2.fromOffset(51, 8)
    brand.Size = UDim2.new(1, -130, 0, 20)
    local version = label(topbar, "ACCESS  •  v5.3", 8, THEME.Faint, Enum.Font.GothamBold, 17)
    version.Position = UDim2.fromOffset(51, 26)
    version.Size = UDim2.new(1, -130, 0, 15)

    local closeButton = makeIconButton(topbar, {
        Name = "Close",
        Position = UDim2.new(1, -47, 0, 10),
        Size = UDim2.fromOffset(34, 30),
        Icon = ICON.Close,
        IconSize = UDim2.fromOffset(15, 15),
        BackgroundColor3 = Color3.fromRGB(18, 21, 29),
        HoverColor3 = THEME.DangerSoft,
        HoverStrokeColor3 = THEME.Danger,
        HoverIconColor3 = Color3.fromRGB(255, 174, 181),
    })

    local divider = accessCreate("Frame", {
        Position = UDim2.fromOffset(14, 49),
        Size = UDim2.new(1, -28, 0, 1),
        BackgroundColor3 = THEME.StrokeSoft,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        ZIndex = 15,
        Parent = shell,
    })

    local body = accessCreate("Frame", {
        Position = UDim2.fromOffset(14, 60),
        Size = UDim2.new(1, -28, 1, -74),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 15,
        Parent = shell,
    })

    local chooser = accessCreate("CanvasGroup", {
        Name = "Chooser",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        GroupTransparency = openPremiumImmediately and 1 or 0,
        Visible = not openPremiumImmediately,
        ZIndex = 16,
        Parent = body,
    })

    local premium = accessCreate("CanvasGroup", {
        Name = "Premium",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        GroupTransparency = openPremiumImmediately and 0 or 1,
        Visible = openPremiumImmediately,
        ZIndex = 16,
        Parent = body,
    })

    local dragging = false
    local dragStart
    local startPosition
    local dragHandle = accessCreate("TextButton", {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, -56, 0, 50),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Active = true,
        ZIndex = 18,
        Parent = topbar,
    })
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = shell.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging or not dragStart or not startPosition then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            shell.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    local function closeAnimated()
        if cancelled then return end
        cancelled = true
        accessTween(dim, 0.16, {BackgroundTransparency = 1})
        accessTween(shell, 0.16, {GroupTransparency = 1, Position = UDim2.new(shell.Position.X.Scale, shell.Position.X.Offset, shell.Position.Y.Scale, shell.Position.Y.Offset + 10)})
        accessTween(shellScale, 0.16, {Scale = uiScaleValue * 0.97})
        task.delay(0.17, function() pcall(function() gui:Destroy() end) end)
    end
    closeButton.Activated:Connect(closeAnimated)

    local function resize(height)
        currentHeight = height
        accessTween(shell, 0.20, {Size = UDim2.fromOffset(windowWidth, height)}, Enum.EasingStyle.Quart)
    end

    local function switchPanel(from, to, targetHeight, direction)
        if busy or cancelled then return end
        direction = direction or 1
        to.Visible = true
        to.GroupTransparency = 1
        to.Position = UDim2.new(0, 18 * direction, 0, 0)
        accessTween(from, 0.13, {GroupTransparency = 1, Position = UDim2.new(0, -14 * direction, 0, 0)})
        resize(targetHeight)
        task.delay(0.10, function()
            if cancelled or not to.Parent then return end
            from.Visible = false
            from.Position = UDim2.fromScale(0, 0)
            accessTween(to, 0.20, {GroupTransparency = 0, Position = UDim2.fromScale(0, 0)}, Enum.EasingStyle.Quart)
        end)
    end

    -- ------------------------------------------------------------------------
    -- Chooser
    -- ------------------------------------------------------------------------
    local chooserTitle = label(chooser, "Choose your access", phoneLayout and 19 or 21, THEME.Text, Enum.Font.GothamBold, 20)
    chooserTitle.Position = UDim2.fromOffset(2, 0)
    chooserTitle.Size = UDim2.new(1, -4, 0, 30)
    local chooserSub = label(chooser, "Pick Free for the public hub or Premium to validate your PuckHub key.", 10, THEME.Muted, Enum.Font.Gotham, 20)
    chooserSub.Position = UDim2.fromOffset(2, 30)
    chooserSub.Size = UDim2.new(1, -4, 0, 24)
    chooserSub.TextWrapped = true

    rememberedChoice = normalizeChoice(rememberedChoice)
    local rememberChoice = rememberedChoice ~= ""
    local savedCountdownToken = 0
    local function cancelSavedCountdown() savedCountdownToken = savedCountdownToken + 1 end

    local chooserStatusPill, _, setChooserStatus = makeStatus(chooser, UDim2.new(0, 2, 1, -36), UDim2.new(1, -4, 0, 32))

    local freeCard
    local premiumCard
    local function chooseFree()
        if busy or cancelled then return end
        cancelSavedCountdown()
        if rememberChoice then saveChoice("free") else clearSavedChoice() end
        busy = true
        setChooserStatus("Loading Free access…", false, false)
        task.spawn(function()
            local ok = launchFree(function(message, isError)
                setChooserStatus(message, isError, not isError)
            end)
            busy = false
            if ok and not cancelled then
                setChooserStatus("Free access started.", false, true)
                task.wait(0.12)
                closeAnimated()
            end
        end)
    end

    local function choosePremium()
        if busy or cancelled then return end
        cancelSavedCountdown()
        if rememberChoice then saveChoice("premium") else clearSavedChoice() end
        switchPanel(chooser, premium, premiumHeight, 1)
    end

    if phoneLayout then
        freeCard = makeAccessCard(chooser, {
            Name = "FreeAccess",
            Position = UDim2.fromOffset(2, 66),
            Size = UDim2.new(1, -4, 0, 125),
            Icon = ICON.Gamepad,
            AccentColor = THEME.Accent,
            IconBackground = THEME.AccentSoft,
            Tag = "KEYLESS",
            Title = "Free access",
            Description = "Public PuckAFK scripts with no key required.",
            ActionText = "CONTINUE FREE",
            ActionColor = Color3.fromRGB(53, 103, 217),
            ActionHoverColor = THEME.Accent,
            Callback = chooseFree,
        })
        premiumCard = makeAccessCard(chooser, {
            Name = "PremiumAccess",
            Position = UDim2.fromOffset(2, 200),
            Size = UDim2.new(1, -4, 0, 125),
            BackgroundColor3 = Color3.fromRGB(25, 23, 20),
            HoverColor3 = Color3.fromRGB(34, 30, 23),
            StrokeColor3 = Color3.fromRGB(66, 57, 36),
            Icon = ICON.Crown,
            AccentColor = THEME.Premium,
            IconBackground = THEME.PremiumSoft,
            Tag = "PAID TIER",
            Title = "Premium access",
            Description = "Validate your key to unlock paid Premium scripts.",
            ActionText = "OPEN PREMIUM",
            ActionColor = Color3.fromRGB(154, 111, 31),
            ActionHoverColor = Color3.fromRGB(187, 139, 40),
            Callback = choosePremium,
        })
    else
        local cardWidth = math.floor((windowWidth - 28 - 10) / 2)
        freeCard = makeAccessCard(chooser, {
            Name = "FreeAccess",
            Position = UDim2.fromOffset(2, 67),
            Size = UDim2.fromOffset(cardWidth, 177),
            Icon = ICON.Gamepad,
            AccentColor = THEME.Accent,
            IconBackground = THEME.AccentSoft,
            Tag = "KEYLESS",
            Title = "Free access",
            Description = "Public PuckAFK scripts. No key, no account validation, just continue.",
            ActionText = "CONTINUE FREE",
            ActionColor = Color3.fromRGB(53, 103, 217),
            ActionHoverColor = THEME.Accent,
            Callback = chooseFree,
        })
        premiumCard = makeAccessCard(chooser, {
            Name = "PremiumAccess",
            Position = UDim2.fromOffset(cardWidth + 12, 67),
            Size = UDim2.fromOffset(cardWidth, 177),
            BackgroundColor3 = Color3.fromRGB(25, 23, 20),
            HoverColor3 = Color3.fromRGB(34, 30, 23),
            StrokeColor3 = Color3.fromRGB(66, 57, 36),
            Icon = ICON.Crown,
            AccentColor = THEME.Premium,
            IconBackground = THEME.PremiumSoft,
            Tag = "PAID TIER",
            Title = "Premium access",
            Description = "Validate your PuckHub key, then launch the paid release for this game.",
            ActionText = "OPEN PREMIUM",
            ActionColor = Color3.fromRGB(154, 111, 31),
            ActionHoverColor = Color3.fromRGB(187, 139, 40),
            Callback = choosePremium,
        })
    end

    local toggleY = phoneLayout and 336 or 257
    local _, setRememberToggle = makeToggle(chooser, UDim2.fromOffset(2, toggleY), windowWidth - 32, rememberChoice, function(value)
        rememberChoice = value
        cancelSavedCountdown()
        if not value then
            clearSavedChoice()
            rememberedChoice = ""
            setChooserStatus("Remember choice is off — you will be asked every time.", false, true)
        else
            setChooserStatus("Your next selection will be remembered.", false, true)
        end
    end)

    -- ------------------------------------------------------------------------
    -- Premium
    -- ------------------------------------------------------------------------
    local premiumBack = makeIconButton(premium, {
        Name = "Back",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(34, 32),
        Icon = ICON.Back,
        IconSize = UDim2.fromOffset(16, 16),
        Callback = function()
            if busy then return end
            switchPanel(premium, chooser, chooserHeight, -1)
        end,
    })

    local premiumTitle = label(premium, "Premium access", 19, THEME.Text, Enum.Font.GothamBold, 20)
    premiumTitle.Position = UDim2.fromOffset(45, -1)
    premiumTitle.Size = UDim2.new(1, -47, 0, 26)
    local premiumSub = label(premium, "Get your key, paste it below, then validate.", 10, THEME.Muted, Enum.Font.Gotham, 20)
    premiumSub.Position = UDim2.fromOffset(45, 24)
    premiumSub.Size = UDim2.new(1, -47, 0, 20)

    local setPremiumStatus
    local premiumStatusPill, _, premiumStatusSetter = makeStatus(premium, UDim2.new(0, 0, 1, -36), UDim2.new(1, 0, 0, 32))
    setPremiumStatus = premiumStatusSetter

    local discordCard = accessCreate("TextButton", {
        Name = "DiscordCard",
        Position = UDim2.fromOffset(0, 57),
        Size = UDim2.new(1, 0, 0, 68),
        BackgroundColor3 = THEME.DiscordSoft,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        ZIndex = 24,
        Parent = premium,
    })
    corner(discordCard, 13)
    local discordStroke = stroke(discordCard, Color3.fromRGB(65, 71, 130), 0.1, 1)
    local discordSc