-- Main HUD: cash, cash/s, current region, quest tracker, active events, save status, offline-earnings summary,
-- server notices and server-wide rare-roll announcements.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local player = Players.LocalPlayer
local M = RS:WaitForChild("Monster")
local B = require(M:WaitForChild("BattleConfig"))
local P = require(M:WaitForChild("ProgressConfig"))
local Config = require(M:WaitForChild("MonsterConfig"))
local Mon = require(M:WaitForChild("MonetizationConfig"))

local function short(n)
	for _, u in { { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return (("%.1f"):format(n / u[1]):gsub("%.0$", "")) .. u[2] end
	end
	return tostring(math.floor(n))
end
local function text(parent, size, pos, color, anchor)
	local l = Instance.new("TextLabel") l.Size = size l.Position = pos l.AnchorPoint = anchor or Vector2.new(0.5, 0) l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne l.TextScaled = true l.Text = "" l.TextColor3 = color l.TextStrokeTransparency = 0 l.Parent = parent
	return l
end
local function decode(s)
	local ok, v = pcall(Http.JSONDecode, Http, s or "")
	return ok and v or {}
end

local gui = Instance.new("ScreenGui") gui.Name = "HudUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")
local cash = text(gui, UDim2.fromOffset(420, 40), UDim2.new(0.5, 0, 0, 6), Color3.fromRGB(120, 255, 120))
local region = text(gui, UDim2.fromOffset(320, 22), UDim2.new(0.5, 0, 0, 46), Color3.fromRGB(200, 230, 255))
local status = text(gui, UDim2.fromOffset(520, 26), UDim2.new(0.5, 0, 0, 70), Color3.fromRGB(255, 220, 120))
local events = text(gui, UDim2.fromOffset(520, 24), UDim2.new(0.5, 0, 0, 96), Color3.fromRGB(255, 170, 255))
local boosts = text(gui, UDim2.fromOffset(620, 24), UDim2.new(0.5, 0, 0, 122), Color3.fromRGB(150, 255, 170))
local toast = text(gui, UDim2.fromScale(0.6, 0.06), UDim2.fromScale(0.5, 0.2), Color3.new(1, 1, 1))
local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(640, 54) lim.Parent = toast
local banner = text(gui, UDim2.fromScale(0.7, 0.05), UDim2.fromScale(0.5, 0.27), Color3.new(1, 1, 1))
local blim = Instance.new("UISizeConstraint") blim.MaxSize = Vector2.new(700, 44) blim.Parent = banner
-- quest tracker (top-right, under the leaderboard)
local quests = Instance.new("Frame") quests.AnchorPoint = Vector2.new(1, 0) quests.Position = UDim2.new(1, -12, 0, 120) quests.Size = UDim2.fromOffset(260, 96)
quests.BackgroundColor3 = Color3.fromRGB(20, 24, 34) quests.BackgroundTransparency = 0.3 quests.Parent = gui
Instance.new("UICorner", quests)
local qTitle = text(quests, UDim2.new(1, -12, 0, 22), UDim2.new(0.5, 0, 0, 4), Color3.fromRGB(255, 220, 120))
qTitle.Text = "QUESTS"
local qLines = {}
for i = 1, 3 do
	local l = text(quests, UDim2.new(1, -16, 0, 20), UDim2.new(0.5, 0, 0, 6 + i * 22), Color3.new(1, 1, 1))
	l.TextXAlignment = Enum.TextXAlignment.Left
	qLines[i] = l
end

local shown, bannerShown = 0, 0
local function show(msg, color, secs)
	toast.Text, toast.TextColor3 = msg, color or Color3.new(1, 1, 1)
	shown += 1
	local mine = shown
	task.delay(secs or 3, function() if shown == mine then toast.Text = "" end end)
end

local function refreshStatus()
	local ds, ps = player:GetAttribute("DataStatus"), player:GetAttribute("PlotStatus")
	status.Text = ds == "loading" and "Loading your save..." or ds == "unsaved" and "Studio test session: progress is NOT saved"
		or ps == "full" and "All plots are taken. You'll get one as soon as a player leaves." or ""
end
player:GetAttributeChangedSignal("DataStatus"):Connect(refreshStatus)
player:GetAttributeChangedSignal("PlotStatus"):Connect(refreshStatus)
refreshStatus()
local function refreshEvents()
	local names = {}
	for _, e in decode(RS:GetAttribute("Events")) do table.insert(names, e.name) end
	events.Text = #names > 0 and ("🎉 " .. table.concat(names, "  •  ")) or ""
end
RS:GetAttributeChangedSignal("Events"):Connect(refreshEvents)
refreshEvents()
M:WaitForChild("Announce").OnClientEvent:Connect(function(msg, rarity)
	local r = Config.RarityById[rarity]
	banner.Text, banner.TextColor3 = "📣 " .. msg, r and r.color or Color3.new(1, 1, 1)
	bannerShown += 1
	local mine = bannerShown
	task.delay(5, function() if bannerShown == mine then banner.Text = "" end end)
end)

local state = player:WaitForChild("PlayerGui"):WaitForChild("State")
local function refreshCash()
	cash.Text = "$" .. short(state:GetAttribute("Cash") or 0) .. "   (+" .. short(state:GetAttribute("CashPerSec") or 0) .. "/s)   💎 " .. (state:GetAttribute("Gems") or 0)
end
state:GetAttributeChangedSignal("Cash"):Connect(refreshCash)
state:GetAttributeChangedSignal("CashPerSec"):Connect(refreshCash)
state:GetAttributeChangedSignal("Gems"):Connect(refreshCash)
refreshCash()
-- current region = the furthest battle region you can enter
local function refreshRegion()
	local prog, dice = decode(state:GetAttribute("BattleProgress")), decode(state:GetAttribute("Dice"))
	local cur = B.Regions[1]
	for _, r in B.Regions do
		local prev = B.PrevStage[r.stages[1].id]
		if (not r.requiresDie or dice[r.requiresDie]) and (not prev or prog[prev]) then cur = r end
	end
	region.Text = cur.icon .. " Region: " .. cur.name
end
state:GetAttributeChangedSignal("BattleProgress"):Connect(refreshRegion)
state:GetAttributeChangedSignal("Dice"):Connect(refreshRegion)
refreshRegion()
local function refreshQuests()
	local pr = decode(state:GetAttribute("Progress"))
	local done, stats = pr.quests or {}, pr.stats or {}
	local value = { rolls = pr.rolls, discoveries = pr.unique, placed = pr.placed, earned = state:GetAttribute("LifetimeEarnings") or pr.earned }
	local i = 0
	for _, q in P.Quests do
		if not done[q.id] then
			i += 1
			local v = math.min(q.target, value[q.stat] or stats[q.stat] or 0)
			qLines[i].Text = "• " .. q.text .. "  " .. short(v) .. "/" .. short(q.target)
			if i == 3 then break end
		end
	end
	for k = i + 1, 3 do qLines[k].Text = k == 1 and "All quests done!" or "" end
end
state:GetAttributeChangedSignal("Progress"):Connect(refreshQuests)
state:GetAttributeChangedSignal("LifetimeEarnings"):Connect(refreshQuests)
refreshQuests()

-- luck line: banked Lucky Rolls, next Golden/Rainbow roll, biome and Server Luck timers (ticks every second)
local function clock(secs) return ("%d:%02d"):format(secs // 60, secs % 60) end
task.spawn(function()
	while true do
		local parts, now = {}, os.time()
		local lucky = state:GetAttribute("LuckyRolls") or 0
		if lucky > 0 then table.insert(parts, "🍀 Lucky Rolls: " .. lucky) end
		local friends = state:GetAttribute("Friends") or 0
		if friends > 0 then table.insert(parts, "👥 +" .. math.min(50, friends * 10) .. "% income (" .. friends .. " friends)") end
		local rolls = decode(state:GetAttribute("Progress")).rolls or 0
		local toG, toR = Mon.GOLDEN_EVERY - rolls % Mon.GOLDEN_EVERY, Mon.RAINBOW_EVERY - rolls % Mon.RAINBOW_EVERY
		table.insert(parts, toR <= toG and ("🌈 Rainbow in " .. toR) or ("✨ Golden in " .. toG))
		local b = decode(RS:GetAttribute("Biome"))
		if b.id and P.BiomeById[b.id] and b.ends > now then table.insert(parts, P.BiomeById[b.id].icon .. " " .. P.BiomeById[b.id].name .. " " .. clock(b.ends - now)) end
		local sl = decode(RS:GetAttribute("ServerLuck"))
		if sl.ends and sl.ends > now then table.insert(parts, "🌍 Server Luck x" .. sl.mult .. " " .. clock(sl.ends - now)) end
		local pot = decode(state:GetAttribute("Boosts")).luck
		if pot and pot.ends > now then table.insert(parts, "🧪 x" .. pot.mult .. " luck " .. clock(pot.ends - now)) end
		boosts.Text = table.concat(parts, "   •   ")
		task.wait(1)
	end
end)

local function offline()
	local o = decode(state:GetAttribute("OfflineEarnings"))
	if o.amount then
		show(("Welcome back! Your monsters earned $%s while you were away (%dh %dm)"):format(short(o.amount), o.secs // 3600, o.secs % 3600 // 60),
			Color3.fromRGB(120, 255, 120), 6)
	end
end
state:GetAttributeChangedSignal("OfflineEarnings"):Connect(offline)
offline()
-- confetti burst for quest / milestone rewards
local TweenService = game:GetService("TweenService")
local CONFETTI = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 220, 70), Color3.fromRGB(90, 220, 120), Color3.fromRGB(90, 160, 255), Color3.fromRGB(220, 110, 255) }
local function confetti()
	for _ = 1, 40 do
		local f = Instance.new("Frame") f.Size = UDim2.fromOffset(math.random(6, 12), math.random(10, 18)) f.BorderSizePixel = 0
		f.Position = UDim2.new(math.random(), 0, 0, -20) f.Rotation = math.random(0, 360) f.BackgroundColor3 = CONFETTI[math.random(1, #CONFETTI)]
		f.Parent = gui
		local t = math.random(15, 25) / 10
		TweenService:Create(f, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(f.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1, 20), Rotation = f.Rotation + math.random(-360, 360) }):Play()
		task.delay(t, function() f:Destroy() end)
	end
end
state:GetAttributeChangedSignal("Notice"):Connect(function()
	local n = decode(state:GetAttribute("Notice"))
	if not n.text then return end
	show(n.text, Color3.fromRGB(255, 200, 120), 4)
	if n.text:find("Quest complete") or n.text:find("Milestone") then confetti() end
end)
