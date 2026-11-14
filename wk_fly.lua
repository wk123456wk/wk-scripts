-- ===== WK 辅助 (防多开 + 极速启动弹窗版) =====
local p = game:GetService('Players').LocalPlayer
local R = game:GetService('RunService')
local U = game:GetService('UserInputService')
local CoreGui = game:GetService('CoreGui')
local PlayerGui = p:WaitForChild('PlayerGui')

-- ==========================================
-- 1. 极速清理旧版本 (防多点重叠)
-- ==========================================
-- 遍历并彻底销毁之前可能生成的 UI
local function cleanOldUI()
    for _, parent in ipairs({CoreGui, PlayerGui}) do
        for _, obj in ipairs(parent:GetChildren()) do
            local name = obj.Name:lower()
            if name:find("rayfield") or name:find("wk_") or name:find("flygui") or name:find("ui_manager") then
                pcall(function() obj:Destroy() end)
            end
        end
    end
end
cleanOldUI()

-- ==========================================
-- 2. 立刻显示启动弹窗
-- ==========================================
local loadGui = Instance.new('ScreenGui')
loadGui.Name = 'WK_QuickLoad'
loadGui.DisplayOrder = 999999
loadGui.Parent = CoreGui

local frame = Instance.new('Frame', loadGui)
frame.Size = UDim2.new(0, 200, 0, 60)
frame.Position = UDim2.new(0.5, -100, 0.5, -30)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
frame.BorderSizePixel = 0

local corner = Instance.new('UICorner', frame)
corner.CornerRadius = UDim.new(0, 8)

local stroke = Instance.new('UIStroke', frame)
stroke.Color = Color3.fromRGB(0, 255, 0)
stroke.Thickness = 2

local text = Instance.new('TextLabel', frame)
text.Size = UDim2.new(1, 0, 1, 0)
text.BackgroundTransparency = 1
text.Text = '正在启动 WK 脚本...'
text.TextColor3 = Color3.fromRGB(0, 255, 0)
text.Font = Enum.Font.SourceSansBold
text.TextSize = 16

-- ==========================================
-- 3. 加载 Rayfield
-- ==========================================
local success, Rayfield = pcall(function() 
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))() 
end)
if not success or not Rayfield then
    Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/SiriusSoftwareSptd/Rayfield/main/source.lua', true))()
end

if not Rayfield then 
    text.Text = '网络错误，加载失败'
    text.TextColor3 = Color3.fromRGB(255, 0, 0)
    task.wait(3)
    loadGui:Destroy()
    return 
end

-- ==========================================
-- 4. 创建新菜单 (成功后销毁弹窗)
-- ==========================================
local Window = Rayfield:CreateWindow({
    Name = "WK 辅助菜单",
    LoadingTitle = "WK 辅助加载中",
    LoadingSubtitle = "正在初始化模块...",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

loadGui:Destroy() -- 菜单创建成功，销毁启动弹窗

local TabFly = Window:CreateTab("飞行控制", 4483362458)
local TabFun = Window:CreateTab("特效与动作", 4483362458)

-- ===== 核心变量 =====
local isFlying = false
local flySpeed = 50
local rp, h
local bodyVel, bodyGyro
local flyConn = nil

local isSpinning = false
local spinSpeed = 360
local spinAngle = 0

local fastManEnabled = false
local animSpeedMult = 6
local origWalkSpeed = 16

local function initChar()
    if p.Character then
        rp = p.Character:WaitForChild('HumanoidRootPart')
        h = p.Character:WaitForChild('Humanoid')
        origWalkSpeed = h.WalkSpeed
    end
end
initChar()

-- ===== 飞行核心逻辑 =====
local function stopFly()
    isFlying = false
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if bodyVel then bodyVel:Destroy(); bodyVel = nil end
    if bodyGyro then bodyGyro:Destroy(); bodyGyro = nil end
    if h then
        h.PlatformStand = false
        h:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
    if rp then rp.Velocity = Vector3.zero end
end

local function startFly()
    if not rp or not h then return end
    isFlying = true
    
    rp.Velocity = Vector3.new(0, 30, 0)
    h.PlatformStand = true
    
    bodyVel = Instance.new('BodyVelocity')
    bodyVel.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    bodyVel.Parent = rp
    
    bodyGyro = Instance.new('BodyGyro')
    bodyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    bodyGyro.P = 10000
    bodyGyro.D = 500
    bodyGyro.Parent = rp
    
    flyConn = R.RenderStepped:Connect(function(dt)
        if not isFlying or not rp or not h then return end
        
        pcall(function() rp:SetNetworkOwner(p) end)
        
        local cam = workspace.CurrentCamera
        local look = cam.CFrame.LookVector
        local right = cam.CFrame.RightVector
        
        local moveDir = h.MoveDirection
        local moveVec = (Vector3.new(look.X, 0, look.Z).Unit * moveDir.Z) + (Vector3.new(right.X, 0, right.Z).Unit * moveDir.X)
        
        local vert = 0
        if U:IsKeyDown(Enum.KeyCode.Space) then vert = 1
        elseif U:IsKeyDown(Enum.KeyCode.LeftShift) then vert = -1 end
        
        if U.TouchEnabled then
            if look.Y > 0.35 then vert = (look.Y - 0.35) * 2.5
            elseif look.Y < -0.35 then vert = (look.Y + 0.35) * 2.5 end
        end
        
        local finalVel = (moveVec * flySpeed) + Vector3.new(0, vert * flySpeed, 0)
        bodyVel.Velocity = finalVel
        
        local targetCF = CFrame.lookAt(rp.Position, rp.Position + look)
        
        if isSpinning then
            spinAngle = spinAngle + math.rad(spinSpeed * dt)
            targetCF = targetCF * CFrame.Angles(0, spinAngle, 0)
        end
        
        bodyGyro.CFrame = bodyGyro.CFrame:Lerp(targetCF, 0.3)
        h.PlatformStand = true
    end)
end

-- ===== 旋转/动画循环 =====
R.Heartbeat:Connect(function(dt)
    -- 地面旋转
    if not isFlying and isSpinning and rp then
        spinAngle = spinAngle + math.rad(spinSpeed * dt)
        rp.CFrame = rp.CFrame * CFrame.Angles(0, spinAngle, 0)
    end
    
    -- 极速动画
    if fastManEnabled and h then
        local slowSpeed = math.max(1, origWalkSpeed / 5)
        if h.WalkSpeed > slowSpeed then h.WalkSpeed = slowSpeed end
        
        local animator = h:FindFirstChildOfType('Animator') or h:FindFirstChild('Animator')
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                track:AdjustSpeed(animSpeedMult)
            end
        end
    end
end)

-- ===== UI 配置 =====
TabFly:CreateSection("飞行开关")
local flyToggle = TabFly:CreateToggle({
    Name = "开启飞行 (快捷键 F)",
    CurrentValue = false,
    Flag = "FlyEnabled",
    Callback = function(state)
        if state then startFly() else stopFly() end
    end,
})

TabFly:CreateSection("参数设置")
TabFly:CreateSlider({
    Name = "飞行速度",
    Range = {10, 200},
    Increment = 5,
    Suffix = " Speed",
    CurrentValue = 50,
    Flag = "FlySpeed",
    Callback = function(val) flySpeed = val end,
})

TabFun:CreateSection("高速旋转")
local spinToggle = TabFun:CreateToggle({
    Name = "开启高速旋转",
    CurrentValue = false,
    Flag = "SpinEnabled",
    Callback = function(state)
        isSpinning = state
        if not state then spinAngle = 0 end
    end,
})
TabFun:CreateSlider({
    Name = "旋转速度 (度/秒)",
    Range = {30, 3600},
    Increment = 30,
    Suffix = " 度/秒",
    CurrentValue = 360,
    Flag = "SpinSpeed",
    Callback = function(val) spinSpeed = val end,
})

TabFun:CreateSection("世界上最快的人")
local fastToggle = TabFun:CreateToggle({
    Name = "开启极慢移动 + 超快动作",
    CurrentValue = false,
    Flag = "FastManEnabled",
    Callback = function(state)
        fastManEnabled = state
        if not state and h then
            h.WalkSpeed = origWalkSpeed
            local animator = h:FindFirstChildOfType('Animator') or h:FindFirstChild('Animator')
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:AdjustSpeed(1) end
            end
        end
    end,
})
TabFun:CreateSlider({
    Name = "动画播放倍率",
    Range = {2, 15},
    Increment = 1,
    Suffix = " 倍",
    CurrentValue = 6,
    Flag = "AnimSpeed",
    Callback = function(val) animSpeedMult = val end,
})

-- ===== 快捷键 =====
U.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F then
        local t = Window:GetToggle("开启飞行 (快捷键 F)")
        if t then t:Toggle() end
    end
end)

-- ===== 重生处理 =====
p.CharacterAdded:Connect(function(char)
    if flyToggle then flyToggle:Set(false) end
    stopFly()
    rp = char:WaitForChild('HumanoidRootPart')
    h = char:WaitForChild('Humanoid')
    origWalkSpeed = h.WalkSpeed
    spinAngle = 0
    if fastManEnabled then fastManEnabled = true end
end)

print('WK 辅助 (极速弹窗防重叠版) 已成功加载')
