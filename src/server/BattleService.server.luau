-- BATTLES: isolated per-player sessions held on the server; the client only sends action choices.
-- action = "start" (stageId) | "act" (action, targetIndex) | "leave" | "team" ({ iid, ... } up to 3)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local M = RS.Monster
local BattleConfig = require(M.BattleConfig)
local GearConfig = require(M.GearConfig)
local DiceConfig = require(M.DiceConfig)
local Battle = require(script.Parent.BattleEngine)
local Data = require(script.Parent.DataService)
local Game = require(script.Parent.Game)
local Guard = require(script.Parent.Guard)
local rng = Random.new()
local battles = {} -- [Player] = { state, stage, settled, rewards }

local function power(st) return st.hp + st.dmg * 5 end
-- the saved team if it has any monsters left, otherwise the 3 strongest owned monsters
local function teamFor(p)
	local team = {}
	for _, iid in p.data.BattleTeams[1] or {} do
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
			d.Materials[mat] = (d.Materials[mat] or 0) + n
			table.insert(rewards, n .. " " .. GearConfig.MaterialById[mat].name)
		end
		if not d.BattleProgress[stage.id] then
			d.BattleProgress[stage.id] = true
			table.insert(rewards, "Stage cleared!")
			if stage.firstClearGear then
				local t = GearConfig.Types[rng:NextInteger(1, #GearConfig.Types)].id
				if Game.addGear(p, stage.firstClearGear, t) then
					table.insert(rewards, stage.firstClearGear .. " " .. GearConfig.TypeById[t].name)
				else
					table.insert(rewards, "(gear bag full, boss gear skipped)")
				end
			end
		end
		Game.publish(player, p, "BattleProgress", "Materials", "Gear")
		Data.saveSoon(player)
	end
	b.rewards = rewards
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
		local bt = { state = Battle.new(team, stage.enemies, rng), stage = stage, settled = false }
		battles[player] = bt
		Battle.runEnemies(bt.state)
		settle(player, p, bt)
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
		return true, snap(bt)
	elseif action == "leave" then
		battles[player] = nil -- fleeing forfeits; no rewards
		return true
	elseif action == "team" then
		local ids = a == nil and {} or Guard.ids(a, Game.TEAM_SIZE)
		if not ids then return false, "Bad team" end
		for _, iid in ids do
			if not p.data.Monsters[iid] then return false, "You don't own that monster" end
		end
		p.data.BattleTeams[1] = table.clone(ids)
		Game.publish(player, p, "Team")
		return true
	end
	return false, "Bad request"
end
Players.PlayerRemoving:Connect(function(player) battles[player] = nil end)
