-- Chest Shop panel (+ crafting recipes) and GEAR bag (equip gear onto one of your monsters).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PPS = game:GetService("ProximityPromptService")
local Http = game:GetService("HttpService")
local Gear = require(RS:WaitForChild("Monster"):WaitForChild("GearConfig"))
local Dice = require(RS.Monster:WaitForChild("DiceConfig"))
local Config = require(RS.Monster:WaitForChild("MonsterConfig"))
local ChestAction = RS.Monster:WaitForChild("ChestAction")
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server

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
local function decode(attr)
	local ok, v = pcall(Http.JSONDecode, Http, state:GetAttribute(attr) or "")
	return ok and v or {}
end
local function pct(x) return math.floor(x * 100 + 0.5) .. "%" end
local function nameOf(m)
	local def = Config.ById[m.id]
	return (m.v ~= "Normal" and m.v .. " " or "") .. (def and def.name or "?")
end
local function panelFrame(gui, titleText, color)
	local panel = Instance.new("Frame") panel.AnchorPoint = Vector2.new(0.5, 0.5) panel.Position = UDim2.fromScale(0.5, 0.5) panel.Size = UDim2.fromScale(0.8, 0.82)
	panel.BackgroundColor3 = color panel.Visible = false panel.Parent = gui
	local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(820, 640) lim.Parent = panel
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	local ps = Instance.new("UIStroke", panel) ps.Thickness = 4
	text("TextLabel", panel, titleText, UDim2.fromScale(0.6, 0.09), UDim2.fromScale(0.03, 0.02)).TextXAlignment = Enum.TextXAlignment.Left
	local msg = text("TextLabel", panel, "", UDim2.fromScale(0.94, 0.055), UDim2.fromScale(0.03, 0.115), Color3.fromRGB(255, 220, 120))
	local close = text("TextButton", panel, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 8))
	close.BackgroundTransparency = 0 close.BackgroundColor3 = Color3.fromRGB(220, 50, 50) Instance.new("UICorner", close)
	close.MouseButton1Click:Connect(function() panel.Visible = false end)
	local list = Instance.new("ScrollingFrame") list.Position = UDim2.fromScale(0.03, 0.18) list.Size = UDim2.fromScale(0.94, 0.79)
	list.BackgroundTransparency = 1 list.BorderSizePixel = 0 list.CanvasSize = UDim2.new() list.AutomaticCanvasSize = Enum.AutomaticSize.Y list.ScrollBarThickness = 8 list.Parent = panel
	return panel, msg, list
end
local function btn(parent, size, pos, color)
	local b = text("TextButton", parent, "", size, pos)
	b.BackgroundTransparency = 0 b.BackgroundColor3 = color
	Instance.new("UICorner", b)
	local st = Instance.new("UIStroke", b) st.Thickness = 3 st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return b
end

local gui = Instance.new("ScreenGui") gui.Name = "ChestUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")

-- CHEST SHOP
local shop, shopMsg, shopList = panelFrame(gui, "CHEST SHOP", Color3.fromRGB(60, 40, 25))
local sl = Instance.new("UIListLayout") sl.Padding = UDim.new(0, 8) sl.SortOrder = Enum.SortOrder.LayoutOrder sl.Parent = shopList
local chestRows = {}
for i, c in Gear.Chests do
	local row = Instance.new("Frame") row.Size = UDim2.new(1, -12, 0, 78) row.BackgroundColor3 = Color3.fromRGB(85, 60, 40) row.LayoutOrder = i row.Parent = shopList
	Instance.new("UICorner", row)
	local icon = text("TextLabel", row, "🧰", UDim2.fromOffset(56, 56), UDim2.fromOffset(10, 11))
	icon.BackgroundTransparency = 0 icon.BackgroundColor3 = c.color Instance.new("UICorner", icon) Instance.new("UIStroke", icon).Thickness = 3
	text("TextLabel", row, c.name, UDim2.new(0.55, -80, 0, 30), UDim2.fromOffset(76, 6), c.color).TextXAlignment = Enum.TextXAlignment.Left
	local o = text("TextLabel", row, "", UDim2.new(0.6, -80, 0, 34), UDim2.fromOffset(76, 38), Color3.fromRGB(230, 220, 200))
	o.TextXAlignment = Enum.TextXAlignment.Left o.TextWrapped = true
	local b = btn(row, UDim2.new(0.21, 0, 0, 52), UDim2.new(0.6, 0, 0, 13), Color3.fromRGB(50, 180, 70))
	local b10 = btn(row, UDim2.new(0.15, 0, 0, 52), UDim2.new(0.83, 0, 0, 13), Color3.fromRGB(50, 150, 90))
	b10.Text = "x10"
	chestRows[c.id] = { button = b, chest = c, odds = o }
	local function open(n)
		local ok, res = ChestAction:InvokeServer("open", c.id, n)
		if ok then
			local best = res[1]
			for _, g in res do if Gear.RarityIndex[g.r] > Gear.RarityIndex[best.r] then best = g end end
			shopMsg.TextColor3 = Gear.RarityById[best.r].color
			shopMsg.Text = (#res > 1 and ("Opened " .. #res .. "! Best: ") or "You got: ") .. Gear.TypeById[best.t].icon .. " " .. Gear.name(best)
				.. "  (+" .. pct(Gear.power(best)) .. ")" .. (best.sec and ("  " .. Gear.secondaryText(best)) or "")
		else
			shopMsg.TextColor3 = Color3.fromRGB(255, 140, 140)
			shopMsg.Text = res
		end
	end
	b.MouseButton1Click:Connect(function() open(1) end)
	b10.MouseButton1Click:Connect(function() open(10) end)
end
-- CRAFTING (same panel, below the chests)
local craftRows = {}
for i, rec in Gear.Recipes do
	local row = Instance.new("Frame") row.Size = UDim2.new(1, -12, 0, 78) row.BackgroundColor3 = Color3.fromRGB(55, 70, 50) row.LayoutOrder = 100 + i row.Parent = shopList
	Instance.new("UICorner", row)
	local r = Gear.RarityById[rec.rarity]
	text("TextLabel", row, "⚒️ " .. rec.name .. (rec.gtype == "relic" and " 🔮" or ""), UDim2.new(0.6, -12, 0, 30), UDim2.fromOffset(12, 6), r.color).TextXAlignment = Enum.TextXAlignment.Left
	local need = text("TextLabel", row, "", UDim2.new(0.62, -12, 0, 30), UDim2.fromOffset(12, 40), Color3.fromRGB(230, 220, 200))
	need.TextXAlignment = Enum.TextXAlignment.Left
	local b = btn(row, UDim2.new(0.3, 0, 0, 52), UDim2.new(0.68, 0, 0, 13), Color3.fromRGB(50, 180, 70))
	craftRows[rec.id] = { button = b, need = need, rec = rec }
	b.MouseButton1Click:Connect(function()
		local ok, res = ChestAction:InvokeServer("craft", rec.id)
		shopMsg.TextColor3 = ok and r.color or Color3.fromRGB(255, 140, 140)
		shopMsg.Text = ok and ("Crafted: " .. Gear.TypeById[res.t].icon .. " " .. Gear.name(res)) or res
	end)
end
local function refreshShop()
	local owned, cash = decode("Dice"), state:GetAttribute("Cash") or 0
	local mats = decode("Materials")
	for _, row in craftRows do
		local parts, can = {}, cash >= row.rec.cash
		for id, n in row.rec.mats do
			local have = mats[id] or 0
			can = can and have >= n
			table.insert(parts, Gear.MaterialById[id].icon .. " " .. have .. "/" .. n)
		end
		row.need.Text = table.concat(parts, "  ") .. "  •  $" .. short(row.rec.cash)
		row.button.Text = "Craft"
		row.button.BackgroundColor3 = can and Color3.fromRGB(50, 180, 70) or Color3.fromRGB(150, 60, 60)
	end
	-- prices and odds the server will actually use (Treasure Research discount, Better Chest Finder luck)
	local discount, luck = state:GetAttribute("ChestDiscount") or 0, state:GetAttribute("ChestLuck") or 0
	for _, row in chestRows do
		local c, b = row.chest, row.button
		local price = math.floor(c.cost * (1 - discount))
		local parts, odds = {}, Gear.odds(c, luck)
		for _, r in Gear.Rarities do if odds[r.id] then table.insert(parts, r.id .. " " .. pct(odds[r.id])) end end
		row.odds.Text = table.concat(parts, " • ") .. (c.relics and "  • can drop 🔮 relics" or "")
		if not owned[c.die] then
			b.Text, b.BackgroundColor3 = "🔒 " .. Dice.ById[c.die].name, Color3.fromRGB(60, 60, 70)
		else
			b.Text = "Open $" .. short(price)
			b.BackgroundColor3 = cash >= price and Color3.fromRGB(50, 180, 70) or Color3.fromRGB(150, 60, 60)
		end
	end
end
state:GetAttributeChangedSignal("Cash"):Connect(function() if shop.Visible then refreshShop() end end)
state:GetAttributeChangedSignal("Dice"):Connect(refreshShop)
state:GetAttributeChangedSignal("ChestLuck"):Connect(function() if shop.Visible then refreshShop() end end)
state:GetAttributeChangedSignal("Materials"):Connect(function() if shop.Visible then refreshShop() end end)

-- GEAR BAG
local bag, bagMsg, bagList = panelFrame(gui, "GEAR", Color3.fromRGB(30, 45, 60))
bagList.Size = UDim2.fromScale(0.94, 0.6)
local grid = Instance.new("UIGridLayout") grid.CellSize = UDim2.fromOffset(150, 84) grid.CellPadding = UDim2.fromOffset(8, 8)
grid.SortOrder = Enum.SortOrder.LayoutOrder grid.HorizontalAlignment = Enum.HorizontalAlignment.Center grid.Parent = bagList
local slotBar = Instance.new("Frame") slotBar.Position = UDim2.fromScale(0.03, 0.8) slotBar.Size = UDim2.fromScale(0.94, 0.17) slotBar.BackgroundTransparency = 1 slotBar.Parent = bag
local sbl = Instance.new("UIListLayout") sbl.FillDirection = Enum.FillDirection.Horizontal sbl.Padding = UDim.new(0, 6) sbl.HorizontalAlignment = Enum.HorizontalAlignment.Center
sbl.VerticalAlignment = Enum.VerticalAlignment.Center sbl.Parent = slotBar
local selected

local function refreshBag()
	for _, c in bagList:GetChildren() do if c:IsA("GuiButton") then c:Destroy() end end
	for _, c in slotBar:GetChildren() do if c:IsA("GuiButton") then c:Destroy() end end
	local gear, placed, mons, team = decode("Gear"), decode("Placed"), decode("Monsters"), decode("Team")
	if selected and not gear[selected] then selected = nil end
	local items = {}
	for uid, g in gear do table.insert(items, { uid = uid, g = g }) end
	table.sort(items, function(a, b) return Gear.power(a.g) > Gear.power(b.g) end)
	bagMsg.TextColor3 = Color3.fromRGB(220, 220, 230)
	bagMsg.Text = #items == 0 and "No gear yet. Open chests at the Chest Shop!" or (selected and "Pick a monster to equip it on" or "Tap gear, then pick a monster")
	for i, it in items do
		local r = Gear.RarityById[it.g.r]
		local b = btn(bagList, UDim2.new(), UDim2.new(), Color3.fromRGB(45, 60, 80))
		b.LayoutOrder = i
		b:FindFirstChildOfClass("UIStroke").Color = it.uid == selected and Color3.new(1, 1, 1) or r.color
		b:FindFirstChildOfClass("UIStroke").Thickness = it.uid == selected and 5 or 3
		text("TextLabel", b, Gear.TypeById[it.g.t].icon .. " " .. Gear.name(it.g), UDim2.new(1, -8, 0.4, 0), UDim2.fromOffset(4, 4), r.color)
		text("TextLabel", b, "+" .. pct(Gear.power(it.g)) .. "  " .. Gear.secondaryText(it.g), UDim2.new(1, -8, 0.26, 0), UDim2.new(0, 4, 0.44, 0), Color3.fromRGB(120, 255, 120))
		local wearer = it.g.m and mons[it.g.m]
		text("TextLabel", b, wearer and ("On " .. nameOf(wearer)) or "In bag", UDim2.new(1, -8, 0.22, 0), UDim2.new(0, 4, 0.72, 0), Color3.fromRGB(190, 190, 200))
		b.MouseButton1Click:Connect(function() selected = it.uid refreshBag() end)
	end
	if not selected then return end
	-- targets: monsters on your base (by slot), then your battle team
	local targets, seen = {}, {}
	local keys = {}
	for sk in placed do table.insert(keys, tonumber(sk)) end
	table.sort(keys)
	for _, n in keys do
		local iid = placed[tostring(n)]
		if mons[iid] then table.insert(targets, { iid = iid, label = "Slot " .. n }) seen[iid] = true end
	end
	for _, iid in team do
		if mons[iid] and not seen[iid] then table.insert(targets, { iid = iid, label = "Team" }) end
	end
	for _, t in targets do
		local b = btn(slotBar, UDim2.fromOffset(92, 60), UDim2.new(), Color3.fromRGB(40, 130, 230))
		b.Text = t.label .. "\n" .. nameOf(mons[t.iid])
		b.MouseButton1Click:Connect(function()
			local ok, err = ChestAction:InvokeServer("equip", selected, t.iid)
			if not ok then bagMsg.TextColor3 = Color3.fromRGB(255, 140, 140) bagMsg.Text = err end
		end)
	end
	if #targets == 0 then bagMsg.Text = "Place a monster on your base or pick a battle team first" end
	local g = gear[selected]
	if g.t == "relic" and not state:GetAttribute("RelicSlot") then bagMsg.Text = "Relics need the Equipment Slots node (Utility branch)" end
	if (g.lvl or 1) < Gear.MAX_LEVEL then
		local up = btn(slotBar, UDim2.fromOffset(110, 60), UDim2.new(), Color3.fromRGB(60, 160, 70))
		up.Text = "Upgrade\n$" .. short(Gear.upgradeCost(g))
		up.MouseButton1Click:Connect(function()
			local ok, err = ChestAction:InvokeServer("upgrade", selected)
			if not ok then bagMsg.TextColor3 = Color3.fromRGB(255, 140, 140) bagMsg.Text = err end
		end)
	end
	local un = btn(slotBar, UDim2.fromOffset(92, 60), UDim2.new(), Color3.fromRGB(150, 60, 60))
	un.Text = "Unequip"
	un.MouseButton1Click:Connect(function() ChestAction:InvokeServer("unequip", selected) end)
end
state:GetAttributeChangedSignal("Gear"):Connect(function() if bag.Visible then refreshBag() end end)
state:GetAttributeChangedSignal("Placed"):Connect(function() if bag.Visible then refreshBag() end end)
state:GetAttributeChangedSignal("Team"):Connect(function() if bag.Visible then refreshBag() end end)

local hud = btn(gui, UDim2.fromOffset(120, 50), UDim2.new(0, 12, 0.5, 70), Color3.fromRGB(40, 110, 170))
hud.Text = "GEAR"
hud.MouseButton1Click:Connect(function() selected = nil refreshBag() bag.Visible = not bag.Visible end)
PPS.PromptTriggered:Connect(function(prompt)
	if prompt:FindFirstAncestor("ChestShop") then shopMsg.Text = "" refreshShop() shop.Visible = true end
end)
