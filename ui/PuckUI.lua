--[[
    PuckUI v2.0
    Shared PuckAFK game-script UI.

    Visual direction:
      - compact classic/Aztup-style dark hub
      - thin titlebar + horizontally scrollable tab strip
      - two-column bordered group boxes
      - square checkbox toggles
      - dense buttons, sliders, inputs and dropdowns
      - dropdowns use a top-level popup layer so they are never clipped
      - dedicated titlebar drag handle for reliable dragging

    UI only: no game-specific automation or loader logic.
]]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local LocalPlayer = Players.LocalPlayer

local PuckUI = {
    Version = "2.1.0",
    Flags = {},
    Window = nil,
}

local Theme = {
    Main = Color3.fromRGB(12, 12, 12),
    Top = Color3.fromRGB(18, 18, 18),
    Tab = Color3.fromRGB(15, 15, 15),
    Section = Color3.fromRGB(19, 19, 19),
    SectionInner = Color3.fromRGB(16, 16, 16),
    Element = Color3.fromRGB(34, 34, 34),
    ElementHover = Color3.fromRGB(43, 43, 43),
    Border = Color3.fromRGB(58, 58, 58),
    BorderDark = Color3.fromRGB(3, 3, 3),
    Text = Color3.fromRGB(198, 198, 198),
    DimText = Color3.fromRGB(137, 137, 137),
    BrightText = Color3.fromRGB(232, 232, 232),
    Accent = Color3.fromRGB(20, 126, 235),
    Danger = Color3.fromRGB(180, 58, 64),
    Success = Color3.fromRGB(48, 145, 78),
}

PuckUI.Theme = Theme

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
    if type(gethui) == "function" then
        local ok, target = pcall(gethui)
        if ok and target then
            screenGui.Parent = target
            return target
        end
    end

    local ok = pcall(function()
        screenGui.Parent = CoreGui
    end)
    if ok and screenGui.Parent then
        return CoreGui
    end

    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui and LocalPlayer then
        playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
    end
    if playerGui then
        screenGui.Parent = playerGui
    end
    return playerGui
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

    local toast = create("Frame", {
        Size = UDim2.fromOffset(280, 56),
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

    local title = codeLabel(toast, data.Title or "PuckAFK", 12, Theme.BrightText, 703)
    title.Position = UDim2.fromOffset(12, 5)
    title.Size = UDim2.new(1, -18, 0, 18)

    local content = codeLabel(toast, data.Content or "", 11, Theme.DimText, 703)
    content.Position = UDim2.fromOffset(12, 22)
    content.Size = UDim2.new(1, -18, 0, 28)
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

    local width = tonumber(settings.Width) or 440
    local height = tonumber(settings.Height) or 530
    width = math.max(360, width)
    height = math.max(360, height)

    local screen = create("ScreenGui", {
        Name = settings.GuiName or "PuckAFK_UI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 10000,
    })
    getGuiParent(screen)

    local main = create("Frame", {
        Name = "Main",
        Position = UDim2.new(0.5, -math.floor(width / 2), 0.5, -math.floor(height / 2)),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Theme.Main,
        BorderColor3 = Theme.BorderDark,
        BorderSizePixel = 1,
        Active = true,
        ZIndex = 2,
        Parent = screen,
    })

    -- Classic double-edge shell.
    create("Frame", {
        Name = "InnerBorder",
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(1, -4, 1, -4),
        BackgroundTransparency = 1,
        BorderColor3 = Theme.Border,
        BorderSizePixel = 1,
        ZIndex = 3,
        Parent = main,
    })

    local titleBar = create("Frame", {
        Name = "TitleBar",
        Position = UDim2.fromOffset(3, 3),
        Size = UDim2.new(1, -6, 0, 21),
        BackgroundColor3 = Theme.Top,
        BorderColor3 = Theme.Border,
        BorderSizePixel = 1,
        ZIndex = 8,
        Parent = main,
    })

    -- Subtle old-school textured strip.
    create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Image = "rbxassetid://2454009026",
        ImageColor3 = Color3.fromRGB(75, 75, 75),
        ImageTransparency = 0.72,
        ScaleType = Enum.ScaleType.Tile,
        TileSize = UDim2.fromOffset(32, 16),
        ZIndex = 9,
        Parent = titleBar,
    })

    local titleLabel = codeLabel(titleBar, settings.Name or settings.Title or "PuckAFK", 13, Theme.BrightText, 11)
    titleLabel.Position = UDim2.fromOffset(5, 0)
    titleLabel.Size = UDim2.new(1, -52, 1, 0)

    local close = create("TextButton", {
        Name = "Close",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -2, 0, 0),
        Size = UDim2.fromOffset(18, 20),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.Code,
        Text = "x",
        TextSize = 11,
        TextColor3 = Theme.DimText,
        ZIndex = 15,
        Parent = titleBar,
    })

    local minimize = create("TextButton", {
        Name = "Minimize",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -20, 0, 0),
        Size = UDim2.fromOffset(18, 20),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.Code,
        Text = "-",
        TextSize = 11,
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
        Position = UDim2.fromOffset(3, 26),
        Size = UDim2.new(1, -6, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 9,
        Parent = main,
    })

    local tabBar = create("ScrollingFrame", {
        Name = "TabBar",
        Position = UDim2.fromOffset(3, 26),
        Size = UDim2.new(1, -6, 0, 21),
        BackgroundColor3 = Theme.Tab,
        BorderColor3 = Theme.Border,
        BorderSizePixel = 1,
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
        Padding = UDim.new(0, 0),
        Parent = tabBar,
    })

    local columnsHost = create("Frame", {
        Name = "ColumnsHost",
        Position = UDim2.fromOffset(5, 50),
        Size = UDim2.new(1, -10, 1, -55),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        ZIndex = 4,
        Parent = main,
    })

    -- Popup layer is NOT inside the scrolling columns.
    -- This is what fixes dropdowns being hidden under/inside other sections.
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
        FullSize = UDim2.fromOffset(width, height),
        ToggleKey = settings.ToggleUIKeybind or settings.ToggleKeybind or "K",
    }

    self.Window = window

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
        main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
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
        self.Main.Visible = state == true
        if not self.Main.Visible then
            self:ClosePopup()
        end
    end

    function window:Toggle()
        self:SetVisible(not self.Main.Visible)
    end

    function window:Destroy()
        self:ClosePopup()
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

        -- Keep selected tab visible in the horizontal strip.
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
        local buttonWidth = math.max(42, textSize.X + 14)

        local button = create("TextButton", {
            Name = "Tab_" .. tab.Name,
            LayoutOrder = #self.Tabs + 1,
            Size = UDim2.fromOffset(buttonWidth, 19),
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

        local highlight = create("Frame", {
            Position = UDim2.new(0, 2, 1, -1),
            Size = UDim2.new(1, -4, 0, 1),
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

        local singleColumn = create("ScrollingFrame", {
            Name = "SingleColumn",
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = Color3.fromRGB(86, 86, 86),
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ElasticBehavior = Enum.ElasticBehavior.Never,
            ZIndex = 4,
            Parent = container,
        })

        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 5),
            Parent = singleColumn,
        })

        create("UIPadding", {
            PaddingBottom = UDim.new(0, 5),
            Parent = singleColumn,
        })

        for index = 1, 2 do
            local leftSide = index == 1
            local scroll = create("ScrollingFrame", {
                Name = "Column" .. tostring(index),
                Position = UDim2.new(leftSide and 0 or 0.5, leftSide and 0 or 4, 0, 0),
                Size = UDim2.new(0.5, -4, 1, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = Color3.fromRGB(86, 86, 86),
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ElasticBehavior = Enum.ElasticBehavior.Never,
                ZIndex = 4,
                Visible = false,
                Parent = container,
            })

            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 5),
                Parent = scroll,
            })

            create("UIPadding", {
                PaddingRight = UDim.new(0, leftSide and 2 or 0),
                PaddingBottom = UDim.new(0, 5),
                Parent = scroll,
            })

            scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                if window.OpenPopup then
                    window:ClosePopup()
                end
            end)

            columns[index] = scroll
        end

        singleColumn:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
            if window.OpenPopup then
                window:ClosePopup()
            end
        end)

        tab.Button = button
        tab.Highlight = highlight
        tab.Container = container
        tab.Columns = columns
        tab.SingleColumn = singleColumn

        local function relayoutSections()
            local count = #tab.Sections
            if count <= 1 then
                singleColumn.Visible = true
                columns[1].Visible = false
                columns[2].Visible = false
                if count == 1 then
                    local section = tab.Sections[1]
                    if section and section.Frame.Parent ~= singleColumn then
                        section.Frame.Parent = singleColumn
                    end
                end
                return
            end

            singleColumn.Visible = false
            columns[1].Visible = true
            columns[2].Visible = true

            local heights = {0, 0}
            for _, section in ipairs(tab.Sections) do
                local est = section.Frame.AbsoluteSize.Y
                if est <= 0 then
                    est = section.EstimatedHeight or 86
                end
                local targetIndex = heights[1] <= heights[2] and 1 or 2
                heights[targetIndex] = heights[targetIndex] + est + 5
                if section.Frame.Parent ~= columns[targetIndex] then
                    section.Frame.Parent = columns[targetIndex]
                end
            end
        end

        function tab:CreateSection(sectionName)
            local section = {
                Name = tostring(sectionName or "Section"),
                Tab = self,
            }

            local frame = create("Frame", {
                Name = "Section_" .. section.Name,
                Size = UDim2.new(1, -2, 0, 24),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.SectionInner,
                BorderColor3 = Theme.Border,
                BorderSizePixel = 1,
                ClipsDescendants = false,
                ZIndex = 5,
                Parent = singleColumn,
            })

            create("UIStroke", {
                Color = Theme.BorderDark,
                Thickness = 1,
                Transparency = 0,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                Parent = frame,
            })

            -- Group-box title sits over the top border.
            local headerPatch = create("Frame", {
                Position = UDim2.fromOffset(5, -6),
                Size = UDim2.fromOffset(
                    math.max(48, TextService:GetTextSize(section.Name, 12, Enum.Font.Code, Vector2.new(1000, 16)).X + 10),
                    14
                ),
                BackgroundColor3 = Theme.Main,
                BorderSizePixel = 0,
                ZIndex = 7,
                Parent = frame,
            })

            local header = codeLabel(headerPatch, section.Name, 12, Theme.BrightText, 8)
            header.Position = UDim2.fromOffset(4, 0)
            header.Size = UDim2.new(1, -8, 1, 0)

            local body = create("Frame", {
                Name = "Body",
                Position = UDim2.fromOffset(5, 8),
                Size = UDim2.new(1, -10, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = false,
                ZIndex = 6,
                Parent = frame,
            })

            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 1),
                Parent = body,
            })

            create("UIPadding", {
                PaddingBottom = UDim.new(0, 5),
                Parent = body,
            })

            section.Frame = frame
            section.Body = body
            section.EstimatedHeight = 86

            function section:Set(newName)
                self.Name = tostring(newName or "")
                header.Text = self.Name
            end

            frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                section.EstimatedHeight = math.max(section.Frame.AbsoluteSize.Y, 86)
                task.defer(relayoutSections)
            end)

            table.insert(self.Sections, section)
            self._currentSection = section
            task.defer(relayoutSections)
            return section
        end

        local function addControlFrame(height)
            local section = getCurrentSection(tab)
            return create("Frame", {
                Size = UDim2.new(1, 0, 0, height),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = false,
                ZIndex = 6,
                Parent = section.Body,
            })
        end

        function tab:CreateDivider()
            local row = addControlFrame(7)
            local divider = create("Frame", {
                Position = UDim2.fromOffset(0, 3),
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
                label.Text = tostring(value or "")
                if typeof(newColor) == "Color3" then
                    label.TextColor3 = newColor
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

            local title = codeLabel(row, data.Title or "", 11, Theme.BrightText, 7)
            title.Position = UDim2.fromOffset(0, 0)
            title.Size = UDim2.new(1, 0, 0, 16)

            local body = codeLabel(row, contentText, 10, Theme.DimText, 7)
            body.Position = UDim2.fromOffset(0, 16)
            body.Size = UDim2.new(1, 0, 1, -16)
            body.TextWrapped = true
            body.TextYAlignment = Enum.TextYAlignment.Top

            local object = {}
            function object:Set(nextData)
                if type(nextData) == "table" then
                    if nextData.Title ~= nil then
                        title.Text = tostring(nextData.Title)
                    end
                    if nextData.Content ~= nil then
                        body.Text = tostring(nextData.Content)
                    end
                else
                    body.Text = tostring(nextData or "")
                end
            end

            return object
        end

        function tab:CreateButton(data)
            data = data or {}
            local row = addControlFrame(23)

            local buttonControl = create("TextButton", {
                Position = UDim2.fromOffset(0, 1),
                Size = UDim2.new(1, 0, 1, -2),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.Border,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = tostring(data.Name or data.Text or "Button"),
                TextColor3 = Theme.Text,
                TextSize = 12,
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

            local row = addControlFrame(20)
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
                Position = UDim2.fromOffset(1, 4),
                Size = UDim2.fromOffset(11, 11),
                BackgroundColor3 = Color3.fromRGB(11, 11, 11),
                BorderColor3 = Theme.Border,
                BorderSizePixel = 1,
                ZIndex = 7,
                Parent = row,
            })

            local fill = create("Frame", {
                Position = UDim2.fromOffset(2, 2),
                Size = UDim2.new(1, -4, 1, -4),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                Visible = state,
                ZIndex = 8,
                Parent = box,
            })
            table.insert(window.AccentObjects, fill)

            local label = codeLabel(row, data.Name or data.Text or "Toggle", 12, state and Theme.Text or Theme.DimText, 7)
            label.Position = UDim2.fromOffset(18, 0)
            label.Size = UDim2.new(1, -18, 1, 0)
            label.TextTruncate = Enum.TextTruncate.AtEnd

            local object = {}

            local function apply(value, invokeCallback)
                state = value == true
                fill.Visible = state
                label.TextColor3 = state and Theme.Text or Theme.DimText

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
                Position = UDim2.fromOffset(0, 16),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.Border,
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
            arrow.Size = UDim2.fromOffset(12, 18)
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
                local itemHeight = 19
                local maxVisible = tonumber(data.MaxVisible) or 8
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
                    BackgroundColor3 = Color3.fromRGB(25, 25, 25),
                    BorderColor3 = Theme.Border,
                    BorderSizePixel = 1,
                    CanvasSize = UDim2.new(),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    ScrollBarThickness = #options > maxVisible and 2 or 0,
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
                        TextSize = 10,
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

            return object
        end

        function tab:CreateSlider(data)
            data = data or {}

            local row = addControlFrame(37)
            local minimum = tonumber(data.Range and data.Range[1] or data.Min) or 0
            local maximum = tonumber(data.Range and data.Range[2] or data.Max) or 100
            local increment = tonumber(data.Increment) or 1
            local suffix = tostring(data.Suffix or "")

            local value = tonumber(data.CurrentValue or data.Value) or minimum
            value = math.clamp(value, minimum, maximum)

            local label = codeLabel(row, data.Name or "Slider", 12, Theme.Text, 7)
            label.Size = UDim2.new(0.68, 0, 0, 16)

            local valueLabel = codeLabel(row, tostring(value) .. suffix, 11, Theme.DimText, 7)
            valueLabel.Position = UDim2.new(0.68, 0, 0, 0)
            valueLabel.Size = UDim2.new(0.32, 0, 0, 16)
            valueLabel.TextXAlignment = Enum.TextXAlignment.Right

            local rail = create("Frame", {
                Position = UDim2.fromOffset(0, 22),
                Size = UDim2.new(1, 0, 0, 7),
                BackgroundColor3 = Color3.fromRGB(9, 9, 9),
                BorderColor3 = Theme.Border,
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

                -- keep decimals stable for increments such as 0.05 / 0.5
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

            return object
        end

        function tab:CreateInput(data)
            data = data or {}

            local row = addControlFrame(41)

            local label = codeLabel(row, data.Name or "Input", 12, Theme.Text, 7)
            label.Size = UDim2.new(1, 0, 0, 16)

            local box = create("TextBox", {
                Position = UDim2.fromOffset(0, 16),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = Color3.fromRGB(22, 22, 22),
                BorderColor3 = Theme.Border,
                BorderSizePixel = 1,
                ClearTextOnFocus = false,
                Font = Enum.Font.Code,
                Text = tostring(data.CurrentValue or ""),
                PlaceholderText = tostring(data.PlaceholderText or ""),
                TextColor3 = Theme.Text,
                PlaceholderColor3 = Theme.DimText,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 8,
                Parent = row,
            })

            create("UIPadding", {
                PaddingLeft = UDim.new(0, 5),
                PaddingRight = UDim.new(0, 5),
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

            return object
        end

        button.MouseButton1Click:Connect(function()
            window:SelectTab(tab)
        end)

        table.insert(self.Tabs, tab)

        if #self.Tabs == 1 then
            task.defer(function()
                if button.Parent then
                    self:SelectTab(tab)
                end
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
            main.Size = UDim2.fromOffset(width, 25)
            minimize.Text = "+"
        else
            main.Size = window.FullSize
            minimize.Text = "-"
        end
    end)

    -- K (or configured key) toggles the whole UI.
    local keyName = tostring(window.ToggleKey or "K")
    local keyCode = Enum.KeyCode[keyName] or Enum.KeyCode.K

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
            return
        end
        if input.KeyCode == keyCode then
            window:Toggle()
        end
    end)

    return window
end

return PuckUI
