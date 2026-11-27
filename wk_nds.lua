-- ===== WK 总控 + 独立防怪 (去雾白昼 + 怪物三级测距 + 防怪靠近 · 零联网秒启动) =====
-- 适用: 「不要停止 / make sure to drive fast」等雨夜浓雾黑夜地图
-- 特点: 不加载任何UI库 / 不联网 / 无启动动画, 执行即出开关并生效
-- 防闪烁: 雾/暗化效果整体移出渲染树 + Lighting标量用属性变更即时反制 + 怪物测距降频
-- 总开关: 一键开启/关闭「去雾白昼」与「怪物三级测距」, 关闭恢复夜景
-- 独立防怪: 单独的「防怪靠近」按钮, 不属于总开关; 怪物近身尝试推离, 变红自动把自己传到红色范围外
-- V3 修复「距离恒显示2m」:
--   ① 玩家坐标只认角色 HumanoidRootPart, 拿不到就显示"等待角色"而非回退相机位置(旧版相机回退会给出恒定错值)
--   ② 扫描排除「所有玩家角色 + 角色嵌套子Model + 玩家乘坐的载具」, 避免把贴身的车/自身当怪物
--   ③ 排除带 VehicleSeat/Seat 或名字含载具词的Model, 根治 "Monster Truck" 命中 monster 关键词的误判
--   ④ 状态条附带识别到的目标名字 + 控制台打印, 一眼可核对到底把谁当成了怪物
-- FE说明: 客户端改不动服务端怪物, 故"让怪物无法靠近"以"自己自动弹开"为可靠实现,
--         另叠加 best-effort 推离(抢到网络所有权时才明显生效), 且不改写怪物CFrame以免距离读数失真
--   [WK_DAY_V3]

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

-- ③ 怪物距离三级 (更保守): 红<25 / 黄25-60 / 绿>60 (单位 stud, 脚本沿称 m)
local RED_D, YELLOW_D = 25, 60
local COL = {
    red    = Color3.fromRGB(210, 55, 55),
    yellow = Color3.fromRGB(215, 165, 45),
    green  = Color3.fromRGB(40, 175, 95),
    gray   = Color3.fromRGB(70, 74, 80),
}
-- 通用怪物识别: 带Humanoid的非玩家模型(最可靠) + 明确的怪物名关键词
-- 注意: 不放 "it"/"the" 这类短词, 否则会误匹配 Building/Light/Exit 等普通物件
local MONSTER_HINTS = {
    "monster","creature","enemy","zombie","killer","beast","entity","rake",
    "pursuer","stalker","horror","demon","ghost","alien","seek","figure",
    "怪","尸","幽灵","恶魔","追击","异形","巨兽","妖",
}
-- 载具排除: 驾驶地图里 "Monster Truck" 会命中 monster, 必须排除掉
local VEHICLE_HINTS = { "truck","vehicle","kart","bike","bus","cart","载具","卡车","汽车","摩托" }

-- ④ 独立防怪参数
local GUARD_R     = 120   -- 扫描缓存半径
local BLOCK_D     = 60    -- 进入此范围开始尝试推离 (best-effort)
local SAFE_D      = 75    -- 红色时把自己传到距怪物 75 (落在红区外的绿区)
local PUSH_SPEED  = 60    -- 推离速度
local TP_COOLDOWN = 1.5   -- 传送冷却(秒), 防止连续瞬移抖动

-- ==========================================
-- 状态
-- ==========================================
local ON = false          -- 总开关 (去雾白昼 + 测距可视化)
local GUARD_ON = false    -- 独立防怪开关 (不属于总开关, 默认关: 会传送玩家, 需手动开)
local dayOn = false
local backup, stash = nil, {}
local guardConns, fxConns = {}, {}
local hbConn, charConn, curHl, acc = nil, nil, nil, 0
local nearList = {}       -- 近处怪物缓存: {{root, dist}, ...}
local lastTP = 0          -- 上次自动传送时间
local lastPrinted = nil   -- 上次打印的目标名(避免刷屏)

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
-- UI: 总开关按钮 + 距离状态条 + 独立防怪按钮
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
statusLabel.TextScaled = true
statusLabel.Parent = gui
Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 8)

-- 独立防怪按钮 (与总开关互不隶属, 单独开关、单独工作)
local guardBtn = Instance.new("TextButton")
guardBtn.Size = UDim2.new(0, 148, 0, 44)
guardBtn.Position = UDim2.new(0, 12, 0.30, 90)
guardBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 48)
guardBtn.BorderSizePixel = 0
guardBtn.Font = Enum.Font.GothamBold
guardBtn.Text = "防怪靠近：关"
guardBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
guardBtn.TextSize = 14
guardBtn.Parent = gui
Instance.new("UICorner", guardBtn).CornerRadius = UDim.new(0, 22)

local function setStatus(text, col)
    statusLabel.Text = text
    statusLabel.BackgroundColor3 = col
end
local function syncVisible()
    -- 两个开关任一开启, 都能看到距离状态, 便于核对识别是否正确
    statusLabel.Visible = (ON or GUARD_ON)
end
local function refresh()
    if ON then
        btn.Text = "WK 总开关：开"
        btn.BackgroundColor3 = COL.green
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
        btn.Text = "WK 总开关：关"
        btn.BackgroundColor3 = Color3.fromRGB(40, 44, 48)
        btn.TextColor3 = Color3.fromRGB(230, 230, 230)
        if not GUARD_ON then setStatus("未发现怪物", COL.gray) end
    end
    syncVisible()
end
local function refreshGuard()
    if GUARD_ON then
        guardBtn.Text = "防怪靠近：开"
        guardBtn.BackgroundColor3 = COL.red
        guardBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
        guardBtn.Text = "防怪靠近：关"
        guardBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 48)
        guardBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
    end
    syncVisible()
end

-- ==========================================
-- 能力A: 去雾白昼 (移出效果 + 标量反制) —— 原样保留
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
-- 能力B: 怪物扫描 + 三级测距 + 高亮 (V3 距离修复)
--        同时把"近处怪物缓存"喂给能力C, 全脚本只扫一次全图
-- ==========================================
-- 玩家坐标: 只认角色 HumanoidRootPart; 拿不到返回 nil(绝不回退相机)
local function myHrp()
    local char = p.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") and hrp.Parent then return hrp end
    return nil
end

-- 构建「玩家相关」排除集: 所有玩家角色 + 正在乘坐的载具
local function buildCharSet()
    local set = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        local ch = plr.Character
        if ch then
            set[ch] = true
            local hum = ch:FindFirstChildOfClass("Humanoid")
            if hum and hum.SeatPart then
                local vm = hum.SeatPart:FindFirstAncestorOfClass("Model")
                if vm then set[vm] = true end
            end
        end
    end
    return set
end
-- 候选是否与玩家相关(自身 / 角色嵌套子Model / 角色祖先Model)
local function relatedToPlayer(model, set)
    if set[model] then return true end
    for ch in pairs(set) do
        if model:IsDescendantOf(ch) or ch:IsDescendantOf(model) then return true end
    end
    return false
end
local function looksLikeVehicle(model)
    local n = string.lower(model.Name)
    for _, h in ipairs(VEHICLE_HINTS) do
        if string.find(n, h, 1, true) then return true end
    end
    if model:FindFirstChildOfClass("VehicleSeat") then return true end
    if model:FindFirstChildOfClass("Seat") then return true end
    return false
end
local function isMonster(model, set)
    if relatedToPlayer(model, set) then return false end
    if Players:GetPlayerFromCharacter(model) then return false end
    if looksLikeVehicle(model) then return false end
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
local function grade(d)
    if d < RED_D then return "红", COL.red end
    if d < YELLOW_D then return "黄", COL.yellow end
    return "绿", COL.green
end
local function clearHl()
    if curHl then pcall(function() curHl:Destroy() end); curHl = nil end
end

-- best-effort 推离: 只设"远离玩家"的速度, 绝不改写怪物 CFrame (避免本地读数失真/抽搐)
local function pushAway(root, me)
    pcall(function() root:SetNetworkOwner(p) end)
    local away = Vector3.new(root.Position.X - me.X, 0, root.Position.Z - me.Z)
    if away.Magnitude > 0.001 then
        pcall(function()
            root.AssemblyLinearVelocity = away.Unit * PUSH_SPEED
            root.Velocity = away.Unit * PUSH_SPEED
        end)
    end
end

local function scan()
    local hrp = myHrp()
    if not hrp then
        -- 角色未就绪: 不扫描, 明确显示等待, 绝不给一个假距离
        clearHl()
        nearList = {}
        setStatus("等待角色…", COL.gray)
        return
    end
    local me = hrp.Position
    local set = buildCharSet()
    local best, bestD, bestRoot = nil, math.huge, nil
    local list = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and isMonster(obj, set) then
            local r = rootOf(obj)
            if r then
                local d = (r.Position - me).Magnitude
                if d < bestD then bestD, best, bestRoot = d, obj, r end
                if d < GUARD_R then table.insert(list, { root = r, dist = d }) end
            end
        end
    end
    nearList = list

    -- 能力C(低频层): 对黄区内怪物尝试推离 (仅防怪开启时)
    if GUARD_ON then
        for _, it in ipairs(list) do
            if it.dist < BLOCK_D and it.root.Parent then
                pushAway(it.root, me)
            end
        end
    end

    -- 能力B可视化: 任一开关开启都显示
    if ON or GUARD_ON then
        clearHl()
        if not best then setStatus("未发现怪物", COL.gray); return end
        local g, col = grade(bestD)
        local nm = best.Name
        if #nm > 10 then nm = string.sub(nm, 1, 10) .. "…" end
        setStatus(g .. "·" .. math.floor(bestD) .. "m ·" .. nm, col)
        -- 目标变化时打印一次, 方便核对识别是否正确
        if best.Name ~= lastPrinted then
            lastPrinted = best.Name
            print("[WK] 最近目标: " .. best.Name .. " @ " .. math.floor(bestD) .. "m")
        end
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
end

-- ==========================================
-- 能力C: 独立防怪 (红色时自动把自己传送到红色范围外)
-- ==========================================
local function teleportOut(root, hrp)
    local away = Vector3.new(hrp.Position.X - root.Position.X, 0, hrp.Position.Z - root.Position.Z)
    if away.Magnitude < 0.001 then away = Vector3.new(1, 0, 0) end
    away = away.Unit
    -- 落到"怪物→我"方向上、距怪物 SAFE_D 的位置(绿区), 保持当前高度并微抬防卡地
    local dest = Vector3.new(
        root.Position.X + away.X * SAFE_D,
        hrp.Position.Y + 2,
        root.Position.Z + away.Z * SAFE_D
    )
    pcall(function()
        hrp.CFrame = CFrame.new(dest)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.Velocity = Vector3.zero
    end)
end

-- 每帧层: 用实时坐标重算最近距离, 红色立即(带冷却)自动闪避, 可靠兜底
local function guardStep()
    local hrp = myHrp()
    if not hrp then return end
    local me = hrp.Position
    local minRoot, minD = nil, math.huge
    for _, it in ipairs(nearList) do
        local r = it.root
        if r and r.Parent then
            local d = (r.Position - me).Magnitude
            if d < minD then minD, minRoot = d, r end
        end
    end
    if minRoot and minD < RED_D and tick() - lastTP > TP_COOLDOWN then
        lastTP = tick()
        teleportOut(minRoot, hrp)
    end
end

-- 单一循环: 只要「总开关」或「独立防怪」任一开启就运行; 互不隶属
local function ensureLoop()
    local need = ON or GUARD_ON
    if need and not hbConn then
        acc = 0
        hbConn = RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc >= 0.4 then acc = 0; pcall(scan) end
            if GUARD_ON then pcall(guardStep) end
        end)
        task.defer(function() pcall(scan) end)
    elseif not need and hbConn then
        pcall(function() hbConn:Disconnect() end); hbConn = nil
        nearList = {}
        clearHl()
    end
end

-- 重生后立即强制重扫一次, 避免沿用旧角色坐标
charConn = p.CharacterAdded:Connect(function() acc = 99 end)

-- ==========================================
-- 总开关 / 独立防怪 两个按钮, 各自独立
-- ==========================================
local function setOn(v)
    ON = v
    if v then enableDay() else disableDay() end
    ensureLoop()
    refresh()
end
local function setGuard(v)
    GUARD_ON = v
    if not v then lastTP = 0 end
    ensureLoop()
    refreshGuard()
end

local lastTap, lastGuardTap = 0, 0
btn.Activated:Connect(function()
    if tick() - lastTap < 0.2 then return end
    lastTap = tick()
    setOn(not ON)
end)
guardBtn.Activated:Connect(function()
    if tick() - lastGuardTap < 0.2 then return end
    lastGuardTap = tick()
    setGuard(not GUARD_ON)
end)

_G.WK_Day_Cleanup = function()
    if hbConn then pcall(function() hbConn:Disconnect() end); hbConn = nil end
    if charConn then pcall(function() charConn:Disconnect() end); charConn = nil end
    pcall(disableDay)
    pcall(clearHl)
    pcall(function() gui:Destroy() end)
end

-- 默认: 总开关开(执行即去雾白昼+测距), 独立防怪关(会传送玩家, 需手动开)
refreshGuard()
setOn(true)

print("WK 总控 + 独立防怪 已就绪 · 测距已修复(排除自身/载具, 严格HRP基准) [WK_DAY_V3]")
