-- TuanxAura_Hub_v20_Ultimate_Stable_Flight.lua
-- Phiên bản: v20 Ultimate Stable Flight Edition
-- Mô tả: Cải tiến bay mượt, Notify ngay lập tức (giữa trên), emoji cho status/notify,
--        HUD modern, ESP UI, JSON save, toggle UI, robust retries.
-- Lưu ý: Không chứa mã exploit (không dùng getgc/getfenv/getconstants). Chạy bằng executor hỗ trợ API.

-- ========== CẤU HÌNH ==========
local IMAGE_ID = "rbxassetid://13483203475" -- Thay đổi nếu muốn ảnh nền khác
local UI_SCALE = 1
local ESP_MAX_SHOW = 5
local FRUIT_PROXIMITY = 500
local FRUIT_SCAN_INTERVAL = 0.7
local HOP_TIMEOUT = 60
local STORE_INTERVAL = 2.0
local FLIGHT_SPEED = 150
local MAX_TRAVEL_TIME = 5.0
local DEBUG_MODE = false
local STATS_FILE = "TuanxAura_Stats.json"

-- ========== BẢO VỆ DOUBLE-RUN ==========
if _G.TuanxAura_v20_Ran then return end
_G.TuanxAura_v20_Ran = true

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
local UserInputService = gs("UserInputService") or game:GetService("UserInputService")

-- ========== TIỆN ÍCH ==========
local function safeWait(t) task.wait(t or 0.03) end
local function SetProps(o, props) pcall(function() for k,v in pairs(props) do o[k]=v end end) return o end
local function getHRP() return LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") end
local function DebugLog(msg) if DEBUG_MODE then pcall(function() print("[TuanxAura DEBUG] "..tostring(msg)) end) end

-- ========== THỐNG KÊ ==========
local stats = { picked = 0, stored = 0, hops = 0, startTime = tick(), lastFruitFound = 0 }

-- ========== UI (HUD + Notify) ==========
local PlayerGui = (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")) or StarterGui
if not PlayerGui then PlayerGui = StarterGui end

local ScreenGui = SetProps(Instance.new("ScreenGui"), {Name="TuanxAura_Hub_v20", Parent=PlayerGui, ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local Bg = SetProps(Instance.new("ImageLabel"), {Parent=ScreenGui, Name="Background", Size=UDim2.fromScale(1,1), Position=UDim2.new(0,0,0,0), BackgroundTransparency=1, Image=IMAGE_ID, ScaleType=Enum.ScaleType.Crop, ZIndex=1})
local Overlay = SetProps(Instance.new("Frame"), {Parent=ScreenGui, Name="Overlay", Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.fromRGB(5,5,8), BackgroundTransparency=0.55, ZIndex=2})

-- Container HUD
local HudContainer = SetProps(Instance.new("Frame"), {Parent=ScreenGui, Name="HudContainer", Size=UDim2.new(0.55*UI_SCALE,0,0.42*UI_SCALE,0), Position=UDim2.new(0.5,0,0.08,0), AnchorPoint=Vector2.new(0.5,0), BackgroundTransparency=1, ZIndex=3})

-- Title center top
local Title = SetProps(Instance.new("TextLabel"), {Parent=HudContainer, Name="Title", Size=UDim2.new(1,0,0,38), Position=UDim2.new(0,0,0,0), BackgroundTransparency=1, Font=Enum.Font.Code, TextSize=22*UI_SCALE, Text="💎 TUANXAURA HUB 💙", TextColor3=Color3.fromRGB(220,240,255), TextStrokeColor3=Color3.fromRGB(30,140,255), TextStrokeTransparency=0.4, ZIndex=4})
local function makeGlow(lbl)
    local stroke = Instance.new("UIStroke"); stroke.Parent=lbl; stroke.Color=Color3.fromRGB(30,140,255); stroke.Thickness=2; stroke.Transparency=0.3; stroke.LineJoinMode=Enum.LineJoinMode.Round
end
makeGlow(Title)

-- Left and right columns
local LeftCol = SetProps(Instance.new("Frame"), {Parent=HudContainer, Name="LeftCol", Size=UDim2.new(0.48,0,0.8,0), Position=UDim2.new(0,0,0,48), BackgroundTransparency=0.12, BackgroundColor3=Color3.fromRGB(10,10,12), ZIndex=4})
Instance.new("UICorner", LeftCol).CornerRadius=UDim.new(0,8)
SetProps(Instance.new("UIStroke"), {Parent=LeftCol, Color=Color3.fromRGB(30,140,255), Thickness=1})
local RightCol = SetProps(Instance.new("Frame"), {Parent=HudContainer, Name="RightCol", Size=UDim2.new(0.48,0,0.8,0), Position=UDim2.new(0.52,0,0,48), BackgroundTransparency=0.12, BackgroundColor3=Color3.fromRGB(10,10,12), ZIndex=4})
Instance.new("UICorner", RightCol).CornerRadius=UDim.new(0,8)
SetProps(Instance.new("UIStroke"), {Parent=RightCol, Color=Color3.fromRGB(30,140,255), Thickness=1})

-- Status (left)
local StatusLabel = SetProps(Instance.new("TextLabel"), {Parent=LeftCol, Name="Status", Size=UDim2.new(1,-12,0,28), Position=UDim2.new(0,6,0,6), BackgroundTransparency=1, Font=Enum.Font.SourceSansBold, TextSize=16*UI_SCALE, Text="🔍 Trạng thái: Khởi động...", TextColor3=Color3.fromRGB(230,240,255), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5})
makeGlow(StatusLabel)

-- Stored & Time (left)
local StoredLabel = SetProps(Instance.new("TextLabel"), {Parent=LeftCol, Name="Stored", Size=UDim2.new(1,-12,0,22), Position=UDim2.new(0,6,0,40), BackgroundTransparency=1, Font=Enum.Font.SourceSans, TextSize=15*UI_SCALE, Text="🍈 Trái đã lưu: 0", TextColor3=Color3.fromRGB(220,235,255), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5})
makeGlow(StoredLabel)
local TimeLabel = SetProps(Instance.new("TextLabel"), {Parent=LeftCol, Name="Time", Size=UDim2.new(1,-12,0,22), Position=UDim2.new(0,6,0,64), BackgroundTransparency=1, Font=Enum.Font.SourceSans, TextSize=15*UI_SCALE, Text="⏱ Thời gian: 00:00:00", TextColor3=Color3.fromRGB(220,235,255), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5})
makeGlow(TimeLabel)

-- ESP header & list (left)
local EspHeader = SetProps(Instance.new("TextLabel"), {Parent=LeftCol, Name="EspHeader", Size=UDim2.new(1,-12,0,20), Position=UDim2.new(0,6,0,94), BackgroundTransparency=1, Font=Enum.Font.SourceSansBold, TextSize=14*UI_SCALE, Text="🔍 Trái gần nhất:", TextColor3=Color3.fromRGB(200,230,255), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5})
makeGlow(EspHeader)
local EspList = SetProps(Instance.new("Frame"), {Parent=LeftCol, Name="EspList", Size=UDim2.new(1,-12,0,(ESP_MAX_SHOW*22)+8), Position=UDim2.new(0,6,0,118), BackgroundTransparency=1, ZIndex=5})
local function CreateEspRow(parent, idx) local row=SetProps(Instance.new("TextLabel"),{Parent=parent,Name="EspRow"..tostring(idx),Size=UDim2.new(1,0,0,20),Position=UDim2.new(0,0,0,(idx-1)*22),BackgroundTransparency=1,Font=Enum.Font.SourceSans,TextSize=14*UI_SCALE,Text="",TextColor3=Color3.fromRGB(240,240,245),TextXAlignment=Enum.TextXAlignment.Left,ZIndex=5}); return row end
local EspRows = {} for i=1,ESP_MAX_SHOW do EspRows[i]=CreateEspRow(EspList,i) end

-- Right column labels
local PickedLabel = SetProps(Instance.new("TextLabel"), {Parent=RightCol, Name="Picked", Size=UDim2.new(1,-12,0,28), Position=UDim2.new(0,6,0,6), BackgroundTransparency=1, Font=Enum.Font.SourceSansBold, TextSize=16*UI_SCALE, Text="🥭 Trái đã nhặt: 0", TextColor3=Color3.fromRGB(230,240,255), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5})
makeGlow(PickedLabel)
local HopLabel = SetProps(Instance.new("TextLabel"), {Parent=RightCol, Name="Hop", Size=UDim2.new(1,-12,0,22), Position=UDim2.new(0,6,0,40), BackgroundTransparency=1, Font=Enum.Font.SourceSans, TextSize=15*UI_SCALE, Text="🌍 Số lần hop: 0", TextColor3=Color3.fromRGB(220,235,255), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5})
makeGlow(HopLabel)
local NameLabel = SetProps(Instance.new("TextLabel"), {Parent=RightCol, Name="Name", Size=UDim2.new(1,-12,0,22), Position=UDim2.new(0,6,0,64), BackgroundTransparency=1, Font=Enum.Font.SourceSans, TextSize=15*UI_SCALE, Text="👤 Người chơi: "..(LocalPlayer and LocalPlayer.Name or "Unknown"), TextColor3=Color3.fromRGB(220,235,255), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5})
makeGlow(NameLabel)

-- Toggle button (top-right)
local ToggleBtn = SetProps(Instance.new("TextButton"), {Parent=ScreenGui, Name="ToggleHUD", Size=UDim2.new(0,36,0,24), Position=UDim2.new(1,-42,0,8), AnchorPoint=Vector2.new(0,0), BackgroundColor3=Color3.fromRGB(18,18,22), BackgroundTransparency=0.12, Text="UI", Font=Enum.Font.SourceSansBold, TextSize=14, TextColor3=Color3.fromRGB(220,240,255), ZIndex=6})
Instance.new("UICorner", ToggleBtn).CornerRadius=UDim.new(0,6)
SetProps(Instance.new("UIStroke"), {Parent=ToggleBtn, Color=Color3.fromRGB(30,140,255), Thickness=1})
local UI_VISIBLE = true
local function SetUIVisible(v) UI_VISIBLE=v; pcall(function() HudContainer.Visible=v; Overlay.Visible=v; Bg.Visible=v end) end
ToggleBtn.MouseButton1Click:Connect(function() SetUIVisible(not UI_VISIBLE) end)
pcall(function() UserInputService.InputBegan:Connect(function(inp,gp) if gp then return end if inp.KeyCode==Enum.KeyCode.RightControl then SetUIVisible(not UI_VISIBLE) end end) end)

-- ========== Notify system (popup hình chữ nhật, giữa trên, xuất hiện ngay) ==========
local NotifyContainer = SetProps(Instance.new("Frame"), {Parent=ScreenGui, Name="NotifyContainer", Size=UDim2.new(0.4,0,0,0), Position=UDim2.new(0.5,0,0.03,0), AnchorPoint=Vector2.new(0.5,0), BackgroundTransparency=1, ZIndex=10})
local activeNotifies = {}
local function Notify(text, kindColor)
    pcall(function()
        local frame = Instance.new("Frame")
        frame.Name = "NotifyFrame"
        frame.Size = UDim2.new(0,0,0,36)
        frame.Position = UDim2.new(0.5,0,0,0)
        frame.AnchorPoint = Vector2.new(0.5,0)
        frame.BackgroundColor3 = kindColor or Color3.fromRGB(12,30,45)
        frame.BorderSizePixel = 0
        frame.Parent = NotifyContainer
        local corner = Instance.new("UICorner"); corner.Parent = frame; corner.CornerRadius = UDim.new(0,8)
        local stroke = Instance.new("UIStroke"); stroke.Parent = frame; stroke.Color = Color3.fromRGB(30,140,255); stroke.Thickness = 1
        local lbl = Instance.new("TextLabel"); lbl.Parent = frame; lbl.Size = UDim2.new(1,-16,1,0); lbl.Position = UDim2.new(0,8,0,0); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.SourceSansBold; lbl.TextSize = 16; lbl.TextColor3 = Color3.fromRGB(240,245,250); lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Text = text
        table.insert(activeNotifies, frame)
        -- tween in quickly
        local targetSize = UDim2.new(0.4,0,0,36)
        local twIn = TweenService:Create(frame, TweenInfo.new(0.10, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Size = targetSize})
        twIn:Play()
        -- auto hide
        task.spawn(function()
            task.wait(3.2)
            local twOut = TweenService:Create(frame, TweenInfo.new(0.10, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {Size = UDim2.new(0,0,0,36)})
            twOut:Play()
            twOut.Completed:Wait()
            pcall(function() frame:Destroy() end)
            -- cleanup list
            for i,f in ipairs(activeNotifies) do if f==frame then table.remove(activeNotifies,i); break end end
            -- reposition remaining (stacking)
            for i,f in ipairs(activeNotifies) do pcall(function() f.Position = UDim2.new(0.5,0,0,(i-1)*40) end) end
        end)
    end)
end
local function NotifyInfo(t) Notify("ℹ️ "..t, Color3.fromRGB(30,110,200)) end
local function NotifySuccess(t) Notify("✅ "..t, Color3.fromRGB(30,180,140)) end
local function NotifyWarn(t) Notify("⚠️ "..t, Color3.fromRGB(230,120,80)) end

-- ========== ESP WORLD (SelectionBox + Billboard) ==========
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
local function removeSelectionBoxFor(model) if selectionBoxes[model] then pcall(function() selectionBoxes[model]:Destroy() end); selectionBoxes[model]=nil end end
local function cleanupSelectionBoxes() for m,box in pairs(selectionBoxes) do if not m or not m.Parent or (box and box.Adornee==nil) then pcall(function() if box then box:Destroy() end end); selectionBoxes[m]=nil end end end

-- ========== JSON SAVE/LOAD ==========
local function LoadStats()
    if type(isfile)~="function" or type(readfile)~="function" or not HttpService then return {Picked=0,Stored=0,HopCount=0} end
    if not isfile(STATS_FILE) then pcall(function() writefile(STATS_FILE, HttpService:JSONEncode({Picked=0,Stored=0,HopCount=0})) end); return {Picked=0,Stored=0,HopCount=0} end
    local ok,data = pcall(function() return HttpService:JSONDecode(readfile(STATS_FILE)) end)
    if ok and data then return {Picked=tonumber(data.Picked or 0), Stored=tonumber(data.Stored or 0), HopCount=tonumber(data.HopCount or 0)} end
    return {Picked=0,Stored=0,HopCount=0}
end
local function SaveStats() if type(writefile)~="function" or not HttpService then DebugLog("No writefile"); return end; local tbl={Picked=stats.picked,Stored=stats.stored,HopCount=stats.hops}; pcall(function() writefile(STATS_FILE, HttpService:JSONEncode(tbl)) end) end
do local old = LoadStats(); stats.picked = old.Picked or 0; stats.stored = old.Stored or 0; stats.hops = old.HopCount or 0; pcall(function() PickedLabel.Text="🥭 Trái đã nhặt: "..stats.picked; StoredLabel.Text="🍈 Trái đã lưu: "..stats.stored; HopLabel.Text="🌍 Số lần hop: "..stats.hops end) end

-- ========== Remote utilities (safe) ==========
local function findCommRemote()
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage
    if not remotesFolder then return nil end
    local cands = {"CommF_","CommF","Comm","CommFruit","CommStore"}
    for _,n in ipairs(cands) do local o = remotesFolder:FindFirstChild(n); if o and (o.ClassName=="RemoteFunction" or o.ClassName=="RemoteEvent") then return o end end
    for _,child in pairs(remotesFolder:GetChildren()) do if child.ClassName=="RemoteFunction" then return child end end
    return nil
end
local _cachedCommRemote = findCommRemote()
local function invokeWithRetries(remote, methodName, ...) if not remote then return false,"no_remote" end; local args={...}; local attempt=0; local lastErr=nil; while attempt<3 do attempt=attempt+1; local ok,res = pcall(function() return remote:InvokeServer(methodName, table.unpack(args)) end); if ok then return true,res end; lastErr=res; DebugLog(("Invoke failed %d: %s"):format(attempt,tostring(res))); task.wait(0.18*attempt); end; return false,lastErr end
local function safeInvokeStore(fruitName, toolInstance) local remote=_cachedCommRemote; if not remote then remote=findCommRemote(); _cachedCommRemote=remote end; if not remote then return false,"no_remote" end; local ok,res = invokeWithRetries(remote,"StoreFruit",toolInstance,fruitName); if not ok then ok,res = invokeWithRetries(remote,"StoreFruit",fruitName,toolInstance) end; if not ok then return false,res end; if type(res)=="string" and res:lower():find("full") then return "Full" end; return true,res end

-- ========== STORE FRUIT ==========
local storeLock=false
local function AttemptStoreFruit(fromMain)
    if storeLock then return false end
    storeLock=true
    task.spawn(function()
        pcall(function()
            if not LocalPlayer then return end
            local function tryStore(t)
                if not t or not string.find(t.Name or "","Fruit") then return end
                local original = (t.GetAttribute and t:GetAttribute("OriginalName")) or t.Name
                local ok,res = safeInvokeStore(original,t)
                if ok==true then
                    stats.stored=stats.stored+1; pcall(function() StoredLabel.Text="🍈 Trái đã lưu: "..stats.stored end); SaveStats(); NotifySuccess("Đã lưu: "..tostring(original))
                elseif res=="Full" then NotifyWarn("Túi đầy, không lưu thêm") end
            end
            local held = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
            tryStore(held)
            if LocalPlayer.Backpack then for _,tool in pairs(LocalPlayer.Backpack:GetChildren()) do tryStore(tool); task.wait(0.12) end end
        end)
        task.wait(STORE_INTERVAL)
        storeLock=false
    end)
    return true
end

-- ========== SMOOTH, STABLE FLIGHT MOVEMENT ==========
local function SafeMoveToPositionStable(targetPos)
    local hrp = getHRP()
    if not hrp then return false end
    local humanoid = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local goal = targetPos + Vector3.new(0,2,0)
    local startPos = hrp.Position
    local distance = (startPos - goal).Magnitude
    local totalTime = math.clamp(distance / FLIGHT_SPEED, 0.45, MAX_TRAVEL_TIME)
    local startTime = tick()

    -- gentle short tween attempt to reduce jitter
    pcall(function()
        local tw = TweenService:Create(hrp, TweenInfo.new(math.min(totalTime,1.0), Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {CFrame = CFrame.new(goal)})
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
        tw:Play()
        tw.Completed:Wait()
    end)

    -- heartbeat interpolation
    local aborted = false
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if not hrp or not hrp.Parent then aborted=true; if conn then conn:Disconnect() end; return end
        local elapsed = tick() - startTime
        local alpha = math.clamp(elapsed / totalTime, 0, 1)
        local ease = 1 - (1 - alpha)*(1 - alpha)
        local newPos = startPos:Lerp(goal, ease)
        local maxStep = math.max((distance / 20) * dt * 60, 2)
        local stepVec = newPos - hrp.Position
        if stepVec.Magnitude > maxStep then stepVec = stepVec.Unit * maxStep; newPos = hrp.Position + stepVec end
        pcall(function() hrp.CFrame = CFrame.new(newPos) end)
        if alpha >= 1 then if conn then conn:Disconnect() end end
    end)

    local waitStart = tick()
    local timeout = totalTime + 0.6
    while tick() - waitStart <= timeout do
        if aborted then return false end
        if (hrp.Position - goal).Magnitude <= 1.9 then break end
        task.wait(0.02)
    end
    pcall(function() if hrp and hrp.Parent then hrp.CFrame = CFrame.new(goal) end end)
    return true
end

-- ========== SCAN FRUITS (mở rộng) ==========
local function findHandle(obj) if not obj then return nil end; return obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart") or obj.PrimaryPart end
local function scanWorkspaceForFruits()
    local fruits={}
    local hrp = getHRP()
    if not hrp then return fruits end
    for _,obj in pairs(Workspace:GetDescendants()) do
        if obj and obj:IsA("Model") and obj.Name then
            local nm = tostring(obj.Name):lower()
            if nm:find("fruit") or nm:find("fruta") or nm:find("bomb") or nm:find("slice") then
                local handle = findHandle(obj)
                if handle and handle.Position then
                    local ok,dist = pcall(function() return (hrp.Position - handle.Position).Magnitude end)
                    if ok and dist and dist <= FRUIT_PROXIMITY then
                        table.insert(fruits, {model=obj, pos=handle.Position, dist=dist, name=obj.Name})
                    end
                end
            end
        end
    end
    table.sort(fruits, function(a,b) return a.dist < b.dist end)
    return fruits
end

-- ========== UPDATE ESP UI & WORLD ==========
local function updateESP_UI_and_world(fruits)
    for i=1,ESP_MAX_SHOW do
        local row = EspRows[i]
        if fruits[i] then
            row.Text = string.format("• %s — %dm", fruits[i].name, math.floor(fruits[i].dist))
            pcall(function() ensureSelectionBoxFor(fruits[i].model) end)
            pcall(function()
                local m = fruits[i].model
                if m and m.Parent then
                    local bb = m:FindFirstChild("TuanxAuraBillboard")
                    local handle = m:FindFirstChild("Handle") or m:FindFirstChildWhichIsA("BasePart")
                    if not bb and handle then
                        local bbg = Instance.new("BillboardGui"); bbg.Name="TuanxAuraBillboard"; bbg.Size=UDim2.new(0,120,0,28)
                        bbg.StudsOffset=Vector3.new(0,2.4,0); bbg.Adornee=handle; bbg.AlwaysOnTop=true
                        local lbl=Instance.new("TextLabel",bbg); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.SourceSansBold; lbl.TextSize=14; lbl.TextColor3=Color3.fromRGB(220,240,255); lbl.TextStrokeTransparency=0.6; lbl.Text=string.format("%s — %dm", fruits[i].name, math.floor(fruits[i].dist))
                        bbg.Parent = m
                    else
                        if bb and bb:FindFirstChildWhichIsA("TextLabel") then bb:FindFirstChildWhichIsA("TextLabel").Text = string.format("%s — %dm", fruits[i].name, math.floor(fruits[i].dist)) end
                    end
                end
            end)
        else
            row.Text = ""
        end
    end
    local present = {}
    for _,f in pairs(fruits) do present[f.model] = true end
    for m,box in pairs(selectionBoxes) do if not present[m] then removeSelectionBoxFor(m) end end
end

-- ========== SERVER HOP ==========
local function ExecuteServerHop()
    stats.hops = stats.hops + 1; pcall(function() HopLabel.Text="🌍 Số lần hop: "..stats.hops end); SaveStats()
    NotifyInfo("🌍 Chuẩn bị chuyển server...")
    task.wait(1.2)
    local PlaceId = game.PlaceId; local LocalJobId = game.JobId; local Cursor=""; local Blacklisted={}
    if type(isfile)=="function" and isfile("NotSameServers.json") then pcall(function() Blacklisted = HttpService:JSONDecode(readfile("NotSameServers.json")) end) end
    if type(Blacklisted)~="table" then Blacklisted={} end
    local CurrentServerID = tostring(LocalJobId); if not table.find(Blacklisted, CurrentServerID) then table.insert(Blacklisted, CurrentServerID) end
    local successHop=false
    for page=1,5 do
        local url="https://games.roblox.com/v1/games/"..tostring(PlaceId).."/servers/Public?sortOrder=Asc&limit=100"
        if Cursor~="" then url = url.."&cursor="..tostring(Cursor) end
        local ok,res = pcall(function() return game:HttpGet(url) end)
        if not ok or not res then break end
        local ok2,data = pcall(function() return HttpService:JSONDecode(res) end)
        if not ok2 or not data or not data.data then break end
        Cursor = data.nextPageCursor or ""
        for _,sv in pairs(data.data) do
            if tonumber(sv.playing) and tonumber(sv.maxPlayers) and tonumber(sv.playing) < tonumber(sv.maxPlayers) then
                local sid = tostring(sv.id)
                if sid ~= CurrentServerID and not table.find(Blacklisted, sid) then
                    table.insert(Blacklisted, sid)
                    pcall(function() if type(writefile)=="function" then writefile("NotSameServers.json", HttpService:JSONEncode(Blacklisted)) end end)
                    pcall(function() TeleportService:TeleportToPlaceInstance(PlaceId, sid, LocalPlayer) end)
                    successHop=true; break
                end
            end
        end
        if successHop then break end
        task.wait(0.25)
    end
    if not successHop then pcall(function() TeleportService:Teleport(PlaceId, LocalPlayer) end) end
end

-- ========== MAIN LOOP ==========
task.spawn(function()
    local lastScan=0; local noFruitTimer=0
    while true do
        local ok,err = pcall(function()
            local now = tick()
            if now - lastScan >= FRUIT_SCAN_INTERVAL then
                lastScan = now
                local fruits = scanWorkspaceForFruits()
                if fruits and #fruits > 0 then
                    noFruitTimer = 0; stats.lastFruitFound = tick(); updateESP_UI_and_world(fruits)
                    local target = fruits[1]
                    if target and target.pos then
                        pcall(function() StatusLabel.Text = "✈️ Đang bay tới: "..tostring(target.name) end)
                        local moved = SafeMoveToPositionStable(target.pos)
                        if moved then
                            pcall(function() AttemptStoreFruit(true) end)
                            stats.picked = stats.picked + 1
                            pcall(function() PickedLabel.Text = "🥭 Trái đã nhặt: "..tostring(stats.picked) end)
                            SaveStats()
                            NotifySuccess("Đã nhặt: "..tostring(target.name).." ("..math.floor(target.dist).."m)")
                        else
                            DebugLog("Move failed for "..tostring(target.name))
                        end
                    end
                else
                    noFruitTimer = noFruitTimer + FRUIT_SCAN_INTERVAL
                    pcall(function() StatusLabel.Text = ("🔍 Không tìm thấy trái (%.1fs)"):format(noFruitTimer) end)
                    cleanupSelectionBoxes()
                    if noFruitTimer >= HOP_TIMEOUT then
                        noFruitTimer = 0
                        task.spawn(ExecuteServerHop)
                    end
                end
            end
            local elapsed = math.floor(tick() - stats.startTime)
            local h = math.floor(elapsed/3600); local m = math.floor((elapsed%3600)/60); local s = elapsed%60
            pcall(function() TimeLabel.Text = string.format("⏱ Thời gian: %02d:%02d:%02d", h,m,s) end)
        end)
        if not ok then DebugLog("Main loop error: "..tostring(err)); task.wait(1) end
        task.wait(0.08)
    end
end)

-- ========== PERIODIC STORE ==========
task.spawn(function() while true do pcall(function() AttemptStoreFruit(false) end); task.wait(STORE_INTERVAL) end end)

-- ========== SAFE AUTO JOIN TEAM (optional) ==========
local function findSafeSetTeamRemote() local remotesFolder=ReplicatedStorage:FindFirstChild("Remotes"); if remotesFolder then local rf=remotesFolder:FindFirstChild("SetTeamRF"); if rf and rf.ClassName=="RemoteFunction" then return rf end; for _,c in ipairs({"SetTeam","SetTeamFunction","SetTeamRemote"}) do local f=remotesFolder:FindFirstChild(c); if f and f.ClassName=="RemoteFunction" then return f end end; for _,child in pairs(remotesFolder:GetChildren()) do if child.ClassName=="RemoteFunction" then return child end end end; return nil end
local function SafeInvokeSetTeam(remote, teamName) if not remote or type(teamName)~="string" then return false,"no_remote" end; for i=1,3 do local ok,res=pcall(function() return remote:InvokeServer(teamName) end); if ok then return true,res end; task.wait(0.25*i) end; return false,"invoke_failed" end
task.spawn(function() task.wait(0.8); local player=LocalPlayer; if not player then return end; local desired=(type(getgenv)=="function" and getgenv().Team) or nil; if not desired or (desired~="Marines" and desired~="Pirates") then return end; if player.Team then pcall(function() StatusLabel.Text="⚙️ Đã ở team: "..tostring(player.Team.Name) end); return end; local remote=findSafeSetTeamRemote(); if not remote then pcall(function() StatusLabel.Text="⚠️ Không tìm thấy RemoteFunction để set team" end); return end; pcall(function() StatusLabel.Text="⚙️ Đang cố join team: "..tostring(desired) end); local st=tick(); while tick()-st<=18 do if player.Team then pcall(function() StatusLabel.Text="✅ Đã vào team: "..tostring(player.Team.Name) end); return end; local ok,res=SafeInvokeSetTeam(remote,desired); if ok then local waited=0; repeat task.wait(0.25); waited=waited+0.25 until waited>=1.2 or player.Team; if player.Team then pcall(function() StatusLabel.Text="✅ Đã vào team: "..tostring(player.Team.Name) end); return end end; task.wait(1); end; pcall(function() if not player.Team then StatusLabel.Text="⚠️ Không thể join team tự động" end end) end)

-- ========== RE-PARENT GUI ==========
if LocalPlayer then LocalPlayer.CharacterAdded:Connect(function(char) task.wait(0.8); pcall(function() ScreenGui.Parent = LocalPlayer:FindFirstChild("PlayerGui") or StarterGui; NameLabel.Text="👤 Người chơi: "..(LocalPlayer.Name or "Unknown") end) end) end

-- ========== FINISH ==========
pcall(function() StatusLabel.Text="🔍 Hoạt động: AutoFind/AutoStore/AutoHop (v20 Stable)" end)
NotifyInfo("📥 TuanxAura v20 Loaded")
DebugLog("TuanxAura v20 loaded.")
