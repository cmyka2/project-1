-- Chest shop (server-rolled gear), equipping gear onto monster instances, and crafting from battle materials.
-- action = "open" (chestId, count 1-10) | "equip" (gearUid, monster iid) | "unequip" (gearUid) | "craft" (recipeId)
--        | "upgrade" (gearUid): +1 level (+10% power) for cash, up to GearConfig.MAX_LEVEL
local RS = game:GetService("ReplicatedStorage")
local M = RS.Monster
local GearConfig = require(M.GearConfig)
local DiceConfig = require(M.DiceConfig)
local Data = require(script.Parent.DataService)
local Game = require(script.Parent.Game)
local Guard = require(script.Parent.Guard)
local rng = Random.new()
local MAX_BATCH = 10

M.ChestAction.OnServerInvoke = function(player, action, a, b)
	local p = Game.get(player)
	if not p then return false, "Still loading" end
	if not Guard.rate(player, "chest", 0.25) then return false, "Too fast" end
	local d = p.data
	if action == "open" then
		local chest = Guard.str(a) and GearConfig.ChestById[a]
		local count = b == nil and 1 or Guard.int(b, 1, MAX_BATCH)
		if not chest then return false, "Unknown chest" end
		if not count then return false, "Bad amount" end
		if not d.Dice[chest.die] then return false, "Needs the " .. DiceConfig.ById[chest.die].name end
		if Game.count(d.Gear) + count > Game.MAX_GEAR then return false, "Gear bag full (" .. Game.MAX_GEAR .. ")" end
		local price = Game.chestCost(p, chest) * count
		if not Game.spend(p, price) then return false, "Need $" .. Game.short(price) end
		-- paid and granted in the same non-yielding step: exactly once, whatever the client does next
		local got = {}
		for _ = 1, count do
			local rarity, gtype = GearConfig.roll(chest, rng, Game.stat(p, "chestluck"))
			local uid = Game.addGear(p, rarity, gtype)
			local copy = table.clone(d.Gear[uid])
			copy.uid = uid
			table.insert(got, copy)
		end
		Game.bump(p, "chests", count)
		Game.publish(player, p, "Gear", "Progress")
		Data.saveSoon(player)
		return true, got
	elseif action == "craft" then
		local recipe = Guard.str(a) and GearConfig.RecipeById[a]
		if not recipe then return false, "Unknown recipe" end
		if recipe.event then
			local live = false
			for _, e in Game.events do if e.id == recipe.event then live = true end end
			if not live then return false, "Only during the event" end
		end
		for mat, n in recipe.mats do
			if (d.Materials[mat] or 0) < n then return false, "Need " .. n .. " " .. GearConfig.MaterialById[mat].name end
		end
		if Game.count(d.Gear) >= Game.MAX_GEAR then return false, "Gear bag full (" .. Game.MAX_GEAR .. ")" end
		if not Game.spend(p, recipe.cash) then return false, "Need $" .. Game.short(recipe.cash) end
		for mat, n in recipe.mats do d.Materials[mat] -= n end
		local uid = Game.addGear(p, recipe.rarity, recipe.gtype or GearConfig.randomType(rng))
		Game.publish(player, p, "Gear", "Materials")
		Data.saveSoon(player)
		local out = table.clone(d.Gear[uid])
		out.uid = uid
		return true, out
	end
	local g = Guard.str(a) and d.Gear[a]
	if not g then return false, "Unknown gear" end
	if action == "upgrade" then
		if (g.lvl or 1) >= GearConfig.MAX_LEVEL then return false, "Max level" end
		local cost = GearConfig.upgradeCost(g)
		if not Game.spend(p, cost) then return false, "Need $" .. Game.short(cost) end
		g.lvl = (g.lvl or 1) + 1
	elseif action == "equip" then
		local iid = Guard.str(b)
		if not iid or not d.Monsters[iid] then return false, "You don't own that monster" end
		if g.t == "relic" and Game.stat(p, "relic") <= 0 then return false, "Unlock Equipment Slots in the Evolution Tree first" end
		for _, other in d.Gear do -- one of each type per monster: swap out the old one
			if other ~= g and other.m == iid and other.t == g.t then other.m = nil end
		end
		g.m = iid
	elseif action == "unequip" then
		g.m = nil
	else
		return false, "Bad request"
	end
	Game.publish(player, p, "Gear", "Monsters")
	Game.BaseChanged:Fire(player) -- slot income labels
	return true
end
