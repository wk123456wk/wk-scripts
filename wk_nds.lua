-- ===== WK 视野 + 自动转弯 V4 (去雾白昼 · 弯道大幅转向/漂移 · 零联网秒启动) =====
-- 适用: 「不要停止 / make sure to drive fast」等雨夜浓雾黑夜驾驶地图
-- V4 专治「转弯幅度太小会撞墙」:
--   1) 宽扇区 9 角度(±75°) + 3 档前探(最远 48 stud) → 更早、更广地发现急弯/直角弯
--   2) 转向增益调猛: 偏离 20° 即打满舵 (旧版 50° 才满舵, 中等弯只给半舵)
--   3) 平滑/探测频率提高 (0.8 / 0.08s) → 方向果断到位, 不再拖到贴墙才转
--   4) 前方近处无路面(墙/断路)时【绝不回正】, 强制朝有路一侧满舵避险
--   控制: 自适应 —— 优先写 VehicleSeat.Steer; 自定义脚本车改为车身横摆扭矩兜底
--   漂移: 速度高 + 转向大时叠加横向滑移 + 横摆角速度, 做出甩尾观感
--   性能: 未开启时【零新增开销】; 开启后不用每帧循环 —— 转向值靠属性变更信号维持,
--         路面探测每 0.08 秒一次 (27 条射线), 无全图遍历 / 无 GetDescendants
-- 视野逻辑原样保留: 删高频 DescendantAdded 监听 + 字典查重 + 反制节流 + 10 秒低频巡检
--   [WK_VIEW_V4]

local Lighting  = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local CoreGui   = game:GetService("CoreGui")
local Players   = game:GetService("Players")
local p         = Players.LocalPlayer
local PlayerGui = p:WaitForChild("PlayerGui")

-- 防多开: 让上一份实例(含旧版心跳/扫描)彻底停下并恢复夜景
if _G.WK_Day_Cleanup then pcall(_G.WK_Day_Cleanup) end
for _, parent in ipairs({CoreGui, PlayerGui}) do
    for _, obj in ipairs(parent:GetChildren()) do
        if obj.Name == "WK_DayToggle" then pcall(function() obj:Destroy() end) end
    end
end

-- ==========================================
-- 配置: 视野
-- ==========================================
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
local FX = {
    Atmosphere = true, ColorCorrectionEffect = true, BlurEffect = true,
    DepthOfFieldEffect = true, SunRaysEffect = true, BloomEffect = true, Sky = true,
}
local GREEN          = Color3.fromRGB(40, 175, 95)
local DARK           = Color3.fromRGB(40, 44, 48)
local SWEEP_INTERVAL = 10    -- 秒; 视野效果极低频巡检 (设 0 完全不巡检)
local FIX_THROTTLE   = 0.15  -- 秒; 属性写回最小间隔, 防乒乓
local STASH_MAX      = 200

-- ==========================================
-- 配置: 自动转弯 / 漂移  (V4: 大幅转向 + 提前预判 + 前方避险)
-- ==========================================
local AUTO_TICK      = 0.08  -- 秒; 路面探测间隔 (提高响应, 仍非每帧)
local PROBE_ANGLES   = {-75, -50, -28, -12, 0, 12, 28, 50, 75}  -- 度; 宽扇区, 覆盖急弯/直角弯
local PROBE_DISTS    = {10, 26, 48}         -- stud; 近处感知障碍 + 远处提前预判弯道
local PROBE_W        = {1, 3, 5}            -- 三档得分权重 (越远仍有路越说明路往这边延伸)
local PROBE_UP       = 4                     -- 射线起点抬高
local PROBE_DOWN     = 35                    -- 向下探测深度
local TURN_GAIN_DEG  = 20    -- 度; 偏离 20° 即打满舵 (越小越猛; 还嫌不够改 15)
local STEER_SIGN     = 1     -- 若发现车往反方向拐, 把这里改成 -1
local STEER_SMOOTH   = 0.8   -- 转向平滑 (提高: 果断到位, 不再拖到撞墙)
local DRIFT_MIN_SPD  = 35    -- 触发漂移的最低速度
local DRIFT_MIN_TURN = 0.45  -- 触发漂移的最小转向幅度
local DRIFT_SIDE     = 10    -- 漂移横向滑移强度
local DRIFT_YAW      = 0.8   -- 漂移附加横摆
local TORQUE_YAW     = 1.6   -- 扭矩兜底模式的横摆角速度

-- ==========================================
-- 状态
-- ==========================================
local ON = true          -- 视野
local AUTO_ON = false    -- 自动转弯 (默认关: 会接管方向, 需手动开)
local dayOn = false
local backup = nil
local stashMap, stashList = {}, {}
local scalarConns, lastFix = {}, {}
local sweepThread, alive = nil, false

local curSteer = 0
local autoThread, autoAlive = nil, false
local veh, rayParams, lastChar, lastModel = nil, nil, nil, nil
local steerConn, lastSeat, ctrlMode = nil, nil, nil
local wasTurning = false

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
-- UI: 两个独立开关
-- ==========================================
local gui = Instance.new("ScreenGui")
gui.Name = "WK_DayToggle"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
local uiOk = pcall(function() gui.Parent = CoreGui end)
if not uiOk or not gui.Parent then gui.Parent = PlayerGui end

local function mkBtn(y, txt)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 148, 0, 44)
    b.Position = UDim2.new(0, 12, 0.30, y)
    b.BackgroundColor3 = DARK
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.Text = txt
    b.TextColor3 = Color3.fromRGB(230, 230, 230)
    b.TextSize = 14
    b.Parent = gui
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 22)
    return b
end
local btn     = mkBtn(0,  "WK 视野：关")
local btnAuto = mkBtn(54, "自动转弯：关")

local function refresh()
    if ON then
        btn.Text = "WK 视野：开"
        btn.BackgroundColor3 = GREEN
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
        btn.Text = "WK 视野：关"
        btn.BackgroundColor3 = DARK
        btn.TextColor3 = Color3.fromRGB(230, 230, 230)
    end
end
local function refreshAuto()
    if AUTO_ON then
        btnAuto.Text = "自动转弯：开"
        btnAuto.BackgroundColor3 = GREEN
        btnAuto.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
        btnAuto.Text = "自动转弯：关"
        btnAuto.BackgroundColor3 = DARK
        btnAuto.TextColor3 = Color3.fromRGB(230, 230, 230)
    end
end

-- ==========================================
-- 能力A: 视野 (去雾 + 去黑夜) —— 原样保留
-- ==========================================
local function moveOut(obj)
    if stashMap[obj] then return end
    local par = obj.Parent
    if #stashList < STASH_MAX then
        stashMap[obj] = true
        table.insert(stashList, { obj = obj, parent = par })
    end
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
    for _, it in ipairs(stashList) do
        local ok = pcall(function() it.obj.Parent = it.parent or Lighting end)
        if not ok then pcall(function() it.obj.Parent = Lighting end) end
    end
    stashMap, stashList = {}, {}
end
local function enableView()
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
                local now = os.clock()
                if lastFix[k] and now - lastFix[k] < FIX_THROTTLE then return end
                if not sameVal(getP(Lighting, k), v) then
                    lastFix[k] = now
                    setP(Lighting, k, v)
                end
            end)
            table.insert(scalarConns, c)
        end)
    end
    if SWEEP_INTERVAL > 0 then
        alive = true
        sweepThread = task.spawn(function()
            while alive and dayOn do
                task.wait(SWEEP_INTERVAL)
                if not (alive and dayOn) then break end
                pcall(sweepEffects)
            end
        end)
    end
end
local function disableView()
    if not dayOn then return end
    dayOn = false
    alive = false
    if sweepThread then pcall(function() task.cancel(sweepThread) end); sweepThread = nil end
    for _, c in ipairs(scalarConns) do pcall(function() c:Disconnect() end) end
    scalarConns = {}
    lastFix = {}
    if backup then
        for k, v in pairs(backup) do if v ~= nil then setP(Lighting, k, v) end end
        backup = nil
    end
    moveBackAll()
end

-- ==========================================
-- 能力B: 自动转弯 + 漂移
-- ==========================================
local function findVehicle()
    local char = p.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    if not seat or not seat.Parent then return nil end
    return { seat = seat, model = seat:FindFirstAncestorOfClass("Model"), root = seat, char = char }
end

-- 射线过滤: 排除自己的角色 / 车, 否则会打到自己的车顶
local function ensureParams()
    if rayParams and veh and lastChar == veh.char and lastModel == veh.model then return end
    lastChar, lastModel = veh and veh.char, veh and veh.model
    rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local f = {}
    if veh then
        if veh.char then table.insert(f, veh.char) end
        if veh.model then table.insert(f, veh.model) end
        if veh.seat then table.insert(f, veh.seat) end
    end
    rayParams.FilterDescendantsInstances = f
end

-- 绕 Y 轴旋转水平向量 (正角度 = 左)
local function rotated(v, deg)
    local c, s = math.cos(math.rad(deg)), math.sin(math.rad(deg))
    return Vector3.new(v.X * c + v.Z * s, 0, -v.X * s + v.Z * c)
end
-- 前进方向: 优先用实际速度方向 (车真实往哪开), 低速时用座椅朝向
local function forwardOf(root)
    local ok, vel = pcall(function() return root.AssemblyLinearVelocity end)
    if ok and vel then
        local h = Vector3.new(vel.X, 0, vel.Z)
        if h.Magnitude > 5 then return h.Unit end
    end
    local lv = root.CFrame.LookVector
    local h = Vector3.new(lv.X, 0, lv.Z)
    if h.Magnitude < 0.01 then return Vector3.new(0, 0, -1) end
    return h.Unit
end

-- 扇形探路面: 返回 (最佳角度, 得分, 正前方近处是否被挡)
local function probeRoad(root, fw)
    ensureParams()
    local origin = root.Position + Vector3.new(0, PROBE_UP, 0)
    local bestDeg, bestScore = 0, -1
    local frontNearOK = false
    for _, deg in ipairs(PROBE_ANGLES) do
        local dir = rotated(fw, deg)
        local s = 0
        for i, d in ipairs(PROBE_DISTS) do
            local hit = Workspace:Raycast(origin + dir * d, Vector3.new(0, -PROBE_DOWN, 0), rayParams)
            if hit then
                s = s + (PROBE_W[i] or 1)               -- 越远仍有路面 = 路往这边延伸
                if deg == 0 and i <= 2 then frontNearOK = true end
            end
        end
        s = s + (1 - math.abs(deg) / 90) * 0.4           -- 轻微中心偏好, 直路不乱拐
        if s > bestScore then bestScore, bestDeg = s, deg end
    end
    return bestDeg, bestScore, not frontNearOK
end

-- 自适应控制方式: 能写 VehicleSeat.Steer 就用它, 否则扭矩兜底
local function bindSeat(seat)
    if lastSeat == seat and ctrlMode then return end
    if steerConn then pcall(function() steerConn:Disconnect() end); steerConn = nil end
    lastSeat = seat
    local ok = pcall(function() local _ = seat.Steer; seat.Steer = 0 end)
    if ok then
        ctrlMode = "seat"
        -- 游戏输入系统每帧会把 Steer 清成 0; 用属性变更事件即时写回, 无需每帧循环
        pcall(function()
            steerConn = seat:GetPropertyChangedSignal("Steer"):Connect(function()
                if not AUTO_ON or ctrlMode ~= "seat" then return end
                if math.abs(seat.Steer - curSteer) > 0.02 then
                    pcall(function() seat.Steer = curSteer end)
                end
            end)
        end)
        print("[WK] 车辆控制: VehicleSeat.Steer")
    else
        ctrlMode = "torque"
        print("[WK] 车辆控制: 自定义车 → 横摆扭矩兜底")
    end
end

local function applySteer(v)
    if not veh then return end
    if ctrlMode == "seat" then
        pcall(function() veh.seat.Steer = v end)
    else
        pcall(function()
            local av = veh.root.AssemblyAngularVelocity
            veh.root.AssemblyAngularVelocity = Vector3.new(av.X, v * TORQUE_YAW, av.Z)
        end)
    end
end

-- 漂移: 高速急弯时叠加横向滑移 + 横摆 (best-effort, pcall 兜底不影响主转向)
local function doDrift(root, fw, v)
    local ok, vel = pcall(function() return root.AssemblyLinearVelocity end)
    if not ok or not vel then return end
    if Vector3.new(vel.X, 0, vel.Z).Magnitude < DRIFT_MIN_SPD then return end
    if math.abs(v) < DRIFT_MIN_TURN then return end
    local right = fw:Cross(Vector3.new(0, 1, 0))
    pcall(function()
        root.AssemblyLinearVelocity = vel + right * (v * DRIFT_SIDE)
        local av = root.AssemblyAngularVelocity
        root.AssemblyAngularVelocity = Vector3.new(av.X, av.Y + v * DRIFT_YAW, av.Z)
    end)
end

local function autoTick()
    if not AUTO_ON then return end
    local v = findVehicle()
    if not v then
        curSteer = curSteer * 0.7   -- 没坐车/角色未就绪: 缓慢回正
        return
    end
    veh = v
    bindSeat(v.seat)
    local fw = forwardOf(v.root)
    local deg, score, blocked = probeRoad(v.root, fw)
    local raw = 0
    if blocked then
        -- 正前方紧挨着就没路面 (墙/断路): 绝不回正直怼, 朝有路一侧满舵避险
        if deg ~= 0 then
            raw = math.max(-1, math.min(1, -deg / TURN_GAIN_DEG))
        else
            raw = (math.abs(curSteer) > 0.05 and (curSteer > 0 and 1 or -1)) or 1
        end
        if math.abs(raw) < 0.85 then raw = raw >= 0 and 0.85 or -0.85 end
    elseif score > 1 then
        raw = math.max(-1, math.min(1, -deg / TURN_GAIN_DEG))
    end
    local target = raw * STEER_SIGN
    curSteer = curSteer + (target - curSteer) * STEER_SMOOTH
    applySteer(curSteer)
    doDrift(v.root, fw, curSteer)
    local turning = math.abs(target) > 0.2
    if turning ~= wasTurning then
        wasTurning = turning
        print("[WK] " .. (blocked and "前方无路 → 满舵避险" or (turning and "进入弯道 → 自动转向" or "回到直路 → 回正")))
    end
end

local function startAuto()
    if autoThread then return end
    autoAlive = true
    autoThread = task.spawn(function()
        while autoAlive and AUTO_ON do
            pcall(autoTick)
            task.wait(AUTO_TICK)
        end
    end)
end
local function stopAuto()
    autoAlive = false
    if autoThread then pcall(function() task.cancel(autoThread) end); autoThread = nil end
    if steerConn then pcall(function() steerConn:Disconnect() end); steerConn = nil end
    lastSeat, rayParams, lastChar, lastModel = nil, nil, nil, nil
    wasTurning = false
    if veh and ctrlMode == "seat" and veh.seat and veh.seat.Parent then
        pcall(function() veh.seat.Steer = 0 end)   -- 关掉后方向归零, 交还玩家
    end
    curSteer = 0
    veh = nil
end

-- ==========================================
-- 按钮逻辑 (两个开关互不隶属, Activated 统一鼠标+触摸 + 防抖)
-- ==========================================
local lastTap, lastAutoTap = 0, 0
btn.Activated:Connect(function()
    if tick() - lastTap < 0.2 then return end
    lastTap = tick()
    ON = not ON
    if ON then enableView() else disableView() end
    refresh()
end)
btnAuto.Activated:Connect(function()
    if tick() - lastAutoTap < 0.2 then return end
    lastAutoTap = tick()
    AUTO_ON = not AUTO_ON
    if AUTO_ON then startAuto() else stopAuto() end
    refreshAuto()
end)

_G.WK_Day_Cleanup = function()
    pcall(stopAuto)
    pcall(disableView)
    pcall(function() gui:Destroy() end)
end

-- 默认: 视野开, 自动转弯关
refresh()
refreshAuto()
enableView()

print("WK 已就绪 (视野 + 自动转弯/漂移 V4 · 大幅转向防撞墙 · 零联网 · 低开销) [WK_VIEW_V4]")
