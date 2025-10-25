-- TuanxAura_Hub_v19_Improved_Vietnamese.lua
-- Phiên bản: v19 Improved (cải tiến độ ổn định)
-- Tác vụ: HUD hiện đại + ESP UI + AutoFind/AutoStore/AutoHop + Lưu stats JSON + Toggle UI
-- Hướng dẫn: Thay IMAGE_ID = "rbxassetid://123456789" bằng asset id bạn muốn.
-- Lưu ý: Script này KHÔNG chứa mã exploit (không dùng getgc/getfenv/getconstants). Chỉ hoạt động trên executor hỗ trợ API cần thiết.

-- ========== CẤU HÌNH (Chỉnh trong code) ==========
local IMAGE_ID = "rbxassetid://13483203475" -- <-- Thay bằng asset id bạn muốn (ví dụ: "rbxassetid://1234567890")
local UI_SCALE = 1             -- tỉ lệ kích thước UI
local ESP_MAX_SHOW = 5         -- số trái hiển thị trong danh sách ESP UI
local FRUIT_PROXIMITY = 500    -- phạm vi tìm trái (mét)
local FRUIT_SCAN_INTERVAL = 0.8-- giây giữa 2 lần scan
local HOP_TIMEOUT = 40         -- giây không tìm được trái -> hop
local STORE_INTERVAL = 2.0     -- giây giữa 2 lần thử lưu vào bank
local FLIGHT_SPEED = 150       -- tốc độ bay mô phỏng
local MAX_TRAVEL_TIME = 5.0    -- thời gian di chuyển tối đa
local DEBUG_MODE = false       -- bật = in log debug và notify thêm
local INVOKE_RETRIES = 3
local INVOKE_BACKOFF = 0.18

-- Tên file stats (JSON) để lưu tiến trình
local STATS_FILE = "TuanxAura_Stats.json"

-- ========== BẢO VỆ DOUBLE-RUN ==========
if _G.TuanxAura_v19_Improved_Vietnamese_Ran then return end
_G.TuanxAura_v19_Improved_Vietnamese_Ran = true

-- ========== SERVICES ==========
local function gs(n) local ok,s = pcall(function() return game:GetService(n) end) return ok and s or nil end
local Players = gs("Players") or game.Players
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = gs("ReplicatedStorage") or game:GetService("ReplicatedStorage")
local Workspace = gs("Workspace") or game.Workspace
local TweenService = gs("TweenService") or game:GetService("TweenService")
local HttpService = gs("HttpService") or game:GetService("HttpService")
local TeleportService = gs("TeleportService") or game:GetService("TeleportService")
local RunService = gs("RunService") or game:GetService("RunService")
local StarterGui = gs("StarterGui") or game:GetService("StarterGui")
local UserInputService = gs("UserInputService")

-- ========== TIỆN ÍCH ==========
local function safeWait(t) task.wait(t or 0.03) end
local function SetProps(obj, props) pcall(function() for k,v in pairs(props) do obj[k]=v end end) return obj end
local function getHRP() return LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") end
local function DebugLog(msg)
    if DEBUG_MODE then
        pcall(function() print("[TuanxAura DEBUG] "..tostring(msg)) end)
    end
end

-- ========== THỐNG KÊ ==========
local stats = { picked = 0, stored = 0, hops = 0, startTime = tick(), lastFruitFound = 0 }

-- ========== UI CREATION (HUD hiện đại, 2 cột, toggle) ==========
-- Tạo ScreenGui & background
local PlayerGui = (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")) or StarterGui
if not PlayerGui then PlayerGui = StarterGui end

local ScreenGui = SetProps(Instance.new("ScreenGui"), {
    Name = "TuanxAura_Hub_v19", Parent = PlayerGui, ZIndexBehavior = Enum.ZIndexBehavior.Sibling
})

-- Background ảnh full màn
local Bg = SetProps(Instance.new("ImageLabel"), {
    Parent = ScreenGui, Name = "Background", Size = UDim2.fromScale(1,1), Position = UDim2.new(0,0,0,0),
    BackgroundTransparency = 1, Image = IMAGE_ID, ScaleType = Enum.ScaleType.Crop, ZIndex = 1
})

-- Overlay mờ tối để chữ đọc tốt
local BlurContainer = SetProps(Instance.new("Frame"), {
    Parent = ScreenGui, Name = "BlurContainer", Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, ZIndex = 2
})
local DarkOverlay = SetProps(Instance.new("Frame"), {
    Parent = BlurContainer, Name = "Overlay", Size = UDim2.new(1,0,1,0),
    BackgroundColor3 = Color3.fromRGB(5,5,8), BackgroundTransparency = 0.55, ZIndex = 2
})
Instance.new("UICorner", DarkOverlay).CornerRadius = UDim.new(0,0)

-- Container trung tâm cho HUD (dễ ẩn/hiện)
local HudContainer = SetProps(Instance.new("Frame"), {
    Parent = BlurContainer, Name = "HudContainer", Size = UDim2.new(0.55 * UI_SCALE,0,0.42 * UI_SCALE,0),
    Position = UDim2.new(0.5,0,0.08,0), AnchorPoint = Vector2.new(0.5,0), BackgroundTransparency = 1, ZIndex = 3
})

-- Tiêu đề ở giữa trên
local Title = SetProps(Instance.new("TextLabel"), {
    Parent = HudContainer, Name = "Title", Size = UDim2.new(1,0,0,38), Position = UDim2.new(0,0,0,0),
    BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 22 * UI_SCALE, Text = "💎 TUANXAURA HUB 💙",
    TextColor3 = Color3.fromRGB(220, 240, 255), TextStrokeColor3 = Color3.fromRGB(30,140,255), TextStrokeTransparency = 0.4,
    ZIndex = 4
})
local function makeGlow(lbl)
    local stroke = Instance.new("UIStroke")
    stroke.Parent = lbl
    stroke.Color = Color3.fromRGB(30,140,255)
    stroke.Thickness = 2
    stroke.Transparency = 0.3
    stroke.LineJoinMode = Enum.LineJoinMode.Round
end
makeGlow(Title)

-- Cột trái & cột phải
local LeftCol = SetProps(Instance.new("Frame"), {
    Parent = HudContainer, Name = "LeftCol", Size = UDim2.new(0.48,0,0.8,0), Position = UDim2.new(0,0,0,48),
    BackgroundTransparency = 0.12, BackgroundColor3 = Color3.fromRGB(10,10,12), ZIndex = 4
})
Instance.new("UICorner", LeftCol).CornerRadius = UDim.new(0,8)
SetProps(Instance.new("UIStroke"), {Parent = LeftCol, Color = Color3.fromRGB(30,140,255), Thickness = 1})

local RightCol = SetProps(Instance.new("Frame"), {
    Parent = HudContainer, Name = "RightCol", Size = UDim2.new(0.48,0,0.8,0), Position = UDim2.new(0.52,0,0,48),
    BackgroundTransparency = 0.12, BackgroundColor3 = Color3.fromRGB(10,10,12), ZIndex = 4
})
Instance.new("UICorner", RightCol).CornerRadius = UDim.new(0,8)
SetProps(Instance.new("UIStroke"), {Parent = RightCol, Color = Color3.fromRGB(30,140,255), Thickness = 1})

-- Label trạng thái (bên trái)
local StatusLabel = SetProps(Instance.new("TextLabel"), {
    Parent = LeftCol, Name = "Status", Size = UDim2.new(1,-12,0,28), Position = UDim2.new(0,6,0,6),
    BackgroundTransparency = 1, Font = Enum.Font.SourceSansBold, TextSize = 16 * UI_SCALE,
    Text = "⚙️ Trạng thái: Khởi động...", TextColor3 = Color3.fromRGB(230,240,255), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5
})
makeGlow(StatusLabel)

-- Label trái đã lưu (bên trái)
local StoredLabel = SetProps(Instance.new("TextLabel"), {
    Parent = LeftCol, Name = "Stored", Size = UDim2.new(1,-12,0,22), Position = UDim2.new(0,6,0,40),
    BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 15 * UI_SCALE,
    Text = "🍈 Trái đã lưu: 0", TextColor3 = Color3.fromRGB(220,235,255), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5
})
makeGlow(StoredLabel)

-- Label thời gian (bên trái)
local TimeLabel = SetProps(Instance.new("TextLabel"), {
    Parent = LeftCol, Name = "Time", Size = UDim2.new(1,-12,0,22), Position = UDim2.new(0,6,0,64),
    BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 15 * UI_SCALE,
    Text = "⏱ Thời gian: 00:00:00", TextColor3 = Color3.fromRGB(220,235,255), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5
})
makeGlow(TimeLabel)

-- ESP header và khung danh sách
local EspHeader = SetProps(Instance.new("TextLabel"), {
    Parent = LeftCol, Name = "EspHeader", Size = UDim2.new(1,-12,0,20), Position = UDim2.new(0,6,0,94),
    BackgroundTransparency = 1, Font = Enum.Font.SourceSansBold, TextSize = 14 * UI_SCALE,
    Text = "🔍 Trái gần nhất:", TextColor3 = Color3.fromRGB(200,230,255), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5
})
makeGlow(EspHeader)

local EspList = SetProps(Instance.new("Frame"), {
    Parent = LeftCol, Name = "EspList", Size = UDim2.new(1,-12,0, (ESP_MAX_SHOW * 22) + 8), Position = UDim2.new(0,6,0,118),
    BackgroundTransparency = 1, ZIndex = 5
})

-- Tạo hàng ESP UI
local function CreateEspRow(parent, idx)
    local row = SetProps(Instance.new("TextLabel"), {
        Parent = parent, Name = "EspRow"..tostring(idx), Size = UDim2.new(1,0,0,20), Position = UDim2.new(0,0,0,(idx-1)*22),
        BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 14 * UI_SCALE,
        Text = "", TextColor3 = Color3.fromRGB(240,240,245), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5
    })
    return row
end
local EspRows = {}
for i=1, ESP_MAX_SHOW do EspRows[i] = CreateEspRow(EspList, i) end

-- Bên phải: số trái nhặt
local PickedLabel = SetProps(Instance.new("TextLabel"), {
    Parent = RightCol, Name = "Picked", Size = UDim2.new(1,-12,0,28), Position = UDim2.new(0,6,0,6),
    BackgroundTransparency = 1, Font = Enum.Font.SourceSansBold, TextSize = 16 * UI_SCALE,
    Text = "🥭 Trái đã nhặt: 0", TextColor3 = Color3.fromRGB(230,240,255), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5
})
makeGlow(PickedLabel)

local HopLabel = SetProps(Instance.new("TextLabel"), {
    Parent = RightCol, Name = "Hop", Size = UDim2.new(1,-12,0,22), Position = UDim2.new(0,6,0,40),
    BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 15 * UI_SCALE,
    Text = "🌍 Số lần hop: 0", TextColor3 = Color3.fromRGB(220,235,255), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5
})
makeGlow(HopLabel)

local NameLabel = SetProps(Instance.new("TextLabel"), {
    Parent = RightCol, Name = "Name", Size = UDim2.new(1,-12,0,22), Position = UDim2.new(0,6,0,64),
    BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 15 * UI_SCALE,
    Text = "👤 Người chơi: "..(LocalPlayer and LocalPlayer.Name or "Unknown"), TextColor3 = Color3.fromRGB(220,235,255), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5
})
makeGlow(NameLabel)

-- Nút ẩn/hiện UI góc trên phải
local ToggleBtn = SetProps(Instance.new("TextButton"), {
    Parent = ScreenGui, Name = "ToggleHUD", Size = UDim2.new(0,36,0,24), Position = UDim2.new(1,-42,0,8),
    AnchorPoint = Vector2.new(0,0), BackgroundColor3 = Color3.fromRGB(18,18,22), BackgroundTransparency = 0.12, Text = "UI",
    Font = Enum.Font.SourceSansBold, TextSize = 14, TextColor3 = Color3.fromRGB(220,240,255), ZIndex = 6
})
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0,6)
SetProps(Instance.new("UIStroke"), {Parent = ToggleBtn, Color = Color3.fromRGB(30,140,255), Thickness = 1})

local UI_VISIBLE = true
local function SetUIVisible(v)
    UI_VISIBLE = v
    pcall(function()
        HudContainer.Visible = v
        DarkOverlay.Visible = v
        Bg.Visible = v
    end)
end
ToggleBtn.MouseButton1Click:Connect(function() SetUIVisible(not UI_VISIBLE) end)
pcall(function()
    if UserInputService then
        UserInputService.InputBegan:Connect(function(inp, gp)
            if gp then return end
            if inp.KeyCode == Enum.KeyCode.RightControl then SetUIVisible(not UI_VISIBLE) end
        end)
    end
end)

-- ========== ESP WORLD: SelectionBox + Billboard ==========
local selectionBoxes = {}
local function ensureSelectionBoxFor(model)
    if not model then return end
    if selectionBoxes[model] and selectionBoxes[model].Parent then return selectionBoxes[model] end
    local handle = model:FindFirstChild("Handle") or model:FindFirstChildWhichIsA("BasePart") or model.PrimaryPart
    if not handle then return end
    local box = Instance.new("SelectionBox")
    box.Name = "TuanxAura_SelectionBox"
    box.Adornee = handle
    box.Color3 = Color3.fromRGB(80,160,255)
    box.LineThickness = 0.006
    box.SurfaceTransparency = 0.8
    box.Parent = Workspace
    selectionBoxes[model] = box
    return box
end
local function removeSelectionBoxFor(model)
    if selectionBoxes[model] then
        pcall(function() selectionBoxes[model]:Destroy() end)
        selectionBoxes[model] = nil
    end
end
local function cleanupSelectionBoxes()
    for m, box in pairs(selectionBoxes) do
        if not m or not m.Parent or (box and box.Adornee == nil) then
            pcall(function() if box then box:Destroy() end end)
            selectionBoxes[m] = nil
        end
    end
end

-- ========== JSON SAVE / LOAD (Lưu tiến trình) ==========
local function LoadStats()
    if type(isfile) ~= "function" or type(readfile) ~= "function" or not HttpService then
        DebugLog("File API không có, bỏ qua LoadStats")
        return {Picked=0,Stored=0,HopCount=0}
    end
    if not isfile(STATS_FILE) then
        pcall(function() writefile(STATS_FILE, HttpService:JSONEncode({Picked=0,Stored=0,HopCount=0})) end)
        return {Picked=0,Stored=0,HopCount=0}
    end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(STATS_FILE)) end)
    if ok and data then
        return {Picked = tonumber(data.Picked or 0), Stored = tonumber(data.Stored or 0), HopCount = tonumber(data.HopCount or 0)}
    else
        return {Picked=0,Stored=0,HopCount=0}
    end
end

local function SaveStats()
    if type(writefile) ~= "function" or not HttpService then
        DebugLog("File API không có, bỏ qua SaveStats")
        return
    end
    local tbl = {Picked=stats.picked, Stored=stats.stored, HopCount=stats.hops}
    pcall(function() writefile(STATS_FILE, HttpService:JSONEncode(tbl)) end)
end

-- Gọi Load lúc bắt đầu
do
    local old = LoadStats()
    stats.picked = old.Picked or 0
    stats.stored = old.Stored or 0
    stats.hops = old.HopCount or 0
    pcall(function()
        PickedLabel.Text = "🥭 Trái đã nhặt: "..tostring(stats.picked)
        StoredLabel.Text = "🍈 Trái đã lưu: "..tostring(stats.stored)
        HopLabel.Text = "🌍 Số lần hop: "..tostring(stats.hops)
    end)
end

-- ========== Remote store helper (phát hiện RemoteFunction linh hoạt) ==========
local function findCommRemote()
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage
    if not remotesFolder then return nil end
    local candidates = {"CommF_","CommF","Comm","CommFruit","CommStore","RemoteFunction"}
    for _, name in ipairs(candidates) do
        local obj = remotesFolder:FindFirstChild(name)
        if obj and (obj.ClassName == "RemoteFunction" or obj.ClassName == "RemoteEvent") then
            return obj
        end
    end
    for _, child in pairs(remotesFolder:GetChildren()) do
        if child.ClassName == "RemoteFunction" then return child end
    end
    return nil
end
local _cachedCommRemote = findCommRemote()

local function invokeWithRetries(remote, methodName, ...)
    if not remote then return false, "no_remote" end
    local args = {...}
    local attempt = 0
    local lastErr = nil
    while attempt < INVOKE_RETRIES do
        attempt = attempt + 1
        local ok, res = pcall(function() return remote:InvokeServer(methodName, table.unpack(args)) end)
        if ok then return true, res end
        lastErr = res
        DebugLog(("Invoke attempt %d failed: %s"):format(attempt, tostring(res)))
        task.wait(INVOKE_BACKOFF * attempt)
    end
    return false, lastErr
end

local function safeInvokeStore(fruitName, toolInstance)
    local remote = _cachedCommRemote
    if not remote then
        remote = findCommRemote()
        _cachedCommRemote = remote
    end
    if not remote then return false, "no_remote" end
    local ok, res = invokeWithRetries(remote, "StoreFruit", toolInstance, fruitName)
    if not ok then ok, res = invokeWithRetries(remote, "StoreFruit", fruitName, toolInstance) end
    if not ok then return false, res end
    if type(res) == "string" and res:lower():find("full") then return "Full" end
    return true, res
end

-- ========== STORE FRUIT (an toàn) ==========
local storeLock = false
local function AttemptStoreFruit(fromMainLoop)
    if storeLock then return false end
    storeLock = true
    task.spawn(function()
        pcall(function()
            if not LocalPlayer then return end
            local function tryStoreTool(tool)
                if not tool then return end
                if not string.find(tool.Name or "", "Fruit") then return end
                local original = (tool.GetAttribute and tool:GetAttribute("OriginalName")) or tool.Name
                local ok, res = safeInvokeStore(original, tool)
                if ok == true or ok == "true" then
                    stats.stored = stats.stored + 1
                    pcall(function() StoredLabel.Text = "🍈 Trái đã lưu: "..tostring(stats.stored) end)
                    SaveStats()
                elseif res == "Full" then
                    -- túi đầy
                else
                    DebugLog("AttemptStoreFruit lỗi: "..tostring(res))
                end
            end
            local held = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
            tryStoreTool(held)
            if LocalPlayer.Backpack then
                for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
                    tryStoreTool(tool)
                    task.wait(0.12)
                end
            end
        end)
        task.wait(STORE_INTERVAL)
        storeLock = false
    end)
    return true
end

-- ========== MOVE (Flight Mode) ==========
local function SafeMoveToPosition(pos)
    local hrp = getHRP()
    if not hrp then return false end
    local humanoid = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    local targetPos = pos + Vector3.new(0,2,0)
    local dist = (hrp.Position - targetPos).Magnitude
    local t = math.clamp(dist / FLIGHT_SPEED, 0.4, MAX_TRAVEL_TIME)
    local start = hrp.CFrame
    local finish = CFrame.new(targetPos)
    local startTime = tick()
    local success = false
    -- thử Tween trước
    local okTween = pcall(function()
        local tw = TweenService:Create(hrp, TweenInfo.new(t, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {CFrame = finish})
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
        tw:Play()
        tw.Completed:Wait()
        humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
        success = true
    end)
    if okTween and success then return true end
    -- fallback: interpolation heartbeat
    local conn
    local aborted = false
    conn = RunService.Heartbeat:Connect(function(dt)
        if not hrp or not hrp.Parent then aborted = true if conn then conn:Disconnect() end return end
        local elapsed = tick() - startTime
        local alpha = math.clamp(elapsed / t, 0, 1)
        local newCFrame = start:Lerp(finish, alpha)
        pcall(function() hrp.CFrame = newCFrame end)
        if alpha >= 1 then if conn then conn:Disconnect() end end
    end)
    local waitStart = tick()
    while tick() - waitStart <= t + 0.5 do
        if aborted then return false end
        if (hrp.CFrame.Position - targetPos).Magnitude <= 2 then break end
        task.wait(0.02)
    end
    pcall(function() if hrp and hrp.Parent then hrp.CFrame = finish end end)
    return not aborted
end

-- ========== SCAN FRUITS ==========
local function findHandle(obj)
    if not obj then return nil end
    return obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart") or obj.PrimaryPart
end

local function scanWorkspaceForFruits()
    local fruits = {}
    local hrp = getHRP()
    if not hrp then return fruits end
    for _, obj in pairs(Workspace:GetChildren()) do
        if obj and obj:IsA("Model") and obj.Name and tostring(obj.Name):lower():find("fruit") then
            local handle = findHandle(obj)
            if handle and handle.Position then
                local ok, dist = pcall(function() return (hrp.Position - handle.Position).Magnitude end)
                if ok and dist and dist <= FRUIT_PROXIMITY then
                    table.insert(fruits, {model = obj, pos = handle.Position, dist = dist, name = obj.Name})
                end
            end
        end
    end
    table.sort(fruits, function(a,b) return a.dist < b.dist end)
    return fruits
end

-- ========== UPDATE ESP UI & WORLD ==========
local function updateESP_UI_and_world(fruits)
    for i=1, ESP_MAX_SHOW do
        local row = EspRows[i]
        if fruits[i] then
            row.Text = string.format("• %s — %dm", fruits[i].name, math.floor(fruits[i].dist))
            row.TextTransparency = 0
            pcall(function() ensureSelectionBoxFor(fruits[i].model) end)
            pcall(function()
                local m = fruits[i].model
                if m and m.Parent then
                    local bb = m:FindFirstChild("TuanxAuraBillboard")
                    local handle = m:FindFirstChild("Handle") or m:FindFirstChildWhichIsA("BasePart")
                    if not bb and handle then
                        local bbg = Instance.new("BillboardGui"); bbg.Name = "TuanxAuraBillboard"; bbg.Size = UDim2.new(0,120,0,28)
                        bbg.StudsOffset = Vector3.new(0,2.4,0); bbg.Adornee = handle; bbg.AlwaysOnTop = true
                        local lbl = Instance.new("TextLabel", bbg); lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1
                        lbl.Font = Enum.Font.SourceSansBold; lbl.TextSize = 14; lbl.TextColor3 = Color3.fromRGB(220,240,255)
                        lbl.TextStrokeTransparency = 0.6; lbl.Text = string.format("%s — %dm", fruits[i].name, math.floor(fruits[i].dist))
                        bbg.Parent = m
                    else
                        if bb and bb:FindFirstChildWhichIsA("TextLabel") then
                            bb:FindFirstChildWhichIsA("TextLabel").Text = string.format("%s — %dm", fruits[i].name, math.floor(fruits[i].dist))
                        end
                    end
                end
            end)
        else
            row.Text = ""
        end
    end
    local present = {}
    for _, f in pairs(fruits) do present[f.model] = true end
    for m, box in pairs(selectionBoxes) do
        if not present[m] then removeSelectionBoxFor(m) end
    end
end

-- ========== SERVER HOP ==========
local function ExecuteServerHop()
    stats.hops = stats.hops + 1
    pcall(function() HopLabel.Text = "🌍 Số lần hop: "..tostring(stats.hops) end)
    pcall(function() StatusLabel.Text = "⚙️ Trạng thái: Chuyển server..." end)
    local PlaceId = game.PlaceId
    local LocalJobId = game.JobId
    local Cursor = ""
    local Blacklisted = {}
    if type(isfile) == "function" and isfile("NotSameServers.json") then
        pcall(function() Blacklisted = HttpService:JSONDecode(readfile("NotSameServers.json")) end)
    end
    if type(Blacklisted) ~= "table" then Blacklisted = {} end
    local CurrentServerID = tostring(LocalJobId)
    if not table.find(Blacklisted, CurrentServerID) then table.insert(Blacklisted, CurrentServerID) end
    local successHop = false
    for page = 1,5 do
        local url = "https://games.roblox.com/v1/games/"..tostring(PlaceId).."/servers/Public?sortOrder=Asc&limit=100"
        if Cursor ~= "" then url = url .. "&cursor=" .. tostring(Cursor) end
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if not ok or not res then DebugLog("HttpGet failed for server list"); break end
        local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
        if not ok2 or not data or not data.data then break end
        Cursor = data.nextPageCursor or ""
        for _, sv in pairs(data.data) do
            if tonumber(sv.playing) and tonumber(sv.maxPlayers) and tonumber(sv.playing) < tonumber(sv.maxPlayers) then
                local sid = tostring(sv.id)
                if sid ~= CurrentServerID and not table.find(Blacklisted, sid) then
                    table.insert(Blacklisted, sid)
                    pcall(function() if type(writefile)=="function" then writefile("NotSameServers.json", HttpService:JSONEncode(Blacklisted)) end end)
                    pcall(function() TeleportService:TeleportToPlaceInstance(PlaceId, sid, LocalPlayer) end)
                    successHop = true
                    break
                end
            end
        end
        if successHop then break end
        task.wait(0.2)
    end
    if not successHop then pcall(function() TeleportService:Teleport(PlaceId, LocalPlayer) end) end
    SaveStats()
end

-- ========== MAIN LOOP ==========
task.spawn(function()
    local lastScan = 0
    local noFruitTimer = 0
    while true do
        local okMain, err = pcall(function()
            local now = tick()
            if now - lastScan >= FRUIT_SCAN_INTERVAL then
                lastScan = now
                local fruits = scanWorkspaceForFruits()
                if fruits and #fruits > 0 then
                    noFruitTimer = 0
                    stats.lastFruitFound = tick()
                    updateESP_UI_and_world(fruits)
                    local target = fruits[1]
                    if target and target.pos then
                        currentTarget = target.model
                        pcall(function() StatusLabel.Text = "⚙️ Trạng thái: Đang bay tới "..tostring(target.name) end)
                        local moved = SafeMoveToPosition(target.pos)
                        if moved then
                            pcall(function() AttemptStoreFruit(true) end)
                            stats.picked = stats.picked + 1
                            pcall(function() PickedLabel.Text = "🥭 Trái đã nhặt: "..tostring(stats.picked) end)
                            SaveStats()
                        else
                            DebugLog("Move failed to target "..tostring(target.name))
                        end
                    end
                else
                    noFruitTimer = noFruitTimer + FRUIT_SCAN_INTERVAL
                    pcall(function() StatusLabel.Text = ("⚙️ Trạng thái: Không tìm thấy trái (%.1fs)"):format(noFruitTimer) end)
                    cleanupSelectionBoxes()
                    if noFruitTimer >= HOP_TIMEOUT then
                        noFruitTimer = 0
                        task.spawn(ExecuteServerHop)
                    end
                end
            end
            -- cập nhật thời gian trong server
            local elapsed = math.floor(tick() - stats.startTime)
            local h = math.floor(elapsed/3600); local m = math.floor((elapsed%3600)/60); local s = elapsed%60
            pcall(function() TimeLabel.Text = string.format("⏱ Thời gian: %02d:%02d:%02d", h,m,s) end)
        end)
        if not okMain then
            DebugLog("Lỗi vòng chính: "..tostring(err))
            task.wait(1)
        end
        task.wait(0.12)
    end
end)

-- ========== PERIODIC STORE ==========
task.spawn(function()
    while true do
        pcall(function() AttemptStoreFruit(false) end)
        task.wait(STORE_INTERVAL)
    end
end)

-- ========== SAFE AUTO JOIN TEAM (TÙY CHỌN) ==========
-- Nếu bạn muốn auto join team trong project của bạn (Roblox Studio server của bạn),
-- bạn có thể đặt getgenv().Team = "Marines" trước khi chạy script.
-- Đoạn code dưới đây sẽ tìm RemoteFunction an toàn (SetTeamRF ...) và InvokeServer nếu có.
local function findSafeSetTeamRemote()
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if remotesFolder then
        local rf = remotesFolder:FindFirstChild("SetTeamRF")
        if rf and rf.ClassName == "RemoteFunction" then return rf end
        for _,c in ipairs({"SetTeam","SetTeamFunction","SetTeamRemote"}) do
            local f = remotesFolder:FindFirstChild(c)
            if f and f.ClassName == "RemoteFunction" then return f end
        end
        for _,child in pairs(remotesFolder:GetChildren()) do
            if child.ClassName == "RemoteFunction" then return child end
        end
    end
    return nil
end

local function SafeInvokeSetTeam(remote, teamName)
    if not remote or type(teamName) ~= "string" then return false, "no_remote_or_invalid" end
    for i=1,3 do
        local ok, res = pcall(function() return remote:InvokeServer(teamName) end)
        if ok then return true, res end
        task.wait(0.25 * i)
    end
    return false, "invoke_failed"
end

task.spawn(function()
    task.wait(0.8)
    local player = LocalPlayer
    if not player then return end
    local desiredTeam = (type(getgenv) == "function" and getgenv().Team) or nil
    if not desiredTeam or (desiredTeam ~= "Marines" and desiredTeam ~= "Pirates") then return end
    if player.Team then
        pcall(function() StatusLabel.Text = "⚙️ Trạng thái: Đã ở team: "..tostring(player.Team.Name) end)
        return
    end
    local remote = findSafeSetTeamRemote()
    if not remote then
        pcall(function() StatusLabel.Text = "⚠️ Không tìm thấy RemoteFunction an toàn để set team." end)
        return
    end
    pcall(function() StatusLabel.Text = "⚙️ Đang cố join team: "..tostring(desiredTeam) end)
    local startT = tick()
    local timeout = 18
    while tick() - startT <= timeout do
        if player.Team then pcall(function() StatusLabel.Text = "✅ Đã vào team: "..tostring(player.Team.Name) end) return end
        local ok, res = SafeInvokeSetTeam(remote, desiredTeam)
        if ok then
            local waited = 0
            repeat task.wait(0.25); waited = waited + 0.25 until waited >= 1.2 or player.Team
            if player.Team then pcall(function() StatusLabel.Text = "✅ Đã vào team: "..tostring(player.Team.Name) end) return end
        end
        task.wait(1)
    end
    pcall(function() if not player.Team then StatusLabel.Text = "⚠️ Không thể join team tự động (remote không hợp lệ)." end end)
end)

-- ========== HANDLE RE-PARENT GUI KHI CHARACTER RESET ==========
if LocalPlayer then
    LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(0.8)
        pcall(function()
            ScreenGui.Parent = LocalPlayer:FindFirstChild("PlayerGui") or StarterGui
            NameLabel.Text = "👤 Người chơi: "..(LocalPlayer.Name or "Unknown")
        end)
    end)
end

-- ========== HOÀN THÀNH ==========
pcall(function() StatusLabel.Text = "⚙️ Trạng thái: Hoạt động (Stable Mode)" end)
DebugLog("TuanxAura v19 Improved (Vietnamese) loaded.")
