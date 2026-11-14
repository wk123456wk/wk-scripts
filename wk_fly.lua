-- ===== WK 飞天 + 旋转 + 极速动画 (Rayfield 整合版) =====
local p = game:GetService('Players').LocalPlayer
local R = game:GetService('RunService')
local U = game:GetService('UserInputService')

-- 清理旧UI防冲突
for _, obj in ipairs(game:GetService('CoreGui'):GetChildren()) do
    if obj.Name == 'WK_FlyGui' then obj:Destroy() end
end
for _, obj in ipairs(p:WaitForChild('PlayerGui'):GetChildren()) do
    if obj.Name == 'WK_FlyGui' then obj:Destroy() end
end

-- 加载 Rayfield
local success, Rayfield = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)
if not success or not Rayfield then
    Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/SiriusSoftwareSptd/Rayfield/main/source.lua', true))()
end
if not Rayfield then warn('Rayfield UI 加载失败'); return end

local Window = Rayfield:CreateWindow({
    Name = "WK 辅助菜单",
    LoadingTitle = "WK 辅助加载中",
    LoadingSubtitle = "正在初始化模块...",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local TabFly = Window:CreateTab("飞行控制", 4483362458)
local TabFun = Window:CreateTab("特效与动作", 4483362458)

-- ===== 核心变量 =====
-- 飞行相关
local isFlying = false
local flySpeed = 50
local rp, h
local bodyVel, bodyGyro
local flyConn = nil

-- 旋转相关
local isSpinning = false
local spinSpeed = 360
local spinAngle = 0

-- 极速动画相关 (世界上最快的人)
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

        -- 飞行时的朝向处理
        local targetCF = CFrame.lookAt(rp.Position, rp.Position + look)

        -- 如果开启了旋转，将旋转角度叠加到视角朝向上
        if isSpinning then
            spinAngle = spinAngle + math.rad(spinSpeed * dt)
            targetCF = targetCF * CFrame.Angles(0, spinAngle, 0)
        end

        bodyGyro.CFrame = bodyGyro.CFrame:Lerp(targetCF, 0.3)
        h.PlatformStand = true
    end)
end

-- ===== 旋转核心逻辑 (地面/空中独立生效) =====
R.Heartbeat:Connect(function(dt)
    if not isSpinning or isFlying or not rp then return end
    -- 如果在飞行，旋转在飞行逻辑里处理。如果不飞行，这里独立旋转。
    spinAngle = spinAngle + math.rad(spinSpeed * dt)
    rp.CFrame = rp.CFrame * CFrame.Angles(0, spinAngle, 0)
end)

-- ===== 极速动画核心逻辑 =====
local function applyFastMan(enable)
    if not h then return end
    if enable then
        origWalkSpeed = h.WalkSpeed
    else
        h.WalkSpeed = origWalkSpeed
        local animator = h:FindFirstChildOfType('Animator') or h:FindFirstChild('Animator')
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                track:AdjustSpeed(1)
            end
        end
    end
end

R.Heartbeat:Connect(function(dt)
    if fastManEnabled and h then
        -- 1. 强制降低移动速度 (最低1)
        local slowSpeed = math.max(1, origWalkSpeed / 5)
        if h.WalkSpeed > slowSpeed then
            h.WalkSpeed = slowSpeed
        end

        -- 2. 疯狂加速动画播放速度
        local animator = h:FindFirstChildOfType('Animator') or h:FindFirstChild('Animator')
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                track:AdjustSpeed(animSpeedMult)
            end
        end
    end
end)

-- ===== 飞行 UI =====
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

-- ===== 特效与动作 UI =====
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
        applyFastMan(state)
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
        flyToggle:Set(not isFlying)
    end
end)

-- ===== 角色重生处理 =====
p.CharacterAdded:Connect(function(char)
    if flyToggle then flyToggle:Set(false) end
    stopFly()
    rp = char:WaitForChild('HumanoidRootPart')
    h = char:WaitForChild('Humanoid')
    origWalkSpeed = h.WalkSpeed
    spinAngle = 0

    if fastManEnabled then
        applyFastMan(true)
    end
end)

print('WK 整合版 (飞行 + 旋转 + 极速动作) 已加载')
