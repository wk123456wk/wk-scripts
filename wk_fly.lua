-- ===== WK 辅助菜单 (纯净飞行版 + 控制物体 手机版) =====
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

-- 直接加载 Rayfield
local success, Rayfield = pcall(function() return loadstring(game:HttpGet('https://sirius.menu/rayfield'))() end)
if not success or not Rayfield then
    Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/SiriusSoftwareSptd/Rayfield/main/source.lua', true))()
end
if not Rayfield then return end

local Window = Rayfield:CreateWindow({
    Name = "WK 辅助菜单",
    LoadingTitle = "",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local TabFly = Window:CreateTab("飞行控制", 4483362458)
local TabSky = Window:CreateTab("环境修改", 4483362458)
local TabFun = Window:CreateTab("特效与动作", 4483362458)

-- ===== 核心变量 =====
local flying = false
local flySpeed = 50
local height = 0

local isSpinning = false
local spinSpeed = 360
local spinAngle = 0

local fastManEnabled = false
local animSpeedMult = 6
local origWalkSpeed = 16

local rp, h
local mouse = p:GetMouse()
local function initChar()
    if p.Character then
        rp = p.Character:WaitForChild('HumanoidRootPart')
        h = p.Character:WaitForChild('Humanoid')
        origWalkSpeed = h.WalkSpeed
    end
end
initChar()

-- ==========================================
-- 飞天核心逻辑
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

-- ==========================================
-- 彩虹天空盒逻辑
-- ==========================================
local origSky = {}
local function toggleSkybox(state)
    local sky = Lighting:FindFirstChild('Sky')
    if not sky then sky = Instance.new('Sky', Lighting) end
    if state then
        origSky.Bk = sky.SkyboxBk or ""; origSky.Dn = sky.SkyboxDn or ""; origSky.Ft = sky.SkyboxFt or ""
        origSky.Lf = sky.SkyboxLf or ""; origSky.Rt = sky.SkyboxRt or ""; origSky.Up = sky.SkyboxUp or ""
        local id = "rbxassetid://207358036"
        sky.SkyboxBk = id; sky.SkyboxDn = id; sky.SkyboxFt = id; sky.SkyboxLf = id; sky.SkyboxRt = id; sky.SkyboxUp = id
    else
        sky.SkyboxBk = origSky.Bk; sky.SkyboxDn = origSky.Dn; sky.SkyboxFt = origSky.Ft
        sky.SkyboxLf = origSky.Lf; sky.SkyboxRt = origSky.Rt; sky.SkyboxUp = origSky.Up
    end
end

-- ==========================================
-- 控制物体 (悬浮窗开关控制 + 吸附模式, 手机可用)
-- ==========================================
local ctrlEnabled = false   -- 物体控制总开关
local adsorbEnabled = false -- 吸附模式: 自动抓取最近的物体
local ctrlPart = nil
local ctrlBP, ctrlBAV, ctrlSB = nil, nil, nil
local ctrlHoverLow, ctrlHoverHigh = 5.7, 7.2 -- 悬浮弹跳的两个高度
local adsorbRadius = 40 -- 吸附搜索半径

local rainbowColors = {
    Color3.fromRGB(255, 0, 0),
    Color3.fromRGB(255, 170, 0),
    Color3.fromRGB(255, 255, 0),
    Color3.fromRGB(0, 255, 0),
    Color3.fromRGB(0, 170, 255),
    Color3.fromRGB(170, 0, 255),
    Color3.fromRGB(255, 255, 255),
}

local function releaseCtrlPart()
    if ctrlBP then pcall(function() ctrlBP:Destroy() end); ctrlBP = nil end
    if ctrlBAV then pcall(function() ctrlBAV:Destroy() end); ctrlBAV = nil end
    if ctrlSB then pcall(function() ctrlSB:Destroy() end); ctrlSB = nil end
    if ctrlPart and ctrlPart.Parent then
        pcall(function() ctrlPart.CanCollide = true end)
    end
    ctrlPart = nil
end

local function grabCtrlPart(part)
    releaseCtrlPart()
    ctrlPart = part
    pcall(function() part.CanCollide = false end)

    -- 悬浮定位
    ctrlBP = Instance.new('BodyPosition')
    ctrlBP.Name = 'WK_BP'
    ctrlBP.P = 1000000
    ctrlBP.MaxForce = Vector3.new(100000, 100000, 100000)
    if rp then ctrlBP.Position = rp.Position + Vector3.new(0, ctrlHoverHigh, 0) end
    ctrlBP.Parent = part

    -- 疯狂自转
    ctrlBAV = Instance.new('BodyAngularVelocity')
    ctrlBAV.Name = 'WK_BAV'
    ctrlBAV.P = 1e9
    ctrlBAV.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    ctrlBAV.AngularVelocity = Vector3.new(0, 25, 0)
    ctrlBAV.Parent = part

    -- 随机颜色高亮框
    ctrlSB = Instance.new('SelectionBox')
    ctrlSB.Name = 'WK_SB'
    ctrlSB.Adornee = part
    ctrlSB.Color3 = rainbowColors[math.random(1, #rainbowColors)]
    ctrlSB.Parent = part
end

-- 查找附近最近的可抓取物体 (排除角色部位)
local function findNearestPart(radius)
    if not rp then return nil end
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {p.Character}
    local parts = workspace:GetPartBoundsInRadius(rp.Position, radius, params)
    local best, bestDist = nil, radius
    for _, part in ipairs(parts) do
        if not part.Anchored then
            local model = part:FindFirstAncestorOfClass('Model')
            local isCharPart = model and model:FindFirstChildOfClass('Humanoid') ~= nil
            if not isCharPart then
                local d = (part.Position - rp.Position).Magnitude
                if d < bestDist then
                    best, bestDist = part, d
                end
            end
        end
    end
    return best
end

-- 悬浮弹跳循环 (5.7 <-> 7.2 来回弹跳)
task.spawn(function()
    local up = true
    while true do
        task.wait(0.3)
        if ctrlPart and ctrlPart.Parent and ctrlBP and ctrlBP.Parent and rp and rp.Parent then
            local yOff = up and ctrlHoverHigh or ctrlHoverLow
            ctrlBP.Position = rp.Position + Vector3.new(0, yOff, 0)
            pcall(function() ctrlPart.CanCollide = false end)
            up = not up
        end
    end
end)

-- 吸附模式循环: 手里没物体时自动抓最近的
task.spawn(function()
    while true do
        task.wait(0.5)
        if adsorbEnabled and rp and rp.Parent then
            if not (ctrlPart and ctrlPart.Parent and ctrlBP and ctrlBP.Parent) then
                local part = findNearestPart(adsorbRadius)
                if part then grabCtrlPart(part) end
            end
        end
    end
end)

-- ==========================================
-- 主循环 (飞行 / 旋转 / 动画)
-- ==========================================
R.Heartbeat:Connect(function(dt)
    -- 旋转角度累加
    if isSpinning then spinAngle = spinAngle + math.rad(spinSpeed * dt) else spinAngle = 0 end

    -- 飞行主逻辑
    if flying and rp then
        local cam = workspace.CurrentCamera
        local look = cam.CFrame.LookVector
        
        -- 角色朝向视角，叠加旋转
        local targetCF = CFrame.new(rp.Position, rp.Position + look)
        if isSpinning then targetCF = targetCF * CFrame.Angles(0, spinAngle, 0) end
        rp.CFrame = targetCF
        
        -- 移动计算
        local fwdWorld = Vector3.new(look.X, 0, look.Z)
        if fwdWorld.Magnitude > 0 then fwdWorld = fwdWorld.Unit else fwdWorld = Vector3.new(0,0,-1) end
        local md = h.MoveDirection
        local mag = md.Magnitude
        
        if mag > 0.1 then
            local forwardInput = md:Dot(fwdWorld)
            local stickMag = math.min(math.abs(forwardInput), 1)
            if stickMag > 0.1 then
                local dir = fwdWorld * (forwardInput > 0 and 1 or -1)
                local hDisplacement = dir * flySpeed * stickMag * dt
                -- 视角上下控制升降
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
        rp.Velocity = Vector3.zero
        h.PlatformStand = true
    end
    
    -- 地面旋转
    if not flying and isSpinning and rp then
        rp.CFrame = rp.CFrame * CFrame.Angles(0, math.rad(spinSpeed * dt), 0)
    end
    
    -- 极速动作（世界上最快的人）
    if fastManEnabled and h then
        h.WalkSpeed = math.max(1, origWalkSpeed / 5)
        local animator = h:FindFirstChildOfType('Animator') or h:FindFirstChild('Animator')
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do 
                track:AdjustSpeed(animSpeedMult) 
            end
        end
    end
end)

-- ==========================================
-- UI 配置 (全部悬浮窗开关, 手机可用)
-- ==========================================
TabFly:CreateSection("飞行开关")
local flyToggle = TabFly:CreateToggle({
    Name = "开启飞行 (电脑端快捷键 F)",
    CurrentValue = false,
    Callback = function(state) if state then enableFly() else disableFly() end end,
})

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

TabFun:CreateSection("控制物体 (手机用按钮/吸附)")
TabFun:CreateToggle({
    Name = "开启物体控制 (电脑端可按Q抓取)",
    CurrentValue = false,
    Callback = function(state)
        ctrlEnabled = state
        if not state then releaseCtrlPart() end
    end,
})
TabFun:CreateToggle({
    Name = "开启吸附 (自动抓最近物体)",
    CurrentValue = false,
    Callback = function(state)
        adsorbEnabled = state
        if not state then releaseCtrlPart() end
    end,
})
TabFun:CreateButton({
    Name = "抓取最近的物体",
    Callback = function()
        local part = findNearestPart(adsorbRadius)
        if part then grabCtrlPart(part) end
    end,
})
TabFun:CreateButton({
    Name = "释放当前物体",
    Callback = function() releaseCtrlPart() end,
})

TabFun:CreateSection("高速旋转")
TabFun:CreateToggle({
    Name = "开启高速旋转",
    CurrentValue = false,
    Callback = function(state) isSpinning = state; if not state then spinAngle = 0 end end,
})
TabFun:CreateSlider({
    Name = "旋转速度",
    Range = {30, 3600}, Increment = 30, CurrentValue = 360,
    Callback = function(val) spinSpeed = val end,
})

TabFun:CreateSection("世界上最快的人")
TabFun:CreateToggle({
    Name = "开启极慢移动 + 超快动作",
    CurrentValue = false,
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
    Range = {2, 15}, Increment = 1, CurrentValue = 6,
    Callback = function(val) animSpeedMult = val end,
})

-- ===== 快捷键 (仅电脑端, 手机请用悬浮窗开关) =====
U.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F then
        flyToggle:Set(not flying)
    end
    -- 按Q抓取/释放物体
    if input.KeyCode == Enum.KeyCode.Q and ctrlEnabled then
        local target = mouse.Target
        if target and target:IsA('BasePart') and not target.Anchored then
            if target == ctrlPart then
                releaseCtrlPart()
            else
                grabCtrlPart(target)
            end
        end
    end
end)

-- ===== 角色重生处理 =====
p.CharacterAdded:Connect(function(char)
    if flyToggle then flyToggle:Set(false) end
    disableFly()
    releaseCtrlPart()
    rp = char:WaitForChild('HumanoidRootPart')
    h = char:WaitForChild('Humanoid')
    origWalkSpeed = h.WalkSpeed
    spinAngle = 0
end)

print('WK 纯净飞行版 (控制物体手机版) 已加载')
