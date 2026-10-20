-- Index panel (rarity + Normal/Huge/Monstrous pages), HUD button and roll toast.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PPS = game:GetService("ProximityPromptService")
local Http = game:GetService("HttpService")
local Config = require(RS:WaitForChild("Monster"):WaitForChild("MonsterConfig"))
local MonsterModel = require(RS.Monster.MonsterModel)
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server

local FONT = Enum.Font.FredokaOne
local function corner(o, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r or 12) c.Parent = o end
local function stroke(o, color, t) local s = Instance.new("UIStroke") s.Color = color s.Thickness = t or 3 s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border s.Parent = o return s end
local function text(class, parent, str, size, pos, color)
	local l = Instance.new(class) l.Size = size l.Position = pos l.BackgroundTransparency = 1 l.Font = FONT l.TextScaled = true
	l.Text = str l.TextColor3 = color or Color3.new(1, 1, 1) l.TextStrokeTransparency = 0 l.Parent = parent
	return l
end
local function fmt(n)
	if n >= 1e9 then return ("%.1fB"):format(n / 1e9) elseif n >= 1e6 then return ("%.1fM"):format(n / 1e6) elseif n >= 1e4 then return ("%.1fK"):format(n / 1e3) end
	return tostring(math.floor(n + 0.5))
end
-- the player's real odds: effective luck + equipped die's rarity cap and pool (published by the server)
local function oneIn(rarity)
	local p = Config.oddsFor(state:GetAttribute("Luck") or 1, state:GetAttribute("MaxTier"), state:GetAttribute("SelectedDie"))[rarity] or 0
	return p > 0 and "1 in " .. fmt(1 / p) or "better die needed"
end

local gui = Instance.new("ScreenGui") gui.Name = "MonsterUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")

-- HUD button (left-middle, clear of the mobile thumbstick)
local hud = text("TextButton", gui, "INDEX", UDim2.fromOffset(120, 50), UDim2.new(0, 12, 0.5, 0))
hud.AnchorPoint = Vector2.new(0, 0.5) hud.BackgroundTransparency = 0 hud.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
corner(hud) stroke(hud, Color3.new(0, 0, 0), 3)

-- panel
local panel = Instance.new("Frame") panel.AnchorPoint = Vector2.new(0.5, 0.5) panel.Position = UDim2.fromScale(0.5, 0.5) panel.Size = UDim2.fromScale(0.92, 0.86)
panel.BackgroundColor3 = Color3.fromRGB(30, 32, 48) panel.Visible = false panel.Parent = gui
corner(panel, 18) stroke(panel, Color3.new(0, 0, 0), 4)
local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(1000, 700) lim.Parent = panel
text("TextLabel", panel, "MONSTER INDEX", UDim2.fromScale(0.45, 0.08), UDim2.fromScale(0.02, 0.015)).TextXAlignment = Enum.TextXAlignment.Left
local progress = text("TextLabel", panel, "", UDim2.fromScale(0.42, 0.05), UDim2.fromScale(0.5, 0.03), Color3.fromRGB(220, 220, 230))
progress.TextXAlignment = Enum.TextXAlignment.Right
local close = text("TextButton", panel, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 8))
close.BackgroundTransparency = 0 close.BackgroundColor3 = Color3.fromRGB(220, 50, 50) corner(close, 10) stroke(close, Color3.new(0, 0, 0), 2)

local tab = "Normal"
local tabs = {}
for i, v in Config.Variants do
	local b = text("TextButton", panel, v.id:upper(), UDim2.fromScale(0.18, 0.065), UDim2.fromScale(0.02 + (i - 1) * 0.2, 0.11), v.id == "Normal" and Color3.new(1, 1, 1) or v.color)
	b.BackgroundTransparency = 0 b.BackgroundColor3 = Color3.fromRGB(50, 54, 78) corner(b, 10)
	tabs[v.id] = stroke(b, Color3.new(1, 1, 1), 0)
	b.MouseButton1Click:Connect(function() tab = v.id refreshAll() end)
end

local scroll = Instance.new("ScrollingFrame") scroll.Position = UDim2.fromScale(0.02, 0.2) scroll.Size = UDim2.fromScale(0.96, 0.77)
scroll.BackgroundTransparency = 1 scroll.BorderSizePixel = 0 scroll.CanvasSize = UDim2.new() scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y scroll.ScrollBarThickness = 8 scroll.Parent = panel
local grid = Instance.new("UIGridLayout") grid.CellSize = UDim2.fromOffset(140, 185) grid.CellPadding = UDim2.fromOffset(10, 10)
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center grid.SortOrder = Enum.SortOrder.LayoutOrder grid.Parent = scroll
local pad = Instance.new("UIPadding") pad.PaddingTop = UDim.new(0, 6) pad.PaddingBottom = UDim.new(0, 6) pad.Parent = scroll

local cards = {}
for i, def in Config.Monsters do
	local rar = Config.RarityById[def.rarity]
	local card = Instance.new("Frame") card.BackgroundColor3 = Color3.fromRGB(45, 48, 68) card.LayoutOrder = i card.Parent = scroll
	corner(card) stroke(card, rar.color, 3)
	local vp = Instance.new("ViewportFrame") vp.Size = UDim2.new(1, -12, 0.58, 0) vp.Position = UDim2.fromOffset(6, 6)
	vp.BackgroundColor3 = Color3.fromRGB(25, 27, 40) vp.Ambient = Color3.fromRGB(190, 190, 190) vp.LightDirection = Vector3.new(-1, -1, 1) vp.Parent = card
	corner(vp, 10)
	local badge = text("TextLabel", vp, "", UDim2.fromScale(0.7, 0.2), UDim2.fromScale(0.02, 0.02))
	-- hover/tap a discovered card to read its lore and role in the header line
	local hit = Instance.new("TextButton") hit.Size = UDim2.fromScale(1, 1) hit.BackgroundTransparency = 1 hit.Text = "" hit.ZIndex = 3 hit.Parent = card
	local function showLore()
		local c = cards[def.id]
		if c and c.found then progress.Text = def.name .. " (" .. (Config.RoleByElement[def.element] or "") .. "): " .. (Config.Lore[def.id] or "") end
	end
	hit.MouseEnter:Connect(showLore)
	hit.MouseButton1Click:Connect(showLore)
	badge.TextXAlignment = Enum.TextXAlignment.Left badge.ZIndex = 2
	cards[def.id] = {
		vp = vp, badge = badge, state = nil,
		name = text("TextLabel", card, "", UDim2.new(1, -8, 0.13, 0), UDim2.new(0, 4, 0.61, 0)),
		rar = text("TextLabel", card, def.rarity .. " • " .. oneIn(def.rarity), UDim2.new(1, -8, 0.1, 0), UDim2.new(0, 4, 0.75, 0), rar.color),
		count = text("TextLabel", card, "", UDim2.new(1, -8, 0.09, 0), UDim2.new(0, 4, 0.87, 0), Color3.fromRGB(190, 190, 200)),
	}
end

local function render(c, def, found)
	local state = tab .. tostring(found)
	if c.state == state then return end
	c.state = state
	for _, ch in c.vp:GetChildren() do if not ch:IsA("TextLabel") and not ch:IsA("UICorner") then ch:Destroy() end end
	local m = MonsterModel.build(def, tab)
	if not found then
		for _, d in m:GetDescendants() do if d:IsA("BasePart") then d.Color = Color3.new(0, 0, 0) d.Material = Enum.Material.SmoothPlastic end end
	end
	m:PivotTo(CFrame.new())
	m.Parent = c.vp
	local cf, size = m:GetBoundingBox()
	local dist = math.max(size.X, size.Y, size.Z) * 1.5
	local cam = Instance.new("Camera") cam.FieldOfView = 40
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist * 0.55, dist * 0.3, -dist), cf.Position)
	cam.Parent = c.vp c.vp.CurrentCamera = cam
	local v = Config.VariantById[tab]
	c.badge.Text = tab ~= "Normal" and tab:upper() or "" c.badge.TextColor3 = v.color
end

function refreshAll()
	local ok, data = pcall(Http.JSONDecode, Http, state:GetAttribute("Index") or "")
	if not ok then data = { D = {}, O = {}, R = 0 } end
	local found = 0
	for _, def in Config.Monsters do
		local c = cards[def.id]
		local disc = data.D[def.id]
		local f = disc ~= nil and disc[tab] == true
		if f then found += 1 end
		c.found = disc ~= nil
		render(c, def, f)
		c.name.Text = f and def.name or "???"
		c.rar.Text = def.rarity .. " • " .. oneIn(def.rarity)
		c.count.Text = f and ("Owned x" .. (data.O[def.id .. "|" .. tab] or 0)) or "Not found"
	end
	for id, st in tabs do st.Thickness = id == tab and 3 or 0 end
	progress.Text = ("%s: %d/%d found  •  %d rolls"):format(tab, found, #Config.Monsters, data.R or 0)
end

local function setOpen(open) panel.Visible = open if open then refreshAll() end end
hud.MouseButton1Click:Connect(function() setOpen(not panel.Visible) end)
close.MouseButton1Click:Connect(function() setOpen(false) end)
PPS.PromptTriggered:Connect(function(prompt) if prompt:FindFirstAncestor("Index") then setOpen(true) end end)
state:GetAttributeChangedSignal("Index"):Connect(function() if panel.Visible then refreshAll() end end)
state:GetAttributeChangedSignal("Luck"):Connect(function() if panel.Visible then refreshAll() end end)
state:GetAttributeChangedSignal("SelectedDie"):Connect(function() if panel.Visible then refreshAll() end end)

-- roll toast
local toast = text("TextLabel", gui, "", UDim2.fromScale(0.6, 0.08), UDim2.fromScale(0.5, 0.1))
toast.AnchorPoint = Vector2.new(0.5, 0) toast.Visible = false
local tlim = Instance.new("UISizeConstraint") tlim.MaxSize = Vector2.new(640, 70) tlim.Parent = toast
local shown = 0
state:GetAttributeChangedSignal("LastRoll"):Connect(function()
	local ok, r = pcall(Http.JSONDecode, Http, state:GetAttribute("LastRoll"))
	local def = ok and Config.ById[r.id]
	if not def then return end
	local v = Config.VariantById[r.v]
	toast.Text = (r.new and "NEW! " or "") .. (r.v ~= "Normal" and r.v:upper() .. " " or "") .. def.name .. "  (" .. def.rarity .. ", " .. oneIn(def.rarity) .. ")"
	toast.TextColor3 = r.v ~= "Normal" and v.color or Config.RarityById[def.rarity].color
	toast.Visible = true
	shown += 1
	local mine = shown
	task.delay(2.5, function() if shown == mine then toast.Visible = false end end)
end)
