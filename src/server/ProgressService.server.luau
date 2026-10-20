-- Progress extras, all server-authoritative: collection milestones and quests (auto-complete from server counters),
-- the 7-day daily reward, timed events, fast travel (Portal Mastery), and the cosmetics / premium shop.
-- ProgressAction: ("daily") | ("gift", index) | ("travel", destination) | ("code", text)
--                 | ("setting", "skipBelow" | "useLucky" | "autoPlace", value)
-- Also runs the server-wide biomes (weather that boosts one element's roll weight).
-- ShopAction: ("buy", cosmeticId) | ("equip", cosmeticId) | ("unequip", "title" | "aura") | ("premium", cosmeticId)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MPS = game:GetService("MarketplaceService")
local Http = game:GetService("HttpService")
local M = RS.Monster
local P = require(M.ProgressConfig)
local Config = require(M.MonsterConfig)
local GearConfig = require(M.GearConfig)
local Assets = require(M.AssetRegistry)
local Weighted = require(M.Weighted)
local Data = require(script.Parent.DataService)
local Game = require(script.Parent.Game)
local Guard = require(script.Parent.Guard)
local rng = Random.new()

-- REWARDS shared by quests, milestones and daily days
local function grant(player, p, r)
	local d, got = p.data, {}
	if r.cash then Game.addCash(p, r.cash) table.insert(got, "$" .. Game.short(r.cash)) end
	if r.gems then d.Gems += r.gems table.insert(got, r.gems .. " Gems") end
	if r.luckyRolls then d.LuckyRolls += r.luckyRolls table.insert(got, r.luckyRolls .. " Lucky Rolls") end
	for mat, n in r.mats or {} do
		d.Materials[mat] = (d.Materials[mat] or 0) + n
		table.insert(got, n .. " " .. GearConfig.MaterialById[mat].name)
	end
	if r.gear then
		local uid = Game.addGear(p, r.gear, GearConfig.randomType(rng))
		table.insert(got, uid and (r.gear .. " gear") or "(gear bag full)")
	end
	if r.cosmetic and not d.Cosmetics[r.cosmetic] then
		d.Cosmetics[r.cosmetic] = true
		table.insert(got, P.CosmeticById[r.cosmetic].name)
	end
	return table.concat(got, ", ")
end

-- MILESTONES + QUESTS: checked whenever a counter moves and on a slow sweep (for income-driven ones)
local function questValue(p, stat)
	local d = p.data
	if stat == "rolls" then return d.Rolls end
	if stat == "discoveries" then return Game.unique(p) end
	if stat == "placed" then return Game.count(d.Placed) end
	if stat == "earned" then return d.LifetimeEarnings end
	return d.Stats[stat] or 0
end
-- every monster of a rarity discovered (any variant)
local function setDone(p, rarity)
	for _, m in Config.Pools[rarity] or {} do
		local disc = p.data.Discovered[m.id]
		if not (disc and next(disc)) then return false end
	end
	return Config.Pools[rarity] ~= nil
end
local function check(player)
	local p = Game.get(player)
	if not p or p.released then return end
	local d, changed = p.data, false
	for _, m in P.Milestones do
		if not d.Milestones[m.id] and ((m.unique and Game.unique(p) >= m.unique) or (m.set and setDone(p, m.set))) then
			d.Milestones[m.id] = true
			changed = true
			local got = grant(player, p, m)
			Game.notify(player, "Milestone: " .. m.name .. (got ~= "" and ("  →  " .. got) or ""))
		end
	end
	local active = 0
	for _, q in P.Quests do
		if not d.Quests[q.id] then
			active += 1
			if questValue(p, q.stat) >= q.target then
				d.Quests[q.id] = true
				changed = true
				Game.notify(player, "Quest complete: " .. q.text .. "  →  " .. grant(player, p, q.reward))
			end
			if active >= 3 then break end
		end
	end
	if changed then
		Game.publish(player, p) -- milestones can change stats (storage/luck); cosmetics and gear too
		Data.saveSoon(player)
	end
end
Game.Changed.Event:Connect(check)
Data.onLoaded(function(player) check(player) end)

-- EVENTS: recomputed every 30 s and published publicly (they're global, not private)
local forced = {} -- [eventId] = until (Studio QA hook)
local function refreshEvents()
	Game.events = P.activeEvents(os.time(), forced)
	local list = {}
	for _, e in Game.events do table.insert(list, { id = e.id, name = e.name }) end
	local json = Http:JSONEncode(list)
	if RS:GetAttribute("Events") == json then return end
	RS:SetAttribute("Events", json)
	for player, p in Data.all() do -- luck and income previews change with events
		if not p.released then Game.publish(player, p) Game.BaseChanged:Fire(player) end
	end
end
task.spawn(function()
	while true do
		refreshEvents()
		for player, p in Data.all() do
			if not p.released then check(player) end
		end
		task.wait(30)
	end
end)

-- COSMETICS: titles above the head, auras as particles (AssetRegistry Particles/<id> if imported)
local function dress(player, p)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end
	for _, old in char:GetDescendants() do if old:GetAttribute("Cosmetic") then old:Destroy() end end
	local eq = p.data.Equipped
	local title = eq.title and P.CosmeticById[eq.title]
	if title then
		local b = Instance.new("BillboardGui") b.Size = UDim2.fromOffset(200, 30) b.StudsOffset = Vector3.new(0, 2.6, 0) b.MaxDistance = 80
		b:SetAttribute("Cosmetic", true)
		local t = Instance.new("TextLabel") t.Size = UDim2.fromScale(1, 1) t.BackgroundTransparency = 1 t.TextScaled = true t.Font = Enum.Font.FredokaOne
		t.Text = title.name t.TextColor3 = title.color t.TextStrokeTransparency = 0 t.Parent = b
		b.Parent = head
	end
	local aura = eq.aura and P.CosmeticById[eq.aura]
	local root = char:FindFirstChild("HumanoidRootPart")
	if aura and root then
		local asset = Assets.GetAsset("Particles", aura.id)
		local pe = asset and asset:IsA("ParticleEmitter") and asset:Clone() or Instance.new("ParticleEmitter")
		if not asset then
			pe.Color = ColorSequence.new(aura.color) pe.LightEmission = 1 pe.Rate = 12 pe.Lifetime = NumberRange.new(1, 1.6)
			pe.Speed = NumberRange.new(1, 2) pe.Size = NumberSequence.new(0.6, 0)
		end
		pe:SetAttribute("Cosmetic", true)
		pe.Parent = root
	end
end
Data.onLoaded(function(player, p)
	player.CharacterAdded:Connect(function(char) char:WaitForChild("Head", 5) dress(player, p) end)
	if player.Character then dress(player, p) end
	Game.publish(player, p, "Cosmetics")
end)

M.ShopAction.OnServerInvoke = function(player, action, id)
	local p = Game.get(player)
	if not p then return false, "Still loading" end
	if not Guard.rate(player, "shop", 0.3) then return false, "Too fast" end
	local d = p.data
	if action == "unequip" then
		if id ~= "title" and id ~= "aura" then return false, "Bad request" end
		d.Equipped[id] = nil
	else
		local c = Guard.str(id) and P.CosmeticById[id]
		if not c then return false, "Unknown item" end
		if action == "buy" then
			if d.Cosmetics[id] then return false, "Already owned" end
			if not c.cash then return false, "Not for sale" end
			if not Game.spend(p, c.cash) then return false, "Need $" .. Game.short(c.cash) end
			d.Cosmetics[id] = true
			Data.saveSoon(player)
		elseif action == "equip" then
			if not d.Cosmetics[id] then return false, "You don't own that" end
			d.Equipped[c.kind] = id
		elseif action == "premium" then
			if d.Cosmetics[id] then return false, "Already owned" end
			if c.product then MPS:PromptProductPurchase(player, c.product) return true end -- granted in MonetizationService.ProcessReceipt
			return false, "Not on sale yet"
		else
			return false, "Bad request"
		end
	end
	Game.publish(player, p, "Cosmetics")
	dress(player, p)
	return true
end
-- DAILY REWARD
local function claimDaily(player, p)
	local d = p.data
	local nxt = P.nextDaily(d.Daily, os.time())
	if not nxt then return false, "Already claimed today. Come back tomorrow!" end
	local day = P.Daily[nxt.day]
	d.Daily = nxt
	local got = {}
	if day.cashSecs then
		local cash = math.max(day.cash or 0, math.floor(Game.incomePerSec(p, true) * day.cashSecs))
		Game.addCash(p, cash)
		table.insert(got, "$" .. Game.short(cash))
	end
	if day.chest then -- a free open of the best chest you can buy
		local best
		for _, c in GearConfig.Chests do if d.Dice[c.die] then best = c end end
		local rarity, gtype = GearConfig.roll(best, rng, Game.stat(p, "chestluck"))
		table.insert(got, Game.addGear(p, rarity, gtype) and (rarity .. " " .. GearConfig.TypeById[gtype].name) or "(gear bag full)")
	end
	if day.boost then
		local b = day.boost
		d.Boosts[b.effect] = { mult = b.mult, ends = os.time() + b.secs }
		table.insert(got, day.text)
	end
	local more = grant(player, p, { mats = day.mats, gear = day.gear, cosmetic = day.cosmetic, gems = day.gems, luckyRolls = day.luckyRolls })
	if more ~= "" then table.insert(got, more) end
	Game.publish(player, p)
	Data.saveSoon(player)
	return true, { day = nxt.day, text = table.concat(got, ", ") }
end

-- FAST TRAVEL (Portal Mastery): only to named hub spots or your own base
local DEST = { "SummonArea", "DiceShop", "ChestShop", "UpgradeTree", "RebirthAltar", "Index", "DailyRewards", "Leaderboard", "CosmeticShop" }
local function travel(player, p, dest)
	if Game.stat(p, "travel") <= 0 then return false, "Unlock Portal Mastery in the Evolution Tree" end
	local char = player.Character
	if not char then return false, "No character" end
	local hub = workspace:FindFirstChild("Hub")
	local target
	if dest == "base" then
		local id = player:GetAttribute("PlotId")
		local plot = id and hub and hub:FindFirstChild("Plots") and hub.Plots:FindFirstChild("Plot" .. id)
		target = plot and plot:FindFirstChild("SpawnPoint") and plot.SpawnPoint.CFrame
	elseif table.find(DEST, dest) then
		local m = hub and hub:FindFirstChild(dest, true)
		target = m and m:GetPivot() * CFrame.new(0, 0, 18)
	end
	if not target then return false, "Can't find that place" end
	char:PivotTo(target + Vector3.new(0, 5, 0))
	return true
end

-- CODES: once per player, case-insensitive, optional expiry
local function redeem(player, p, text)
	if typeof(text) ~= "string" or #text > 40 then return false, "Invalid code" end
	local key = text:upper():gsub("%s", "")
	local c = P.CodeByName[key]
	if not c then return false, "Invalid code" end
	if c.expires and os.time() >= c.expires then return false, "That code has expired" end
	local d = p.data
	if d.Codes[key] then return false, "Already redeemed" end
	d.Codes[key] = true
	local r, got = c.reward, {}
	if r.boost then
		local b, now = d.Boosts[r.boost.effect], os.time()
		local live = b and b.ends > now
		d.Boosts[r.boost.effect] = { mult = math.max(r.boost.mult, live and b.mult or 1), ends = (live and b.ends or now) + r.boost.secs }
		table.insert(got, r.boost.mult .. "x " .. r.boost.effect .. " for " .. r.boost.secs // 60 .. " min")
	end
	local more = grant(player, p, { cash = r.cash, gems = r.gems, luckyRolls = r.luckyRolls, mats = r.mats, gear = r.gear })
	if more ~= "" then table.insert(got, more) end
	Game.publish(player, p)
	Data.saveSoon(player)
	return true, table.concat(got, ", ")
end

local function setting(p, key, value)
	if key == "skipBelow" then
		local v = Guard.int(value, 0, #Config.Rarities)
		if not v then return false, "Bad value" end
		p.data.Settings.skipBelow = v
	elseif key == "useLucky" or key == "autoPlace" then
		if typeof(value) ~= "boolean" then return false, "Bad value" end
		p.data.Settings[key] = value
	else
		return false, "Bad setting"
	end
	Game.publish(p.player, p)
	return true
end

-- PLAYTIME GIFTS: unlocked by session minutes on the server clock
Data.onLoaded(function(player, p)
	p.sessionStart, p.gifts = os.time(), {}
	Game.publish(player, p)
end)
local function claimGift(player, p, i)
	local gift = Guard.int(i, 1, #P.Gifts) and P.Gifts[i]
	if not gift then return false, "Unknown gift" end
	if p.gifts[i] then return false, "Already claimed" end
	if os.time() - (p.sessionStart or os.time()) < gift.mins * 60 then return false, "Not ready yet" end
	p.gifts[i] = true
	local r, d, got = gift.reward, p.data, {}
	if r.cashSecs then
		local cash = math.max(r.cash or 0, math.floor(Game.incomePerSec(p, true) * r.cashSecs))
		Game.addCash(p, cash)
		table.insert(got, "$" .. Game.short(cash))
	end
	if r.boost then
		local b, now = d.Boosts[r.boost.effect], os.time()
		local live = b and b.ends > now
		d.Boosts[r.boost.effect] = { mult = math.max(r.boost.mult, live and b.mult or 1), ends = (live and b.ends or now) + r.boost.secs }
		table.insert(got, r.boost.mult .. "x luck for " .. r.boost.secs // 60 .. " min")
	end
	local more = grant(player, p, { gems = r.gems, luckyRolls = r.luckyRolls })
	if more ~= "" then table.insert(got, more) end
	Game.publish(player, p)
	Data.saveSoon(player)
	return true, table.concat(got, ", ")
end

M.ProgressAction.OnServerInvoke = function(player, action, a, b)
	local p = Game.get(player)
	if not p then return false, "Still loading" end
	if not Guard.rate(player, "progress", 0.5) then return false, "Too fast" end
	if action == "daily" then return claimDaily(player, p) end
	if action == "travel" then return travel(player, p, Guard.str(a)) end
	if action == "code" then return redeem(player, p, a) end
	if action == "gift" then return claimGift(player, p, a) end
	if action == "setting" then return setting(p, a, b) end
	return false, "Bad request"
end

-- FRIENDS: +10% income per friend in this server (Game.friendMult); recounted on joins and leaves
local friendCache = {} -- [a][b] = bool (IsFriendsWith yields, so cache it per pair)
local function recountFriends()
	local list = Players:GetPlayers()
	for _, a in list do
		local p = Game.get(a)
		if p then
			local n = 0
			for _, b in list do
				if b ~= a then
					friendCache[a] = friendCache[a] or {}
					if friendCache[a][b] == nil then
						local ok, yes = pcall(a.IsFriendsWith, a, b.UserId)
						friendCache[a][b] = ok and yes or false
					end
					if friendCache[a][b] then n += 1 end
				end
			end
			if p.friends ~= n then
				p.friends = n
				Game.publish(a, p, "Monsters")
				Game.BaseChanged:Fire(a)
			end
		end
	end
end
Data.onLoaded(function() task.spawn(recountFriends) end)
Players.PlayerRemoving:Connect(function(player)
	friendCache[player] = nil
	for _, c in friendCache do c[player] = nil end
	task.defer(recountFriends)
end)

-- BIOMES: published on ReplicatedStorage "Biome" (public); the roll pool reads Game.biome
local biomeToken = 0
local function setBiome(b, secs)
	biomeToken += 1
	Game.biome = b and { id = b.id, element = b.element, mult = b.mult, ends = os.time() + secs } or nil
	RS:SetAttribute("Biome", Http:JSONEncode(Game.biome or {}))
	if b then M.Announce:FireAllClients(b.icon .. " " .. b.name .. " has begun! " .. b.element .. " monsters are x" .. b.mult .. " more likely", "Epic") end
	local mine = biomeToken
	if b then task.delay(secs, function() if biomeToken == mine then setBiome(nil) end end) end
end
task.spawn(function()
	while true do
		task.wait(P.BIOME_EVERY)
		if not Game.biome and rng:NextNumber() < P.BIOME_CHANCE then
			local list = {}
			for _, b in P.Biomes do table.insert(list, { b, b.weight }) end
			local b = Weighted.pick(list, rng)
			if b then setBiome(b, b.secs) end
		end
	end
end)
RS:SetAttribute("Biome", "{}")

-- Studio QA: ServerStorage.DevStartEvent:Invoke("weekend_income", 600)  ServerStorage.DevStartBiome:Invoke("starfall", 120)
if RunService:IsStudio() then
	local bb = Instance.new("BindableFunction") bb.Name = "DevStartBiome"
	bb.OnInvoke = function(id, secs)
		local b = P.BiomeById[id]
		if not b then return false end
		setBiome(b, secs or b.secs)
		return true
	end
	bb.Parent = game:GetService("ServerStorage")
	local b = Instance.new("BindableFunction") b.Name = "DevStartEvent"
	b.OnInvoke = function(id, secs)
		if not P.EventById[id] then return false end
		forced[id] = os.time() + (secs or 600)
		refreshEvents()
		return true
	end
	b.Parent = game:GetService("ServerStorage")
end
