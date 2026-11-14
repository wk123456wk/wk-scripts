-- ===== WK 辅助 (经典飞天统一调速 + 彩虹天空盒) =====
local p = game:GetService('Players').LocalPlayer
local R = game:GetService('RunService')
local U = game:GetService('UserInputService')
local CoreGui = game:GetService('CoreGui')
local PlayerGui = p:WaitForChild('PlayerGui')
local Lighting = game:GetService('Lighting')

-- 清理旧UI
for _, parent in ipairs({CoreGui, PlayerGui}) do
    for _, obj in ipairs(parent:GetChildren()) do
        local name = obj.Name:lower()
        if name:find("rayfield") or name:find("wk_") then pcall(function() obj:Destroy() end) end
    end
end

-- 极速启动弹窗
local loadGui = Instance.new('ScreenGui')
loadGui.Name = 'WK_QuickLoad'
loadGui.DisplayOrder = 999999
loadGui.Parent = CoreGui

local frame = Instance.new('Frame', loadGui)
frame.Size = UDim2.new(0, 200, 0, 60)
frame.Position = UDim2.new(0.5, -100, 0.5, -30)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 8)
Instance.new('UIStroke', frame).Color = Color3.fromRGB(0, 255, 0)

local text = Instance.new('TextLabel', frame)
text.Size = UDim2.new(1, 0, 1, 0)
text.BackgroundTransparency = 1
text.Text = '正在启动 WK 脚本...'
text.TextColor3 = Color3.fromRGB(0, 255, 0)
text.Font = Enum.Font.SourceSansBold
text.TextSize = 16

-- 加载 Rayfield
local success, Rayfield = pcall(function() return loadstring(game:HttpGet('https://sirius.menu/rayfield'))() end)
if not success or not Rayfield then
    Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/SiriusSoftwareSptd/Rayfield/main/source.lua', true))()
end
if not Rayfield then text.Text = '网络错误'; task.wait(3); loadGui:Destroy(); return end

local Window = Rayfield:CreateWindow({
    Name = "WK 辅助菜单",
    LoadingTitle = "加载中...",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})
loadGui:Destroy()

local TabFly = Window:CreateTab("飞行控制", 4483362458)
local TabSky = Window:CreateTab("环境修改", 4483362458)
local TabFun = Window:CreateTab("特效与动作", 4483362458)

-- ===== 核心变量 =====
local flying = false
local flySpeed = 50  -- 统一飞行速度（水平与垂直共用）
local height = 0

local isSpinning = false
local spinSpeed = 360
local spinAngle = 0

local fastManEnabled = false
local animSpeedMult = 6
local origWalkSpeed = 16

local rp, h
local function initChar()
    if p.Character then
        rp = p.Character:WaitForChild('HumanoidRootPart')
        h = p.Character:WaitForChild('Humanoid')
        origWalkSpeed = h.WalkSpeed
    end
end
initChar()

-- ==========================================
-- 经典飞天逻辑 (统一速度)
-- ==========================================
local function enableFly()
    if not rp then return end
    flying = true
    h.PlatformStand = true
    h.AutoRotate = false
    height = rp.Position.Y
end

local function disableFly()
    if not flying then return end
    flying = false
    h.PlatformStand = false
    h.AutoRotate = true
    h:ChangeState(Enum.HumanoidStateType.GettingUp)
    rp.Velocity = Vector3.zero
end

R.Heartbeat:Connect(function(dt)
    -- 飞行主循环
    if flying and rp then
        local cam = workspace.CurrentCamera
        local look = cam.CFrame.LookVector
        
        -- 角色始终面向视角
        rp.CFrame = CFrame.new(rp.Position, rp.Position + look)
        
        local fwdWorld = Vector3.new(look.X, 0, look.Z)
        if fwdWorld.Magnitude > 0 then fwdWorld = fwdWorld.Unit else fwdWorld = Vector3.new(0,0,-1) end
        
        local md = h.MoveDirection
        local mag = md.Magnitude
        
        if mag > 0.1 then
            local forwardInput = md:Dot(fwdWorld)
            local stickMag = math.min(math.abs(forwardInput), 1)
            
            if stickMag > 0.1 then
                local dir = fwdWorld * (forwardInput > 0 and 1 or -1)
                -- 统一使用 flySpeed 计算水平位移
                local hDisplacement = dir * flySpeed * stickMag * dt
                
                -- 视角上下控制升降，统一使用 flySpeed
                local vert = flySpeed * look.Y * stickMag * dt
                height = height + vert
                
                rp.Position = rp.Position + Vector3.new(hDisplacement.X, 0, hDisplacement.Z)
                rp.Position = Vector3.new(rp.Position.X, height, rp.Position.Z)
            else
                rp.Position = Vector3.new(rp.Position.X, height, rp.Position.Z)
            end
        else
            rp.Position = Vector3.new(rp.Position.X, height, rp.Position.Z)
        end
        
        rp.Velocity = Vector3.new(0,0,0)
        h.PlatformStand = true
    end
    
    -- 地面旋转
    if not flying and isSpinning and rp then
        spinAngle = spinAngle + math.rad(spinSpeed * dt)
        rp.CFrame = rp.CFrame * CFrame.Angles(0, spinAngle, 0)
    end
    
    -- 极速动作（世界上最快的人）
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

-- ==========================================
-- 彩虹天空盒逻辑
-- ==========================================
local skyboxEnabled = false
local origSky = {}
local function toggleSkybox(state)
    local sky = Lighting:FindFirstChild('Sky')
    if not sky then sky = Instance.new('Sky', Lighting) end
    
    if state then
        origSky.Bk = sky.SkyboxBk or ""
        origSky.Dn = sky.SkyboxDn or ""
        origSky.Ft = sky.SkyboxFt or ""
        origSky.Lf = sky.SkyboxLf or ""
        origSky.Rt = sky.SkyboxRt or ""
        origSky.Up = sky.SkyboxUp or ""
        
        local id = "rbxassetid://207358036"
        sky.SkyboxBk = id
        sky.SkyboxDn = id
        sky.SkyboxFt = id
        sky.SkyboxLf = id
        sky.SkyboxRt = id
        sky.SkyboxUp = id
    else
        sky.SkyboxBk = origSky.Bk
        sky.SkyboxDn = origSky.Dn
        sky.SkyboxFt = origSky.Ft
        sky.SkyboxLf = origSky.Lf
        sky.SkyboxRt = origSky.Rt
        sky.SkyboxUp = origSky.Up
    end
end

-- ==========================================
-- UI 配置
-- ==========================================
TabFly:CreateSection("经典飞行开关")
local flyToggle = TabFly:CreateToggle({
    Name = "开启飞行 (快捷键 F)",
    CurrentValue = false,
    Callback = function(state) if state then enableFly() else disableFly() end end,
})

-- 统一为一个速度滑块
TabFly:CreateSlider({
    Name = "飞行速度",
    Range = {10, 200}, Increment = 5, CurrentValue = 50,
    Callback = function(val) flySpeed = val end,
})

TabSky:CreateSection("环境设置")
TabSky:CreateToggle({
    Name = "开启彩虹天空盒",
    CurrentValue = false,
    Callback = function(state) toggleSkybox(state) end,
})

TabFun:CreateSection("高速旋转")
TabFun:CreateToggle({
    Name = "开启高速旋转", CurrentValue = false,
    Callback = function(state) isSpinning = state; if not state then spinAngle = 0 end end,
})
TabFun:CreateSlider({
    Name = "旋转速度", Range = {30, 3600}, Increment = 30, CurrentValue = 360,
    Callback = function(val) spinSpeed = val end,
})

TabFun:CreateSection("世界上最快的人")
TabFun:CreateToggle({
    Name = "开启极慢移动 + 超快动作", CurrentValue = false,
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
    Name = "动画播放倍率", Range = {2, 15}, Increment = 1, CurrentValue = 6,
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

-- ===== 角色重生处理 =====
p.CharacterAdded:Connect(function(char)
    if flyToggle then flyToggle:Set(false) end
    disableFly()
    rp = char:WaitForChild('HumanoidRootPart')
    h = char:WaitForChild('Humanoid')
    origWalkSpeed = h.WalkSpeed
    spinAngle = 0
end)

print('WK 统一调速版已加载')
