-- ===== WK 视野 + 自动转弯 V13 (去雾白昼 · 弯道自动转向/漂移 · 零联网秒启动) =====
-- [WK_VIEW_V13] 用户实测: 「转弯乱抽搐根本转不好」→ 通道仍生效(诊断 通道 fire1 | fire OK),
--   病根不在通道, 在【喂给通道的舵量高频左右横跳】:
--     (1) deg 只有 9 个离散值, TURN_GAIN_DEG=15 → 最小 12° 偏离就给 0.8 舵;
--         弯道护栏让 bestDeg 在相邻拍于 ±12/±28/±50 间跳 → 舵量 +满舵/0/-满舵 翻烧饼
--     (2) STEER_SMOOTH=0.9 把每次跳变 90% 直送滑块 → 抖动放大
--     (3)【物理正反馈·最致命】writeSeat 车身横摆扭矩每帧强设 AssemblyAngularVelocity.Y
--         + doDrift 叠线速度/角速度 → 改车身朝向 → forwardOf 变 → 射线方向变 → deg 再跳 → 自激振荡
--         (诊断「速1」低速车头仍抽, 正是扭矩强设角速度的铁证)
--   => V13【只加决策层转向稳定器 + 切断物理扰动】, 输入通道/视野/UI/诊断渲染全部一字不动:
--         角度死区 + 方向迟滞(换边需连续3拍反向证据) + 限斜率(每拍Δ有上限, 物理上抽不动)
--         + 关车身扭矩 TRY_TORQUE=false / 关漂移 TRY_DRIFT=false (均留开关, 可设回 true)
--         紧急满舵走单独更大斜率, 不拖慢避险; V12 的 130stud 提前量/反应距离全部保留
-- V12 历史 (用户实测): 「确实转了, 但转得慢, 要撞到才转」→ 通道已验证生效(诊断 通道 fire1),
--   本版【只修决策时机】, 转向通道 / 视野 / UI / 诊断渲染全部一字不动。
--   病根 (3 个叠加, 全在探路+决策层, 与通道无关):
--     (1) PROBE_LEN=55 太短: 弯道外侧护栏要开到很近才进射线; 之前 9 个方向全打满 55,
--         得分只差中心偏好 → 恒「最佳+0°」判直路 (用户诊断 前方55stud 分14.6 实锤)
--     (2) WALL_DANGER=18 固定硬阈值: 高速下 18 stud 只剩 0.2~0.3 秒, 物理来不及转
--     (3) 平滑0.8 / 采样0.08 / 增益22: 舵量到位还要爬几拍
--   => V12: 前探 55→130 + 速度自适应反应距离(越快越早打) + 侧向净空差渐进打舵
--           + TURN_GAIN 15 / 平滑0.9 / 采样0.05; 前方近处无路仍满舵避险兜底
--   [关键] 弯道还在 80~130 stud 外就开始打方向, 不再等贴到 18 stud 才满舵。
-- V11 根因 (用户 V10 完整诊断报告实锤, 7 轮盲试全废的原因):
--   【锁错了控件】V7~V10 一直锁定 "ThumbstickStart" (@66,246 R28), 它属于
--   DynamicThumbstickFrame = Roblox 引擎默认的【角色走路摇杆】, 不是开车转向。
--   报告 888 个候选里真正的转向控件是游戏自定义的【横向滑动转向条】:
--     SteerZone [TextButton] 0,93 322x208   <- 转向触摸热区 (名字直译"转向区")
--     Track     [Frame]      27,229 216x12  <- 滑槽, 中心 X = 27+108 = 135
--     Knob      [Frame]      108,208 54x54  <- 滑块, 中心 X = 108+27 = 135
--   两者中心精确重合 = 回正位; 可移动半程 = (216-54)/2 = 81。
--   ThumbstickEnd [ImageLabel] 48,228 36x36 是默认摇杆把手 (备选兼容)。
--   报告另确认: 触摸 被拒绝(VIM 无权限) / UIS 可用 fire OK(firesignal 可用) /
--     学习 -(静止时无转向远程) / Val 无对象 / 座位 普通Seat/无属性 / 前方55stud(直路)。
--   => V11: 精确锁定 SteerZone+Knob, 把已有的 firesignal/UIS/触摸通道【全部校正到
--      真实转向控件】, 补齐缺失的 InputBegan 手势, 直写 Knob.Position, 每条通道结果上屏。
--   => 报告精简: 888 个噪音候选(Scanline/Dot/Selection)过滤, 只留转向相关 + 疑似转向 Remote。
-- 适用: 「不要停止 / make sure to drive fast」等雨夜浓雾黑夜驾驶地图
-- V10 修正 V9 的实测问题 (用户实测截图: 每行右侧仍被裁断, 底部按钮又只露一半):
--   [问题1] TextWrapped=false + 固定像素宽310 + 每行30+字符(含中文), 手机 DPI 放大后
--           文字宽 > 框宽 -> 每行尾部被【横向裁断】("触摸 被拒..." / "firesign..." /
--           "车身 Chass..."); 且 V9 的 clipLine 只作用于分页报告, 实时8行没走截断
--   [问题2] 翻页按钮 y=286 固定像素, 在这台设备上超出屏幕底边 -> 又被切一半
--   -> 布局改为【运行时读真实 Camera.ViewportSize】动态计算: 框高 = 屏高 - 顶栏 - 底边距,
--      按钮固定在右上角顶部 (绝不掉出屏幕), 框宽按屏宽比例钳制, 不再猜 DPI/分辨率
--   -> 截断升级为按【显示宽度】(ASCII=1 / 中文全角=2), 且实时状态改为「一行一个属性」
--      共12个短行, 全部过截断, 任何设备都不会横向裁断
--   -> 报告列出全部 RemoteEvent 名字 (上限 40->60), 便于一次复制取证
--   [实测诊断] 座位 普通Seat/无属性 · 车 Car_8406302455 · 摇杆 ThumbstickStart @66,246 R28
--              UIS 可用 · 触摸 被拒 · 学习 - · 候选 R39 V0 · knob OK
-- V9 修正 V8 的实测问题 (用户: 「属性看不完，建议移到右上角」):
--   [问题] 诊断框在左下角 272x92 / 字号13, 手机 DPI 放大后一页只露出标题+1行,
--          底部被屏幕裁掉; 每页仅4行, 完整属性清单共28页, 根本翻不完 (截图实锤)
--   -> 整个诊断面板移到【右上角】: AnchorPoint(1,0) + Position(1,-12,0,12),
--      绝不溢出屏幕; 框加大到 310x268, 字号缩到 11, 更透 (0.35) 少挡速度表
--   -> 每页 4 行 -> 12 行 (LINES_PER_PAGE), 页数 28 -> 约10
--   -> 实时状态视图 4 行 -> 8 行: 座位属性/通道/车模型/摇杆中心常显, 不翻页也能看全
--   -> 报告中超长行按 UTF-8 字符边界截断, 杜绝 TextWrapped=false 时被框右侧裁掉
--   -> 翻页按钮跟着移到面板正下方, 右对齐; 点诊断框本身同样可翻页
-- V8 修正 V7 的实测问题:
--   [问题1] 用户反馈「根本没有复制诊断」: V7 诊断框塞了 9 行文字 + TextWrapped 自动换行,
--           在手机横屏上溢出屏幕底部, 把下方 y=278 的复制按钮整个挤出可视区 (截图实锤)
--           → 诊断框压缩到 4 行 / 关闭换行 / 字号加大; 复制按钮上移并做成与主开关同宽的大按钮;
--             诊断框本身也可点击; 复制后把完整报告【分页显示在屏幕上】, 不依赖剪贴板 API
--   [问题2] V7 诊断泄露了关键事实: 摇杆真实对象名 = ThumbstickStart (Roblox 引擎自带动态触摸摇杆)
--           → 说明转向输入走 UserInputService.TouchMoved, 不读 Value / knob.Position
--           → 新增 firesignal(UserInputService.TouchMoved) 伪造触摸 + 触摸状态保持
--   [问题3] 座位 普通Seat / 无 SteerFloat (V6 起已确认): 自定义车, 转向值多经 RemoteEvent 上报
--           → 新增 __namecall 学习: 自动捕获游戏自己发的转向 FireServer(实例名+参数格式),
--             之后用同样格式重放脚本算出的舵量; 学到的名字显示在诊断里, 无需用户截图/复制
-- 视野逻辑原样保留: 删高频 DescendantAdded 监听 + 字典查重 + 反制节流 + 10 秒低频巡检
--   性能: 未开启零新增开销; 扫描只在开启/换车时一次; 每帧仅几次属性赋值
--   (V11 视野逻辑基线)

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
local AUTO_TICK      = 0.05  -- 秒; V12 0.08→0.05 采样更密, 舵更快到位
local PROBE_ANGLES   = {-75, -50, -28, -12, 0, 12, 28, 50, 75}  -- 度; 正=左, 负=右
local PROBE_LEN      = 130   -- stud; V12 55→130 大幅提前看到弯道护栏/墙
local PROBE_UP       = 2     -- 射线起点抬高 (避开地面)
local WALL_DANGER    = 22    -- stud; V12 18→22 前方近处无路 → 紧急满舵避险 (兜底)
local TURN_GAIN_DEG  = 15    -- 度; V12 22→15 中等偏离即打满舵 (越小越猛)
local STEER_SIGN     = 1     -- 车往反方向拐 → 改成 -1
local STICK_SIGN     = 1     -- 摇杆左右拖反 → 改成 -1
local STEER_SMOOTH   = 0.9   -- V12 0.8→0.9 舵量几乎即时到位
-- V12 新增: 速度自适应提前介入 (核心: 车速越快, 越早开始打方向)
local REACT_TIME     = 1.1   -- 秒; 反应距离 = 车速(stud/s) × 该值 (越大越早)
local REACT_MIN      = 30    -- stud; 反应距离下限 (低速也留基本提前量)
local REACT_MAX      = 120   -- stud; 反应距离上限 (≤ PROBE_LEN, 保证射线探得到)
local LEAD_GAP_MIN   = 0.12  -- 侧向净空差 > 反应距离×此值 才算真弯道 (防直路乱晃)
-- V13 转向稳定器 (根治抽搐): 舵量每拍变化受限 + 方向迟滞 + 角度死区
local SLEW_UP        = 0.20  -- 常态每拍最大增舵 (0.05s 一拍 → 约 4/s 平滑爬升)
local SLEW_URGENT    = 0.55  -- 紧急满舵(前方近处无路)每拍最大增舵, 不拖慢避险
local SLEW_DOWN      = 0.30  -- 每拍最大回舵
local TURN_DEADZONE  = 0.18  -- 目标舵绝对值小于此 → 视为直路/噪声, 直接当 0
local FLIP_HOLD      = 3     -- 想换转向边, 需连续 N 拍都指向反侧才允许 (防 ± 翻烧饼)
-- 注: STEER_SMOOTH(0.9) 自 V13 起不再用于 autoTick, 改由 smoothSteer 的限斜率取代(保留作历史)
local DRIFT_MIN_SPD  = 35
local DRIFT_MIN_TURN = 0.45
local DRIFT_SIDE     = 10
local DRIFT_YAW      = 0.8
local TORQUE_YAW     = 1.6

-- ==========================================
-- 配置: 转向输出 (V7 自适应取证 + 多通道)
-- ==========================================
-- V11: 依据完整诊断报告, 精确锁定游戏自定义转向条 (不再把走路摇杆当转向控件)
local STEER_ZONE_NAME = "SteerZone"      -- 转向触摸热区 (TextButton 0,93 322x208)
local KNOB_NAME       = "Knob"           -- 滑块把手 (Frame 108,208 54x54)
local TRACK_NAME      = "Track"          -- 横向滑槽 (Frame 27,229 216x12)
local THUMB_END_NAME  = "ThumbstickEnd"  -- 默认摇杆把手 (备选兼容)
local STEER_HALF      = 0                -- 0=按 (Track宽-Knob宽)/2 自动算(报告=81); 也可填固定值
local TRY_STEER       = true             -- 主通道: firesignal 伪造 SteerZone 输入 + 直写 Knob
local SUSPECT_REMOTES = { TurnCall=true, SetHandling=true, SetAutoGas=true, RunEvent=true,
                          StartRun=true, LineCross=true, Crank=true, DriftHintSeen=true }
local STICK_NAME     = ""    -- 置空: 由 findSteer 精确锁定; 需强制指定某对象时填名字
local STICK_RADIUS   = 0     -- 0=按摇杆尺寸自动算; 也可填固定像素如 70
local TRY_TOUCH      = true  -- VirtualInputManager 触摸注入 (带成功/失败回显)
local TRY_UIS        = true  -- firesignal 伪造 UserInputService.TouchMoved (默认摇杆真正读的输入)
local TRY_HOOK       = true  -- 自动学习游戏自己的转向 RemoteEvent 调用
local TRY_REPLAY     = true  -- 用学到的格式重放转向值
local TRY_FIRESIGNAL = true  -- firesignal 触发摇杆输入信号 (若执行器提供)
local TRY_KNOB       = true  -- 直接移动 knob 位置 (降级)
local TRY_VALUES     = true  -- 写名字含 steer/turn/方向 的 Value
local TRY_SEAT       = true  -- 写 SteerFloat / Steer (若座位支持)
local TRY_TORQUE     = false -- V13 关: 每帧强设车身角速度→改朝向→射线自激振荡(抽搐元凶); 留开关可设回 true
local TRY_DRIFT      = false -- V13 关: 漂移叠线速度/角速度同理会扰动探路; 转向稳定后可设回 true
local WRITE_FLOAT    = true
local WRITE_INT      = true
local EVERY_FRAME    = true
local HINGE_ANGLE    = 30
local DIAG           = true  -- 屏幕诊断 (确认工作后可改 false 隐藏)
local LINES_PER_PAGE = 12   -- V10: 运行时按真实屏高动态覆盖 (见下方布局块)

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
local reportLines, reportPage, showingReport = {}, 1, false
local uisOK, hookOK, learnedName, learnedIdx = false, false, "-", 0
local learnedRemote, learnedSample = nil, nil
local updateDiag
local getFireSignal          -- 前向声明: 供 applyFireSignal / applyUIS / bindVehicle 共用同一 upvalue
-- V11: 精确锁定的转向控件 (与 findStick 的 stick 系列分开, 避免 knobBase 被覆盖)
local steerZone, steerKnob, steerTrack, thumbEnd = nil, nil, nil, nil
-- steerCenter 必须非 nil: startAuto() 的首次 updateDiag(true) 早于 findSteer() 执行
local steerCenter, steerHalf, knobHome = Vector2.new(135, 235), 81, nil
local steerDown, chanSteer = false, "未测"
-- V13 转向稳定器跨拍状态: dir=当前转向边(-1/0/1), flip=连续反向证据拍数
local steerSt = { dir = 0, flip = 0 }

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

-- ===== 屏幕诊断 (V10): 右上角 / 运行时按真实屏高布局 / 每行按显示宽度截断 =====
local diag = Instance.new("TextButton")       -- 点诊断框本身也能复制/翻页
diag.Name = "WK_Diag"
diag.AnchorPoint = Vector2.new(1, 0)          -- 右上角为锚点: 框向左下展开
diag.BackgroundColor3 = Color3.fromRGB(12, 16, 20)
diag.BackgroundTransparency = 0.42           -- 更透, 少挡右上角速度表
diag.BorderSizePixel = 0
diag.Font = Enum.Font.GothamBold
diag.TextSize = 9                            -- 缩小字号: 一页装更多行, 更不易横向溢出
diag.TextColor3 = Color3.fromRGB(170, 235, 185)
diag.TextXAlignment = Enum.TextXAlignment.Left
diag.TextYAlignment = Enum.TextYAlignment.Top
diag.TextWrapped = false                     -- 不换行 (靠下方截断保证每行不超宽)
diag.Text = "诊断待开启"
diag.Visible = false
diag.Parent = gui
pcall(function() Instance.new("UICorner", diag).CornerRadius = UDim.new(0, 8) end)

-- 翻页按钮 (V10): 固定在【右上角顶部】, 与屏幕顶边绑定, 绝不掉出屏幕
local copyBtn = Instance.new("TextButton")
copyBtn.Name = "WK_Copy"
copyBtn.AnchorPoint = Vector2.new(1, 0)
copyBtn.BackgroundColor3 = Color3.fromRGB(60, 105, 190)
copyBtn.BorderSizePixel = 0
copyBtn.Font = Enum.Font.GothamBold
copyBtn.Text = "复制诊断 / 翻页"
copyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
copyBtn.TextSize = 12
-- 尺寸/位置由下方动态布局块统一赋值
copyBtn.Visible = false
copyBtn.Parent = gui
pcall(function() Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 22) end)

-- V10 动态布局: 用【真实】Camera.ViewportSize 计算, 不再猜设备 DPI / 固定像素
--   顶栏(按钮) + 间距 + 框 + 底边距 = 屏高, 因此整块永远完整在屏幕内
local DIAG_W, BOX_W = 34, 310                 -- 每行最大显示宽度 / 框宽基准
do
    local vp
    pcall(function()
        local c = Workspace.CurrentCamera
        if c then vp = c.ViewportSize end
    end)
    local VX = (vp and vp.X > 0) and vp.X or 800
    local VY = (vp and vp.Y > 0) and vp.Y or 600
    local TOP, BTN_H, GAP, BOTTOM = 12, 38, 6, 14
    BOX_W  = math.max(210, math.min(360, math.floor(VX * 0.46)))
    local boxH = math.max(140, VY - TOP - BTN_H - GAP - BOTTOM)
    copyBtn.Size     = UDim2.new(0, math.min(210, BOX_W), 0, BTN_H)
    copyBtn.Position = UDim2.new(1, -12, 0, TOP)
    diag.Size        = UDim2.new(0, BOX_W, 0, boxH)
    diag.Position    = UDim2.new(1, -12, 0, TOP + BTN_H + GAP)
    -- 每行约 15 逻辑像素高, 按真实框高算每页行数 (6~16 行)
    LINES_PER_PAGE   = math.max(6, math.min(16, math.floor((boxH - 10) / 15)))
    DIAG_W           = math.max(22, math.min(46, math.floor(BOX_W / 9)))
end

-- 按【显示宽度】截断长行: ASCII=1 / 中文全角=2, 逐字符累加预算,
-- 保证 UTF-8 字符边界完整且绝不横向溢出框宽 (TextWrapped=false 下的唯一保险)
local function clipLine(x, maxW)
    x = tostring(x)
    -- 先算整行显示宽度: 放得下就原样返回, 避免「明明没超宽却加省略号」
    local total, k = 0, 1
    while k <= #x do
        local c = x:byte(k)
        local n = 1
        if c >= 0xF0 then n = 4
        elseif c >= 0xE0 then n = 3
        elseif c >= 0xC0 then n = 2 end
        total = total + ((n == 1) and 1 or 2)
        k = k + n
    end
    if total <= maxW then return x end
    -- 真超宽: 逐字符累加到 budget (预留 3 给 "..."), 保证 UTF-8 边界完整
    local i, w = 1, 0
    local budget = maxW - 3
    while i <= #x do
        local c = x:byte(i)
        local n = 1
        if c >= 0xF0 then n = 4
        elseif c >= 0xE0 then n = 3
        elseif c >= 0xC0 then n = 2 end
        local dw = (n == 1) and 1 or 2        -- 显示宽度
        if w + dw > budget then break end
        w = w + dw
        i = i + n
    end
    return x:sub(1, i - 1) .. "..."
end

-- 点击行为: 1) 尝试剪贴板  2) 无论如何把完整报告分页显示在诊断框(截图即可, 不依赖剪贴板)
local function copyAndPage()
    local done = false
    pcall(function()
        local env = (type(getgenv) == "function") and getgenv() or _G
        for _, n in ipairs({"setclipboard", "toclipboard", "set_clipboard", "setclip"}) do
            if type(env[n]) == "function" then
                if pcall(env[n], fullReport) then done = true break end
            end
        end
    end)
    local pages = math.max(1, math.ceil(#reportLines / LINES_PER_PAGE))
    if not showingReport then
        showingReport = true
        reportPage = 1
    else
        reportPage = reportPage + 1
        if reportPage > pages then reportPage = 1 end
    end
    copyBtn.Text = "报告 " .. reportPage .. "/" .. pages ..
        (done and " · 已复制" or " · 再点翻页")
    if showingReport then
        local from = (reportPage - 1) * LINES_PER_PAGE + 1
        diag.Text = table.concat(reportLines, "\n", from,
            math.min(#reportLines, from + LINES_PER_PAGE - 1))
    else
        updateDiag(true)
    end
end
copyBtn.Activated:Connect(copyAndPage)
diag.Activated:Connect(copyAndPage)          -- 双保险: 点诊断框同样生效

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
    local frontDist, bestDist = PROBE_LEN, PROBE_LEN
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
        if score > bestScore then bestScore, bestDeg, bestDist = score, deg, d end
    end
    return bestDeg, frontDist, bestScore, bestDist
end
-- [TEST_BLOCK_END]

-- [TEST_DECIDE_START]
-- V12 决策纯函数 (可独立测试): 速度自适应提前介入 + 侧向净空差渐进打舵
--   输入: deg=最空方向角 / frontDist=正前方可行距离 / bestDist=最空方向可行距离
--         speed=车速(stud/s) / cur=上一拍舵量(用于选边兜底)
--   返回: raw(目标舵 -1~1), reactDist(反应距离), mode(诊断字符串)
--   <要点> 「前方进入反应距离」且「侧向明显更空」就提前打舵, 不再等 WALL_DANGER 才满舵。
local function decideSteer(deg, frontDist, bestDist, speed, cur)
    local reactDist = math.max(REACT_MIN, math.min(REACT_MAX, speed * REACT_TIME))
    local raw, mode = 0, "直路"
    if frontDist < WALL_DANGER then
        -- 正前方近处无路: 满舵避险 (绝不回正直怼), 判不出方向时沿已有舵向选边
        mode = "紧急满舵"
        if deg ~= 0 then
            raw = math.max(-1, math.min(1, -deg / TURN_GAIN_DEG))
        else
            raw = (math.abs(cur) > 0.05 and (cur > 0 and 1 or -1)) or 1
        end
        if math.abs(raw) < 0.85 then raw = raw >= 0 and 0.85 or -0.85 end
    elseif frontDist < reactDist then
        -- 墙还在「反应距离」内就提前打舵: 越近越急, 侧向净空越好打得越早越猛
        local gap = bestDist - frontDist
        local needTurn = gap > math.max(6, reactDist * LEAD_GAP_MIN)
        local urgency = (reactDist - frontDist) / math.max(1, reactDist - WALL_DANGER)
        urgency = math.max(0, math.min(1, urgency))
        if deg ~= 0 and needTurn then
            raw = math.max(-1, math.min(1, -deg / TURN_GAIN_DEG)) * (0.55 + 0.45 * urgency)
            mode = "提前转向"
        elseif deg ~= 0 then
            raw = math.max(-1, math.min(1, -deg / TURN_GAIN_DEG)) * 0.4 * urgency
            mode = "轻微预判"
        end
    end
    return raw, reactDist, mode
end
-- [TEST_DECIDE_END]

-- [TEST_SMOOTH_START]
-- V13 转向稳定器 (纯函数, 可独立测试): 把 decideSteer 的暴力 target 整形成平滑舵量
--   cur=当前实际舵量 / target=本拍原始目标(已乘 STEER_SIGN) / urgent=是否紧急满舵
--   st=跨拍状态 {dir, flip}   返回: 平滑后的新舵量 (-1~1)
--   三道防线: ①角度死区(小目标归零) ②方向迟滞(换边需连续 FLIP_HOLD 拍反向证据)
--             ③限斜率(每拍 |Δ| 有上限, 物理上根本抽不动)
local function smoothSteer(cur, target, urgent, st)
    -- ① 死区: 直路/射线噪声产生的小目标一律归零, 杜绝直路乱转
    if math.abs(target) < TURN_DEADZONE then target = 0 end
    -- ② 方向迟滞: 想换边必须累积多拍反向证据, 单拍跳变不改向
    local sign = (target > 0 and 1) or (target < 0 and -1) or 0
    if urgent then
        -- 紧急满舵(前方近处无路): 跳过迟滞立即响应, 限斜率(SLEW_URGENT)仍生效
        if sign ~= 0 then st.dir, st.flip = sign, 0 end
    elseif sign ~= 0 and st.dir ~= 0 and sign ~= st.dir then
        st.flip = st.flip + 1
        if st.flip < FLIP_HOLD then
            target = 0                       -- 证据不足: 本拍不打反方向
        else
            st.dir, st.flip = sign, 0        -- 累积证据足够: 允许换边
        end
    else
        if sign ~= 0 then
            st.dir, st.flip = sign, 0        -- 同向证据: 回到原方向, 清零换边计数
        end
        -- sign==0(直路/射线噪声)弃权: 【不清零 flip】, 允许跨噪声累积反向证据,
        --   避免护栏射线「-1,0,-1,0,-1」时永远换不了边 → 撞墙 (实测场景)
    end
    -- ③ 限斜率: 无论 target 跳多大, 每拍实际变化受限 (紧急时放宽)
    local up = urgent and SLEW_URGENT or SLEW_UP
    local lim = (math.abs(target) > math.abs(cur)) and up or SLEW_DOWN
    local d = math.max(-lim, math.min(lim, target - cur))
    local out = cur + d
    if math.abs(out) < 0.02 then out = 0 end
    return out
end
-- [TEST_SMOOTH_END]

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
    -- V11: 校正到真实转向热区 -> applyFireSignal/applyUIS/applyTouch 的坐标与对象随之全部对准
    if steerZone then best = steerZone end
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

-- V11 精确锁定: 报告实锤的 4 个对象 (按名字递归找, 排除脚本自己的 gui)
-- [TEST_STEER_START]
local function findSteer()
    steerZone, steerKnob, steerTrack, thumbEnd = nil, nil, nil, nil
    steerCenter, steerHalf, knobHome = nil, 81, nil
    local function byName(n)
        if not n or n == "" then return nil end
        local o
        pcall(function() o = PlayerGui:FindFirstChild(n, true) end)
        if not o then pcall(function() o = CoreGui:FindFirstChild(n, true) end) end
        if o and o:IsA("GuiObject") and not o:IsDescendantOf(gui) then return o end
        return nil
    end
    steerZone  = byName(STEER_ZONE_NAME)
    steerKnob  = byName(KNOB_NAME)
    steerTrack = byName(TRACK_NAME)
    thumbEnd   = byName(THUMB_END_NAME)
    if steerKnob then pcall(function() knobHome = steerKnob.Position end) end
    -- 中心优先取 Track 中心 (=滑块回正位), 退回 SteerZone 中心
    local ref = steerTrack or steerZone
    if ref then
        pcall(function()
            local pp, sz = ref.AbsolutePosition, ref.AbsoluteSize
            steerCenter = Vector2.new(pp.X + sz.X / 2, pp.Y + sz.Y / 2)
        end)
    end
    -- 半程: (Track宽 - Knob宽)/2 ; 报告 216-54 -> 81
    if STEER_HALF > 0 then
        steerHalf = STEER_HALF
    elseif steerTrack and steerKnob then
        pcall(function()
            steerHalf = math.max(12, (steerTrack.AbsoluteSize.X - steerKnob.AbsoluteSize.X) * 0.5)
        end)
    end
    if not steerCenter then steerCenter = Vector2.new(135, 235) end
    return steerZone
end
-- [TEST_STEER_END]

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
    if not TRY_KNOB or not steerKnob or not knobHome then chanKnob = "无滑块"; return end
    local ok = pcall(function()
        steerKnob.Position = UDim2.new(knobHome.X.Scale,
            knobHome.X.Offset + v * steerHalf * STICK_SIGN,
            knobHome.Y.Scale, knobHome.Y.Offset)
    end)
    chanKnob = ok and "OK" or "失败"
end
local function restoreKnob()
    if steerKnob and knobHome then pcall(function() steerKnob.Position = knobHome end) end
end

-- V8: 伪造 UserInputService.TouchMoved (Roblox 默认动态摇杆 ThumbstickStart 真正读的输入)
getFireSignal = function()
    if type(firesignal) == "function" then return firesignal end
    if type(fire_signal) == "function" then return fire_signal end
    local f
    pcall(function()
        if type(getgenv) == "function" then
            f = getgenv().firesignal or getgenv().fire_signal
        end
    end)
    return f
end
local UIS = game:GetService("UserInputService")
local uisDown = false
local function applyUIS(v)
    if not TRY_UIS or not stickCenter then return end
    local fs = getFireSignal()
    if type(fs) ~= "function" then uisOK = false; return end
    local x = stickCenter.X + v * stickRadius * STICK_SIGN
    local y = stickCenter.Y
    local function fake(state, px, py)
        return {
            Position = Vector3.new(px, py, 0),
            Delta = Vector3.new(v * 3, 0, 0),
            UserInputType = Enum.UserInputType.Touch,
            UserInputState = state,
            KeyCode = Enum.KeyCode.Unknown,
        }
    end
    local ok = pcall(function()
        if not uisDown then
            fs(UIS.TouchStarted, fake(Enum.UserInputState.Begin, stickCenter.X, y), false)
            uisDown = true
        end
        fs(UIS.TouchMoved, fake(Enum.UserInputState.Change, x, y), false)
    end)
    uisOK = ok
end
local function releaseUIS()
    if uisDown then
        local fs = getFireSignal()
        if type(fs) == "function" and stickCenter then
            pcall(function()
                fs(UIS.TouchEnded, {
                    Position = Vector3.new(stickCenter.X, stickCenter.Y, 0),
                    UserInputType = Enum.UserInputType.Touch,
                    UserInputState = Enum.UserInputState.End,
                    KeyCode = Enum.KeyCode.Unknown,
                }, false)
            end)
        end
        uisDown = false
    end
end

-- V11 主通道: firesignal 伪造 SteerZone 的【完整手势】Begin -> Change -> End
--   V8/V10 只发 InputChanged 且打在 ThumbstickStart(走路摇杆)上, 游戏因无活跃触摸而忽略。
-- [TEST_ZONE_START]
local function applySteerZone(v)
    if not TRY_STEER or not steerZone or not steerCenter then chanSteer = "未锁定"; return end
    local fs = getFireSignal()
    if type(fs) ~= "function" then chanSteer = "无firesignal"; return end
    local px = steerCenter.X + v * steerHalf * STICK_SIGN
    local py = steerCenter.Y
    local function fake(state)
        return {
            Position = Vector3.new(px, py, 0),
            Delta    = Vector3.new(v * 4, 0, 0),
            UserInputType  = Enum.UserInputType.Touch,
            UserInputState = state,
            KeyCode = Enum.KeyCode.Unknown,
        }
    end
    local n = 0
    pcall(function()
        if not steerDown then
            fs(steerZone.InputBegan, fake(Enum.UserInputState.Begin)); n = n + 1
            steerDown = true
        end
        fs(steerZone.InputChanged, fake(Enum.UserInputState.Change)); n = n + 1
    end)
    chanSteer = "fire" .. n
end
local function releaseSteerZone()
    if steerDown and steerZone then
        local fs = getFireSignal()
        if type(fs) == "function" and steerCenter then
            pcall(function()
                fs(steerZone.InputEnded, {
                    Position = Vector3.new(steerCenter.X, steerCenter.Y, 0),
                    UserInputType  = Enum.UserInputType.Touch,
                    UserInputState = Enum.UserInputState.End,
                    KeyCode = Enum.KeyCode.Unknown,
                })
            end)
        end
    end
    steerDown = false
end
-- [TEST_ZONE_END]

-- V8: 自动学习游戏自己的转向 RemoteEvent (无需用户截图 / 复制 / 看控制台)
local installHook
installHook = function()
    if hookOK or not TRY_HOOK then return end
    if not (type(hookmetamethod) == "function" and type(getnamecallmethod) == "function"
            and type(newcclosure) == "function") then return end
    pcall(function()
        -- 跨实例复用: 重复执行脚本时, 沿用上一份实例已学到的转向 Remote
        if _G.WK_HookInstalled then
            hookOK = true
            if _G.WK_Learned then
                learnedRemote = _G.WK_Learned.remote or learnedRemote
                learnedIdx    = _G.WK_Learned.idx or learnedIdx
                learnedSample = _G.WK_Learned.sample or learnedSample
                learnedName   = _G.WK_Learned.name or learnedName
            end
            return
        end
        local old
        old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local m = getnamecallmethod()
            if m == "FireServer" and typeof(self) == "Instance" then
                local args = {...}
                -- 只学「-1~1 之间的非整数小数」: 模拟转向的典型特征
                -- 排除 0 / ±1 等整数, 否则大量带 id/标志位的 Remote 会被误学 (实测踩过)
                for i, a in ipairs(args) do
                    if type(a) == "number" and a ~= 0 and math.abs(a) <= 1.001
                       and a ~= math.floor(a) then
                        learnedRemote, learnedIdx = self, i
                        learnedSample = args
                        learnedName = self.Name .. "#" .. i
                        _G.WK_Learned = { remote = self, idx = i, sample = args,
                                          name = learnedName }
                        break
                    end
                end
            end
            return old(self, ...)
        end))
        if old then hookOK = true; _G.WK_HookInstalled = true end
    end)
end

local function replayLearned(v)
    if not TRY_REPLAY or not learnedRemote or not learnedSample then return end
    pcall(function()
        local args = {}
        for i = 1, #learnedSample do args[i] = learnedSample[i] end
        args[learnedIdx] = v
        learnedRemote:FireServer(table.unpack(args, 1, #args))
    end)
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
    findSteer()
    findStick(vp.X, vp.Y)
    findObjects()
    detectTouch()
    installHook()
    pcall(function() uisOK = (type(getFireSignal()) == "function") end)
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
    -- V11 安全别名: startAuto() 的首次 updateDiag(true) 早于 findSteer(), 任何时序都不崩在 .X 上
    local sc = steerCenter or Vector2.new(135, 235)
    local sh = steerHalf or 81
    local seatType = veh and (veh.isVehicleSeat and "VehicleSeat" or "普通Seat") or "未坐车"
    -- 实时状态 (V10): 一行一个属性, 12 个短行, 每行按显示宽度截断, 绝不横向裁断
    local L = {}
    local function put(x) L[#L + 1] = clipLine(x, DIAG_W) end
    put("座位 " .. seatType)
    put(string.format("目标 %+.2f", curSteer))
    put(probeInfo)
    put("转向 " .. ((steerZone and steerZone.Name) or "未锁") .. "/" .. ((steerKnob and steerKnob.Name) or "-"))
    put("触摸 " .. chanTouch)
    put("通道 " .. chanSteer .. " | fire " .. chanFire)
    put("学习 " .. learnedName .. " 候选 R" .. #remoteObjs .. " V" .. #stickVals)
    put("座位属性 " .. chanSeat)
    put("knob " .. chanKnob .. " Val " .. chanVal)
    put("车 " .. ((veh and veh.model and veh.model.Name) or "无"))
    put("车身 " .. ((veh and veh.body and veh.body.Name) or "无"))
    put(string.format("中心 %.0f,%.0f 半程%.0f", sc.X, sc.Y, sh))
    local stateText = table.concat(L, "\n")
    if not showingReport then diag.Text = stateText end

    -- V11 报告精简: 888 个候选里只留【转向相关】, 噪音(Scanline/Dot/Selection)全部剔除
    local function steerRelated(line)
        local l = line:lower()
        for _, k in ipairs({"steer", "knob", "track", "wheel", "thumb", "stick",
                           "joystick", "drag", "zone", "摇杆", "方向"}) do
            if l:find(k, 1, true) then return true end
        end
        return false
    end
    local function suspects(list)
        local out = {}
        for _, nm in ipairs(list) do
            if SUSPECT_REMOTES[nm] then out[#out + 1] = nm end
        end
        return out
    end
    local relCands = {}
    for _, x in ipairs(stickCands) do
        if steerRelated(x) and #relCands < 24 then relCands[#relCands + 1] = x end
    end
    local susp = suspects(remoteNames)

    -- 完整报告 (点「复制诊断 / 翻页」会分页显示, 也可复制整段文本)
    local R = {}
    local function add(x) R[#R + 1] = clipLine(x, DIAG_W) end
    add("=== WK V13 诊断报告 ===")
    for _, x in ipairs(L) do add(x) end           -- 复用实时 12 短行, 不重复拼长句
    add("--- V13 锁定对象 ---")
    add("热区 " .. ((steerZone and steerZone.Name) or "未锁") ..
        " 滑块 " .. ((steerKnob and steerKnob.Name) or "-") ..
        " 槽 " .. ((steerTrack and steerTrack.Name) or "-"))
    add(string.format("中心 %.0f,%.0f 半程%.0f fire %s", sc.X, sc.Y, sh, chanSteer))
    add("--- 转向候选 (" .. #relCands .. "/" .. #stickCands .. ") ---")
    for _, x in ipairs(relCands) do add(x) end
    add("--- 疑似转向 Remote (" .. #susp .. ") ---")
    for _, x in ipairs(susp) do add(x) end
    add("--- RemoteEvent (" .. #remoteNames .. ") ---")
    for i2, x in ipairs(remoteNames) do if i2 <= 40 then add(x) end end
    add("--- 转向 Value (" .. #valueNames .. ") ---")
    for i2, x in ipairs(valueNames) do if i2 <= 12 then add(x) end end
    add("=== 学到 " .. learnedName .. " | 报告共 " .. #R .. " 行 ===")
    reportLines = R
    -- 复制到剪贴板的版本【不截断】: 完整对象名一次给全, 便于精确接管
    local F = {}
    local function addF(x) F[#F + 1] = x end
    addF("=== WK V13 完整诊断 (未截断·已滤噪音) ===")
    for _, x in ipairs(L) do addF(x) end
    addF("--- V13 锁定对象 ---")
    addF("热区 " .. ((steerZone and steerZone.Name) or "未锁") ..
         " 滑块 " .. ((steerKnob and steerKnob.Name) or "-") ..
         " 槽 " .. ((steerTrack and steerTrack.Name) or "-") ..
         " 备选 " .. ((thumbEnd and thumbEnd.Name) or "-"))
    addF(string.format("中心 %.0f,%.0f 半程%.0f fire %s", sc.X, sc.Y, sh, chanSteer))
    addF("--- 转向候选 (" .. #relCands .. "/" .. #stickCands .. ") ---")
    for _, x in ipairs(relCands) do addF(x) end
    addF("--- 疑似转向 Remote (" .. #susp .. ") ---")
    for _, x in ipairs(susp) do addF(x) end
    addF("--- RemoteEvent (" .. #remoteNames .. ") ---")
    for _, x in ipairs(remoteNames) do addF(x) end
    addF("--- 转向 Value (" .. #valueNames .. ") ---")
    for _, x in ipairs(valueNames) do addF(x) end
    fullReport = table.concat(F, "\n")
    if showingReport then
        local pages = math.max(1, math.ceil(#reportLines / LINES_PER_PAGE))
        if reportPage > pages then reportPage = 1 end
        local from = (reportPage - 1) * LINES_PER_PAGE + 1
        diag.Text = table.concat(reportLines, "\n", from,
            math.min(#reportLines, from + LINES_PER_PAGE - 1))
    end
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
    local deg, frontDist, _, bestDist = probeAhead(v.root, fw)
    local speed = 0
    pcall(function()
        local vel = v.root.AssemblyLinearVelocity
        speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
    end)
    local raw, reactDist, mode = decideSteer(deg, frontDist, bestDist, speed, curSteer)
    probeInfo = string.format("最佳%+d° 前%.0f 侧%.0f 反%.0f 速%.0f",
        deg, frontDist, bestDist, reactDist, speed)
    local target = raw * STEER_SIGN
    local urgent = (mode == "紧急满舵")
    curSteer = smoothSteer(curSteer, target, urgent, steerSt)
    writeSeat(curSteer)
    applyValues(curSteer)
    applyTouch(curSteer)
    applyUIS(curSteer)
    replayLearned(curSteer)
    applyFireSignal(curSteer)
    applyKnob(curSteer)
    applySteerZone(curSteer)
    if TRY_DRIFT then doDrift(v.root, fw, curSteer) end
    updateDiag()
    local turning = math.abs(target) > 0.2
    if turning ~= wasTurning then
        wasTurning = turning
        print("[WK] " .. mode .. (turning and " → 自动转向" or " → 回正"))
    end
end

local function startAuto()
    if autoThread then return end
    autoAlive = true
    diag.Visible = DIAG
    copyBtn.Visible = DIAG
    copyBtn.Text = "复制诊断 / 翻页"
    showingReport, reportPage = false, 1
    steerSt.dir, steerSt.flip = 0, 0        -- V13 每次开启重置稳定器
    installHook()
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
    releaseUIS()
    releaseSteerZone()
    restoreKnob()
    lastSeat, rayParams, lastChar, lastModel = nil, nil, nil, nil
    wasTurning = false
    if veh and veh.seat and veh.seat.Parent then
        pcall(function() if floatOK then veh.seat.SteerFloat = 0 end end)
        pcall(function() veh.seat.Steer = 0 end)
    end
    curSteer = 0
    steerSt.dir, steerSt.flip = 0, 0        -- V13
    veh = nil
    diag.Visible = false
    copyBtn.Visible = false
    showingReport, reportPage = false, 1
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

print("WK 已就绪 (视野 + 自动转弯 V13 · 转向稳定器防抽搐 · 零联网) [WK_VIEW_V13]")
