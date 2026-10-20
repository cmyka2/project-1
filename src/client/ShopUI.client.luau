-- Robux shop (🍀 SHOP button): gamepasses, luck products, codes and roll settings.
-- Luck items show the odds you would actually get with them, before buying (Roblox paid-random-items rules).
-- Prices come from Roblox when the item has an id; purchases are prompted and granted by the server.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MPS = game:GetService("MarketplaceService")
local Http = game:GetService("HttpService")
local M = RS:WaitForChild("Monster")
local Mon = require(M:WaitForChild("MonetizationConfig"))
local Config = require(M:WaitForChild("MonsterConfig"))
local Luck = require(M:WaitForChild("LuckConfig"))
local RobuxAction = M:WaitForChild("RobuxAction")
local ProgressAction = M:WaitForChild("ProgressAction")
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server

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
local function decode(s)
	local ok, v = pcall(Http.JSONDecode, Http, s or "")
	return ok and v or {}
end

local gui = Instance.new("ScreenGui") gui.Name = "ShopUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")
local hud = btn(gui, "🍀 SHOP", UDim2.fromOffset(110, 36), UDim2.fromOffset(12, 54), Color3.fromRGB(40, 190, 90))
local panel = Instance.new("Frame") panel.AnchorPoint = Vector2.new(0.5, 0.5) panel.Position = UDim2.fromScale(0.5, 0.5) panel.Size = UDim2.fromScale(0.9, 0.86)
panel.BackgroundColor3 = Color3.fromRGB(24, 40, 30) panel.Visible = false panel.Parent = gui
local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(1000, 700) lim.Parent = panel
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
local ps = Instance.new("UIStroke", panel) ps.Thickness = 4 ps.Color = Color3.fromRGB(80, 220, 120)
text("TextLabel", panel, "🍀 SHOP", UDim2.fromScale(0.3, 0.08), UDim2.fromScale(0.02, 0.015), Color3.fromRGB(150, 255, 170)).TextXAlignment = Enum.TextXAlignment.Left
local msg = text("TextLabel", panel, "", UDim2.fromScale(0.6, 0.05), UDim2.fromScale(0.33, 0.03), Color3.fromRGB(255, 220, 120))
local close = btn(panel, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 8), Color3.fromRGB(220, 50, 50))
close.MouseButton1Click:Connect(function() panel.Visible = false end)
local body = Instance.new("ScrollingFrame") body.Position = UDim2.fromScale(0.02, 0.2) body.Size = UDim2.fromScale(0.6, 0.78)
body.BackgroundTransparency = 1 body.BorderSizePixel = 0 body.CanvasSize = UDim2.new() body.AutomaticCanvasSize = Enum.AutomaticSize.Y body.ScrollBarThickness = 8 body.Parent = panel
local grid = Instance.new("UIGridLayout") grid.CellSize = UDim2.fromOffset(180, 200) grid.CellPadding = UDim2.fromOffset(10, 10)
grid.SortOrder = Enum.SortOrder.LayoutOrder grid.HorizontalAlignment = Enum.HorizontalAlignment.Center grid.Parent = body
-- right side: odds disclosure for the hovered/selected luck item
local oddsBox = Instance.new("Frame") oddsBox.Position = UDim2.fromScale(0.64, 0.2) oddsBox.Size = UDim2.fromScale(0.34, 0.78)
oddsBox.BackgroundColor3 = Color3.fromRGB(18, 28, 22) oddsBox.Parent = panel
Instance.new("UICorner", oddsBox)
local oddsTitle = text("TextLabel", oddsBox, "Tap an item to see its odds", UDim2.new(1, -12, 0, 26), UDim2.fromOffset(6, 6), Color3.fromRGB(200, 255, 210))
local oddsList = Instance.new("ScrollingFrame") oddsList.Position = UDim2.fromOffset(6, 36) oddsList.Size = UDim2.new(1, -12, 1, -42) oddsList.BackgroundTransparency = 1
oddsList.BorderSizePixel = 0 oddsList.CanvasSize = UDim2.new() oddsList.AutomaticCanvasSize = Enum.AutomaticSize.Y oddsList.Parent = oddsBox
local ol = Instance.new("UIListLayout") ol.SortOrder = Enum.SortOrder.LayoutOrder ol.Parent = oddsList

local tabs, tab = { "Gamepasses", "Luck", "Codes", "Settings" }, "Gamepasses"
local tabButtons = {}
local refresh
for i, name in tabs do
	local b = btn(panel, name, UDim2.fromScale(0.14, 0.06), UDim2.fromScale(0.02 + (i - 1) * 0.15, 0.11), Color3.fromRGB(50, 80, 60))
	tabButtons[name] = b
	b.MouseButton1Click:Connect(function() tab = name refresh() end)
end

-- real Robux prices (cached); falls back to the configured display price
local prices = {}
local function priceOf(item, kind)
	local id = kind == "pass" and item.gamepass or item.product
	if not id then return "Coming soon" end
	if prices[id] == nil then
		prices[id] = false
		task.spawn(function()
			local ok, info = pcall(MPS.GetProductInfo, MPS, id, kind == "pass" and Enum.InfoType.GamePass or Enum.InfoType.Product)
			prices[id] = ok and info and info.PriceInRobux or item.robux
			if panel.Visible then refresh() end
		end)
	end
	return "R$ " .. tostring(prices[id] or item.robux)
end

-- odds disclosure: what your current die would roll with this item's multiplier, every rarity, percent
local function biome()
	local b = decode(RS:GetAttribute("Biome"))
	return b.element and { element = b.element, mult = b.mult } or nil
end
local function extraMult(item, kind)
	if kind == "pass" then return item.effects.luckMult or 1 end
	local g = item.grant
	if g.luckyRolls then return Mon.LUCKY_ROLL_MULT end
	if g.potion then
		local cur = decode(state:GetAttribute("Boosts")).luck
		local m = cur and cur.mult or 1
		return math.max(g.potion.mult, m) / m
	end
	if g.serverLuck then
		local sl = decode(RS:GetAttribute("ServerLuck"))
		local m = sl.ends and sl.ends > os.time() and sl.mult or 1
		return math.max(g.serverLuck.mult, m) / m
	end
	return 1
end
local function showOdds(item, kind)
	for _, c in oddsList:GetChildren() do if c:IsA("TextLabel") then c:Destroy() end end
	local owned = kind == "pass" and decode(state:GetAttribute("Passes"))[item.id]
	local mult = owned and 1 or extraMult(item, kind)
	local base = state:GetAttribute("Luck") or 1
	local luck = math.min(Luck.HARD_CAP, base * mult)
	local maxTier, die, b = state:GetAttribute("MaxTier"), state:GetAttribute("SelectedDie"), biome()
	local now, with = Config.oddsFor(base, maxTier, die, b), Config.oddsFor(luck, maxTier, die, b)
	oddsTitle.Text = item.name .. ": luck x" .. ("%.2f"):format(base):gsub("%.?0+$", "") .. " → x" .. ("%.2f"):format(luck):gsub("%.?0+$", "")
	local order = 0
	local function line(str, color)
		order += 1
		local l = text("TextLabel", oddsList, str, UDim2.new(1, -8, 0, 20), UDim2.new(), color)
		l.TextXAlignment = Enum.TextXAlignment.Left l.LayoutOrder = order
	end
	line("Rarity: now  →  with this item (per roll)", Color3.fromRGB(200, 200, 210))
	local sum = 0
	for _, r in Config.Rarities do
		local p = with[r.id]
		if p and p > 0 then
			sum += p
			local n = 0
			for _, def in Config.Pools[r.id] or {} do if not def.dice or table.find(def.dice, die) then n += 1 end end
			line(("%s: %.4f%% → %.4f%%  (%d monsters, equal odds)"):format(r.id, (now[r.id] or 0) * 100, p * 100, n), r.color)
		end
	end
	line(("Total: %.4f%%"):format(sum * 100), Color3.new(1, 1, 1))
	line("Variants roll separately: Huge 2%, Monstrous 0.2%, Normal 97.8%", Color3.fromRGB(255, 200, 120))
	if kind == "product" and item.grant.luckyRolls then line("Each Lucky Roll applies to one roll, then is used up.", Color3.fromRGB(200, 200, 210)) end
	if state:GetAttribute("Restricted") then line("Paid luck items aren't available in your region.", Color3.fromRGB(255, 140, 140)) end
end

local function card(item, kind, i)
	local owned = kind == "pass" and decode(state:GetAttribute("Passes"))[item.id]
	local restricted = item.luck and state:GetAttribute("Restricted")
	local c = btn(body, "", UDim2.new(), UDim2.new(), Color3.fromRGB(36, 60, 44))
	c.LayoutOrder = i
	c:FindFirstChildOfClass("UIStroke").Color = item.color
	local icon = Instance.new("Frame") icon.Size = UDim2.fromOffset(96, 96) icon.Position = UDim2.new(0.5, -48, 0, 8) icon.BackgroundColor3 = item.color icon.Parent = c
	Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 18)
	Instance.new("UIStroke", icon).Thickness = 3
	if item.image then
		local img = Instance.new("ImageLabel") img.Size = UDim2.fromScale(1, 1) img.BackgroundTransparency = 1 img.Image = item.image img.Parent = icon
	else
		text("TextLabel", icon, item.icon, UDim2.fromScale(0.9, 0.9), UDim2.fromScale(0.05, 0.05))
	end
	text("TextLabel", c, item.name, UDim2.new(1, -10, 0, 24), UDim2.fromOffset(5, 108), Color3.new(1, 1, 1))
	local d = text("TextLabel", c, item.desc, UDim2.new(1, -10, 0, 30), UDim2.fromOffset(5, 132), Color3.fromRGB(200, 230, 210))
	d.TextWrapped = true
	local label = owned and "OWNED" or restricted and "Unavailable" or priceOf(item, kind)
	local buy = btn(c, label, UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, 164),
		owned and Color3.fromRGB(80, 90, 85) or restricted and Color3.fromRGB(90, 60, 60) or Color3.fromRGB(0, 170, 110))
	c.MouseButton1Click:Connect(function() if item.luck then showOdds(item, kind) end end)
	buy.MouseButton1Click:Connect(function()
		if item.luck then showOdds(item, kind) end
		if owned or restricted then return end
		local ok, err = RobuxAction:InvokeServer(kind, item.id)
		msg.Text = ok and "" or err
	end)
end

refresh = function()
	for _, c in body:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	for name, b in tabButtons do b.BackgroundColor3 = name == tab and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(50, 80, 60) end
	oddsBox.Visible = tab == "Gamepasses" or tab == "Luck"
	grid.CellSize = oddsBox.Visible and UDim2.fromOffset(180, 200) or UDim2.fromOffset(420, 56)
	if tab == "Gamepasses" then
		for i, item in Mon.Passes do card(item, "pass", i) end
	elseif tab == "Luck" then
		for i, item in Mon.Products do card(item, "product", i) end
	elseif tab == "Codes" then
		local box = Instance.new("TextBox") box.Size = UDim2.fromOffset(360, 50) box.PlaceholderText = "Enter code" box.Text = ""
		box.Font = Enum.Font.FredokaOne box.TextScaled = true box.BackgroundColor3 = Color3.fromRGB(40, 60, 50) box.TextColor3 = Color3.new(1, 1, 1)
		box.LayoutOrder = 1 box.Parent = body
		Instance.new("UICorner", box)
		local r = btn(body, "Redeem", UDim2.new(), UDim2.new(), Color3.fromRGB(0, 170, 110))
		r.LayoutOrder = 2
		r.MouseButton1Click:Connect(function()
			local ok, res = ProgressAction:InvokeServer("code", box.Text)
			msg.Text = ok and ("Redeemed: " .. res) or res
		end)
	else -- Settings
		local s = decode(state:GetAttribute("Settings"))
		local skip = s.skipBelow or 0
		local rb = btn(body, "Skip roll animation below: " .. (Config.Rarities[skip] and Config.Rarities[skip].id or "nothing"), UDim2.new(), UDim2.new(), Color3.fromRGB(60, 90, 140))
		rb.LayoutOrder = 1
		rb.MouseButton1Click:Connect(function()
			ProgressAction:InvokeServer("setting", "skipBelow", (skip + 1) % (#Config.Rarities + 1))
		end)
		local useLucky = s.useLucky ~= false
		local lb = btn(body, "Use Lucky Rolls: " .. (useLucky and "ON" or "OFF") .. " (" .. (state:GetAttribute("LuckyRolls") or 0) .. " left)", UDim2.new(), UDim2.new(),
			useLucky and Color3.fromRGB(40, 170, 90) or Color3.fromRGB(110, 90, 90))
		lb.LayoutOrder = 2
		lb.MouseButton1Click:Connect(function() ProgressAction:InvokeServer("setting", "useLucky", not useLucky) end)
		local autoPlace = s.autoPlace ~= false
		local ab = btn(body, "Auto-place new monsters: " .. (autoPlace and "ON" or "OFF"), UDim2.new(), UDim2.new(),
			autoPlace and Color3.fromRGB(40, 170, 90) or Color3.fromRGB(110, 90, 90))
		ab.LayoutOrder = 3
		ab.MouseButton1Click:Connect(function() ProgressAction:InvokeServer("setting", "autoPlace", not autoPlace) end)
	end
end
for _, a in { "Passes", "Settings", "LuckyRolls", "Restricted" } do
	state:GetAttributeChangedSignal(a):Connect(function() if panel.Visible then refresh() end end)
end
hud.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then msg.Text = "" refresh() end
end)
