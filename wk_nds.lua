-- ===== WK 视野 + 自动转弯 V6 (去雾白昼 · 直写 VehicleSeat 摇杆输出 · 零联网秒启动) =====
-- 适用: 「不要停止 / make sure to drive fast」等雨夜浓雾黑夜驾驶地图
-- V6 修正依据 (Roblox 官方 VehicleSeat 文档):
--   * Steer 是 int(1/0/-1) 且已弃用; 移动端摇杆的模拟转向写入的是 SteerFloat (float, 1右~-1左)
--   * 二者 ReadWrite / security None, 且 "Will refresh back to 0 unless constantly set"
--   * VirtualInputManager 是内部服务(RobloxScriptSecurity), 普通脚本无法注入触摸 → 放弃 V5 方案
--   实现: 找到 VehicleSeat → 写 SteerFloat + Steer → Heartbeat 每帧持续写 + 属性变更即时写回
--   兜底: 非 VehicleSeat 的车, 写车模型内可疑转向 Value/HingeConstraint + 车身横摆扭矩
--   诊断: 开启后屏幕左上角显示 座位类型 / 目标舵 / SteerFloat 读回值 / 候选对象名 (截图即可)
--   性能: 未开启时零新增开销; 开启后每帧仅几次属性赋值, 无全图遍历, 无每帧射线
-- 视野逻辑原样保留: 删高频 DescendantAdded 监听 + 字典查重 + 反制节流 + 10 秒低频巡检
--   [WK_VIEW_V6]

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
-- 配置: 自动转弯 / 漂移  (V4 弯道决策原样保留)
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
-- 配置: 转向输出 (V6 主通道, 依据 Roblox 官方 VehicleSeat 文档)
-- ==========================================
local WRITE_FLOAT    = true   -- 写 SteerFloat (移动端摇杆的模拟转向值, float 1~-1)
local WRITE_INT      = true   -- 同时写 Steer (int 1/0/-1, 兼容老式脚本)
local EVERY_FRAME    = true   -- 每帧持续写 (官方: 不持续设置会刷回 0)
local HINGE_ANGLE    = 30    -- 自定义车伺服转向铰链的满舵角度
local DIAG           = true   -- 屏幕诊断 (确认工作后可改 false 隐藏)

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
local floatConn, frameConn, lastSeat = nil, nil, nil
local floatOK, intOK = false, false
local carValues, carNames = {}, {}
local wasTurning = false
local diagT = 0

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

-- 屏幕诊断: 仅自动转弯开启时可见; 手机端不用开控制台, 直接截图即可
local diag = Instance.new("TextLabel")
diag.Name = "WK_Diag"
diag.Size = UDim2.new(0, 236, 0, 78)
diag.Position = UDim2.new(0, 12, 0.30, 106)
diag.BackgroundColor3 = Color3.fromRGB(12, 16, 20)
diag.BackgroundTransparency = 0.35
diag.BorderSizePixel = 0
diag.Font = Enum.Font.Gotham
diag.TextSize = 11
diag.TextColor3 = Color3.fromRGB(170, 235, 185)
diag.TextXAlignment = Enum.TextXAlignment.Left
diag.TextYAlignment = Enum.TextYAlignment.Top
diag.TextWrapped = true
diag.Text = "诊断待开启"
diag.Visible = false
diag.Parent = gui
pcall(function() Instance.new("UICorner", diag).CornerRadius = UDim.new(0, 8) end)

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
-- 能力B: 自动转弯 + 漂移  (V6: 直写 VehicleSeat 摇杆输出属性)
-- ==========================================
local RunService = game:GetService("RunService")

-- 找座位: 优先真正的 VehicleSeat (摇杆输出写在这里), 否则退回 SeatPart
local function findVehicle()
    local char = p.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    if not seat or not seat.Parent then return nil end
    local model = seat:FindFirstAncestorOfClass("Model")
    local vs = nil
    if seat:IsA("VehicleSeat") then vs = seat end
    if not vs and model then
        pcall(function() vs = model:FindFirstChildWhichIsA("VehicleSeat", true) end)
    end
    if not vs then
        pcall(function()
            local par = seat.Parent
            if par then vs = par:FindFirstChildWhichIsA("VehicleSeat", true) end
        end)
    end
    local target = vs or seat
    return { seat = target, rawSeat = seat, isVehicleSeat = vs ~= nil,
             model = model, root = target, char = char }
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

-- === V6 转向输出 ===
local VALUE_KEY = {
    steer=1, turn=1, input=1, direction=1, dir=1, angle=1, wheel=1, yaw=1,
    ["转向"]=1, ["方向"]=1, ["角度"]=1,
}

-- 扫描车模型内可疑的转向值对象 (仅换车时一次; 只收看起来像输入量的)
local function scanCarValues(model)
    carValues, carNames = {}, {}
    if not model then return end
    pcall(function()
        for _, o in ipairs(model:GetDescendants()) do
            local isHinge = (o.ClassName == "HingeConstraint")
            local isVal   = o:IsA("NumberValue") or o:IsA("IntValue")
            if isHinge or isVal then
                local n = o.Name:lower()
                local match = false
                for k in pairs(VALUE_KEY) do if n:find(k, 1, true) then match = true break end end
                if match and (isHinge or (type(o.Value) == "number" and math.abs(o.Value) <= 1.01)) then
                    table.insert(carValues, o)
                    table.insert(carNames, o.Name)
                end
            end
            if #carValues >= 8 then break end
        end
    end)
end

-- 真正的输出: 写 SteerFloat (模拟) + Steer (整数) + 自定义车兜底
local function writeSeat(v)
    if not veh or not veh.seat then return end
    local s = veh.seat
    if WRITE_FLOAT then pcall(function() s.SteerFloat = v end) end
    if WRITE_INT   then pcall(function() s.Steer = (v > 0.15 and 1 or (v < -0.15 and -1 or 0)) end) end
    if not veh.isVehicleSeat then
        for _, o in ipairs(carValues) do
            pcall(function()
                if o:IsA("NumberValue") or o:IsA("IntValue") then
                    o.Value = v
                elseif o.ClassName == "HingeConstraint" then
                    o.TargetAngle = v * HINGE_ANGLE
                end
            end)
        end
        pcall(function()
            local av = veh.root.AssemblyAngularVelocity
            veh.root.AssemblyAngularVelocity = Vector3.new(av.X, v * TORQUE_YAW, av.Z)
        end)
    end
end

-- 绑定座位: 探测可写属性 + 属性变更即时写回 + 扫描候选 (换车才重做)
local function bindVehicle(v)
    if lastSeat == v.seat then return end
    lastSeat = v.seat
    if floatConn then pcall(function() floatConn:Disconnect() end); floatConn = nil end
    floatOK = pcall(function() local _ = v.seat.SteerFloat; v.seat.SteerFloat = 0 end)
    intOK   = pcall(function() local _ = v.seat.Steer; v.seat.Steer = 0 end)
    if floatOK then
        -- 引擎每帧把 SteerFloat 清成 0 时立刻压回, 不靠轮询
        pcall(function()
            floatConn = v.seat:GetPropertyChangedSignal("SteerFloat"):Connect(function()
                if not AUTO_ON then return end
                local ok, cur = pcall(function() return v.seat.SteerFloat end)
                if ok and type(cur) == "number" and math.abs(cur - curSteer) > 0.02 then
                    pcall(function() v.seat.SteerFloat = curSteer end)
                end
            end)
        end)
    end
    scanCarValues(v.model)
end

-- 每帧持续写 (官方要求 constantly set; 回调只有几次属性赋值, 不遍历不射线)
local function startFrameWriter()
    if not EVERY_FRAME or frameConn then return end
    frameConn = RunService.Heartbeat:Connect(function()
        if not AUTO_ON or not veh then return end
        pcall(writeSeat, curSteer)
    end)
end

-- 屏幕诊断: 读回 SteerFloat 与目标的差, 一眼看出写入是否被接受
local function updateDiag(force)
    if not DIAG then return end
    local now = os.clock()
    if not force and now - diagT < 0.3 then return end
    diagT = now
    local seatType, readback = "未坐车", "-"
    if veh then
        seatType = veh.isVehicleSeat and "VehicleSeat"
            or ("普通" .. (veh.rawSeat and veh.rawSeat.ClassName or "Seat"))
        local ok, val = pcall(function() return veh.seat.SteerFloat end)
        if ok and type(val) == "number" then readback = string.format("%+.2f", val) end
    end
    local ch = (floatOK and "Float" or "无Float") .. (intOK and "+Int" or "")
        .. (EVERY_FRAME and " 每帧" or "")
    local names = "无"
    if #carNames > 0 then names = table.concat(carNames, ",", 1, math.min(3, #carNames)) end
    diag.Text = string.format("座位 %s | %s\n目标 %+.2f  读回 %s\n候选 %s\n%s",
        seatType, ch, curSteer, readback, names,
        (veh and veh.isVehicleSeat) and "读回≈目标 → 写入成功"
            or "非VehicleSeat/写入被覆盖 → 截图发我")
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
        updateDiag()
        return
    end
    veh = v
    bindVehicle(v)
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
    writeSeat(curSteer)
    doDrift(v.root, fw, curSteer)
    updateDiag()
    local turning = math.abs(target) > 0.2
    if turning ~= wasTurning then
        wasTurning = turning
        print("[WK] " .. (blocked and "前方无路 → 满舵避险" or (turning and "进入弯道 → 自动转向" or "回到直路 → 回正")))
    end
end

local function startAuto()
    if autoThread then return end
    autoAlive = true
    diag.Visible = DIAG
    startFrameWriter()
    updateDiag(true)
    autoThread = task.spawn(function()
        while autoAlive and AUTO_ON do
            pcall(autoTick)
            task.wait(AUTO_TICK)
        end
    end)
end
local function stopAuto()
    autoAlive = false
    if frameConn then pcall(function() frameConn:Disconnect() end); frameConn = nil end
    if floatConn then pcall(function() floatConn:Disconnect() end); floatConn = nil end
    if autoThread then pcall(function() task.cancel(autoThread) end); autoThread = nil end
    lastSeat, rayParams, lastChar, lastModel = nil, nil, nil, nil
    wasTurning = false
    if veh and veh.seat and veh.seat.Parent then
        pcall(function() if floatOK then veh.seat.SteerFloat = 0 end end)
        pcall(function() veh.seat.Steer = 0 end)   -- 关掉后方向归零, 交还玩家
    end
    curSteer = 0
    veh = nil
    diag.Visible = false
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

print("WK 已就绪 (视野 + 自动转弯 V6 · 直写 SteerFloat · 屏幕诊断 · 零联网) [WK_VIEW_V6]")
