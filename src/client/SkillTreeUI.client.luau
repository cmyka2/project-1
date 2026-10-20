-- Hex upgrade tree: thick black hex outlines, blue = owned, dark = buyable, "?" = locked.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PPS = game:GetService("ProximityPromptService")
local Http = game:GetService("HttpService")
local Tree = require(RS:WaitForChild("Monster"):WaitForChild("SkillTree"))
local BuySkill = RS.Monster:WaitForChild("BuySkill")
local player = Players.LocalPlayer

local BLACK = Color3.new(0, 0, 0)
local OWNED, AVAIL, HIDDEN = Color3.fromRGB(0, 170, 255), Color3.fromRGB(48, 48, 56), Color3.fromRGB(36, 36, 42)
local SQ3 = math.sqrt(3)

local function fmt(n)
	for _, u in { { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
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

local gui = Instance.new("ScreenGui") gui.Name = "SkillTreeUI" gui.ResetOnSpawn = false gui.Enabled = false gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")
local dim = Instance.new("Frame") dim.Size = UDim2.fromScale(1, 1) dim.BackgroundColor3 = BLACK dim.BackgroundTransparency = 0.4 dim.Parent = gui

local W = math.clamp(workspace.CurrentCamera.ViewportSize.Y * 0.19, 95, 170)
local H = W * SQ3 / 2
local scroll = Instance.new("ScrollingFrame") scroll.Size = UDim2.fromScale(1, 1) scroll.BackgroundTransparency = 1 scroll.BorderSizePixel = 0
scroll.ScrollingDirection = Enum.ScrollingDirection.XY scroll.ScrollBarThickness = 6 scroll.ElasticBehavior = Enum.ElasticBehavior.Never scroll.Parent = gui

local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
local function center(node) return node.q * W * 0.75 * 1.02, (node.r + node.q / 2) * H * 1.02 end
for _, node in Tree.Nodes do
	local x, y = center(node)
	minX, minY, maxX, maxY = math.min(minX, x), math.min(minY, y), math.max(maxX, x), math.max(maxY, y)
end

local info = label(gui, "", UDim2.new(0.8, 0, 0, 30), UDim2.new(0.1, 0, 0, 58), Color3.fromRGB(230, 230, 240), 10)
local cashL = label(gui, "", UDim2.new(0.6, 0, 0, 44), UDim2.new(0.2, 0, 0, 12), Color3.fromRGB(120, 255, 120), 10)

local widgets = {}
for _, node in Tree.Nodes do
	local x, y = center(node)
	local b = Instance.new("TextButton") b.Text = "" b.AutoButtonColor = false b.BackgroundTransparency = 1 b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Size = UDim2.fromOffset(W, H) b.Parent = scroll
	hex(b, W, BLACK, 1)
	local w = {
		node = node, button = b,
		inner = hex(b, W * 0.86, HIDDEN, 2),
		icon = label(b, node.icon, UDim2.fromScale(0.44, 0.4), UDim2.fromScale(0.28, 0.08)),
		name = label(b, node.name, UDim2.fromScale(0.84, 0.2), UDim2.fromScale(0.08, 0.48)),
		price = label(b, "💵 " .. fmt(node.cost), UDim2.fromScale(0.6, 0.18), UDim2.fromScale(0.2, 0.7)),
		q = label(b, "?", UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.25, 0.15)),
		state = "hidden", x = x - minX, y = y - minY,
	}
	widgets[node.id] = w
	b.MouseEnter:Connect(function()
		if w.state == "hidden" then info.Text = "???  Unlock the upgrade next to it first" return end
		info.Text = node.name .. ": " .. Tree.describe(node) .. (w.state == "avail" and ("  •  $" .. fmt(node.cost)) or "")
	end)
	b.MouseButton1Click:Connect(function()
		if w.state ~= "avail" then return end
		local ok, msg = BuySkill:InvokeServer(node.id)
		info.Text = ok and ("Unlocked " .. node.name .. "!  " .. Tree.describe(node)) or msg
	end)
end

local function decode(attr, fallback)
	local ok, v = pcall(Http.JSONDecode, Http, player:GetAttribute(attr) or "")
	return ok and v or fallback
end
local function refresh()
	local skills = decode("Skills", { start = true })
	local cash = player:GetAttribute("Cash") or 0
	cashL.Text = "💵 $" .. fmt(cash) .. "   (+" .. fmt(player:GetAttribute("CashPerSec") or 0) .. "/s)"
	for id, w in widgets do
		local node = w.node
		w.state = skills[id] and "owned" or ((not node.requires or skills[node.requires]) and "avail" or "hidden")
		local col = w.state == "owned" and OWNED or w.state == "avail" and AVAIL or HIDDEN
		for _, f in w.inner do f.BackgroundColor3 = col end
		w.icon.Visible, w.name.Visible = w.state ~= "hidden", w.state ~= "hidden"
		w.q.Visible = w.state == "hidden"
		w.price.Visible = w.state == "avail"
		w.price.TextColor3 = cash >= node.cost and Color3.fromRGB(90, 255, 90) or Color3.fromRGB(255, 80, 80)
	end
end
player:GetAttributeChangedSignal("Skills"):Connect(refresh)
player:GetAttributeChangedSignal("Cash"):Connect(function() if gui.Enabled then refresh() end end)

local close = Instance.new("TextButton") close.AnchorPoint = Vector2.new(0.5, 1) close.Position = UDim2.new(0.5, 0, 1, -24) close.Size = UDim2.fromOffset(240, 66)
close.BackgroundColor3 = Color3.fromRGB(230, 40, 40) close.Text = "" close.ZIndex = 10 close.Parent = gui
local cc = Instance.new("UICorner") cc.CornerRadius = UDim.new(0, 12) cc.Parent = close
local cs = Instance.new("UIStroke") cs.Thickness = 4 cs.Color = BLACK cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border cs.Parent = close
label(close, "Close", UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.1, 0.1), Color3.new(1, 1, 1), 11)
close.MouseButton1Click:Connect(function() gui.Enabled = false end)

-- pad so a small tree still sits centered on any screen size
local function layout()
	local view = workspace.CurrentCamera.ViewportSize -- gui is full-screen (IgnoreGuiInset); AbsoluteSize lags a frame after enabling
	local padX, padY = math.max(W * 2.5, (view.X - (maxX - minX)) / 2), math.max(H * 2.5, (view.Y - (maxY - minY)) / 2)
	scroll.CanvasSize = UDim2.fromOffset(maxX - minX + padX * 2, maxY - minY + padY * 2)
	for _, w in widgets do w.button.Position = UDim2.fromOffset(w.x + padX, w.y + padY) end
end

local function open()
	refresh()
	gui.Enabled = true
	layout()
	local start = widgets.start.button
	task.defer(function()
		scroll.CanvasPosition = Vector2.new(start.Position.X.Offset, start.Position.Y.Offset) - workspace.CurrentCamera.ViewportSize / 2
	end)
	info.Text = "Tap a dark hex to buy it"
end
PPS.PromptTriggered:Connect(function(prompt) if prompt:FindFirstAncestor("UpgradeTree") then open() end end)
