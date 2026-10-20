-- Dice shop panel (buy/equip) + current-die HUD label.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PPS = game:GetService("ProximityPromptService")
local Http = game:GetService("HttpService")
local Config = require(RS:WaitForChild("Monster"):WaitForChild("MonsterConfig"))
local Dice = require(RS.Monster:WaitForChild("DiceConfig"))
local DiceAction = RS.Monster:WaitForChild("DiceAction")
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server

local function short(n)
	for _, u in { { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return (("%.1f"):format(n / u[1]):gsub("%.0$", "")) .. u[2] end
	end
	return tostring(math.floor(n))
end
local function text(class, parent, str, size, pos, color)
	local l = Instance.new(class) l.Size = size l.Position = pos l.BackgroundTransparency = 1 l.Font = Enum.Font.FredokaOne l.TextScaled = true
	l.Text = str l.TextColor3 = color or Color3.new(1, 1, 1) l.TextStrokeTransparency = 0 l.Parent = parent
	return l
end
local function decode(attr)
	local ok, v = pcall(Http.JSONDecode, Http, state:GetAttribute(attr) or "")
	return ok and v or {}
end

local gui = Instance.new("ScreenGui") gui.Name = "DiceUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")
local hud = text("TextLabel", gui, "", UDim2.fromOffset(240, 28), UDim2.new(0, 12, 0.5, 34))
hud.TextXAlignment = Enum.TextXAlignment.Left

local panel = Instance.new("Frame") panel.AnchorPoint = Vector2.new(0.5, 0.5) panel.Position = UDim2.fromScale(0.5, 0.5) panel.Size = UDim2.fromScale(0.75, 0.8)
panel.BackgroundColor3 = Color3.fromRGB(30, 40, 70) panel.Visible = false panel.Parent = gui
local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(760, 640) lim.Parent = panel
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
local ps = Instance.new("UIStroke", panel) ps.Thickness = 4
text("TextLabel", panel, "DICE SHOP", UDim2.fromScale(0.6, 0.09), UDim2.fromScale(0.03, 0.02)).TextXAlignment = Enum.TextXAlignment.Left
local msg = text("TextLabel", panel, "", UDim2.fromScale(0.94, 0.05), UDim2.fromScale(0.03, 0.115), Color3.fromRGB(255, 220, 120))
local close = text("TextButton", panel, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 8))
close.BackgroundTransparency = 0 close.BackgroundColor3 = Color3.fromRGB(220, 50, 50) Instance.new("UICorner", close)
close.MouseButton1Click:Connect(function() panel.Visible = false end)
local list = Instance.new("ScrollingFrame") list.Position = UDim2.fromScale(0.03, 0.18) list.Size = UDim2.fromScale(0.94, 0.79)
list.BackgroundTransparency = 1 list.BorderSizePixel = 0 list.CanvasSize = UDim2.new() list.AutomaticCanvasSize = Enum.AutomaticSize.Y list.ScrollBarThickness = 8 list.Parent = panel
local layout = Instance.new("UIListLayout") layout.Padding = UDim.new(0, 8) layout.SortOrder = Enum.SortOrder.LayoutOrder layout.Parent = list

local rows = {}
for i, die in Dice.List do
	local row = Instance.new("Frame") row.Size = UDim2.new(1, -12, 0, 72) row.BackgroundColor3 = Color3.fromRGB(45, 55, 90) row.LayoutOrder = i row.Parent = list
	Instance.new("UICorner", row)
	local sw = Instance.new("Frame") sw.Size = UDim2.fromOffset(52, 52) sw.Position = UDim2.fromOffset(10, 10) sw.BackgroundColor3 = die.color sw.Parent = row
	Instance.new("UICorner", sw).CornerRadius = UDim.new(0, 10)
	local st = Instance.new("UIStroke", sw) st.Thickness = 3
	for _, o in { { 0.25, 0.25 }, { 0.5, 0.5 }, { 0.75, 0.75 } } do
		local pip = Instance.new("Frame") pip.AnchorPoint = Vector2.new(0.5, 0.5) pip.Position = UDim2.fromScale(o[1], o[2]) pip.Size = UDim2.fromScale(0.18, 0.18)
		pip.BackgroundColor3 = die.id == "glitch" and Color3.new(0, 0, 0) or Color3.new(1, 1, 1) pip.Parent = sw
		Instance.new("UICorner", pip).CornerRadius = UDim.new(1, 0)
	end
	local cap = Config.Rarities[die.maxTier].id
	text("TextLabel", row, die.name, UDim2.new(0.5, -80, 0, 32), UDim2.fromOffset(74, 6), die.color).TextXAlignment = Enum.TextXAlignment.Left
	text("TextLabel", row, "Luck x" .. die.luck .. "  •  up to " .. cap, UDim2.new(0.5, -80, 0, 24), UDim2.fromOffset(74, 40), Config.RarityById[cap].color).TextXAlignment = Enum.TextXAlignment.Left
	local b = text("TextButton", row, "", UDim2.new(0.3, 0, 0, 50), UDim2.new(0.68, 0, 0, 11))
	b.BackgroundTransparency = 0
	Instance.new("UICorner", b)
	local bs = Instance.new("UIStroke", b) bs.Thickness = 3 bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rows[die.id] = { button = b, die = die }
	b.MouseButton1Click:Connect(function()
		local owned = decode("Dice")
		local ok, err = DiceAction:InvokeServer(owned[die.id] and "equip" or "buy", die.id)
		msg.Text = ok and ((owned[die.id] and "Equipped " or "Bought ") .. die.name .. "!") or err
	end)
end

local function refresh()
	local owned, sel, cash = decode("Dice"), state:GetAttribute("SelectedDie"), state:GetAttribute("Cash") or 0
	local cur = Dice.ById[sel or "grassland"] or Dice.List[1]
	hud.Text = "🎲 " .. cur.name .. "  •  Luck x" .. ("%.2f"):format(state:GetAttribute("Luck") or 1):gsub("%.?0+$", "")
	for i, r in rows do
		local die, b = r.die, r.button
		local prev = Dice.List[Dice.Index[die.id] - 1]
		if die.id == sel then
			b.Text, b.BackgroundColor3 = "Equipped", Color3.fromRGB(90, 95, 110)
		elseif owned[die.id] then
			b.Text, b.BackgroundColor3 = "Equip", Color3.fromRGB(40, 130, 230)
		elseif prev and not owned[prev.id] then
			b.Text, b.BackgroundColor3 = "🔒 Locked", Color3.fromRGB(60, 60, 70)
		else
			b.Text = "Buy $" .. short(die.cost)
			b.BackgroundColor3 = cash >= die.cost and Color3.fromRGB(50, 180, 70) or Color3.fromRGB(150, 60, 60)
		end
	end
end
for _, a in { "Dice", "SelectedDie", "Luck" } do state:GetAttributeChangedSignal(a):Connect(refresh) end
state:GetAttributeChangedSignal("Cash"):Connect(function() if panel.Visible then refresh() end end)
PPS.PromptTriggered:Connect(function(prompt)
	if prompt:FindFirstAncestor("DiceShop") then msg.Text = "" refresh() panel.Visible = true end
end)
refresh()
