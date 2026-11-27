-- ===== WK 视野 + 自动转弯 V7 (去雾白昼 · 弯道自动转向/漂移 · 零联网秒启动) =====
-- 适用: 「不要停止 / make sure to drive fast」等雨夜浓雾黑夜驾驶地图
-- V7 是依据 V6【屏幕诊断的实测证据】重做, 不再凭猜测换控制通道:
--   诊断实录: 「座位 普通Seat | 无Float 每帧 / 目标 +0.00 读回 -」
--   [证据1] 这游戏不是 VehicleSeat, 连 SteerFloat 属性都不存在 → V6 写了个不存在的属性, 全废
--   [证据2] 目标恒 +0.00 → 旧版「向下打射线找路面」在整片大地地图上 9 个方向全部命中,
--           得分几乎相同 + 中心偏好 → 永远判直路, 一次方向都没打过。这是更致命的独立 Bug
-- V7 两项根本修复:
--   (1) 探路改为【水平前方障碍射线】: 从车头向 9 个方向打水平射线, 测「撞墙距离」(法线朝上
--       的地面不算障碍), 叠加远处地面连续性; 选最空的方向。前方近处有墙 → 立即满舵避险
--   (2) 转向输出改为【自适应取证 + 多通道并打】: 开启时扫描 PlayerGui/CoreGui 定位真实摇杆,
--       列出 ReplicatedStorage/车模型 的 RemoteEvent 与转向 Value; 驱动时按 触摸注入 /
--       firesignal / knob 位置 / 转向 Value / SteerFloat / 车身横摆 依次尝试, 每条通道的
--       成功与失败都显示在屏幕诊断里, 点「复制诊断」即可把完整对象清单粘贴出来
-- 视野逻辑原样保留: 删高频 DescendantAdded 监听 + 字典查重 + 反制节流 + 10 秒低频巡检
--   性能: 未开启零新增开销; 扫描只在开启/换车时做一次; 每帧仅几次属性赋值
--   [WK_VIEW_V7]

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
-- 配置: 自动转弯 / 漂移  (V7 水平障碍探路)
-- ==========================================
local AUTO_TICK      = 0.08  -- 秒; 探路间隔
local PROBE_ANGLES   = {-75, -50, -28, -12, 0, 12, 28, 50, 75}  -- 度; 正=左, 负=右
local PROBE_LEN      = 55    -- stud; 水平前探距离
local PROBE_UP       = 2     -- 射线起点抬高 (避开地面)
local WALL_DANGER    = 18    -- stud; 正前方障碍近于此 → 紧急满舵避险
local TURN_GAIN_DEG  = 22    -- 度; 最佳方向偏离 22° 即打满舵 (越小越猛)
local STEER_SIGN     = 1     -- 车往反方向拐 → 改成 -1
local STICK_SIGN     = 1     -- 摇杆左右拖反 → 改成 -1
local STEER_SMOOTH   = 0.8
local DRIFT_MIN_SPD  = 35
local DRIFT_MIN_TURN = 0.45
local DRIFT_SIDE     = 10
local DRIFT_YAW      = 0.8
local TORQUE_YAW     = 1.6

-- ==========================================
-- 配置: 转向输出 (V7 自适应取证 + 多通道)
-- ==========================================
local STICK_NAME     = ""    -- 留空=自动扫描; 诊断里看到正确对象名后填这里精确锁定
local STICK_RADIUS   = 0     -- 0=按摇杆尺寸自动算; 也可填固定像素如 70
local TRY_TOUCH      = true  -- VirtualInputManager 触摸注入 (带成功/失败回显)
local TRY_FIRESIGNAL = true  -- firesignal 触发摇杆输入信号 (若执行器提供)
local TRY_KNOB       = true  -- 直接移动 knob 位置 (降级)
local TRY_VALUES     = true  -- 写名字含 steer/turn/方向 的 Value
local TRY_SEAT       = true  -- 写 SteerFloat / Steer (若座位支持)
local TRY_TORQUE     = true  -- 车身横摆兜底
local WRITE_FLOAT    = true
local WRITE_INT      = true
local EVERY_FRAME    = true
local HINGE_ANGLE    = 30
local DIAG           = true  -- 屏幕诊断 (确认工作后可改 false 隐藏)

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
-- V7 取证 / 通道状态
local stick, stickCenter, stickRadius, knobBase = nil, nil, nil, nil
local stickCands, remoteObjs, remoteNames, stickVals, valueNames = {}, {}, {}, {}, {}
local chanTouch, chanFire, chanKnob, chanVal, chanSeat = "未测", "-", "-", "-", "-"
local touchOK, touchSig, touchErr = false, 0, ""
local touchDown, touchId = false, 9137
local probeInfo = "探路 -"
local fullReport = ""
local updateDiag

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

-- 屏幕诊断 (V7): 仅自动转弯开启时可见; 加大显示多通道状态
local diag = Instance.new("TextLabel")
diag.Name = "WK_Diag"
diag.Size = UDim2.new(0, 272, 0, 170)
diag.Position = UDim2.new(0, 12, 0.30, 106)
diag.BackgroundColor3 = Color3.fromRGB(12, 16, 20)
diag.BackgroundTransparency = 0.28
diag.BorderSizePixel = 0
diag.Font = Enum.Font.Gotham
diag.TextSize = 10
diag.TextColor3 = Color3.fromRGB(170, 235, 185)
diag.TextXAlignment = Enum.TextXAlignment.Left
diag.TextYAlignment = Enum.TextYAlignment.Top
diag.TextWrapped = true
diag.Text = "诊断待开启"
diag.Visible = false
diag.Parent = gui
pcall(function() Instance.new("UICorner", diag).CornerRadius = UDim.new(0, 8) end)

-- 一键复制完整取证报告 (手机端不用开控制台 / 不用截图)
local copyBtn = Instance.new("TextButton")
copyBtn.Name = "WK_Copy"
copyBtn.Size = UDim2.new(0, 92, 0, 26)
copyBtn.Position = UDim2.new(0, 12, 0.30, 278)
copyBtn.BackgroundColor3 = DARK
copyBtn.BorderSizePixel = 0
copyBtn.Font = Enum.Font.GothamBold
copyBtn.Text = "复制诊断"
copyBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
copyBtn.TextSize = 11
copyBtn.Visible = false
copyBtn.Parent = gui
pcall(function() Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 13) end)

copyBtn.Activated:Connect(function()
    local done = false
    pcall(function()
        local env = (type(getgenv) == "function") and getgenv() or _G
        for _, n in ipairs({"setclipboard", "toclipboard", "set_clipboard", "setclip"}) do
            if type(env[n]) == "function" then
                if pcall(env[n], fullReport) then done = true break end
            end
        end
    end)
    copyBtn.Text = done and "已复制" or "无剪贴板"
    task.delay(1.6, function() pcall(function() copyBtn.Text = "复制诊断" end) end)
end)

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
-- 能力B: 自动转弯 V7 (水平障碍探路 + 自适应取证 + 多通道驱动)
-- ==========================================
local RunService = game:GetService("RunService")
local VIM = nil
pcall(function() VIM = game:GetService("VirtualInputManager") end)
local RS = game:GetService("ReplicatedStorage")

local VALUE_KEY = {
    steer=1, turn=1, input=1, direction=1, dir=1, angle=1, wheel=1, yaw=1,
    drive=1, control=1, vehicle=1, car=1, move=1, throttle=1,
    ["转向"]=1, ["方向"]=1, ["角度"]=1, ["驾驶"]=1, ["移动"]=1, ["油门"]=1,
}
local function nameHit(n)
    if not n then return false end
    n = tostring(n):lower()
    for k in pairs(VALUE_KEY) do if n:find(k, 1, true) then return true end end
    return false
end

-- 座位 / 车身 (V6 基础上补 PrimaryPart 作为探路与扭矩目标)
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
    local body = model and model.PrimaryPart or nil
    local target = vs or seat
    return { seat = target, rawSeat = seat, isVehicleSeat = vs ~= nil,
             model = model, root = body or target, body = body, char = char }
end

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

-- 前进方向: 优先实际速度方向 (车身/座位都试), 低速时退回朝向
local function forwardOf(root, alt)
    for _, r in ipairs({root, alt}) do
        if r then
            local ok, vel = pcall(function() return r.AssemblyLinearVelocity end)
            if ok and vel then
                local h = Vector3.new(vel.X, 0, vel.Z)
                if h.Magnitude > 5 then return h.Unit end
            end
        end
    end
    local r = root or alt
    local lv = r.CFrame.LookVector
    local h = Vector3.new(lv.X, 0, lv.Z)
    if h.Magnitude < 0.01 then return Vector3.new(0, 0, -1) end
    return h.Unit
end

-- [TEST_BLOCK_START]
-- 绕 Y 轴旋转水平向量 (正角度 = 左)
local function rotated(v, deg)
    local c, s = math.cos(math.rad(deg)), math.sin(math.rad(deg))
    return Vector3.new(v.X * c + v.Z * s, 0, -v.X * s + v.Z * c)
end

-- V7 探路: 水平障碍射线 (测撞墙距离) + 远处地面连续性 (测路面边界)
--   旧版只「向下找路面」, 在整片大地地图上 9 个方向全命中 → 恒判直路 (诊断 目标 +0.00)
local function probeAhead(root, fw)
    ensureParams()
    local origin = root.Position + Vector3.new(0, PROBE_UP, 0)
    local bestDeg, bestScore = 0, -1
    local frontDist = PROBE_LEN
    for _, deg in ipairs(PROBE_ANGLES) do
        local dir = rotated(fw, deg)
        local d = PROBE_LEN
        local ok, hit = pcall(function()
            return Workspace:Raycast(origin, dir * PROBE_LEN, rayParams)
        end)
        -- 打到地面(法线朝上)不算障碍; 墙/栏杆/树/建筑才算
        if ok and hit and not (hit.Normal and hit.Normal.Y > 0.6) then
            d = hit.Distance
        end
        if deg == 0 then frontDist = d end
        local ground = 0
        for _, dd in ipairs({20, 42}) do
            local ok2, g = pcall(function()
                return Workspace:Raycast(origin + dir * dd + Vector3.new(0, 6, 0),
                                         Vector3.new(0, -40, 0), rayParams)
            end)
            if ok2 and g then ground = ground + (dd == 42 and 2 or 1) end
        end
        local score = (d / PROBE_LEN) * 10 + ground * 1.2 + (1 - math.abs(deg) / 90) * 1.0
        if score > bestScore then bestScore, bestDeg = score, deg end
    end
    return bestDeg, frontDist, bestScore
end
-- [TEST_BLOCK_END]

-- ===== 取证: 定位真实摇杆 / RemoteEvent / 转向 Value =====
-- [TEST_STICK_START]
local function findStick(vpX, vpY)
    stick, stickCenter, stickRadius, knobBase = nil, nil, nil, nil
    stickCands = {}
    local best, bestScore = nil, -1
    for _, parent in ipairs({PlayerGui, CoreGui}) do
        pcall(function()
            for _, o in ipairs(parent:GetDescendants()) do
                if o:IsA("GuiObject") and not o:IsDescendantOf(gui) then
                    local pos, sz = o.AbsolutePosition, o.AbsoluteSize
                    local n = o.Name:lower()
                    local sc = 0
                    if pos.Y > vpY * 0.45 and pos.X < vpX * 0.55 then sc = sc + 6 end
                    if n:find("stick") or n:find("joystick") or n:find("thumb")
                       or n:find("wheel") or n:find("drag") or n:find("steer")
                       or n:find("摇杆") or n:find("方向") then sc = sc + 9 end
                    if sz.X >= 40 and sz.Y >= 40 and sz.X <= 280 and sz.Y <= 280 then
                        local r = sz.X / math.max(sz.Y, 1)
                        if r > 0.65 and r < 1.5 then sc = sc + 5 end
                    end
                    if o:IsA("ImageButton") or o:IsA("ImageLabel") then sc = sc + 2 end
                    if sc >= 6 then
                        table.insert(stickCands, string.format("%s [%s] %.0f,%.0f %dx%d 分%d",
                            o.Name, o.ClassName, pos.X, pos.Y, sz.X, sz.Y, sc))
                        if sc > bestScore then bestScore, best = sc, o end
                    end
                end
            end
        end)
    end
    if STICK_NAME ~= "" then
        pcall(function()
            local o = PlayerGui:FindFirstChild(STICK_NAME, true)
            if not o then o = CoreGui:FindFirstChild(STICK_NAME, true) end
            if o and o:IsA("GuiObject") then best = o end
        end)
    end
    if best then
        stick = best
        local pos, sz = best.AbsolutePosition, best.AbsoluteSize
        stickCenter = Vector2.new(pos.X + sz.X / 2, pos.Y + sz.Y / 2)
        stickRadius = (STICK_RADIUS > 0) and STICK_RADIUS
            or (math.min(sz.X, sz.Y) * 0.38)
        knobBase = best.Position
    end
    return best
end
-- [TEST_STICK_END]

local function findObjects()
    remoteObjs, remoteNames, stickVals, valueNames = {}, {}, {}, {}
    local seen, cnt = {}, 0
    local function walk(root, depth)
        if not root or depth > 4 or cnt > 400 then return end
        pcall(function()
            for _, o in ipairs(root:GetChildren()) do
                cnt = cnt + 1
                if cnt > 400 then break end
                if (o:IsA("RemoteEvent") or o:IsA("UnreliableRemoteEvent")) and not seen[o] then
                    seen[o] = true
                    table.insert(remoteObjs, o)
                    table.insert(remoteNames, o.Name)
                end
                if depth < 4 then walk(o, depth + 1) end
            end
        end)
    end
    walk(RS, 0)
    if veh and veh.model then walk(veh.model, 0) end
    local function vals(root)
        if not root then return end
        pcall(function()
            for _, o in ipairs(root:GetDescendants()) do
                if (o:IsA("NumberValue") or o:IsA("IntValue")) and nameHit(o.Name) then
                    table.insert(stickVals, o)
                    table.insert(valueNames, o.Name .. "=" .. tostring(o.Value))
                end
                if #stickVals >= 12 then break end
            end
        end)
    end
    vals(veh and veh.model)
    vals(PlayerGui)
end

-- ===== 多通道 =====
-- 触摸注入能力探测: 实测两种签名, 结果写进诊断 (不再靠文档猜)
local function detectTouch()
    touchOK, touchSig, touchErr = false, 0, ""
    if not TRY_TOUCH or not VIM then touchErr = "无VirtualInputManager"; return end
    local a = pcall(function()
        VIM:SendTouchEvent(touchId, Enum.UserInputState.End, Vector2.new(5, 5))
    end)
    local b = pcall(function() VIM:SendTouchEvent(5, 5, false) end)
    if a then
        touchOK, touchSig, chanTouch = true, 1, "可用 新签名"
    elseif b then
        touchOK, touchSig, chanTouch = true, 2, "可用 老签名"
    else
        local _, err = pcall(function()
            VIM:SendTouchEvent(touchId, Enum.UserInputState.End, Vector2.new(5, 5))
        end)
        touchErr = tostring(err):sub(1, 60)
        chanTouch = "被拒绝"
    end
end

local function applyTouch(v)
    if not (touchOK and stickCenter) then return end
    local x = stickCenter.X + v * stickRadius * STICK_SIGN
    local y = stickCenter.Y
    if touchSig == 1 then
        if not touchDown then
            pcall(function() VIM:SendTouchEvent(touchId, Enum.UserInputState.Begin,
                                                Vector2.new(stickCenter.X, y)) end)
            touchDown = true
        end
        pcall(function() VIM:SendTouchEvent(touchId, Enum.UserInputState.Change,
                                            Vector2.new(x, y)) end)
    else
        pcall(function() VIM:SendTouchEvent(x, y, true) end)
        pcall(function() VIM:SendTouchEvent(x, y, false) end)
    end
end
local function releaseTouch()
    if touchDown and touchOK and touchSig == 1 and stickCenter then
        pcall(function() VIM:SendTouchEvent(touchId, Enum.UserInputState.End,
                                            Vector2.new(stickCenter.X, stickCenter.Y)) end)
    end
    touchDown = false
end

local function getFireSignal()
    if type(firesignal) == "function" then return firesignal end
    local f
    pcall(function()
        if type(getgenv) == "function" then f = getgenv().firesignal end
    end)
    return f
end
local function applyFireSignal(v)
    if not TRY_FIRESIGNAL or not stick or not stickCenter then return end
    local fs = getFireSignal()
    if type(fs) ~= "function" then chanFire = "无此API"; return end
    local fake = {
        Position = Vector3.new(stickCenter.X + v * stickRadius * STICK_SIGN, stickCenter.Y, 0),
        Delta    = Vector3.new(v * 3, 0, 0),
        UserInputType  = Enum.UserInputType.Touch,
        UserInputState = Enum.UserInputState.Change,
    }
    local ok, err = pcall(function() fs(stick.InputChanged, fake) end)
    chanFire = ok and "OK" or ("错误:" .. tostring(err):sub(1, 22))
end

local function applyKnob(v)
    if not TRY_KNOB or not stick or not knobBase then return end
    local ok = pcall(function()
        stick.Position = UDim2.new(knobBase.X.Scale,
            knobBase.X.Offset + v * stickRadius * STICK_SIGN,
            knobBase.Y.Scale, knobBase.Y.Offset)
    end)
    chanKnob = ok and "OK" or "失败"
end
local function restoreKnob()
    if stick and knobBase then pcall(function() stick.Position = knobBase end) end
end

local function applyValues(v)
    if not TRY_VALUES then return end
    local n = 0
    for _, o in ipairs(stickVals) do
        if pcall(function() o.Value = v end) then n = n + 1 end
    end
    chanVal = (#stickVals == 0) and "无对象" or (n .. "/" .. #stickVals .. " 写入")
end

local function writeSeat(v)
    if not veh or not veh.seat then return end
    local s = veh.seat
    if TRY_SEAT and WRITE_FLOAT then pcall(function() s.SteerFloat = v end) end
    if TRY_SEAT and WRITE_INT then
        pcall(function() s.Steer = (v > 0.15 and 1 or (v < -0.15 and -1 or 0)) end)
    end
    for _, o in ipairs(carValues) do
        pcall(function()
            if o.ClassName == "HingeConstraint" then o.TargetAngle = v * HINGE_ANGLE end
        end)
    end
    if TRY_TORQUE then
        pcall(function()
            local r = veh.body or veh.root
            local av = r.AssemblyAngularVelocity
            r.AssemblyAngularVelocity = Vector3.new(av.X, v * TORQUE_YAW, av.Z)
        end)
    end
end

local function bindVehicle(v)
    if lastSeat == v.seat then return end
    lastSeat = v.seat
    if floatConn then pcall(function() floatConn:Disconnect() end); floatConn = nil end
    floatOK = pcall(function() local _ = v.seat.SteerFloat; v.seat.SteerFloat = 0 end)
    intOK   = pcall(function() local _ = v.seat.Steer; v.seat.Steer = 0 end)
    chanSeat = (floatOK and "Float可写") or (intOK and "Int可写") or "普通Seat/无属性"
    if floatOK then
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
    -- 一次性取证 (只在开启 / 换车时做)
    local cam = Workspace.CurrentCamera
    local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
    findStick(vp.X, vp.Y)
    findObjects()
    detectTouch()
    updateDiag(true)
end

local function startFrameWriter()
    if not EVERY_FRAME or frameConn then return end
    frameConn = RunService.Heartbeat:Connect(function()
        if not AUTO_ON or not veh then return end
        pcall(writeSeat, curSteer)
    end)
end

updateDiag = function(force)
    if not DIAG then return end
    local now = os.clock()
    if not force and now - diagT < 0.3 then return end
    diagT = now
    local seatType = veh and (veh.isVehicleSeat and "VehicleSeat"
        or ("普通" .. (veh.rawSeat and veh.rawSeat.ClassName or "Seat"))) or "未坐车"
    local readback = "-"
    if veh then
        local ok, val = pcall(function() return veh.seat.SteerFloat end)
        if ok and type(val) == "number" then readback = string.format("%+.2f", val) end
    end
    local stickTxt = "-"
    if stick and stickCenter then
        stickTxt = string.format("%s @%.0f,%.0f R%.0f",
            stick.Name, stickCenter.X, stickCenter.Y, stickRadius)
    end
    diag.Text = string.format(
        "座位 %s | %s\n探路 %s\n目标 %+.2f 读回 %s\n摇杆 %s\n触摸 %s | 信号 %s\n通道 knob %s / Val %s / 扭矩 %s\n候选摇杆 %d | Remote %d | Value %d\n点「复制诊断」粘贴完整清单",
        seatType, chanSeat, probeInfo, curSteer, readback, stickTxt,
        chanTouch, chanFire, chanKnob, chanVal, (TRY_TORQUE and "开" or "关"),
        #stickCands, #remoteObjs, #stickVals)
    local L = {}
    local function add(x) L[#L + 1] = x end
    add("=== WK V7 诊断报告 (整段粘贴给我) ===")
    add("座位: " .. seatType .. " | 车模型: " .. ((veh and veh.model and veh.model.Name) or "无"))
    add("车身部件: " .. ((veh and veh.body and veh.body.Name) or "无PrimaryPart"))
    add("座位属性: " .. chanSeat .. " | 读回 " .. readback)
    add("探路: " .. probeInfo .. " | 当前目标 " .. string.format("%+.2f", curSteer))
    add("摇杆锁定: " .. stickTxt)
    add("触摸注入: " .. chanTouch .. " " .. touchErr)
    add("firesignal: " .. chanFire)
    add("--- 摇杆候选 (" .. #stickCands .. ") ---")
    for i, x in ipairs(stickCands) do if i <= 12 then add(x) end end
    add("--- RemoteEvent (" .. #remoteNames .. ") ---")
    for i, x in ipairs(remoteNames) do if i <= 50 then add(x) end end
    add("--- 转向 Value (" .. #valueNames .. ") ---")
    for i, x in ipairs(valueNames) do if i <= 12 then add(x) end end
    add("--- ScreenGui ---")
    pcall(function()
        for _, parent in ipairs({PlayerGui, CoreGui}) do
            for _, o in ipairs(parent:GetChildren()) do
                if o:IsA("ScreenGui") and o ~= gui then
                    add(o.Name .. " [" .. tostring(o.Parent and o.Parent.Name) .. "]")
                end
            end
        end
    end)
    add("=== 把以上全部粘贴给我即可 ===")
    fullReport = table.concat(L, "\n")
end

-- 漂移: 高速急弯叠加横向滑移 + 横摆 (best-effort)
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
        curSteer = curSteer * 0.7
        if math.abs(curSteer) < 0.02 then curSteer = 0 end
        applyTouch(0)
        updateDiag()
        return
    end
    veh = v
    bindVehicle(v)
    local fw = forwardOf(v.root, v.seat)
    local deg, frontDist, score = probeAhead(v.root, fw)
    probeInfo = string.format("最佳%+d° 前方%.0fstud 分%.1f", deg, frontDist, score)
    local raw = 0
    if frontDist < WALL_DANGER then
        -- 正前方近处有墙: 朝最空方向满舵避险 (绝不回正直怼)
        if deg ~= 0 then
            raw = math.max(-1, math.min(1, -deg / TURN_GAIN_DEG))
        else
            raw = (math.abs(curSteer) > 0.05 and (curSteer > 0 and 1 or -1)) or 1
        end
        if math.abs(raw) < 0.85 then raw = raw >= 0 and 0.85 or -0.85 end
    elseif deg ~= 0 then
        raw = math.max(-1, math.min(1, -deg / TURN_GAIN_DEG))
    end
    local target = raw * STEER_SIGN
    curSteer = curSteer + (target - curSteer) * STEER_SMOOTH
    writeSeat(curSteer)
    applyValues(curSteer)
    applyTouch(curSteer)
    applyFireSignal(curSteer)
    applyKnob(curSteer)
    doDrift(v.root, fw, curSteer)
    updateDiag()
    local turning = math.abs(target) > 0.2
    if turning ~= wasTurning then
        wasTurning = turning
        print("[WK] " .. (frontDist < WALL_DANGER and "前方障碍 → 满舵避险"
            or (turning and "弯道 → 自动转向" or "直路 → 回正")))
    end
end

local function startAuto()
    if autoThread then return end
    autoAlive = true
    diag.Visible = DIAG
    copyBtn.Visible = DIAG
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
    releaseTouch()
    restoreKnob()
    lastSeat, rayParams, lastChar, lastModel = nil, nil, nil, nil
    wasTurning = false
    if veh and veh.seat and veh.seat.Parent then
        pcall(function() if floatOK then veh.seat.SteerFloat = 0 end end)
        pcall(function() veh.seat.Steer = 0 end)
    end
    curSteer = 0
    veh = nil
    diag.Visible = false
    copyBtn.Visible = false
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

print("WK 已就绪 (视野 + 自动转弯 V7 · 水平障碍探路 · 自适应取证 · 零联网) [WK_VIEW_V7]")
