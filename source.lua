--VER=7
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

local THEMES = {
    Amethyst = {Accent=Color3.fromRGB(140,100,255), AccentDark=Color3.fromRGB(100,70,200), ToggleOn=Color3.fromRGB(140,100,255), SliderFill=Color3.fromRGB(140,100,255), SectionText=Color3.fromRGB(110,100,160)},
    Cyan     = {Accent=Color3.fromRGB(80,200,230),  AccentDark=Color3.fromRGB(50,150,180), ToggleOn=Color3.fromRGB(80,200,230),  SliderFill=Color3.fromRGB(80,200,230),  SectionText=Color3.fromRGB(100,160,180)},
    Crimson  = {Accent=Color3.fromRGB(255,80,100),  AccentDark=Color3.fromRGB(200,50,70),  ToggleOn=Color3.fromRGB(255,80,100),  SliderFill=Color3.fromRGB(255,80,100),  SectionText=Color3.fromRGB(180,100,110)},
    Emerald  = {Accent=Color3.fromRGB(80,220,130),  AccentDark=Color3.fromRGB(50,170,100), ToggleOn=Color3.fromRGB(80,220,130),  SliderFill=Color3.fromRGB(80,220,130),  SectionText=Color3.fromRGB(100,170,130)},
    Amber    = {Accent=Color3.fromRGB(255,180,80),  AccentDark=Color3.fromRGB(200,140,50), ToggleOn=Color3.fromRGB(255,180,80),  SliderFill=Color3.fromRGB(255,180,80),  SectionText=Color3.fromRGB(180,150,100)},
    Rose     = {Accent=Color3.fromRGB(255,130,180), AccentDark=Color3.fromRGB(200,90,140), ToggleOn=Color3.fromRGB(255,130,180), SliderFill=Color3.fromRGB(255,130,180), SectionText=Color3.fromRGB(180,130,160)},
}

local function applyTheme(name)
    local t = THEMES[name] or THEMES.Amethyst
    for k, v in pairs(t) do C[k] = v end
end

---------- LAYOUT CONSTANTS ----------
local PANEL_W      = 260
local TITLE_H      = 32
local ELEM_H       = 32
local SLIDER_H     = 46
local DROPDOWN_H   = 46
local SECTION_H    = 24
local ACCORDION_H  = 28
local PAD           = 8
local GAP           = 4
local CORNER_R      = 6
local CORNER_SM     = 4
local MAX_PANEL_CONTENT = 720
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
local accordionRegistry = setmetatable({}, {__mode = "k"}) -- scrollFrame -> list of accordion entries
local pulseStripes      = setmetatable({}, {__mode = "k"}) -- shared-phase pulse driver registry
local pulseDriverConn   = nil
local zCounter        = 10
local configEnabled   = false
local configFolder    = ""
local configFile      = ""
local uiVisible       = true
local toggleKeybind   = Enum.KeyCode.RightShift
local openDropdown    = nil -- currently open dropdown closer
local savedMouseBehavior = nil
local FADE_STAGGER    = 0.05 -- stagger delay between panel fade-ins
local FADE_STAGGER_OUT = 0.025 -- stagger delay for fade-out (稍快，收得干脆)

---------- PANEL STATE PERSISTENCE ----------
local _panelStateFile = "xiro_panel_state.json"
local _panelStates = {}
local _panelSavePending = false

local function _loadPanelStates()
    if not (isfile and readfile) then return end
    local ok, exists = pcall(isfile, _panelStateFile)
    if not ok or not exists then return end
    local rok, raw = pcall(readfile, _panelStateFile)
    if not rok or type(raw) ~= "string" then return end
    local dok, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if dok and type(data) == "table" then _panelStates = data end
end

local function _flushPanelStates()
    if not writefile then return end
    pcall(function() writefile(_panelStateFile, HttpService:JSONEncode(_panelStates)) end)
end

local function _savePanelState(name, x, y, minimized)
    if type(name) ~= "string" then return end
    _panelStates[name] = _panelStates[name] or {}
    if x ~= nil then _panelStates[name].x = x end
    if y ~= nil then _panelStates[name].y = y end
    if minimized ~= nil then _panelStates[name].min = minimized end
    if _panelSavePending then return end
    _panelSavePending = true
    task.delay(0.3, function()
        _panelSavePending = false
        _flushPanelStates()
    end)
end

_loadPanelStates()

---------- SHARED PULSE DRIVER ----------
-- All enabled-toggle stripes share one phase so they pulse in sync.
local PULSE_PERIOD = 0.9 -- seconds per half-cycle (matches old tween)
local PULSE_MIN = 0.0    -- transparency at peak brightness
local PULSE_MAX = 0.55   -- transparency at dim
local function _ensurePulseDriver()
    if pulseDriverConn then return end
    pulseDriverConn = RunService.Heartbeat:Connect(function()
        local t = tick()
        -- 0..1 sine wave with period 2*PULSE_PERIOD (one full reverse cycle)
        local phase = (math.sin(t * math.pi / PULSE_PERIOD) + 1) * 0.5
        local trans = PULSE_MIN + (PULSE_MAX - PULSE_MIN) * phase
        local any = false
        for stripe in pairs(pulseStripes) do
            if stripe.Parent then
                stripe.BackgroundTransparency = trans
                any = true
            else
                pulseStripes[stripe] = nil
            end
        end
        if not any then
            pulseDriverConn:Disconnect()
            pulseDriverConn = nil
        end
    end)
end
local function pulseAdd(stripe)
    pulseStripes[stripe] = true
    _ensurePulseDriver()
end
local function pulseRemove(stripe)
    pulseStripes[stripe] = nil
end

---------- INPUT DISPATCHER ----------
-- Consolidate global UIS listeners: handlers opt in only while active,
-- so idle UI costs 0 work per mouse-move event.

local moveHandlers = {}       -- [fn] = true, called on MouseMovement/Touch change
local endHandlers = {}        -- [fn] = true, called on MouseButton1/Touch end
local keybindListener = nil   -- single active keybind capture: fn(input) or nil

UIS.InputChanged:Connect(function(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
        for fn in pairs(moveHandlers) do fn(input) end
    end
end)

UIS.InputEnded:Connect(function(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
        for fn in pairs(endHandlers) do fn(input) end
    end
end)

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if keybindListener and input.UserInputType == Enum.UserInputType.Keyboard then
        keybindListener(input)
    end
end)

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

local function makeDraggable(frame, handle, onDragEnd)
    local dragStart, startPos
    local moveFn
    moveFn = function(input)
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragStart = input.Position
            startPos = frame.Position
            zCounter = zCounter + 1
            frame.ZIndex = zCounter
            moveHandlers[moveFn] = true

            -- Visual feedback: fade + accent stroke
            local stroke = frame:FindFirstChildOfClass("UIStroke")
            local origStrokeColor, origStrokeThick
            if stroke then
                origStrokeColor = stroke.Color
                origStrokeThick = stroke.Thickness
                tw(stroke, {Color = C.Accent, Thickness = 2}, 0.12)
            end
            if frame:IsA("CanvasGroup") then
                tw(frame, {GroupTransparency = 0.12}, 0.12)
            end

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    moveHandlers[moveFn] = nil
                    if stroke then
                        tw(stroke, {Color = origStrokeColor, Thickness = origStrokeThick}, 0.18)
                    end
                    if frame:IsA("CanvasGroup") then
                        tw(frame, {GroupTransparency = 0}, 0.18)
                    end
                    if onDragEnd then
                        pcall(onDragEnd, frame.Position.X.Offset, frame.Position.Y.Offset)
                    end
                end
            end)
        end
    end)
end

---------- CONFIG SYSTEM ----------

local saveDirty = false
local savePending = false
local function saveConfig()
    if not configEnabled then return end
    saveDirty = true
    if savePending then return end
    savePending = true
    task.delay(0.5, function()
        savePending = false
        if not saveDirty then return end
        saveDirty = false
        pcall(function()
            local data = {}
            for flag, info in pairs(flagStore) do
                data[flag] = info.value
            end
            local folder = configFolder
            if not isfolder(folder) then makefolder(folder) end
            writefile(folder .. "/" .. configFile .. ".json", HttpService:JSONEncode(data))
        end)
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
    local suppress = false
    local function resize()
        if suppress then return end
        local contentH = layout.AbsoluteContentSize.Y + PAD * 2
        local visH = math.min(contentH, MAX_PANEL_CONTENT)
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, contentH)
        scrollFrame.Size = UDim2.new(1, 0, 0, visH)
        panel.Size = UDim2.new(0, PANEL_W, 0, TITLE_H + visH)
    end
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
    task.defer(resize)
    local function setSuppress(v) suppress = v end
    return resize, setSuppress
end

--==========================================================
--                     CREATE WINDOW
--==========================================================

function XiroLib:CreateWindow(config)
    config = config or {}
    local windowName = config.Name or "Xiro"
    toggleKeybind = config.ToggleUIKeybind or Enum.KeyCode.RightShift
    applyTheme(config.Theme)

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
    pcall(function() screenGui:SetAttribute("LocalizationMatchIdentifier", "") end)
    pcall(function() screenGui.AutoLocalize = false end)
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

    -- 保证面板有UIScale，用于pop缩放动画
    local function ensurePanelScale(p)
        local s = p:FindFirstChild("_XiroAnim")
        if not s then
            s = Instance.new("UIScale")
            s.Name = "_XiroAnim"
            s.Scale = 1
            s.Parent = p
        end
        return s
    end

    local fadeTokens = setmetatable({}, {__mode = "k"}) -- panel -> token，弱引用

    local FADE_OUT_DUR  = 0.16
    local FADE_IN_DUR   = 0.24
    local FADE_IN_SCALE = 0.28
    local POP_START     = 0.9
    local POP_END_OUT   = 0.94

    local EASE_OUT_QUART = TweenInfo.new(FADE_IN_DUR, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local EASE_IN_QUART  = TweenInfo.new(FADE_OUT_DUR, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
    local EASE_BACK_OUT  = TweenInfo.new(FADE_IN_SCALE, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

    local function fadeOutPanel(p, delay)
        local scale = ensurePanelScale(p)
        local stroke = p:FindFirstChildOfClass("UIStroke")
        fadeTokens[p] = (fadeTokens[p] or 0) + 1
        local myToken = fadeTokens[p]
        task.delay(delay, function()
            if fadeTokens[p] ~= myToken then return end
            TS:Create(p, EASE_IN_QUART, {GroupTransparency = 1}):Play()
            TS:Create(scale, EASE_IN_QUART, {Scale = POP_END_OUT}):Play()
            if stroke then
                TS:Create(stroke, EASE_IN_QUART, {Transparency = 1}):Play()
            end
        end)
    end

    local function fadeInPanel(p, delay)
        local scale = ensurePanelScale(p)
        local stroke = p:FindFirstChildOfClass("UIStroke")
        scale.Scale = POP_START
        p.GroupTransparency = 1
        if stroke then stroke.Transparency = 1 end
        fadeTokens[p] = (fadeTokens[p] or 0) + 1
        local myToken = fadeTokens[p]
        task.delay(delay, function()
            if fadeTokens[p] ~= myToken then return end
            TS:Create(p, EASE_OUT_QUART, {GroupTransparency = 0}):Play()
            TS:Create(scale, EASE_BACK_OUT, {Scale = 1}):Play()
            if stroke then
                TS:Create(stroke, EASE_OUT_QUART, {Transparency = 0}):Play()
            end
        end)
    end

    -- Toggle UI keybind (防连按卡顿: token失效 + 动画锁)
    local toggleToken = 0
    local toggleBusy = false
    UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode ~= toggleKeybind then return end
        if toggleBusy then return end -- 动画进行中，忽略按键

        toggleBusy = true
        toggleToken = toggleToken + 1
        local myToken = toggleToken
        uiVisible = not uiVisible

        if uiVisible then
            panelContainer.Visible = true
            unlockMouse()
            for i, p in ipairs(panels) do
                fadeInPanel(p, (i - 1) * FADE_STAGGER)
            end
            task.delay(#panels * FADE_STAGGER + 0.3, function()
                if myToken == toggleToken then toggleBusy = false end
            end)
        else
            for i, p in ipairs(panels) do
                fadeOutPanel(p, (i - 1) * FADE_STAGGER_OUT)
            end
            task.delay(#panels * FADE_STAGGER_OUT + 0.2, function()
                if myToken == toggleToken and not uiVisible then
                    panelContainer.Visible = false
                    restoreMouse()
                end
                if myToken == toggleToken then toggleBusy = false end
            end)
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

        -- Panel (CanvasGroup enables single-property fade via GroupTransparency)
        local panel = Instance.new("CanvasGroup")
        panel.Name = "Panel_" .. tabName
        panel.Size = UDim2.new(0, PANEL_W, 0, TITLE_H + 200)
        local _saved = _panelStates[tabName]
        if _saved and _saved.x and _saved.y then
            panel.Position = UDim2.new(0, _saved.x, 0, _saved.y)
        else
            panel.Position = UDim2.new(0, 15 + (panelIndex - 1) * (PANEL_W + 12), 0, 50)
        end
        panel.BackgroundColor3 = C.Panel
        panel.BorderSizePixel = 0
        panel.ClipsDescendants = true
        panel.GroupTransparency = 0
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
        minBtn.Rotation = 0
        minBtn.Parent = titleBar

        minBtn.MouseEnter:Connect(function() tw(minBtn, {TextColor3 = C.Text}, 0.12) end)
        minBtn.MouseLeave:Connect(function() tw(minBtn, {TextColor3 = C.SubText}, 0.12) end)

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
        local resizeFn, setResizeSuppress = bindPanelResize(panel, titleBar, scrollFrame, contentLayout)

        -- Minimize toggle
        minBtn.MouseButton1Click:Connect(function()
            minimized = not minimized
            if minimized then
                expandedSize = panel.Size
                tw(minBtn, {Rotation = -90}, 0.18)
                setResizeSuppress(true)
                tw(panel, {Size = UDim2.new(0, PANEL_W, 0, TITLE_H)}, 0.18)
                task.delay(0.18, function()
                    if minimized then scrollFrame.Visible = false end
                end)
            else
                tw(minBtn, {Rotation = 0}, 0.18)
                scrollFrame.Visible = true
                local target = expandedSize or UDim2.new(0, PANEL_W, 0, TITLE_H + 200)
                setResizeSuppress(true)
                tw(panel, {Size = target}, 0.22)
                task.delay(0.24, function()
                    setResizeSuppress(false)
                    resizeFn()
                end)
            end
            _savePanelState(tabName, nil, nil, minimized)
        end)

        -- Restore minimized state
        if _saved and _saved.min == true then
            task.defer(function()
                minimized = true
                minBtn.Rotation = -90
                setResizeSuppress(true)
                panel.Size = UDim2.new(0, PANEL_W, 0, TITLE_H)
                scrollFrame.Visible = false
            end)
        end

        -- Make draggable (saves position on drag end)
        makeDraggable(panel, titleBar, function(x, y)
            _savePanelState(tabName, x, y, nil)
        end)

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
            local animating = false

            -- Container frame (clips content for slide animation)
            local container = Instance.new("Frame")
            container.Name = "Accordion_" .. (accordionName or "")
            container.Size = UDim2.new(1, 0, 0, ACCORDION_H)
            container.BackgroundTransparency = 1
            container.LayoutOrder = nextOrder()
            container.ClipsDescendants = true
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
            addStroke(header, 1, C.Border)

            local arrow = Instance.new("TextLabel")
            arrow.Size = UDim2.new(0, 20, 1, 0)
            arrow.Position = UDim2.new(0, 6, 0, 0)
            arrow.BackgroundTransparency = 1
            arrow.Text = "▶"
            arrow.TextColor3 = C.Accent
            arrow.Font = FONT
            arrow.TextSize = 9
            arrow.Rotation = 0
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

            -- Content frame (holds child elements, always present but clipped)
            local content = Instance.new("Frame")
            content.Name = "Content"
            content.AutomaticSize = Enum.AutomaticSize.Y
            content.Size = UDim2.new(1, 0, 0, 0)
            content.BackgroundTransparency = 1
            content.Visible = true
            content.LayoutOrder = 1
            content.Parent = container

            local contentInnerLayout = Instance.new("UIListLayout")
            contentInnerLayout.SortOrder = Enum.SortOrder.LayoutOrder
            contentInnerLayout.Padding = UDim.new(0, GAP)
            contentInnerLayout.Parent = content

            -- Toggle expand/collapse with slide animation
            local headerBtn = Instance.new("TextButton")
            headerBtn.Size = UDim2.new(1, 0, 1, 0)
            headerBtn.BackgroundTransparency = 1
            headerBtn.Text = ""
            headerBtn.Parent = header

            local function doExpand()
                if isExpanded or animating then return end
                isExpanded = true
                animating = true
                tw(arrow, {Rotation = 90}, 0.18)
                tw(header, {BackgroundColor3 = C.Elem}, 0.12)
                local contentH = contentInnerLayout.AbsoluteContentSize.Y
                local targetH = ACCORDION_H + GAP + contentH
                local t = tw(container, {Size = UDim2.new(1, 0, 0, targetH)}, 0.2)
                for _, d in content:GetDescendants() do
                    if d:IsA("TextLabel") or d:IsA("TextButton") then
                        d.TextTransparency = 1
                        tw(d, {TextTransparency = 0}, 0.25)
                    end
                end
                t.Completed:Connect(function()
                    animating = false
                    container.ClipsDescendants = false
                    container.Size = UDim2.new(1, 0, 0, ACCORDION_H + GAP + contentInnerLayout.AbsoluteContentSize.Y)
                    -- Auto-scroll: bring this accordion's top into view
                    task.wait()
                    local viewTopY = scrollFrame.AbsolutePosition.Y
                    local viewH = scrollFrame.AbsoluteSize.Y
                    local containerTopY = container.AbsolutePosition.Y
                    local containerH = container.AbsoluteSize.Y
                    local relTop = containerTopY - viewTopY
                    local maxCanvas = math.max(0, scrollFrame.AbsoluteCanvasSize.Y - viewH)
                    local newY = scrollFrame.CanvasPosition.Y
                    if relTop < 0 or containerH > viewH then
                        newY = scrollFrame.CanvasPosition.Y + relTop - PAD
                    elseif relTop + containerH > viewH then
                        newY = scrollFrame.CanvasPosition.Y + (relTop + containerH - viewH) + PAD
                    end
                    newY = math.clamp(newY, 0, maxCanvas)
                    if math.abs(newY - scrollFrame.CanvasPosition.Y) > 1 then
                        tw(scrollFrame, {CanvasPosition = Vector2.new(0, newY)}, 0.18)
                    end
                end)
            end

            local function doCollapse()
                if not isExpanded or animating then return end
                isExpanded = false
                animating = true
                tw(arrow, {Rotation = 0}, 0.18)
                tw(header, {BackgroundColor3 = C.TitleBar}, 0.12)
                container.ClipsDescendants = true
                local t = tw(container, {Size = UDim2.new(1, 0, 0, ACCORDION_H)}, 0.2)
                t.Completed:Connect(function() animating = false end)
            end

            -- Register this accordion so siblings can be closed on overflow
            local entry = {
                container = container,
                isExpanded = function() return isExpanded end,
                collapse = doCollapse,
                expandedHeight = function()
                    return ACCORDION_H + GAP + contentInnerLayout.AbsoluteContentSize.Y
                end,
            }
            local registryList = accordionRegistry[scrollFrame]
            if not registryList then
                registryList = {}
                accordionRegistry[scrollFrame] = registryList
            end
            table.insert(registryList, entry)

            headerBtn.MouseButton1Click:Connect(function()
                if animating then return end
                if isExpanded then
                    doCollapse()
                    return
                end
                -- About to expand: only close siblings if total would exceed MAX_PANEL_CONTENT
                -- (panel auto-resizes to content up to that cap, beyond which a scrollbar appears)
                local sfLayout = scrollFrame:FindFirstChildOfClass("UIListLayout")
                local maxH = MAX_PANEL_CONTENT
                local currentContentH = sfLayout and sfLayout.AbsoluteContentSize.Y or 0
                local thisExpandedH = ACCORDION_H + GAP + contentInnerLayout.AbsoluteContentSize.Y
                local predicted = currentContentH - ACCORDION_H + thisExpandedH
                if predicted > maxH then
                    local list = accordionRegistry[scrollFrame] or {}
                    for _, e in list do
                        if predicted <= maxH then break end
                        if e.container ~= container and e.isExpanded() then
                            local saved = e.expandedHeight()
                            e.collapse()
                            predicted = predicted - (saved - ACCORDION_H)
                        end
                    end
                end
                doExpand()
            end)

            -- Live-resize accordion when inner content (e.g. dropdown options) grows/shrinks
            contentInnerLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                if isExpanded and not animating then
                    container.Size = UDim2.new(1, 0, 0, ACCORDION_H + GAP + contentInnerLayout.AbsoluteContentSize.Y)
                end
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

                local stripe = Instance.new("Frame")
                stripe.Size = UDim2.new(0, 3, 1, -10)
                stripe.Position = UDim2.new(0, 0, 0, 5)
                stripe.BackgroundColor3 = C.Accent
                stripe.BackgroundTransparency = enabled and 0 or 1
                stripe.BorderSizePixel = 0
                stripe.Parent = frame
                addCorner(stripe, 2)

                local function startPulse() pulseAdd(stripe) end
                local function stopPulse() pulseRemove(stripe) end
                if enabled then startPulse() end

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, -52, 1, 0)
                label.Position = UDim2.new(0, 14, 0, 0)
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
                    if enabled then
                        startPulse()
                    else
                        stopPulse()
                        tw(stripe, {BackgroundTransparency = 1}, 0.18)
                    end
                end

                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(1, 0, 1, 0)
                btn.BackgroundTransparency = 1
                btn.Text = ""
                btn.Parent = frame

                local DOT_BASE_SIZE = UDim2.new(0, 14, 0, 14)
                local DOT_POP_SIZE = UDim2.new(0, 18, 0, 18)
                local dotToken = 0
                btn.MouseButton1Click:Connect(function()
                    enabled = not enabled
                    updateVisual()
                    dotToken = dotToken + 1
                    local myToken = dotToken
                    tw(dot, {Size = DOT_POP_SIZE, Position = enabled and UDim2.new(1, -18, 0.5, -9) or UDim2.new(0, 0, 0.5, -9)}, 0.08)
                    task.delay(0.12, function()
                        if myToken == dotToken then
                            tw(dot, {Size = DOT_BASE_SIZE, Position = enabled and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)}, 0.12)
                        end
                    end)
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
                dragArea.Size = UDim2.new(1, 0, 1, 0)
                dragArea.Position = UDim2.new(0, 0, 0, 0)
                dragArea.BackgroundTransparency = 1
                dragArea.Text = ""
                dragArea.Parent = frame

                local function formatDisplay(v)
                    if inc >= 1 then return tostring(math.round(v))
                    else local decimals = math.max(0, math.ceil(-math.log10(inc))); return string.format("%." .. decimals .. "f", v) end
                end

                local function commitValue(snapped)
                    value = snapped
                    valLabel.Text = formatDisplay(value) .. suffix
                    if flag then updateFlag(flag, value) end
                    if cfg.Callback then task.spawn(cfg.Callback, value) end
                end

                local _slTw = nil
                local function slideTo(pct, dur)
                    if _slTw then pcall(function() _slTw:Cancel() end) end
                    _slTw = tw(barFill, {Size = UDim2.new(pct, 0, 1, 0)}, dur)
                end

                local function updateSlider(newVal)
                    value = snapVal(newVal, mn, mx, inc)
                    local pct = (value - mn) / math.max(mx - mn, 0.001)
                    slideTo(pct, 0.15)
                    commitValue(value)
                end

                local sliding = false
                local slMove, slEnd
                slMove = function(input)
                    local absPos = barBG.AbsolutePosition.X
                    local absSize = barBG.AbsoluteSize.X
                    local relX = math.clamp((input.Position.X - absPos) / absSize, 0, 1)
                    local rawVal = math.clamp(mn + relX * (mx - mn), mn, mx)
                    local pct = (rawVal - mn) / math.max(mx - mn, 0.001)
                    slideTo(pct, 0.12)
                    local display = snapVal(rawVal, mn, mx, inc)
                    valLabel.Text = formatDisplay(display) .. suffix
                    value = rawVal
                end
                slEnd = function()
                    if not sliding then return end
                    sliding = false
                    moveHandlers[slMove] = nil
                    endHandlers[slEnd] = nil
                    local snapped = snapVal(value, mn, mx, inc)
                    local pct = (snapped - mn) / math.max(mx - mn, 0.001)
                    slideTo(pct, 0.2)
                    commitValue(snapped)
                end
                dragArea.MouseButton1Down:Connect(function()
                    sliding = true
                    moveHandlers[slMove] = true
                    endHandlers[slEnd] = true
                end)
                dragArea.MouseButton1Click:Connect(function()
                    local mouse = UIS:GetMouseLocation()
                    local absPos = barBG.AbsolutePosition.X
                    local absSize = barBG.AbsoluteSize.X
                    local relX = math.clamp((mouse.X - absPos) / absSize, 0, 1)
                    local rawVal = mn + relX * (mx - mn)
                    local snapped = snapVal(rawVal, mn, mx, inc)
                    local pct = (snapped - mn) / math.max(mx - mn, 0.001)
                    slideTo(pct, 0.2)
                    commitValue(snapped)
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

                local ddLayout = Instance.new("UIListLayout")
                ddLayout.SortOrder = Enum.SortOrder.LayoutOrder
                ddLayout.Padding = UDim.new(0, 0)
                ddLayout.Parent = ddContainer

                local mainRow = Instance.new("Frame")
                mainRow.Size = UDim2.new(1, 0, 0, DROPDOWN_H)
                mainRow.BackgroundColor3 = C.Elem
                mainRow.BorderSizePixel = 0
                mainRow.LayoutOrder = 0
                mainRow.Parent = ddContainer
                addCorner(mainRow, CORNER_SM)
                addStroke(mainRow, 1, C.Border)

                local nameLabel = Instance.new("TextLabel")
                nameLabel.Size = UDim2.new(1, -32, 0, 18)
                nameLabel.Position = UDim2.new(0, 10, 0, 4)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Text = cfg.Name or "Dropdown"
                nameLabel.TextColor3 = C.SubText
                nameLabel.Font = FONT
                nameLabel.TextSize = FSIZE_SMALL
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
                nameLabel.Parent = mainRow

                local valueLabel = Instance.new("TextLabel")
                valueLabel.Size = UDim2.new(1, -32, 0, 18)
                valueLabel.Position = UDim2.new(0, 10, 0, 22)
                valueLabel.BackgroundTransparency = 1
                valueLabel.Text = table.concat(current, ", ")
                valueLabel.TextColor3 = C.Accent
                valueLabel.Font = FONT_SEMI
                valueLabel.TextSize = FSIZE
                valueLabel.TextXAlignment = Enum.TextXAlignment.Left
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
                ddArrow.Rotation = 0
                ddArrow.Parent = mainRow

                local optWrap = Instance.new("Frame")
                optWrap.Name = "OptionsWrap"
                optWrap.Size = UDim2.new(1, 0, 0, 0)
                optWrap.BackgroundTransparency = 1
                optWrap.BorderSizePixel = 0
                optWrap.ClipsDescendants = true
                optWrap.Visible = false
                optWrap.LayoutOrder = 1
                optWrap.Parent = ddContainer

                local optContainer = Instance.new("Frame")
                optContainer.Name = "Options"
                optContainer.Size = UDim2.new(1, 0, 0, 0)
                optContainer.BackgroundTransparency = 1
                optContainer.Parent = optWrap

                local optLayout = Instance.new("UIListLayout")
                optLayout.SortOrder = Enum.SortOrder.LayoutOrder
                optLayout.Padding = UDim.new(0, 1)
                optLayout.Parent = optContainer

                local optPad = Instance.new("UIPadding")
                optPad.PaddingTop = UDim.new(0, 2)
                optPad.Parent = optContainer

                local function getFullH()
                    local n = #options
                    return n * 24 + math.max(0, n - 1) + 2
                end
                local function refreshContainerH()
                    optContainer.Size = UDim2.new(1, 0, 0, getFullH())
                end

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
                            end
                            valueLabel.Text = table.concat(current, ", ")
                            if flag then updateFlag(flag, current) end
                            if cfg.Callback then task.spawn(cfg.Callback, current) end
                            buildOptions()
                            if not multi then
                                isOpen = false
                                tw(ddArrow, {Rotation = 0}, 0.16)
                                TS:Create(optWrap, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Size = UDim2.new(1, 0, 0, 0)}):Play()
                                task.delay(0.16, function()
                                    if not isOpen then optWrap.Visible = false end
                                end)
                                openDropdown = nil
                            else
                                TS:Create(optWrap, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, getFullH())}):Play()
                            end
                        end)
                    end
                    refreshContainerH()
                end
                buildOptions()

                local mainBtn = Instance.new("TextButton")
                mainBtn.Size = UDim2.new(1, 0, 1, 0)
                mainBtn.BackgroundTransparency = 1
                mainBtn.Text = ""
                mainBtn.Parent = mainRow

                local EXPAND_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
                local COLLAPSE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

                local function closeThis()
                    isOpen = false
                    tw(ddArrow, {Rotation = 0}, 0.16)
                    TS:Create(optWrap, COLLAPSE_INFO, {Size = UDim2.new(1, 0, 0, 0)}):Play()
                    task.delay(0.16, function()
                        if not isOpen then optWrap.Visible = false end
                    end)
                end

                mainBtn.MouseButton1Click:Connect(function()
                    if isOpen then
                        closeThis()
                        openDropdown = nil
                    else
                        closeOpenDropdown()
                        isOpen = true
                        optWrap.Size = UDim2.new(1, 0, 0, 0)
                        optWrap.Visible = true
                        refreshContainerH()
                        tw(ddArrow, {Rotation = 180}, 0.22)
                        TS:Create(optWrap, EXPAND_INFO, {Size = UDim2.new(1, 0, 0, getFullH())}):Play()
                        openDropdown = closeThis
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
                local labelObj = {}
                function labelObj:Set(newText)
                    label.Text = newText or ""
                end
                return labelObj
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

            function Acc:CreateKeybind(cfg)
                cfg = cfg or {}
                local currentKey = cfg.CurrentKeybind or "None"
                local flag = cfg.Flag
                local listening = false

                local frame = Instance.new("Frame")
                frame.Name = "Keybind_" .. (cfg.Name or "")
                frame.Size = UDim2.new(1, 0, 0, ELEM_H)
                frame.BackgroundColor3 = C.Elem
                frame.BorderSizePixel = 0
                frame.LayoutOrder = accNextOrder()
                frame.Parent = content
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

                local captureFn
                captureFn = function(input)
                    listening = false
                    keybindListener = nil
                    currentKey = input.KeyCode.Name
                    keyLabel.Text = currentKey
                    tw(keyLabel, {TextColor3 = C.Accent, BackgroundColor3 = C.SliderBG}, 0.2)
                    if flag then updateFlag(flag, currentKey) end
                    if cfg.Callback then task.spawn(cfg.Callback, currentKey) end
                end

                btn.MouseButton1Click:Connect(function()
                    listening = true
                    keyLabel.Text = "..."
                    tw(keyLabel, {TextColor3 = Color3.fromRGB(255, 200, 100), BackgroundColor3 = C.AccentDark}, 0.15)
                    keybindListener = captureFn
                end)

                frame.MouseEnter:Connect(function() tw(frame, {BackgroundColor3 = C.ElemHover}, 0.1) end)
                frame.MouseLeave:Connect(function() tw(frame, {BackgroundColor3 = C.Elem}, 0.1) end)

                local kb = {}
                kb.CurrentKeybind = currentKey
                function kb:Set(key)
                    currentKey = key
                    kb.CurrentKeybind = key
                    keyLabel.Text = key
                    if flag then updateFlag(flag, key) end
                    if cfg.Callback then task.spawn(cfg.Callback, key) end
                end
                if flag then registerFlag(flag, currentKey, function(val) kb:Set(val) end) end
                return kb
            end

            function Acc:CreateInput(cfg)
                cfg = cfg or {}
                local flag = cfg.Flag

                local frame = Instance.new("Frame")
                frame.Name = "Input_" .. (cfg.Name or "")
                frame.Size = UDim2.new(1, 0, 0, ELEM_H + 6)
                frame.BackgroundColor3 = C.Elem
                frame.BorderSizePixel = 0
                frame.LayoutOrder = accNextOrder()
                frame.Parent = content
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
                local boxStroke = addStroke(textBox, 1, C.Border)

                textBox.Focused:Connect(function() tw(boxStroke, {Color = C.Accent, Thickness = 1.5}, 0.15) end)
                textBox.FocusLost:Connect(function(enter)
                    tw(boxStroke, {Color = C.Border, Thickness = 1}, 0.15)
                    if enter then
                        local val = textBox.Text
                        if flag then updateFlag(flag, val) end
                        if cfg.Callback then task.spawn(cfg.Callback, val) end
                    end
                end)

                local inp = {}
                function inp:Set(val)
                    textBox.Text = val or ""
                    if flag then updateFlag(flag, val) end
                end
                if flag then registerFlag(flag, cfg.CurrentValue or "", function(val) inp:Set(val) end) end
                return inp
            end

            function Acc:CreateParagraph(cfg)
                cfg = cfg or {}
                local title = cfg.Title or cfg.Name or ""
                local bodyText = cfg.Content or ""

                local frame = Instance.new("Frame")
                frame.Name = "Paragraph"
                frame.AutomaticSize = Enum.AutomaticSize.Y
                frame.Size = UDim2.new(1, 0, 0, 0)
                frame.BackgroundColor3 = C.Elem
                frame.BorderSizePixel = 0
                frame.LayoutOrder = accNextOrder()
                frame.Parent = content
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

                local tLabel
                if title ~= "" then
                    tLabel = Instance.new("TextLabel")
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
                cLabel.Text = bodyText
                cLabel.TextColor3 = C.SubText
                cLabel.Font = FONT
                cLabel.TextSize = FSIZE_SMALL
                cLabel.TextXAlignment = Enum.TextXAlignment.Left
                cLabel.TextWrapped = true
                cLabel.LayoutOrder = 2
                cLabel.Parent = frame

                local p = {}
                function p:Set(cfg2)
                    if cfg2.Title and tLabel then tLabel.Text = cfg2.Title end
                    if cfg2.Content then cLabel.Text = cfg2.Content end
                end
                return p
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

            -- 防连点: 用token+固定基准尺寸，避免叠加动画把dot卡在"变大"状态
            local DOT_BASE_SIZE = UDim2.new(0, 14, 0, 14)
            local DOT_POP_SIZE = UDim2.new(0, 18, 0, 18)
            local dotToken = 0
            btn.MouseButton1Click:Connect(function()
                enabled = not enabled
                updateVisual()
                dotToken = dotToken + 1
                local myToken = dotToken
                tw(dot, {Size = DOT_POP_SIZE, Position = enabled and UDim2.new(1, -18, 0.5, -9) or UDim2.new(0, 0, 0.5, -9)}, 0.08)
                task.delay(0.12, function()
                    if myToken == dotToken then
                        tw(dot, {Size = DOT_BASE_SIZE, Position = enabled and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)}, 0.12)
                    end
                end)
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
            dragArea.Size = UDim2.new(1, 0, 1, 0)
            dragArea.Position = UDim2.new(0, 0, 0, 0)
            dragArea.BackgroundTransparency = 1
            dragArea.Text = ""
            dragArea.Parent = frame

            local function formatDisplay(v)
                if inc >= 1 then return tostring(math.round(v))
                else local decimals = math.max(0, math.ceil(-math.log10(inc))); return string.format("%." .. decimals .. "f", v) end
            end

            local function commitValue(snapped)
                value = snapped
                valLabel.Text = formatDisplay(value) .. suffix
                if flag then updateFlag(flag, value) end
                if cfg.Callback then task.spawn(cfg.Callback, value) end
            end

            local _slTw = nil
            local function slideTo(pct, dur)
                if _slTw then pcall(function() _slTw:Cancel() end) end
                _slTw = tw(barFill, {Size = UDim2.new(pct, 0, 1, 0)}, dur)
            end

            local function updateSlider(newVal)
                value = snapVal(newVal, mn, mx, inc)
                local pct = (value - mn) / math.max(mx - mn, 0.001)
                slideTo(pct, 0.15)
                commitValue(value)
            end

            local sliding = false
            local slMove, slEnd
            slMove = function(input)
                local absPos = barBG.AbsolutePosition.X
                local absSize = barBG.AbsoluteSize.X
                local relX = math.clamp((input.Position.X - absPos) / absSize, 0, 1)
                local rawVal = math.clamp(mn + relX * (mx - mn), mn, mx)
                local pct = (rawVal - mn) / math.max(mx - mn, 0.001)
                slideTo(pct, 0.12)
                local display = snapVal(rawVal, mn, mx, inc)
                valLabel.Text = formatDisplay(display) .. suffix
                value = rawVal
            end
            slEnd = function()
                if not sliding then return end
                sliding = false
                moveHandlers[slMove] = nil
                endHandlers[slEnd] = nil
                local snapped = snapVal(value, mn, mx, inc)
                local pct = (snapped - mn) / math.max(mx - mn, 0.001)
                slideTo(pct, 0.2)
                commitValue(snapped)
            end

            dragArea.MouseButton1Down:Connect(function()
                sliding = true
                moveHandlers[slMove] = true
                endHandlers[slEnd] = true
            end)

            dragArea.MouseButton1Click:Connect(function()
                local mouse = UIS:GetMouseLocation()
                local absPos = barBG.AbsolutePosition.X
                local absSize = barBG.AbsoluteSize.X
                local relX = math.clamp((mouse.X - absPos) / absSize, 0, 1)
                local rawVal = mn + relX * (mx - mn)
                local snapped = snapVal(rawVal, mn, mx, inc)
                local pct = (snapped - mn) / math.max(mx - mn, 0.001)
                slideTo(pct, 0.2)
                commitValue(snapped)
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

            local ddLayout = Instance.new("UIListLayout")
            ddLayout.SortOrder = Enum.SortOrder.LayoutOrder
            ddLayout.Padding = UDim.new(0, 0)
            ddLayout.Parent = container

            -- Main row
            local mainRow = Instance.new("Frame")
            mainRow.Size = UDim2.new(1, 0, 0, DROPDOWN_H)
            mainRow.BackgroundColor3 = C.Elem
            mainRow.BorderSizePixel = 0
            mainRow.LayoutOrder = 0
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
            arrow.Rotation = 0
            arrow.Parent = mainRow

            -- Options wrap (clips + tweenable size)
            local optWrap = Instance.new("Frame")
            optWrap.Name = "OptionsWrap"
            optWrap.Size = UDim2.new(1, 0, 0, 0)
            optWrap.BackgroundTransparency = 1
            optWrap.BorderSizePixel = 0
            optWrap.ClipsDescendants = true
            optWrap.Visible = false
            optWrap.LayoutOrder = 1
            optWrap.Parent = container

            local optContainer = Instance.new("Frame")
            optContainer.Name = "Options"
            optContainer.Size = UDim2.new(1, 0, 0, 0)
            optContainer.BackgroundTransparency = 1
            optContainer.Parent = optWrap

            local optLayout = Instance.new("UIListLayout")
            optLayout.SortOrder = Enum.SortOrder.LayoutOrder
            optLayout.Padding = UDim.new(0, 1)
            optLayout.Parent = optContainer

            local optPad = Instance.new("UIPadding")
            optPad.PaddingTop = UDim.new(0, 2)
            optPad.Parent = optContainer

            local function getFullH()
                local n = #options
                return n * 24 + math.max(0, n - 1) + 2
            end
            local function refreshContainerH()
                optContainer.Size = UDim2.new(1, 0, 0, getFullH())
            end

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
                        end
                        valueLabel.Text = table.concat(current, ", ")
                        if flag then updateFlag(flag, current) end
                        if cfg.Callback then task.spawn(cfg.Callback, current) end
                        buildOptions()
                        if not multi then
                            isOpen = false
                            tw(arrow, {Rotation = 0}, 0.16)
                            TS:Create(optWrap, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Size = UDim2.new(1, 0, 0, 0)}):Play()
                            task.delay(0.16, function()
                                if not isOpen then optWrap.Visible = false end
                            end)
                            openDropdown = nil
                        else
                            TS:Create(optWrap, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, getFullH())}):Play()
                        end
                    end)
                end
                refreshContainerH()
            end

            buildOptions()

            -- Toggle open/close
            local mainBtn = Instance.new("TextButton")
            mainBtn.Size = UDim2.new(1, 0, 1, 0)
            mainBtn.BackgroundTransparency = 1
            mainBtn.Text = ""
            mainBtn.Parent = mainRow

            local EXPAND_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
            local COLLAPSE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

            local function closeThis()
                isOpen = false
                tw(arrow, {Rotation = 0}, 0.16)
                TS:Create(optWrap, COLLAPSE_INFO, {Size = UDim2.new(1, 0, 0, 0)}):Play()
                task.delay(0.16, function()
                    if not isOpen then optWrap.Visible = false end
                end)
            end

            mainBtn.MouseButton1Click:Connect(function()
                if isOpen then
                    closeThis()
                    openDropdown = nil
                else
                    closeOpenDropdown()
                    isOpen = true
                    optWrap.Size = UDim2.new(1, 0, 0, 0)
                    optWrap.Visible = true
                    refreshContainerH()
                    tw(arrow, {Rotation = 180}, 0.22)
                    TS:Create(optWrap, EXPAND_INFO, {Size = UDim2.new(1, 0, 0, getFullH())}):Play()
                    openDropdown = closeThis
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

            local labelObj = {}
            function labelObj:Set(newText)
                label.Text = newText or ""
            end
            return labelObj
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

            local captureFn
            captureFn = function(input)
                listening = false
                keybindListener = nil
                currentKey = input.KeyCode.Name
                keyLabel.Text = currentKey
                tw(keyLabel, {TextColor3 = C.Accent, BackgroundColor3 = C.SliderBG}, 0.2)
                if flag then updateFlag(flag, currentKey) end
                if cfg.Callback then task.spawn(cfg.Callback, currentKey) end
            end

            btn.MouseButton1Click:Connect(function()
                listening = true
                keyLabel.Text = "..."
                tw(keyLabel, {TextColor3 = Color3.fromRGB(255, 200, 100), BackgroundColor3 = C.AccentDark}, 0.15)
                keybindListener = captureFn
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
            local boxStroke = addStroke(textBox, 1, C.Border)

            textBox.Focused:Connect(function()
                tw(boxStroke, {Color = C.Accent, Thickness = 1.5}, 0.15)
            end)
            textBox.FocusLost:Connect(function()
                tw(boxStroke, {Color = C.Border, Thickness = 1}, 0.15)
            end)

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
    --               FLAG ACCESS API
    --==================================================
    function Window:SetFlag(flag, value)
        local entry = flagStore[flag]
        if entry and entry.set then task.spawn(entry.set, value) end
    end
    function Window:GetFlag(flag)
        local entry = flagStore[flag]
        return entry and entry.value
    end
    function Window:GetAllFlags()
        local copy = {}
        for k, v in pairs(flagStore) do copy[k] = v.value end
        return copy
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

    -- Animate in (bg + labels + stroke together)
    for _, c in notif:GetChildren() do
        if c:IsA("TextLabel") then c.TextTransparency = 1; tw(c, {TextTransparency = 0}, 0.25) end
    end
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
