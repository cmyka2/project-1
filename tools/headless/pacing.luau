-- Pacing simulation: a greedy active player using the real shared configs/formulas (no Roblox needed).
-- Rolls at the cooldown, keeps the best earners placed, buys dice / tree nodes / upgrades greedily, rebirths ASAP.
-- Ignores gear, traits, battles (boss gate assumed cleared after 30 min), events, passes and friends, so it shows
-- the free baseline. Run: tools/headless/target/release/headless tools/headless/pacing.luau [hours]
local R = compile(readfile("tools/headless/mockrbx.luau"), "mockrbx")()
local M = R.RS.Monster
local C = R.req(M.MonsterConfig)
local F = R.req(M.Formulas)
local Reb = R.req(M.RebirthConfig)
local Dice = R.req(M.DiceConfig)
local Tree = R.req(M.SkillTree)
local Luck = R.req(M.LuckConfig)
local Traits = R.req(M.TraitConfig)
local Mon = R.req(M.MonetizationConfig)

local HOURS = tonumber(ARGS[1]) or 8
local rng = R.env.Random.new(42)
local t, cash, rolls, reb = 0, 0, 0, 0
local mons = {} -- { def, v, lvl, mu }
local skills = { start = 1 }
local owned = { grassland = true }
local die = Dice.List[1]
local log, seen = {}, {}
local function mark(key, text)
	if seen[key] then return end
	seen[key] = true
	table.insert(log, ("%7s  %s"):format(("%d:%02d"):format(t // 3600, t % 3600 // 60) .. (t < 3600 and ("m" .. t % 60 .. "s") or ""), text))
end
local function stat(e) return Tree.stat(skills, e) end
local function income(m)
	return C.Income[m.def.rarity] * (C.VariantIncome[m.v] or 1) * F.levelMult(m.lvl) * Traits.incomeMult(m)
		* (1 + stat("income")) * (1 + reb * Reb.INCOME_BONUS)
end
local function placedSorted()
	table.sort(mons, function(a, b) return income(a) > income(b) end)
	return math.min(#mons, F.slots(reb))
end
local function ips()
	local s = 0
	for i = 1, placedSorted() do s += income(mons[i]) end
	return s
end
local function short(n)
	for _, u in { { 1e21, "sx" }, { 1e18, "qn" }, { 1e15, "qd" }, { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return ("%.1f%s"):format(n / u[1], u[2]) end
	end
	return tostring(math.floor(n))
end

local cooldown, nextRoll, lastReb = 0.8, 0, 0
local rebirthTimes = {}
while t < HOURS * 3600 do
	-- roll
	if t >= nextRoll then
		rolls += 1
		local extra = rolls % Mon.RAINBOW_EVERY == 0 and Mon.RAINBOW_MULT or rolls % Mon.GOLDEN_EVERY == 0 and Mon.GOLDEN_MULT or 1
		local luck = Luck.combine(die.luck, stat("luck") + reb * Reb.LUCK_BONUS, extra)
		local def, v = C.roll(rng, luck, die.maxTier, die.id)
		table.insert(mons, { def = def, v = v, lvl = 1, mu = Traits.rollMutation(rng, nil) })
		local tier = C.Tier[def.rarity]
		mark("tier" .. tier, "first " .. def.rarity .. " (" .. def.name .. ")")
		-- backpack: sell the worst when over capacity
		if #mons > 100 + stat("storage") then
			placedSorted()
			local worst = table.remove(mons)
			cash += F.sellValue(C.Income[worst.def.rarity] * (C.VariantIncome[worst.v] or 1), worst.lvl, stat("sell"))
		end
		nextRoll = t + cooldown * (1 - math.min(0.75, stat("rollspeed")))
	end
	-- earn
	local inc = ips()
	cash += inc
	if t % 5 == 0 then
		-- next die
		local nd = Dice.List[(table.find(Dice.List, die) or 1) + 1]
		if nd and cash >= nd.cost and (not nd.rebirth or reb >= nd.rebirth) then
			cash -= nd.cost
			owned[nd.id] = true
			die = nd
			mark("die" .. nd.id, nd.name .. "  ($" .. short(inc) .. "/s)")
		end
		-- cheapest buyable tree node (income/luck/rollspeed/storage/upgradecost), if it costs < 15 min of income
		local best
		for _, node in Tree.Nodes do
			local useful = node.effects.income or node.effects.luck or node.effects.rollspeed or node.effects.storage or node.effects.upgradecost
			if useful and not Tree.blocked(node, skills, reb) then
				local c = Tree.cost(node, skills[node.id] or 0)
				if not best or c < best.c then best = { node = node, c = c } end
			end
		end
		if best and cash >= best.c and best.c <= inc * 900 + 500 then
			cash -= best.c
			skills[best.node.id] = (skills[best.node.id] or 0) + 1
		end
		-- upgrade placed monsters while an upgrade pays back within 10 minutes
		local n = placedSorted()
		for i = 1, n do
			local m = mons[i]
			local cost = F.upgradeCost(C.Income[m.def.rarity] * (C.VariantIncome[m.v] or 1), m.lvl) * (1 - math.min(0.5, stat("upgradecost")))
			local gain = income(m) * (F.levelMult(m.lvl + 1) / F.levelMult(m.lvl) - 1)
			if m.lvl < F.MAX_LEVEL and cash >= cost and cost <= gain * 600 then
				cash -= cost
				m.lvl += 1
			end
		end
		-- rebirth as soon as allowed
		local req = Reb.requirement(reb)
		local have = 0
		for _, m in mons do if C.Tier[m.def.rarity] >= req.minTier then have += 1 end end
		if cash >= req.cost and have >= req.count and (not req.stage or t >= 1800) then
			cash = 0
			reb += 1
			table.insert(rebirthTimes, t - lastReb)
			lastReb = t
			mark("reb" .. reb, ("REBIRTH %d (cycle %dm, slots %d, floors %d)"):format(reb, rebirthTimes[#rebirthTimes] // 60, F.slots(reb), F.floors(reb)))
		end
	end
	if t == 30 then mark("t30", "after 30s: $" .. short(inc) .. "/s, " .. #mons .. " monsters") end
	if t == 300 then mark("t300", "after 5m: $" .. short(inc) .. "/s") end
	if t % 3600 == 0 and t > 0 then mark("h" .. t, ("--- hour %d: $%s/s, cash $%s, die %s, rebirths %d, rolls %d"):format(t // 3600, short(inc), short(cash), die.name, reb, rolls)) end
	t += 1
end
print(table.concat(log, "\n"))
