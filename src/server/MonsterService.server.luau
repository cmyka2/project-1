-- Server-authoritative core loop: rolling, base placement + floors, income and offline earnings, monster upgrades,
-- inventory actions (lock/favorite/sell/fuse), skill tree, dice shop, rebirth.
-- Persistence lives in DataService, shared state/economy in Game, chests/gear in ChestService, battles in BattleService.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Http = game:GetService("HttpService")
local M = RS.Monster
local Config = require(M.MonsterConfig)
local Tree = require(M.SkillTree)
local RebirthConfig = require(M.RebirthConfig)
local DiceConfig = require(M.DiceConfig)
local MonsterModel = require(M.MonsterModel)
local Assets = require(M.AssetRegistry)
local F = require(M.Formulas)
local Traits = require(M.TraitConfig)
local Data = require(script.Parent.DataService)
local Game = require(script.Parent.Game)
local Guard = require(script.Parent.Guard)

local rng = Random.new()
local ROLL_COOLDOWN = 0.8
local FLOOR_H = 24 -- studs between generated floors
local short = Game.short

local function applyWalk(player, p)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	hum.WalkSpeed = 16 + Game.stat(p, "walkspeed") -- includes the VIP pass
	hum.UseJumpPower = true
	hum.JumpPower = 50 + Game.stat(p, "jump")
end

-- BASE: plot lookup, generated upper floors, slot rendering
local function plotOf(player)
	local id = player:GetAttribute("PlotId")
	local hub = workspace:FindFirstChild("Hub")
	local plots = hub and hub:FindFirstChild("Plots")
	return id and plots and plots:FindFirstChild("Plot" .. id)
end
-- floor 1 slots are Plot.SlotN; upper floors are Plot.Floor2/Floor3 (built in Studio or generated below)
local function slotPart(plot, i)
	local s = plot:FindFirstChild("Slot" .. i)
	if s then return s end
	for f = 2, F.MAX_FLOORS do
		local fl = plot:FindFirstChild("Floor" .. f)
		s = fl and fl:FindFirstChild("Slot" .. i)
		if s then return s end
	end
	return nil
end
local function part(parent, size, cf, color, props)
	local p = Instance.new("Part") p.Anchored = true p.Size = size p.CFrame = cf p.Color = color p.TopSurface = Enum.SurfaceType.Studs
	for k, v in props or {} do p[k] = v end
	p.Parent = parent
	return p
end
local function label(adornee, name, text, offset)
	local b = Instance.new("BillboardGui") b.Name = name b.Size = UDim2.fromScale(8, 2) b.StudsOffset = offset b.MaxDistance = 120
	local t = Instance.new("TextLabel") t.Name = "Label" t.Size = UDim2.fromScale(1, 1) t.BackgroundTransparency = 1 t.TextScaled = true
	t.Font = Enum.Font.FredokaOne t.Text = text t.TextColor3 = Color3.new(1, 1, 1) t.TextStrokeTransparency = 0 t.Parent = b
	b.Parent = adornee
	return b
end
-- placeholder deck + slot pedestals for floor f, stacked above the plot's Base
local function buildFloor(plot, f)
	local base = plot:FindFirstChild("Base")
	if not base then return end
	local c = plot:GetAttribute("Color") or base.Color
	local m = Instance.new("Model") m.Name = "Floor" .. f m:SetAttribute("Generated", true)
	local o = base.CFrame * CFrame.new(0, FLOOR_H * (f - 1), 0)
	m.PrimaryPart = part(m, Vector3.new(base.Size.X, 2, base.Size.Z), o, c:Lerp(Color3.new(1, 1, 1), 0.3), { Name = "Deck" })
	label(m.PrimaryPart, "FloorSign", "Floor " .. f .. " (placeholder)", Vector3.new(0, 8, 0))
	local ids = {}
	for i = 1, F.MAX_SLOTS do if F.slotFloor(i) == f then table.insert(ids, i) end end
	local cols = math.min(6, #ids)
	local rows = math.ceil(#ids / 6)
	for k, i in ids do
		local x, z = ((k - 1) % 6 - (cols - 1) / 2) * 12, ((k - 1) // 6 - (rows - 1) / 2) * 12
		local s = part(m, Vector3.new(8, 1, 8), o * CFrame.new(x, 1.5, z), c:Lerp(Color3.new(0, 0, 0), 0.25), { Name = "Slot" .. i })
		s:SetAttribute("SlotIndex", i) s:SetAttribute("RequiredRebirth", F.slotRebirth(i))
		label(s, "Income", "$0", Vector3.new(0, 3, 0))
	end
	m.Parent = plot
end
-- elevator pads (back of the centre walkway on every floor) with one prompt per other unlocked floor
local function floorPivot(plot, f)
	local base = plot:FindFirstChild("Base")
	return base and base.CFrame * CFrame.new(0, FLOOR_H * (f - 1) + 2, -26)
end
local function buildElevators(plot, floors)
	for _, e in plot:GetChildren() do if e.Name == "Elevator" then e:Destroy() end end
	if floors < 2 then return end
	for from = 1, floors do
		local cf = floorPivot(plot, from)
		if not cf then return end
		local pad = part(plot, Vector3.new(8, 0.4, 8), cf * CFrame.new(0, -0.8, 0), Color3.fromRGB(255, 215, 80),
			{ Name = "Elevator", Material = Enum.Material.Neon, CanCollide = false })
		for to = 1, floors do
			if to ~= from then
				local pp = Instance.new("ProximityPrompt") pp.ActionText = "Go to Floor " .. to pp.ObjectText = "Elevator"
				pp.HoldDuration = 0 pp.MaxActivationDistance = 10 pp.RequiresLineOfSight = false pp.Parent = pad
				pp.Triggered:Connect(function(who)
					local char, dest = who.Character, floorPivot(plot, to)
					if char and dest and (to == 1 or plot:FindFirstChild("Floor" .. to)) then char:PivotTo(dest + Vector3.new(0, 3, 0)) end
				end)
			end
		end
	end
end
local function ensureFloors(plot, floors)
	for f = 2, F.MAX_FLOORS do
		local fl = plot:FindFirstChild("Floor" .. f)
		if f <= floors and not fl then buildFloor(plot, f)
		elseif f > floors and fl and fl:GetAttribute("Generated") then fl:Destroy() end
	end
	if plot:GetAttribute("BuiltFloors") ~= floors then
		plot:SetAttribute("BuiltFloors", floors)
		buildElevators(plot, floors)
	end
end

-- p = nil clears the slot. A placement whose model is missing keeps its record and shows a placeholder.
local function renderSlot(player, p, i)
	local plot = plotOf(player)
	local slot = plot and slotPart(plot, i)
	if not slot then return end
	local shown = plot:FindFirstChild("Placed") or Instance.new("Folder")
	shown.Name = "Placed" shown.Parent = plot
	for _, g in slot:GetChildren() do -- "Rebirth N" lock signs, hidden once unlocked
		if g:IsA("BillboardGui") and g.Name ~= "Income" then g.Enabled = not (p and i <= Game.slotCount(p)) end
	end
	local iid = p and p.data.Placed[tostring(i)]
	local inst = iid and p.data.Monsters[iid]
	local pad = plot:FindFirstChild("Collect" .. i) or slot:FindFirstChild("Income")
	local text = pad and pad:FindFirstChild("Label", true)
	if text then text.Text = inst and ("$" .. short(Game.income(p, iid)) .. "/s") or "$0" end
	local old = shown:FindFirstChild("Slot" .. i)
	if old and not (inst and old:GetAttribute("Iid") == iid) then old:Destroy() old = nil end
	if not inst then return end
	local def = Config.ById[inst.id]
	local m = old
	if not m then
		m = def and MonsterModel.build(def, inst.v) or Assets.CreateAsset("Monsters", inst.id, nil, Vector3.new(4, 4, 4))
		m.Name = "Slot" .. i
		m:SetAttribute("Iid", iid)
		local top = slot.Position + Vector3.new(0, slot.Size.Y / 2, 0)
		m:PivotTo(CFrame.lookAt(top, top - slot.CFrame.LookVector) * CFrame.new(0, def and 0 or 2, 0))
		m.Parent = shown
	end
	-- floating name / level / income tag over the pedestal (visible to everyone visiting the base)
	local info = m:FindFirstChild("Info")
	if not info then
		local _, size = m:GetBoundingBox()
		info = Instance.new("BillboardGui") info.Name = "Info" info.Size = UDim2.fromOffset(170, 54) info.MaxDistance = 70
		info.StudsOffsetWorldSpace = Vector3.new(0, size.Y + 1.5, 0) info.Adornee = m.PrimaryPart
		for k, h in { 0.42, 0.29, 0.29 } do
			local t = Instance.new("TextLabel") t.Name = "L" .. k t.Size = UDim2.fromScale(1, h) t.Position = UDim2.fromScale(0, k == 1 and 0 or (k == 2 and 0.42 or 0.71))
			t.BackgroundTransparency = 1 t.TextScaled = true t.Font = Enum.Font.FredokaOne t.TextStrokeTransparency = 0 t.Parent = info
		end
		info.Parent = m
	end
	local rar = def and Config.RarityById[def.rarity]
	local mut, trait = inst.mu and Traits.MutationById[inst.mu], inst.tr and Traits.TraitById[inst.tr]
	info.L1.Text = (mut and mut.name .. " " or "") .. (inst.v ~= "Normal" and inst.v:upper() .. " " or "") .. (def and def.name or inst.id)
	info.L1.TextColor3 = mut and mut.color or (rar and rar.color or Color3.new(1, 1, 1))
	info.L2.Text = (def and def.rarity or "?") .. "  •  Lv " .. inst.lvl .. (inst.fr > 0 and ("  ★" .. inst.fr) or "") .. (trait and ("  •  " .. trait.name) or "")
	info.L2.TextColor3 = Color3.fromRGB(230, 230, 240)
	info.L3.Text = "$" .. short(Game.income(p, iid)) .. "/s"
	info.L3.TextColor3 = Color3.fromRGB(120, 255, 120)
end
local function renderAll(player, p)
	local plot = plotOf(player)
	if not plot then return end
	if not p then
		local shown = plot:FindFirstChild("Placed")
		if shown then shown:ClearAllChildren() end
	end
	ensureFloors(plot, p and F.floors(p.data.Rebirths) or 1)
	for i = 1, F.MAX_SLOTS do renderSlot(player, p, i) end
end
Game.BaseChanged.Event:Connect(function(player)
	local p = Game.get(player)
	if p then renderAll(player, p) end
end)

-- JOIN: leaderstats, offline earnings from saved server timestamps, first publish
Data.onLoaded(function(player, p)
	local ls = Instance.new("Folder") ls.Name = "leaderstats"
	local cash = Instance.new("NumberValue") cash.Name = "Cash" cash.Parent = ls
	local reb = Instance.new("IntValue") reb.Name = "Rebirths" reb.Parent = ls
	ls.Parent = player
	local d = p.data
	if d.LastOnline then
		local amount, secs = F.offline(os.time() - d.LastOnline, Game.incomePerSec(p, true), Game.offlineCap(p))
		if amount > 0 then
			Game.addCash(p, amount)
			local s = Game.state(player)
			if s then s:SetAttribute("OfflineEarnings", Http:JSONEncode({ amount = amount, secs = secs })) end
		end
	end
	Game.publish(player, p)
	player.CharacterAdded:Connect(function() task.defer(applyWalk, player, p) end)
	applyWalk(player, p)
	player:GetAttributeChangedSignal("PlotId"):Connect(function() renderAll(player, Game.get(player)) end)
	renderAll(player, p)
end)
Players.PlayerRemoving:Connect(function(player) renderAll(player, nil) end)

-- INCOME: one loop for everyone, 1 s ticks
task.spawn(function()
	while true do
		task.wait(1)
		for player, p in Data.all() do
			if not p.released then
				Game.addCash(p, Game.incomePerSec(p))
				Game.publishCash(player, p)
			end
		end
	end
end)

-- ROLLING (summon prompt; the server picks the result)
-- the reveal model pops up on the summon station when rolled there, otherwise in front of the player
local function showRoll(player, core, def, variant)
	local root = player.Character and player.Character.PrimaryPart
	if not core and not root then return end
	local m = MonsterModel.build(def, variant)
	local pos = core and core.Position + Vector3.new(0, 1, 0) or root.Position + root.CFrame.LookVector * 10 - Vector3.new(0, 3, 0)
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

local Announce = M.Announce
local Mon = require(M.MonetizationConfig)
local MessagingService = game:GetService("MessagingService")
local GLOBAL_TIER = Config.Tier.Secret -- Secret+ rolls are announced in every server
-- awards one rolled monster; returns the result entry for LastRoll
local function grant(player, p, core, def, variant, special)
	local mu = Traits.rollMutation(rng, Game.biome and Game.biome.id)
	local iid, isNew = Game.addMonster(p, def, variant, mu)
	if isNew and Game.stat(p, "discovery") > 0 then -- Discovery Streak
		Game.addCash(p, math.max(100, Game.incomePerSec(p) * Game.stat(p, "discovery")))
	end
	local tier = Config.Tier[def.rarity]
	if tier >= 5 or variant ~= "Normal" then Data.saveSoon(player) end
	if tier >= 6 or variant == "Monstrous" then
		local text = ("%s rolled %s%s (%s)!"):format(player.DisplayName, variant ~= "Normal" and variant:upper() .. " " or "", def.name, def.rarity)
		Announce:FireAllClients(text, def.rarity)
		if tier >= GLOBAL_TIER then
			task.spawn(pcall, MessagingService.PublishAsync, MessagingService, "RareRolls", { text = text, rarity = def.rarity, job = game.JobId })
		end
	end
	showRoll(player, core, def, variant)
	return { id = def.id, v = variant, mu = mu, new = isNew, iid = iid, special = special, tier = tier }
end
task.spawn(function() -- other servers' Secret+ rolls
	pcall(MessagingService.SubscribeAsync, MessagingService, "RareRolls", function(msg)
		local m = msg.Data
		if typeof(m) == "table" and m.job ~= game.JobId and typeof(m.text) == "string" then
			Announce:FireAllClients("🌐 " .. m.text, m.rarity)
		end
	end)
end)

-- one roll press: Triple Roll pass rolls up to 3; each roll may be Golden (every 10th), Rainbow (every 100th)
-- or use a banked Lucky Roll (10x). Everything is decided here; the client only animates LastRoll.
local function roll(player, core)
	local p = Game.get(player)
	if not p then return end
	if not Guard.rate(player, "roll", ROLL_COOLDOWN * (1 - math.min(0.75, Game.stat(p, "rollspeed")))) then return end
	local d = p.data
	if Game.count(d.Monsters) >= Game.capacity(p) then
		Game.notify(player, "Backpack full (" .. Game.capacity(p) .. "). Sell or fuse monsters to roll again.")
		return
	end
	local die = Game.die(p)
	if not d.Dice[die.id] then d.SelectedDie = "grassland" die = Game.die(p) end
	local results, biome = {}, Game.biomeBoost()
	local function once(bonusRoll)
		if Game.count(d.Monsters) >= Game.capacity(p) then return end
		local extra, special = 1, nil
		if not bonusRoll then
			d.Rolls += 1
			if d.Rolls % Mon.RAINBOW_EVERY == 0 then extra, special = Mon.RAINBOW_MULT, "rainbow"
			elseif d.Rolls % Mon.GOLDEN_EVERY == 0 then extra, special = Mon.GOLDEN_MULT, "golden" end
			if d.LuckyRolls > 0 and d.Settings.useLucky ~= false then
				d.LuckyRolls -= 1
				extra *= Mon.LUCKY_ROLL_MULT
				special = special and (special .. "+lucky") or "lucky"
			end
		end
		local def, variant = Config.roll(rng, Game.luck(p, extra), die.maxTier, die.id, biome)
		if not def then warn("Empty roll pool for die", die.id) return end
		table.insert(results, grant(player, p, core, def, variant, special))
	end
	for _ = 1, math.max(1, Mon.passStat(p.passes or {}, "multiRoll")) do once(false) end
	if rng:NextNumber() < Game.stat(p, "double") then once(true) end -- Double Fortune
	if #results == 0 then return end
	-- LastRoll: the rarest result leads, the rest ride along
	table.sort(results, function(a, b) return a.tier > b.tier end)
	local s = Game.state(player)
	if s then
		local best = results[1]
		best.n, best.more = d.Rolls, {}
		for k = 2, #results do table.insert(best.more, { id = results[k].id, v = results[k].v, mu = results[k].mu, new = results[k].new }) end
		s:SetAttribute("LastRoll", Http:JSONEncode(best))
	end
	Game.publish(player, p, "Index", "Monsters", "Progress")
	Game.Changed:Fire(player)
end
local summonCore
local function nearSummon(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return summonCore and root and (root.Position - summonCore.Position).Magnitude <= 25
end
task.spawn(function() -- the summon station may be a placeholder made by HubFallback; don't block the remotes below
	local summon = workspace:WaitForChild("Hub"):WaitForChild("Shops"):WaitForChild("SummonArea"):WaitForChild("SummonCore")
	summonCore = summon
	summon:WaitForChild("ProximityPrompt").Triggered:Connect(function(player) roll(player, summon) end)
end)
-- HUD roll button and auto-roll (Auto Pickup node / Auto Roll pass) work anywhere, like other RNG games;
-- both go through roll(), so they share its cooldown and checks with the station prompt
local auto = {} -- [Player] = true while auto-roll is on (session only)
M.RollAction.OnServerInvoke = function(player, action, on)
	local p = Game.get(player)
	if not p then return false, "Still loading" end
	if action == "roll" then
		roll(player, nearSummon(player) and summonCore or nil)
		return true
	elseif action == "auto" then
		if on == true and Game.stat(p, "autoroll") <= 0 then return false, "Unlock Auto Pickup in the Evolution Tree" end
		auto[player] = on == true or nil
		return true
	end
	return false, "Bad request"
end
Players.PlayerRemoving:Connect(function(player) auto[player] = nil end)
task.spawn(function()
	while true do
		task.wait(0.25)
		for player in auto do roll(player, nearSummon(player) and summonCore or nil) end
	end
end)

-- PLACEMENT: iid = nil removes whatever is on the slot
M.PlaceMonster.OnServerInvoke = function(player, slot, iid)
	local p = Game.get(player)
	if not p then return false, "Still loading" end
	if not Guard.rate(player, "place", 0.15) then return false, "Too fast" end
	slot = Guard.int(slot, 1, F.MAX_SLOTS)
	if not slot then return false, "Bad slot" end
	if slot > Game.slotCount(p) then return false, "Unlocks at Rebirth " .. F.slotRebirth(slot) end
	if not plotOf(player) then return false, "You don't have a plot" end
	local placed, sk = p.data.Placed, tostring(slot)
	if iid == nil then
		placed[sk] = nil
	else
		iid = Guard.str(iid)
		if not iid or not p.data.Monsters[iid] then return false, "You don't own that monster" end
		if placed[sk] == iid then return true end
		if placed[sk] then return false, "That slot is taken" end
		local other = Game.slotOf(p, iid)
		if other then return false, "Already placed on slot " .. other end
		placed[sk] = iid
	end
	Game.publish(player, p, "Placed", "Progress")
	Game.Changed:Fire(player)
	renderSlot(player, p, slot)
	Data.saveSoon(player)
	return true
end

-- INVENTORY: upgrade | lock | fav | sell | fuse | trait (reroll, Gems) | upfuse (Fuse Machine: 5 of a rarity -> next rarity)
local UPFUSE_COUNT = 5
local function owned(p, iid) iid = Guard.str(iid) return iid and p.data.Monsters[iid], iid end
local function nameOf(inst)
	local def = Config.ById[inst.id]
	return (inst.v ~= "Normal" and inst.v .. " " or "") .. (def and def.name or inst.id)
end
local function copies(p, inst)
	local n = 0
	for _, m in p.data.Monsters do if m.id == inst.id and m.v == inst.v then n += 1 end end
	return n
end
M.InventoryAction.OnServerInvoke = function(player, action, a, b)
	local p = Game.get(player)
	if not p then return false, "Still loading" end
	if not Guard.rate(player, "inventory", 0.15) then return false, "Too fast" end
	local d = p.data
	if action == "upgrade" then
		local inst, iid = owned(p, a)
		if not inst then return false, "You don't own that monster" end
		if inst.lvl >= F.MAX_LEVEL then return false, "Max level" end
		local cost = Game.upgradeCost(p, inst)
		if not Game.spend(p, cost) then return false, "Need $" .. short(cost) end
		inst.lvl += 1
		Game.bump(p, "upgrades")
		Game.publish(player, p, "Monsters", "Progress")
		local sk = Game.slotOf(p, iid)
		if sk then renderSlot(player, p, tonumber(sk)) end
		return true
	elseif action == "lock" or action == "fav" then
		local inst = owned(p, a)
		if not inst then return false, "You don't own that monster" end
		inst[action] = b == true or nil
		Game.publish(player, p, "Monsters")
		return true
	elseif action == "sell" then
		local ids = Guard.ids(a, 100)
		if not ids then return false, "Bad request" end
		local total, selling = 0, {}
		for _, iid in ids do -- validate everything before touching anything
			local inst = d.Monsters[iid]
			if not inst then return false, "You don't own that monster" end
			if inst.lock then return false, nameOf(inst) .. " is locked" end
			if Game.slotOf(p, iid) then return false, "Remove " .. nameOf(inst) .. " from your base first" end
			local k = inst.id .. "|" .. inst.v
			selling[k] = (selling[k] or 0) + 1
			local def = Config.ById[inst.id]
			if b ~= true and def and Config.Tier[def.rarity] >= 3 and selling[k] >= copies(p, inst) then
				return false, "That's your last " .. nameOf(inst) .. ". Sell anyway?", "confirm"
			end
			total += F.sellValue(Game.baseIncome(inst), inst.lvl, Game.stat(p, "sell"))
		end
		for _, iid in ids do Game.removeMonster(p, iid) end
		Game.addCash(p, total)
		Game.publish(player, p, "Monsters", "Index", "Team", "Gear")
		Data.saveSoon(player)
		return true, total
	elseif action == "fuse" then
		local target, tid = owned(p, a)
		local need = Game.fuseCopies(p) - 1
		local mats = Guard.ids(b, need)
		if not target then return false, "You don't own that monster" end
		if not mats or #mats ~= need then return false, "Pick " .. need .. " copies to fuse in" end
		if target.fr >= F.MAX_FUSION then return false, "Max fusion rank" end
		for _, iid in mats do
			local inst = d.Monsters[iid]
			if iid == tid or not inst then return false, "Bad fusion copies" end
			if inst.id ~= target.id or inst.v ~= target.v then return false, "Copies must be the same monster and variant" end
			if inst.lock then return false, nameOf(inst) .. " is locked" end
			if Game.slotOf(p, iid) then return false, "Remove the copies from your base first" end
		end
		local cost = Game.fuseCost(p, target)
		if not Game.spend(p, cost) then return false, "Need $" .. short(cost) end
		for _, iid in mats do Game.removeMonster(p, iid) end
		target.fr += 1
		Game.bump(p, "fusions")
		Game.publish(player, p, "Monsters", "Index", "Team", "Gear")
		local sk = Game.slotOf(p, tid)
		if sk then renderSlot(player, p, tonumber(sk)) end
		Data.saveSoon(player)
		return true
	elseif action == "trait" then -- reroll the trait for Gems (Anime Dice style)
		local inst = owned(p, a)
		if not inst then return false, "You don't own that monster" end
		if d.Gems < Traits.TRAIT_COST then return false, "Need " .. Traits.TRAIT_COST .. " Gem" end
		d.Gems -= Traits.TRAIT_COST
		inst.tr = Traits.rollTrait(rng)
		Game.publish(player, p, "Monsters")
		Game.BaseChanged:Fire(player)
		Data.saveSoon(player)
		return true, inst.tr
	elseif action == "upfuse" then -- Fuse Machine: 5 monsters of one rarity become 1 random monster of the next rarity
		local ids = Guard.ids(a, UPFUSE_COUNT)
		if not ids or #ids ~= UPFUSE_COUNT then return false, "Pick " .. UPFUSE_COUNT .. " monsters of the same rarity" end
		local tier
		for _, iid in ids do
			local inst = d.Monsters[iid]
			local def = inst and Config.ById[inst.id]
			if not def then return false, "You don't own that monster" end
			if inst.lock then return false, nameOf(inst) .. " is locked" end
			if Game.slotOf(p, iid) then return false, "Remove " .. nameOf(inst) .. " from your base first" end
			local t = Config.Tier[def.rarity]
			if tier and t ~= tier then return false, "All " .. UPFUSE_COUNT .. " must be the same rarity" end
			tier = t
		end
		if tier >= #Config.Rarities then return false, "Already the top rarity" end
		local pool = {}
		for _, def in Config.Pools[Config.Rarities[tier + 1].id] or {} do
			if not def.dice or table.find(def.dice, d.SelectedDie) or d.Dice.glitch then table.insert(pool, def) end
		end
		if #pool == 0 then return false, "Nothing to fuse into yet" end
		for _, iid in ids do Game.removeMonster(p, iid) end
		local def = pool[rng:NextInteger(1, #pool)]
		local iid = Game.addMonster(p, def, "Normal", nil)
		Game.bump(p, "fusions")
		Game.publish(player, p, "Monsters", "Index", "Team", "Gear", "Progress")
		Data.saveSoon(player)
		return true, { id = def.id, iid = iid }
	end
	return false, "Bad request"
end

-- EVOLUTION TREE (cash) / ASCENSION TREE (AP): nodeId, tree = nil | "ascension"; nodeId "respec" refunds the
-- Evolution Tree at RESPEC_REFUND of the cash spent
local RESPEC_REFUND = 0.75
M.BuySkill.OnServerInvoke = function(player, nodeId, tree)
	local p = Game.get(player)
	if not p then return false, "Still loading" end
	if not Guard.rate(player, "skill", 0.2) then return false, "Too fast" end
	local d = p.data
	if nodeId == "respec" then
		if not Guard.rate(player, "respec", 5) then return false, "Too fast" end
		local refund = math.floor(d.SkillSpent * RESPEC_REFUND)
		d.Skills, d.SkillSpent = { start = 1 }, 0
		Game.addCash(p, refund)
		Game.dropRelics(p)
		Game.publish(player, p)
		applyWalk(player, p)
		auto[player] = nil
		renderAll(player, p)
		Data.saveSoon(player)
		return true, refund
	end
	local asc = tree == "ascension"
	local node = Guard.str(nodeId) and (asc and Tree.AscById or Tree.ById)[nodeId]
	if not node then return false, "Unknown upgrade" end
	local owned = asc and d.Ascension or d.Skills
	local rank = owned[nodeId] or 0
	local why = Tree.blocked(node, owned, d.Rebirths)
	if why then return false, why end
	local cost = Tree.cost(node, rank)
	if asc then
		if d.AscensionPoints < cost then return false, "Need " .. cost .. " Ascension Points" end
		d.AscensionPoints -= cost
	else
		if not Game.spend(p, cost) then return false, "Need $" .. short(cost) end
		d.SkillSpent += cost
	end
	owned[nodeId] = rank + 1
	Game.publish(player, p) -- income/luck/combat previews all move
	applyWalk(player, p)
	renderAll(player, p) -- pad income labels
	Data.saveSoon(player)
	return true
end

-- DICE SHOP: action = "buy" | "equip"
M.DiceAction.OnServerInvoke = function(player, action, dieId)
	local p = Game.get(player)
	if not p then return false, "Still loading" end
	if not Guard.rate(player, "dice", 0.2) then return false, "Too fast" end
	local die = Guard.str(dieId) and DiceConfig.ById[dieId]
	if not die then return false, "Unknown die" end
	local owned = p.data.Dice
	if action == "buy" then
		if owned[dieId] then return false, "Already owned" end -- never charge twice
		local prev = DiceConfig.List[DiceConfig.Index[dieId] - 1]
		if prev and not owned[prev.id] then return false, "Buy the " .. prev.name .. " first" end
		if die.rebirth and p.data.Rebirths < die.rebirth then return false, "Unlocks at Rebirth " .. die.rebirth end
		if not Game.spend(p, die.cost) then return false, "Need $" .. short(die.cost) end
		owned[dieId] = true
		p.data.SelectedDie = dieId
		Data.saveSoon(player)
	elseif action == "equip" then
		if not owned[dieId] then return false, "You don't own that die" end
		p.data.SelectedDie = dieId
	else
		return false, "Bad request"
	end
	Game.publish(player, p, "Dice")
	return true
end

-- REBIRTH: requirement check and the whole reset happen in one non-yielding step
M.Rebirth.OnServerInvoke = function(player)
	local p = Game.get(player)
	if not p then return false, "Still loading" end
	if not Guard.rate(player, "rebirth", 1) then return false, "Too fast" end
	local d = p.data
	local req = RebirthConfig.requirement(d.Rebirths)
	if req.stage and not d.BattleProgress[req.stage] then return false, "Defeat the Overgrown Brute first" end
	local have = 0
	for _, m in d.Monsters do
		local def = Config.ById[m.id]
		if def and Config.Tier[def.rarity] >= req.minTier then have += 1 end
	end
	if have < req.count then return false, ("Own %d %s+ monsters first (%d/%d)"):format(req.count, Config.Rarities[req.minTier].id, have, req.count) end
	if not Game.spend(p, req.cost) then return false, "Need $" .. short(req.cost) end
	local ap = RebirthConfig.apply(d)
	Game.addCash(p, Game.stat(p, "startcash")) -- Head Start
	Game.bump(p, "rebirths")
	Game.publish(player, p)
	renderAll(player, p)
	Data.saveSoon(player)
	return true, { ap = ap, slots = Game.slotCount(p), floors = F.floors(d.Rebirths) }
end

-- Studio-only QA hooks (server-side bindables, unreachable from clients), e.g. from the command bar:
-- ServerStorage.DevGiveCash:Invoke(player, 1e6)  ServerStorage.DevGiveMonster:Invoke(player, "null_0|Monstrous", 3)
-- ServerStorage.DevSetRebirths:Invoke(player, 12)
if RunService:IsStudio() then
	local SS = game:GetService("ServerStorage")
	local function hook(name, fn)
		local b = Instance.new("BindableFunction") b.Name = name
		b.OnInvoke = function(player, ...)
			local p = Game.get(player)
			if not p then return false end
			fn(p, ...)
			Game.publish(player, p)
			renderAll(player, p)
			return true
		end
		b.Parent = SS
	end
	hook("DevGiveCash", function(p, amount) Game.addCash(p, amount) end)
	hook("DevGiveMonster", function(p, k, count)
		local id, variant = string.match(k, "^(.-)|(.+)$")
		if not Config.ById[id] or not Config.VariantById[variant] then return end
		for _ = 1, count or 1 do Game.addMonster(p, Config.ById[id], variant) end
	end)
	hook("DevSetRebirths", function(p, n) p.data.Rebirths = math.max(0, math.floor(n)) end)
end
