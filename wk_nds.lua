-- ===== WK脚本 (自然灾害模拟器版) =====
-- 功能提取自大司马V6开源版, 保留: 自然灾害模拟器功能 + 加载动画
-- 改名: WK脚本

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local _ = Players.LocalPlayer
local mouse = _:GetMouse()

-- ==========================================
-- 加载动画: 右上角实时时间标签
-- ==========================================
local timeGui = Instance.new("ScreenGui")
timeGui.Name = "WK_TimeGui"
timeGui.Parent = game.CoreGui
timeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
timeGui.Enabled = true

local timeLabel = Instance.new("TextLabel")
timeLabel.Name = "WK_Time"
timeLabel.Parent = timeGui
timeLabel.BackgroundColor3 = Color3.new(1, 1, 1)
timeLabel.BackgroundTransparency = 1
timeLabel.BorderColor3 = Color3.new(0, 0, 0)
timeLabel.Position = UDim2.new(0.75, 0, 0.01, 0)
timeLabel.Size = UDim2.new(0, 133, 0, 30)
timeLabel.Font = Enum.Font.GothamSemibold
timeLabel.Text = "WK脚本 时间:--时--分--秒"
timeLabel.TextColor3 = Color3.new(1, 1, 1)
timeLabel.TextScaled = true
timeLabel.TextSize = 14
timeLabel.TextWrapped = true
timeLabel.Visible = true

RunService.Heartbeat:Connect(function()
    timeLabel.Text = "WK脚本 时间:" .. os.date("%H") .. "时" .. os.date("%M") .. "分" .. os.date("%S")
end)

-- ==========================================
-- 加载动画: 启动通知
-- ==========================================
StarterGui:SetCore("SendNotification", {
    Title = "WK脚本",
    Text = "启动中",
    Duration = 2
})
StarterGui:SetCore("SendNotification", {
    Title = "正在加载",
    Text = "启动完毕",
    Duration = 4
})

-- ==========================================
-- UI 库加载
-- ==========================================
local success, uiLib = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/whenheer/iuop/refs/heads/main/Protected_7843953596944453.lua"))()
end)
if not success or not uiLib then
    warn("WK脚本: UI库加载失败, 请检查网络")
    return
end

local v11 = uiLib:new("WK脚本")

-- ==========================================
-- 信息标签页
-- ==========================================
local infoTab = v11:Tab("『信息』", "7734068321"):section("『信息』", false)
infoTab:Label("WK脚本 (自然灾害模拟器版)")
infoTab:Label("功能提取自大司马V6开源版")
infoTab:Label("你现在所在的服务器id:" .. game.GameId)
infoTab:Label("欢迎使用")

-- ==========================================
-- 自然灾害模拟器 标签页
-- ==========================================
local nds = v11:Tab("『自然灾害模拟器』", "7734068321"):section("『自然灾害模拟器』", true)

-- 黑洞脚本1/2 (远程加载)
nds:Button("黑洞脚本1", function()
    loadstring(game:HttpGet("https://glot.io/snippets/gwwv877ga3/raw/main.lua"))()
    return "it will load in around 3 - 131 seconds"
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
    UserInputService.InputBegan:Connect(function(input, processed)
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

-- 键盘脚本 (远程加载)
nds:Button("键盘脚本", function()
    loadstring(game:HttpGet("https://gist.githubusercontent.com/RedZenXYZ/4d80bfd70ee27000660e4bfa7509c667/raw/da903c570249ab3c0c1a74f3467260972c3d87e6/KeyBoard%2520From%2520Ohio%2520Fr%2520Fr"))()
end)
nds:Label("使用黑洞脚本3 刷取物品 手持物品 使用键盘E键 吸取物体")

nds:Button("黑洞脚本中心", function()
    loadstring(game:HttpGet("https://pastebin.com/raw/Q1t1VkrL"))()
end)

-- 自动农场胜出 (自动站上胜出点)
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

-- 地图投票用户界面显示/隐藏
nds:Button("地图投票用户界面", "ToggleInfo", false, function(state)
    pcall(function()
        _.PlayerGui.MainGui.MapVotePage.Visible = state
    end)
end)

-- 在水上行走
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

-- 禁用坠落损坏 (一次性)
nds:Button("禁用坠落损坏", function()
    if _.Character then
        local fd = _.Character:FindFirstChild("FallDamageScript")
        if fd then fd:Destroy() end
    end
end)

-- 自动禁用坠落伤害 (持续)
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

-- 移除灾难界面 (暴风雪和沙尘暴)
nds:Button("移除灾难界面(暴风雪和沙尘暴)", function()
    pcall(function()
        if _.PlayerGui:FindFirstChild("BlizzardGui") then _.PlayerGui.BlizzardGui:Destroy() end
        if _.PlayerGui:FindFirstChild("SandStormGui") then _.PlayerGui.SandStormGui:Destroy() end
    end)
end)

-- 传送到地图
nds:Button("传送到地图", function()
    _.Character.HumanoidRootPart.CFrame = CFrame.new(-115.828506, 65.4863434, 18.8461514, 0.00697017973, 0.0789371505, -0.996855199, -3.13589936e-7, 0.996879458, 0.0789390653, 0.999975681, -0.000549906865, 0.00694845384)
end)

-- 游戏岛 (不建议用)
nds:Button("游戏岛 不建议用", function()
    _.Character.HumanoidRootPart.CFrame = CFrame.new(-83.5, 38.5, -27.5, -1, 0, 0, 0, 1, 0, 0, 0, -1)
end)

-- 产卵塔
nds:Button("产卵塔", function()
    _.Character.HumanoidRootPart.CFrame = CFrame.new(-280, 170, 341, 1, 0, 0, 0, 1, 0, 0, 0, 1)
end)

-- 步行速度滑条
nds:Button("步行速度", "SliderInfo", 16, 16, 250, false, function(value)
    if _.Character and _.Character:FindFirstChild("Humanoid") then
        _.Character.Humanoid.WalkSpeed = value
    end
end)

-- 跳跃能力滑条
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
        local pos = mouse.Hit + Vector3.new(0, 2.5, 0)
        _.Character.HumanoidRootPart.CFrame = CFrame.new(pos.X, pos.Y, pos.Z)
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

-- 飞行 (远程加载)
nds:Button("飞行", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/dingding123hhh/tt/main/jm%E9%A3%9E..lua"))()
end)

-- 自然灾害模拟器1/2/3 (远程加载)
nds:Button("自然灾害模拟器1", function()
    loadstring(game:HttpGet("https://gist.githubusercontent.com/TurkOyuncu99/7c75386107937fa006304efd24543ad4/raw/8d759dfcd95d39949c692735cfdf62baec0bf835/cafwetweg", true))()
end)
nds:Button("自然灾害模拟器2", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/2dgeneralspam1/scripts-and-stuff/master/scripts/LoadstringUjHI6RQpz2o8", true))()
end)
nds:Button("自然灾害模拟器3", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/9NLK7/93qjoadnlaknwldk/main/main"))()
end)

print("WK脚本 (自然灾害模拟器版) 已加载")
