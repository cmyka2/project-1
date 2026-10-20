-- Stage select + turn-based battle screen. The server decides everything; this only shows state and sends choices.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local B = require(RS:WaitForChild("Monster"):WaitForChild("BattleConfig"))
local Dice = require(RS.Monster:WaitForChild("DiceConfig"))
local BattleAction = RS.Monster:WaitForChild("BattleAction")
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server
local ROLE = { Attacker = "⚔️", Tank = "🛡", Healer = "➕", Support = "🎶", Controller = "🌀", Specialist = "🎯" }
local ICON = { Nature = "🌿", Earth = "🟫", Water = "💧", Fire = "🔥", Lightning = "⚡", Light = "✨", Shadow = "🌑", Cosmic = "🌌" }

local function short(n)
	for _, u in { { 1e21, "sx" }, { 1e18, "qn" }, { 1e15, "qd" }, { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return (("%.1f"):format(n / u[1]):gsub("%.0$", "")) .. u[2] end
	end
	return tostring(math.floor(n))
end
local function text(class, parent, str, size, pos, color)
	local l = Instance.new(class) l.Size = size l.Position = pos l.BackgroundTransparency = 1 l.Font = Enum.Font.FredokaOne l.TextScaled = true
	l.Text = str l.TextColor3 = color or Color3.new(1, 1, 1) l.TextStrokeTransparency = 0 l.Parent = parent
	return l
end
local function btn(parent, str, size, pos, color)
	local b = text("TextButton", parent, str, size, pos)
	b.BackgroundTransparency = 0 b.BackgroundColor3 = color
	Instance.new("UICorner", b)
	local st = Instance.new("UIStroke", b) st.Thickness = 3 st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return b
end
local function bar(parent, pos, color, frac)
	local bg = Instance.new("Frame") bg.Size = UDim2.new(1, -12, 0, 12) bg.Position = pos bg.BackgroundColor3 = Color3.fromRGB(30, 30, 35) bg.Parent = parent
	Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)
	local f = Instance.new("Frame") f.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1) f.BackgroundColor3 = color f.Parent = bg
	Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
end
local function decode(attr)
	local ok, v = pcall(Http.JSONDecode, Http, state:GetAttribute(attr) or "")
	return ok and v or {}
end

local gui = Instance.new("ScreenGui") gui.Name = "BattleUI" gui.ResetOnSpawn = false gui.IgnoreGuiInset = true gui.Parent = player:WaitForChild("PlayerGui")

-- STAGE SELECT
local stages = Instance.new("Frame") stages.AnchorPoint = Vector2.new(0.5, 0.5) stages.Position = UDim2.fromScale(0.5, 0.5) stages.Size = UDim2.fromScale(0.7, 0.7)
stages.BackgroundColor3 = Color3.fromRGB(60, 30, 30) stages.Visible = false stages.Parent = gui
local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(700, 520) lim.Parent = stages
Instance.new("UICorner", stages).CornerRadius = UDim.new(0, 18)
Instance.new("UIStroke", stages).Thickness = 4
text("TextLabel", stages, "BATTLES", UDim2.fromScale(0.6, 0.1), UDim2.fromScale(0.03, 0.02)).TextXAlignment = Enum.TextXAlignment.Left
local stageMsg = text("TextLabel", stages, "", UDim2.fromScale(0.94, 0.06), UDim2.fromScale(0.03, 0.13), Color3.fromRGB(255, 200, 120))
local sx = btn(stages, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 8), Color3.fromRGB(220, 50, 50))
sx.MouseButton1Click:Connect(function() stages.Visible = false end)
local stageList = Instance.new("ScrollingFrame") stageList.Position = UDim2.fromScale(0.03, 0.22) stageList.Size = UDim2.fromScale(0.94, 0.75) stageList.BackgroundTransparency = 1
stageList.BorderSizePixel = 0 stageList.CanvasSize = UDim2.new() stageList.AutomaticCanvasSize = Enum.AutomaticSize.Y stageList.ScrollBarThickness = 8 stageList.Parent = stages
local sll = Instance.new("UIListLayout") sll.Padding = UDim.new(0, 8) sll.Parent = stageList

-- BATTLE SCREEN
-- mostly see-through: the server builds a 3D arena around you for each battle
local screen = Instance.new("Frame") screen.Size = UDim2.fromScale(1, 1) screen.BackgroundColor3 = Color3.fromRGB(18, 22, 30) screen.BackgroundTransparency = 0.7
screen.Visible = false screen.Parent = gui
local title = text("TextLabel", screen, "", UDim2.fromScale(0.6, 0.06), UDim2.fromScale(0.2, 0.02))
local turnL = text("TextLabel", screen, "", UDim2.fromScale(0.8, 0.05), UDim2.fromScale(0.1, 0.43), Color3.fromRGB(255, 220, 90))
local msg = text("TextLabel", screen, "", UDim2.fromScale(0.8, 0.04), UDim2.fromScale(0.1, 0.48), Color3.fromRGB(255, 140, 140))
local function row(y)
	local f = Instance.new("Frame") f.Size = UDim2.fromScale(0.96, 0.3) f.Position = UDim2.fromScale(0.02, y) f.BackgroundTransparency = 1 f.Parent = screen
	local l = Instance.new("UIListLayout") l.FillDirection = Enum.FillDirection.Horizontal l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center l.Padding = UDim.new(0, 12) l.Parent = f
	return f
end
local enemyRow, teamRow = row(0.1), row(0.53)
local actions = Instance.new("Frame") actions.Size = UDim2.fromScale(0.96, 0.1) actions.Position = UDim2.fromScale(0.02, 0.85) actions.BackgroundTransparency = 1 actions.Parent = screen
local al = Instance.new("UIListLayout") al.FillDirection = Enum.FillDirection.Horizontal al.HorizontalAlignment = Enum.HorizontalAlignment.Center al.Padding = UDim.new(0, 10) al.Parent = actions
local logL = text("TextLabel", screen, "", UDim2.fromScale(0.3, 0.2), UDim2.fromScale(0.01, 0.62), Color3.fromRGB(210, 210, 220))
logL.TextScaled = false logL.TextSize = 15 logL.TextWrapped = true logL.TextXAlignment = Enum.TextXAlignment.Left logL.TextYAlignment = Enum.TextYAlignment.Bottom
local flee = btn(screen, "Flee", UDim2.fromOffset(100, 44), UDim2.new(1, -112, 0, 12), Color3.fromRGB(120, 60, 60))
local over = Instance.new("Frame") over.AnchorPoint = Vector2.new(0.5, 0.5) over.Position = UDim2.fromScale(0.5, 0.45) over.Size = UDim2.fromOffset(420, 260)
over.BackgroundColor3 = Color3.fromRGB(30, 34, 50) over.Visible = false over.ZIndex = 5 over.Parent = screen
Instance.new("UICorner", over).CornerRadius = UDim.new(0, 18)
Instance.new("UIStroke", over).Thickness = 4
local overT = text("TextLabel", over, "", UDim2.fromScale(0.9, 0.3), UDim2.fromScale(0.05, 0.05)) overT.ZIndex = 6
local overR = text("TextLabel", over, "", UDim2.fromScale(0.9, 0.3), UDim2.fromScale(0.05, 0.36), Color3.fromRGB(140, 255, 140)) overR.ZIndex = 6
local cont = btn(over, "Continue", UDim2.fromScale(0.5, 0.2), UDim2.fromScale(0.25, 0.74), Color3.fromRGB(50, 160, 70)) cont.ZIndex = 6

local state, target
local function call(...)
	local ok, res = BattleAction:InvokeServer(...)
	if not ok then msg.Text = res return nil end
	msg.Text = ""
	return res
end

local function card(parent, u, i, active)
	local c = Instance.new("TextButton") c.Text = "" c.AutoButtonColor = false c.Size = UDim2.fromOffset(170, 150)
	c.BackgroundColor3 = u.side == "enemy" and Color3.fromRGB(80, 35, 35) or Color3.fromRGB(35, 55, 90) c.Parent = parent
	Instance.new("UICorner", c)
	local st = Instance.new("UIStroke", c) st.Thickness = (active or i == target) and 5 or 2
	st.Color = active and Color3.fromRGB(255, 215, 60) or (i == target and Color3.new(1, 1, 1) or Color3.new(0, 0, 0))
	c.BackgroundTransparency = u.alive and 0 or 0.6
	text("TextLabel", c, (ICON[u.element] or "") .. " " .. u.name, UDim2.new(1, -8, 0, 30), UDim2.fromOffset(4, 6))
	text("TextLabel", c, u.alive and (u.hp .. " / " .. u.maxHp .. " HP") or "KO", UDim2.new(1, -8, 0, 22), UDim2.fromOffset(4, 40), u.alive and Color3.new(1, 1, 1) or Color3.fromRGB(150, 150, 150))
	bar(c, UDim2.fromOffset(6, 66), Color3.fromRGB(80, 220, 90), u.hp / u.maxHp)
	bar(c, UDim2.fromOffset(6, 84), Color3.fromRGB(255, 200, 50), u.energy / 100)
	local tags = {}
	if u.boss then table.insert(tags, "👑") end
	if u.role then table.insert(tags, ROLE[u.role] or "") end
	if u.defending then table.insert(tags, "🛡️ Defending") end
	if u.shield > 0 then table.insert(tags, "🔰" .. u.shield) end
	for name, left in u.status do
		local st = B.Status[name]
		if st and name ~= "shield" then table.insert(tags, st.icon .. left) end
	end
	if u.cd > 0 then table.insert(tags, u.skill .. " " .. u.cd) end
	text("TextLabel", c, table.concat(tags, "  "), UDim2.new(1, -8, 0, 20), UDim2.fromOffset(4, 104), Color3.fromRGB(200, 200, 220))
	if u.side == "enemy" then
		c.MouseButton1Click:Connect(function() if u.alive then target = i render() end end)
	end
end

function render()
	for _, f in { enemyRow, teamRow, actions } do for _, ch in f:GetChildren() do if ch:IsA("GuiObject") then ch:Destroy() end end end
	if not state then return end
	local units = state.units
	if not (target and units[target] and units[target].alive and units[target].side == "enemy") then
		target = nil
		for i, u in units do if u.side == "enemy" and u.alive then target = i break end end
	end
	for i, u in units do card(u.side == "enemy" and enemyRow or teamRow, u, i, i == state.active and not state.over) end
	title.Text = state.stage .. "  •  Round " .. state.round
	local logs = {}
	for k = math.max(1, #state.log - 4), #state.log do table.insert(logs, state.log[k]) end
	logL.Text = table.concat(logs, "\n")
	over.Visible = state.over
	if state.over then
		overT.Text = state.winner == "player" and "VICTORY!" or "DEFEAT"
		overT.TextColor3 = state.winner == "player" and Color3.fromRGB(255, 220, 80) or Color3.fromRGB(255, 90, 90)
		overR.Text = state.rewards and #state.rewards > 0 and ("Rewards: " .. table.concat(state.rewards, ", ")) or "No rewards"
		turnL.Text = ""
		return
	end
	local me = units[state.active]
	turnL.Text = "Your turn: " .. me.name .. "  •  tap an enemy to target it"
	local function act(label, action, enabled, color)
		local b = btn(actions, label, UDim2.fromOffset(150, 64), UDim2.new(), enabled and color or Color3.fromRGB(70, 70, 80))
		b.MouseButton1Click:Connect(function()
			local res = call("act", action, target)
			if res then state = res render() end
		end)
	end
	act("Attack", "attack", true, Color3.fromRGB(220, 80, 60))
	act(me.skill .. (me.cd > 0 and " (" .. me.cd .. ")" or ""), "skill", me.cd == 0, Color3.fromRGB(80, 130, 230))
	act("Defend", "defend", true, Color3.fromRGB(90, 160, 90))
	act("Ultimate " .. me.energy .. "%", "ultimate", me.energy >= 100, Color3.fromRGB(200, 90, 230))
end

local function refreshStages()
	for _, ch in stageList:GetChildren() do if ch:IsA("GuiObject") then ch:Destroy() end end
	local prog, dice, teams = decode("BattleProgress"), decode("Dice"), decode("Teams")
	local order = 0
	-- team presets (Extra Team Preset node adds more); pick one, edit members in the BAG
	local presets = teams.presets or 1
	local bar = Instance.new("Frame") bar.Size = UDim2.new(1, 0, 0, 44) bar.BackgroundTransparency = 1 bar.LayoutOrder = 0 bar.Parent = stageList
	local bl = Instance.new("UIListLayout") bl.FillDirection = Enum.FillDirection.Horizontal bl.Padding = UDim.new(0, 8) bl.Parent = bar
	for k = 1, presets do
		local n = teams.list and teams.list[k] and #teams.list[k] or 0
		local b = btn(bar, "Team " .. k .. " (" .. n .. "/3)", UDim2.fromOffset(150, 40), UDim2.new(),
			k == (teams.active or 1) and Color3.fromRGB(60, 140, 230) or Color3.fromRGB(70, 70, 80))
		b.MouseButton1Click:Connect(function()
			local ok, err = BattleAction:InvokeServer("preset", k)
			stageMsg.Text = ok and ("Team " .. k .. " selected. Edit it in the BAG.") or err
			refreshStages()
		end)
	end
	for _, region in B.Regions do
		local dieOk = not region.requiresDie or dice[region.requiresDie]
		local h = text("TextLabel", stageList, region.icon .. " " .. region.name .. (dieOk and "" or ("  (needs the " .. Dice.ById[region.requiresDie].name .. ")")),
			UDim2.new(1, 0, 0, 36), UDim2.new(), Color3.fromRGB(140, 230, 120))
		h.TextXAlignment = Enum.TextXAlignment.Left
		order += 1 h.LayoutOrder = order
		for _, st in region.stages do
			local prev = B.PrevStage[st.id]
			local unlocked = dieOk and (not prev or prog[prev])
			local label = (prog[st.id] and "✅ " or (unlocked and "⚔️ " or "🔒 ")) .. st.name .. "   •   $" .. short(st.cash)
				.. (st.firstClearGear and not prog[st.id] and ("  + " .. st.firstClearGear .. " gear") or "")
			local b = btn(stageList, label, UDim2.new(1, 0, 0, 56), UDim2.new(), unlocked and (st.boss and Color3.fromRGB(170, 50, 50) or Color3.fromRGB(150, 90, 40)) or Color3.fromRGB(70, 70, 80))
			order += 1 b.LayoutOrder = order
			b.MouseButton1Click:Connect(function()
				if not unlocked then stageMsg.Text = dieOk and "Clear the previous stage first" or ("Buy the " .. Dice.ById[region.requiresDie].name .. " first") return end
				local ok, res = BattleAction:InvokeServer("start", st.id)
				if not ok then stageMsg.Text = res return end
				state, target = res, nil
				stages.Visible = false
				screen.Visible = true
				render()
			end)
		end
	end
end
state:GetAttributeChangedSignal("Teams"):Connect(function() if stages.Visible then refreshStages() end end)
state:GetAttributeChangedSignal("BattleProgress"):Connect(function() if stages.Visible then refreshStages() end end)

local function leave()
	BattleAction:InvokeServer("leave")
	state = nil
	screen.Visible = false
	refreshStages()
	stages.Visible = true
end
flee.MouseButton1Click:Connect(leave)
cont.MouseButton1Click:Connect(leave)

local hudGui = Instance.new("ScreenGui") hudGui.Name = "BattleHUD" hudGui.ResetOnSpawn = false hudGui.Parent = gui.Parent -- same inset as the other HUD buttons
local hud = btn(hudGui, "BATTLE", UDim2.fromOffset(120, 50), UDim2.new(0, 12, 0.5, 126), Color3.fromRGB(200, 60, 40))
hud.MouseButton1Click:Connect(function()
	if screen.Visible then return end
	stageMsg.Text = ""
	refreshStages()
	stages.Visible = not stages.Visible
end)
