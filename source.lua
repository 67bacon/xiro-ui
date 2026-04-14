--[[
    XIRO UI Library v1.0
    Vape-style ClickGUI — draggable category panels
    API-compatible with Rayfield for drop-in replacement
]]

local XiroLib = {}

---------- SERVICES ----------
local Players       = game:GetService("Players")
local UIS           = game:GetService("UserInputService")
local TS            = game:GetService("TweenService")
local RunService    = game:GetService("RunService")
local HttpService   = game:GetService("HttpService")
local LocalPlayer   = Players.LocalPlayer

---------- THEME ----------
local C = {
    BG          = Color3.fromRGB(18, 18, 24),
    Panel       = Color3.fromRGB(24, 24, 32),
    TitleBar    = Color3.fromRGB(30, 30, 40),
    Elem        = Color3.fromRGB(36, 36, 48),
    ElemHover   = Color3.fromRGB(48, 48, 62),
    Text        = Color3.fromRGB(225, 225, 235),
    SubText     = Color3.fromRGB(130, 130, 150),
    Accent      = Color3.fromRGB(140, 100, 255),
    AccentDark  = Color3.fromRGB(100, 70, 200),
    ToggleOn    = Color3.fromRGB(140, 100, 255),
    ToggleOff   = Color3.fromRGB(70, 70, 85),
    SliderFill  = Color3.fromRGB(140, 100, 255),
    SliderBG    = Color3.fromRGB(42, 42, 54),
    SectionText = Color3.fromRGB(110, 100, 160),
    Border      = Color3.fromRGB(42, 42, 56),
    ScrollBar   = Color3.fromRGB(55, 55, 68),
    Notif       = Color3.fromRGB(28, 28, 38),
}

---------- LAYOUT CONSTANTS ----------
local PANEL_W      = 235
local TITLE_H      = 32
local ELEM_H       = 30
local SLIDER_H     = 44
local DROPDOWN_H   = 30
local SECTION_H    = 24
local ACCORDION_H  = 28
local PAD           = 6
local GAP           = 3
local CORNER_R      = 6
local CORNER_SM     = 4
local MAX_PANEL_CONTENT = 480
local FONT          = Enum.Font.Gotham
local FONT_BOLD     = Enum.Font.GothamBold
local FONT_SEMI     = Enum.Font.GothamSemibold
local FSIZE         = 12
local FSIZE_TITLE   = 13
local FSIZE_SMALL   = 11

---------- STATE ----------
local screenGui, panelContainer, notifContainer
local flagStore       = {} -- flag -> {value, set}
local panels          = {}
local panelCount      = 0
local zCounter        = 10
local configEnabled   = false
local configFolder    = ""
local configFile      = ""
local uiVisible       = true
local toggleKeybind   = Enum.KeyCode.RightShift
local openDropdown    = nil -- currently open dropdown closer
local savedMouseBehavior = nil
local FADE_STAGGER    = 0.06 -- stagger delay between panel fade-ins

---------- UTILITIES ----------

local function addCorner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or CORNER_R)
    c.Parent = parent
    return c
end

local function addStroke(parent, thick, color)
    local s = Instance.new("UIStroke")
    s.Thickness = thick or 1
    s.Color = color or C.Border
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function tw(obj, props, dur)
    local t = TS:Create(obj, TweenInfo.new(dur or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

local function snapVal(val, mn, mx, inc)
    val = math.clamp(val, mn, mx)
    val = math.round((val - mn) / inc) * inc + mn
    return math.clamp(val, mn, mx)
end

local function makeDraggable(frame, handle)
    local dragging = false
    local dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            zCounter = zCounter + 1
            frame.ZIndex = zCounter
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

---------- CONFIG SYSTEM ----------

local function saveConfig()
    if not configEnabled then return end
    pcall(function()
        local data = {}
        for flag, info in pairs(flagStore) do
            data[flag] = info.value
        end
        local folder = configFolder
        if not isfolder(folder) then makefolder(folder) end
        writefile(folder .. "/" .. configFile .. ".json", HttpService:JSONEncode(data))
    end)
end

local function registerFlag(flag, value, setter)
    if not flag or flag == "" then return end
    flagStore[flag] = { value = value, set = setter }
end

local function updateFlag(flag, value)
    if not flag or flag == "" then return end
    if flagStore[flag] then
        flagStore[flag].value = value
    end
    saveConfig()
end

---------- ELEMENT FADE-IN HELPER ----------

local function fadeInElement(frame, delay)
    frame.BackgroundTransparency = 1
    for _, child in frame:GetDescendants() do
        if child:IsA("TextLabel") or child:IsA("TextButton") then
            child.TextTransparency = 1
        end
        if child:IsA("GuiObject") and not child:IsA("UICorner") and not child:IsA("UIStroke") and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            if child.BackgroundTransparency < 1 then
                local target = child.BackgroundTransparency
                child.BackgroundTransparency = 1
                task.delay(delay or 0, function()
                    tw(child, {BackgroundTransparency = target}, 0.25)
                end)
            end
        end
    end
    task.delay(delay or 0, function()
        tw(frame, {BackgroundTransparency = 0}, 0.25)
        for _, child in frame:GetDescendants() do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                tw(child, {TextTransparency = 0}, 0.25)
            end
        end
    end)
end

---------- MOUSE CONTROL ----------

local function unlockMouse()
    pcall(function()
        savedMouseBehavior = UIS.MouseBehavior
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        UIS.MouseIconEnabled = true
    end)
end

local function restoreMouse()
    pcall(function()
        if savedMouseBehavior then
            UIS.MouseBehavior = savedMouseBehavior
        else
            UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
        end
    end)
end

---------- CLOSE OPEN DROPDOWN ----------

local function closeOpenDropdown()
    if openDropdown then
        pcall(openDropdown)
        openDropdown = nil
    end
end

---------- PANEL RESIZE HELPER ----------

local function bindPanelResize(panel, titleBar, scrollFrame, layout)
    local function resize()
        local contentH = layout.AbsoluteContentSize.Y + PAD * 2
        local visH = math.min(contentH, MAX_PANEL_CONTENT)
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, contentH)
        scrollFrame.Size = UDim2.new(1, 0, 0, visH)
        panel.Size = UDim2.new(0, PANEL_W, 0, TITLE_H + visH)
    end
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
    task.defer(resize)
    return resize
end

--==========================================================
--                     CREATE WINDOW
--==========================================================

function XiroLib:CreateWindow(config)
    config = config or {}
    local windowName = config.Name or "Xiro"
    toggleKeybind = config.ToggleUIKeybind or Enum.KeyCode.RightShift

    if config.ConfigurationSaving and config.ConfigurationSaving.Enabled then
        configEnabled = true
        configFolder = config.ConfigurationSaving.FolderName or "XiroConfig"
        configFile = config.ConfigurationSaving.FileName or "config"
    end

    -- ScreenGui
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "XiroUI"
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    pcall(function()
        if gethui then
            screenGui.Parent = gethui()
        elseif syn and syn.protect_gui then
            syn.protect_gui(screenGui)
            screenGui.Parent = game:GetService("CoreGui")
        else
            screenGui.Parent = game:GetService("CoreGui")
        end
    end)
    if not screenGui.Parent then
        screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end

    -- Panel container
    panelContainer = Instance.new("Frame")
    panelContainer.Name = "Panels"
    panelContainer.Size = UDim2.new(1, 0, 1, 0)
    panelContainer.BackgroundTransparency = 1
    panelContainer.Parent = screenGui

    -- Notification container
    notifContainer = Instance.new("Frame")
    notifContainer.Name = "Notifications"
    notifContainer.Size = UDim2.new(0, 280, 1, -20)
    notifContainer.Position = UDim2.new(1, -290, 0, 10)
    notifContainer.BackgroundTransparency = 1
    notifContainer.Parent = screenGui

    local notifLayout = Instance.new("UIListLayout")
    notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
    notifLayout.Padding = UDim.new(0, 6)
    notifLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    notifLayout.Parent = notifContainer

    -- Toggle UI keybind
    UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == toggleKeybind then
            uiVisible = not uiVisible
            if uiVisible then
                panelContainer.Visible = true
                unlockMouse()
            else
                panelContainer.Visible = false
                restoreMouse()
            end
        end
    end)

    -- Loading screen
    local loadScreen = Instance.new("Frame")
    loadScreen.Name = "Loading"
    loadScreen.Size = UDim2.new(1, 0, 1, 0)
    loadScreen.BackgroundColor3 = C.BG
    loadScreen.ZIndex = 999
    loadScreen.Parent = screenGui

    local loadTitle = Instance.new("TextLabel")
    loadTitle.Size = UDim2.new(1, 0, 0, 30)
    loadTitle.Position = UDim2.new(0, 0, 0.44, 0)
    loadTitle.BackgroundTransparency = 1
    loadTitle.Text = config.LoadingTitle or "Loading..."
    loadTitle.TextColor3 = C.Text
    loadTitle.Font = FONT_BOLD
    loadTitle.TextSize = 20
    loadTitle.ZIndex = 1000
    loadTitle.Parent = loadScreen

    local loadSub = Instance.new("TextLabel")
    loadSub.Size = UDim2.new(1, 0, 0, 20)
    loadSub.Position = UDim2.new(0, 0, 0.44, 34)
    loadSub.BackgroundTransparency = 1
    loadSub.Text = config.LoadingSubtitle or ""
    loadSub.TextColor3 = C.SubText
    loadSub.Font = FONT
    loadSub.TextSize = 14
    loadSub.ZIndex = 1000
    loadSub.Parent = loadScreen

    local accentLine = Instance.new("Frame")
    accentLine.Size = UDim2.new(0, 0, 0, 2)
    accentLine.Position = UDim2.new(0.5, 0, 0.44, 58)
    accentLine.AnchorPoint = Vector2.new(0.5, 0)
    accentLine.BackgroundColor3 = C.Accent
    accentLine.BorderSizePixel = 0
    accentLine.ZIndex = 1000
    accentLine.Parent = loadScreen

    panelContainer.Visible = false
    task.spawn(function()
        tw(accentLine, {Size = UDim2.new(0, 220, 0, 2)}, 1)
        task.wait(1.8)
        tw(loadScreen, {BackgroundTransparency = 1}, 0.4)
        tw(loadTitle, {TextTransparency = 1}, 0.4)
        tw(loadSub, {TextTransparency = 1}, 0.4)
        tw(accentLine, {BackgroundTransparency = 1}, 0.4)
        task.wait(0.4)
        loadScreen:Destroy()
        panelContainer.Visible = true
        unlockMouse()
    end)

    --======================================================
    --                    WINDOW OBJECT
    --======================================================
    local Window = {}

    function Window:CreateTab(tabName, tabIcon)
        panelCount = panelCount + 1
        local panelIndex = panelCount

        -- Panel frame
        local panel = Instance.new("Frame")
        panel.Name = "Panel_" .. tabName
        panel.Size = UDim2.new(0, PANEL_W, 0, TITLE_H + 200)
        panel.Position = UDim2.new(0, 15 + (panelIndex - 1) * (PANEL_W + 12), 0, 50)
        panel.BackgroundColor3 = C.Panel
        panel.BorderSizePixel = 0
        panel.ClipsDescendants = true
        panel.Parent = panelContainer
        addCorner(panel, CORNER_R)
        addStroke(panel, 1, C.Border)

        -- Title bar
        local titleBar = Instance.new("Frame")
        titleBar.Name = "TitleBar"
        titleBar.Size = UDim2.new(1, 0, 0, TITLE_H)
        titleBar.BackgroundColor3 = C.TitleBar
        titleBar.BorderSizePixel = 0
        titleBar.Parent = panel
        addCorner(titleBar, CORNER_R)

        -- Fix bottom corners of title bar (fill gap)
        local titleFill = Instance.new("Frame")
        titleFill.Size = UDim2.new(1, 0, 0, CORNER_R)
        titleFill.Position = UDim2.new(0, 0, 1, -CORNER_R)
        titleFill.BackgroundColor3 = C.TitleBar
        titleFill.BorderSizePixel = 0
        titleFill.Parent = titleBar

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, -40, 1, 0)
        titleLabel.Position = UDim2.new(0, 12, 0, 0)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = tabName
        titleLabel.TextColor3 = C.Text
        titleLabel.Font = FONT_BOLD
        titleLabel.TextSize = FSIZE_TITLE
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Parent = titleBar

        -- Minimize button
        local minimized = false
        local expandedSize = nil -- will be set by resize

        local minBtn = Instance.new("TextButton")
        minBtn.Size = UDim2.new(0, 28, 0, TITLE_H)
        minBtn.Position = UDim2.new(1, -28, 0, 0)
        minBtn.BackgroundTransparency = 1
        minBtn.Text = "▼"
        minBtn.TextColor3 = C.SubText
        minBtn.Font = FONT
        minBtn.TextSize = 10
        minBtn.Parent = titleBar

        -- Scroll frame (content area)
        local scrollFrame = Instance.new("ScrollingFrame")
        scrollFrame.Name = "Content"
        scrollFrame.Size = UDim2.new(1, 0, 0, 200)
        scrollFrame.Position = UDim2.new(0, 0, 0, TITLE_H)
        scrollFrame.BackgroundTransparency = 1
        scrollFrame.BorderSizePixel = 0
        scrollFrame.ScrollBarThickness = 3
        scrollFrame.ScrollBarImageColor3 = C.ScrollBar
        scrollFrame.ScrollBarImageTransparency = 0.3
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scrollFrame.Parent = panel

        local contentLayout = Instance.new("UIListLayout")
        contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
        contentLayout.Padding = UDim.new(0, GAP)
        contentLayout.Parent = scrollFrame

        local contentPadding = Instance.new("UIPadding")
        contentPadding.PaddingLeft = UDim.new(0, PAD)
        contentPadding.PaddingRight = UDim.new(0, PAD)
        contentPadding.PaddingTop = UDim.new(0, PAD)
        contentPadding.PaddingBottom = UDim.new(0, PAD)
        contentPadding.Parent = scrollFrame

        -- Auto-resize panel
        local resizeFn = bindPanelResize(panel, titleBar, scrollFrame, contentLayout)

        -- Minimize toggle
        minBtn.MouseButton1Click:Connect(function()
            minimized = not minimized
            if minimized then
                expandedSize = panel.Size
                minBtn.Text = "▶"
                scrollFrame.Visible = false
                tw(panel, {Size = UDim2.new(0, PANEL_W, 0, TITLE_H)}, 0.15)
            else
                minBtn.Text = "▼"
                scrollFrame.Visible = true
                if expandedSize then
                    tw(panel, {Size = expandedSize}, 0.15)
                end
                task.defer(resizeFn)
            end
        end)

        -- Make draggable
        makeDraggable(panel, titleBar)

        table.insert(panels, panel)

        --==================================================
        --                   TAB OBJECT
        --==================================================
        local Tab = {}
        local elemOrder = 0

        local function nextOrder()
            elemOrder = elemOrder + 1
            return elemOrder
        end

        ---- CREATE ACCORDION ----
        function Tab:CreateAccordion(accordionName)
            local isExpanded = false

            -- Container frame (auto-sizes based on content)
            local container = Instance.new("Frame")
            container.Name = "Accordion_" .. (accordionName or "")
            container.AutomaticSize = Enum.AutomaticSize.Y
            container.Size = UDim2.new(1, 0, 0, 0)
            container.BackgroundTransparency = 1
            container.LayoutOrder = nextOrder()
            container.ClipsDescendants = false
            container.Parent = scrollFrame

            local containerLayout = Instance.new("UIListLayout")
            containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
            containerLayout.Padding = UDim.new(0, GAP)
            containerLayout.Parent = container

            -- Header row
            local header = Instance.new("Frame")
            header.Name = "Header"
            header.Size = UDim2.new(1, 0, 0, ACCORDION_H)
            header.BackgroundColor3 = C.TitleBar
            header.BorderSizePixel = 0
            header.LayoutOrder = 0
            header.Parent = container
            addCorner(header, CORNER_SM)
            addStroke(header, 1, C.AccentDark)

            local arrow = Instance.new("TextLabel")
            arrow.Size = UDim2.new(0, 20, 1, 0)
            arrow.Position = UDim2.new(0, 6, 0, 0)
            arrow.BackgroundTransparency = 1
            arrow.Text = "▶"
            arrow.TextColor3 = C.Accent
            arrow.Font = FONT
            arrow.TextSize = 9
            arrow.Parent = header

            local headerLabel = Instance.new("TextLabel")
            headerLabel.Size = UDim2.new(1, -30, 1, 0)
            headerLabel.Position = UDim2.new(0, 24, 0, 0)
            headerLabel.BackgroundTransparency = 1
            headerLabel.Text = accordionName or "Section"
            headerLabel.TextColor3 = C.Accent
            headerLabel.Font = FONT_SEMI
            headerLabel.TextSize = FSIZE
            headerLabel.TextXAlignment = Enum.TextXAlignment.Left
            headerLabel.Parent = header

            -- Content frame (holds child elements, hidden by default)
            local content = Instance.new("Frame")
            content.Name = "Content"
            content.AutomaticSize = Enum.AutomaticSize.Y
            content.Size = UDim2.new(1, 0, 0, 0)
            content.BackgroundTransparency = 1
            content.Visible = false
            content.LayoutOrder = 1
            content.Parent = container

            local contentInnerLayout = Instance.new("UIListLayout")
            contentInnerLayout.SortOrder = Enum.SortOrder.LayoutOrder
            contentInnerLayout.Padding = UDim.new(0, GAP)
            contentInnerLayout.Parent = content

            -- Toggle expand/collapse
            local headerBtn = Instance.new("TextButton")
            headerBtn.Size = UDim2.new(1, 0, 1, 0)
            headerBtn.BackgroundTransparency = 1
            headerBtn.Text = ""
            headerBtn.Parent = header

            headerBtn.MouseButton1Click:Connect(function()
                isExpanded = not isExpanded
                content.Visible = isExpanded
                arrow.Text = isExpanded and "▼" or "▶"
                tw(header, {BackgroundColor3 = isExpanded and C.Elem or C.TitleBar}, 0.12)
            end)

            headerBtn.MouseEnter:Connect(function()
                tw(header, {BackgroundColor3 = C.ElemHover}, 0.1)
            end)
            headerBtn.MouseLeave:Connect(function()
                tw(header, {BackgroundColor3 = isExpanded and C.Elem or C.TitleBar}, 0.1)
            end)

            -- Accordion child API (mirrors Tab API, parents into content frame)
            local Acc = {}
            local accOrder = 0
            local function accNextOrder()
                accOrder = accOrder + 1
                return accOrder
            end

            function Acc:CreateToggle(cfg)
                cfg = cfg or {}
                local enabled = cfg.CurrentValue or false
                local flag = cfg.Flag

                local frame = Instance.new("Frame")
                frame.Name = "Toggle_" .. (cfg.Name or "")
                frame.Size = UDim2.new(1, 0, 0, ELEM_H)
                frame.BackgroundColor3 = C.Elem
                frame.BorderSizePixel = 0
                frame.LayoutOrder = accNextOrder()
                frame.Parent = content
                addCorner(frame, CORNER_SM)
                addStroke(frame, 1, C.Border)

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, -48, 1, 0)
                label.Position = UDim2.new(0, 10, 0, 0)
                label.BackgroundTransparency = 1
                label.Text = cfg.Name or "Toggle"
                label.TextColor3 = C.Text
                label.Font = FONT
                label.TextSize = FSIZE
                label.TextXAlignment = Enum.TextXAlignment.Left
                label.TextTruncate = Enum.TextTruncate.AtEnd
                label.Parent = frame

                local indicator = Instance.new("Frame")
                indicator.Size = UDim2.new(0, 36, 0, 18)
                indicator.Position = UDim2.new(1, -44, 0.5, -9)
                indicator.BackgroundColor3 = enabled and C.ToggleOn or C.ToggleOff
                indicator.BorderSizePixel = 0
                indicator.Parent = frame
                addCorner(indicator, 9)
                addStroke(indicator, 1, C.Border)

                local dot = Instance.new("Frame")
                dot.Size = UDim2.new(0, 14, 0, 14)
                dot.Position = enabled and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
                dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                dot.BorderSizePixel = 0
                dot.Parent = indicator
                addCorner(dot, 7)

                local function updateVisual()
                    tw(indicator, {BackgroundColor3 = enabled and C.ToggleOn or C.ToggleOff}, 0.15)
                    tw(dot, {Position = enabled and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)}, 0.15)
                end

                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(1, 0, 1, 0)
                btn.BackgroundTransparency = 1
                btn.Text = ""
                btn.Parent = frame

                btn.MouseButton1Click:Connect(function()
                    enabled = not enabled
                    updateVisual()
                    if flag then updateFlag(flag, enabled) end
                    if cfg.Callback then task.spawn(cfg.Callback, enabled) end
                end)

                btn.MouseEnter:Connect(function() tw(frame, {BackgroundColor3 = C.ElemHover}, 0.1) end)
                btn.MouseLeave:Connect(function() tw(frame, {BackgroundColor3 = C.Elem}, 0.1) end)

                local toggleObj = {}
                toggleObj.CurrentValue = enabled
                function toggleObj:Set(val)
                    if type(val) == "boolean" then
                        enabled = val
                        toggleObj.CurrentValue = val
                        updateVisual()
                        if flag then updateFlag(flag, enabled) end
                        if cfg.Callback then task.spawn(cfg.Callback, enabled) end
                    end
                end
                if flag then registerFlag(flag, enabled, function(val) toggleObj:Set(val) end) end
                return toggleObj
            end

            function Acc:CreateSlider(cfg)
                cfg = cfg or {}
                local mn = cfg.Range and cfg.Range[1] or 0
                local mx = cfg.Range and cfg.Range[2] or 100
                local inc = cfg.Increment or 1
                local suffix = cfg.Suffix or ""
                local value = cfg.CurrentValue or mn
                local flag = cfg.Flag
                value = snapVal(value, mn, mx, inc)

                local frame = Instance.new("Frame")
                frame.Name = "Slider_" .. (cfg.Name or "")
                frame.Size = UDim2.new(1, 0, 0, SLIDER_H)
                frame.BackgroundColor3 = C.Elem
                frame.BorderSizePixel = 0
                frame.LayoutOrder = accNextOrder()
                frame.Parent = content
                addCorner(frame, CORNER_SM)
                addStroke(frame, 1, C.Border)

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(0.65, -10, 0, 18)
                label.Position = UDim2.new(0, 10, 0, 4)
                label.BackgroundTransparency = 1
                label.Text = cfg.Name or "Slider"
                label.TextColor3 = C.Text
                label.Font = FONT
                label.TextSize = FSIZE
                label.TextXAlignment = Enum.TextXAlignment.Left
                label.TextTruncate = Enum.TextTruncate.AtEnd
                label.Parent = frame

                local valLabel = Instance.new("TextLabel")
                valLabel.Size = UDim2.new(0.35, -10, 0, 18)
                valLabel.Position = UDim2.new(0.65, 0, 0, 4)
                valLabel.BackgroundTransparency = 1
                valLabel.Text = tostring(value) .. suffix
                valLabel.TextColor3 = C.Accent
                valLabel.Font = FONT_SEMI
                valLabel.TextSize = FSIZE
                valLabel.TextXAlignment = Enum.TextXAlignment.Right
                valLabel.Parent = frame

                local barBG = Instance.new("Frame")
                barBG.Size = UDim2.new(1, -20, 0, 6)
                barBG.Position = UDim2.new(0, 10, 0, 28)
                barBG.BackgroundColor3 = C.SliderBG
                barBG.BorderSizePixel = 0
                barBG.Parent = frame
                addCorner(barBG, 3)

                local barFill = Instance.new("Frame")
                barFill.Size = UDim2.new((value - mn) / (mx - mn), 0, 1, 0)
                barFill.BackgroundColor3 = C.SliderFill
                barFill.BorderSizePixel = 0
                barFill.Parent = barBG
                addCorner(barFill, 3)

                local dragArea = Instance.new("TextButton")
                dragArea.Size = UDim2.new(1, 0, 0, 18)
                dragArea.Position = UDim2.new(0, 0, 0, 22)
                dragArea.BackgroundTransparency = 1
                dragArea.Text = ""
                dragArea.Parent = frame

                local function updateSlider(newVal)
                    value = snapVal(newVal, mn, mx, inc)
                    local pct = (value - mn) / math.max(mx - mn, 0.001)
                    barFill.Size = UDim2.new(pct, 0, 1, 0)
                    local display
                    if inc >= 1 then display = tostring(math.round(value))
                    else local decimals = math.max(0, math.ceil(-math.log10(inc))); display = string.format("%." .. decimals .. "f", value) end
                    valLabel.Text = display .. suffix
                    if flag then updateFlag(flag, value) end
                    if cfg.Callback then task.spawn(cfg.Callback, value) end
                end

                local sliding = false
                dragArea.MouseButton1Down:Connect(function() sliding = true end)
                UIS.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then sliding = false end end)
                UIS.InputChanged:Connect(function(input)
                    if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
                        local absPos = barBG.AbsolutePosition.X
                        local absSize = barBG.AbsoluteSize.X
                        local relX = math.clamp((input.Position.X - absPos) / absSize, 0, 1)
                        updateSlider(mn + relX * (mx - mn))
                    end
                end)
                dragArea.MouseButton1Click:Connect(function()
                    local mouse = UIS:GetMouseLocation()
                    local absPos = barBG.AbsolutePosition.X
                    local absSize = barBG.AbsoluteSize.X
                    local relX = math.clamp((mouse.X - absPos) / absSize, 0, 1)
                    updateSlider(mn + relX * (mx - mn))
                end)

                frame.MouseEnter:Connect(function() tw(frame, {BackgroundColor3 = C.ElemHover}, 0.1) end)
                frame.MouseLeave:Connect(function() tw(frame, {BackgroundColor3 = C.Elem}, 0.1) end)

                local sliderObj = {}
                sliderObj.CurrentValue = value
                function sliderObj:Set(val)
                    if type(val) == "number" then updateSlider(val); sliderObj.CurrentValue = value end
                end
                if flag then registerFlag(flag, value, function(val) sliderObj:Set(val) end) end
                return sliderObj
            end

            function Acc:CreateDropdown(cfg)
                cfg = cfg or {}
                local options = cfg.Options or {}
                local multi = cfg.MultipleOptions or false
                local current = cfg.CurrentOption or (options[1] and {options[1]} or {})
                local flag = cfg.Flag
                local isOpen = false

                local ddContainer = Instance.new("Frame")
                ddContainer.Name = "Dropdown_" .. (cfg.Name or "")
                ddContainer.AutomaticSize = Enum.AutomaticSize.Y
                ddContainer.Size = UDim2.new(1, 0, 0, 0)
                ddContainer.BackgroundTransparency = 1
                ddContainer.LayoutOrder = accNextOrder()
                ddContainer.ClipsDescendants = false
                ddContainer.Parent = content

                local mainRow = Instance.new("Frame")
                mainRow.Size = UDim2.new(1, 0, 0, DROPDOWN_H)
                mainRow.BackgroundColor3 = C.Elem
                mainRow.BorderSizePixel = 0
                mainRow.Parent = ddContainer
                addCorner(mainRow, CORNER_SM)
                addStroke(mainRow, 1, C.Border)

                local nameLabel = Instance.new("TextLabel")
                nameLabel.Size = UDim2.new(0.45, -8, 1, 0)
                nameLabel.Position = UDim2.new(0, 10, 0, 0)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Text = cfg.Name or "Dropdown"
                nameLabel.TextColor3 = C.Text
                nameLabel.Font = FONT
                nameLabel.TextSize = FSIZE
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
                nameLabel.Parent = mainRow

                local valueLabel = Instance.new("TextLabel")
                valueLabel.Size = UDim2.new(0.55, -28, 1, 0)
                valueLabel.Position = UDim2.new(0.45, 0, 0, 0)
                valueLabel.BackgroundTransparency = 1
                valueLabel.Text = table.concat(current, ", ")
                valueLabel.TextColor3 = C.Accent
                valueLabel.Font = FONT
                valueLabel.TextSize = FSIZE_SMALL
                valueLabel.TextXAlignment = Enum.TextXAlignment.Right
                valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
                valueLabel.Parent = mainRow

                local ddArrow = Instance.new("TextLabel")
                ddArrow.Size = UDim2.new(0, 20, 1, 0)
                ddArrow.Position = UDim2.new(1, -22, 0, 0)
                ddArrow.BackgroundTransparency = 1
                ddArrow.Text = "▼"
                ddArrow.TextColor3 = C.SubText
                ddArrow.Font = FONT
                ddArrow.TextSize = 9
                ddArrow.Parent = mainRow

                local optContainer = Instance.new("Frame")
                optContainer.Name = "Options"
                optContainer.AutomaticSize = Enum.AutomaticSize.Y
                optContainer.Size = UDim2.new(1, 0, 0, 0)
                optContainer.BackgroundTransparency = 1
                optContainer.Visible = false
                optContainer.Parent = ddContainer

                local optLayout = Instance.new("UIListLayout")
                optLayout.SortOrder = Enum.SortOrder.LayoutOrder
                optLayout.Padding = UDim.new(0, 1)
                optLayout.Parent = optContainer

                local optPad = Instance.new("UIPadding")
                optPad.PaddingTop = UDim.new(0, 2)
                optPad.Parent = optContainer

                local function buildOptions()
                    for _, child in optContainer:GetChildren() do
                        if child:IsA("TextButton") then child:Destroy() end
                    end
                    for i, opt in ipairs(options) do
                        local isSelected = table.find(current, opt) ~= nil
                        local optBtn = Instance.new("TextButton")
                        optBtn.Size = UDim2.new(1, 0, 0, 24)
                        optBtn.BackgroundColor3 = isSelected and C.AccentDark or C.Elem
                        optBtn.BorderSizePixel = 0
                        optBtn.Text = "  " .. opt
                        optBtn.TextColor3 = isSelected and C.Text or C.SubText
                        optBtn.Font = FONT
                        optBtn.TextSize = FSIZE_SMALL
                        optBtn.TextXAlignment = Enum.TextXAlignment.Left
                        optBtn.LayoutOrder = i
                        optBtn.Parent = optContainer
                        addCorner(optBtn, CORNER_SM)

                        optBtn.MouseEnter:Connect(function()
                            if not table.find(current, opt) then tw(optBtn, {BackgroundColor3 = C.ElemHover}, 0.08) end
                        end)
                        optBtn.MouseLeave:Connect(function()
                            tw(optBtn, {BackgroundColor3 = (table.find(current, opt) ~= nil) and C.AccentDark or C.Elem}, 0.08)
                        end)
                        optBtn.MouseButton1Click:Connect(function()
                            if multi then
                                local idx = table.find(current, opt)
                                if idx then table.remove(current, idx) else table.insert(current, opt) end
                            else
                                current = {opt}
                                isOpen = false
                                optContainer.Visible = false
                                ddArrow.Text = "▼"
                            end
                            valueLabel.Text = table.concat(current, ", ")
                            if flag then updateFlag(flag, current) end
                            if cfg.Callback then task.spawn(cfg.Callback, current) end
                            buildOptions()
                        end)
                    end
                end
                buildOptions()

                local mainBtn = Instance.new("TextButton")
                mainBtn.Size = UDim2.new(1, 0, 1, 0)
                mainBtn.BackgroundTransparency = 1
                mainBtn.Text = ""
                mainBtn.Parent = mainRow

                local function closeThis()
                    isOpen = false
                    optContainer.Visible = false
                    ddArrow.Text = "▼"
                end

                mainBtn.MouseButton1Click:Connect(function()
                    if isOpen then
                        closeThis()
                        openDropdown = nil
                    else
                        closeOpenDropdown()
                        isOpen = true
                        optContainer.Visible = true
                        ddArrow.Text = "▲"
                        openDropdown = closeThis
                        buildOptions()
                    end
                end)

                mainRow.MouseEnter:Connect(function() tw(mainRow, {BackgroundColor3 = C.ElemHover}, 0.1) end)
                mainRow.MouseLeave:Connect(function() tw(mainRow, {BackgroundColor3 = C.Elem}, 0.1) end)

                local dropObj = {}
                dropObj.CurrentOption = current
                function dropObj:Set(newOptions)
                    if type(newOptions) == "table" then
                        current = newOptions
                        dropObj.CurrentOption = current
                        valueLabel.Text = table.concat(current, ", ")
                        if flag then updateFlag(flag, current) end
                        if cfg.Callback then task.spawn(cfg.Callback, current) end
                        buildOptions()
                    end
                end
                function dropObj:Refresh(newOptionsList)
                    if type(newOptionsList) == "table" then options = newOptionsList; buildOptions() end
                end
                if flag then registerFlag(flag, current, function(val) dropObj:Set(val) end) end
                return dropObj
            end

            function Acc:CreateButton(cfg)
                cfg = cfg or {}
                local frame = Instance.new("Frame")
                frame.Name = "Button_" .. (cfg.Name or "")
                frame.Size = UDim2.new(1, 0, 0, ELEM_H)
                frame.BackgroundColor3 = C.Elem
                frame.BorderSizePixel = 0
                frame.LayoutOrder = accNextOrder()
                frame.Parent = content
                addCorner(frame, CORNER_SM)
                addStroke(frame, 1, C.Border)

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, -20, 1, 0)
                label.Position = UDim2.new(0, 10, 0, 0)
                label.BackgroundTransparency = 1
                label.Text = cfg.Name or "Button"
                label.TextColor3 = C.Accent
                label.Font = FONT_SEMI
                label.TextSize = FSIZE
                label.TextXAlignment = Enum.TextXAlignment.Left
                label.Parent = frame

                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(1, 0, 1, 0)
                btn.BackgroundTransparency = 1
                btn.Text = ""
                btn.Parent = frame

                btn.MouseButton1Click:Connect(function()
                    tw(frame, {BackgroundColor3 = C.Accent}, 0.08)
                    task.delay(0.15, function() tw(frame, {BackgroundColor3 = C.Elem}, 0.15) end)
                    if cfg.Callback then task.spawn(cfg.Callback) end
                end)
                btn.MouseEnter:Connect(function() tw(frame, {BackgroundColor3 = C.ElemHover}, 0.1) end)
                btn.MouseLeave:Connect(function() tw(frame, {BackgroundColor3 = C.Elem}, 0.1) end)
                return {}
            end

            function Acc:CreateLabel(text, icon, color, bold)
                if type(text) == "table" then
                    local cfg = text
                    text = cfg.Text or cfg.Name or ""
                    color = cfg.Color
                    bold = cfg.Bold
                end
                local frame = Instance.new("Frame")
                frame.Name = "Label"
                frame.Size = UDim2.new(1, 0, 0, 24)
                frame.BackgroundTransparency = 1
                frame.LayoutOrder = accNextOrder()
                frame.Parent = content

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, -12, 1, 0)
                label.Position = UDim2.new(0, 6, 0, 0)
                label.BackgroundTransparency = 1
                label.Text = text or ""
                label.TextColor3 = color or C.SubText
                label.Font = bold and FONT_BOLD or FONT
                label.TextSize = FSIZE_SMALL
                label.TextXAlignment = Enum.TextXAlignment.Left
                label.TextWrapped = true
                label.Parent = frame
                return {}
            end

            function Acc:CreateSection(sectionName)
                local frame = Instance.new("Frame")
                frame.Name = "Section"
                frame.Size = UDim2.new(1, 0, 0, SECTION_H)
                frame.BackgroundTransparency = 1
                frame.LayoutOrder = accNextOrder()
                frame.Parent = content

                local line = Instance.new("Frame")
                line.Size = UDim2.new(1, 0, 0, 1)
                line.Position = UDim2.new(0, 0, 0.5, 0)
                line.BackgroundColor3 = C.Border
                line.BorderSizePixel = 0
                line.Parent = frame

                local label = Instance.new("TextLabel")
                label.AutomaticSize = Enum.AutomaticSize.X
                label.Size = UDim2.new(0, 0, 1, 0)
                label.Position = UDim2.new(0, 4, 0, 0)
                label.BackgroundColor3 = C.Panel
                label.BackgroundTransparency = 0
                label.Text = "  " .. sectionName .. "  "
                label.TextColor3 = C.SectionText
                label.Font = FONT_SEMI
                label.TextSize = FSIZE_SMALL
                label.Parent = frame
            end

            return Acc
        end

        ---- CREATE SECTION ----
        function Tab:CreateSection(sectionName)
            local frame = Instance.new("Frame")
            frame.Name = "Section"
            frame.Size = UDim2.new(1, 0, 0, SECTION_H)
            frame.BackgroundTransparency = 1
            frame.LayoutOrder = nextOrder()
            frame.Parent = scrollFrame

            local line = Instance.new("Frame")
            line.Size = UDim2.new(1, 0, 0, 1)
            line.Position = UDim2.new(0, 0, 0.5, 0)
            line.BackgroundColor3 = C.Border
            line.BorderSizePixel = 0
            line.Parent = frame

            local label = Instance.new("TextLabel")
            label.AutomaticSize = Enum.AutomaticSize.X
            label.Size = UDim2.new(0, 0, 1, 0)
            label.Position = UDim2.new(0, 4, 0, 0)
            label.BackgroundColor3 = C.Panel
            label.BackgroundTransparency = 0
            label.Text = "  " .. sectionName .. "  "
            label.TextColor3 = C.SectionText
            label.Font = FONT_SEMI
            label.TextSize = FSIZE_SMALL
            label.Parent = frame
        end

        ---- CREATE TOGGLE ----
        function Tab:CreateToggle(cfg)
            cfg = cfg or {}
            local enabled = cfg.CurrentValue or false
            local flag = cfg.Flag

            local frame = Instance.new("Frame")
            frame.Name = "Toggle_" .. (cfg.Name or "")
            frame.Size = UDim2.new(1, 0, 0, ELEM_H)
            frame.BackgroundColor3 = C.Elem
            frame.BorderSizePixel = 0
            frame.LayoutOrder = nextOrder()
            frame.Parent = scrollFrame
            addCorner(frame, CORNER_SM)
            addStroke(frame, 1, C.Border)

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -48, 1, 0)
            label.Position = UDim2.new(0, 10, 0, 0)
            label.BackgroundTransparency = 1
            label.Text = cfg.Name or "Toggle"
            label.TextColor3 = C.Text
            label.Font = FONT
            label.TextSize = FSIZE
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextTruncate = Enum.TextTruncate.AtEnd
            label.Parent = frame

            -- Toggle indicator (pill shape)
            local indicator = Instance.new("Frame")
            indicator.Size = UDim2.new(0, 36, 0, 18)
            indicator.Position = UDim2.new(1, -44, 0.5, -9)
            indicator.BackgroundColor3 = enabled and C.ToggleOn or C.ToggleOff
            indicator.BorderSizePixel = 0
            indicator.Parent = frame
            addCorner(indicator, 9)
            addStroke(indicator, 1, C.Border)

            local dot = Instance.new("Frame")
            dot.Size = UDim2.new(0, 14, 0, 14)
            dot.Position = enabled and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
            dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            dot.BorderSizePixel = 0
            dot.Parent = indicator
            addCorner(dot, 7)

            local function updateVisual()
                tw(indicator, {BackgroundColor3 = enabled and C.ToggleOn or C.ToggleOff}, 0.15)
                tw(dot, {Position = enabled and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)}, 0.15)
            end

            -- Click area
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 1, 0)
            btn.BackgroundTransparency = 1
            btn.Text = ""
            btn.Parent = frame

            btn.MouseButton1Click:Connect(function()
                enabled = not enabled
                updateVisual()
                if flag then updateFlag(flag, enabled) end
                if cfg.Callback then task.spawn(cfg.Callback, enabled) end
            end)

            btn.MouseEnter:Connect(function()
                tw(frame, {BackgroundColor3 = C.ElemHover}, 0.1)
            end)
            btn.MouseLeave:Connect(function()
                tw(frame, {BackgroundColor3 = C.Elem}, 0.1)
            end)

            -- Toggle object
            local toggleObj = {}
            toggleObj.CurrentValue = enabled

            function toggleObj:Set(val)
                if type(val) == "boolean" then
                    enabled = val
                    toggleObj.CurrentValue = val
                    updateVisual()
                    if flag then updateFlag(flag, enabled) end
                    if cfg.Callback then task.spawn(cfg.Callback, enabled) end
                end
            end

            if flag then
                registerFlag(flag, enabled, function(val)
                    toggleObj:Set(val)
                end)
            end

            return toggleObj
        end

        ---- CREATE SLIDER ----
        function Tab:CreateSlider(cfg)
            cfg = cfg or {}
            local mn = cfg.Range and cfg.Range[1] or 0
            local mx = cfg.Range and cfg.Range[2] or 100
            local inc = cfg.Increment or 1
            local suffix = cfg.Suffix or ""
            local value = cfg.CurrentValue or mn
            local flag = cfg.Flag
            value = snapVal(value, mn, mx, inc)

            local frame = Instance.new("Frame")
            frame.Name = "Slider_" .. (cfg.Name or "")
            frame.Size = UDim2.new(1, 0, 0, SLIDER_H)
            frame.BackgroundColor3 = C.Elem
            frame.BorderSizePixel = 0
            frame.LayoutOrder = nextOrder()
            frame.Parent = scrollFrame
            addCorner(frame, CORNER_SM)
            addStroke(frame, 1, C.Border)

            -- Top row: name + value
            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(0.65, -10, 0, 18)
            label.Position = UDim2.new(0, 10, 0, 4)
            label.BackgroundTransparency = 1
            label.Text = cfg.Name or "Slider"
            label.TextColor3 = C.Text
            label.Font = FONT
            label.TextSize = FSIZE
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextTruncate = Enum.TextTruncate.AtEnd
            label.Parent = frame

            local valLabel = Instance.new("TextLabel")
            valLabel.Size = UDim2.new(0.35, -10, 0, 18)
            valLabel.Position = UDim2.new(0.65, 0, 0, 4)
            valLabel.BackgroundTransparency = 1
            valLabel.Text = tostring(value) .. suffix
            valLabel.TextColor3 = C.Accent
            valLabel.Font = FONT_SEMI
            valLabel.TextSize = FSIZE
            valLabel.TextXAlignment = Enum.TextXAlignment.Right
            valLabel.Parent = frame

            -- Slider bar
            local barBG = Instance.new("Frame")
            barBG.Size = UDim2.new(1, -20, 0, 6)
            barBG.Position = UDim2.new(0, 10, 0, 28)
            barBG.BackgroundColor3 = C.SliderBG
            barBG.BorderSizePixel = 0
            barBG.Parent = frame
            addCorner(barBG, 3)

            local barFill = Instance.new("Frame")
            barFill.Size = UDim2.new((value - mn) / (mx - mn), 0, 1, 0)
            barFill.BackgroundColor3 = C.SliderFill
            barFill.BorderSizePixel = 0
            barFill.Parent = barBG
            addCorner(barFill, 3)

            -- Drag handle (invisible, full bar area)
            local dragArea = Instance.new("TextButton")
            dragArea.Size = UDim2.new(1, 0, 0, 18)
            dragArea.Position = UDim2.new(0, 0, 0, 22)
            dragArea.BackgroundTransparency = 1
            dragArea.Text = ""
            dragArea.Parent = frame

            local function updateSlider(newVal)
                value = snapVal(newVal, mn, mx, inc)
                local pct = (value - mn) / math.max(mx - mn, 0.001)
                barFill.Size = UDim2.new(pct, 0, 1, 0)
                -- Format value display
                local display
                if inc >= 1 then
                    display = tostring(math.round(value))
                else
                    local decimals = math.max(0, math.ceil(-math.log10(inc)))
                    display = string.format("%." .. decimals .. "f", value)
                end
                valLabel.Text = display .. suffix
                if flag then updateFlag(flag, value) end
                if cfg.Callback then task.spawn(cfg.Callback, value) end
            end

            local sliding = false

            dragArea.MouseButton1Down:Connect(function()
                sliding = true
            end)

            UIS.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    sliding = false
                end
            end)

            UIS.InputChanged:Connect(function(input)
                if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
                    local absPos = barBG.AbsolutePosition.X
                    local absSize = barBG.AbsoluteSize.X
                    local relX = math.clamp((input.Position.X - absPos) / absSize, 0, 1)
                    local newVal = mn + relX * (mx - mn)
                    updateSlider(newVal)
                end
            end)

            -- Click to set
            dragArea.MouseButton1Click:Connect(function()
                local mouse = UIS:GetMouseLocation()
                local absPos = barBG.AbsolutePosition.X
                local absSize = barBG.AbsoluteSize.X
                local relX = math.clamp((mouse.X - absPos) / absSize, 0, 1)
                updateSlider(mn + relX * (mx - mn))
            end)

            frame.MouseEnter:Connect(function()
                tw(frame, {BackgroundColor3 = C.ElemHover}, 0.1)
            end)
            frame.MouseLeave:Connect(function()
                tw(frame, {BackgroundColor3 = C.Elem}, 0.1)
            end)

            local sliderObj = {}
            sliderObj.CurrentValue = value

            function sliderObj:Set(val)
                if type(val) == "number" then
                    updateSlider(val)
                    sliderObj.CurrentValue = value
                end
            end

            if flag then
                registerFlag(flag, value, function(val)
                    sliderObj:Set(val)
                end)
            end

            return sliderObj
        end

        ---- CREATE DROPDOWN ----
        function Tab:CreateDropdown(cfg)
            cfg = cfg or {}
            local options = cfg.Options or {}
            local multi = cfg.MultipleOptions or false
            local current = cfg.CurrentOption or (options[1] and {options[1]} or {})
            local flag = cfg.Flag
            local isOpen = false

            local container = Instance.new("Frame")
            container.Name = "Dropdown_" .. (cfg.Name or "")
            container.AutomaticSize = Enum.AutomaticSize.Y
            container.Size = UDim2.new(1, 0, 0, 0)
            container.BackgroundTransparency = 1
            container.LayoutOrder = nextOrder()
            container.ClipsDescendants = false
            container.Parent = scrollFrame

            -- Main row
            local mainRow = Instance.new("Frame")
            mainRow.Size = UDim2.new(1, 0, 0, DROPDOWN_H)
            mainRow.BackgroundColor3 = C.Elem
            mainRow.BorderSizePixel = 0
            mainRow.Parent = container
            addCorner(mainRow, CORNER_SM)
            addStroke(mainRow, 1, C.Border)

            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(0.45, -8, 1, 0)
            nameLabel.Position = UDim2.new(0, 10, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = cfg.Name or "Dropdown"
            nameLabel.TextColor3 = C.Text
            nameLabel.Font = FONT
            nameLabel.TextSize = FSIZE
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            nameLabel.Parent = mainRow

            local valueLabel = Instance.new("TextLabel")
            valueLabel.Size = UDim2.new(0.55, -28, 1, 0)
            valueLabel.Position = UDim2.new(0.45, 0, 0, 0)
            valueLabel.BackgroundTransparency = 1
            valueLabel.Text = table.concat(current, ", ")
            valueLabel.TextColor3 = C.Accent
            valueLabel.Font = FONT
            valueLabel.TextSize = FSIZE_SMALL
            valueLabel.TextXAlignment = Enum.TextXAlignment.Right
            valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
            valueLabel.Parent = mainRow

            local arrow = Instance.new("TextLabel")
            arrow.Size = UDim2.new(0, 20, 1, 0)
            arrow.Position = UDim2.new(1, -22, 0, 0)
            arrow.BackgroundTransparency = 1
            arrow.Text = "▼"
            arrow.TextColor3 = C.SubText
            arrow.Font = FONT
            arrow.TextSize = 9
            arrow.Parent = mainRow

            -- Options container
            local optContainer = Instance.new("Frame")
            optContainer.Name = "Options"
            optContainer.AutomaticSize = Enum.AutomaticSize.Y
            optContainer.Size = UDim2.new(1, 0, 0, 0)
            optContainer.BackgroundTransparency = 1
            optContainer.Visible = false
            optContainer.Parent = container

            local optLayout = Instance.new("UIListLayout")
            optLayout.SortOrder = Enum.SortOrder.LayoutOrder
            optLayout.Padding = UDim.new(0, 1)
            optLayout.Parent = optContainer

            local optPad = Instance.new("UIPadding")
            optPad.PaddingTop = UDim.new(0, 2)
            optPad.Parent = optContainer

            local function buildOptions()
                for _, child in optContainer:GetChildren() do
                    if child:IsA("TextButton") then child:Destroy() end
                end

                for i, opt in ipairs(options) do
                    local isSelected = table.find(current, opt) ~= nil

                    local optBtn = Instance.new("TextButton")
                    optBtn.Size = UDim2.new(1, 0, 0, 24)
                    optBtn.BackgroundColor3 = isSelected and C.AccentDark or C.Elem
                    optBtn.BorderSizePixel = 0
                    optBtn.Text = "  " .. opt
                    optBtn.TextColor3 = isSelected and C.Text or C.SubText
                    optBtn.Font = FONT
                    optBtn.TextSize = FSIZE_SMALL
                    optBtn.TextXAlignment = Enum.TextXAlignment.Left
                    optBtn.LayoutOrder = i
                    optBtn.Parent = optContainer
                    addCorner(optBtn, CORNER_SM)

                    optBtn.MouseEnter:Connect(function()
                        if not (table.find(current, opt)) then
                            tw(optBtn, {BackgroundColor3 = C.ElemHover}, 0.08)
                        end
                    end)
                    optBtn.MouseLeave:Connect(function()
                        local sel = table.find(current, opt) ~= nil
                        tw(optBtn, {BackgroundColor3 = sel and C.AccentDark or C.Elem}, 0.08)
                    end)

                    optBtn.MouseButton1Click:Connect(function()
                        if multi then
                            local idx = table.find(current, opt)
                            if idx then
                                table.remove(current, idx)
                            else
                                table.insert(current, opt)
                            end
                        else
                            current = {opt}
                            -- Close dropdown after single selection
                            isOpen = false
                            optContainer.Visible = false
                            arrow.Text = "▼"
                        end
                        valueLabel.Text = table.concat(current, ", ")
                        if flag then updateFlag(flag, current) end
                        if cfg.Callback then task.spawn(cfg.Callback, current) end
                        buildOptions()
                    end)
                end
            end

            buildOptions()

            -- Toggle open/close
            local mainBtn = Instance.new("TextButton")
            mainBtn.Size = UDim2.new(1, 0, 1, 0)
            mainBtn.BackgroundTransparency = 1
            mainBtn.Text = ""
            mainBtn.Parent = mainRow

            local function closeThis()
                isOpen = false
                optContainer.Visible = false
                arrow.Text = "▼"
            end

            mainBtn.MouseButton1Click:Connect(function()
                if isOpen then
                    closeThis()
                    openDropdown = nil
                else
                    closeOpenDropdown()
                    isOpen = true
                    optContainer.Visible = true
                    arrow.Text = "▲"
                    openDropdown = closeThis
                    buildOptions()
                end
            end)

            mainRow.MouseEnter:Connect(function()
                tw(mainRow, {BackgroundColor3 = C.ElemHover}, 0.1)
            end)
            mainRow.MouseLeave:Connect(function()
                tw(mainRow, {BackgroundColor3 = C.Elem}, 0.1)
            end)

            -- Dropdown object
            local dropObj = {}
            dropObj.CurrentOption = current

            function dropObj:Set(newOptions)
                if type(newOptions) == "table" then
                    current = newOptions
                    dropObj.CurrentOption = current
                    valueLabel.Text = table.concat(current, ", ")
                    if flag then updateFlag(flag, current) end
                    if cfg.Callback then task.spawn(cfg.Callback, current) end
                    buildOptions()
                end
            end

            function dropObj:Refresh(newOptionsList)
                if type(newOptionsList) == "table" then
                    options = newOptionsList
                    buildOptions()
                end
            end

            if flag then
                registerFlag(flag, current, function(val)
                    dropObj:Set(val)
                end)
            end

            return dropObj
        end

        ---- CREATE BUTTON ----
        function Tab:CreateButton(cfg)
            cfg = cfg or {}

            local frame = Instance.new("Frame")
            frame.Name = "Button_" .. (cfg.Name or "")
            frame.Size = UDim2.new(1, 0, 0, ELEM_H)
            frame.BackgroundColor3 = C.Elem
            frame.BorderSizePixel = 0
            frame.LayoutOrder = nextOrder()
            frame.Parent = scrollFrame
            addCorner(frame, CORNER_SM)
            addStroke(frame, 1, C.Border)

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -20, 1, 0)
            label.Position = UDim2.new(0, 10, 0, 0)
            label.BackgroundTransparency = 1
            label.Text = cfg.Name or "Button"
            label.TextColor3 = C.Accent
            label.Font = FONT_SEMI
            label.TextSize = FSIZE
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Parent = frame

            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 1, 0)
            btn.BackgroundTransparency = 1
            btn.Text = ""
            btn.Parent = frame

            btn.MouseButton1Click:Connect(function()
                -- Flash effect
                tw(frame, {BackgroundColor3 = C.Accent}, 0.08)
                task.delay(0.15, function()
                    tw(frame, {BackgroundColor3 = C.Elem}, 0.15)
                end)
                if cfg.Callback then task.spawn(cfg.Callback) end
            end)

            btn.MouseEnter:Connect(function()
                tw(frame, {BackgroundColor3 = C.ElemHover}, 0.1)
            end)
            btn.MouseLeave:Connect(function()
                tw(frame, {BackgroundColor3 = C.Elem}, 0.1)
            end)

            return {}
        end

        ---- CREATE LABEL ----
        function Tab:CreateLabel(text, icon, color, bold)
            -- Handle table arg
            if type(text) == "table" then
                local cfg = text
                text = cfg.Text or cfg.Name or ""
                color = cfg.Color
                bold = cfg.Bold
            end

            local frame = Instance.new("Frame")
            frame.Name = "Label"
            frame.Size = UDim2.new(1, 0, 0, 24)
            frame.BackgroundTransparency = 1
            frame.LayoutOrder = nextOrder()
            frame.Parent = scrollFrame

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -12, 1, 0)
            label.Position = UDim2.new(0, 6, 0, 0)
            label.BackgroundTransparency = 1
            label.Text = text or ""
            label.TextColor3 = color or C.SubText
            label.Font = bold and FONT_BOLD or FONT
            label.TextSize = FSIZE_SMALL
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextWrapped = true
            label.Parent = frame

            return {}
        end

        ---- CREATE KEYBIND ----
        function Tab:CreateKeybind(cfg)
            cfg = cfg or {}
            local currentKey = cfg.CurrentKeybind or "None"
            local flag = cfg.Flag
            local listening = false

            local frame = Instance.new("Frame")
            frame.Name = "Keybind_" .. (cfg.Name or "")
            frame.Size = UDim2.new(1, 0, 0, ELEM_H)
            frame.BackgroundColor3 = C.Elem
            frame.BorderSizePixel = 0
            frame.LayoutOrder = nextOrder()
            frame.Parent = scrollFrame
            addCorner(frame, CORNER_SM)

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -80, 1, 0)
            label.Position = UDim2.new(0, 10, 0, 0)
            label.BackgroundTransparency = 1
            label.Text = cfg.Name or "Keybind"
            label.TextColor3 = C.Text
            label.Font = FONT
            label.TextSize = FSIZE
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Parent = frame

            local keyLabel = Instance.new("TextLabel")
            keyLabel.Size = UDim2.new(0, 60, 0, 20)
            keyLabel.Position = UDim2.new(1, -70, 0.5, -10)
            keyLabel.BackgroundColor3 = C.SliderBG
            keyLabel.BorderSizePixel = 0
            keyLabel.Text = currentKey
            keyLabel.TextColor3 = C.Accent
            keyLabel.Font = FONT
            keyLabel.TextSize = FSIZE_SMALL
            keyLabel.Parent = frame
            addCorner(keyLabel, 3)

            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 1, 0)
            btn.BackgroundTransparency = 1
            btn.Text = ""
            btn.Parent = frame

            btn.MouseButton1Click:Connect(function()
                listening = true
                keyLabel.Text = "..."
                keyLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
            end)

            UIS.InputBegan:Connect(function(input, gpe)
                if not listening then return end
                if input.UserInputType == Enum.UserInputType.Keyboard then
                    listening = false
                    currentKey = input.KeyCode.Name
                    keyLabel.Text = currentKey
                    keyLabel.TextColor3 = C.Accent
                    if flag then updateFlag(flag, currentKey) end
                    if cfg.Callback then task.spawn(cfg.Callback, currentKey) end
                end
            end)

            frame.MouseEnter:Connect(function()
                tw(frame, {BackgroundColor3 = C.ElemHover}, 0.1)
            end)
            frame.MouseLeave:Connect(function()
                tw(frame, {BackgroundColor3 = C.Elem}, 0.1)
            end)

            local keybindObj = {}
            keybindObj.CurrentKeybind = currentKey

            function keybindObj:Set(key)
                currentKey = key
                keybindObj.CurrentKeybind = key
                keyLabel.Text = key
                if flag then updateFlag(flag, key) end
                if cfg.Callback then task.spawn(cfg.Callback, key) end
            end

            if flag then
                registerFlag(flag, currentKey, function(val)
                    keybindObj:Set(val)
                end)
            end

            return keybindObj
        end

        ---- CREATE INPUT ----
        function Tab:CreateInput(cfg)
            cfg = cfg or {}
            local flag = cfg.Flag

            local frame = Instance.new("Frame")
            frame.Name = "Input_" .. (cfg.Name or "")
            frame.Size = UDim2.new(1, 0, 0, ELEM_H + 6)
            frame.BackgroundColor3 = C.Elem
            frame.BorderSizePixel = 0
            frame.LayoutOrder = nextOrder()
            frame.Parent = scrollFrame
            addCorner(frame, CORNER_SM)

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(0.4, -8, 1, 0)
            label.Position = UDim2.new(0, 10, 0, 0)
            label.BackgroundTransparency = 1
            label.Text = cfg.Name or "Input"
            label.TextColor3 = C.Text
            label.Font = FONT
            label.TextSize = FSIZE
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Parent = frame

            local textBox = Instance.new("TextBox")
            textBox.Size = UDim2.new(0.55, -10, 0, 22)
            textBox.Position = UDim2.new(0.4, 0, 0.5, -11)
            textBox.BackgroundColor3 = C.SliderBG
            textBox.BorderSizePixel = 0
            textBox.Text = cfg.CurrentValue or ""
            textBox.PlaceholderText = cfg.PlaceholderText or "..."
            textBox.TextColor3 = C.Text
            textBox.PlaceholderColor3 = C.SubText
            textBox.Font = FONT
            textBox.TextSize = FSIZE_SMALL
            textBox.ClearTextOnFocus = false
            textBox.Parent = frame
            addCorner(textBox, 3)

            textBox.FocusLost:Connect(function(enter)
                if enter then
                    local val = textBox.Text
                    if flag then updateFlag(flag, val) end
                    if cfg.Callback then task.spawn(cfg.Callback, val) end
                end
            end)

            local inputObj = {}

            function inputObj:Set(val)
                textBox.Text = val or ""
                if flag then updateFlag(flag, val) end
            end

            if flag then
                registerFlag(flag, cfg.CurrentValue or "", function(val)
                    inputObj:Set(val)
                end)
            end

            return inputObj
        end

        ---- CREATE PARAGRAPH ----
        function Tab:CreateParagraph(cfg)
            cfg = cfg or {}
            local title = cfg.Title or cfg.Name or ""
            local content = cfg.Content or ""

            local frame = Instance.new("Frame")
            frame.Name = "Paragraph"
            frame.AutomaticSize = Enum.AutomaticSize.Y
            frame.Size = UDim2.new(1, 0, 0, 0)
            frame.BackgroundColor3 = C.Elem
            frame.BorderSizePixel = 0
            frame.LayoutOrder = nextOrder()
            frame.Parent = scrollFrame
            addCorner(frame, CORNER_SM)

            local padInner = Instance.new("UIPadding")
            padInner.PaddingLeft = UDim.new(0, 10)
            padInner.PaddingRight = UDim.new(0, 10)
            padInner.PaddingTop = UDim.new(0, 6)
            padInner.PaddingBottom = UDim.new(0, 6)
            padInner.Parent = frame

            local innerLayout = Instance.new("UIListLayout")
            innerLayout.SortOrder = Enum.SortOrder.LayoutOrder
            innerLayout.Padding = UDim.new(0, 3)
            innerLayout.Parent = frame

            if title ~= "" then
                local tLabel = Instance.new("TextLabel")
                tLabel.AutomaticSize = Enum.AutomaticSize.Y
                tLabel.Size = UDim2.new(1, 0, 0, 0)
                tLabel.BackgroundTransparency = 1
                tLabel.Text = title
                tLabel.TextColor3 = C.Accent
                tLabel.Font = FONT_SEMI
                tLabel.TextSize = FSIZE
                tLabel.TextXAlignment = Enum.TextXAlignment.Left
                tLabel.TextWrapped = true
                tLabel.LayoutOrder = 1
                tLabel.Parent = frame
            end

            local cLabel = Instance.new("TextLabel")
            cLabel.AutomaticSize = Enum.AutomaticSize.Y
            cLabel.Size = UDim2.new(1, 0, 0, 0)
            cLabel.BackgroundTransparency = 1
            cLabel.Text = content
            cLabel.TextColor3 = C.SubText
            cLabel.Font = FONT
            cLabel.TextSize = FSIZE_SMALL
            cLabel.TextXAlignment = Enum.TextXAlignment.Left
            cLabel.TextWrapped = true
            cLabel.LayoutOrder = 2
            cLabel.Parent = frame

            local paraObj = {}
            function paraObj:Set(cfg2)
                if cfg2.Title then
                    -- find title label
                    for _, c in frame:GetChildren() do
                        if c:IsA("TextLabel") and c.LayoutOrder == 1 then
                            c.Text = cfg2.Title
                        end
                    end
                end
                if cfg2.Content then cLabel.Text = cfg2.Content end
            end
            return paraObj
        end

        return Tab
    end

    --==================================================
    --                   NOTIFY
    --==================================================
    function Window:Notify(cfg) -- also accessible as XiroLib:Notify
        XiroLib:Notify(cfg)
    end

    --==================================================
    --               LOAD CONFIGURATION
    --==================================================
    function Window:LoadConfiguration()
        XiroLib:LoadConfiguration()
    end

    return Window
end

--==========================================================
--                      NOTIFY
--==========================================================

function XiroLib:Notify(cfg)
    cfg = cfg or {}
    if type(cfg) == "string" then cfg = {Title = cfg} end
    local title = cfg.Title or "Notification"
    local content = cfg.Content or ""
    local duration = cfg.Duration or 4

    if not notifContainer then return end

    local notif = Instance.new("Frame")
    notif.Size = UDim2.new(1, 0, 0, 0)
    notif.AutomaticSize = Enum.AutomaticSize.Y
    notif.BackgroundColor3 = C.Notif
    notif.BorderSizePixel = 0
    notif.BackgroundTransparency = 1
    notif.Parent = notifContainer
    addCorner(notif, CORNER_SM)
    addStroke(notif, 1, C.Border)

    local accentBar = Instance.new("Frame")
    accentBar.Size = UDim2.new(0, 3, 1, -8)
    accentBar.Position = UDim2.new(0, 4, 0, 4)
    accentBar.BackgroundColor3 = C.Accent
    accentBar.BorderSizePixel = 0
    accentBar.Parent = notif
    addCorner(accentBar, 2)

    local innerPad = Instance.new("UIPadding")
    innerPad.PaddingLeft = UDim.new(0, 14)
    innerPad.PaddingRight = UDim.new(0, 10)
    innerPad.PaddingTop = UDim.new(0, 8)
    innerPad.PaddingBottom = UDim.new(0, 8)
    innerPad.Parent = notif

    local innerLayout = Instance.new("UIListLayout")
    innerLayout.SortOrder = Enum.SortOrder.LayoutOrder
    innerLayout.Padding = UDim.new(0, 2)
    innerLayout.Parent = notif

    local tLabel = Instance.new("TextLabel")
    tLabel.AutomaticSize = Enum.AutomaticSize.Y
    tLabel.Size = UDim2.new(1, 0, 0, 0)
    tLabel.BackgroundTransparency = 1
    tLabel.Text = title
    tLabel.TextColor3 = C.Text
    tLabel.Font = FONT_BOLD
    tLabel.TextSize = FSIZE
    tLabel.TextXAlignment = Enum.TextXAlignment.Left
    tLabel.TextWrapped = true
    tLabel.LayoutOrder = 1
    tLabel.Parent = notif

    if content ~= "" then
        local cLabel = Instance.new("TextLabel")
        cLabel.AutomaticSize = Enum.AutomaticSize.Y
        cLabel.Size = UDim2.new(1, 0, 0, 0)
        cLabel.BackgroundTransparency = 1
        cLabel.Text = content
        cLabel.TextColor3 = C.SubText
        cLabel.Font = FONT
        cLabel.TextSize = FSIZE_SMALL
        cLabel.TextXAlignment = Enum.TextXAlignment.Left
        cLabel.TextWrapped = true
        cLabel.LayoutOrder = 2
        cLabel.Parent = notif
    end

    -- Animate in
    tw(notif, {BackgroundTransparency = 0}, 0.2)

    task.delay(duration, function()
        tw(notif, {BackgroundTransparency = 1}, 0.3)
        for _, c in notif:GetChildren() do
            if c:IsA("TextLabel") then tw(c, {TextTransparency = 1}, 0.3) end
            if c:IsA("Frame") then tw(c, {BackgroundTransparency = 1}, 0.3) end
            if c:IsA("UIStroke") then tw(c, {Transparency = 1}, 0.3) end
        end
        task.wait(0.35)
        notif:Destroy()
    end)
end

--==========================================================
--                  LOAD CONFIGURATION
--==========================================================

function XiroLib:LoadConfiguration()
    if not configEnabled then return end
    pcall(function()
        local path = configFolder .. "/" .. configFile .. ".json"
        if not isfile(path) then return end
        local raw = readfile(path)
        local data = HttpService:JSONDecode(raw)
        if type(data) ~= "table" then return end
        for flag, value in pairs(data) do
            if flagStore[flag] and flagStore[flag].set then
                task.spawn(flagStore[flag].set, value)
            end
        end
    end)
end

--==========================================================
--                     DESTROY
--==========================================================

function XiroLib:Destroy()
    if screenGui then screenGui:Destroy() end
    flagStore = {}
    panels = {}
    panelCount = 0
end

return XiroLib
