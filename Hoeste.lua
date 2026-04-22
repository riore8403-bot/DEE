local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = workspace.CurrentCamera
end)
Camera.CameraType = Enum.CameraType.Custom

local old = CoreGui:FindFirstChild("DEVTOOL")
if old then old:Destroy() end

-- ============================================================
-- FARM
-- ============================================================

local character, hrp = nil, nil
local robRemote = nil
spawn(function()
	robRemote = RS:WaitForChild("GeneralEvents"):WaitForChild("Rob")
end)
local MAX_BAG = 40
local safes = {}
local autoRobEnabled = false

local function getCharacter()
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	repeat wait() until char:FindFirstChild("HumanoidRootPart")
	return char, char:WaitForChild("HumanoidRootPart")
end
local function initializeCharacter() character, hrp = getCharacter() end
initializeCharacter()
LocalPlayer.CharacterAdded:Connect(function() wait(1) initializeCharacter() end)

for _, v in pairs(workspace:GetDescendants()) do
	if v.Name == "Safe" then table.insert(safes, v) end
end

local function getBagMoney()
	local states = LocalPlayer:FindFirstChild("States")
	if states then local bag = states:FindFirstChild("Bag") if bag then return bag.Value end end
	return 0
end

local function safeTeleport(safe)
	local part = safe:FindFirstChild("SafePart")
	if not part then return end
	hrp.CFrame = CFrame.new(part.Position + part.CFrame.LookVector * 5 + Vector3.new(0,3,0), part.Position)
end

local function getBestSafe()
	local best, minDist = nil, math.huge
	for _, safe in pairs(safes) do
		local part = safe:FindFirstChild("SafePart")
		if part then
			local dist = (hrp.Position - part.Position).Magnitude
			if dist < minDist then minDist = dist best = safe end
		end
	end
	return best
end

local function robSafe(safe)
	safeTeleport(safe) wait(0.6)
	local oe = safe:FindFirstChild("OpenSafe")
	if oe then oe:FireServer("Complete") wait(1) end
	robRemote:FireServer("Safe", safe)
	wait(2)
end

spawn(function()
	while true do
		wait(0.4)
		if autoRobEnabled then
			if not character or not hrp then initializeCharacter() end
			if getBagMoney() >= MAX_BAG then repeat wait(1) until getBagMoney() < MAX_BAG end
			local t = getBestSafe()
			if t then robSafe(t) end
		end
	end
end)

-- ============================================================
-- ESP + AIM + HITBOX
-- ============================================================

local espEnabled = false
local aimEnabled = false
local hitboxEnabled = false
local currentTarget = nil
local targetLockTime = 0
local MAX_DISTANCE = 800
local FOV_RADIUS = 200
local LOCK_DURATION = 0.3
local friendlyTargets = {}
local lastHealth = 100

local function isCowboy() return LocalPlayer.Team and LocalPlayer.Team.Name == "Cowboys" end
local function isOutlaw() return LocalPlayer.Team and LocalPlayer.Team.Name == "Outlaws" end
local function isCivilian() return LocalPlayer.Team and LocalPlayer.Team.Name == "Civilians" end
local function isEnemy(p)
	if not p.Team then return false end
	if isCowboy() then return p.Team.Name == "Outlaws" end
	if isOutlaw() then return p.Team.Name ~= "Outlaws" or friendlyTargets[p] end
	if isCivilian() then return p.Team.Name == "Outlaws" end
	return p.Team ~= LocalPlayer.Team
end

local teamColors = {
	Civilians = Color3.fromRGB(0,120,255),
	Cowboys   = Color3.fromRGB(255,220,0),
	Outlaws   = Color3.fromRGB(255,50,50)
}

local function applyHighlight(char, color)
	if not char then return end
	local e = char:FindFirstChild("ESP_HIGHLIGHT")
	if e then e:Destroy() end
	local h = Instance.new("Highlight")
	h.Name="ESP_HIGHLIGHT" h.FillColor=color
	h.OutlineColor=Color3.new(1,1,1) h.FillTransparency=0.3
	h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
	h.Adornee=char h.Parent=char
end

local function applyESP(player)
	local function onChar(char)
		if not espEnabled then return end
		if not player.Team then
			local t=0 repeat task.wait(0.1) t+=1 until player.Team or t>30
		end
		if not player.Team then return end
		local color = teamColors[player.Team.Name]
		if color then applyHighlight(char, color) end
	end
	if player.Character then task.spawn(onChar, player.Character) end
	player.CharacterAdded:Connect(function(c) task.spawn(onChar,c) end)
	player:GetPropertyChangedSignal("Team"):Connect(function()
		if player.Character then task.spawn(onChar, player.Character) end
	end)
end

local function applyHitbox(player)
	local function onChar(char)
		task.wait(0.5)
		if not hitboxEnabled then return end
		local old2 = char:FindFirstChild("HITBOX_ESP")
		if old2 then old2:Destroy() end
		local box = Instance.new("SelectionBox")
		box.Name="HITBOX_ESP" box.Adornee=char
		box.Color3=Color3.fromRGB(0,255,0) box.LineThickness=0.05
		box.SurfaceTransparency=0.8 box.SurfaceColor3=Color3.fromRGB(0,255,0)
		box.Parent=char
	end
	if player.Character then task.spawn(onChar, player.Character) end
	player.CharacterAdded:Connect(function(c) task.spawn(onChar,c) end)
end

local function enableHitboxESP()
	for _,p in ipairs(Players:GetPlayers()) do
		if p~=LocalPlayer then applyHitbox(p) end
	end
	Players.PlayerAdded:Connect(function(p)
		if p~=LocalPlayer then applyHitbox(p) end
	end)
end

local function disableHitboxESP()
	for _,p in ipairs(Players:GetPlayers()) do
		if p and p.Character then
			local box = p.Character:FindFirstChild("HITBOX_ESP")
			if box then box:Destroy() end
		end
	end
end

for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then applyESP(p) end end
Players.PlayerAdded:Connect(function(p) if p~=LocalPlayer then applyESP(p) end end)

local function setupHealthDetection()
	local char = LocalPlayer.Character
	if not char then return end
	local hum = char:WaitForChild("Humanoid")
	lastHealth = hum.Health
	hum.HealthChanged:Connect(function(hp)
		if hp < lastHealth and isOutlaw() then
			local att, shortest = nil, math.huge
			for _,p in ipairs(Players:GetPlayers()) do
				if p~=LocalPlayer and p.Character and p.Team==LocalPlayer.Team then
					local head = p.Character:FindFirstChild("Head")
					if head then
						local d=(head.Position-Camera.CFrame.Position).Magnitude
						if d<shortest then shortest=d att=p end
					end
				end
			end
			if att then
				friendlyTargets[att]=true
				if att.Character then applyHighlight(att.Character, Color3.fromRGB(0,0,0)) end
			end
		end
		lastHealth=hp
	end)
end

if LocalPlayer.Character then setupHealthDetection() end
LocalPlayer.CharacterAdded:Connect(function() wait(1) setupHealthDetection() end)

-- ============================================================
-- GUI (tu diseño exacto)
-- ============================================================

local PALETTE = {
	bg          = Color3.fromRGB(10, 11, 16),
	bgSoft      = Color3.fromRGB(14, 15, 22),
	bgInset     = Color3.fromRGB(18, 20, 28),
	bgRow       = Color3.fromRGB(22, 24, 34),
	bgRowHover  = Color3.fromRGB(30, 33, 46),
	bgPill      = Color3.fromRGB(38, 41, 58),
	stroke      = Color3.fromRGB(60, 68, 110),
	strokeSoft  = Color3.fromRGB(38, 42, 62),
	accent      = Color3.fromRGB(120, 110, 255),
	accent2     = Color3.fromRGB(80, 170, 255),
	accentWarm  = Color3.fromRGB(200, 85, 210),
	good        = Color3.fromRGB(90, 225, 150),
	bad         = Color3.fromRGB(230, 95, 110),
	text        = Color3.fromRGB(235, 237, 250),
	textDim     = Color3.fromRGB(140, 146, 175),
	textSubtle  = Color3.fromRGB(180, 186, 215),
	value       = Color3.fromRGB(130, 200, 255),
}

local function tween(inst, t, props, style, dir)
	TweenService:Create(inst, TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props):Play()
end
local function corner(parent, r)
	local c = Instance.new("UICorner", parent) c.CornerRadius = UDim.new(0, r or 8) return c
end
local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke", parent)
	s.Color = color or PALETTE.strokeSoft s.Thickness = thickness or 1
	s.Transparency = transparency or 0.4 s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return s
end

local Gui = Instance.new("ScreenGui")
Gui.Name="DEVTOOL" Gui.ResetOnSpawn=false Gui.IgnoreGuiInset=true
Gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling Gui.Parent=CoreGui

local Panel = Instance.new("Frame")
Panel.Name="Panel" Panel.Size=UDim2.new(0,260,0,230)
Panel.AnchorPoint=Vector2.new(0.5,0.5) Panel.Position=UDim2.new(0.5,0,0.5,0)
Panel.BackgroundColor3=PALETTE.bg Panel.BorderSizePixel=0
Panel.Active=true Panel.Draggable=true Panel.Visible=true
Panel.ClipsDescendants=true Panel.Parent=Gui
corner(Panel, 12)

local panelStroke = stroke(Panel, Color3.fromRGB(255,255,255), 1, 0.55)
local panelStrokeGrad = Instance.new("UIGradient", panelStroke)
panelStrokeGrad.Rotation=120
panelStrokeGrad.Color=ColorSequence.new{
	ColorSequenceKeypoint.new(0.00, PALETTE.accent2),
	ColorSequenceKeypoint.new(0.50, PALETTE.accent),
	ColorSequenceKeypoint.new(1.00, PALETTE.accentWarm),
}

local panelGrad = Instance.new("UIGradient", Panel)
panelGrad.Rotation=110
panelGrad.Color=ColorSequence.new{
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(20,22,32)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(12,13,20)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(8,9,14)),
}

local TitleBar = Instance.new("Frame", Panel)
TitleBar.Name="TitleBar" TitleBar.Size=UDim2.new(1,0,0,32)
TitleBar.BackgroundColor3=Color3.fromRGB(22,24,40) TitleBar.BorderSizePixel=0
TitleBar.ClipsDescendants=true
corner(TitleBar, 12)

local tbFix = Instance.new("Frame", TitleBar)
tbFix.Size=UDim2.new(1,0,0,10) tbFix.Position=UDim2.new(0,0,1,-10)
tbFix.BackgroundColor3=Color3.fromRGB(22,24,40) tbFix.BorderSizePixel=0

local titleGrad = Instance.new("UIGradient", TitleBar)
titleGrad.Rotation=20
titleGrad.Color=ColorSequence.new{
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(55,60,160)),
	ColorSequenceKeypoint.new(0.50, Color3.fromRGB(30,33,70)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(110,55,180)),
}

task.spawn(function()
	local t=0
	while TitleBar.Parent do
		t=(t+0.5)%360
		titleGrad.Offset=Vector2.new(math.sin(math.rad(t))*0.15, 0)
		task.wait(0.05)
	end
end)

local tbLine = Instance.new("Frame", Panel)
tbLine.Size=UDim2.new(1,-12,0,1) tbLine.Position=UDim2.new(0,6,0,32)
tbLine.BackgroundColor3=PALETTE.strokeSoft tbLine.BackgroundTransparency=0.4 tbLine.BorderSizePixel=0

local Title = Instance.new("TextLabel", TitleBar)
Title.BackgroundTransparency=1 Title.Size=UDim2.new(1,-60,1,0)
Title.Position=UDim2.new(0,12,0,0) Title.Text="✦  DEV TOOL"
Title.TextColor3=PALETTE.text Title.TextSize=13
Title.Font=Enum.Font.GothamBold Title.TextXAlignment=Enum.TextXAlignment.Left

local pulse = Instance.new("Frame", TitleBar)
pulse.AnchorPoint=Vector2.new(1,0.5) pulse.Position=UDim2.new(1,-12,0.5,0)
pulse.Size=UDim2.new(0,8,0,8) pulse.BackgroundColor3=PALETTE.good pulse.BorderSizePixel=0
corner(pulse, 999)
task.spawn(function()
	while pulse.Parent do
		tween(pulse, 0.7, {BackgroundTransparency=0.6}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) task.wait(0.75)
		tween(pulse, 0.7, {BackgroundTransparency=0}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) task.wait(0.75)
	end
end)

local TabFrame = Instance.new("Frame", Panel)
TabFrame.Name="TabFrame" TabFrame.Size=UDim2.new(0,70,1,-40)
TabFrame.Position=UDim2.new(0,4,0,36) TabFrame.BackgroundColor3=PALETTE.bgSoft TabFrame.BorderSizePixel=0
corner(TabFrame, 10) stroke(TabFrame, PALETTE.strokeSoft, 1, 0.55)
local tabLayout = Instance.new("UIListLayout", TabFrame)
tabLayout.Padding=UDim.new(0,4) tabLayout.HorizontalAlignment=Enum.HorizontalAlignment.Center
local tabPad = Instance.new("UIPadding", TabFrame) tabPad.PaddingTop=UDim.new(0,6)

local Content = Instance.new("Frame", Panel)
Content.Name="Content" Content.Size=UDim2.new(1,-82,1,-40)
Content.Position=UDim2.new(0,78,0,36) Content.BackgroundColor3=PALETTE.bgSoft
Content.BackgroundTransparency=0.3 Content.BorderSizePixel=0 Content.ClipsDescendants=true
corner(Content, 10) stroke(Content, PALETTE.strokeSoft, 1, 0.6)

-- FOV
local FOVFrame = Instance.new("Frame", Gui)
FOVFrame.Size=UDim2.new(0,FOV_RADIUS*2,0,FOV_RADIUS*2)
FOVFrame.AnchorPoint=Vector2.new(0.5,0.5) FOVFrame.Position=UDim2.new(0.5,0,0.5,0)
FOVFrame.BackgroundTransparency=1 FOVFrame.Visible=false
local fsc=Instance.new("UIStroke",FOVFrame) fsc.Color=Color3.fromRGB(255,255,255) fsc.Thickness=1 fsc.Transparency=0.3
local fcc=Instance.new("UICorner",FOVFrame) fcc.CornerRadius=UDim.new(1,0)

local pages = {}
local tabBtns = {}
local currentPage

local function makePage()
	local p = Instance.new("Frame")
	p.Size=UDim2.new(1,-10,1,-10) p.Position=UDim2.new(0,5,0,5)
	p.BackgroundTransparency=1 p.Visible=false p.Parent=Content
	local l=Instance.new("UIListLayout",p) l.Padding=UDim.new(0,5) l.SortOrder=Enum.SortOrder.LayoutOrder
	return p
end

local function makeTab(name)
	local b = Instance.new("TextButton")
	b.Size=UDim2.new(1,-4,0,30) b.BackgroundColor3=Color3.fromRGB(45,50,120)
	b.BackgroundTransparency=1 b.BorderSizePixel=0 b.AutoButtonColor=false
	b.Text=name b.TextColor3=PALETTE.textDim b.TextSize=11
	b.Font=Enum.Font.GothamBold b.Parent=TabFrame
	corner(b, 7)
	local indicator = Instance.new("Frame", b)
	indicator.Name="Indicator" indicator.AnchorPoint=Vector2.new(0,0.5)
	indicator.Position=UDim2.new(0,3,0.5,0) indicator.Size=UDim2.new(0,2,0,0)
	indicator.BackgroundColor3=PALETTE.accent indicator.BorderSizePixel=0
	corner(indicator, 999)
	b.MouseEnter:Connect(function()
		if currentPage~=name then tween(b, 0.15, {BackgroundTransparency=0.35, TextColor3=PALETTE.text}) end
	end)
	b.MouseLeave:Connect(function()
		if currentPage~=name then tween(b, 0.2, {BackgroundTransparency=1, TextColor3=PALETTE.textDim}) end
	end)
	return b
end

local function makeToggle(parent, text, initialState, callback)
	local state = initialState == true
	local row = Instance.new("TextButton", parent)
	row.Size=UDim2.new(1,-2,0,28) row.BackgroundColor3=PALETTE.bgRow
	row.BorderSizePixel=0 row.AutoButtonColor=false row.Text=""
	corner(row, 7) stroke(row, PALETTE.strokeSoft, 1, 0.5)

	local stripe = Instance.new("Frame", row)
	stripe.Size=UDim2.new(0,2,1,-10) stripe.Position=UDim2.new(0,5,0,5)
	stripe.BackgroundColor3=state and PALETTE.accent or PALETTE.strokeSoft
	stripe.BorderSizePixel=0 corner(stripe, 999)

	local lbl = Instance.new("TextLabel", row)
	lbl.Size=UDim2.new(1,-56,1,0) lbl.Position=UDim2.new(0,14,0,0)
	lbl.BackgroundTransparency=1 lbl.Text=text
	lbl.TextColor3=state and PALETTE.text or PALETTE.textSubtle
	lbl.TextSize=11 lbl.Font=Enum.Font.GothamMedium
	lbl.TextXAlignment=Enum.TextXAlignment.Left

	local pill = Instance.new("Frame", row)
	pill.Size=UDim2.new(0,30,0,16) pill.AnchorPoint=Vector2.new(1,0.5)
	pill.Position=UDim2.new(1,-8,0.5,0) pill.BorderSizePixel=0
	pill.BackgroundColor3=state and PALETTE.good or PALETTE.bgPill
	corner(pill, 999)

	local dot = Instance.new("Frame", pill)
	dot.Size=UDim2.new(0,12,0,12) dot.AnchorPoint=Vector2.new(0,0.5)
	dot.Position=state and UDim2.new(1,-14,0.5,0) or UDim2.new(0,2,0.5,0)
	dot.BackgroundColor3=Color3.new(1,1,1) dot.BorderSizePixel=0
	corner(dot, 999)

	local hovering = false
	local function applyVisual(animated)
		local t = animated and 0.18 or 0
		TweenService:Create(pill, TweenInfo.new(t, Enum.EasingStyle.Quint), {BackgroundColor3=state and PALETTE.good or PALETTE.bgPill}):Play()
		TweenService:Create(dot, TweenInfo.new(t, Enum.EasingStyle.Quint), {Position=state and UDim2.new(1,-14,0.5,0) or UDim2.new(0,2,0.5,0)}):Play()
		TweenService:Create(stripe, TweenInfo.new(t, Enum.EasingStyle.Quint), {BackgroundColor3=state and PALETTE.accent or PALETTE.strokeSoft}):Play()
		TweenService:Create(lbl, TweenInfo.new(t, Enum.EasingStyle.Quint), {TextColor3=state and PALETTE.text or PALETTE.textSubtle}):Play()
		TweenService:Create(row, TweenInfo.new(t, Enum.EasingStyle.Quint), {BackgroundColor3=hovering and PALETTE.bgRowHover or PALETTE.bgRow}):Play()
	end

	row.MouseEnter:Connect(function() hovering=true tween(row, 0.15, {BackgroundColor3=PALETTE.bgRowHover}) end)
	row.MouseLeave:Connect(function() hovering=false tween(row, 0.2, {BackgroundColor3=PALETTE.bgRow}) end)
	row.MouseButton1Click:Connect(function()
		state = not state
		applyVisual(true)
		if callback then callback(state) end
	end)
	return row
end

local function makeInfo(parent, text, val)
	local row = Instance.new("Frame", parent)
	row.Size=UDim2.new(1,-2,0,28) row.BackgroundColor3=PALETTE.bgRow row.BorderSizePixel=0
	corner(row, 7) stroke(row, PALETTE.strokeSoft, 1, 0.5)

	local stripe = Instance.new("Frame", row)
	stripe.Size=UDim2.new(0,2,1,-10) stripe.Position=UDim2.new(0,5,0,5)
	stripe.BackgroundColor3=PALETTE.accent2 stripe.BorderSizePixel=0 corner(stripe, 999)

	local lbl = Instance.new("TextLabel", row)
	lbl.Size=UDim2.new(0.55,-12,1,0) lbl.Position=UDim2.new(0,14,0,0)
	lbl.BackgroundTransparency=1 lbl.Text=text
	lbl.TextColor3=PALETTE.textSubtle lbl.TextSize=10
	lbl.Font=Enum.Font.GothamMedium lbl.TextXAlignment=Enum.TextXAlignment.Left

	local badge = Instance.new("Frame", row)
	badge.AnchorPoint=Vector2.new(1,0.5) badge.Position=UDim2.new(1,-6,0.5,0)
	badge.Size=UDim2.new(0,56,0,18) badge.BackgroundColor3=Color3.fromRGB(24,32,58)
	badge.BorderSizePixel=0 corner(badge, 5) stroke(badge, PALETTE.accent2, 1, 0.55)

	local v = Instance.new("TextLabel", badge)
	v.Size=UDim2.new(1,-4,1,0) v.Position=UDim2.new(0,2,0,0)
	v.BackgroundTransparency=1 v.Text=val
	v.TextColor3=PALETTE.value v.TextSize=11
	v.Font=Enum.Font.GothamBold v.TextXAlignment=Enum.TextXAlignment.Center
	return v
end

local function showPage(name)
	local target = pages[name]
	if not target then return end
	for n,b in pairs(tabBtns) do
		local ind = b:FindFirstChild("Indicator")
		if n==name then
			tween(b, 0.2, {BackgroundTransparency=0, BackgroundColor3=Color3.fromRGB(55,60,150), TextColor3=PALETTE.text})
			if ind then tween(ind, 0.25, {Size=UDim2.new(0,2,0,18)}) end
		else
			tween(b, 0.2, {BackgroundTransparency=1, TextColor3=PALETTE.textDim})
			if ind then tween(ind, 0.2, {Size=UDim2.new(0,2,0,0)}) end
		end
	end
	if currentPage and pages[currentPage] and currentPage~=name then
		local o=pages[currentPage]
		tween(o, 0.15, {Position=UDim2.new(-0.08,0,0,5)})
		task.delay(0.15, function() o.Visible=false end)
	end
	target.Position=UDim2.new(0.08,0,0,5)
	target.Visible=true
	tween(target, 0.25, {Position=UDim2.new(0,5,0,5)}, Enum.EasingStyle.Quint)
	currentPage=name
end

-- PÁGINAS CON FUNCIONES
local combatPage = makePage()
makeToggle(combatPage, "Aim Assist", false, function(val)
	aimEnabled=val currentTarget=nil FOVFrame.Visible=val
end)
makeToggle(combatPage, "ESP", false, function(val)
	espEnabled=val
	if not val then
		for _,p in ipairs(Players:GetPlayers()) do
			if p.Character then local h=p.Character:FindFirstChild("ESP_HIGHLIGHT") if h then h:Destroy() end end
		end
	else
		for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then applyESP(p) end end
	end
end)
makeToggle(combatPage, "Hitbox ESP 🟩", false, function(val)
	hitboxEnabled=val
	if val then enableHitboxESP() else disableHitboxESP() end
end)

local teamsPage = makePage()
local cowV = makeInfo(teamsPage, "🤠 Cowboys", "0")
local outV = makeInfo(teamsPage, "🔴 Outlaws", "0")
local civV = makeInfo(teamsPage, "🔵 Civilians", "0")
local myV  = makeInfo(teamsPage, "👤 Mi equipo", "—")

local farmPage = makePage()
makeToggle(farmPage, "Auto-Rob", false, function(val) autoRobEnabled=val end)
local bagV = makeInfo(farmPage, "💰 Bolsa", "0")

tabBtns["Combat"]=makeTab("Combat")
tabBtns["Teams"] =makeTab("Teams")
tabBtns["Farm"]  =makeTab("Farm")
pages["Combat"]=combatPage pages["Teams"]=teamsPage pages["Farm"]=farmPage

tabBtns["Combat"].MouseButton1Click:Connect(function() showPage("Combat") end)
tabBtns["Teams"] .MouseButton1Click:Connect(function() showPage("Teams")  end)
tabBtns["Farm"]  .MouseButton1Click:Connect(function() showPage("Farm")   end)

task.defer(function() showPage("Combat") end)

RunService.Heartbeat:Connect(function()
	local cow,out,civ=0,0,0
	for _,p in ipairs(Players:GetPlayers()) do
		if p.Team then
			if p.Team.Name=="Cowboys" then cow+=1
			elseif p.Team.Name=="Outlaws" then out+=1
			elseif p.Team.Name=="Civilians" then civ+=1
			end
		end
	end
	cowV.Text=tostring(cow) outV.Text=tostring(out) civV.Text=tostring(civ)
	myV.Text=LocalPlayer.Team and LocalPlayer.Team.Name or "—"
	bagV.Text=tostring(getBagMoney())
end)

-- BOLITA
local Dot = Instance.new("TextButton", Gui)
Dot.Name="FloatingDot" Dot.Size=UDim2.new(0,40,0,40)
Dot.Position=UDim2.new(0,14,0.5,-20) Dot.BackgroundColor3=Color3.fromRGB(18,20,30)
Dot.BorderSizePixel=0 Dot.Text="" Dot.AutoButtonColor=false Dot.ZIndex=20 Dot.Active=true
corner(Dot, 999)

local ds=stroke(Dot, Color3.fromRGB(255,255,255), 1.5, 0.2)
local dsGrad=Instance.new("UIGradient",ds)
dsGrad.Rotation=0
dsGrad.Color=ColorSequence.new{
	ColorSequenceKeypoint.new(0.00, PALETTE.accent2),
	ColorSequenceKeypoint.new(0.50, PALETTE.accent),
	ColorSequenceKeypoint.new(1.00, PALETTE.accentWarm),
}
task.spawn(function()
	local t=0
	while Dot.Parent do t=(t+3)%360 dsGrad.Rotation=t task.wait(0.04) end
end)

local ring=Instance.new("Frame",Dot)
ring.AnchorPoint=Vector2.new(0.5,0.5) ring.Position=UDim2.new(0.5,0,0.5,0)
ring.Size=UDim2.new(1,-6,1,-6) ring.BackgroundColor3=Color3.fromRGB(25,27,42)
ring.BorderSizePixel=0 ring.ZIndex=21 corner(ring, 999)
local ringGrad=Instance.new("UIGradient",ring)
ringGrad.Rotation=45
ringGrad.Color=ColorSequence.new{
	ColorSequenceKeypoint.new(0, Color3.fromRGB(35,40,75)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(15,16,26)),
}

local icon=Instance.new("TextLabel",ring)
icon.BackgroundTransparency=1 icon.AnchorPoint=Vector2.new(0.5,0.5)
icon.Position=UDim2.new(0.5,0,0.5,0) icon.Size=UDim2.new(1,0,1,0)
icon.Text="✦" icon.TextColor3=PALETTE.text icon.TextSize=18
icon.Font=Enum.Font.GothamBold icon.ZIndex=22

local statusDot=Instance.new("Frame",Dot)
statusDot.AnchorPoint=Vector2.new(1,0) statusDot.Position=UDim2.new(1,-3,0,3)
statusDot.Size=UDim2.new(0,8,0,8) statusDot.BackgroundColor3=PALETTE.good
statusDot.BorderSizePixel=0 statusDot.ZIndex=23
corner(statusDot, 999) stroke(statusDot, Color3.fromRGB(10,11,16), 1.5, 0)
task.spawn(function()
	while statusDot.Parent do
		tween(statusDot, 0.7, {BackgroundTransparency=0.5}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) task.wait(0.75)
		tween(statusDot, 0.7, {BackgroundTransparency=0}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) task.wait(0.75)
	end
end)

local dotScale=Instance.new("UIScale",Dot) dotScale.Scale=1
Dot.MouseEnter:Connect(function() tween(dotScale, 0.15, {Scale=1.08}) tween(ring, 0.2, {BackgroundColor3=Color3.fromRGB(35,40,70)}) end)
Dot.MouseLeave:Connect(function() tween(dotScale, 0.15, {Scale=1.00}) tween(ring, 0.2, {BackgroundColor3=Color3.fromRGB(25,27,42)}) end)

local dragging,dragStart,startPos,touchStart=false,nil,nil,0
local moved=0
Dot.InputBegan:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
		dragging=true dragStart=i.Position startPos=Dot.Position touchStart=tick() moved=0
		tween(dotScale, 0.1, {Scale=0.92})
	end
end)
Dot.InputChanged:Connect(function(i)
	if dragging and (i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement) then
		local d=i.Position-dragStart moved=math.max(moved, d.Magnitude)
		Dot.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
	end
end)
Dot.InputEnded:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
		tween(dotScale, 0.2, {Scale=1}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if tick()-touchStart<0.25 and moved<10 then
			Panel.Visible=not Panel.Visible
			if Panel.Visible then
				local s=Instance.new("UIScale",Panel) s.Scale=0.92
				tween(s, 0.25, {Scale=1}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				task.delay(0.3, function() if s then s:Destroy() end end)
			end
			tween(statusDot, 0.2, {BackgroundColor3=Panel.Visible and PALETTE.good or PALETTE.bad})
		end
		dragging=false
	end
end)

-- AIM
local function isFirstPerson()
	return (Camera.Focus.Position-Camera.CFrame.Position).Magnitude<1
end

local function getClosestTarget()
	local closest,shortest=nil,math.huge
	for _,p in ipairs(Players:GetPlayers()) do
		if p~=LocalPlayer and p.Character and p.Team and isEnemy(p) then
			local hum=p.Character:FindFirstChild("Humanoid")
			local part=p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health>0 and part then
				local wd=(part.Position-Camera.CFrame.Position).Magnitude
				if wd<MAX_DISTANCE then
					local pos=Camera:WorldToViewportPoint(part.Position)
					local center=Camera.ViewportSize/2
					local dist=(Vector2.new(pos.X,pos.Y)-center).Magnitude
					if dist<shortest and dist<FOV_RADIUS then shortest=dist closest=part end
				end
			end
		end
	end
	return closest
end

RunService.RenderStepped:Connect(function()
	if not aimEnabled then FOVFrame.Visible=false return end
	if not Camera then return end
	if not isFirstPerson() then FOVFrame.Visible=false currentTarget=nil return end
	FOVFrame.Visible=true
	if currentTarget then
		local hum=currentTarget.Parent and currentTarget.Parent:FindFirstChild("Humanoid")
		if not currentTarget.Parent or not hum or hum.Health<=0 then currentTarget=nil targetLockTime=0 end
	end
	if not currentTarget or (tick()-targetLockTime)>LOCK_DURATION then
		local nt=getClosestTarget()
		if nt and nt~=currentTarget then currentTarget=nt targetLockTime=tick() end
	end
	if currentTarget then
		Camera.CFrame=CFrame.new(Camera.CFrame.Position,currentTarget.Position)
	end
end)
