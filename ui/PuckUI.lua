--[[
    PuckUI v1.0
    Standard PuckAFK game-script UI.

    Visual target: CleanStandaloneUI supplied by PuckAFK.
    - dark 500x600 panel
    - Enum.Font.Code typography
    - top tab strip + accent underline
    - two scrolling columns
    - compact section boxes / controls

    This file intentionally contains UI only. It has no game automation,
    analytics, Discord RPC, filesystem config requirement, or loader logic.
]]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local LocalPlayer = Players.LocalPlayer

local PuckUI = {
    Version = "1.0.0",
    Flags = {},
    Window = nil,
}

local Theme = {
    Main = Color3.fromRGB(20, 20, 20),
    Top = Color3.fromRGB(30, 30, 30),
    Section = Color3.fromRGB(30, 30, 30),
    Element = Color3.fromRGB(50, 50, 50),
    ElementHover = Color3.fromRGB(57, 57, 57),
    Border = Color3.fromRGB(60, 60, 60),
    Text = Color3.fromRGB(210, 210, 210),
    DimText = Color3.fromRGB(160, 160, 160),
    BrightText = Color3.fromRGB(255, 255, 255),
    Accent = Color3.fromRGB(18, 127, 253),
    Danger = Color3.fromRGB(190, 65, 70),
    Success = Color3.fromRGB(52, 145, 82),
}
PuckUI.Theme = Theme

local function tween(instance, duration, properties)
    local t = TweenService:Create(
        instance,
        TweenInfo.new(duration or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        properties
    )
    t:Play()
    return t
end

local function create(className, properties)
    local obj = Instance.new(className)
    for key, value in pairs(properties or {}) do
        obj[key] = value
    end
    return obj
end

local function corner(parent, radius)
    local c = create("UICorner", {
        CornerRadius = UDim.new(0, radius or 2),
        Parent = parent,
    })
    return c
end

local function stroke(parent, color, thickness, transparency)
    local s = create("UIStroke", {
        Color = color or Theme.Border,
        Thickness = thickness or 1,
        Transparency = transparency == nil and 0 or transparency,
        Parent = parent,
    })
    return s
end

local function codeLabel(parent, text, size, color)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = tostring(text or ""),
        TextColor3 = color or Theme.Text,
        TextSize = size or 13,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Parent = parent,
    })
end

local function getGuiParent(screenGui)
    if gethui then
        local ok, result = pcall(gethui)
        if ok and result then
            screenGui.Parent = result
            return result
        end
    end

    local ok = pcall(function()
        screenGui.Parent = CoreGui
    end)
    if ok then
        return CoreGui
    end

    local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg and LocalPlayer then
        pg = LocalPlayer:WaitForChild("PlayerGui", 10)
    end
    if pg then
        screenGui.Parent = pg
    end
    return pg
end

local function setButtonHover(button, normal, hover)
    button.MouseEnter:Connect(function()
        tween(button, 0.12, {BackgroundColor3 = hover})
    end)
    button.MouseLeave:Connect(function()
        tween(button, 0.12, {BackgroundColor3 = normal})
    end)
end

local function normalizeDropdownValue(value)
    if type(value) == "table" then
        return value[1]
    end
    return value
end

local function getCurrentSection(tab)
    if tab._currentSection then
        return tab._currentSection
    end
    return tab:CreateSection("Main")
end

function PuckUI:SetAccent(color)
    if typeof(color) ~= "Color3" then return end
    Theme.Accent = color
    local window = self.Window
    if not window then return end

    if window.AccentLine then window.AccentLine.BackgroundColor3 = color end
    if window.TabHighlight then window.TabHighlight.BackgroundColor3 = color end
    if window.CurrentTab and window.CurrentTab.Button then
        window.CurrentTab.Button.TextColor3 = color
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
end

function PuckUI:Notify(data)
    local window = self.Window
    if not window or not window.ScreenGui or not window.ScreenGui.Parent then return end

    local holder = window.NotificationHolder
    local toast = create("Frame", {
        Size = UDim2.fromOffset(300, 64),
        BackgroundColor3 = Theme.Section,
        BorderColor3 = Theme.Border,
        BorderSizePixel = 1,
        Parent = holder,
    })

    local accent = create("Frame", {
        Size = UDim2.new(0, 2, 1, -10),
        Position = UDim2.fromOffset(5, 5),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = toast,
    })
    table.insert(window.AccentObjects, accent)

    local title = codeLabel(toast, (data and data.Title) or "PuckAFK", 13, Theme.BrightText)
    title.Font = Enum.Font.Code
    title.Position = UDim2.fromOffset(14, 7)
    title.Size = UDim2.new(1, -20, 0, 18)

    local body = codeLabel(toast, (data and data.Content) or "", 11, Theme.DimText)
    body.Position = UDim2.fromOffset(14, 25)
    body.Size = UDim2.new(1, -20, 0, 32)
    body.TextWrapped = true
    body.TextYAlignment = Enum.TextYAlignment.Top

    toast.BackgroundTransparency = 1
    title.TextTransparency = 1
    body.TextTransparency = 1
    accent.BackgroundTransparency = 1
    tween(toast, 0.16, {BackgroundTransparency = 0})
    tween(title, 0.16, {TextTransparency = 0})
    tween(body, 0.16, {TextTransparency = 0})
    tween(accent, 0.16, {BackgroundTransparency = 0})

    task.delay((data and data.Duration) or 3, function()
        if not toast.Parent then return end
        tween(toast, 0.16, {BackgroundTransparency = 1})
        tween(title, 0.16, {TextTransparency = 1})
        tween(body, 0.16, {TextTransparency = 1})
        tween(accent, 0.16, {BackgroundTransparency = 1})
        task.wait(0.18)
        if toast.Parent then toast:Destroy() end
    end)
end

function PuckUI:CreateWindow(settings)
    settings = settings or {}

    if self.Window and self.Window.ScreenGui then
        pcall(function() self.Window.ScreenGui:Destroy() end)
    end

    local screen = create("ScreenGui", {
        Name = settings.GuiName or "PuckAFK_UI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    getGuiParent(screen)

    local main = create("ImageButton", {
        Name = "Main",
        AutoButtonColor = false,
        Position = UDim2.new(0.5, -250, 0.5, -300),
        Size = UDim2.fromOffset(500, 600),
        BackgroundColor3 = Theme.Main,
        BorderColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 1,
        Image = "",
        Parent = screen,
    })

    local top = create("Frame", {
        Name = "Top",
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = Theme.Top,
        BorderColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 1,
        Parent = main,
    })

    create("ImageLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Image = "rbxassetid://2454009026",
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 0.42,
        Parent = top,
    })

    local title = codeLabel(main, settings.Name or settings.Title or "PuckAFK", 18, Theme.BrightText)
    title.Name = "Title"
    title.Position = UDim2.fromOffset(6, 0)
    title.Size = UDim2.new(1, -72, 0, 22)

    local accentLine = create("Frame", {
        Name = "AccentLine",
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.fromOffset(0, 24),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = main,
    })

    local tabHighlight = create("Frame", {
        Name = "TabHighlight",
        Position = UDim2.fromOffset(6, 49),
        Size = UDim2.fromOffset(0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = main,
    })

    local close = create("TextButton", {
        Name = "Close",
        Size = UDim2.fromOffset(22, 18),
        Position = UDim2.new(1, -26, 0, 3),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        Text = "x",
        TextSize = 14,
        TextColor3 = Theme.DimText,
        Parent = main,
    })

    local minimize = create("TextButton", {
        Name = "Minimize",
        Size = UDim2.fromOffset(22, 18),
        Position = UDim2.new(1, -49, 0, 3),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        Text = "-",
        TextSize = 14,
        TextColor3 = Theme.DimText,
        Parent = main,
    })

    local columnsHost = create("Frame", {
        Name = "Columns",
        Position = UDim2.fromOffset(5, 55),
        Size = UDim2.new(1, -10, 1, -60),
        BackgroundTransparency = 1,
        Parent = main,
    })

    local notificationHolder = create("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 12),
        Size = UDim2.fromOffset(310, 500),
        BackgroundTransparency = 1,
        Parent = screen,
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 5),
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = notificationHolder,
    })

    -- Original CleanStandaloneUI uses two slice images for the dark border treatment.
    create("ImageLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Image = "rbxassetid://2592362371",
        ImageColor3 = Theme.Border,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(2, 2, 62, 62),
        ZIndex = 20,
        Parent = main,
    })
    create("ImageLabel", {
        Size = UDim2.new(1, -2, 1, -2),
        Position = UDim2.fromOffset(1, 1),
        BackgroundTransparency = 1,
        Image = "rbxassetid://2592362371",
        ImageColor3 = Color3.new(0, 0, 0),
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(2, 2, 62, 62),
        ZIndex = 20,
        Parent = main,
    })

    local window = {
        ScreenGui = screen,
        Main = main,
        Top = top,
        TitleLabel = title,
        AccentLine = accentLine,
        TabHighlight = tabHighlight,
        ColumnsHost = columnsHost,
        NotificationHolder = notificationHolder,
        AccentObjects = {accentLine, tabHighlight},
        Tabs = {},
        CurrentTab = nil,
        CloseCallback = nil,
        Open = true,
        Minimized = false,
    }

    self.Window = window

    local dragging = false
    local dragStart
    local startPos

    top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = input.Position - dragStart
        local y = math.max(-36, startPos.Y.Offset + delta.Y)
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, y)
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    function window:SetCloseCallback(callback)
        self.CloseCallback = callback
    end

    function window:SetTitle(text)
        self.TitleLabel.Text = tostring(text or "PuckAFK")
    end

    function window:SetVisible(state)
        self.Main.Visible = state == true
    end

    function window:Toggle()
        self.Main.Visible = not self.Main.Visible
    end

    function window:Destroy()
        if self.ScreenGui then
            self.ScreenGui:Destroy()
        end
    end

    function window:SelectTab(tab)
        if self.CurrentTab == tab then return end

        if self.CurrentTab then
            self.CurrentTab.Button.TextColor3 = Theme.BrightText
            self.CurrentTab.Container.Visible = false
        end

        self.CurrentTab = tab
        tab.Container.Visible = true
        tab.Button.TextColor3 = Theme.Accent

        tween(self.TabHighlight, 0.20, {
            Position = UDim2.new(0, tab.Button.Position.X.Offset, 0, 49),
            Size = UDim2.new(0, tab.Button.AbsoluteSize.X, 0, 1),
        })
    end

    local tabOffset = 6

    function window:CreateTab(tabName, _icon)
        local tab = {
            Name = tostring(tabName),
            Window = self,
            Sections = {},
            _nextColumn = 1,
            _currentSection = nil,
        }

        local size = TextService:GetTextSize(tab.Name, 14, Enum.Font.Code, Vector2.new(1000, 20))
        local buttonWidth = math.max(42, size.X + 12)

        local button = create("TextButton", {
            Name = "Tab_" .. tab.Name,
            Position = UDim2.fromOffset(tabOffset, 27),
            Size = UDim2.fromOffset(buttonWidth, 22),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.Code,
            Text = tab.Name,
            TextSize = 14,
            TextColor3 = Theme.BrightText,
            Parent = main,
        })
        tabOffset += buttonWidth

        local container = create("Frame", {
            Name = "Content_" .. tab.Name,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
            Parent = columnsHost,
        })

        local columns = {}
        for index = 1, 2 do
            local scroll = create("ScrollingFrame", {
                Name = "Column" .. tostring(index),
                Position = UDim2.new(index == 1 and 0 or 0.5, index == 1 and 0 or 3, 0, 0),
                Size = UDim2.new(0.5, -3, 1, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 4,
                ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100),
                ScrollingDirection = Enum.ScrollingDirection.Y,
                Parent = container,
            })
            create("UIListLayout", {
                Padding = UDim.new(0, 6),
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = scroll,
            })
            columns[index] = scroll
        end

        tab.Button = button
        tab.Container = container
        tab.Columns = columns

        local function chooseColumn()
            local left = columns[1].AbsoluteCanvasSize.Y
            local right = columns[2].AbsoluteCanvasSize.Y
            if left == 0 and right == 0 then
                local index = tab._nextColumn
                tab._nextColumn = tab._nextColumn == 1 and 2 or 1
                return columns[index]
            end
            return left <= right and columns[1] or columns[2]
        end

        function tab:CreateSection(sectionName)
            local section = {
                Name = tostring(sectionName),
                Tab = self,
            }

            local frame = create("Frame", {
                Name = "Section_" .. section.Name,
                Size = UDim2.new(1, -2, 0, 30),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Section,
                BorderColor3 = Theme.Border,
                BorderSizePixel = 1,
                Parent = chooseColumn(),
            })

            local header = codeLabel(frame, section.Name, 13, Theme.BrightText)
            header.Position = UDim2.fromOffset(7, 2)
            header.Size = UDim2.new(1, -14, 0, 20)

            local body = create("Frame", {
                Name = "Body",
                Position = UDim2.fromOffset(6, 24),
                Size = UDim2.new(1, -12, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Parent = frame,
            })
            create("UIListLayout", {
                Padding = UDim.new(0, 4),
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = body,
            })
            create("UIPadding", {
                PaddingBottom = UDim.new(0, 6),
                Parent = body,
            })

            section.Frame = frame
            section.Body = body
            table.insert(self.Sections, section)
            self._currentSection = section
            return section
        end

        local function addControlFrame(height)
            local section = getCurrentSection(tab)
            return create("Frame", {
                Size = UDim2.new(1, 0, 0, height),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Parent = section.Body,
            })
        end

        function tab:CreateLabel(text)
            local row = addControlFrame(18)
            local label = codeLabel(row, text, 12, Theme.DimText)
            label.Size = UDim2.fromScale(1, 1)
            return label
        end

        function tab:CreateParagraph(data)
            data = data or {}
            local row = addControlFrame(54)
            local titleLabel = codeLabel(row, data.Title or "", 12, Theme.Text)
            titleLabel.Position = UDim2.fromOffset(0, 0)
            titleLabel.Size = UDim2.new(1, 0, 0, 18)

            local bodyLabel = codeLabel(row, data.Content or "", 11, Theme.DimText)
            bodyLabel.Position = UDim2.fromOffset(0, 18)
            bodyLabel.Size = UDim2.new(1, 0, 0, 34)
            bodyLabel.TextWrapped = true
            bodyLabel.TextYAlignment = Enum.TextYAlignment.Top

            local object = {}
            function object:Set(nextData)
                if type(nextData) == "table" then
                    if nextData.Title ~= nil then titleLabel.Text = tostring(nextData.Title) end
                    if nextData.Content ~= nil then bodyLabel.Text = tostring(nextData.Content) end
                else
                    bodyLabel.Text = tostring(nextData or "")
                end
            end
            return object
        end

        function tab:CreateButton(data)
            data = data or {}
            local row = addControlFrame(28)
            local buttonControl = create("TextButton", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.Border,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = tostring(data.Name or data.Text or "Button"),
                TextColor3 = Theme.Text,
                TextSize = 12,
                Parent = row,
            })
            setButtonHover(buttonControl, Theme.Element, Theme.ElementHover)
            buttonControl.MouseButton1Click:Connect(function()
                if data.Callback then
                    task.spawn(data.Callback)
                end
            end)
            local object = {Button = buttonControl}
            function object:SetText(value)
                buttonControl.Text = tostring(value)
            end
            return object
        end

        function tab:CreateToggle(data)
            data = data or {}
            local row = addControlFrame(24)
            local state = data.CurrentValue == true
            local name = tostring(data.Name or data.Text or "Toggle")

            local hit = create("TextButton", {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = "",
                Parent = row,
            })

            local box = create("Frame", {
                Position = UDim2.fromOffset(1, 5),
                Size = UDim2.fromOffset(14, 14),
                BackgroundColor3 = Color3.fromRGB(30, 30, 30),
                BorderColor3 = Theme.Border,
                BorderSizePixel = 1,
                Parent = row,
            })
            local fill = create("Frame", {
                Position = UDim2.fromOffset(2, 2),
                Size = UDim2.new(1, -4, 1, -4),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                Visible = state,
                Parent = box,
            })
            table.insert(window.AccentObjects, fill)

            local label = codeLabel(row, name, 12, state and Theme.Text or Theme.DimText)
            label.Position = UDim2.fromOffset(22, 1)
            label.Size = UDim2.new(1, -22, 1, -2)

            local object = {}
            local flag = data.Flag
            local function apply(value, invokeCallback)
                state = value == true
                fill.Visible = state
                label.TextColor3 = state and Theme.Text or Theme.DimText
                if flag then
                    PuckUI.Flags[flag] = state
                end
                if invokeCallback and data.Callback then
                    task.spawn(data.Callback, state)
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

            if flag then PuckUI.Flags[flag] = state end
            return object
        end

        function tab:CreateDropdown(data)
            data = data or {}
            local row = addControlFrame(48)
            local name = codeLabel(row, data.Name or "Dropdown", 12, Theme.Text)
            name.Size = UDim2.new(1, 0, 0, 18)

            local options = data.Options or {}
            local current = normalizeDropdownValue(data.CurrentOption) or options[1]
            local open = false

            local selector = create("TextButton", {
                Position = UDim2.fromOffset(0, 20),
                Size = UDim2.new(1, 0, 0, 24),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.Border,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = "  " .. tostring(current or "Select..."),
                TextColor3 = Theme.Text,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
            setButtonHover(selector, Theme.Element, Theme.ElementHover)

            local arrow = codeLabel(selector, "v", 11, Theme.DimText)
            arrow.AnchorPoint = Vector2.new(1, 0)
            arrow.Position = UDim2.new(1, -5, 0, 2)
            arrow.Size = UDim2.fromOffset(12, 20)
            arrow.TextXAlignment = Enum.TextXAlignment.Center

            local menu = create("Frame", {
                Position = UDim2.new(0, 0, 1, 2),
                Size = UDim2.new(1, 0, 0, math.max(26, #options * 24 + 4)),
                BackgroundColor3 = Color3.fromRGB(40, 40, 40),
                BorderColor3 = Theme.Border,
                BorderSizePixel = 1,
                Visible = false,
                ZIndex = 40,
                Parent = selector,
            })
            create("UIListLayout", {
                Padding = UDim.new(0, 1),
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = menu,
            })

            local object = {}
            local flag = data.Flag

            local function apply(value, invokeCallback)
                if value == nil then return end
                current = value
                selector.Text = "  " .. tostring(current)
                if flag then PuckUI.Flags[flag] = current end
                if invokeCallback and data.Callback then
                    task.spawn(data.Callback, {current})
                end
            end

            for index, value in ipairs(options) do
                local optionButton = create("TextButton", {
                    LayoutOrder = index,
                    Size = UDim2.new(1, 0, 0, 23),
                    BackgroundColor3 = Color3.fromRGB(40, 40, 40),
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Font = Enum.Font.Code,
                    Text = "  " .. tostring(value),
                    TextColor3 = Theme.Text,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 41,
                    Parent = menu,
                })
                setButtonHover(optionButton, Color3.fromRGB(40, 40, 40), Theme.Element)
                optionButton.MouseButton1Click:Connect(function()
                    apply(value, true)
                    open = false
                    menu.Visible = false
                    arrow.Text = "v"
                end)
            end

            selector.MouseButton1Click:Connect(function()
                open = not open
                menu.Visible = open
                arrow.Text = open and "^" or "v"
            end)

            function object:Set(value)
                apply(normalizeDropdownValue(value), true)
            end
            function object:Get()
                return current
            end

            if flag and current ~= nil then PuckUI.Flags[flag] = current end
            return object
        end

        function tab:CreateSlider(data)
            data = data or {}
            local row = addControlFrame(43)
            local min = tonumber(data.Range and data.Range[1] or data.Min) or 0
            local max = tonumber(data.Range and data.Range[2] or data.Max) or 100
            local value = tonumber(data.CurrentValue or data.Value) or min
            value = math.clamp(value, min, max)

            local label = codeLabel(row, data.Name or "Slider", 12, Theme.Text)
            label.Size = UDim2.new(0.7, 0, 0, 18)
            local valueLabel = codeLabel(row, tostring(value), 11, Theme.DimText)
            valueLabel.Position = UDim2.new(0.7, 0, 0, 0)
            valueLabel.Size = UDim2.new(0.3, 0, 0, 18)
            valueLabel.TextXAlignment = Enum.TextXAlignment.Right

            local rail = create("Frame", {
                Position = UDim2.fromOffset(0, 24),
                Size = UDim2.new(1, 0, 0, 7),
                BackgroundColor3 = Color3.fromRGB(30, 30, 30),
                BorderColor3 = Theme.Border,
                BorderSizePixel = 1,
                Parent = row,
            })
            local fill = create("Frame", {
                Size = UDim2.new((value - min) / math.max(max - min, 1), 0, 1, 0),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                Parent = rail,
            })
            table.insert(window.AccentObjects, fill)

            local draggingSlider = false
            local flag = data.Flag
            local object = {}

            local function apply(nextValue, invokeCallback)
                nextValue = math.clamp(tonumber(nextValue) or min, min, max)
                if data.Increment then
                    local inc = tonumber(data.Increment) or 1
                    nextValue = math.floor(nextValue / inc + 0.5) * inc
                end
                value = nextValue
                valueLabel.Text = tostring(value)
                fill.Size = UDim2.new((value - min) / math.max(max - min, 1), 0, 1, 0)
                if flag then PuckUI.Flags[flag] = value end
                if invokeCallback and data.Callback then task.spawn(data.Callback, value) end
            end

            local function fromInput(input)
                local ratio = math.clamp((input.Position.X - rail.AbsolutePosition.X) / math.max(rail.AbsoluteSize.X, 1), 0, 1)
                apply(min + ratio * (max - min), true)
            end

            rail.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    draggingSlider = true
                    fromInput(input)
                end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    fromInput(input)
                end
            end)
            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    draggingSlider = false
                end
            end)

            function object:Set(nextValue) apply(nextValue, true) end
            function object:Get() return value end
            if flag then PuckUI.Flags[flag] = value end
            return object
        end

        button.MouseButton1Click:Connect(function()
            window:SelectTab(tab)
        end)

        table.insert(self.Tabs, tab)
        if #self.Tabs == 1 then
            task.defer(function()
                self:SelectTab(tab)
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
        window.Minimized = not window.Minimized
        columnsHost.Visible = not window.Minimized
        for _, tab in ipairs(window.Tabs) do
            tab.Button.Visible = not window.Minimized
        end
        accentLine.Visible = not window.Minimized
        tabHighlight.Visible = not window.Minimized
        main.Size = window.Minimized and UDim2.fromOffset(500, 25) or UDim2.fromOffset(500, 600)
        minimize.Text = window.Minimized and "+" or "-"
    end)

    return window
end

return PuckUI
