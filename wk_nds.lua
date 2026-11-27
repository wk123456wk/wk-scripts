-- ===== WK 一键白昼 (强制去雾 + 去黑夜 · 单开关 · 零联网秒启动) =====
-- 适用: 「不要停止 / make sure to drive fast」等雨夜浓雾/黑夜地图
-- 特点: 不加载任何UI库 / 不联网 / 无启动动画 / 无通知, 执行即出开关并生效
-- 原理: 每帧强制锁定 Lighting(含后处理)为白天清晰值, 地图重设会被立刻压回

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
-- ① 目标「白天无雾」参数 (每帧强制写回)
-- ==========================================
local DAY = {
    ClockTime            = 12,                              -- 正午
    Brightness           = 2,
    FogStart             = 0,
    FogEnd               = 1000000,                         -- 雾拉到极远 = 无雾
    Ambient              = Color3.fromRGB(200, 200, 200),
    OutdoorAmbient       = Color3.fromRGB(200, 200, 200),
    ColorShift_Top       = Color3.fromRGB(255, 255, 255),
    ColorShift_Bottom    = Color3.fromRGB(255, 255, 255),
    ExposureCompensation = 0,
}

-- ② 各类「雾 / 暗化 / 夜空」效果 → 压成无害值 (每帧强制)
local FX = {
    Atmosphere            = {Density=0, Haze=0, Glare=0},   -- 体积雾
    ColorCorrectionEffect = {Enabled=false},                 -- 暗色/去饱和滤镜
    BlurEffect            = {Enabled=false},                 -- 模糊
    DepthOfFieldEffect    = {Enabled=false},                 -- 景深
    SunRaysEffect         = {Enabled=false},
    BloomEffect           = {Enabled=false},
    Sky                   = {                               -- 夜空盒: 清空贴图/星星
        SkyboxBk="", SkyboxDn="", SkyboxFt="", SkyboxLf="", SkyboxRt="", SkyboxUp="",
        StarCount=0, SunTextureId="", MoonTextureId="",
    },
}

local ON        = false
local backup    = nil      -- Lighting 原始属性
local snapProps = {}       -- 效果对象 → 原始属性快照
local forceConn = nil

local function setP(obj, prop, val) pcall(function() obj[prop] = val end) end
local function getP(obj, prop)
    local ok, v = pcall(function() return obj[prop] end)
    if ok then return v end
end

-- 记录一次原值, 然后压成无害值
local function suppress(obj)
    local props = FX[obj.ClassName]
    if not props then return end
    if not snapProps[obj] then
        local s = {}
        for k in pairs(props) do s[k] = getP(obj, k) end
        snapProps[obj] = s
    end
    for k, v in pairs(props) do setP(obj, k, v) end
end

-- 每帧强制: 属性写回 + 扫描 Lighting/Camera 下所有雾/暗化效果
local function applyFrame()
    for k, v in pairs(DAY) do setP(Lighting, k, v) end
    for _, obj in ipairs(Lighting:GetDescendants()) do
        if FX[obj.ClassName] then suppress(obj) end
    end
    local cam = Workspace.CurrentCamera
    if cam then
        for _, obj in ipairs(cam:GetDescendants()) do
            if FX[obj.ClassName] then suppress(obj) end
        end
    end
end

-- 关闭时恢复原样
local function restore()
    for obj, s in pairs(snapProps) do
        for k, v in pairs(s) do
            if v ~= nil then setP(obj, k, v) end
        end
    end
    snapProps = {}
    if backup then
        for k, v in pairs(backup) do
            if v ~= nil then setP(Lighting, k, v) end
        end
        backup = nil
    end
end

-- ==========================================
-- ③ 唯一的 UI: 一个胶囊开关按钮 (原生, 触屏可点)
-- ==========================================
local gui = Instance.new("ScreenGui")
gui.Name = "WK_DayToggle"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
local ok = pcall(function() gui.Parent = CoreGui end)
if not ok or not gui.Parent then gui.Parent = PlayerGui end

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(0, 140, 0, 44)
btn.Position = UDim2.new(0, 12, 0.32, 0)
btn.BackgroundColor3 = Color3.fromRGB(40, 44, 48)
btn.BorderSizePixel = 0
btn.Font = Enum.Font.GothamBold
btn.Text = "白昼模式：关"
btn.TextColor3 = Color3.fromRGB(220, 220, 220)
btn.TextSize = 14
btn.Parent = gui
Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 22)

local function refresh()
    if ON then
        btn.Text = "白昼模式：开"
        btn.BackgroundColor3 = Color3.fromRGB(0, 170, 90)
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
        btn.Text = "白昼模式：关"
        btn.BackgroundColor3 = Color3.fromRGB(40, 44, 48)
        btn.TextColor3 = Color3.fromRGB(220, 220, 220)
    end
end

local function setOn(v)
    ON = v
    if forceConn then forceConn:Disconnect(); forceConn = nil end
    if ON then
        if not backup then
            backup = {}
            for k in pairs(DAY) do backup[k] = getP(Lighting, k) end
        end
        applyFrame()                                         -- 立即生效, 不等下一帧
        forceConn = RunService.Heartbeat:Connect(applyFrame)  -- 每帧强制锁定
    else
        restore()
    end
    refresh()
end

-- Activated: 鼠标/触摸/手柄统一单次触发, 避免手机端 MouseButton1Click+TouchTap 双触发
local lastTap = 0
btn.Activated:Connect(function()
    if tick() - lastTap < 0.2 then return end
    lastTap = tick()
    setOn(not ON)
end)

_G.WK_Day_Cleanup = function()
    if forceConn then forceConn:Disconnect(); forceConn = nil end
    restore()
end

-- 默认开启: 执行即变白天 (点按钮可关闭恢复夜景)
setOn(true)

print("WK 一键白昼 已就绪 [WK_DAY_V1]")
