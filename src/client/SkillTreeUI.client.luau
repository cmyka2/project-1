-- Evolution Tree (cash) + Ascension Tree (Ascension Points). Six branches on a hex grid, nodes joined by lines.
-- Tap a node to see it, tap it again to buy the next rank. The server checks every purchase.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PPS = game:GetService("ProximityPromptService")
local Http = game:GetService("HttpService")
local Tree = require(RS:WaitForChild("Monster"):WaitForChild("SkillTree"))
local BuySkill = RS.Monster:WaitForChild("BuySkill")
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server

local BLACK = Color3.new(0, 0, 0)
local LOCKED, AVAIL = Color3.fromRGB(32, 32, 38), Color3.fromRGB(52, 52, 62)
local SQ3 = math.sqrt(3)

local function fmt(n)
	for _, u in { { 1e21, "sx" }, { 1e18, "qn" }, { 1e15, "qd" }, { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return (("%.1f"):format(n / u[1]):gsub("%.0$", "")) .. u[2] end
	end
	return tostring(math.floor(n))
end
local function label(parent, text, size, pos, color, z)
	local l = Instance.new("TextLabel") l.BackgroundTransparency = 1 l.Size = size l.Position = pos l.Text = text l.TextScaled = true
	l.Font = Enum.Font.FredokaOne l.TextColor3 = color or Color3.new(1, 1, 1) l.ZIndex = z or 3 l.Parent = parent
	local st = Instance.new("UIStroke") st.Thickness = 2.5 st.Color = BLACK st.Parent = l
	return l
end
local function button(parent, text, size, pos, color, z)
	local b = Instance.new("TextButton") b.Size = size b.Position = pos b.BackgroundColor3 = color b.Text = "" b.ZIndex = z or 10 b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 12)
	local st = Instance.new("UIStroke") st.Thickness = 3 st.Color = BLACK st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border st.Parent = b
	label(b, text, UDim2.fromScale(0.86, 0.8), UDim2.fromScale(0.07, 0.1), Color3.new(1, 1, 1), (z or 10) + 1).Name = "Caption"
	return b
end
-- flat-top hexagon from 3 rotated rectangles; returns the pieces so they can be recolored
local function hex(parent, w, color, z)
	local s, parts = w / 2, {}
	for _, rot in { 0, 60, -60 } do
		local f = Instance.new("Frame") f.AnchorPoint = Vector2.new(0.5, 0.5) f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromOffset(s, SQ3 * s) f.Rotation = rot f.BackgroundColor3 = color f.BorderSizePixel = 0 f.ZIndex = z f.Parent = parent
		table.insert(parts, f)
	end
	return parts
end
local function decode(attr, fallback)
	local ok, v = pcall(Http.JSONDecode, Http, state:GetAttribute(attr) or "")
	return ok and v or fallback
end

local gui = Instance.new("ScreenGui") gui.Name = "SkillTreeUI" gui.ResetOnSpawn = false gui.Enabled = false gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")
local dim = Instance.new("Frame") dim.Size = UDim2.fromScale(1, 1) dim.BackgroundColor3 = BLACK dim.BackgroundTransparency = 0.35 dim.Parent = gui

local W = math.clamp(workspace.CurrentCamera.ViewportSize.Y * 0.14, 80, 130)
local H = W * SQ3 / 2
local scroll = Instance.new("ScrollingFrame") scroll.Size = UDim2.fromScale(1, 1) scroll.BackgroundTransparency = 1 scroll.BorderSizePixel = 0
scroll.ScrollingDirection = Enum.ScrollingDirection.XY scroll.ScrollBarThickness = 6 scroll.ElasticBehavior = Enum.ElasticBehavior.Never scroll.Parent = gui

local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
local function center(node) return node.q * W * 0.75 * 1.04, (node.r + node.q / 2) * H * 1.04 end
for _, node in Tree.Nodes do
	local x, y = center(node)
	minX, minY, maxX, maxY = math.min(minX, x), math.min(minY, y), math.max(maxX, x), math.max(maxY, y)
end

local cashL = label(gui, "", UDim2.new(0.5, 0, 0, 40), UDim2.new(0.25, 0, 0, 10), Color3.fromRGB(120, 255, 120), 10)
local info = label(gui, "", UDim2.new(0.84, 0, 0, 28), UDim2.new(0.08, 0, 0, 54), Color3.fromRGB(230, 230, 240), 10)
local search = Instance.new("TextBox") search.Size = UDim2.fromOffset(200, 36) search.Position = UDim2.new(0, 12, 0, 12) search.ZIndex = 10
search.PlaceholderText = "Search nodes..." search.Text = "" search.ClearTextOnFocus = false search.Font = Enum.Font.FredokaOne search.TextScaled = true
search.BackgroundColor3 = Color3.fromRGB(50, 56, 70) search.TextColor3 = Color3.new(1, 1, 1) search.Parent = gui
Instance.new("UICorner", search)

-- prerequisite lines (drawn under the hexes)
local lines = {}
local function lineBetween(a, b)
	local f = Instance.new("Frame") f.AnchorPoint = Vector2.new(0.5, 0.5) f.BorderSizePixel = 0 f.ZIndex = 0 f.Parent = scroll
	f.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
	table.insert(lines, { frame = f, a = a, b = b })
end
for _, node in Tree.Nodes do
	for _, req in node.requires or {} do lineBetween(Tree.ById[req], node) end
end

local widgets, selected = {}, nil
local refresh
for _, node in Tree.Nodes do
	local x, y = center(node)
	local branch = Tree.BranchById[node.branch]
	local b = Instance.new("TextButton") b.Text = "" b.AutoButtonColor = false b.BackgroundTransparency = 1 b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Size = UDim2.fromOffset(W, H) b.Parent = scroll
	local rim = hex(b, W, branch.color, 1)
	local w = {
		node = node, button = b, rim = rim,
		inner = hex(b, W * 0.84, LOCKED, 2),
		icon = label(b, node.icon, UDim2.fromScale(0.36, 0.3), UDim2.fromScale(0.32, 0.06)),
		name = label(b, node.name, UDim2.fromScale(0.84, 0.2), UDim2.fromScale(0.08, 0.38)),
		rank = label(b, "", UDim2.fromScale(0.5, 0.16), UDim2.fromScale(0.25, 0.58)),
		price = label(b, "", UDim2.fromScale(0.7, 0.16), UDim2.fromScale(0.15, 0.75)),
		x = x - minX, y = y - minY,
	}
	widgets[node.id] = w
	b.MouseEnter:Connect(function()
		if selected == nil then info.Text = node.name .. ": " .. Tree.describe(node) end
	end)
	b.MouseButton1Click:Connect(function()
		local owned = decode("Skills", { start = 1 })
		local why = Tree.blocked(node, owned, state:GetAttribute("Rebirths") or 0)
		local rank = owned[node.id] or 0
		if selected ~= node.id or why then
			selected = node.id
			info.Text = node.name .. ": " .. Tree.describe(node, rank)
				.. (why and ("  •  " .. why) or ("  •  $" .. fmt(Tree.cost(node, rank)) .. "  •  tap again to buy"))
			refresh()
			return
		end
		local ok, msg = BuySkill:InvokeServer(node.id)
		info.Text = ok and ("Unlocked " .. node.name .. " rank " .. rank + 1 .. "!  " .. Tree.describe(node)) or msg
	end)
end

refresh = function()
	local owned = decode("Skills", { start = 1 })
	local cash, reb = state:GetAttribute("Cash") or 0, state:GetAttribute("Rebirths") or 0
	cashL.Text = "💵 $" .. fmt(cash) .. "   (+" .. fmt(state:GetAttribute("CashPerSec") or 0) .. "/s)"
	local q = search.Text:lower()
	for id, w in widgets do
		local node = w.node
		local rank = owned[id] or 0
		local why = Tree.blocked(node, owned, reb)
		local branch = Tree.BranchById[node.branch]
		local col = rank >= node.max and branch.color or rank > 0 and branch.color:Lerp(BLACK, 0.45) or (why and LOCKED or AVAIL)
		for _, f in w.inner do f.BackgroundColor3 = col end
		local hit = q ~= "" and node.name:lower():find(q, 1, true)
		for _, f in w.rim do f.BackgroundColor3 = (hit or id == selected) and Color3.new(1, 1, 1) or branch.color end
		w.rank.Text = node.max > 1 and (rank .. "/" .. node.max) or (rank > 0 and "✔" or "")
		local cost = rank < node.max and Tree.cost(node, rank) or nil
		w.price.Text = cost and ("$" .. fmt(cost)) or ""
		w.price.TextColor3 = cost and cash >= cost and not why and Color3.fromRGB(90, 255, 90) or Color3.fromRGB(255, 90, 90)
		w.icon.TextTransparency = why and rank == 0 and 0.5 or 0
	end
	for _, l in lines do
		local on = (owned[l.a.id] or 0) > 0
		l.frame.BackgroundColor3 = on and Tree.BranchById[l.b.branch].color or Color3.fromRGB(70, 70, 80)
	end
end
state:GetAttributeChangedSignal("Skills"):Connect(function() if gui.Enabled then refresh() end end)
state:GetAttributeChangedSignal("Cash"):Connect(function() if gui.Enabled then refresh() end end)
search:GetPropertyChangedSignal("Text"):Connect(function() if gui.Enabled then refresh() end end)
search.FocusLost:Connect(function()
	local q = search.Text:lower()
	if q == "" then return end
	for _, w in widgets do
		if w.node.name:lower():find(q, 1, true) then
			scroll.CanvasPosition = Vector2.new(w.button.Position.X.Offset, w.button.Position.Y.Offset) - workspace.CurrentCamera.ViewportSize / 2
			return
		end
	end
end)

-- ASCENSION panel (AP)
local asc = Instance.new("Frame") asc.AnchorPoint = Vector2.new(0.5, 0.5) asc.Position = UDim2.fromScale(0.5, 0.52) asc.Size = UDim2.fromScale(0.7, 0.7)
asc.BackgroundColor3 = Color3.fromRGB(40, 28, 64) asc.Visible = false asc.ZIndex = 20 asc.Parent = gui
Instance.new("UICorner", asc).CornerRadius = UDim.new(0, 18)
Instance.new("UIStroke", asc).Thickness = 4
local apL = label(asc, "", UDim2.new(0.9, 0, 0, 36), UDim2.new(0.05, 0, 0, 10), Color3.fromRGB(230, 170, 255), 21)
local alist = Instance.new("ScrollingFrame") alist.Position = UDim2.new(0.03, 0, 0, 56) alist.Size = UDim2.new(0.94, 0, 1, -66) alist.BackgroundTransparency = 1
alist.BorderSizePixel = 0 alist.ZIndex = 21 alist.CanvasSize = UDim2.new() alist.AutomaticCanvasSize = Enum.AutomaticSize.Y alist.Parent = asc
local al = Instance.new("UIListLayout") al.Padding = UDim.new(0, 8) al.SortOrder = Enum.SortOrder.LayoutOrder al.Parent = alist
local ascRows = {}
for i, node in Tree.Ascension do
	local row = Instance.new("Frame") row.Size = UDim2.new(1, -10, 0, 64) row.BackgroundColor3 = Color3.fromRGB(60, 44, 90) row.LayoutOrder = i row.ZIndex = 21 row.Parent = alist
	Instance.new("UICorner", row)
	local t = label(row, node.icon .. " " .. node.name, UDim2.new(0.6, 0, 0, 30), UDim2.fromOffset(10, 2), Color3.new(1, 1, 1), 22)
	t.TextXAlignment = Enum.TextXAlignment.Left
	local d = label(row, "", UDim2.new(0.6, 0, 0, 24), UDim2.fromOffset(10, 34), Color3.fromRGB(210, 200, 230), 22)
	d.TextXAlignment = Enum.TextXAlignment.Left
	local b = button(row, "", UDim2.new(0.3, 0, 0, 48), UDim2.new(0.68, 0, 0, 8), Color3.fromRGB(150, 70, 230), 22)
	ascRows[node.id] = { desc = d, button = b }
	b.MouseButton1Click:Connect(function()
		local ok, msg = BuySkill:InvokeServer(node.id, "ascension")
		apL.Text = ok and ("Ascended: " .. node.name) or msg
	end)
end
local function refreshAsc()
	local owned, ap = decode("Ascension", {}), state:GetAttribute("AscensionPoints") or 0
	apL.Text = "✨ Ascension Points: " .. ap .. "   (earned by rebirthing; never reset)"
	for _, node in Tree.Ascension do
		local r, rank = ascRows[node.id], owned[node.id] or 0
		r.desc.Text = Tree.describe(node, rank)
		local maxed = rank >= node.max
		local cost = Tree.cost(node, rank)
		r.button.Caption.Text = maxed and "Maxed" or (cost .. " AP")
		r.button.BackgroundColor3 = not maxed and ap >= cost and Color3.fromRGB(150, 70, 230) or Color3.fromRGB(80, 70, 95)
	end
end
state:GetAttributeChangedSignal("Ascension"):Connect(refreshAsc)
state:GetAttributeChangedSignal("AscensionPoints"):Connect(refreshAsc)

-- bottom bar: Ascension toggle, Respec (two taps), Close
local ascB = button(gui, "Ascension Tree", UDim2.fromOffset(200, 60), UDim2.new(0.5, -330, 1, -84), Color3.fromRGB(150, 70, 230))
ascB.MouseButton1Click:Connect(function() asc.Visible = not asc.Visible refreshAsc() end)
local respec = button(gui, "Respec", UDim2.fromOffset(200, 60), UDim2.new(0.5, -100, 1, -84), Color3.fromRGB(200, 130, 40))
local armed = false
respec.MouseButton1Click:Connect(function()
	if not armed then
		armed = true
		respec.Caption.Text = "Confirm respec?"
		info.Text = ("Respec refunds 75%% of the $%s you spent on the Evolution Tree. Tap again to confirm."):format(fmt(state:GetAttribute("SkillSpent") or 0))
		task.delay(4, function() armed = false respec.Caption.Text = "Respec" end)
		return
	end
	armed = false
	respec.Caption.Text = "Respec"
	local ok, res = BuySkill:InvokeServer("respec")
	info.Text = ok and ("Tree reset. Refunded $" .. fmt(res)) or res
end)
local close = button(gui, "Close", UDim2.fromOffset(200, 60), UDim2.new(0.5, 130, 1, -84), Color3.fromRGB(230, 40, 40))
close.MouseButton1Click:Connect(function() gui.Enabled = false end)

-- pad so a small tree still sits centered on any screen size
local function layout()
	local view = workspace.CurrentCamera.ViewportSize -- gui is full-screen (IgnoreGuiInset); AbsoluteSize lags a frame after enabling
	local padX, padY = math.max(W * 2.5, (view.X - (maxX - minX)) / 2), math.max(H * 2.5, (view.Y - (maxY - minY)) / 2)
	scroll.CanvasSize = UDim2.fromOffset(maxX - minX + padX * 2, maxY - minY + padY * 2)
	for _, w in widgets do w.button.Position = UDim2.fromOffset(w.x + padX, w.y + padY) end
	for _, l in lines do
		local a, b = widgets[l.a.id], widgets[l.b.id]
		local ax, ay, bx, by = a.x + padX, a.y + padY, b.x + padX, b.y + padY
		l.frame.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
		l.frame.Size = UDim2.fromOffset(math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2), 6)
		l.frame.Rotation = math.deg(math.atan2(by - ay, bx - ax))
	end
end

local function open()
	selected = nil
	refresh()
	gui.Enabled = true
	layout()
	local start = widgets.start.button
	task.defer(function()
		scroll.CanvasPosition = Vector2.new(start.Position.X.Offset, start.Position.Y.Offset) - workspace.CurrentCamera.ViewportSize / 2
	end)
	info.Text = "Six branches grow from Start. Tap a node to inspect it, tap again to buy."
end
PPS.PromptTriggered:Connect(function(prompt) if prompt:FindFirstAncestor("UpgradeTree") then open() end end)
local hudGui = Instance.new("ScreenGui") hudGui.Name = "TreeHUD" hudGui.ResetOnSpawn = false hudGui.Parent = gui.Parent
local hud = button(hudGui, "TREE", UDim2.fromOffset(120, 50), UDim2.new(0, 12, 0.5, 182), Color3.fromRGB(40, 150, 110), 1)
hud.MouseButton1Click:Connect(function() if gui.Enabled then gui.Enabled = false else open() end end)
