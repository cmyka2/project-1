-- Server-authoritative: rolling, cash/income, skill tree purchases, saving.
local DSS = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Http = game:GetService("HttpService")
local Config = require(RS.Monster.MonsterConfig)
local Tree = require(RS.Monster.SkillTree)
local RebirthConfig = require(RS.Monster.RebirthConfig)
local DiceConfig = require(RS.Monster.DiceConfig)
local GearConfig = require(RS.Monster.GearConfig)
local MAX_GEAR = 200
local MonsterModel = require(RS.Monster.MonsterModel)

local storeOk, store = pcall(DSS.GetDataStore, DSS, "MonsterRoll_v1") -- errors in unpublished places
if not storeOk then warn("DataStore unavailable:", store) store = nil end
local profiles = {} -- [Player] = { data = table, saveable = bool }
local lastAction = {}
local rng = Random.new()
local ROLL_COOLDOWN = 0.8
local BASE_SLOTS, MAX_SLOTS = 5, 10 -- 5 + rebirths, capped by the 10 pedestals on a plot
-- ponytail: one floor; add floors 2-3 (rebirth 6/12) when plots get upper levels
local renderAll -- defined with placement below
local MAX_CASH = 1e15 -- ponytail: plain numbers; switch to a big-number format before costs pass ~1e15

local function key(player) return "u_" .. player.UserId end
local function default() return { Version = 1, Discovered = {}, Owned = {}, Rolls = 0, Cash = 0, Skills = { start = true }, Placed = {}, Rebirths = 0, Dice = { grassland = true }, SelectedDie = "grassland", Gear = {}, NextGearId = 1, BattleProgress = {} } end
local function migrate(d)
	d.Cash = d.Cash or 0
	d.Skills = d.Skills or { start = true }
	d.Placed = d.Placed or {}
	d.Rebirths = d.Rebirths or 0
	d.Dice = d.Dice or { grassland = true }
	d.SelectedDie = d.SelectedDie or "grassland"
	d.Gear = d.Gear or {}
	d.NextGearId = d.NextGearId or 1
	d.BattleProgress = d.BattleProgress or {}
	return d
end

local function stat(p, effect) return Tree.stat(p.data.Skills, effect) end
local function dieOf(p) return DiceConfig.ById[p.data.SelectedDie] or DiceConfig.List[1] end
local function effLuck(p) return (1 + stat(p, "luck")) * dieOf(p).luck end

-- k = "monsterId|Variant"
local function keyIncome(p, k)
	local id, variant = string.match(k, "^(.-)|(.+)$")
	local def = Config.ById[id]
	if not def then return 0 end
	return Config.Income[def.rarity] * (Config.VariantIncome[variant] or 1) * (1 + stat(p, "income"))
end

-- gear is equipped to a base slot (sk = "1".."10") and boosts that slot's monster
-- ponytail: gear follows the slot, not a monster instance; move to instance ids when monsters get levels/fusion
local function gearBonus(p, sk)
	local b = 0
	for _, g in p.data.Gear do
		if g.slot == sk then b += GearConfig.RarityById[g.r].income end
	end
	return b
end
local function slotIncome(p, sk, k) return keyIncome(p, k) * (1 + gearBonus(p, sk)) end

-- only monsters placed on base slots earn
local function incomePerSec(p)
	local total = 0
	for sk, k in p.data.Placed do total += slotIncome(p, sk, k) end
	return total
end
local function slotCount(p) return math.min(MAX_SLOTS, BASE_SLOTS + p.data.Rebirths) end

-- client-visible state; the server never reads these back
local function publish(player, p)
	player:SetAttribute("Index", Http:JSONEncode({ D = p.data.Discovered, O = p.data.Owned, R = p.data.Rolls }))
	player:SetAttribute("Skills", Http:JSONEncode(p.data.Skills))
	player:SetAttribute("Luck", effLuck(p))
	player:SetAttribute("MaxTier", dieOf(p).maxTier)
	player:SetAttribute("Dice", Http:JSONEncode(p.data.Dice))
	player:SetAttribute("SelectedDie", dieOf(p).id)
	player:SetAttribute("Gear", Http:JSONEncode(p.data.Gear))
	player:SetAttribute("BattleProgress", Http:JSONEncode(p.data.BattleProgress))
	player:SetAttribute("Placed", Http:JSONEncode(p.data.Placed))
	player:SetAttribute("Slots", slotCount(p))
	player:SetAttribute("Rebirths", p.data.Rebirths)
end
local function publishCash(player, p)
	local ls = player:FindFirstChild("leaderstats")
	if ls then ls.Cash.Value = math.floor(p.data.Cash) end
	player:SetAttribute("Cash", p.data.Cash)
	player:SetAttribute("CashPerSec", incomePerSec(p))
end
local function applyWalk(player, p)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = 16 + stat(p, "walkspeed") end
end

local function load(player)
	local ok, data
	for i = 1, store and 3 or 0 do
		ok, data = pcall(store.GetAsync, store, key(player))
		if ok then break end
		warn("Load failed for", player.Name, data)
		task.wait(i * 2)
	end
	if not player.Parent then return end
	if ok then
		profiles[player] = { data = migrate(data or default()), saveable = true }
	elseif RunService:IsStudio() then
		warn("DataStore unavailable in Studio; playing without saving (publish + enable Studio API access to test saves)")
		profiles[player] = { data = default(), saveable = false }
	else
		-- never start a session that could overwrite a real save with defaults
		player:Kick("Couldn't load your save. Your data is safe, please rejoin.")
		return
	end
	local p = profiles[player]
	local ls = Instance.new("Folder") ls.Name = "leaderstats"
	local cash = Instance.new("NumberValue") cash.Name = "Cash" cash.Parent = ls
	ls.Parent = player
	publish(player, p)
	publishCash(player, p)
	player.CharacterAdded:Connect(function() task.defer(applyWalk, player, p) end)
	applyWalk(player, p)
	player:GetAttributeChangedSignal("PlotId"):Connect(function() renderAll(player, profiles[player]) end)
	renderAll(player, p)
end

local function save(player)
	local p = profiles[player]
	if not p or not p.saveable then return end
	for i = 1, 3 do
		-- ponytail: no session lock; add one before trading or cross-server teleports exist
		local ok, err = pcall(store.UpdateAsync, store, key(player), function() return p.data end)
		if ok then return end
		warn("Save failed for", player.Name, err)
		task.wait(i)
	end
end

Players.PlayerAdded:Connect(load)
for _, pl in Players:GetPlayers() do task.defer(load, pl) end -- defer: renderAll is assigned further down
Players.PlayerRemoving:Connect(function(player)
	renderAll(player, nil) -- clear their monsters off the plot
	save(player)
	profiles[player] = nil
	lastAction[player] = nil
end)
game:BindToClose(function()
	local left = 0
	for player in profiles do
		left += 1
		task.spawn(function() save(player) left -= 1 end)
	end
	while left > 0 do task.wait() end
end)
task.spawn(function()
	local t = 0
	while true do
		task.wait(1)
		t += 1
		for player, p in profiles do
			p.data.Cash = math.min(MAX_CASH, p.data.Cash + incomePerSec(p))
			publishCash(player, p)
			if t % 60 == 0 then task.spawn(save, player) end
		end
	end
end)

local function showRoll(player, core, def, variant)
	local m = MonsterModel.build(def, variant)
	local root = player.Character and player.Character.PrimaryPart
	local pos = core.Position + Vector3.new(0, 1, 0)
	local look = root and Vector3.new(root.Position.X, pos.Y, root.Position.Z) or pos + Vector3.zAxis
	if (look - pos).Magnitude < 0.1 then look = pos + Vector3.zAxis end
	m:PivotTo(CFrame.lookAt(pos, look))
	local rar = Config.RarityById[def.rarity]
	local v = Config.VariantById[variant]
	if variant ~= "Normal" then
		local h = Instance.new("Highlight") h.FillTransparency = 1 h.OutlineColor = v.color h.Parent = m
	end
	local _, size = m:GetBoundingBox()
	local b = Instance.new("BillboardGui") b.Size = UDim2.fromOffset(260, 50) b.StudsOffsetWorldSpace = Vector3.new(0, size.Y + 2, 0) b.MaxDistance = 120
	local t = Instance.new("TextLabel") t.Size = UDim2.fromScale(1, 1) t.BackgroundTransparency = 1 t.TextScaled = true t.Font = Enum.Font.FredokaOne
	t.Text = (variant ~= "Normal" and variant:upper() .. " " or "") .. def.name t.TextColor3 = variant ~= "Normal" and v.color or rar.color t.TextStrokeTransparency = 0
	t.Parent = b b.Adornee = m.PrimaryPart b.Parent = m
	m.Parent = workspace
	Debris:AddItem(m, 4)
end

local summon = workspace:WaitForChild("Hub"):WaitForChild("Shops"):WaitForChild("SummonArea"):WaitForChild("SummonCore")
summon:WaitForChild("ProximityPrompt").Triggered:Connect(function(player)
	local p = profiles[player]
	if not p then return end
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < ROLL_COOLDOWN * (1 - math.min(0.75, stat(p, "rollspeed"))) then return end
	lastAction[player] = now

	local def, variant = Config.roll(rng, effLuck(p), dieOf(p).maxTier)
	local d = p.data
	d.Rolls += 1
	local disc = d.Discovered[def.id] or {}
	local isNew = not disc[variant]
	disc[variant] = true
	d.Discovered[def.id] = disc
	local k = def.id .. "|" .. variant
	d.Owned[k] = (d.Owned[k] or 0) + 1

	publish(player, p)
	publishCash(player, p)
	player:SetAttribute("LastRoll", Http:JSONEncode({ id = def.id, v = variant, new = isNew, n = d.Rolls }))
	showRoll(player, summon, def, variant)
end)

local function short(n)
	for _, u in { { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return (("%.1f"):format(n / u[1]):gsub("%.0$", "")) .. u[2] end
	end
	return n < 100 and (("%.1f"):format(n):gsub("%.0$", "")) or tostring(math.floor(n))
end
local function plotOf(player)
	local id = player:GetAttribute("PlotId")
	return id and workspace.Hub.Plots:FindFirstChild("Plot" .. id)
end
-- p = nil clears the slot
local function renderSlot(player, p, i)
	local plot = plotOf(player)
	local slot = plot and plot:FindFirstChild("Slot" .. i)
	if not slot then return end
	local shown = plot:FindFirstChild("Placed") or Instance.new("Folder")
	shown.Name = "Placed" shown.Parent = plot
	local old = shown:FindFirstChild("Slot" .. i)
	if old then old:Destroy() end
	local lockLabel = slot:FindFirstChildOfClass("BillboardGui") -- "Rebirth N" sign, hidden once unlocked
	if lockLabel then lockLabel.Enabled = not (p and i <= slotCount(p)) end
	local k = p and p.data.Placed[tostring(i)]
	local pad = plot:FindFirstChild("Collect" .. i)
	local label = pad and pad:FindFirstChild("Label", true)
	if label then label.Text = k and ("$" .. short(slotIncome(p, tostring(i), k)) .. "/s") or "$0" end
	if not k then return end
	local id, variant = string.match(k, "^(.-)|(.+)$")
	local def = Config.ById[id]
	if not def then return end -- unknown id: keep the record, show nothing
	local m = MonsterModel.build(def, variant)
	m.Name = "Slot" .. i
	local top = slot.Position + Vector3.new(0, slot.Size.Y / 2, 0)
	m:PivotTo(CFrame.lookAt(top, top - slot.CFrame.LookVector))
	m.Parent = shown
end
renderAll = function(player, p)
	for i = 1, MAX_SLOTS do renderSlot(player, p, i) end
end

local lastBuy = {}
RS.Monster.BuySkill.OnServerInvoke = function(player, nodeId)
	local p = profiles[player]
	if not p then return false, "Still loading" end
	if typeof(nodeId) ~= "string" then return false, "Bad request" end
	local node = Tree.ById[nodeId]
	if not node then return false, "Unknown upgrade" end
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < 0.2 then return false, "Too fast" end
	lastBuy[player] = now
	local skills = p.data.Skills
	if skills[nodeId] then return false, "Already owned" end
	if node.requires and not skills[node.requires] then return false, "Locked" end
	if p.data.Cash < node.cost then return false, "Not enough cash" end
	p.data.Cash -= node.cost
	skills[nodeId] = true
	publish(player, p)
	publishCash(player, p)
	applyWalk(player, p)
	renderAll(player, p) -- pad income labels change with Money nodes
	return true
end

RS.Monster.PlaceMonster.OnServerInvoke = function(player, slot, k)
	local p = profiles[player]
	if not p then return false, "Still loading" end
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < 0.15 then return false, "Too fast" end
	lastBuy[player] = now
	if typeof(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > MAX_SLOTS then return false, "Bad slot" end
	if slot > slotCount(p) then return false, "Unlocks at Rebirth " .. (slot - BASE_SLOTS) end
	if not plotOf(player) then return false, "You don't have a plot" end
	local placed, sk = p.data.Placed, tostring(slot)
	if k == nil then
		placed[sk] = nil
	else
		if typeof(k) ~= "string" then return false, "Bad request" end
		local owned = p.data.Owned[k] or 0
		local inUse = 0
		for s2, v in placed do if v == k and s2 ~= sk then inUse += 1 end end
		if inUse >= owned then return false, "You don't have a free one of those" end
		placed[sk] = k
	end
	-- the monster in this slot changed: its gear goes back to the bag
	for _, g in p.data.Gear do if g.slot == sk then g.slot = nil end end
	publish(player, p)
	publishCash(player, p)
	renderSlot(player, p, slot)
	return true
end
Players.PlayerRemoving:Connect(function(player) lastBuy[player] = nil end)

RS.Monster.Rebirth.OnServerInvoke = function(player)
	local p = profiles[player]
	if not p then return false, "Still loading" end
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < 0.5 then return false, "Too fast" end
	lastBuy[player] = now
	local cost = RebirthConfig.cost(p.data.Rebirths)
	if p.data.Cash < cost then return false, "Need $" .. short(cost) end
	-- single server thread, no yields: the whole reset applies at once
	p.data.Cash = 0
	p.data.Rebirths += 1
	publish(player, p)
	publishCash(player, p)
	renderAll(player, p)
	task.spawn(save, player)
	return true
end

-- Studio-only QA hook (server-side bindable, unreachable from clients): ServerStorage.DevGiveCash:Invoke(player, amount)
if RunService:IsStudio() then
	local dev = Instance.new("BindableFunction") dev.Name = "DevGiveCash"
	dev.OnInvoke = function(player, amount)
		local p = profiles[player]
		if not p then return false end
		p.data.Cash = math.min(MAX_CASH, p.data.Cash + amount)
		publishCash(player, p)
		return true
	end
	dev.Parent = game:GetService("ServerStorage")
	-- ServerStorage.DevGiveMonster:Invoke(player, "null_0|Monstrous", 3)
	local devMon = Instance.new("BindableFunction") devMon.Name = "DevGiveMonster"
	devMon.OnInvoke = function(player, k, count)
		local p = profiles[player]
		local id, variant = string.match(k, "^(.-)|(.+)$")
		if not p or not Config.ById[id] or not Config.VariantById[variant] then return false end
		p.data.Owned[k] = (p.data.Owned[k] or 0) + (count or 1)
		p.data.Discovered[id] = p.data.Discovered[id] or {}
		p.data.Discovered[id][variant] = true
		publish(player, p)
		return true
	end
	devMon.Parent = game:GetService("ServerStorage")
end

-- action = "buy" | "equip"
RS.Monster.DiceAction.OnServerInvoke = function(player, action, dieId)
	local p = profiles[player]
	if not p then return false, "Still loading" end
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < 0.2 then return false, "Too fast" end
	lastBuy[player] = now
	if typeof(dieId) ~= "string" or not DiceConfig.ById[dieId] then return false, "Unknown die" end
	local die, owned = DiceConfig.ById[dieId], p.data.Dice
	if action == "buy" then
		if owned[dieId] then return false, "Already owned" end -- never charge twice
		local prev = DiceConfig.List[DiceConfig.Index[dieId] - 1]
		if prev and not owned[prev.id] then return false, "Buy the " .. prev.name .. " first" end
		if p.data.Cash < die.cost then return false, "Need $" .. short(die.cost) end
		p.data.Cash -= die.cost
		owned[dieId] = true
		p.data.SelectedDie = dieId
	elseif action == "equip" then
		if not owned[dieId] then return false, "You don't own that die" end
		p.data.SelectedDie = dieId
	else
		return false, "Bad request"
	end
	publish(player, p)
	publishCash(player, p)
	return true
end

-- action = "open" (chestId) | "equip" (gearUid, slot) | "unequip" (gearUid)
RS.Monster.ChestAction.OnServerInvoke = function(player, action, a, b)
	local p = profiles[player]
	if not p then return false, "Still loading" end
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < 0.25 then return false, "Too fast" end
	lastBuy[player] = now
	local d = p.data
	if action == "open" then
		local chest = typeof(a) == "string" and GearConfig.ChestById[a]
		if not chest then return false, "Unknown chest" end
		if not d.Dice[chest.die] then return false, "Needs the " .. DiceConfig.ById[chest.die].name end
		local count = 0 for _ in d.Gear do count += 1 end
		if count >= MAX_GEAR then return false, "Gear bag full (" .. MAX_GEAR .. ")" end
		if d.Cash < chest.cost then return false, "Need $" .. short(chest.cost) end
		d.Cash -= chest.cost
		local rarity, gtype = GearConfig.roll(chest, rng)
		local uid = "g" .. d.NextGearId
		d.NextGearId += 1
		d.Gear[uid] = { r = rarity, t = gtype }
		publish(player, p)
		publishCash(player, p)
		return true, { uid = uid, r = rarity, t = gtype }
	end
	local g = typeof(a) == "string" and d.Gear[a]
	if not g then return false, "Unknown gear" end
	local oldSlot = g.slot
	if action == "equip" then
		if typeof(b) ~= "number" or b % 1 ~= 0 then return false, "Bad slot" end
		local sk = tostring(b)
		if not d.Placed[sk] then return false, "No monster on slot " .. sk end
		for _, other in d.Gear do -- one of each type per monster: swap out the old one
			if other ~= g and other.slot == sk and other.t == g.t then other.slot = nil end
		end
		g.slot = sk
	elseif action == "unequip" then
		g.slot = nil
	else
		return false, "Bad request"
	end
	publish(player, p)
	publishCash(player, p)
	for _, sk in { oldSlot, g.slot } do if sk then renderSlot(player, p, tonumber(sk)) end end
	return true
end

-- BATTLES: isolated per-player sessions held on the server; the client only sends action choices.
local Battle = require(script.Parent.BattleEngine)
local BattleConfig = require(RS.Monster.BattleConfig)
local battles = {} -- [Player] = { state, stage, settled }

-- team = the 3 strongest monsters on your base, with their gear and Damage/Health tree nodes applied
local function teamFor(p)
	local team = {}
	for sk, k in p.data.Placed do
		local id, variant = string.match(k, "^(.-)|(.+)$")
		local def = Config.ById[id]
		if def then
			local st = BattleConfig.monsterStats(def, variant)
			local wpn, arm, acc = 0, 0, 0
			for _, g in p.data.Gear do
				if g.slot == sk then
					local v = GearConfig.RarityById[g.r].income
					if g.t == "weapon" then wpn += v elseif g.t == "armor" then arm += v else acc += v end
				end
			end
			st.dmg = math.floor(st.dmg * (1 + wpn) * (1 + stat(p, "damage")))
			st.hp = math.floor(st.hp * (1 + arm) * (1 + stat(p, "health")))
			st.spd = math.floor(st.spd * (1 + acc))
			table.insert(team, st)
		end
	end
	table.sort(team, function(x, y) return x.hp + x.dmg * 5 > y.hp + y.dmg * 5 end)
	while #team > 3 do table.remove(team) end
	return team
end

-- pays out exactly once per battle
local function settle(player, p, b)
	if b.settled or not b.state.over then return end
	b.settled = true
	local rewards = {}
	if b.state.winner == "player" then
		local d, stage = p.data, b.stage
		d.Cash = math.min(MAX_CASH, d.Cash + stage.cash)
		table.insert(rewards, "$" .. short(stage.cash))
		if not d.BattleProgress[stage.id] then
			d.BattleProgress[stage.id] = true
			table.insert(rewards, "Stage cleared!")
			if stage.firstClearGear then
				local count = 0 for _ in d.Gear do count += 1 end
				if count < MAX_GEAR then
					local t = GearConfig.Types[rng:NextInteger(1, #GearConfig.Types)].id
					d.Gear["g" .. d.NextGearId] = { r = stage.firstClearGear, t = t }
					d.NextGearId += 1
					table.insert(rewards, stage.firstClearGear .. " " .. GearConfig.TypeById[t].name)
				else
					table.insert(rewards, "(gear bag full, boss gear skipped)")
				end
			end
		end
		publish(player, p)
		publishCash(player, p)
		task.spawn(save, player)
	end
	b.rewards = rewards
end
local function snap(b)
	local out = Battle.snapshot(b.state)
	out.stage = b.stage.name
	out.rewards = b.rewards
	return out
end

-- action = "start" (stageId) | "act" (action, targetIndex) | "leave"
RS.Monster.BattleAction.OnServerInvoke = function(player, action, a, b2)
	local p = profiles[player]
	if not p then return false, "Still loading" end
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < 0.2 then return false, "Too fast" end
	lastBuy[player] = now
	if action == "start" then
		local stage = typeof(a) == "string" and BattleConfig.StageById[a]
		if not stage then return false, "Unknown stage" end
		local prev = BattleConfig.PrevStage[stage.id]
		if prev and not p.data.BattleProgress[prev] then return false, "Clear the previous stage first" end
		local cur = battles[player]
		if cur and not cur.state.over then return false, "Finish your current battle first" end
		local team = teamFor(p)
		if #team == 0 then return false, "Place monsters on your base to form a team" end
		local bt = { state = Battle.new(team, stage.enemies, rng), stage = stage, settled = false }
		battles[player] = bt
		Battle.runEnemies(bt.state)
		settle(player, p, bt)
		return true, snap(bt)
	elseif action == "act" then
		local bt = battles[player]
		if not bt or bt.state.over then return false, "No battle running" end
		if Battle.current(bt.state).side ~= "player" then return false, "Not your turn" end
		if typeof(a) ~= "string" then return false, "Bad request" end
		local ok, err = Battle.act(bt.state, a, b2)
		if not ok then return false, err end
		Battle.runEnemies(bt.state)
		settle(player, p, bt)
		return true, snap(bt)
	elseif action == "leave" then
		battles[player] = nil -- fleeing forfeits; no rewards
		return true
	end
	return false, "Bad request"
end
Players.PlayerRemoving:Connect(function(player) battles[player] = nil end)
