-- run from the command bar: require(game.ServerStorage.Tests.RollSpec)()
return function()
	local C = require(game.ReplicatedStorage.Monster.MonsterConfig)
	local W = require(game.ReplicatedStorage.Monster.Weighted)
	local L = require(game.ReplicatedStorage.Monster.LuckConfig)
	local function total(t) local s = 0 for _, p in t do assert(p >= 0, "negative odds") s += p end return s end
	local sum = total(C.Odds)
	assert(math.abs(sum - 1) < 1e-9, "odds must sum to 1, got " .. sum)
	local rng, n, common, huge, monstrous = Random.new(1), 200000, 0, 0, 0
	for _ = 1, n do
		local d, v = C.roll(rng)
		assert(C.ById[d.id] and C.VariantById[v])
		if d.rarity == "Common" then common += 1 end
		if v == "Huge" then huge += 1 elseif v == "Monstrous" then monstrous += 1 end
	end
	assert(math.abs(common / n - C.Odds.Common) < 0.01, "common rate off: " .. common / n)
	assert(math.abs(huge / n - 1 / 50) < 0.003, "huge rate off: " .. huge / n)
	assert(math.abs(monstrous / n - 1 / 500) < 0.0008, "monstrous rate off: " .. monstrous / n)
	-- die cap: nothing above maxTier, capped odds still sum to 1
	local capped = C.oddsFor(5, 5)
	for id in capped do assert(C.Tier[id] <= 5, "tier above cap in odds: " .. id) end
	assert(math.abs(total(capped) - 1) < 1e-9, "capped odds must sum to 1")
	for _ = 1, 20000 do local d = C.roll(rng, 5, 5) assert(C.Tier[d.rarity] <= 5, "rolled above cap: " .. d.rarity) end
	-- extreme / invalid luck stays valid and normalized
	for _, luck in { 1e9, math.huge, 0, -5, 0 / 0 } do
		assert(math.abs(total(C.oddsFor(L.effective(luck))) - 1) < 1e-9, "luck " .. tostring(luck))
	end
	assert(L.effective(1e12) <= L.HARD_CAP and L.effective(10) == 10 and L.effective(100) < 100, "diminishing returns")
	-- luck only ever shifts odds toward rarer tiers, and the shift grows with tier
	local base, lucky = C.oddsFor(1), C.oddsFor(20)
	assert(lucky.Common < base.Common and lucky.Mythic > base.Mythic, "luck should favor rares")
	assert(lucky.Mythic / base.Mythic > lucky.Rare / base.Rare, "rarer tiers gain more from luck")
	local lr, lucky1 = Random.new(7), 0
	for _ = 1, 50000 do if C.Tier[C.roll(lr, 20).rarity] >= 3 then lucky1 += 1 end end
	local expect = 0 for id, p in lucky do if C.Tier[id] >= 3 then expect += p end end
	assert(math.abs(lucky1 / 50000 - expect) < 0.01, "lucky rare+ rate off: " .. lucky1 / 50000)
	-- world eligibility: Glitched monsters only come from the Glitch die
	assert((C.oddsFor(40, 12, "cosmic").Glitched or 0) == 0, "cosmic die must not roll Glitched")
	assert((C.oddsFor(40, 12, "glitch").Glitched or 0) > 0, "glitch die rolls Glitched")
	for _, e in C.pool(40, 12, "cosmic") do assert(not e[1].dice, "die-exclusive monster leaked: " .. e[1].id) end
	-- weighted picker: invalid weights are ignored, empty/zero pools pick nothing
	local wr = Random.new(3)
	assert(W.pick({}, wr) == nil and W.odds({}) == nil, "empty pool")
	assert(W.pick({ { "a", 0 }, { "b", -1 }, { "c", 0 / 0 }, { "d", "x" } }, wr) == nil, "all-invalid pool")
	for _ = 1, 1000 do assert(W.pick({ { "a", 0 }, { "b", 3 }, { "c", -2 }, { "d", math.huge } }, wr) == "b", "only b is valid") end
	local o = W.odds({ { "a", 1 }, { "b", 3 } })
	assert(o[1] == 0.25 and o[2] == 0.75, "odds normalize")
	-- chest odds valid and rolls stay inside each chest's table
	local G = require(game.ReplicatedStorage.Monster.GearConfig)
	for _, c in G.Chests do
		local s = 0 for id, p in G.odds(c) do assert(G.RarityById[id] and p > 0, c.id) s += p end
		assert(math.abs(s - 1) < 1e-9, c.id .. " odds must sum to 1")
		for _ = 1, 2000 do local r, t = G.roll(c, rng) assert(c.weights[r] and G.TypeById[t], c.id .. " rolled " .. tostring(r)) end
	end
	-- chest luck shifts drops toward rarer gear and stays normalized; gear levels scale power
	local wood = G.ChestById.wooden
	local base, lucky = G.odds(wood), G.odds(wood, 0.75)
	local ls = 0 for _, p in lucky do ls += p end
	assert(math.abs(ls - 1) < 1e-9 and lucky.Rare > base.Rare and lucky.Common < base.Common, "chest luck")
	assert(math.abs(G.power({ r = "Rare", lvl = 3 }) - G.RarityById.Rare.income * 1.2) < 1e-9, "gear level power")
	for _ = 1, 500 do assert(G.randomType(rng, false) ~= "relic", "relics only from relic chests") end
	return ("roll ok: common %.3f (exp %.3f), huge %.4f, monstrous %.4f, luck20 rare+ %.3f (exp %.3f)"):format(
		common / n, C.Odds.Common, huge / n, monstrous / n, lucky1 / 50000, expect)
end
