-- ===== WK 视野 (强制去雾 + 去黑夜 · 防闪烁 · 零联网秒启动) =====
-- 适用: 「不要停止 / make sure to drive fast」等雨夜浓雾黑夜驾驶地图
-- 只保留视野: 已按要求删除【怪物检测 / 三级测距 / 高亮 / 防怪推离 / 自动传送 / 诊断面板】全部逻辑
-- 特点: 不加载任何UI库 / 不联网 / 无启动动画 / 无常驻循环, 执行即出开关并生效
-- 防闪烁: 雾/暗化效果整体移出渲染树 + Lighting标量属性变更即时反制 (只写一次, 不与地图每帧对拉)
-- 单开关: 「WK 视野」一键开/关, 默认开启; 关闭恢复原始夜景
--   [WK_VIEW_V1]

local Lighting  = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local CoreGui   = game:GetService("CoreGui")
local Players   = game:GetService("Players")
local p         = Players.LocalPlayer
local PlayerGui = p:WaitForChild("PlayerGui")

-- 防多开: 让上一份实例恢复夜景并销毁旧UI
if _G.WK_Day_Cleanup then pcall(_G.WK_Day_Cleanup) end
for _, parent in ipairs({CoreGui, PlayerGui}) do
    for _, obj in ipairs(parent:GetChildren()) do
        if obj.Name == "WK_DayToggle" then pcall(function() obj:Destroy() end) end
    end
end

-- ==========================================
-- 配置
-- ==========================================
-- ① 目标「白天无雾」标量 (只在被地图改动时写回, 不每帧重写 → 不闪)
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
-- ② 雾/暗化/夜空/后处理效果类 → 整体移出渲染树 (地图改不到, 根除闪烁)
local FX = {
    Atmosphere = true, ColorCorrectionEffect = true, BlurEffect = true,
    DepthOfFieldEffect = true, SunRaysEffect = true, BloomEffect = true, Sky = true,
}
local GREEN = Color3.fromRGB(40, 175, 95)
local DARK  = Color3.fromRGB(40, 44, 48)

-- ==========================================
-- 状态
-- ==========================================
local ON = true
local dayOn = false
local backup, stash = nil, {}
local scalarConns, fxConns = {}, {}

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
-- UI: 仅一个开关按钮
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
btn.BackgroundColor3 = DARK
btn.BorderSizePixel = 0
btn.Font = Enum.Font.GothamBold
btn.Text = "WK 视野：关"
btn.TextColor3 = Color3.fromRGB(230, 230, 230)
btn.TextSize = 14
btn.Parent = gui
Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 22)

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

-- ==========================================
-- 视野: 去雾 + 去黑夜 (移出效果 + 标量反制) —— 原样保留
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
local function enableView()
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
            table.insert(scalarConns, c)
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
local function disableView()
    if not dayOn then return end
    dayOn = false
    for _, c in ipairs(scalarConns) do pcall(function() c:Disconnect() end) end
    scalarConns = {}
    for _, c in ipairs(fxConns) do pcall(function() c:Disconnect() end) end
    fxConns = {}
    if backup then
        for k, v in pairs(backup) do if v ~= nil then setP(Lighting, k, v) end end
        backup = nil
    end
    moveBackAll()
end

-- ==========================================
-- 按钮: 一键开/关 (Activated 统一鼠标+触摸, 防抖避免手机双触发)
-- ==========================================
local lastTap = 0
btn.Activated:Connect(function()
    if tick() - lastTap < 0.2 then return end
    lastTap = tick()
    ON = not ON
    if ON then enableView() else disableView() end
    refresh()
end)

_G.WK_Day_Cleanup = function()
    pcall(disableView)
    pcall(function() gui:Destroy() end)
end

-- 默认开启: 执行即去雾白昼
refresh()
enableView()

print("WK 视野 已就绪 (仅去雾/白昼 · 防闪烁 · 零联网) [WK_VIEW_V1]")
