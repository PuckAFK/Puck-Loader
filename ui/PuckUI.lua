--[[
    PuckUI v3.5 - Responsive Release / Global Keybind + Configs
    Shared PuckAFK game-script UI.

    Combined from both supplied PuckUI variants:
      - Uses the fuller v2.2 control/API implementation as the functional base
      - Uses the tighter v3.0 "Exact Replica" palette and visual treatment
      - Keeps notifications, close/minimize, labels, paragraphs, dividers,
        inputs, refreshable dropdowns, setters/getters, and touch support
      - Keeps the compact dark/floral Aztup-style presentation
]]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local PuckUI = {
    Version = "3.5.0",
    Flags = {},
    Window = nil,
}

local Theme = {
    -- v3 "Exact Replica" palette
    Main = Color3.fromRGB(12, 12, 12),
    Top = Color3.fromRGB(12, 12, 12),
    Tab = Color3.fromRGB(12, 12, 12),
    Section = Color3.fromRGB(18, 18, 18),
    SectionInner = Color3.fromRGB(18, 18, 18),
    Element = Color3.fromRGB(24, 24, 24),
    ElementHover = Color3.fromRGB(32, 32, 32),
    Border = Color3.fromRGB(45, 45, 45),
    BorderDark = Color3.fromRGB(5, 5, 5),
    Text = Color3.fromRGB(170, 170, 170),
    DimText = Color3.fromRGB(100, 100, 100),
    BrightText = Color3.fromRGB(230, 230, 230),
    Accent = Color3.fromRGB(0, 95, 255),

    -- Kept from the fuller build for APIs/notifications that use semantic colors.
    Danger = Color3.fromRGB(180, 58, 64),
    Success = Color3.fromRGB(48, 145, 78),
}

PuckUI.Theme = Theme

-- One keybind state shared by every PuckAFK UI loaded in this Roblox session.
-- Changing it from any script's Settings tab immediately updates every other
-- currently-loaded PuckUI window as well.
local function getSharedEnvironment()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then
            return env
        end
    end

    return _G
end

local SharedEnvironment = getSharedEnvironment()
SharedEnvironment.__PUCKAFK_UI_SHARED_STATE =
    SharedEnvironment.__PUCKAFK_UI_SHARED_STATE
    or {
        ToggleKeyName = "K",
        Windows = setmetatable({}, {__mode = "k"}),
        CapturingWindow = nil,
        CapturingControl = nil,
        SuppressToggleUntil = 0,
        LayoutMode = "Auto",
        UIScalePercent = 100,
    }

local SharedUIState = SharedEnvironment.__PUCKAFK_UI_SHARED_STATE
SharedUIState.ToggleKeyName = SharedUIState.ToggleKeyName or "K"
SharedUIState.Windows = SharedUIState.Windows or setmetatable({}, {__mode = "k"})
SharedUIState.SuppressToggleUntil = SharedUIState.SuppressToggleUntil or 0
SharedUIState.LayoutMode = tostring(SharedUIState.LayoutMode or "Auto")
SharedUIState.UIScalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125)

-- Shared persistent-config defaults used by every PuckAFK UI.
-- The Hub can override these values in getgenv() before a game script starts,
-- but direct script execution gets the same defaults.
SharedEnvironment.__PUCKAFK_CONFIG_SHARED_STATE =
    SharedEnvironment.__PUCKAFK_CONFIG_SHARED_STATE
    or {
        Root = "PuckAFK/Configs",
        AutoSaveDefault = true,
        AutoLoadDefault = true,
    }

local SharedConfigState = SharedEnvironment.__PUCKAFK_CONFIG_SHARED_STATE
SharedConfigState.Root = tostring(SharedConfigState.Root or "PuckAFK/Configs")
if SharedConfigState.AutoSaveDefault == nil then
    SharedConfigState.AutoSaveDefault = true
end
if SharedConfigState.AutoLoadDefault == nil then
    SharedConfigState.AutoLoadDefault = true
end

local FileAPI = {
    Write = type(writefile) == "function" and writefile or nil,
    Read = type(readfile) == "function" and readfile or nil,
    IsFile = type(isfile) == "function" and isfile or nil,
    MakeFolder = type(makefolder) == "function" and makefolder or nil,
    ListFiles = type(listfiles) == "function" and listfiles or nil,
    DeleteFile = type(delfile) == "function" and delfile or nil,
}

local function sanitizeFileComponent(value, fallback)
    local text = tostring(value or "")
    text = text:gsub("[^%w%-%._ ]", "_")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("%s+", "_")
    text = text:gsub("_+", "_")

    if text == "" then
        text = tostring(fallback or "default")
    end

    return text:sub(1, 80)
end

local function ensureFolderPath(path)
    if not FileAPI.MakeFolder then
        return false
    end

    local current = ""
    for part in tostring(path):gmatch("[^/\\]+") do
        current = current == "" and part or (current .. "/" .. part)
        pcall(FileAPI.MakeFolder, current)
    end

    return true
end

local function jsonDecode(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local ok, value = pcall(function()
        return HttpService:JSONDecode(text)
    end)

    return ok and value or nil
end

local function jsonEncode(value)
    local ok, text = pcall(function()
        return HttpService:JSONEncode(value)
    end)

    return ok and text or nil
end

local function normalizeLayoutMode(value)
    local text = tostring(value or "Auto")
    local lowered = string.lower(text)
    if lowered == "phone" or lowered == "mobile" then
        return "Phone"
    elseif lowered == "desktop" or lowered == "pc" then
        return "Desktop"
    end
    return "Auto"
end

local function getViewportSize()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    if viewport.X < 1 or viewport.Y < 1 then
        return Vector2.new(1280, 720)
    end
    return viewport
end

local function resolveLayoutMode(mode, viewport)
    mode = normalizeLayoutMode(mode)
    if mode ~= "Auto" then
        return mode
    end

    viewport = viewport or getViewportSize()
    local smallViewport = viewport.X < 760 or viewport.Y < 500
    local touchPhone = UserInputService.TouchEnabled
        and math.min(viewport.X, viewport.Y) <= 720

    return (smallViewport or touchPhone) and "Phone" or "Desktop"
end

local UI_PREFS_PATH = SharedConfigState.Root .. "/_ui_layout.json"

local function loadSharedUIPreferences()
    if not FileAPI.Read or not FileAPI.IsFile then
        return
    end

    local okExists, exists = pcall(FileAPI.IsFile, UI_PREFS_PATH)
    if not okExists or not exists then
        return
    end

    local okRead, text = pcall(FileAPI.Read, UI_PREFS_PATH)
    if not okRead then
        return
    end

    local data = jsonDecode(text)
    if type(data) ~= "table" then
        return
    end

    SharedUIState.LayoutMode = normalizeLayoutMode(data.LayoutMode or SharedUIState.LayoutMode)
    SharedUIState.UIScalePercent = math.clamp(
        tonumber(data.UIScalePercent) or SharedUIState.UIScalePercent or 100,
        75,
        125
    )
end

local function saveSharedUIPreferences()
    if not FileAPI.Write or not FileAPI.MakeFolder then
        return false
    end

    ensureFolderPath(SharedConfigState.Root)
    local encoded = jsonEncode({
        Version = 1,
        LayoutMode = normalizeLayoutMode(SharedUIState.LayoutMode),
        UIScalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125),
    })

    return encoded ~= nil and pcall(FileAPI.Write, UI_PREFS_PATH, encoded)
end

loadSharedUIPreferences()

local function create(className, properties)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    return object
end

local function tween(object, duration, properties)
    local animation = TweenService:Create(
        object,
        TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        properties
    )
    animation:Play()
    return animation
end

local function codeLabel(parent, text, size, color, zIndex)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = tostring(text or ""),
        TextColor3 = color or Theme.Text,
        TextSize = size or 12,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = zIndex or 4,
        Parent = parent,
    })
end

local function getGuiParent(screenGui)
    -- Prefer PlayerGui. Some executor/plugin environments allow the initial
    -- load thread to touch CoreGui/gethui(), but later task.spawn callbacks run
    -- with a lower capability and then fail when updating those descendants.
    -- PlayerGui keeps every UI instance accessible from normal game threads.
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui and LocalPlayer then
        playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
    end

    if playerGui then
        local ok = pcall(function()
            screenGui.Parent = playerGui
        end)
        if ok and screenGui.Parent == playerGui then
            return playerGui
        end
    end

    -- Compatibility fallback only when PlayerGui is genuinely unavailable.
    if type(gethui) == "function" then
        local ok, target = pcall(gethui)
        if ok and target then
            local parented = pcall(function()
                screenGui.Parent = target
            end)
            if parented then
                return target
            end
        end
    end

    return nil
end

local function normalizeDropdownValue(value)
    if type(value) == "table" then
        return value[1]
    end
    return value
end

local function safeCallback(callback, ...)
    if type(callback) == "function" then
        task.spawn(callback, ...)
    end
end

-- Runtime-safe property update for live labels/paragraphs. This is intentionally
-- used by public Set() methods because they are often called from farm worker
-- threads long after the UI was created.
local function safeSet(instance, property, value)
    if not instance then
        return false
    end

    local ok = pcall(function()
        instance[property] = value
    end)
    return ok
end

local function setHover(button, normal, hover)
    button.MouseEnter:Connect(function()
        if button.Parent then
            tween(button, 0.08, {BackgroundColor3 = hover})
        end
    end)
    button.MouseLeave:Connect(function()
        if button.Parent then
            tween(button, 0.08, {BackgroundColor3 = normal})
        end
    end)
end

local function getCurrentSection(tab)
    if tab._currentSection then
        return tab._currentSection
    end
    return tab:CreateSection("Main")
end

function PuckUI:SetAccent(color)
    if typeof(color) ~= "Color3" then
        return
    end

    Theme.Accent = color

    local window = self.Window
    if not window then
        return
    end

    for _, object in ipairs(window.AccentObjects or {}) do
        if object and object.Parent then
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                object.TextColor3 = color
            elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
                object.ImageColor3 = color
            elseif object:IsA("GuiObject") then
                object.BackgroundColor3 = color
            end
        end
    end

    if window.CurrentTab and window.CurrentTab.Highlight then
        window.CurrentTab.Highlight.BackgroundColor3 = color
    end
end

function PuckUI:Notify(data)
    local window = self.Window
    if not window or not window.ScreenGui or not window.ScreenGui.Parent then
        return
    end

    data = data or {}

    local viewport = getViewportSize()
    local phoneLayout = resolveLayoutMode(SharedUIState.LayoutMode, viewport) == "Phone"
    local toastWidth = math.min(phoneLayout and 330 or 280, math.max(220, viewport.X - 24))
    local toastHeight = phoneLayout and 64 or 56

    local toast = create("Frame", {
        Size = UDim2.fromOffset(toastWidth, toastHeight),
        BackgroundColor3 = Theme.Section,
        BorderColor3 = Theme.Border,
        BorderSizePixel = 1,
        ZIndex = 700,
        Parent = window.NotificationHolder,
    })

    create("Frame", {
        Position = UDim2.fromOffset(1, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BackgroundTransparency = 1,
        BorderColor3 = Theme.BorderDark,
        BorderSizePixel = 1,
        ZIndex = 701,
        Parent = toast,
    })

    local accent = create("Frame", {
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.new(0, 2, 1, -8),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 702,
        Parent = toast,
    })
    table.insert(window.AccentObjects, accent)

    local title = codeLabel(toast, data.Title or "PuckAFK", phoneLayout and 14 or 12, Theme.BrightText, 703)
    title.Position = UDim2.fromOffset(12, 5)
    title.Size = UDim2.new(1, -18, 0, phoneLayout and 21 or 18)

    local content = codeLabel(toast, data.Content or "", phoneLayout and 12 or 11, Theme.DimText, 703)
    content.Position = UDim2.fromOffset(12, phoneLayout and 27 or 22)
    content.Size = UDim2.new(1, -18, 0, phoneLayout and 31 or 28)
    content.TextWrapped = true
    content.TextYAlignment = Enum.TextYAlignment.Top

    toast.BackgroundTransparency = 1
    title.TextTransparency = 1
    content.TextTransparency = 1
    accent.BackgroundTransparency = 1

    tween(toast, 0.12, {BackgroundTransparency = 0})
    tween(title, 0.12, {TextTransparency = 0})
    tween(content, 0.12, {TextTransparency = 0})
    tween(accent, 0.12, {BackgroundTransparency = 0})

    task.delay(tonumber(data.Duration) or 3, function()
        if not toast.Parent then return end
        tween(toast, 0.12, {BackgroundTransparency = 1})
        tween(title, 0.12, {TextTransparency = 1})
        tween(content, 0.12, {TextTransparency = 1})
        tween(accent, 0.12, {BackgroundTransparency = 1})
        task.wait(0.14)
        if toast.Parent then
            toast:Destroy()
        end
    end)
end

function PuckUI:CreateWindow(settings)
    settings = settings or {}

    if self.Window and self.Window.ScreenGui then
        pcall(function()
            self.Window.ScreenGui:Destroy()
        end)
    end

    local width = tonumber(settings.Width) or 480
    local height = tonumber(settings.Height) or 540
    width = math.max(320, width)
    height = math.max(320, height)

    local screen = create("ScreenGui", {
        Name = settings.GuiName or "PuckAFK_UI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 10000,
    })
    getGuiParent(screen)

    local shadow = create("Frame", {
        Name = "Shadow",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 4, 0.5, 4),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = screen,
    })

    local main = create("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Theme.Main,
        BorderColor3 = Theme.BorderDark,
        BorderSizePixel = 1,
        Active = true,
        ZIndex = 2,
        Parent = screen,
    })

    local mainScale = create("UIScale", {Scale = 1, Parent = main})
    local shadowScale = create("UIScale", {Scale = 1, Parent = shadow})

    -- Refined procedural rose / damask background.
    -- The whole pattern is faded as one group so overlapping petals never
    -- become harsh white blobs.
    local roseBackground = create("CanvasGroup", {
        Name = "RoseBackground",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        GroupTransparency = 0.68,
        ZIndex = 3,
        Parent = main,
    })

    local themeColor = Color3.fromRGB(255, 255, 255)

    local function softPart(parent, position, anchor, size, rotation, transparency, corner)
        local part = create("Frame", {
            AnchorPoint = anchor or Vector2.new(0.5, 0.5),
            Position = position,
            Size = size,
            Rotation = rotation or 0,
            BackgroundColor3 = themeColor,
            BackgroundTransparency = transparency or 0.82,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = parent,
        })

        create("UICorner", {
            CornerRadius = UDim.new(corner or 1, 0),
            Parent = part,
        })

        return part
    end

    local function createPetal(parent, center, width, height, rotation, transparency)
        local petal = softPart(
            parent,
            center,
            Vector2.new(0.5, 1),
            UDim2.fromOffset(width, height),
            rotation,
            transparency,
            0.5
        )

        create("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.18),
                NumberSequenceKeypoint.new(0.55, 0.42),
                NumberSequenceKeypoint.new(1, 0.78),
            }),
            Parent = petal,
        })

        return petal
    end

    local function createRose(centerX, centerY, scale, rotationOffset)
        local size = math.floor(82 * scale)
        local motif = create("Frame", {
            Name = "RoseMotif",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(centerX, centerY),
            Size = UDim2.fromOffset(size, size),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = roseBackground,
        })

        local center = UDim2.fromScale(0.5, 0.42)

        -- Broad outer petals.  These are intentionally narrow and highly
        -- transparent so the result reads as a damask rose, not a flower icon.
        for i = 0, 5 do
            createPetal(
                motif,
                center,
                math.max(5, math.floor(14 * scale)),
                math.max(10, math.floor(22 * scale)),
                (i * 60) + rotationOffset,
                0.76
            )
        end

        -- Inner petals, offset into the gaps.
        for i = 0, 4 do
            createPetal(
                motif,
                center,
                math.max(4, math.floor(10 * scale)),
                math.max(7, math.floor(15 * scale)),
                (i * 72) + 36 + rotationOffset,
                0.70
            )
        end

        -- Small soft centre rather than a bright solid dot.
        softPart(
            motif,
            center,
            Vector2.new(0.5, 0.5),
            UDim2.fromOffset(math.max(3, math.floor(5 * scale)), math.max(3, math.floor(5 * scale))),
            0,
            0.58,
            1
        )

        -- Curved-looking damask leaves made from thin rotated pills.
        local leafY = 0.60
        softPart(
            motif,
            UDim2.new(0.5, -5 * scale, leafY, 0),
            Vector2.new(1, 0.5),
            UDim2.fromOffset(math.max(8, math.floor(17 * scale)), math.max(2, math.floor(4 * scale))),
            -32 + rotationOffset * 0.15,
            0.78,
            1
        )
        softPart(
            motif,
            UDim2.new(0.5, 5 * scale, leafY + 0.035, 0),
            Vector2.new(0, 0.5),
            UDim2.fromOffset(math.max(8, math.floor(17 * scale)), math.max(2, math.floor(4 * scale))),
            32 + rotationOffset * 0.15,
            0.78,
            1
        )

        -- Very thin fading stem.
        local stem = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.56, 0),
            Size = UDim2.fromOffset(1, math.max(10, math.floor(24 * scale))),
            BackgroundColor3 = themeColor,
            BackgroundTransparency = 0.74,
            BorderSizePixel = 0,
            ZIndex = 2,
            Parent = motif,
        })

        create("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.10),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = stem,
        })
    end

    -- Wider, staggered spacing.  Centres stay inside the window so there are
    -- no ugly chopped flowers along the frame edges.
    local tileX = 138
    local tileY = 132
    local firstY = 88 -- keeps the title/tab/control area visually clean
    local row = 0

    for y = firstY, height - 34, tileY do
        local offset = (row % 2 == 0) and 0 or math.floor(tileX / 2)
        local column = 0

        for x = 50 + offset, width - 38, tileX do
            local scale = ((row + column) % 3 == 0) and 0.70 or 0.60
            local tilt = ((row + column) % 2 == 0) and -7 or 7
            createRose(x, y, scale, tilt)
            column += 1
        end

        row += 1
    end

    create("Frame", {
        Name = "InnerBorder",
        Position = UDim2.fromOffset(1, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BackgroundTransparency = 1,
        BorderColor3 = Theme.Border,
        BorderSizePixel = 1,
        ZIndex = 4,
        Parent = main,
    })

    local titleBar = create("Frame", {
        Name = "TitleBar",
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(1, -4, 0, 24),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = main,
    })

    local titleLabel = codeLabel(titleBar, settings.Name or settings.Title or "Aztup Hub V3", 13, Theme.BrightText, 11)
    titleLabel.Position = UDim2.fromOffset(6, 0)
    titleLabel.Size = UDim2.new(1, -52, 1, 0)

    local close = create("TextButton", {
        Name = "Close",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -2, 0, 2),
        Size = UDim2.fromOffset(18, 19),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.Code,
        Text = "x",
        TextSize = 12,
        TextColor3 = Theme.DimText,
        ZIndex = 15,
        Parent = titleBar,
    })

    local minimize = create("TextButton", {
        Name = "Minimize",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -20, 0, 2),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.Code,
        Text = "-",
        TextSize = 12,
        TextColor3 = Theme.DimText,
        ZIndex = 15,
        Parent = titleBar,
    })

    local dragHandle = create("TextButton", {
        Name = "DragHandle",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, -42, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        Active = true,
        ZIndex = 14,
        Parent = titleBar,
    })

    local accentTop = create("Frame", {
        Name = "AccentTop",
        Position = UDim2.fromOffset(2, 26),
        Size = UDim2.new(1, -4, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 9,
        Parent = main,
    })

    local tabBar = create("ScrollingFrame", {
        Name = "TabBar",
        Position = UDim2.fromOffset(2, 27),
        Size = UDim2.new(1, -4, 0, 22),
        BackgroundColor3 = Theme.Tab,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
        ScrollBarThickness = 0,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        ZIndex = 8,
        Parent = main,
    })

    local tabLayout = create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 12),
        Parent = tabBar,
    })

    -- Separator under the tab row. Keeping this separate from the active-tab
    -- highlight prevents the header from looking broken when only one tab exists.
    create("Frame", {
        Name = "TabSeparatorDark",
        Position = UDim2.fromOffset(2, 49),
        Size = UDim2.new(1, -4, 0, 1),
        BackgroundColor3 = Theme.BorderDark,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = main,
    })

    create("Frame", {
        Name = "TabSeparator",
        Position = UDim2.fromOffset(2, 50),
        Size = UDim2.new(1, -4, 0, 1),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = main,
    })

    local columnsHost = create("Frame", {
        Name = "ColumnsHost",
        Position = UDim2.fromOffset(8, 57),
        Size = UDim2.new(1, -16, 1, -65),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 4,
        Parent = main,
    })

    local popupLayer = create("Frame", {
        Name = "PopupLayer",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Active = false,
        ZIndex = 500,
        Parent = screen,
    })

    local notificationHolder = create("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 10),
        Size = UDim2.fromOffset(290, 450),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 690,
        Parent = screen,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = notificationHolder,
    })

    local window = {
        ScreenGui = screen,
        Main = main,
        TitleBar = titleBar,
        TitleLabel = titleLabel,
        TabBar = tabBar,
        ColumnsHost = columnsHost,
        PopupLayer = popupLayer,
        NotificationHolder = notificationHolder,
        AccentObjects = {accentTop},
        Tabs = {},
        CurrentTab = nil,
        OpenPopup = nil,
        CloseCallback = nil,
        Minimized = false,
        Visible = true,
        FullSize = UDim2.fromOffset(width, height),
        BaseWidth = width,
        BaseHeight = height,
        MainScale = mainScale,
        ShadowScale = shadowScale,
        LayoutMode = normalizeLayoutMode(SharedUIState.LayoutMode),
        ResolvedLayout = "Desktop",
        UIScalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125),
        ToggleKeyName = tostring(SharedUIState.ToggleKeyName or "K"),
        ToggleKeyCode = Enum.KeyCode.K,
        KeybindDisplays = {},
        ResponsiveConnections = {},
    }

    local function updateResponsiveTextSizes(phoneLayout)
        local factor = phoneLayout and 1.12 or 1
        for _, object in ipairs(screen:GetDescendants()) do
            if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                local base = object:GetAttribute("PuckBaseTextSize")
                if not base then
                    base = object.TextSize
                    object:SetAttribute("PuckBaseTextSize", base)
                end
                object.TextSize = math.max(9, math.floor(base * factor + 0.5))
            end
        end
    end

    local function updateResponsiveRows(phoneLayout)
        local factor = phoneLayout and 1.10 or 1
        for _, object in ipairs(screen:GetDescendants()) do
            if object:IsA("GuiObject") then
                local baseHeight = object:GetAttribute("PuckControlBaseHeight")
                if baseHeight then
                    object.Size = UDim2.new(1, 0, 0, math.floor(baseHeight * factor + 0.5))
                end
            end
        end
    end

    function window:ApplyResponsiveLayout()
        if not self.ScreenGui or not self.ScreenGui.Parent then
            return
        end

        local viewport = getViewportSize()
        local requestedMode = normalizeLayoutMode(SharedUIState.LayoutMode)
        local resolved = resolveLayoutMode(requestedMode, viewport)
        local phoneLayout = resolved == "Phone"
        local scalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125)
        local requestedScale = scalePercent / 100
        local landscape = viewport.X > viewport.Y

        local baseWidth = self.BaseWidth
        local baseHeight = self.BaseHeight
        if phoneLayout then
            if landscape then
                baseWidth = math.min(560, math.max(420, math.floor((viewport.X - 18) / math.max(requestedScale, 0.75))))
                baseHeight = math.min(370, math.max(300, math.floor((viewport.Y - 18) / math.max(requestedScale, 0.75))))
            else
                baseWidth = math.min(380, math.max(320, math.floor((viewport.X - 18) / math.max(requestedScale, 0.75))))
                baseHeight = math.min(620, math.max(430, math.floor((viewport.Y - 18) / math.max(requestedScale, 0.75))))
            end
        end

        local fitScale = math.min(
            (viewport.X - 12) / math.max(baseWidth, 1),
            (viewport.Y - 12) / math.max(baseHeight, 1)
        )
        local effectiveScale = math.max(0.60, math.min(requestedScale, fitScale))

        self.LayoutMode = requestedMode
        self.ResolvedLayout = resolved
        self.UIScalePercent = scalePercent
        self.FullSize = UDim2.fromOffset(baseWidth, baseHeight)
        self.MainScale.Scale = effectiveScale
        self.ShadowScale.Scale = effectiveScale

        local headerHeight = phoneLayout and 31 or 24
        local tabHeight = phoneLayout and 29 or 22
        local tabY = phoneLayout and 35 or 27
        local contentY = phoneLayout and 70 or 57
        local bottomPad = phoneLayout and 79 or 65

        titleBar.Size = UDim2.new(1, -4, 0, headerHeight)
        close.Size = UDim2.fromOffset(phoneLayout and 27 or 18, phoneLayout and 27 or 19)
        minimize.Position = UDim2.new(1, phoneLayout and -30 or -20, 0, 2)
        minimize.Size = UDim2.fromOffset(phoneLayout and 27 or 18, phoneLayout and 27 or 18)
        dragHandle.Size = UDim2.new(1, phoneLayout and -62 or -42, 1, 0)
        accentTop.Position = UDim2.fromOffset(2, phoneLayout and 33 or 26)
        tabBar.Position = UDim2.fromOffset(2, tabY)
        tabBar.Size = UDim2.new(1, -4, 0, tabHeight)
        columnsHost.Position = UDim2.fromOffset(phoneLayout and 5 or 8, contentY)
        columnsHost.Size = UDim2.new(1, phoneLayout and -10 or -16, 1, -bottomPad)

        for _, tab in ipairs(self.Tabs or {}) do
            if tab.Button then
                local baseTabWidth = tab.Button:GetAttribute("PuckBaseTabWidth") or tab.Button.Size.X.Offset
                tab.Button.Size = UDim2.fromOffset(baseTabWidth + (phoneLayout and 10 or 0), tabHeight)
            end
            if tab._ReflowSections then
                tab:_ReflowSections()
            end
        end

        updateResponsiveRows(phoneLayout)
        updateResponsiveTextSizes(phoneLayout)

        if self.Minimized then
            main.Size = UDim2.fromOffset(baseWidth, phoneLayout and 34 or 27)
            shadow.Size = main.Size
        else
            main.Size = self.FullSize
            shadow.Size = self.FullSize
        end

        notificationHolder.Size = UDim2.fromOffset(
            math.min(phoneLayout and 340 or 290, math.max(220, viewport.X - 18)),
            math.max(220, viewport.Y - 20)
        )

        if self.DeviceStatusLabel and self.DeviceStatusLabel.Set then
            local inputName = UserInputService.TouchEnabled and "Touch" or "Keyboard/Mouse"
            self.DeviceStatusLabel:Set(string.format(
                "%s • %s • %dx%d • %d%%",
                inputName,
                resolved,
                math.floor(viewport.X),
                math.floor(viewport.Y),
                scalePercent
            ))
        end
    end

    function window:SetLayoutMode(mode)
        SharedUIState.LayoutMode = normalizeLayoutMode(mode)
        for otherWindow in pairs(SharedUIState.Windows) do
            if otherWindow and otherWindow.ApplyResponsiveLayout then
                otherWindow:ApplyResponsiveLayout()
            end
        end
        saveSharedUIPreferences()
        return SharedUIState.LayoutMode
    end

    function window:SetUIScalePercent(value)
        SharedUIState.UIScalePercent = math.clamp(tonumber(value) or 100, 75, 125)
        for otherWindow in pairs(SharedUIState.Windows) do
            if otherWindow and otherWindow.ApplyResponsiveLayout then
                otherWindow:ApplyResponsiveLayout()
            end
        end
        saveSharedUIPreferences()
        return SharedUIState.UIScalePercent
    end

    ------------------------------------------------------------------------
    -- Shared persistent configuration
    ------------------------------------------------------------------------
    local configSettings = type(settings.Configs) == "table" and settings.Configs or {}
    local configId = sanitizeFileComponent(
        settings.ConfigId or settings.GuiName or settings.Name or settings.Title,
        "PuckAFK"
    )

    local config = {
        Enabled = settings.DisableConfigs ~= true,
        Available = false,
        Root = tostring(configSettings.Root or SharedConfigState.Root),
        Id = configId,
        Folder = "",
        MetaPath = "",
        Selected = sanitizeFileComponent(configSettings.DefaultProfile or "default", "default"),
        AutoSave = SharedConfigState.AutoSaveDefault == true,
        AutoLoad = SharedConfigState.AutoLoadDefault == true,
        Controls = {},
        LoadedValues = {},
        Applying = false,
        Ready = false,
        LastFingerprint = nil,
        StatusLabel = nil,
        ProfilesDropdown = nil,
        ProfileInput = nil,
    }

    config.Folder = config.Root .. "/" .. config.Id
    config.MetaPath = config.Folder .. "/_meta.json"
    config.Available =
        config.Enabled
        and FileAPI.Write ~= nil
        and FileAPI.Read ~= nil
        and FileAPI.IsFile ~= nil
        and FileAPI.MakeFolder ~= nil

    if configSettings.AutoSave ~= nil then
        config.AutoSave = configSettings.AutoSave == true
    end
    if configSettings.AutoLoad ~= nil then
        config.AutoLoad = configSettings.AutoLoad == true
    end

    window.Config = config

    local function configFilePath(profile)
        return config.Folder
            .. "/"
            .. sanitizeFileComponent(profile, "default")
            .. ".json"
    end

    local function setConfigStatus(text)
        local value = tostring(text or "")
        if config.StatusLabel and config.StatusLabel.Set then
            config.StatusLabel:Set(value)
        end
    end

    function window:_SaveConfigMeta()
        if not config.Available then
            return false
        end

        local encoded = jsonEncode({
            Version = 1,
            Selected = config.Selected,
            AutoSave = config.AutoSave,
            AutoLoad = config.AutoLoad,
        })

        if not encoded then
            return false
        end

        local ok = pcall(FileAPI.Write, config.MetaPath, encoded)
        return ok == true
    end

    local function loadConfigMeta()
        if not config.Available or not FileAPI.IsFile(config.MetaPath) then
            return
        end

        local ok, text = pcall(FileAPI.Read, config.MetaPath)
        if not ok then
            return
        end

        local data = jsonDecode(text)
        if type(data) ~= "table" then
            return
        end

        if data.Selected ~= nil then
            config.Selected = sanitizeFileComponent(data.Selected, "default")
        end
        if data.AutoSave ~= nil then
            config.AutoSave = data.AutoSave == true
        end
        if data.AutoLoad ~= nil then
            config.AutoLoad = data.AutoLoad == true
        end
    end

    function window:_SnapshotConfigValues()
        local values = {}

        for key, control in pairs(config.Controls) do
            if control and control.Get then
                local ok, value = pcall(function()
                    return control:Get()
                end)

                if ok then
                    local valueType = typeof(value)
                    if valueType == "boolean"
                        or valueType == "number"
                        or valueType == "string" then
                        values[key] = value
                    end
                end
            end
        end

        return values
    end

    function window:_ConfigFingerprint()
        return jsonEncode(self:_SnapshotConfigValues()) or ""
    end

    function window:_WriteConfig(profile, showNotification)
        if not config.Available then
            setConfigStatus("Configs unavailable • executor filesystem APIs missing")
            if showNotification then
                PuckUI:Notify({
                    Title = "Configs",
                    Content = "This executor does not expose writefile/readfile/makefolder.",
                    Duration = 3,
                })
            end
            return false
        end

        local cleanProfile = sanitizeFileComponent(profile or config.Selected, "default")
        config.Selected = cleanProfile
        ensureFolderPath(config.Folder)

        local payload = {
            Version = 1,
            PuckUIVersion = PuckUI.Version,
            ConfigId = config.Id,
            Profile = cleanProfile,
            Values = self:_SnapshotConfigValues(),
        }

        local encoded = jsonEncode(payload)
        if not encoded then
            setConfigStatus("Save failed • JSON encode error")
            return false
        end

        local ok, err = pcall(FileAPI.Write, configFilePath(cleanProfile), encoded)
        if not ok then
            setConfigStatus("Save failed • " .. tostring(err))
            return false
        end

        self:_SaveConfigMeta()
        config.LastFingerprint = self:_ConfigFingerprint()
        setConfigStatus("Saved • " .. cleanProfile)

        if showNotification then
            PuckUI:Notify({
                Title = "Configs",
                Content = "Saved " .. cleanProfile,
                Duration = 2,
            })
        end

        return true
    end

    function window:_ApplyConfigValues(values)
        if type(values) ~= "table" then
            return false
        end

        config.Applying = true

        for key, value in pairs(values) do
            local control = config.Controls[key]
            if control and control.Set then
                pcall(function()
                    control:Set(value)
                end)
            else
                -- Keep the value around in case this control is created later.
                config.LoadedValues[key] = value
            end
        end

        config.Applying = false
        config.LastFingerprint = self:_ConfigFingerprint()
        return true
    end

    function window:_ReadConfig(profile, showNotification)
        if not config.Available then
            setConfigStatus("Configs unavailable • executor filesystem APIs missing")
            return false
        end

        local cleanProfile = sanitizeFileComponent(profile or config.Selected, "default")
        local path = configFilePath(cleanProfile)

        if not FileAPI.IsFile(path) then
            setConfigStatus("Not found • " .. cleanProfile)
            if showNotification then
                PuckUI:Notify({
                    Title = "Configs",
                    Content = "Config not found: " .. cleanProfile,
                    Duration = 2.5,
                })
            end
            return false
        end

        local ok, text = pcall(FileAPI.Read, path)
        if not ok then
            setConfigStatus("Load failed • could not read file")
            return false
        end

        local data = jsonDecode(text)
        if type(data) ~= "table" or type(data.Values) ~= "table" then
            setConfigStatus("Load failed • invalid config file")
            return false
        end

        config.Selected = cleanProfile
        config.LoadedValues = data.Values
        self:_ApplyConfigValues(data.Values)
        self:_SaveConfigMeta()
        setConfigStatus("Loaded • " .. cleanProfile)

        if showNotification then
            PuckUI:Notify({
                Title = "Configs",
                Content = "Loaded " .. cleanProfile,
                Duration = 2,
            })
        end

        return true
    end

    function window:_DeleteConfig(profile)
        if not config.Available or not FileAPI.DeleteFile then
            setConfigStatus("Delete unavailable in this executor")
            return false
        end

        local cleanProfile = sanitizeFileComponent(profile or config.Selected, "default")
        local path = configFilePath(cleanProfile)

        if not FileAPI.IsFile(path) then
            setConfigStatus("Not found • " .. cleanProfile)
            return false
        end

        local ok = pcall(FileAPI.DeleteFile, path)
        if not ok then
            setConfigStatus("Delete failed • " .. cleanProfile)
            return false
        end

        if config.Selected == cleanProfile then
            config.Selected = "default"
        end

        self:_SaveConfigMeta()
        setConfigStatus("Deleted • " .. cleanProfile)
        return true
    end

    function window:_ListConfigProfiles()
        local found = {}
        local seen = {}

        local function add(name)
            local clean = sanitizeFileComponent(name, "default")
            if not seen[clean] then
                seen[clean] = true
                table.insert(found, clean)
            end
        end

        add(config.Selected)
        add("default")

        if config.Available and FileAPI.ListFiles then
            local ok, files = pcall(FileAPI.ListFiles, config.Folder)
            if ok and type(files) == "table" then
                for _, path in ipairs(files) do
                    local normalized = tostring(path):gsub("\\", "/")
                    local name = normalized:match("([^/]+)%.json$")
                    if name and name ~= "_meta" then
                        add(name)
                    end
                end
            end
        end

        table.sort(found)
        return found
    end

    function window:_RegisterConfigControl(tab, data, control)
        if not config.Enabled
            or not control
            or type(data) ~= "table"
            or data.NoConfig == true then
            return
        end

        local baseName = data.ConfigKey or data.Flag or data.Name or data.Text
        if baseName == nil then
            return
        end

        local key = tostring(tab.Name) .. "." .. tostring(baseName)
        if config.Controls[key] and config.Controls[key] ~= control then
            local suffix = 2
            local original = key
            while config.Controls[key] do
                key = original .. "#" .. tostring(suffix)
                suffix += 1
            end
        end

        config.Controls[key] = control

        local loaded = config.LoadedValues[key]
        if loaded ~= nil and control.Set then
            task.defer(function()
                if not control.Set then
                    return
                end

                config.Applying = true
                pcall(function()
                    control:Set(loaded)
                end)
                config.Applying = false
            end)
        end
    end

    if config.Available then
        ensureFolderPath(config.Folder)
        loadConfigMeta()

        if config.AutoLoad then
            local path = configFilePath(config.Selected)
            if FileAPI.IsFile(path) then
                local ok, text = pcall(FileAPI.Read, path)
                if ok then
                    local data = jsonDecode(text)
                    if type(data) == "table" and type(data.Values) == "table" then
                        config.LoadedValues = data.Values
                    end
                end
            end
        end
    end

    self.Window = window
    SharedUIState.Windows[window] = true

    local function connectViewportCamera(camera)
        if not camera then
            return
        end
        table.insert(window.ResponsiveConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            task.defer(function()
                if window.ScreenGui and window.ScreenGui.Parent then
                    window:ApplyResponsiveLayout()
                end
            end)
        end))
    end

    connectViewportCamera(workspace.CurrentCamera)
    table.insert(window.ResponsiveConnections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        connectViewportCamera(workspace.CurrentCamera)
        task.defer(function()
            if window.ScreenGui and window.ScreenGui.Parent then
                window:ApplyResponsiveLayout()
            end
        end)
    end))

    ------------------------------------------------------------------------
    -- Reliable dragging
    ------------------------------------------------------------------------
    local dragging = false
    local dragInput = nil
    local closeOpenPopup = function() end
    local dragStart = nil
    local startPosition = nil

    local function updateDrag(input)
        if not dragging or not dragStart or not startPosition then
            return
        end

        local delta = input.Position - dragStart
        local newPos = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
        main.Position = newPos
        shadow.Position = UDim2.new(newPos.X.Scale, newPos.X.Offset + 4, newPos.Y.Scale, newPos.Y.Offset + 4)
    end

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then

            closeOpenPopup()
            dragging = true
            dragStart = input.Position
            startPosition = main.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            updateDrag(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    ------------------------------------------------------------------------
    -- Popup management
    ------------------------------------------------------------------------
    function window:ClosePopup()
        local popup = self.OpenPopup
        self.OpenPopup = nil
        if popup and popup.Close then
            popup:Close()
        end
    end

    closeOpenPopup = function()
        window:ClosePopup()
    end

    function window:SetCloseCallback(callback)
        self.CloseCallback = callback
    end

    function window:SetTitle(text)
        self.TitleLabel.Text = tostring(text or "")
    end

    function window:SetVisible(state)
        local visible = state == true
        self.Visible = visible
        safeSet(self.Main, "Visible", visible)
        if shadow then
            safeSet(shadow, "Visible", visible)
        end
        if not visible then
            self:ClosePopup()
        end
    end

    function window:Toggle()
        self:SetVisible(not self.Visible)
    end

    function window:_ApplyToggleKey(key)
        local keyCode

        if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
            keyCode = key
        else
            keyCode = Enum.KeyCode[tostring(key or "")]
        end

        if not keyCode or keyCode == Enum.KeyCode.Unknown then
            return false
        end

        self.ToggleKeyCode = keyCode
        self.ToggleKeyName = keyCode.Name

        for _, control in ipairs(self.KeybindDisplays or {}) do
            if control and control._SetKeyName then
                control:_SetKeyName(self.ToggleKeyName)
            end
        end

        return true
    end

    function window:SetToggleKey(key)
        local keyCode

        if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
            keyCode = key
        else
            keyCode = Enum.KeyCode[tostring(key or "")]
        end

        if not keyCode or keyCode == Enum.KeyCode.Unknown then
            return false
        end

        SharedUIState.ToggleKeyName = keyCode.Name

        -- Broadcast the new key to every PuckAFK window currently loaded.
        for otherWindow in pairs(SharedUIState.Windows) do
            if otherWindow and otherWindow._ApplyToggleKey then
                otherWindow:_ApplyToggleKey(keyCode)
            end
        end

        return true
    end

    function window:GetToggleKey()
        return self.ToggleKeyName
    end

    function window:Destroy()
        self:ClosePopup()
        SharedUIState.Windows[self] = nil

        for _, connection in ipairs(self.ResponsiveConnections or {}) do
            pcall(function() connection:Disconnect() end)
        end
        self.ResponsiveConnections = {}

        if SharedUIState.CapturingWindow == self then
            SharedUIState.CapturingWindow = nil
            SharedUIState.CapturingControl = nil
        end

        if self.ScreenGui then
            self.ScreenGui:Destroy()
        end
    end

    function window:SelectTab(tab)
        if self.CurrentTab == tab then
            return
        end

        self:ClosePopup()

        if self.CurrentTab then
            self.CurrentTab.Container.Visible = false
            self.CurrentTab.Button.TextColor3 = Theme.Text
            self.CurrentTab.Highlight.Visible = false
        end

        self.CurrentTab = tab
        tab.Container.Visible = true
        tab.Button.TextColor3 = Theme.Accent
        tab.Highlight.BackgroundColor3 = Theme.Accent
        tab.Highlight.Visible = true

        task.defer(function()
            if not tab.Button.Parent then return end
            local buttonLeft = tab.Button.AbsolutePosition.X - tabBar.AbsolutePosition.X + tabBar.CanvasPosition.X
            local buttonRight = buttonLeft + tab.Button.AbsoluteSize.X
            local visibleLeft = tabBar.CanvasPosition.X
            local visibleRight = visibleLeft + tabBar.AbsoluteSize.X

            if buttonLeft < visibleLeft then
                tabBar.CanvasPosition = Vector2.new(math.max(0, buttonLeft - 4), 0)
            elseif buttonRight > visibleRight then
                tabBar.CanvasPosition = Vector2.new(
                    math.max(0, buttonRight - tabBar.AbsoluteSize.X + 4),
                    0
                )
            end
        end)
    end

    -- Resolve this window to the current shared UI key.
    if not window:_ApplyToggleKey(SharedUIState.ToggleKeyName) then
        window:_ApplyToggleKey("K")
    end

    ------------------------------------------------------------------------
    -- Tabs and controls
    ------------------------------------------------------------------------
    function window:CreateTab(tabName, _icon)
        local tab = {
            Name = tostring(tabName),
            Window = self,
            Sections = {},
            _nextColumn = 1,
            _currentSection = nil,
        }

        local textSize = TextService:GetTextSize(tab.Name, 13, Enum.Font.Code, Vector2.new(1000, 18))
        local buttonWidth = math.max(38, textSize.X + 10)

        -- New tabs always begin from the left edge. This also clears stale
        -- CanvasPosition values left over by some executor/Studio UI states.
        if #self.Tabs == 0 then
            tabBar.CanvasPosition = Vector2.new(0, 0)
        end

        local button = create("TextButton", {
            Name = "Tab_" .. tab.Name,
            LayoutOrder = #self.Tabs + 1,
            Size = UDim2.fromOffset(buttonWidth, 22),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.Code,
            Text = tab.Name,
            TextSize = 13,
            TextColor3 = Theme.Text,
            ZIndex = 10,
            Parent = tabBar,
        })
        button:SetAttribute("PuckBaseTabWidth", buttonWidth)

        -- Aztup top/bottom highlight for active tab
        local highlight = create("Frame", {
            Position = UDim2.new(0, 0, 1, -1),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 11,
            Parent = button,
        })
        table.insert(window.AccentObjects, highlight)

        local container = create("Frame", {
            Name = "Content_" .. tab.Name,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ClipsDescendants = false,
            Visible = false,
            ZIndex = 4,
            Parent = columnsHost,
        })

        local columns = {}
        local columnLayouts = {}

        local function updateColumnCanvas(index)
            local scroll = columns[index]
            local layout = columnLayouts[index]
            if not scroll or not layout then
                return
            end

            -- Manual CanvasSize is more reliable than nested AutomaticCanvasSize
            -- when this library is used through Studio/executor environments.
            local contentHeight = math.max(0, layout.AbsoluteContentSize.Y + 14)
            scroll.CanvasSize = UDim2.fromOffset(0, contentHeight)
        end

        for index = 1, 2 do
            local leftSide = index == 1
            local scroll = create("ScrollingFrame", {
                Name = "Column" .. tostring(index),
                Position = UDim2.new(leftSide and 0 or 0.5, leftSide and 0 or 4, 0, 0),
                Size = UDim2.new(0.5, -4, 1, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.None,
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60),
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ElasticBehavior = Enum.ElasticBehavior.Never,
                ClipsDescendants = true,
                ZIndex = 4,
                Parent = container,
            })

            local layout = create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 8),
                Parent = scroll,
            })

            create("UIPadding", {
                PaddingTop = UDim.new(0, 8),
                PaddingRight = UDim.new(0, leftSide and 3 or 0),
                PaddingBottom = UDim.new(0, 6),
                Parent = scroll,
            })

            layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                updateColumnCanvas(index)
            end)

            scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                if window.OpenPopup then
                    window:ClosePopup()
                end
            end)

            columns[index] = scroll
            columnLayouts[index] = layout
        end

        tab.Button = button
        tab.Highlight = highlight
        tab.Container = container
        tab.Columns = columns

        -- Reflow rules:
        --   1 section  -> one full-width column (fixes the giant empty right side)
        --   2+ sections -> stable two-column alternating layout
        -- We do not use AbsoluteContentSize to choose a column at creation time,
        -- because Roblox may not update it until a later render step.
        local function reflowSections()
            local count = #tab.Sections
            local phoneLayout = window.ResolvedLayout == "Phone"

            if phoneLayout or count <= 1 then
                columns[1].Visible = true
                columns[1].Position = UDim2.new(0, 0, 0, 0)
                columns[1].Size = UDim2.new(1, 0, 1, 0)
                columns[2].Visible = false
                columns[2].CanvasPosition = Vector2.new(0, 0)

                for _, existingSection in ipairs(tab.Sections) do
                    if existingSection.Frame.Parent ~= columns[1] then
                        existingSection.Frame.Parent = columns[1]
                    end
                end
            else
                columns[1].Visible = true
                columns[2].Visible = true
                columns[1].Position = UDim2.new(0, 0, 0, 0)
                columns[1].Size = UDim2.new(0.5, -4, 1, 0)
                columns[2].Position = UDim2.new(0.5, 4, 0, 0)
                columns[2].Size = UDim2.new(0.5, -4, 1, 0)

                for sectionIndex, existingSection in ipairs(tab.Sections) do
                    local targetColumn = ((sectionIndex - 1) % 2) + 1
                    if existingSection.Frame.Parent ~= columns[targetColumn] then
                        existingSection.Frame.Parent = columns[targetColumn]
                    end
                end
            end

            task.defer(function()
                updateColumnCanvas(1)
                updateColumnCanvas(2)
            end)
        end

        tab._ReflowSections = reflowSections

        function tab:CreateSection(sectionName)
            local section = {
                Name = tostring(sectionName or "Section"),
                Tab = self,
            }

            local frame = create("Frame", {
                Name = "Section_" .. section.Name,
                Size = UDim2.new(1, -2, 0, 24),
                BackgroundColor3 = Theme.SectionInner,
                BackgroundTransparency = 0.5,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                ClipsDescendants = false,
                ZIndex = 5,
                Parent = columns[1],
            })

            create("UIStroke", {
                Color = Theme.Border,
                Thickness = 1,
                Parent = frame,
            })

            local topAccentLine = create("Frame", {
                Position = UDim2.fromOffset(0, 0),
                Size = UDim2.new(1, 0, 0, 1),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                ZIndex = 6,
                Parent = frame,
            })
            table.insert(window.AccentObjects, topAccentLine)

            local titleWidth = TextService:GetTextSize(section.Name, 12, Enum.Font.Code, Vector2.new(1000, 16)).X + 12

            local headerPatch = create("Frame", {
                Position = UDim2.fromOffset(12, -7),
                Size = UDim2.fromOffset(titleWidth, 14),
                BackgroundColor3 = Theme.Main,
                BorderSizePixel = 0,
                ZIndex = 7,
                Parent = frame,
            })

            local header = codeLabel(headerPatch, section.Name, 12, Theme.Text, 8)
            header.Position = UDim2.fromOffset(0, 0)
            header.Size = UDim2.new(1, 0, 1, 0)
            header.TextXAlignment = Enum.TextXAlignment.Center

            local body = create("Frame", {
                Name = "Body",
                Position = UDim2.fromOffset(8, 14),
                Size = UDim2.new(1, -16, 0, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = false,
                ZIndex = 6,
                Parent = frame,
            })

            local bodyLayout = create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 4),
                Parent = body,
            })

            create("UIPadding", {
                PaddingBottom = UDim.new(0, 8),
                Parent = body,
            })

            local function updateSectionSize()
                local bodyHeight = math.max(0, bodyLayout.AbsoluteContentSize.Y + 8)
                body.Size = UDim2.new(1, -16, 0, bodyHeight)
                frame.Size = UDim2.new(1, -2, 0, math.max(28, 14 + bodyHeight))
            end

            bodyLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                updateSectionSize()
                task.defer(function()
                    updateColumnCanvas(1)
                    updateColumnCanvas(2)
                end)
            end)

            section.Frame = frame
            section.Body = body

            function section:Set(newName)
                self.Name = tostring(newName or "")
                header.Text = self.Name
                local newWidth = TextService:GetTextSize(self.Name, 12, Enum.Font.Code, Vector2.new(1000, 16)).X + 12
                headerPatch.Size = UDim2.fromOffset(newWidth, 14)
            end

            table.insert(self.Sections, section)
            self._currentSection = section
            reflowSections()

            task.defer(updateSectionSize)
            return section
        end

        local function addControlFrame(height)
            local section = getCurrentSection(tab)
            local phoneFactor = window.ResolvedLayout == "Phone" and 1.10 or 1
            local row = create("Frame", {
                Size = UDim2.new(1, 0, 0, math.floor(height * phoneFactor + 0.5)),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = false,
                ZIndex = 6,
                Parent = section.Body,
            })
            row:SetAttribute("PuckControlBaseHeight", height)
            return row
        end

        function tab:CreateDivider()
            local row = addControlFrame(9)
            local divider = create("Frame", {
                Position = UDim2.fromOffset(0, 4),
                Size = UDim2.new(1, 0, 0, 1),
                BackgroundColor3 = Theme.Border,
                BorderSizePixel = 0,
                ZIndex = 7,
                Parent = row,
            })

            local object = {}
            function object:Set(visible)
                divider.Visible = visible ~= false
            end
            return object
        end

        function tab:CreateLabel(text, _icon, color)
            local row = addControlFrame(17)
            local label = codeLabel(row, text, 11, color or Theme.DimText, 7)
            label.Size = UDim2.fromScale(1, 1)
            label.TextTruncate = Enum.TextTruncate.AtEnd

            local object = {
                Label = label,
            }

            function object:Set(value, _newIcon, newColor)
                safeSet(label, "Text", tostring(value or ""))
                if typeof(newColor) == "Color3" then
                    safeSet(label, "TextColor3", newColor)
                end
            end

            return object
        end

        function tab:CreateParagraph(data)
            data = data or {}

            local contentText = tostring(data.Content or "")
            local rowHeight = tonumber(data.Height) or 50
            if #contentText > 140 then
                rowHeight = 68
            elseif #contentText > 75 then
                rowHeight = 58
            end

            local row = addControlFrame(rowHeight)

            local title = codeLabel(row, data.Title or "", 12, Theme.BrightText, 7)
            title.Position = UDim2.fromOffset(0, 0)
            title.Size = UDim2.new(1, 0, 0, 16)

            local body = codeLabel(row, contentText, 11, Theme.DimText, 7)
            body.Position = UDim2.fromOffset(0, 16)
            body.Size = UDim2.new(1, 0, 1, -16)
            body.TextWrapped = true
            body.TextYAlignment = Enum.TextYAlignment.Top

            local object = {}
            function object:Set(nextData)
                if type(nextData) == "table" then
                    if nextData.Title ~= nil then
                        safeSet(title, "Text", tostring(nextData.Title))
                    end
                    if nextData.Content ~= nil then
                        safeSet(body, "Text", tostring(nextData.Content))
                    end
                else
                    safeSet(body, "Text", tostring(nextData or ""))
                end
            end

            return object
        end

        function tab:CreateButton(data)
            data = data or {}

            -- Legacy scripts used dedicated Hide UI buttons. The UI keybind in
            -- Settings replaces them, so suppress those buttons automatically.
            local requestedName = tostring(data.Name or data.Text or "Button")
            local normalizedName = string.lower(requestedName)
            normalizedName = normalizedName:gsub("%s+", " ")

            local legacyUIButtons = {
                ["hide ui"] = true,
                ["toggle ui"] = true,
                ["hide/show ui"] = true,
                ["show/hide ui"] = true,
                ["hide / show ui"] = true,
                ["show / hide ui"] = true,
            }

            if legacyUIButtons[normalizedName] then
                local hiddenObject = {}
                function hiddenObject:Set(_value) end
                function hiddenObject:SetText(_value) end
                function hiddenObject:Get() return false end
                return hiddenObject
            end

            local row = addControlFrame(24)

            local buttonControl = create("TextButton", {
                Position = UDim2.fromOffset(0, 1),
                Size = UDim2.new(1, 0, 1, -2),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = tostring(data.Name or data.Text or "Button"),
                TextColor3 = Theme.Text,
                TextSize = 11,
                ZIndex = 7,
                Parent = row,
            })
            setHover(buttonControl, Theme.Element, Theme.ElementHover)

            buttonControl.MouseButton1Click:Connect(function()
                safeCallback(data.Callback)
            end)

            local object = {
                Button = buttonControl,
            }

            function object:Set(value)
                buttonControl.Text = tostring(value or "")
            end

            function object:SetText(value)
                buttonControl.Text = tostring(value or "")
            end

            return object
        end

        function tab:CreateToggle(data)
            data = data or {}

            local row = addControlFrame(18)
            local state = data.CurrentValue == true
            local flag = data.Flag

            local hit = create("TextButton", {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = "",
                ZIndex = 9,
                Parent = row,
            })

            local box = create("Frame", {
                Position = UDim2.fromOffset(2, 3),
                Size = UDim2.fromOffset(12, 12),
                BackgroundColor3 = Color3.fromRGB(15, 15, 15),
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                ZIndex = 7,
                Parent = row,
            })
            create("UIStroke", { Color = Theme.Border, Thickness = 1, Parent = box })

            local fill = create("Frame", {
                Position = UDim2.fromOffset(2, 2),
                Size = UDim2.new(1, -4, 1, -4),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                Visible = state,
                ZIndex = 9,
                Parent = box,
            })
            table.insert(window.AccentObjects, fill)

            local label = codeLabel(row, data.Name or data.Text or "Toggle", 12, state and Theme.BrightText or Theme.DimText, 7)
            label.Position = UDim2.fromOffset(22, 0)
            label.Size = UDim2.new(1, -22, 1, 0)
            label.TextTruncate = Enum.TextTruncate.AtEnd

            local object = {}

            local function apply(value, invokeCallback)
                state = value == true
                fill.Visible = state
                label.TextColor3 = state and Theme.BrightText or Theme.DimText

                if flag then
                    PuckUI.Flags[flag] = state
                end

                if invokeCallback then
                    safeCallback(data.Callback, state)
                end
            end

            function object:Set(value)
                apply(value, true)
            end

            function object:Get()
                return state
            end

            hit.MouseButton1Click:Connect(function()
                apply(not state, true)
            end)

            if flag then
                PuckUI.Flags[flag] = state
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateDropdown(data)
            data = data or {}

            local row = addControlFrame(40)
            local label = codeLabel(row, data.Name or "Dropdown", 12, Theme.Text, 7)
            label.Size = UDim2.new(1, 0, 0, 16)

            local options = {}
            for _, option in ipairs(data.Options or {}) do
                table.insert(options, option)
            end

            local current = normalizeDropdownValue(data.CurrentOption)
            if current == nil then
                current = options[1]
            end

            local selector = create("TextButton", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = "  " .. tostring(current or "Select..."),
                TextColor3 = Theme.Text,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 8,
                Parent = row,
            })
            setHover(selector, Theme.Element, Theme.ElementHover)

            local arrow = codeLabel(selector, "v", 10, Theme.DimText, 9)
            arrow.AnchorPoint = Vector2.new(1, 0)
            arrow.Position = UDim2.new(1, -3, 0, 0)
            arrow.Size = UDim2.fromOffset(12, 20)
            arrow.TextXAlignment = Enum.TextXAlignment.Center

            local object = {}
            local flag = data.Flag
            local popup = nil
            local blocker = nil

            local function apply(value, invokeCallback)
                if value == nil then
                    return
                end

                current = value
                selector.Text = "  " .. tostring(current)

                if flag then
                    PuckUI.Flags[flag] = current
                end

                if invokeCallback then
                    safeCallback(data.Callback, {current})
                end
            end

            local function closePopup()
                if popup then
                    popup:Destroy()
                    popup = nil
                end
                if blocker then
                    blocker:Destroy()
                    blocker = nil
                end
                arrow.Text = "v"

                if window.OpenPopup == object then
                    window.OpenPopup = nil
                end
            end

            function object:Close()
                closePopup()
            end

            local function openPopup()
                if window.OpenPopup and window.OpenPopup ~= object then
                    window.OpenPopup:Close()
                end

                closePopup()

                local selectorPosition = selector.AbsolutePosition
                local selectorSize = selector.AbsoluteSize
                local itemHeight = window.ResolvedLayout == "Phone" and 28 or 20
                local maxVisible = tonumber(data.MaxVisible) or (window.ResolvedLayout == "Phone" and 6 or 8)
                local visibleCount = math.min(#options, maxVisible)
                local menuHeight = math.max(itemHeight + 2, visibleCount * itemHeight + 2)

                local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
                local menuY = selectorPosition.Y + selectorSize.Y + 1

                if menuY + menuHeight > viewport.Y - 6 then
                    menuY = selectorPosition.Y - menuHeight - 1
                end

                blocker = create("TextButton", {
                    Size = UDim2.fromScale(1, 1),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = "",
                    ZIndex = 501,
                    Parent = popupLayer,
                })

                blocker.MouseButton1Click:Connect(closePopup)

                popup = create("ScrollingFrame", {
                    Position = UDim2.fromOffset(selectorPosition.X, menuY),
                    Size = UDim2.fromOffset(math.max(80, selectorSize.X), menuHeight),
                    BackgroundColor3 = Color3.fromRGB(20, 20, 20),
                    BorderColor3 = Theme.Border,
                    BorderSizePixel = 1,
                    CanvasSize = UDim2.new(),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    ScrollBarThickness = #options > maxVisible and 3 or 0,
                    ScrollBarImageColor3 = Color3.fromRGB(90, 90, 90),
                    ScrollingDirection = Enum.ScrollingDirection.Y,
                    ElasticBehavior = Enum.ElasticBehavior.Never,
                    ClipsDescendants = true,
                    ZIndex = 510,
                    Parent = popupLayer,
                })

                create("UIListLayout", {
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 0),
                    Parent = popup,
                })

                for index, value in ipairs(options) do
                    local optionButton = create("TextButton", {
                        LayoutOrder = index,
                        Size = UDim2.new(1, 0, 0, itemHeight),
                        BackgroundColor3 = value == current and Color3.fromRGB(38, 38, 38) or Color3.fromRGB(25, 25, 25),
                        BorderSizePixel = 0,
                        AutoButtonColor = false,
                        Font = Enum.Font.Code,
                        Text = "  " .. tostring(value),
                        TextColor3 = value == current and Theme.BrightText or Theme.Text,
                        TextSize = window.ResolvedLayout == "Phone" and 12 or 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        ZIndex = 512,
                        Parent = popup,
                    })

                    setHover(
                        optionButton,
                        value == current and Color3.fromRGB(38, 38, 38) or Color3.fromRGB(25, 25, 25),
                        Theme.Element
                    )

                    optionButton.MouseButton1Click:Connect(function()
                        apply(value, true)
                        closePopup()
                    end)
                end

                arrow.Text = "^"
                window.OpenPopup = object
            end

            selector.MouseButton1Click:Connect(function()
                if window.OpenPopup == object then
                    closePopup()
                else
                    openPopup()
                end
            end)

            function object:Set(value)
                apply(normalizeDropdownValue(value), true)
            end

            function object:Get()
                return current
            end

            function object:Refresh(newOptions)
                closePopup()

                options = {}
                for _, option in ipairs(newOptions or {}) do
                    table.insert(options, option)
                end

                if current == nil or not table.find(options, current) then
                    current = options[1]
                    selector.Text = "  " .. tostring(current or "Select...")
                    if flag then
                        PuckUI.Flags[flag] = current
                    end
                end
            end

            if flag and current ~= nil then
                PuckUI.Flags[flag] = current
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateSlider(data)
            data = data or {}

            -- Sliders redesigned for Aztup format: thicker bar, value inside.
            local row = addControlFrame(34)
            local minimum = tonumber(data.Range and data.Range[1] or data.Min) or 0
            local maximum = tonumber(data.Range and data.Range[2] or data.Max) or 100
            local increment = tonumber(data.Increment) or 1
            local suffix = tostring(data.Suffix or "")

            local value = tonumber(data.CurrentValue or data.Value) or minimum
            value = math.clamp(value, minimum, maximum)

            local label = codeLabel(row, data.Name or "Slider", 11, Theme.DimText, 7)
            label.Size = UDim2.new(1, 0, 0, 14)

            local rail = create("Frame", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 14),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                Active = true,
                ZIndex = 7,
                Parent = row,
            })

            local fill = create("Frame", {
                Size = UDim2.new((value - minimum) / math.max(maximum - minimum, 1), 0, 1, 0),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                ZIndex = 8,
                Parent = rail,
            })
            table.insert(window.AccentObjects, fill)

            -- The value label is now placed inside the rail to mimic Aztup
            local valueLabel = codeLabel(rail, tostring(value) .. suffix, 11, Theme.BrightText, 9)
            valueLabel.Size = UDim2.fromScale(1, 1)
            valueLabel.TextXAlignment = Enum.TextXAlignment.Center

            local draggingSlider = false
            local flag = data.Flag
            local object = {}

            local function apply(nextValue, invokeCallback)
                nextValue = tonumber(nextValue)
                if not nextValue then
                    return
                end

                nextValue = math.clamp(nextValue, minimum, maximum)
                nextValue = math.floor(nextValue / increment + 0.5) * increment

                if increment < 1 then
                    local decimals = math.max(0, math.ceil(-math.log10(increment)))
                    local factor = 10 ^ decimals
                    nextValue = math.floor(nextValue * factor + 0.5) / factor
                end

                value = nextValue
                valueLabel.Text = tostring(value) .. suffix
                fill.Size = UDim2.new(
                    (value - minimum) / math.max(maximum - minimum, 1),
                    0,
                    1,
                    0
                )

                if flag then
                    PuckUI.Flags[flag] = value
                end

                if invokeCallback then
                    safeCallback(data.Callback, value)
                end
            end

            local function fromPosition(x)
                local alpha = math.clamp(
                    (x - rail.AbsolutePosition.X) / math.max(rail.AbsoluteSize.X, 1),
                    0,
                    1
                )
                apply(minimum + (maximum - minimum) * alpha, true)
            end

            rail.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    draggingSlider = true
                    fromPosition(input.Position.X)
                end
            end)

            UserInputService.InputChanged:Connect(function(input)
                if draggingSlider and (
                    input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch
                ) then
                    fromPosition(input.Position.X)
                end
            end)

            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    draggingSlider = false
                end
            end)

            function object:Set(nextValue)
                apply(nextValue, true)
            end

            function object:Get()
                return value
            end

            if flag then
                PuckUI.Flags[flag] = value
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateInput(data)
            data = data or {}

            local row = addControlFrame(40)

            local label = codeLabel(row, data.Name or "Input", 11, Theme.Text, 7)
            label.Size = UDim2.new(1, 0, 0, 16)

            local box = create("TextBox", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                ClearTextOnFocus = false,
                Font = Enum.Font.Code,
                Text = tostring(data.CurrentValue or ""),
                PlaceholderText = tostring(data.PlaceholderText or ""),
                TextColor3 = Theme.Text,
                PlaceholderColor3 = Theme.DimText,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 8,
                Parent = row,
            })

            create("UIPadding", {
                PaddingLeft = UDim.new(0, 6),
                PaddingRight = UDim.new(0, 6),
                Parent = box,
            })

            local current = box.Text
            local flag = data.Flag
            local object = {}

            local function apply(value, invokeCallback)
                current = tostring(value or "")
                box.Text = current

                if flag then
                    PuckUI.Flags[flag] = current
                end

                if invokeCallback then
                    safeCallback(data.Callback, current)
                end
            end

            box.FocusLost:Connect(function()
                current = box.Text

                if flag then
                    PuckUI.Flags[flag] = current
                end

                safeCallback(data.Callback, current)

                if data.RemoveTextAfterFocusLost then
                    box.Text = ""
                end
            end)

            function object:Set(value)
                apply(value, true)
            end

            function object:Get()
                return current
            end

            if flag then
                PuckUI.Flags[flag] = current
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateKeybind(data)
            data = data or {}

            local row = addControlFrame(40)

            local label = codeLabel(row, data.Name or "UI Toggle Keybind", 11, Theme.Text, 7)
            label.Size = UDim2.new(1, 0, 0, 16)

            local bindButton = create("TextButton", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = "",
                TextColor3 = Theme.Text,
                TextSize = 11,
                ZIndex = 8,
                Parent = row,
            })
            create("UIStroke", {Color = Theme.Border, Thickness = 1, Parent = bindButton})
            setHover(bindButton, Theme.Element, Theme.ElementHover)

            local object = {
                Button = bindButton,
                Callback = data.Callback,
                CurrentKey = window.ToggleKeyName,
                Capturing = false,
            }

            function object:_SetKeyName(keyName)
                self.CurrentKey = tostring(keyName or "K")
                self.Capturing = false
                bindButton.Text = "[ " .. self.CurrentKey .. " ]"
                bindButton.TextColor3 = Theme.Text
            end

            function object:Set(value)
                local previous = window.ToggleKeyName
                if window:SetToggleKey(value) then
                    self:_SetKeyName(window.ToggleKeyName)
                    if previous ~= window.ToggleKeyName then
                        safeCallback(self.Callback, window.ToggleKeyName)
                    end
                    return true
                end
                return false
            end

            function object:Get()
                return window.ToggleKeyName
            end

            function object:CancelCapture()
                if SharedUIState.CapturingControl == self then
                    SharedUIState.CapturingControl = nil
                    SharedUIState.CapturingWindow = nil
                end
                self:_SetKeyName(window.ToggleKeyName)
            end

            bindButton.MouseButton1Click:Connect(function()
                local previousControl = SharedUIState.CapturingControl
                if previousControl and previousControl ~= object and previousControl.CancelCapture then
                    previousControl:CancelCapture()
                end

                window:ClosePopup()
                SharedUIState.CapturingWindow = window
                SharedUIState.CapturingControl = object
                object.Capturing = true
                bindButton.Text = "[ press a key... ]"
                bindButton.TextColor3 = Theme.Accent
            end)

            object:_SetKeyName(window.ToggleKeyName)
            table.insert(window.KeybindDisplays, object)

            return object
        end

        button.MouseButton1Click:Connect(function()
            window:SelectTab(tab)
        end)

        table.insert(self.Tabs, tab)

        -- Shared interface controls are injected into every Settings tab.
        if string.lower(tab.Name) == "settings"
            and settings.DisableBuiltInResponsiveUI ~= true then

            tab:CreateSection("Interface")

            if settings.DisableBuiltInUIKeybind ~= true then
                tab:CreateKeybind({
                    Name = "UI Toggle Keybind",
                    Callback = function(keyName)
                        PuckUI:Notify({
                            Title = "UI Keybind",
                            Content = "All PuckAFK UIs now use " .. tostring(keyName),
                            Duration = 2.5,
                        })
                    end,
                })
            end

            tab:CreateDropdown({
                Name = "UI Layout",
                Options = {"Auto", "Desktop", "Phone"},
                CurrentOption = {normalizeLayoutMode(SharedUIState.LayoutMode)},
                NoConfig = true,
                Callback = function(option)
                    local selected = normalizeDropdownValue(option)
                    window:SetLayoutMode(selected)
                end,
            })

            tab:CreateSlider({
                Name = "UI Size",
                Range = {75, 125},
                Increment = 5,
                CurrentValue = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125),
                Suffix = "%",
                NoConfig = true,
                Callback = function(value)
                    window:SetUIScalePercent(value)
                end,
            })

            window.DeviceStatusLabel = tab:CreateLabel("Detecting display...")
            if settings.DisableBuiltInUIKeybind ~= true then
                tab:CreateLabel("Click the key box, then press any key. Escape cancels.")
            end
        end

        if string.lower(tab.Name) == "settings"
            and settings.DisableBuiltInConfigs ~= true
            and not self._CreatingConfigTab then
            task.defer(function()
                if self.ScreenGui and self.ScreenGui.Parent then
                    self:_EnsureConfigTab()
                end
            end)
        end

        if #self.Tabs == 1 then
            task.defer(function()
                if button.Parent then
                    tabBar.CanvasPosition = Vector2.new(0, 0)
                    self:SelectTab(tab)
                end
            end)
        end

        task.defer(function()
            if window.ScreenGui and window.ScreenGui.Parent then
                window:ApplyResponsiveLayout()
            end
        end)

        return tab
    end

    function window:_EnsureConfigTab()
        if self._ConfigTab or self._CreatingConfigTab or not config.Enabled then
            return self._ConfigTab
        end

        self._CreatingConfigTab = true
        local tab = self:CreateTab("Configs")
        self._CreatingConfigTab = false
        self._ConfigTab = tab

        tab:CreateSection("Profiles")

        config.StatusLabel = tab:CreateLabel(
            config.Available
                and ("Ready • " .. config.Selected)
                or "Unavailable • executor filesystem APIs missing"
        )

        if not config.Available then
            tab:CreateParagraph({
                Title = "Persistent configs unavailable",
                Content = "This executor needs writefile, readfile, isfile and makefolder for saved configs. The rest of PuckAFK still works normally.",
                Height = 64,
            })
            return tab
        end

        config.ProfilesDropdown = tab:CreateDropdown({
            Name = "Config Profile",
            Options = self:_ListConfigProfiles(),
            CurrentOption = {config.Selected},
            NoConfig = true,
            Callback = function(option)
                local value = normalizeDropdownValue(option)
                if value ~= nil then
                    config.Selected = sanitizeFileComponent(value, "default")
                    if config.ProfileInput and config.ProfileInput.Set then
                        config.ProfileInput:Set(config.Selected)
                    end
                    self:_SaveConfigMeta()
                    setConfigStatus("Selected • " .. config.Selected)
                end
            end,
        })

        config.ProfileInput = tab:CreateInput({
            Name = "Profile Name",
            CurrentValue = config.Selected,
            PlaceholderText = "default",
            NoConfig = true,
            Callback = function(value)
                config.PendingProfile = sanitizeFileComponent(value, config.Selected)
            end,
        })

        tab:CreateButton({
            Name = "Save / Create Profile",
            Callback = function()
                local profile = config.PendingProfile or config.Selected
                config.Selected = sanitizeFileComponent(profile, "default")
                self:_WriteConfig(config.Selected, true)

                if config.ProfilesDropdown and config.ProfilesDropdown.Refresh then
                    config.ProfilesDropdown:Refresh(self:_ListConfigProfiles())
                    config.ProfilesDropdown:Set(config.Selected)
                end
            end,
        })

        tab:CreateButton({
            Name = "Load Selected Profile",
            Callback = function()
                self:_ReadConfig(config.Selected, true)
            end,
        })

        tab:CreateButton({
            Name = "Refresh Profiles",
            Callback = function()
                if config.ProfilesDropdown and config.ProfilesDropdown.Refresh then
                    config.ProfilesDropdown:Refresh(self:_ListConfigProfiles())
                    config.ProfilesDropdown:Set(config.Selected)
                end
                setConfigStatus("Profiles refreshed")
            end,
        })

        tab:CreateButton({
            Name = "Delete Selected Profile",
            Callback = function()
                local deleted = config.Selected
                if self:_DeleteConfig(deleted) then
                    if config.ProfilesDropdown and config.ProfilesDropdown.Refresh then
                        config.ProfilesDropdown:Refresh(self:_ListConfigProfiles())
                        config.ProfilesDropdown:Set(config.Selected)
                    end
                    if config.ProfileInput and config.ProfileInput.Set then
                        config.ProfileInput:Set(config.Selected)
                    end
                    PuckUI:Notify({
                        Title = "Configs",
                        Content = "Deleted " .. tostring(deleted),
                        Duration = 2,
                    })
                end
            end,
        })

        tab:CreateSection("Automation")

        tab:CreateToggle({
            Name = "Auto Save",
            CurrentValue = config.AutoSave,
            NoConfig = true,
            Callback = function(value)
                config.AutoSave = value == true
                self:_SaveConfigMeta()
                if config.AutoSave then
                    self:_WriteConfig(config.Selected, false)
                end
                setConfigStatus(
                    config.AutoSave
                        and ("Auto Save ON • " .. config.Selected)
                        or "Auto Save OFF"
                )
            end,
        })

        tab:CreateToggle({
            Name = "Auto Load",
            CurrentValue = config.AutoLoad,
            NoConfig = true,
            Callback = function(value)
                config.AutoLoad = value == true
                self:_SaveConfigMeta()
                setConfigStatus(
                    config.AutoLoad
                        and ("Auto Load ON • " .. config.Selected)
                        or "Auto Load OFF"
                )
            end,
        })

        tab:CreateLabel("Auto Load restores the selected profile next run.")
        tab:CreateLabel("Auto Save writes changes after you adjust any saved control.")

        if next(config.LoadedValues) ~= nil and config.AutoLoad then
            task.defer(function()
                PuckUI:Notify({
                    Title = "Configs",
                    Content = "Auto-loaded " .. config.Selected,
                    Duration = 2.5,
                })
            end)
        end

        return tab
    end

    close.MouseButton1Click:Connect(function()
        if window.CloseCallback then
            window.CloseCallback()
        else
            window:Destroy()
        end
    end)

    minimize.MouseButton1Click:Connect(function()
        window:ClosePopup()
        window.Minimized = not window.Minimized

        tabBar.Visible = not window.Minimized
        accentTop.Visible = not window.Minimized
        columnsHost.Visible = not window.Minimized

        if window.Minimized then
            local miniHeight = window.ResolvedLayout == "Phone" and 34 or 27
            main.Size = UDim2.fromOffset(window.FullSize.X.Offset, miniHeight)
            shadow.Size = main.Size
            minimize.Text = "+"
        else
            main.Size = window.FullSize
            shadow.Size = window.FullSize
            minimize.Text = "-"
        end
    end)

    -- Dynamic key capture + hide/show handling.
    UserInputService.InputBegan:Connect(function(input, processed)
        local capturingWindow = SharedUIState.CapturingWindow

        if capturingWindow then
            -- Only the window that owns the active capture consumes the key.
            if capturingWindow ~= window then
                return
            end

            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end

            local control = SharedUIState.CapturingControl

            if input.KeyCode == Enum.KeyCode.Escape then
                SharedUIState.SuppressToggleUntil = os.clock() + 0.25
                SharedUIState.CapturingWindow = nil
                SharedUIState.CapturingControl = nil

                if control and control.CancelCapture then
                    control:CancelCapture()
                end
                return
            end

            if input.KeyCode ~= Enum.KeyCode.Unknown then
                local keyName = input.KeyCode.Name

                -- Prevent this same keypress being treated as the newly-set
                -- hide/show shortcut by another loaded PuckUI callback.
                SharedUIState.SuppressToggleUntil = os.clock() + 0.30
                SharedUIState.CapturingWindow = nil
                SharedUIState.CapturingControl = nil

                window:SetToggleKey(input.KeyCode)

                if control then
                    control:_SetKeyName(keyName)
                    safeCallback(control.Callback, keyName)
                end
            end

            return
        end

        if os.clock() < (SharedUIState.SuppressToggleUntil or 0) then
            return
        end

        if processed then
            return
        end

        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == window.ToggleKeyCode then
            window:Toggle()
        end
    end)

    window:ApplyResponsiveLayout()

    -- Config autosave watches control values instead of requiring every game
    -- script to manually call Save after each callback.
    task.spawn(function()
        task.wait(1.0)

        if not config.Available or not config.Enabled then
            return
        end

        config.Ready = true
        config.LastFingerprint = window:_ConfigFingerprint()

        -- If Auto Save is enabled and the selected profile does not exist yet,
        -- create it from the script's current defaults/loaded state.
        if config.AutoSave and not FileAPI.IsFile(configFilePath(config.Selected)) then
            window:_WriteConfig(config.Selected, false)
        end

        while window.ScreenGui and window.ScreenGui.Parent do
            if config.AutoSave and not config.Applying then
                local fingerprint = window:_ConfigFingerprint()

                if fingerprint ~= ""
                    and fingerprint ~= config.LastFingerprint then
                    window:_WriteConfig(config.Selected, false)
                end
            end

            task.wait(0.5)
        end
    end)

    return window
end

return PuckUI
