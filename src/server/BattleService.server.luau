-- BATTLES: isolated per-player sessions held on the server; the client only sends action choices.
-- Each battle also gets its own placeholder 3D arena far from the hub (AssetRegistry Arenas/Enemies/Bosses),
-- so players never share or disturb each other's fights.
-- action = "start" (stageId) | "act" (action, targetIndex) | "leave" | "team" ({ iid, ... } up to 3, preset?) | "preset" (n)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local M = RS.Monster
local BattleConfig = require(M.BattleConfig)
local GearConfig = require(M.GearConfig)
local DiceConfig = require(M.DiceConfig)
local Config = require(M.MonsterConfig)
local MonsterModel = require(M.MonsterModel)
local Assets = require(M.AssetRegistry)
local Battle = require(script.Parent.BattleEngine)
local Data = require(script.Parent.DataService)
local Game = require(script.Parent.Game)
local Guard = require(script.Parent.Guard)
local rng = Random.new()
local battles = {} -- [Player] = { state, stage, settled, rewards }

local function power(st) return st.hp + st.dmg * 5 end
-- the active preset if it has any monsters left, otherwise the 3 strongest owned monsters
local function teamFor(p)
	local team = {}
	for _, iid in Game.team(p) do
		local st = Game.combat(p, iid)
		if st then table.insert(team, st) end
	end
	if #team > 0 then return team end
	for iid in p.data.Monsters do table.insert(team, Game.combat(p, iid)) end
	table.sort(team, function(x, y) return power(x) > power(y) end)
	while #team > Game.TEAM_SIZE do table.remove(team) end
	return team
end

-- pays out exactly once per battle
local function settle(player, p, b)
	if b.settled or not b.state.over then return end
	b.settled = true
	local rewards = {}
	if b.state.winner == "player" then
		local d, stage = p.data, b.stage
		Game.addCash(p, stage.cash)
		table.insert(rewards, "$" .. Game.short(stage.cash))
		for mat, n in stage.mats or {} do
			n = math.floor(n * (1 + Game.stat(p, "research"))) -- Research Lab
			d.Materials[mat] = (d.Materials[mat] or 0) + n
			table.insert(rewards, n .. " " .. GearConfig.MaterialById[mat].name)
		end
		d.Gems += 1
		table.insert(rewards, "1 Gem")
		Game.bump(p, "wins")
		if stage.boss then Game.bump(p, "bosses") end
		if not d.BattleProgress[stage.id] then
			d.BattleProgress[stage.id] = true
			table.insert(rewards, "Stage cleared!")
			if stage.boss then d.Gems += 10 table.insert(rewards, "10 Gems") end
			if stage.firstClearGear then
				local t = GearConfig.Types[rng:NextInteger(1, #GearConfig.Types)].id
				if Game.addGear(p, stage.firstClearGear, t) then
					table.insert(rewards, stage.firstClearGear .. " " .. GearConfig.TypeById[t].name)
				else
					table.insert(rewards, "(gear bag full, boss gear skipped)")
				end
			end
		end
		Game.publish(player, p, "BattleProgress", "Materials", "Gear", "Progress")
		Data.saveSoon(player)
	end
	b.rewards = rewards
end
-- ARENAS: one slot per running battle, spaced far apart above the ocean
local ARENA_ORIGIN, ARENA_GAP = Vector3.new(0, 600, 4000), 400
local arenaFolder = workspace:FindFirstChild("Arenas") or Instance.new("Folder")
arenaFolder.Name = "Arenas"
arenaFolder.Parent = workspace
local usedSlots = {}
local function closeArena(player, b)
	local a = b and b.arena
	if not a then return end
	b.arena = nil
	usedSlots[a.slot] = nil
	a.model:Destroy()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and a.back then player.Character:PivotTo(a.back) end
end
local function openArena(player, p, b)
	local slot = 1
	while usedSlots[slot] do slot += 1 end
	usedSlots[slot] = true
	local origin = CFrame.new(ARENA_ORIGIN + Vector3.new(slot * ARENA_GAP, 0, 0))
	local region = BattleConfig.RegionOf[b.stage.id]
	local m = Instance.new("Model") m.Name = "Arena_" .. player.UserId
	local env = Assets.CreateAsset("Arenas", region.id .. "_arena", m, Vector3.new(140, 4, 90))
	env:PivotTo(origin)
	local units, sides = {}, { player = {}, enemy = {} }
	for i, u in b.state.units do table.insert(sides[u.side], i) end
	for side, list in sides do
		local z = side == "player" and 18 or -18
		for k, i in ipairs(list) do
			local u = b.state.units[i]
			local inst = u.iid and p.data.Monsters[u.iid]
			local def = inst and Config.ById[inst.id]
			local model = def and MonsterModel.build(def, inst.v)
				or Assets.CreateAsset(u.boss and "Bosses" or "Enemies", BattleConfig.enemyId(u.name), nil, u.boss and Vector3.new(10, 12, 10) or Vector3.new(5, 6, 5))
			local pos = origin * CFrame.new((k - (#list + 1) / 2) * 16, 2, z)
			model:PivotTo(CFrame.lookAt(pos.Position, (origin * CFrame.new(0, 2, -z)).Position))
			model.Parent = m
			units[i] = model
		end
	end
	m.Parent = arenaFolder
	local char = player.Character
	b.arena = { model = m, slot = slot, units = units, back = char and char:GetPivot() }
	if char then char:PivotTo(CFrame.lookAt((origin * CFrame.new(0, 8, 42)).Position, origin.Position)) end
end
-- knocked-out units leave the arena
local function syncArena(b)
	if not b.arena then return end
	for i, u in b.state.units do
		local model = b.arena.units[i]
		if model and not u.alive then model:Destroy() b.arena.units[i] = nil end
	end
end

local function snap(b)
	local out = Battle.snapshot(b.state)
	out.stage = b.stage.name
	out.rewards = b.rewards
	return out
end

M.BattleAction.OnServerInvoke = function(player, action, a, b2)
	local p = Game.get(player)
	if not p then return false, "Still loading" end
	if not Guard.rate(player, "battle", 0.2) then return false, "Too fast" end
	if action == "start" then
		local stage = Guard.str(a) and BattleConfig.StageById[a]
		if not stage then return false, "Unknown stage" end
		local prev = BattleConfig.PrevStage[stage.id]
		if prev and not p.data.BattleProgress[prev] then return false, "Clear the previous stage first" end
		local region = BattleConfig.RegionOf[stage.id]
		if region.requiresDie and not p.data.Dice[region.requiresDie] then
			return false, region.name .. " needs the " .. DiceConfig.ById[region.requiresDie].name
		end
		local cur = battles[player]
		if cur and not cur.state.over then return false, "Finish your current battle first" end
		local team = teamFor(p)
		if #team == 0 then return false, "Roll some monsters to form a team" end
		closeArena(player, cur)
		local bt = { state = Battle.new(team, stage.enemies, rng), stage = stage, settled = false }
		battles[player] = bt
		openArena(player, p, bt)
		Battle.runEnemies(bt.state)
		settle(player, p, bt)
		syncArena(bt)
		return true, snap(bt)
	elseif action == "act" then
		local bt = battles[player]
		if not bt or bt.state.over then return false, "No battle running" end
		if Battle.current(bt.state).side ~= "player" then return false, "Not your turn" end
		if not Guard.str(a) then return false, "Bad request" end
		local ok, err = Battle.act(bt.state, a, Guard.int(b2, 1, #bt.state.units))
		if not ok then return false, err end
		Battle.runEnemies(bt.state)
		settle(player, p, bt)
		syncArena(bt)
		return true, snap(bt)
	elseif action == "leave" then
		closeArena(player, battles[player])
		battles[player] = nil -- fleeing forfeits; no rewards
		return true
	elseif action == "team" then
		local ids = a == nil and {} or Guard.ids(a, Game.TEAM_SIZE)
		local k = b2 == nil and math.min(p.data.ActiveTeam, Game.presets(p)) or Guard.int(b2, 1, Game.presets(p))
		if not ids then return false, "Bad team" end
		if not k then return false, "That preset is locked" end
		for _, iid in ids do
			if not p.data.Monsters[iid] then return false, "You don't own that monster" end
		end
		local teams = p.data.BattleTeams
		for i = #teams + 1, k do teams[i] = {} end -- keep the list dense (saves/JSON need arrays)
		teams[k] = table.clone(ids)
		Game.publish(player, p, "Team", "Teams")
		return true
	elseif action == "preset" then
		local k = Guard.int(a, 1, Game.presets(p))
		if not k then return false, "That preset is locked" end
		p.data.ActiveTeam = k
		Game.publish(player, p, "Team", "Teams")
		return true
	end
	return false, "Bad request"
end
Players.PlayerRemoving:Connect(function(player)
	closeArena(player, battles[player])
	battles[player] = nil
end)
