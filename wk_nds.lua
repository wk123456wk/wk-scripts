-- ===== WK 总控 (去雾白昼 + 怪物三级测距 · 总开关 · 零联网秒启动) =====
-- 适用: 「不要停止 / make sure to drive fast」等雨夜浓雾黑夜地图
-- 特点: 不加载任何UI库 / 不联网 / 无启动动画, 执行即出开关并生效
-- 防闪烁: 雾/暗化效果整体移出渲染树 + Lighting标量用属性变更即时反制 + 怪物测距降频
-- 总开关: 一键开启/关闭「去雾白昼」与「怪物三级测距」全部能力, 关闭恢复夜景

local Lighting   = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local CoreGui    = game:GetService("CoreGui")
local Players    = game:GetService("Players")
local p          = Players.LocalPlayer
local PlayerGui  = p:WaitForChild("PlayerGui")

-- 防多开: 先让上一份实例停下并恢复
if _G.WK_Day_Cleanup then pcall(_G.WK_Day_Cleanup) end
for _, parent in ipairs({CoreGui, PlayerGui}) do
    for _, obj in ipairs(parent:GetChildren()) do
        if obj.Name == "WK_DayToggle" then pcall(function() obj:Destroy() end) end
    end
end

-- ==========================================
-- 配置
-- ==========================================
-- ① 目标「白天无雾」标量 (只在被地图改动时写回, 不每帧重写)
local DAY = {
    ClockTime            = 12,
    Brightness           = 2,
    FogStart             = 0,
    FogEnd               = 1000000,
    Ambient              = Color3.fromRGB(200, 200, 200),
    OutdoorAmbient       = Color3.fromRGB(200, 200, 200),
    ColorShift_Top       = Color3.fromRGB(255, 255, 255),
    ColorShift_Bottom    = Color3.fromRGB(255, 255, 255),
    ExposureCompensation = 0,
}

-- ② 雾/暗化/夜空效果类 → 整体移出渲染树 (地图改不到, 根除闪烁)
local FX = {
    Atmosphere = true, ColorCorrectionEffect = true, BlurEffect = true,
    DepthOfFieldEffect = true, SunRaysEffect = true, BloomEffect = true, Sky = true,
}

-- ③ 怪物距离三级 (更保守): 红<25 / 黄25-60 / 绿>60
local RED_D, YELLOW_D = 25, 60
local COL = {
    red    = Color3.fromRGB(210, 55, 55),
    yellow = Color3.fromRGB(215, 165, 45),
    green  = Color3.fromRGB(40, 175, 95),
    gray   = Color3.fromRGB(70, 74, 80),
}
-- 通用怪物识别: 带Humanoid的非玩家模型 + 常见怪物名关键词
local MONSTER_HINTS = {
    "monster","creature","enemy","zombie","killer","beast","entity","rake",
    "pursuer","stalker","horror","demon","ghost","alien","boss","it","the ",
    "怪","尸","幽灵","恶魔","追击","异形",
}

-- ==========================================
-- 状态
-- ==========================================
local ON = false
local dayOn = false
local backup, stash = nil, {}
local guardConns, fxConns = {}, {}
local hbConn, curHl, acc = nil, nil, 0

local function setP(obj, prop, val) pcall(function() obj[prop] = val end) end
local function getP(obj, prop)
    local ok, v = pcall(function() return obj[prop] end)
    if ok then return v end
end
local function sameVal(a, b)
    if a == nil or b == nil then return a == b end
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 0.001 end
    local ok, eq = pcall(function() return a == b end)
    return ok and eq
end

-- ==========================================
-- UI: 一个总开关按钮 + 一个距离状态条
-- ==========================================
local gui = Instance.new("ScreenGui")
gui.Name = "WK_DayToggle"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
local uiOk = pcall(function() gui.Parent = CoreGui end)
if not uiOk or not gui.Parent then gui.Parent = PlayerGui end

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(0, 148, 0, 44)
btn.Position = UDim2.new(0, 12, 0.30, 0)
btn.BackgroundColor3 = Color3.fromRGB(40, 44, 48)
btn.BorderSizePixel = 0
btn.Font = Enum.Font.GothamBold
btn.Text = "WK 总开关：关"
btn.TextColor3 = Color3.fromRGB(230, 230, 230)
btn.TextSize = 14
btn.Parent = gui
Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 22)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 148, 0, 30)
statusLabel.Position = UDim2.new(0, 12, 0.30, 50)
statusLabel.BackgroundColor3 = COL.gray
statusLabel.BorderSizePixel = 0
statusLabel.Font = Enum.Font.GothamBold
statusLabel.Text = "未发现怪物"
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.TextSize = 13
statusLabel.Parent = gui
Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 8)

local function setStatus(text, col)
    statusLabel.Text = text
    statusLabel.BackgroundColor3 = col
end
local function refresh()
    if ON then
        btn.Text = "WK 总开关：开"
        btn.BackgroundColor3 = COL.green
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        statusLabel.Visible = true
    else
        btn.Text = "WK 总开关：关"
        btn.BackgroundColor3 = Color3.fromRGB(40, 44, 48)
        btn.TextColor3 = Color3.fromRGB(230, 230, 230)
        statusLabel.Visible = false
        setStatus("未发现怪物", COL.gray)
    end
end

-- ==========================================
-- 能力A: 去雾白昼 (移出效果 + 标量反制)
-- ==========================================
local function moveOut(obj)
    for _, it in ipairs(stash) do if it.obj == obj then return end end
    local par = obj.Parent
    table.insert(stash, { obj = obj, parent = par })
    pcall(function() obj.Parent = nil end)
end
local function sweepEffects()
    for _, obj in ipairs(Lighting:GetDescendants()) do
        if FX[obj.ClassName] then moveOut(obj) end
    end
    local cam = Workspace.CurrentCamera
    if cam then
        for _, obj in ipairs(cam:GetDescendants()) do
            if FX[obj.ClassName] then moveOut(obj) end
        end
    end
end
local function moveBackAll()
    for _, it in ipairs(stash) do
        local ok = pcall(function() it.obj.Parent = it.parent or Lighting end)
        if not ok then pcall(function() it.obj.Parent = Lighting end) end
    end
    stash = {}
end

local function enableDay()
    if dayOn then return end
    dayOn = true
    backup = {}
    for k in pairs(DAY) do backup[k] = getP(Lighting, k) end
    for k, v in pairs(DAY) do setP(Lighting, k, v) end   -- 首次写一次
    sweepEffects()                                       -- 雾/夜空/暗化效果移出渲染树
    -- 标量: 只在被地图改动时即时写回 (零轮询, 渲染帧永远看到白天值)
    for k, v in pairs(DAY) do
        pcall(function()
            local c = Lighting:GetPropertyChangedSignal(k):Connect(function()
                if not dayOn then return end
                if not sameVal(getP(Lighting, k), v) then setP(Lighting, k, v) end
            end)
            table.insert(guardConns, c)
        end)
    end
    -- 地图动态新建的雾/暗化效果立刻移走
    pcall(function()
        table.insert(fxConns, Lighting.DescendantAdded:Connect(function(obj)
            if dayOn and FX[obj.ClassName] then moveOut(obj) end
        end))
    end)
    pcall(function()
        local cam = Workspace.CurrentCamera
        if cam then
            table.insert(fxConns, cam.DescendantAdded:Connect(function(obj)
                if dayOn and FX[obj.ClassName] then moveOut(obj) end
            end))
        end
    end)
end

local function disableDay()
    if not dayOn then return end
    dayOn = false
    for _, c in ipairs(guardConns) do pcall(function() c:Disconnect() end) end
    guardConns = {}
    for _, c in ipairs(fxConns) do pcall(function() c:Disconnect() end) end
    fxConns = {}
    if backup then
        for k, v in pairs(backup) do if v ~= nil then setP(Lighting, k, v) end end
        backup = nil
    end
    moveBackAll()
end

-- ==========================================
-- 能力B: 怪物距离三级测距 + 高亮
-- ==========================================
local function isMonster(model)
    if Players:GetPlayerFromCharacter(model) then return false end
    if model:FindFirstChildOfClass("Humanoid") then return true end
    local n = string.lower(model.Name)
    for _, h in ipairs(MONSTER_HINTS) do
        if string.find(n, h, 1, true) then return true end
    end
    return false
end
local function rootOf(model)
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end
local function myPos()
    local char = p.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp.Position end
    local cam = Workspace.CurrentCamera
    if cam then return cam.CFrame.Position end
    return Vector3.zero
end
local function grade(d)
    if d < RED_D then return "红", "危险", COL.red end
    if d < YELLOW_D then return "黄", "注意", COL.yellow end
    return "绿", "安全", COL.green
end
local function clearHl()
    if curHl then pcall(function() curHl:Destroy() end); curHl = nil end
end
local function scan()
    local me = myPos()
    local best, bestD = nil, math.huge
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and isMonster(obj) then
            local r = rootOf(obj)
            if r then
                local d = (r.Position - me).Magnitude
                if d < bestD then bestD, best = d, obj end
            end
        end
    end
    clearHl()
    if not best then setStatus("未发现怪物", COL.gray); return end
    local g, word, col = grade(bestD)
    setStatus(g .. "·" .. word .. "  " .. math.floor(bestD) .. "m", col)
    pcall(function()
        local hl = Instance.new("Highlight")
        hl.Name = "WK_MonsterHL"
        hl.Adornee = best
        hl.FillColor = col
        hl.OutlineColor = col
        hl.FillTransparency = 0.5
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = best
        curHl = hl
    end)
end
local function startProx()
    if hbConn then return end
    acc = 0
    hbConn = RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc >= 0.4 then acc = 0; pcall(scan) end
    end)
    task.defer(function() if ON then pcall(scan) end end)
end
local function stopProx()
    if hbConn then pcall(function() hbConn:Disconnect() end); hbConn = nil end
    clearHl()
end

-- ==========================================
-- 总开关: 一键开关全部能力
-- ==========================================
local function setOn(v)
    ON = v
    if v then
        enableDay()
        startProx()
    else
        stopProx()
        disableDay()
    end
    refresh()
end

local lastTap = 0
btn.Activated:Connect(function()
    if tick() - lastTap < 0.2 then return end
    lastTap = tick()
    setOn(not ON)
end)

_G.WK_Day_Cleanup = function()
    pcall(stopProx)
    pcall(disableDay)
    pcall(function() gui:Destroy() end)
end

-- 默认开启: 执行即生效, 点一下总开关全关并恢复夜景
setOn(true)

print("WK 总控 (去雾白昼 + 怪物三级测距 · 防闪烁) 已就绪 [WK_DAY_V2]")
