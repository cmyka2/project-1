-- Daily Rewards, Leaderboards and Cosmetics panels (prompts at DailyRewards / Leaderboard / CosmeticShop,
-- plus a row of HUD buttons). Rewards, purchases and rankings all come from the server.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PPS = game:GetService("ProximityPromptService")
local Http = game:GetService("HttpService")
local M = RS:WaitForChild("Monster")
local P = require(M:WaitForChild("ProgressConfig"))
local ProgressAction = M:WaitForChild("ProgressAction")
local ShopAction = M:WaitForChild("ShopAction")
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
local gui = Instance.new("ScreenGui") gui.Name = "ExtrasUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")
local panels = {}
local function panel(title, color)
	local f = Instance.new("Frame") f.AnchorPoint = Vector2.new(0.5, 0.5) f.Position = UDim2.fromScale(0.5, 0.5) f.Size = UDim2.fromScale(0.75, 0.75)
	f.BackgroundColor3 = color f.Visible = false f.Parent = gui
	local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(760, 560) lim.Parent = f
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 18)
	Instance.new("UIStroke", f).Thickness = 4
	text("TextLabel", f, title, UDim2.fromScale(0.6, 0.09), UDim2.fromScale(0.03, 0.02)).TextXAlignment = Enum.TextXAlignment.Left
	local msg = text("TextLabel", f, "", UDim2.fromScale(0.94, 0.06), UDim2.fromScale(0.03, 0.11), Color3.fromRGB(255, 220, 120))
	local x = btn(f, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 8), Color3.fromRGB(220, 50, 50))
	x.MouseButton1Click:Connect(function() f.Visible = false end)
	local list = Instance.new("ScrollingFrame") list.Position = UDim2.fromScale(0.03, 0.19) list.Size = UDim2.fromScale(0.94, 0.78)
	list.BackgroundTransparency = 1 list.BorderSizePixel = 0 list.CanvasSize = UDim2.new() list.AutomaticCanvasSize = Enum.AutomaticSize.Y list.Parent = f
	table.insert(panels, f)
	return f, msg, list
end
local function clear(list) for _, c in list:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end end

-- DAILY
local daily, dMsg, dList = panel("DAILY REWARDS", Color3.fromRGB(40, 60, 40))
local dg = Instance.new("UIGridLayout") dg.CellSize = UDim2.fromOffset(150, 110) dg.CellPadding = UDim2.fromOffset(8, 8)
dg.HorizontalAlignment = Enum.HorizontalAlignment.Center dg.SortOrder = Enum.SortOrder.LayoutOrder dg.Parent = dList
local function refreshDaily()
	clear(dList)
	local d = decode(state:GetAttribute("Progress")).daily or { day = 0, last = -1 }
	local today = P.day(os.time())
	local nxt = P.nextDaily(d, os.time())
	for i, reward in P.Daily do
		local claimedDay = d.last == today and d.day or nil
		local isNext = nxt and nxt.day == i
		local f = btn(dList, "", UDim2.new(), UDim2.new(), isNext and Color3.fromRGB(60, 160, 70) or (claimedDay and i <= claimedDay and Color3.fromRGB(70, 90, 70) or Color3.fromRGB(50, 56, 60)))
		f.LayoutOrder = i
		text("TextLabel", f, "Day " .. i, UDim2.new(1, -8, 0.3, 0), UDim2.fromOffset(4, 4))
		text("TextLabel", f, reward.text, UDim2.new(1, -8, 0.4, 0), UDim2.new(0, 4, 0.36, 0), Color3.fromRGB(230, 230, 200)).TextWrapped = true
		text("TextLabel", f, isNext and "CLAIM" or (claimedDay and i <= claimedDay and "✔" or ""), UDim2.new(1, -8, 0.2, 0), UDim2.new(0, 4, 0.78, 0), Color3.fromRGB(150, 255, 150))
		if isNext then
			f.MouseButton1Click:Connect(function()
				local ok, res = ProgressAction:InvokeServer("daily")
				dMsg.Text = ok and ("Day " .. res.day .. ": " .. res.text) or res
			end)
		end
	end
	if not nxt then dMsg.Text = "Claimed today. Come back tomorrow (UTC) to keep your streak." end
end
state:GetAttributeChangedSignal("Progress"):Connect(function() if daily.Visible then refreshDaily() end end)

-- LEADERBOARDS
local ranks, rMsg, rList = panel("LEADERBOARDS", Color3.fromRGB(40, 40, 70))
local rl = Instance.new("UIGridLayout") rl.CellSize = UDim2.fromOffset(330, 270) rl.CellPadding = UDim2.fromOffset(10, 10)
rl.HorizontalAlignment = Enum.HorizontalAlignment.Center rl.SortOrder = Enum.SortOrder.LayoutOrder rl.Parent = rList
local function refreshRanks()
	clear(rList)
	local lb = decode(RS:GetAttribute("Leaderboards"))
	rMsg.Text = lb.boards == nil and "Leaderboards are loading..." or (lb.live and "Global top 10 (updates every 2 min)" or "Global boards unavailable here: showing this server")
	for i, b in lb.boards or {} do
		local f = Instance.new("Frame") f.BackgroundColor3 = Color3.fromRGB(55, 55, 90) f.LayoutOrder = i f.Parent = rList
		Instance.new("UICorner", f)
		text("TextLabel", f, b.name, UDim2.new(1, -10, 0, 28), UDim2.fromOffset(5, 4), Color3.fromRGB(255, 220, 120))
		for k, e in b.entries do
			local l = text("TextLabel", f, k .. ". " .. e.name .. "   " .. short(e.value), UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 10 + k * 23))
			l.TextXAlignment = Enum.TextXAlignment.Left
		end
	end
end
RS:GetAttributeChangedSignal("Leaderboards"):Connect(function() if ranks.Visible then refreshRanks() end end)

-- COSMETICS (titles + auras; cash, earned, or fixed Robux items, never random, never gameplay)
local shop, sMsg, sList = panel("COSMETICS", Color3.fromRGB(60, 35, 60))
local sl = Instance.new("UIListLayout") sl.Padding = UDim.new(0, 6) sl.SortOrder = Enum.SortOrder.LayoutOrder sl.Parent = sList
local function refreshShop()
	clear(sList)
	local c = decode(state:GetAttribute("Cosmetics"))
	local owned, eq = c.owned or {}, c.equipped or {}
	for i, item in P.Cosmetics do
		local row = Instance.new("Frame") row.Size = UDim2.new(1, -10, 0, 56) row.BackgroundColor3 = Color3.fromRGB(80, 50, 80) row.LayoutOrder = i row.Parent = sList
		Instance.new("UICorner", row)
		local name = text("TextLabel", row, (item.kind == "title" and "🏷️ " or "✨ ") .. item.name, UDim2.new(0.6, 0, 1, -10), UDim2.fromOffset(10, 5), item.color)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local label, color, action
		if owned[item.id] then
			local on = eq[item.kind] == item.id
			label, color, action = on and "Unequip" or "Equip", on and Color3.fromRGB(120, 80, 80) or Color3.fromRGB(60, 140, 220), on and "unequip" or "equip"
		elseif item.cash then
			label, color, action = "$" .. short(item.cash), Color3.fromRGB(50, 170, 70), "buy"
		elseif item.paid and (item.gamepass or item.product) then
			label, color, action = "Robux", Color3.fromRGB(0, 160, 120), "premium"
		elseif item.paid then
			label, color = "Coming soon", Color3.fromRGB(70, 70, 80)
		else
			label, color = "Earn it", Color3.fromRGB(70, 70, 80)
		end
		local b = btn(row, label, UDim2.new(0.3, 0, 1, -12), UDim2.new(0.68, 0, 0, 6), color)
		if action then
			b.MouseButton1Click:Connect(function()
				local ok, err = ShopAction:InvokeServer(action, action == "unequip" and item.kind or item.id)
				sMsg.Text = ok and "" or err
			end)
		end
	end
end
state:GetAttributeChangedSignal("Cosmetics"):Connect(function() if shop.Visible then refreshShop() end end)

local function open(f, refresh)
	for _, other in panels do other.Visible = false end
	refresh()
	f.Visible = true
end
PPS.PromptTriggered:Connect(function(prompt)
	if prompt:FindFirstAncestor("DailyRewards") then open(daily, refreshDaily)
	elseif prompt:FindFirstAncestor("Leaderboard") then open(ranks, refreshRanks)
	elseif prompt:FindFirstAncestor("CosmeticShop") then open(shop, refreshShop) end
end)
-- PLAYTIME GIFTS (server-timed; the countdown uses the server clock)
local gifts, gMsg, gList = panel("FREE GIFTS", Color3.fromRGB(40, 50, 80))
local gg = Instance.new("UIGridLayout") gg.CellSize = UDim2.fromOffset(150, 110) gg.CellPadding = UDim2.fromOffset(8, 8)
gg.HorizontalAlignment = Enum.HorizontalAlignment.Center gg.SortOrder = Enum.SortOrder.LayoutOrder gg.Parent = gList
local function giftLabel(r)
	local parts = {}
	if r.cashSecs then table.insert(parts, "💵 Cash") end
	if r.gems then table.insert(parts, "💎 " .. r.gems) end
	if r.luckyRolls then table.insert(parts, "🍀 " .. r.luckyRolls .. " Lucky Rolls") end
	if r.boost then table.insert(parts, "🧪 " .. r.boost.mult .. "x luck") end
	return table.concat(parts, "  ")
end
local function giftState(i)
	local claimed = decode(state:GetAttribute("GiftsClaimed"))
	if claimed[i] or claimed[tostring(i)] then return "claimed", 0 end
	local left = P.Gifts[i].mins * 60 - (workspace:GetServerTimeNow() - (state:GetAttribute("SessionStart") or 0))
	return left <= 0 and "ready" or "wait", math.max(0, math.ceil(left))
end
local function refreshGifts()
	clear(gList)
	for i, g in P.Gifts do
		local st, left = giftState(i)
		local f = btn(gList, "", UDim2.new(), UDim2.new(), st == "ready" and Color3.fromRGB(60, 170, 80) or Color3.fromRGB(50, 56, 72))
		f.LayoutOrder = i
		text("TextLabel", f, g.mins .. " min", UDim2.new(1, -8, 0.28, 0), UDim2.fromOffset(4, 4))
		text("TextLabel", f, giftLabel(g.reward), UDim2.new(1, -8, 0.36, 0), UDim2.new(0, 4, 0.32, 0), Color3.fromRGB(230, 230, 200)).TextWrapped = true
		text("TextLabel", f, st == "claimed" and "✔" or st == "ready" and "CLAIM" or ("%d:%02d"):format(left // 60, left % 60),
			UDim2.new(1, -8, 0.22, 0), UDim2.new(0, 4, 0.74, 0), Color3.fromRGB(150, 255, 150))
		if st == "ready" then
			f.MouseButton1Click:Connect(function()
				local ok, res = ProgressAction:InvokeServer("gift", i)
				gMsg.Text = ok and ("Gift: " .. res) or res
			end)
		end
	end
end
state:GetAttributeChangedSignal("GiftsClaimed"):Connect(function() if gifts.Visible then refreshGifts() end end)

-- HUD row (top-left, below the Roblox menu buttons); a red "!" marks anything claimable
local row = Instance.new("Frame") row.Position = UDim2.fromOffset(12, 12) row.Size = UDim2.fromOffset(400, 36) row.BackgroundTransparency = 1 row.Parent = gui
local rlay = Instance.new("UIListLayout") rlay.FillDirection = Enum.FillDirection.Horizontal rlay.Padding = UDim.new(0, 6) rlay.Parent = row
local badges = {}
for _, h in { { "DAILY", daily, refreshDaily, Color3.fromRGB(60, 160, 70) }, { "GIFTS", gifts, refreshGifts, Color3.fromRGB(230, 120, 40) },
	{ "RANKS", ranks, refreshRanks, Color3.fromRGB(80, 80, 180) }, { "STYLE", shop, refreshShop, Color3.fromRGB(170, 70, 170) } } do
	local b = btn(row, h[1], UDim2.fromOffset(90, 36), UDim2.new(), h[4])
	b.MouseButton1Click:Connect(function() if h[2].Visible then h[2].Visible = false else open(h[2], h[3]) end end)
	local dot = text("TextLabel", b, "!", UDim2.fromOffset(20, 20), UDim2.new(1, -12, 0, -8))
	dot.BackgroundTransparency = 0 dot.BackgroundColor3 = Color3.fromRGB(230, 40, 40) dot.Visible = false
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	badges[h[1]] = dot
end
-- invite friends (no reward: just the Roblox invite prompt)
local SocialService = game:GetService("SocialService")
local invite = btn(gui, "📨 INVITE", UDim2.fromOffset(110, 36), UDim2.fromOffset(128, 54), Color3.fromRGB(40, 130, 200))
invite.MouseButton1Click:Connect(function()
	local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if ok and can then pcall(SocialService.PromptGameInvite, SocialService, player) end
end)
-- badges + live gift countdowns, once a second
task.spawn(function()
	while true do
		local d = decode(state:GetAttribute("Progress")).daily or { day = 0, last = -1 }
		badges.DAILY.Visible = P.nextDaily(d, os.time()) ~= nil
		local ready = false
		for i in P.Gifts do if giftState(i) == "ready" then ready = true end end
		badges.GIFTS.Visible = ready
		if gifts.Visible then refreshGifts() end
		task.wait(1)
	end
end)
