-- Prompts on your own plot's pedestals (every floor) + a picker to place owned monsters. Server validates everything.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local Config = require(RS:WaitForChild("Monster"):WaitForChild("MonsterConfig"))
local F = require(RS.Monster:WaitForChild("Formulas"))
local PlaceMonster = RS.Monster:WaitForChild("PlaceMonster")
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server

local function decode(attr)
	local ok, v = pcall(Http.JSONDecode, Http, state:GetAttribute(attr) or "")
	return ok and v or {}
end
local function short(n)
	for _, u in { { 1e21, "sx" }, { 1e18, "qn" }, { 1e15, "qd" }, { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return (("%.1f"):format(n / u[1]):gsub("%.0$", "")) .. u[2] end
	end
	return tostring(math.floor(n))
end

-- picker UI
local gui = Instance.new("ScreenGui") gui.Name = "BaseUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")
local panel = Instance.new("Frame") panel.AnchorPoint = Vector2.new(0.5, 0.5) panel.Position = UDim2.fromScale(0.5, 0.5) panel.Size = UDim2.fromScale(0.7, 0.7)
panel.BackgroundColor3 = Color3.fromRGB(30, 32, 48) panel.Visible = false panel.Parent = gui
local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(720, 560) lim.Parent = panel
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
local ps = Instance.new("UIStroke", panel) ps.Thickness = 4
local function text(class, parent, str, size, pos, color)
	local l = Instance.new(class) l.Size = size l.Position = pos l.BackgroundTransparency = 1 l.Font = Enum.Font.FredokaOne l.TextScaled = true
	l.Text = str l.TextColor3 = color or Color3.new(1, 1, 1) l.TextStrokeTransparency = 0 l.Parent = parent
	return l
end
local title = text("TextLabel", panel, "", UDim2.fromScale(0.8, 0.1), UDim2.fromScale(0.03, 0.02))
title.TextXAlignment = Enum.TextXAlignment.Left
local msg = text("TextLabel", panel, "", UDim2.fromScale(0.94, 0.06), UDim2.fromScale(0.03, 0.12), Color3.fromRGB(255, 120, 120))
local close = text("TextButton", panel, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 8))
close.BackgroundTransparency = 0 close.BackgroundColor3 = Color3.fromRGB(220, 50, 50) Instance.new("UICorner", close)
close.MouseButton1Click:Connect(function() panel.Visible = false end)
local list = Instance.new("ScrollingFrame") list.Position = UDim2.fromScale(0.03, 0.2) list.Size = UDim2.fromScale(0.94, 0.77)
list.BackgroundTransparency = 1 list.BorderSizePixel = 0 list.CanvasSize = UDim2.new() list.AutomaticCanvasSize = Enum.AutomaticSize.Y list.ScrollBarThickness = 8 list.Parent = panel
local grid = Instance.new("UIGridLayout") grid.CellSize = UDim2.fromOffset(200, 70) grid.CellPadding = UDim2.fromOffset(8, 8)
grid.SortOrder = Enum.SortOrder.LayoutOrder grid.HorizontalAlignment = Enum.HorizontalAlignment.Center grid.Parent = list

local function openPicker(slot)
	for _, c in list:GetChildren() do if c:IsA("GuiButton") then c:Destroy() end end
	local mons, placed = decode("Monsters"), decode("Placed")
	local used = {}
	for _, iid in placed do used[iid] = true end
	local free = {}
	for iid, m in mons do
		if not used[iid] and Config.ById[m.id] then table.insert(free, { iid = iid, m = m }) end
	end
	table.sort(free, function(a, b) return a.m.inc > b.m.inc end)
	title.Text = "Place on Slot " .. slot .. " (Floor " .. F.slotFloor(slot) .. ")"
	msg.Text = #free == 0 and "No free monsters. Roll at the Summon Area!" or ""
	for i, e in free do
		local def, v = Config.ById[e.m.id], e.m.v
		local rar = Config.RarityById[def.rarity]
		local b = Instance.new("TextButton") b.Text = "" b.LayoutOrder = i b.BackgroundColor3 = Color3.fromRGB(45, 48, 68) b.Parent = list
		Instance.new("UICorner", b)
		local st = Instance.new("UIStroke", b) st.Thickness = 3 st.Color = v ~= "Normal" and Config.VariantById[v].color or rar.color st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		text("TextLabel", b, (v ~= "Normal" and v:upper() .. " " or "") .. def.name, UDim2.new(1, -10, 0.5, 0), UDim2.fromOffset(5, 3), rar.color)
		text("TextLabel", b, "$" .. short(e.m.inc) .. "/s   Lv " .. e.m.lvl .. (e.m.fr > 0 and ("  ★" .. e.m.fr) or ""), UDim2.new(1, -10, 0.38, 0), UDim2.new(0, 5, 0.55, 0), Color3.fromRGB(120, 255, 120))
		b.MouseButton1Click:Connect(function()
			local ok, err = PlaceMonster:InvokeServer(slot, e.iid)
			if ok then panel.Visible = false else msg.Text = err end
		end)
	end
	panel.Visible = true
end

-- local prompts, only on my plot (nobody else sees them); upper floors appear as rebirths unlock them
local prompts = {}
local function refreshPrompts()
	local placed, slots = decode("Placed"), state:GetAttribute("Slots") or 5
	for i, pp in prompts do
		local unlocked = i <= slots
		pp.ActionText = not unlocked and ("Locked: Rebirth " .. F.slotRebirth(i)) or (placed[tostring(i)] and "Remove" or "Place Monster")
		pp.ObjectText = "Slot " .. i
	end
end
local function addSlot(slot)
	local i = slot:IsA("BasePart") and slot:GetAttribute("SlotIndex")
	if not i or prompts[i] then return end
	local pp = Instance.new("ProximityPrompt") pp.HoldDuration = 0 pp.MaxActivationDistance = 10 pp.RequiresLineOfSight = false
	pp.Parent = slot
	prompts[i] = pp
	pp.Triggered:Connect(function()
		if i > (state:GetAttribute("Slots") or 5) then return end
		if decode("Placed")[tostring(i)] then
			PlaceMonster:InvokeServer(i, nil)
		else
			openPicker(i)
		end
	end)
	pp.Destroying:Connect(function() if prompts[i] == pp then prompts[i] = nil end end)
end
local conn
local function setup()
	for _, pp in prompts do pp:Destroy() end
	table.clear(prompts)
	if conn then conn:Disconnect() conn = nil end
	local id = player:GetAttribute("PlotId")
	local plot = id and workspace:WaitForChild("Hub"):WaitForChild("Plots"):WaitForChild("Plot" .. id, 10)
	if not plot then return end
	for _, d in plot:GetDescendants() do addSlot(d) end
	conn = plot.DescendantAdded:Connect(function(d)
		task.defer(function() addSlot(d) refreshPrompts() end) -- attributes land with the part; defer to read them
	end)
	refreshPrompts()
end
-- PLACE BEST: the server fills every unlocked slot with your top earners
local best = Instance.new("TextButton") best.Size = UDim2.fromOffset(120, 44) best.AnchorPoint = Vector2.new(0, 0.5) best.Position = UDim2.new(0, 12, 0.5, -112)
best.BackgroundColor3 = Color3.fromRGB(230, 170, 40) best.Font = Enum.Font.FredokaOne best.TextScaled = true best.Text = "⭐ PLACE BEST"
best.TextColor3 = Color3.new(1, 1, 1) best.TextStrokeTransparency = 0 best.Parent = gui
Instance.new("UICorner", best)
local bst = Instance.new("UIStroke", best) bst.Thickness = 3 bst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
best.MouseButton1Click:Connect(function() PlaceMonster:InvokeServer("best") end)
player:GetAttributeChangedSignal("PlotId"):Connect(setup)
state:GetAttributeChangedSignal("Placed"):Connect(refreshPrompts)
state:GetAttributeChangedSignal("Slots"):Connect(refreshPrompts)
setup()
