-- ===== WK 总控 + 独立防怪 (去雾白昼 + 威胁测距 + 防怪靠近 · 零联网秒启动) =====
-- 适用: 「不要停止 / make sure to drive fast」等雨夜浓雾黑夜/追逐驾驶地图
-- 特点: 不加载任何UI库 / 不联网 / 无启动动画, 执行即出开关并生效
-- 防闪烁: 雾/暗化效果整体移出渲染树 + Lighting标量属性变更即时反制 (能力A, 已验证好用, 不动)
-- 总开关: 一键开/关「去雾白昼 + 威胁测距」; 关闭恢复夜景
-- 独立防怪: 单独按钮, 不属于总开关; 目标变红自动把自己(连车)传送到红区外
-- V4 修复「怪物检查/防怪靠近都没用」——不再靠猜怪物名字:
--   ① 玩家坐标多级兜底: HRP → PrimaryPart → Humanoid.RootPart → 首个BasePart (驾驶/自定义角色也能拿到)
--   ② 候选不设名字门槛: 任何「非玩家、非超大静态地形」的 Model/BasePart 都纳入, 取最近的当目标
--      (命中怪物名/带Humanoid 只是加分, 不再是必需条件) → 名字再特殊也能测到
--   ③ 删掉按名字排除 truck/Seat 的逻辑(会误排除追你的车), 改为精确排除「所有玩家角色 + 其乘坐载具」
--   ④ 传送改用 PivotTo 整体移动角色, 坐车时连载具一起搬 → 不会被座位拉回
--   ⑤ 内置「诊断」面板: 列出扫到的最近实体(名字/类型/距离/锚定), 一眼看清到底识别到了什么
-- FE说明: 客户端改不动服务端怪物, "无法靠近"以"自己自动弹开"为可靠实现, 推离为 best-effort
--   [WK_DAY_V4]

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
-- ③ 距离三级 (单位 stud, 脚本沿称 m)
local RED_D, YELLOW_D = 25, 60
local COL = {
    red    = Color3.fromRGB(210, 55, 55),
    yellow = Color3.fromRGB(215, 165, 45),
    green  = Color3.fromRGB(40, 175, 95),
    gray   = Color3.fromRGB(70, 74, 80),
}
-- 命中则标★(优先), 但【不再是必需条件】——没命中也照样进候选
local MONSTER_HINTS = {
    "monster","creature","enemy","zombie","killer","beast","entity","rake",
    "pursuer","stalker","horror","demon","ghost","alien","seek","figure",
    "kill","death","chase","crush","boulder","boss","giant","titan","shadow",
    "robot","sphere","spike","saw","slasher","hunter","train","truck",
    "怪","尸","幽灵","恶魔","追击","异形","巨兽","妖","杀手","追","撞","死神",
}
-- ④ 防怪参数
local SCAN_R      = 200   -- 威胁扫描半径
local BLOCK_D     = 60    -- 进入此范围尝试推离 (best-effort)
local SAFE_D      = 75    -- 红色时把自己传到距目标 75 (红区外绿区)
local PUSH_SPEED  = 80
local TP_COOLDOWN = 1.5
local SCAN_MAX    = 12000 -- 单次扫描对象数上限, 防超大地图卡顿

-- ==========================================
-- 状态
-- ==========================================
local ON = false          -- 总开关
local GUARD_ON = false    -- 独立防怪 (默认关: 会传送, 需手动开)
local DIAG_ON = false     -- 诊断面板
local dayOn = false
local backup, stash = nil, {}
local guardConns, fxConns = {}, {}
local hbConn, charConn, curHl, acc = nil, nil, nil, 0
local nearList = {}       -- 威胁候选 {{root, dist, obj, score}, ...} 已按距离升序
local lastTP = 0
local lastPrinted = nil
local diagCache, diagRoot, diagTotal = {}, "nil", 0

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
-- UI: 总开关 / 状态条 / 独立防怪 / 诊断按钮 + 诊断面板
-- ==========================================
local gui = Instance.new("ScreenGui")
gui.Name = "WK_DayToggle"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
local uiOk = pcall(function() gui.Parent = CoreGui end)
if not uiOk or not gui.Parent then gui.Parent = PlayerGui end

local function mkBtn(y, h, txt)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 148, 0, h)
    b.Position = UDim2.new(0, 12, 0.30, y)
    b.BackgroundColor3 = Color3.fromRGB(40, 44, 48)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.Text = txt
    b.TextColor3 = Color3.fromRGB(230, 230, 230)
    b.TextSize = 14
    b.Parent = gui
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 22)
    return b
end

local btn      = mkBtn(0,   44, "WK 总开关：关")
local guardBtn = mkBtn(90,  44, "防怪靠近：关")
local diagBtn  = mkBtn(140, 34, "诊断 (排查用)")

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 148, 0, 30)
statusLabel.Position = UDim2.new(0, 12, 0.30, 50)
statusLabel.BackgroundColor3 = COL.gray
statusLabel.BorderSizePixel = 0
statusLabel.Font = Enum.Font.GothamBold
statusLabel.Text = "待机"
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.TextSize = 13
statusLabel.TextScaled = true
statusLabel.Parent = gui
Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 8)

-- 诊断面板 (默认隐藏, 点「诊断」切换)
local diagFrame = Instance.new("Frame")
diagFrame.Size = UDim2.new(0, 250, 0, 210)
diagFrame.Position = UDim2.new(0, 12, 0.30, 182)
diagFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
diagFrame.BorderSizePixel = 0
diagFrame.Visible = false
diagFrame.Parent = gui
Instance.new("UICorner", diagFrame).CornerRadius = UDim.new(0, 8)
local diagStroke = Instance.new("UIStroke", diagFrame)
diagStroke.Color = COL.green
diagStroke.Thickness = 1.5
local diagLabel = Instance.new("TextLabel")
diagLabel.Size = UDim2.new(1, -12, 1, -12)
diagLabel.Position = UDim2.new(0, 6, 0, 6)
diagLabel.BackgroundTransparency = 1
diagLabel.Font = Enum.Font.Code
diagLabel.Text = "诊断未开启"
diagLabel.TextColor3 = Color3.fromRGB(220, 235, 220)
diagLabel.TextSize = 11
diagLabel.TextXAlignment = Enum.TextXAlignment.Left
diagLabel.TextYAlignment = Enum.TextYAlignment.Top
diagLabel.TextWrapped = true
diagLabel.Parent = diagFrame

local function setStatus(text, col)
    statusLabel.Text = text
    statusLabel.BackgroundColor3 = col
end
local function syncVisible()
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
        if not GUARD_ON then setStatus("待机", COL.gray) end
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
-- 能力A: 去雾白昼 (移出效果 + 标量反制) —— 原样保留, 不动
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
    for k, v in pairs(DAY) do setP(Lighting, k, v) end
    sweepEffects()
    for k, v in pairs(DAY) do
        pcall(function()
            local c = Lighting:GetPropertyChangedSignal(k):Connect(function()
                if not dayOn then return end
                if not sameVal(getP(Lighting, k), v) then setP(Lighting, k, v) end
            end)
            table.insert(guardConns, c)
        end)
    end
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
-- 能力B: 通用威胁扫描 (不依赖怪物名字) + 三级测距 + 高亮
-- ==========================================
-- 玩家坐标: 多级兜底, 驾驶/自定义角色也能拿到; 拿不到才返回 nil
local function myRoot()
    local char = p.Character
    if not char then return nil end
    local r = char:FindFirstChild("HumanoidRootPart")
    if r and r:IsA("BasePart") and r.Parent then return r end
    if char.PrimaryPart and char.PrimaryPart.Parent then return char.PrimaryPart end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.RootPart and hum.RootPart.Parent then return hum.RootPart end
    local any = char:FindFirstChildWhichIsA("BasePart")
    if any and any.Parent then return any end
    return nil
end
local function rootOf(obj)
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
        or obj:FindFirstChildWhichIsA("BasePart")
end

-- 精确排除「所有玩家角色 + 其乘坐载具」及其全部子部件 (不再按名字排除车)
local function playerSet()
    local s = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        local ch = plr.Character
        if ch then
            s[ch] = true
            local hum = ch:FindFirstChildOfClass("Humanoid")
            if hum and hum.SeatPart then
                local m = hum.SeatPart:FindFirstAncestorOfClass("Model")
                if m then s[m] = true end
            end
        end
    end
    return s
end
local function isPlayerRelated(obj, set)
    if set[obj] then return true end
    for m in pairs(set) do
        if obj:IsDescendantOf(m) then return true end
    end
    return false
end
-- 超大锚定几何 = 地形/建筑, 不算威胁 (避免地面被当成"最近物体"恒显 0m)
local function isTerrain(obj)
    if not obj:IsA("BasePart") then return false end
    if not obj.Anchored then return false end
    local s = obj.Size
    return (s.X > 400 or s.Y > 400 or s.Z > 400)
end
-- 威胁打分: 2=明确命中名字/带Humanoid, 1=一般可动实体, 0=不算
-- 关键: 名字不再是门槛, 只要不是玩家/地形, 至少给 1 分
local function threatScore(obj)
    local n = string.lower(obj.Name)
    for _, h in ipairs(MONSTER_HINTS) do
        if string.find(n, h, 1, true) then return 2 end
    end
    if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then return 2 end
    if obj:IsA("BasePart") and not obj.Anchored then return 1 end
    if obj:IsA("Model") then return 1 end
    return 0
end
local function grade(d)
    if d < RED_D then return "红", COL.red end
    if d < YELLOW_D then return "黄", COL.yellow end
    return "绿", COL.green
end
local function clearHl()
    if curHl then pcall(function() curHl:Destroy() end); curHl = nil end
end

-- best-effort 推离 (不改 CFrame, 避免读数失真)
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

-- 诊断文本
local function renderDiag()
    local lines = {}
    table.insert(lines, "基准根: " .. diagRoot)
    table.insert(lines, "扫描对象: " .. diagTotal .. " | 候选: " .. #diagCache)
    table.insert(lines, "★=命中名/有人形  ·=一般实体  锚=固定")
    local n = math.min(8, #diagCache)
    for i = 1, n do
        local it = diagCache[i]
        table.insert(lines, string.format("%d.%s %s[%s] %dm%s",
            i, it.sc == 2 and "★" or "·", it.name, it.cls,
            math.floor(it.d), it.anch and " 锚" or ""))
    end
    if #diagCache == 0 then
        table.insert(lines, "(半径内无候选 → 全被排除?)")
    end
    diagLabel.Text = table.concat(lines, "\n")
end

local function scan()
    local root = myRoot()
    if not root then
        clearHl()
        nearList = {}
        diagRoot, diagTotal, diagCache = "nil(无角色)", 0, {}
        setStatus("等待角色…", COL.gray)
        if DIAG_ON then renderDiag() end
        return
    end
    diagRoot = root.Name
    local me = root.Position
    local set = playerSet()
    local list, diag = {}, {}
    local total = 0
    for _, obj in ipairs(Workspace:GetDescendants()) do
        total = total + 1
        if total > SCAN_MAX then break end
        if obj:IsA("Model") or obj:IsA("BasePart") then
            if not isPlayerRelated(obj, set) and not isTerrain(obj) then
                local r = rootOf(obj)
                if r and r.Parent then
                    local d = (r.Position - me).Magnitude
                    if d < SCAN_R then
                        local sc = threatScore(obj)
                        if sc > 0 then
                            local anch = false
                            if obj:IsA("BasePart") then anch = obj.Anchored end
                            table.insert(list, { root = r, dist = d, obj = obj, score = sc })
                            table.insert(diag, { name = obj.Name, cls = obj.ClassName,
                                                  d = d, sc = sc, anch = anch })
                        end
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    table.sort(diag,  function(a, b) return a.d < b.d end)
    nearList = list
    diagTotal, diagCache = total, diag

    -- 推离 (低频, 仅防怪开启)
    if GUARD_ON then
        for _, it in ipairs(list) do
            if it.dist < BLOCK_D and it.root.Parent then
                pushAway(it.root, me)
            end
        end
    end

    -- 状态条 + 高亮 (任一开关开启都显示)
    if ON or GUARD_ON then
        clearHl()
        -- 优先展示「明确命中名字/带Humanoid」的目标(★); list 已按距离升序
        local best = nil
        for _, it in ipairs(list) do
            if it.score == 2 then best = it; break end
        end
        if not best then best = list[1] end
        if not best then
            setStatus("无目标 (0)", COL.gray)
        else
            local g, col = grade(best.dist)
            local nm = best.obj.Name
            if #nm > 9 then nm = string.sub(nm, 1, 9) .. "…" end
            setStatus(g .. "·" .. math.floor(best.dist) .. "m ·" .. nm .. " (" .. #list .. ")", col)
            if best.obj.Name ~= lastPrinted then
                lastPrinted = best.obj.Name
                print("[WK] 目标: " .. best.obj.Name .. " [" .. best.obj.ClassName .. "] @ "
                      .. math.floor(best.dist) .. "m 候选数=" .. #list)
            end
            pcall(function()
                local hl = Instance.new("Highlight")
                hl.Name = "WK_MonsterHL"
                hl.Adornee = best.obj
                hl.FillColor = col
                hl.OutlineColor = col
                hl.FillTransparency = 0.5
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Parent = best.obj
                curHl = hl
            end)
        end
    end
    if DIAG_ON then renderDiag() end
end

-- ==========================================
-- 能力C: 独立防怪 (红色时自动把自己 + 载具 传送到红区外)
-- ==========================================
local function teleportOut(tgt)
    local char = p.Character
    local root = myRoot()
    if not char or not root then return end
    local away = Vector3.new(root.Position.X - tgt.X, 0, root.Position.Z - tgt.Z)
    if away.Magnitude < 0.001 then away = Vector3.new(1, 0, 0) end
    away = away.Unit
    local dest = Vector3.new(tgt.X + away.X * SAFE_D, root.Position.Y + 2, tgt.Z + away.Z * SAFE_D)
    local cf = CFrame.new(dest)
    -- PivotTo 整体移动角色 (比改 HRP.CFrame 可靠, 坐车也不会被座位拉回)
    pcall(function() char:PivotTo(cf) end)
    -- 坐车时把载具一起搬走, 否则角色会被车拽回原地
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart then
        local m = hum.SeatPart:FindFirstAncestorOfClass("Model")
        if m then pcall(function() m:PivotTo(cf) end) end
    end
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.Velocity = Vector3.zero
    end)
end

-- 每帧层: 实时重算最近距离, 红色(带冷却)自动闪避
local function guardStep()
    local root = myRoot()
    if not root then return end
    local me = root.Position
    local minD, minPos = math.huge, nil
    for _, it in ipairs(nearList) do
        local r = it.root
        if r and r.Parent then
            local d = (r.Position - me).Magnitude
            if d < minD then minD, minPos = d, r.Position end
        end
    end
    if minPos and minD < RED_D and tick() - lastTP > TP_COOLDOWN then
        lastTP = tick()
        teleportOut(minPos)
    end
end

-- 单一循环: 只要任一能力开启就运行
local function ensureLoop()
    local need = ON or GUARD_ON or DIAG_ON
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

-- 重生后强制重扫
charConn = p.CharacterAdded:Connect(function() acc = 99 end)

-- ==========================================
-- 按钮逻辑 (三个按钮互不隶属)
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
local function setDiag(v)
    DIAG_ON = v
    diagFrame.Visible = v
    diagBtn.BackgroundColor3 = v and COL.green or Color3.fromRGB(40, 44, 48)
    diagBtn.TextColor3 = v and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(230, 230, 230)
    ensureLoop()
    if v then renderDiag() end
end

local lastTap, lastGuardTap, lastDiagTap = 0, 0, 0
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
diagBtn.Activated:Connect(function()
    if tick() - lastDiagTap < 0.2 then return end
    lastDiagTap = tick()
    setDiag(not DIAG_ON)
end)

_G.WK_Day_Cleanup = function()
    if hbConn then pcall(function() hbConn:Disconnect() end); hbConn = nil end
    if charConn then pcall(function() charConn:Disconnect() end); charConn = nil end
    pcall(disableDay)
    pcall(clearHl)
    pcall(function() gui:Destroy() end)
end

-- 默认: 总开关开(去雾白昼+测距), 防怪/诊断关
refreshGuard()
setDiag(false)
setOn(true)

print("WK 总控 + 独立防怪 已就绪 · V4(不依赖怪物名+坐标多级兜底+PivotTo传送+诊断面板) [WK_DAY_V4]")
