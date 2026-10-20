-- run from the command bar: require(game.ServerStorage.Tests.RollSpec)()
return function()
	local C = require(game.ReplicatedStorage.Monster.MonsterConfig)
	local sum = 0 for _, p in C.Odds do sum += p end
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
	local cs = 0 for id, p in capped do cs += p assert(C.Tier[id] <= 5, "tier above cap in odds: " .. id) end
	assert(math.abs(cs - 1) < 1e-9, "capped odds must sum to 1")
	for _ = 1, 20000 do local d = C.roll(rng, 5, 5) assert(C.Tier[d.rarity] <= 5, "rolled above cap: " .. d.rarity) end
	-- extreme luck stays valid
	local hs = 0 for _, p in C.oddsFor(1e9) do assert(p >= 0) hs += p end
	assert(math.abs(hs - 1) < 1e-9)
	-- chest odds valid and rolls stay inside each chest's table
	local G = require(game.ReplicatedStorage.Monster.GearConfig)
	for _, c in G.Chests do
		local s = 0 for id, p in G.odds(c) do assert(G.RarityById[id] and p > 0, c.id) s += p end
		assert(math.abs(s - 1) < 1e-9, c.id .. " odds must sum to 1")
		for _ = 1, 2000 do local r, t = G.roll(c, rng) assert(c.weights[r] and G.TypeById[t], c.id .. " rolled " .. tostring(r)) end
	end
	return ("ok: common %.3f (exp %.3f), huge %.4f, monstrous %.4f"):format(common / n, C.Odds.Common, huge / n, monstrous / n)
end
