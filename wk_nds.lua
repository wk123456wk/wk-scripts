-- ===== WK脚本 (自然灾害模拟器版 · Rayfield UI) =====
-- 功能提取自大司马V6开源版 + Rayfield 界面 + 黑洞3合1
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

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
local timeOk = pcall(function() timeGui.Parent = CoreGui end)
if not timeOk or not timeGui.Parent then timeGui.Parent = PlayerGui end

local timeLabel = Instance.new("TextLabel")
timeLabel.Name = "WK_Time"
timeLabel.Parent = timeGui
timeLabel.BackgroundColor3 = Color3.new(1, 1, 1)
timeLabel.BackgroundTransparency = 1
timeLabel.Position = UDim2.new(0.68, 0, 0.02, 0)
timeLabel.Size = UDim2.new(0, 200, 0, 28)
timeLabel.Font = Enum.Font.GothamBold
timeLabel.Text = "WK脚本 时间:--时--分--秒"
timeLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
timeLabel.TextStrokeTransparency = 0.4
timeLabel.TextSize = 15

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
-- 极速启动弹窗 (防止黑屏等待)
-- ==========================================
local loadGui = Instance.new("ScreenGui")
loadGui.Name = "WK_QuickLoad"
loadGui.DisplayOrder = 999999
loadGui.Parent = CoreGui

local frame = Instance.new("Frame", loadGui)
frame.Size = UDim2.new(0, 200, 0, 60)
frame.Position = UDim2.new(0.5, -100, 0.5, -30)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", frame).Color = Color3.fromRGB(0, 255, 0)

local loadText = Instance.new("TextLabel", frame)
loadText.Size = UDim2.new(1, 0, 1, 0)
loadText.BackgroundTransparency = 1
loadText.Text = "正在启动 WK 脚本..."
loadText.TextColor3 = Color3.fromRGB(0, 255, 0)
loadText.Font = Enum.Font.SourceSansBold
loadText.TextSize = 16

-- 清理旧UI
for _, parent in ipairs({CoreGui, PlayerGui}) do
    for _, obj in ipairs(parent:GetChildren()) do
        local name = obj.Name:lower()
        if name:find("rayfield") or name:find("wk_hub") then pcall(function() obj:Destroy() end) end
    end
end

-- ==========================================
-- 加载 Rayfield (原UI界面)
-- ==========================================
local success, Rayfield = pcall(function() return loadstring(game:HttpGet("https://sirius.menu/rayfield"))() end)
if not success or not Rayfield then
    Rayfield = loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareSptd/Rayfield/main/source.lua", true))()
end
if not Rayfield then
    loadText.Text = "网络错误，加载失败"
    loadText.TextColor3 = Color3.fromRGB(255, 0, 0)
    task.wait(3)
    loadGui:Destroy()
    return
end

local Window = Rayfield:CreateWindow({
    Name = "WK脚本",
    LoadingTitle = "",
    LoadingSubtitle = "",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})
loadGui:Destroy() -- 菜单创建成功，销毁启动弹窗

local TabInfo = Window:CreateTab("信息", 4483362458)
local TabNDS = Window:CreateTab("自然灾害模拟器", 4483362458)

-- ==========================================
-- 信息页
-- ==========================================
TabInfo:CreateSection("『信息』")
TabInfo:CreateParagraph({
    Title = "WK脚本 (自然灾害模拟器版)",
    Content = "功能提取自大司马V6开源版\nUI: Rayfield (手机可用)\n你现在所在的服务器id: " .. tostring(game.GameId) .. "\n黑洞已3合1: 一个按钮全开"
})

-- ==========================================
-- 黑洞 3合1 (黑洞1 + 黑洞2 + 黑洞3 一键全开)
-- ==========================================
TabNDS:CreateSection("黑洞 (3合1)")

local blackHoleStarted = false
TabNDS:CreateButton({
    Name = "黑洞脚本 (3合1) 一键全开",
    Callback = function()
        if blackHoleStarted then return end
        blackHoleStarted = true
        task.spawn(function()
            -- 1. 黑洞脚本1 (远程)
            pcall(function()
                loadstring(game:HttpGet("https://glot.io/snippets/gwwv877ga3/raw/main.lua"))()
            end)
            task.wait(1)
            -- 2. 黑洞脚本2 (远程)
            pcall(function()
                loadstring(game:HttpGet("https://raw.githubusercontent.com/dingding123hhh/lililiugg/main/jm114514.lua"))()
            end)
            task.wait(1)
            -- 3. 黑洞脚本3 (本地: 对准位置按E吸取物体)
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
            while RunService.RenderStepped:Wait() do
                anchorAtt.WorldCFrame = suctionPos
            end
        end)
    end,
})
TabNDS:CreateParagraph({
    Title = "黑洞使用说明",
    Content = "点上面的按钮后黑洞1+2+3全部自动启动。\n吸取位置: 电脑按E换位置 (手机无法按E, 默认在鼠标指向处)。\n刷取物品: 手持物品后开黑洞吸取。"
})

TabNDS:CreateButton({
    Name = "键盘脚本 (手持物品用)",
    Callback = function()
        loadstring(game:HttpGet("https://gist.githubusercontent.com/RedZenXYZ/4d80bfd70ee27000660e4bfa7509c667/raw/da903c570249ab3c0c1a74f3467260972c3d87e6/KeyBoard%2520From%2520Ohio%2520Fr%2520Fr"))()
    end,
})

TabNDS:CreateButton({
    Name = "黑洞脚本中心",
    Callback = function()
        loadstring(game:HttpGet("https://pastebin.com/raw/Q1t1VkrL"))()
    end,
})

-- ==========================================
-- 自动胜出 / 界面 / 碰撞
-- ==========================================
TabNDS:CreateSection("自动与界面")

TabNDS:CreateToggle({
    Name = "自动农场胜出",
    CurrentValue = false,
    Flag = "AutoWinFarm",
    Callback = function(state)
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
    end,
})

TabNDS:CreateToggle({
    Name = "地图投票用户界面",
    CurrentValue = false,
    Flag = "MapVoteUI",
    Callback = function(state)
        pcall(function()
            PlayerGui.MainGui.MapVotePage.Visible = state
        end)
    end,
})

TabNDS:CreateToggle({
    Name = "在水上行走",
    CurrentValue = false,
    Flag = "WalkOnWater",
    Callback = function(state)
        pcall(function()
            if state == false then
                Workspace.WaterLevel.CanCollide = false
                Workspace.WaterLevel.Size = Vector3.new(10, 1, 10)
            else
                Workspace.WaterLevel.CanCollide = true
                Workspace.WaterLevel.Size = Vector3.new(5000, 1, 5000)
            end
        end)
    end,
})

TabNDS:CreateToggle({
    Name = "游戏岛悬崖碰撞",
    CurrentValue = false,
    Flag = "CliffCollision",
    Callback = function(state)
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj.Name == "LowerRocks" and obj:IsA("BasePart") then
                obj.CanCollide = state
            end
        end
    end,
})

-- ==========================================
-- 坠落伤害
-- ==========================================
TabNDS:CreateSection("坠落伤害")

TabNDS:CreateButton({
    Name = "禁用坠落损坏",
    Callback = function()
        if _.Character then
            local fd = _.Character:FindFirstChild("FallDamageScript")
            if fd then fd:Destroy() end
        end
    end,
})

TabNDS:CreateToggle({
    Name = "自动禁用坠落伤害",
    CurrentValue = false,
    Flag = "AutoNoFallDamage",
    Callback = function(state)
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
    end,
})

-- ==========================================
-- 灾难信息
-- ==========================================
TabNDS:CreateSection("灾难信息")

TabNDS:CreateButton({
    Name = "打印下一次灾难(/console)",
    Callback = function()
        pcall(function()
            warn("下一次灾难: " .. tostring(_.Character.SurvivalTag.Value))
        end)
    end,
})

TabNDS:CreateButton({
    Name = "移除灾难界面(暴风雪和沙尘暴)",
    Callback = function()
        pcall(function()
            if PlayerGui:FindFirstChild("BlizzardGui") then PlayerGui.BlizzardGui:Destroy() end
            if PlayerGui:FindFirstChild("SandStormGui") then PlayerGui.SandStormGui:Destroy() end
        end)
    end,
})

-- ==========================================
-- 传送
-- ==========================================
TabNDS:CreateSection("传送")

TabNDS:CreateButton({
    Name = "传送到地图",
    Callback = function()
        if _.Character and _.Character:FindFirstChild("HumanoidRootPart") then
            _.Character.HumanoidRootPart.CFrame = CFrame.new(-115.828506, 65.4863434, 18.8461514, 0.00697017973, 0.0789371505, -0.996855199, -3.13589936e-7, 0.996879458, 0.0789390653, 0.999975681, -0.000549906865, 0.00694845384)
        end
    end,
})

TabNDS:CreateButton({
    Name = "游戏岛 不建议用",
    Callback = function()
        if _.Character and _.Character:FindFirstChild("HumanoidRootPart") then
            _.Character.HumanoidRootPart.CFrame = CFrame.new(-83.5, 38.5, -27.5, -1, 0, 0, 0, 1, 0, 0, 0, -1)
        end
    end,
})

TabNDS:CreateButton({
    Name = "产卵塔",
    Callback = function()
        if _.Character and _.Character:FindFirstChild("HumanoidRootPart") then
            _.Character.HumanoidRootPart.CFrame = CFrame.new(-280, 170, 341, 1, 0, 0, 0, 1, 0, 0, 0, 1)
        end
    end,
})

-- ==========================================
-- 速度与跳跃
-- ==========================================
TabNDS:CreateSection("角色属性")

TabNDS:CreateSlider({
    Name = "步行速度",
    Range = {16, 250},
    Increment = 1,
    Suffix = " WalkSpeed",
    CurrentValue = 16,
    Flag = "WalkSpeed",
    Callback = function(value)
        if _.Character and _.Character:FindFirstChild("Humanoid") then
            _.Character.Humanoid.WalkSpeed = value
        end
    end,
})

TabNDS:CreateSlider({
    Name = "跳跃能力",
    Range = {16, 250},
    Increment = 1,
    Suffix = " JumpPower",
    CurrentValue = 16,
    Flag = "JumpPower",
    Callback = function(value)
        if _.Character and _.Character:FindFirstChild("Humanoid") then
            _.Character.Humanoid.JumpPower = value
        end
    end,
})

-- ==========================================
-- 工具与其他
-- ==========================================
TabNDS:CreateSection("工具")

TabNDS:CreateButton({
    Name = "单击TP工具",
    Callback = function()
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
    end,
})

TabNDS:CreateButton({
    Name = "反AFK",
    Callback = function()
        wait(0.5)
        local virtualUser = game:GetService("VirtualUser")
        Players.LocalPlayer.Idled:Connect(function()
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.new())
        end)
        print("Antiafk enabled")
    end,
})

-- ==========================================
-- 远程加载功能
-- ==========================================
TabNDS:CreateSection("远程脚本")

TabNDS:CreateButton({
    Name = "飞行",
    Callback = function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/dingding123hhh/tt/main/jm%E9%A3%9E..lua"))()
    end,
})

TabNDS:CreateButton({
    Name = "自然灾害模拟器1",
    Callback = function()
        loadstring(game:HttpGet("https://gist.githubusercontent.com/TurkOyuncu99/7c75386107937fa006304efd24543ad4/raw/8d759dfcd95d39949c692735cfdf62baec0bf835/cafwetweg", true))()
    end,
})

TabNDS:CreateButton({
    Name = "自然灾害模拟器2",
    Callback = function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/2dgeneralspam1/scripts-and-stuff/master/scripts/LoadstringUjHI6RQpz2o8", true))()
    end,
})

TabNDS:CreateButton({
    Name = "自然灾害模拟器3",
    Callback = function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/9NLK7/93qjoadnlaknwldk/main/main"))()
    end,
})

print("WK脚本 (自然灾害模拟器版 · Rayfield UI · 黑洞3合1) 已加载")
