-- ===== WK脚本 (自然灾害模拟器版 · 内置UI) =====
-- 功能提取自大司马V6开源版 + 自研内置UI框架 (手机可用, 无加密库依赖)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local _ = Players.LocalPlayer
local mouse = _:GetMouse()

-- ==========================================
-- 加载动画: 右上角实时时间标签
-- ==========================================
local timeGui = Instance.new("ScreenGui")
timeGui.Name = "WK_TimeGui"
timeGui.ResetOnSpawn = false
timeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
timeGui.DisplayOrder = 998
local timeOk = pcall(function() timeGui.Parent = game:GetService("CoreGui") end)
if not timeOk or not timeGui.Parent then timeGui.Parent = _.PlayerGui end

local timeLabel = Instance.new("TextLabel")
timeLabel.Name = "WK_Time"
timeLabel.Parent = timeGui
timeLabel.BackgroundColor3 = Color3.new(1, 1, 1)
timeLabel.BackgroundTransparency = 1
timeLabel.BorderColor3 = Color3.new(0, 0, 0)
timeLabel.Position = UDim2.new(0.68, 0, 0.02, 0)
timeLabel.Size = UDim2.new(0, 200, 0, 28)
timeLabel.Font = Enum.Font.GothamBold
timeLabel.Text = "WK脚本 时间:--时--分--秒"
timeLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
timeLabel.TextStrokeTransparency = 0.4
timeLabel.TextSize = 15
timeLabel.Visible = true

RunService.Heartbeat:Connect(function()
    timeLabel.Text = "WK脚本 时间:" .. os.date("%H") .. "时" .. os.date("%M") .. "分" .. os.date("%S")
end)

-- ==========================================
-- 加载动画: 启动通知
-- ==========================================
pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "WK脚本",
        Text = "启动中",
        Duration = 2
    })
    task.wait(0.6)
    StarterGui:SetCore("SendNotification", {
        Title = "正在加载",
        Text = "启动完毕",
        Duration = 4
    })
end)

-- ==========================================
-- 内置 UI 框架 (替代原加密UI库)
-- ==========================================
local THEME = {
    bg = Color3.fromRGB(18, 20, 22),
    panel = Color3.fromRGB(28, 31, 34),
    row = Color3.fromRGB(38, 42, 46),
    accent = Color3.fromRGB(0, 255, 120),
    text = Color3.fromRGB(238, 241, 243),
    sub = Color3.fromRGB(150, 158, 165),
    dark = Color3.fromRGB(10, 12, 12),
}

local function new(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props) do
        obj[k] = v
    end
    if parent then obj.Parent = parent end
    return obj
end

local TabMethods = {}
local SectionMethods = {}

local WKUI = {}
WKUI.__index = WKUI

function WKUI.new(title)
    local self = setmetatable({}, WKUI)
    self.tabs = {}

    local gui = Instance.new("ScreenGui")
    gui.Name = "WK_Hub"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 999
    local ok = pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not ok or not gui.Parent then gui.Parent = _.PlayerGui end
    self.gui = gui

    local main = new("Frame", {
        Name = "Main",
        Size = UDim2.new(0, 400, 0, 440),
        Position = UDim2.new(0, 24, 0.5, -220),
        BackgroundColor3 = THEME.bg,
        BorderSizePixel = 0,
        Active = true,
    }, gui)
    new("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
    new("UIStroke", { Color = THEME.accent, Thickness = 1.5, Transparency = 0.5 }, main)
    self.main = main

    -- 标题栏
    local titleBar = new("Frame", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = THEME.panel,
        BorderSizePixel = 0,
    }, main)
    new("UICorner", { CornerRadius = UDim.new(0, 10) }, titleBar)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -60, 1, 0),
        Font = Enum.Font.GothamBold,
        Text = title,
        TextColor3 = THEME.accent,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, titleBar)

    local hideBtn = new("TextButton", {
        Size = UDim2.new(0, 32, 0, 24),
        Position = UDim2.new(1, -40, 0, 6),
        BackgroundColor3 = Color3.fromRGB(58, 64, 70),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "—",
        TextColor3 = THEME.text,
        TextSize = 14,
    }, titleBar)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, hideBtn)

    -- 悬浮恢复按钮
    local floatBtn = new("TextButton", {
        Size = UDim2.new(0, 48, 0, 48),
        Position = UDim2.new(0, 20, 0.32, 0),
        BackgroundColor3 = THEME.accent,
        BorderSizePixel = 0,
        Text = "WK",
        Font = Enum.Font.GothamBold,
        TextColor3 = THEME.dark,
        TextSize = 15,
        Visible = false,
        AutoButtonColor = true,
    }, gui)
    new("UICorner", { CornerRadius = UDim.new(0, 24) }, floatBtn)

    hideBtn.MouseButton1Click:Connect(function()
        main.Visible = false
        floatBtn.Visible = true
    end)
    floatBtn.MouseButton1Click:Connect(function()
        main.Visible = true
        floatBtn.Visible = false
    end)

    -- 窗口拖动 (鼠标 + 触屏)
    local dragging, dragStart, startPos = false, nil, nil
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- 标签栏
    local tabBar = new("Frame", {
        Position = UDim2.new(0, 10, 0, 44),
        Size = UDim2.new(1, -20, 0, 32),
        BackgroundTransparency = 1,
    }, main)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, tabBar)

    self.contentHolder = new("Frame", {
        Position = UDim2.new(0, 8, 0, 82),
        Size = UDim2.new(1, -16, 1, -90),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
    }, main)
    self.tabBar = tabBar
    return self
end

function WKUI:Tab(name)
    local index = #self.tabs + 1
    local scroll = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarImageTransparency = 0.3,
        Visible = (index == 1),
    }, self.contentHolder)
    new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
    new("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 12) }, scroll)

    local btn = new("TextButton", {
        Size = UDim2.new(0, 118, 0, 30),
        BackgroundColor3 = (index == 1) and THEME.accent or THEME.row,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = name,
        TextColor3 = (index == 1) and THEME.dark or THEME.text,
        TextSize = 12,
        LayoutOrder = index,
    }, self.tabBar)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)

    local tab = setmetatable({ ui = self, scroll = scroll, btn = btn, orderCount = 0 }, { __index = TabMethods })
    table.insert(self.tabs, tab)

    btn.MouseButton1Click:Connect(function()
        for _, t in ipairs(self.tabs) do
            t.scroll.Visible = (t == tab)
            t.btn.BackgroundColor3 = (t == tab) and THEME.accent or THEME.row
            t.btn.TextColor3 = (t == tab) and THEME.dark or THEME.text
        end
    end)
    return tab
end

function TabMethods:section(title)
    self.orderCount = self.orderCount + 1
    local sec = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.panel,
        BorderSizePixel = 0,
        LayoutOrder = self.orderCount,
    }, self.scroll)
    new("UICorner", { CornerRadius = UDim.new(0, 8) }, sec)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, sec)
    new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, sec)

    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = title,
        TextColor3 = THEME.accent,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 0,
    }, sec)

    local body = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 1,
    }, sec)
    new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, body)

    return setmetatable({ body = body, order = 0 }, { __index = SectionMethods })
end

function SectionMethods:Label(text)
    self.order = self.order + 1
    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = text,
        TextColor3 = THEME.sub,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = self.order,
    }, self.body)
end

-- 兼容原库三种调用:
-- Button(名字, 回调)
-- Button(名字, "ToggleInfo", 默认值, 回调)
-- Button(名字, "SliderInfo", 当前值, 最小值, 最大值, 百分比?, 回调)
function SectionMethods:Button(name, kind, a, b, c, d, e)
    self.order = self.order + 1
    local order = self.order

    if type(kind) == "function" or kind == nil then
        local callback = kind or function() end
        local btn = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = THEME.row,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            Text = name,
            TextColor3 = THEME.text,
            TextSize = 13,
            LayoutOrder = order,
            AutoButtonColor = true,
        }, self.body)
        new("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
        btn.MouseButton1Click:Connect(function()
            pcall(callback)
        end)
        return btn

    elseif kind == "ToggleInfo" then
        local state = a and true or false
        local callback = b or function() end

        local row = new("Frame", {
            Size = UDim2.new(1, 0, 0, 36),
            BackgroundColor3 = THEME.row,
            BorderSizePixel = 0,
            LayoutOrder = order,
        }, self.body)
        new("UICorner", { CornerRadius = UDim.new(0, 6) }, row)

        new("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 10, 0, 0),
            Size = UDim2.new(1, -64, 1, 0),
            Font = Enum.Font.Gotham,
            Text = name,
            TextColor3 = THEME.text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)

        local switch = new("Frame", {
            Size = UDim2.new(0, 40, 0, 20),
            Position = UDim2.new(1, -50, 0.5, -10),
            BackgroundColor3 = state and THEME.accent or Color3.fromRGB(70, 76, 82),
            BorderSizePixel = 0,
        }, row)
        new("UICorner", { CornerRadius = UDim.new(0, 10) }, switch)

        local knob = new("Frame", {
            Size = UDim2.new(0, 16, 0, 16),
            Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
            BackgroundColor3 = Color3.fromRGB(240, 240, 240),
            BorderSizePixel = 0,
        }, switch)
        new("UICorner", { CornerRadius = UDim.new(0, 8) }, knob)

        local hit = new("TextButton", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
        }, row)

        local function apply(newState)
            state = newState
            switch.BackgroundColor3 = state and THEME.accent or Color3.fromRGB(70, 76, 82)
            knob.Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        end

        hit.MouseButton1Click:Connect(function()
            state = not state
            apply(state)
            pcall(callback, state)
        end)
        return row

    elseif kind == "SliderInfo" then
        local current = tonumber(a) or 0
        local minV = tonumber(b) or 0
        local maxV = tonumber(c) or 100
        local callback = e or function() end
        if maxV <= minV then maxV = minV + 1 end

        local row = new("Frame", {
            Size = UDim2.new(1, 0, 0, 46),
            BackgroundColor3 = THEME.row,
            BorderSizePixel = 0,
            LayoutOrder = order,
        }, self.body)
        new("UICorner", { CornerRadius = UDim.new(0, 6) }, row)

        new("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 10, 0, 4),
            Size = UDim2.new(1, -80, 0, 18),
            Font = Enum.Font.Gotham,
            Text = name,
            TextColor3 = THEME.text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)

        local valueText = new("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -70, 0, 4),
            Size = UDim2.new(0, 60, 0, 18),
            Font = Enum.Font.GothamBold,
            Text = tostring(current),
            TextColor3 = THEME.accent,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Right,
        }, row)

        local track = new("Frame", {
            Position = UDim2.new(0, 10, 0, 28),
            Size = UDim2.new(1, -20, 0, 8),
            BackgroundColor3 = Color3.fromRGB(60, 66, 72),
            BorderSizePixel = 0,
        }, row)
        new("UICorner", { CornerRadius = UDim.new(0, 4) }, track)

        local rel0 = math.clamp((current - minV) / (maxV - minV), 0, 1)
        local fill = new("Frame", {
            Size = UDim2.new(rel0, 0, 1, 0),
            BackgroundColor3 = THEME.accent,
            BorderSizePixel = 0,
        }, track)
        new("UICorner", { CornerRadius = UDim.new(0, 4) }, fill)

        local dragging = false
        local function setFromX(px)
            local rel = math.clamp((px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
            local value = math.floor(minV + (maxV - minV) * rel + 0.5)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            valueText.Text = tostring(value)
            pcall(callback, value)
        end

        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                setFromX(input.Position.X)
            end
        end)
        UIS.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                setFromX(input.Position.X)
            end
        end)
        UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
        return row
    end
end

-- ==========================================
-- 创建菜单
-- ==========================================
local v11 = WKUI.new("WK脚本")

-- 信息页
local infoTab = v11:Tab("信息"):section("『信息』")
infoTab:Label("WK脚本 (自然灾害模拟器版)")
infoTab:Label("功能提取自大司马V6开源版")
infoTab:Label("内置UI · 手机可用")
infoTab:Label("你现在所在的服务器id:" .. game.GameId)
infoTab:Label("点标题栏可拖动窗口, 点 — 可收起")

-- ==========================================
-- 自然灾害模拟器
-- ==========================================
local nds = v11:Tab("自然灾害模拟器"):section("『自然灾害模拟器』")

nds:Button("黑洞脚本1", function()
    loadstring(game:HttpGet("https://glot.io/snippets/gwwv877ga3/raw/main.lua"))()
end)
nds:Button("黑洞脚本2", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/dingding123hhh/lililiugg/main/jm114514.lua"))()
end)
nds:Label("黑洞1,2都要开 先开1,再开2")

-- 黑洞脚本3 (本地实现: 对准位置按E吸取物体)
nds:Button("黑洞脚本3", function()
    print("WK 黑洞3 启动")
    local folder = Instance.new("Folder", Workspace)
    local anchor = Instance.new("Part", folder)
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.Transparency = 1
    local anchorAtt = Instance.new("Attachment", anchor)
    local suctionPos = mouse.Hit + Vector3.new(0, 5, 0)
    local spinSpeed = 1000

    local function applyPart(part)
        if part:IsA("Part") and part.Anchored == false and part.Parent ~= _.Character then
            mouse.TargetFilter = part
            for _, child in ipairs(part:GetChildren()) do
                if child:IsA("BodyAngularVelocity") or child:IsA("BodyForce") or child:IsA("BodyGyro") or child:IsA("BodyPosition") or child:IsA("BodyThrust") or child:IsA("BodyVelocity") or child:IsA("RocketPropulsion") then
                    child:Destroy()
                end
            end
            local oldAtt = part:FindFirstChild("Attachment")
            if oldAtt then oldAtt:Destroy() end
            part.CanCollide = false
            local bav = Instance.new("BodyAngularVelocity", part)
            bav.AngularVelocity = Vector3.new(0, math.rad(spinSpeed), 0)
            bav.MaxTorque = Vector3.new(10000, 10000, 10000)
            local align = Instance.new("AlignPosition", part)
            local att0 = Instance.new("Attachment", part)
            align.MaxForce = 50000
            align.MaxVelocity = 50
            align.Responsiveness = 50
            align.Attachment0 = att0
            align.Attachment1 = anchorAtt
        end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Part") and obj.Parent ~= _.Character then
            applyPart(obj)
        end
    end
    Workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("Part") and obj.Parent ~= _.Character then
            applyPart(obj)
        end
    end)
    UIS.InputBegan:Connect(function(input, processed)
        if input.KeyCode == Enum.KeyCode.E and not processed then
            suctionPos = mouse.Hit + Vector3.new(0, 5, 0)
        end
    end)
    task.spawn(function()
        while RunService.RenderStepped:Wait() do
            anchorAtt.WorldCFrame = suctionPos
        end
    end)
end)

nds:Button("键盘脚本", function()
    loadstring(game:HttpGet("https://gist.githubusercontent.com/RedZenXYZ/4d80bfd70ee27000660e4bfa7509c667/raw/da903c570249ab3c0c1a74f3467260972c3d87e6/KeyBoard%2520From%2520Ohio%2520Fr%2520Fr"))()
end)
nds:Label("使用黑洞脚本3 刷取物品 手持物品 使用键盘E键 吸取物体")

nds:Button("黑洞脚本中心", function()
    loadstring(game:HttpGet("https://pastebin.com/raw/Q1t1VkrL"))()
end)

-- 自动农场胜出
nds:Button("自动农场胜出", "ToggleInfo", false, function(state)
    _G.autowinfarm = state
    if _G.wkAutoWinStarted then return end
    _G.wkAutoWinStarted = true
    task.spawn(function()
        while wait(0.1) do
            if _G.autowinfarm == true and _.Character and _.Character:FindFirstChild("HumanoidRootPart") then
                _.Character.HumanoidRootPart.CFrame = CFrame.new(-236, 180, 360, 1, 0, 0, 0, 1, 0, 0, 0, 1)
            end
        end
    end)
end)

-- 地图投票界面
nds:Button("地图投票用户界面", "ToggleInfo", false, function(state)
    pcall(function()
        _.PlayerGui.MainGui.MapVotePage.Visible = state
    end)
end)

-- 水上行走
nds:Button("在水上行走", "ToggleInfo", false, function(state)
    pcall(function()
        if state == false then
            Workspace.WaterLevel.CanCollide = false
            Workspace.WaterLevel.Size = Vector3.new(10, 1, 10)
        else
            Workspace.WaterLevel.CanCollide = true
            Workspace.WaterLevel.Size = Vector3.new(5000, 1, 5000)
        end
    end)
end)

-- 游戏岛悬崖碰撞
nds:Button("游戏岛悬崖碰撞", "ToggleInfo", false, function(state)
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name == "LowerRocks" and obj:IsA("BasePart") then
            obj.CanCollide = state
        end
    end
end)

-- 禁用坠落损坏
nds:Button("禁用坠落损坏", function()
    if _.Character then
        local fd = _.Character:FindFirstChild("FallDamageScript")
        if fd then fd:Destroy() end
    end
end)

-- 自动禁用坠落伤害
nds:Button("自动禁用坠落伤害", "ToggleInfo", false, function(state)
    _G.NoFallDamage = state
    if _G.wkNoFallStarted then return end
    _G.wkNoFallStarted = true
    task.spawn(function()
        while wait(0.5) do
            if _G.NoFallDamage == true and _.Character then
                local fd = _.Character:FindFirstChild("FallDamageScript")
                if fd then fd:Destroy() end
            end
        end
    end)
end)

-- 打印下一次灾难
nds:Button("打印下一次灾难(/console)", function()
    pcall(function()
        warn("下一次灾难: " .. tostring(_.Character.SurvivalTag.Value))
    end)
end)

-- 移除灾难界面
nds:Button("移除灾难界面(暴风雪和沙尘暴)", function()
    pcall(function()
        if _.PlayerGui:FindFirstChild("BlizzardGui") then _.PlayerGui.BlizzardGui:Destroy() end
        if _.PlayerGui:FindFirstChild("SandStormGui") then _.PlayerGui.SandStormGui:Destroy() end
    end)
end)

-- 传送
nds:Button("传送到地图", function()
    if _.Character and _.Character:FindFirstChild("HumanoidRootPart") then
        _.Character.HumanoidRootPart.CFrame = CFrame.new(-115.828506, 65.4863434, 18.8461514, 0.00697017973, 0.0789371505, -0.996855199, -3.13589936e-7, 0.996879458, 0.0789390653, 0.999975681, -0.000549906865, 0.00694845384)
    end
end)

nds:Button("游戏岛 不建议用", function()
    if _.Character and _.Character:FindFirstChild("HumanoidRootPart") then
        _.Character.HumanoidRootPart.CFrame = CFrame.new(-83.5, 38.5, -27.5, -1, 0, 0, 0, 1, 0, 0, 0, -1)
    end
end)

nds:Button("产卵塔", function()
    if _.Character and _.Character:FindFirstChild("HumanoidRootPart") then
        _.Character.HumanoidRootPart.CFrame = CFrame.new(-280, 170, 341, 1, 0, 0, 0, 1, 0, 0, 0, 1)
    end
end)

-- 滑条
nds:Button("步行速度", "SliderInfo", 16, 16, 250, false, function(value)
    if _.Character and _.Character:FindFirstChild("Humanoid") then
        _.Character.Humanoid.WalkSpeed = value
    end
end)

nds:Button("跳跃能力", "SliderInfo", 16, 16, 250, false, function(value)
    if _.Character and _.Character:FindFirstChild("Humanoid") then
        _.Character.Humanoid.JumpPower = value
    end
end)

-- 单击TP工具
nds:Button("单击TP工具", function()
    local tool = Instance.new("Tool")
    tool.RequiresHandle = false
    tool.Name = "Click Teleport"
    tool.Activated:Connect(function()
        if _.Character and _.Character:FindFirstChild("HumanoidRootPart") then
            local pos = mouse.Hit + Vector3.new(0, 2.5, 0)
            _.Character.HumanoidRootPart.CFrame = CFrame.new(pos.X, pos.Y, pos.Z)
        end
    end)
    tool.Parent = _:Backpack()
end)

-- 反AFK
nds:Button("反AFK", function()
    wait(0.5)
    local virtualUser = game:GetService("VirtualUser")
    Players.LocalPlayer.Idled:Connect(function()
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new())
    end)
    print("Antiafk enabled")
end)

-- 远程加载功能
nds:Button("飞行", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/dingding123hhh/tt/main/jm%E9%A3%9E..lua"))()
end)

nds:Button("自然灾害模拟器1", function()
    loadstring(game:HttpGet("https://gist.githubusercontent.com/TurkOyuncu99/7c75386107937fa006304efd24543ad4/raw/8d759dfcd95d39949c692735cfdf62baec0bf835/cafwetweg", true))()
end)
nds:Button("自然灾害模拟器2", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/2dgeneralspam1/scripts-and-stuff/master/scripts/LoadstringUjHI6RQpz2o8", true))()
end)
nds:Button("自然灾害模拟器3", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/9NLK7/93qjoadnlaknwldk/main/main"))()
end)

print("WK脚本 (自然灾害模拟器版 · 内置UI) 已加载")
