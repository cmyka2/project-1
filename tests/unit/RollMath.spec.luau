-- Weighted RNG, luck transform and odds correctness, including statistical checks.
return function(ctx)
	local T, Loader = ctx.Test, ctx.Loader
	local describe, it, expect = T.describe, T.it, T.expect
	local RollMath = Loader.requirePath("ReplicatedStorage.Shared.Util.RollMath")
	local DiceConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DiceConfig")
	local RarityConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RarityConfig")
	local MonsterConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonsterConfig")
	local Random = ctx.Mock.Random

	local function sum(odds)
		local total = 0
		for _, o in odds do
			total += o.Chance
		end
		return total
	end

	describe("RollMath.rarityOdds", function()
		it("sums to 100% for every dice at several luck values", function()
			for id, dice in DiceConfig.Dice do
				for _, luck in { 1, 1.5, 3, 10, 20 } do
					local odds = RollMath.rarityOdds(dice.RarityWeights, dice.Pool, luck)
					assert(#odds > 0, id .. " has no odds")
					expect(sum(odds)).toBeNear(1, 1e-9)
				end
			end
		end)

		it("is sorted by tier and only lists rarities present in the pool", function()
			local dice = DiceConfig.Dice.grassland_dice
			local odds = RollMath.rarityOdds(dice.RarityWeights, dice.Pool, 1)
			for i = 2, #odds do
				expect(RarityConfig.tierOf(odds[i].Rarity) > RarityConfig.tierOf(odds[i - 1].Rarity)).toBe(
					true
				)
			end
			for _, o in odds do
				expect(dice.RarityWeights[o.Rarity] ~= nil).toBe(true)
			end
		end)

		it("matches the configured weights exactly at luck 1", function()
			local dice = DiceConfig.Dice.grassland_dice
			local odds = RollMath.rarityOdds(dice.RarityWeights, dice.Pool, 1)
			local total = 0
			for _, w in dice.RarityWeights do
				total += w
			end
			for _, o in odds do
				expect(o.Chance).toBeNear(dice.RarityWeights[o.Rarity] / total, 1e-12)
			end
		end)

		it("raises every rare tier's chance monotonically with luck, never common", function()
			local dice = DiceConfig.Dice.cave_dice
			local previous = nil
			for _, luck in { 1, 1.25, 2, 4, 8 } do
				local odds = RollMath.rarityOdds(dice.RarityWeights, dice.Pool, luck)
				local map = {}
				for _, o in odds do
					map[o.Rarity] = o.Chance
				end
				if previous then
					expect(map.Celestial > previous.Celestial).toBe(true)
					expect(map.Divine > previous.Divine).toBe(true)
					expect(map.Rare < previous.Rare).toBe(true)
				end
				previous = map
			end
		end)

		it("does not make rare results guaranteed even at max luck", function()
			local dice = DiceConfig.Dice.glitch_dice
			local odds = RollMath.rarityOdds(dice.RarityWeights, dice.Pool, RollMath.effectiveLuck(1e9))
			for _, o in odds do
				if o.Rarity == "Glitched" then
					expect(o.Chance < 0.05).toBe(true)
				end
			end
		end)

		it("ignores invalid, zero, negative and NaN weights", function()
			local pool = DiceConfig.Dice.grassland_dice.Pool
			local odds = RollMath.rarityOdds(
				{ Common = 10, Uncommon = 0, Rare = -5, Epic = 0 / 0, Legendary = math.huge, Bogus = 50 },
				pool,
				1
			)
			expect(#odds).toBe(1)
			expect(odds[1].Rarity).toBe("Common")
			expect(odds[1].Chance).toBeNear(1, 1e-12)
		end)

		it("returns no odds for an empty or unknown pool", function()
			expect(#RollMath.rarityOdds({ Common = 1 }, {}, 1)).toBe(0)
			expect(#RollMath.rarityOdds({ Common = 1 }, { "not_a_monster" }, 1)).toBe(0)
			local id = RollMath.roll({ Common = 1 }, {}, 1, function()
				return 0.5
			end)
			expect(id).toBeNil()
		end)
	end)

	describe("RollMath.effectiveLuck", function()
		it("is linear below the soft cap and capped above", function()
			expect(RollMath.effectiveLuck(1)).toBe(1)
			expect(RollMath.effectiveLuck(2)).toBe(2)
			expect(RollMath.effectiveLuck(DiceConfig.Luck.SoftCapStart)).toBe(DiceConfig.Luck.SoftCapStart)
			expect(RollMath.effectiveLuck(1e12)).toBe(DiceConfig.Luck.HardCap)
		end)
		it("is monotonic non-decreasing and handles bad input", function()
			local last = 0
			for raw = 0.5, 60, 0.5 do
				local v = RollMath.effectiveLuck(raw)
				expect(v >= last).toBe(true)
				last = v
			end
			expect(RollMath.effectiveLuck(0 / 0)).toBe(1)
			expect(RollMath.effectiveLuck(-5)).toBe(1)
		end)
	end)

	describe("RollMath.pickWeighted", function()
		it("returns nil only with no valid weights", function()
			expect(RollMath.pickWeighted({}, math.random)).toBeNil()
			expect(RollMath.pickWeighted({ { Value = "a", Weight = 0 } }, math.random)).toBeNil()
			expect(RollMath.pickWeighted({ { Value = "a", Weight = 1 } }, function()
				return 0.9999999
			end)).toBe("a")
		end)

		it("handles rng edge values 0 and ~1", function()
			local entries = { { Value = "a", Weight = 1 }, { Value = "b", Weight = 1 } }
			expect(RollMath.pickWeighted(entries, function()
				return 0
			end)).toBe("a")
			expect(RollMath.pickWeighted(entries, function()
				return 1
			end)).toBe("b")
		end)

		it("matches theoretical frequencies over 200k samples (chi-square)", function()
			local rng = Random.new(12345)
			local entries = {
				{ Value = "a", Weight = 600 },
				{ Value = "b", Weight = 300 },
				{ Value = "c", Weight = 80 },
				{ Value = "d", Weight = 18 },
				{ Value = "e", Weight = 2 },
			}
			local n = 200000
			local counts = {}
			for _ = 1, n do
				local v = RollMath.pickWeighted(entries, function()
					return rng:NextNumber()
				end)
				counts[v] = (counts[v] or 0) + 1
			end
			local chi = 0
			for _, e in entries do
				local expected = n * e.Weight / 1000
				chi += ((counts[e.Value] or 0) - expected) ^ 2 / expected
			end
			-- 4 degrees of freedom: p = 0.001 critical value is 18.47
			assert(chi < 18.47, "chi-square too high: " .. chi)
		end)

		it("full two-stage roll distribution matches published odds (100k rolls)", function()
			local rng = Random.new(777)
			local dice = DiceConfig.Dice.forest_dice
			local odds = RollMath.rarityOdds(dice.RarityWeights, dice.Pool, 1.1)
			local counts = {}
			local n = 100000
			for _ = 1, n do
				local monsterId, rarity = RollMath.roll(dice.RarityWeights, dice.Pool, 1.1, function()
					return rng:NextNumber()
				end)
				assert(
					monsterId and MonsterConfig.Monsters[monsterId].Rarity == rarity,
					"monster/rarity mismatch"
				)
				counts[rarity] = (counts[rarity] or 0) + 1
			end
			for _, o in odds do
				local observed = (counts[o.Rarity] or 0) / n
				local sigma = math.sqrt(o.Chance * (1 - o.Chance) / n)
				assert(
					math.abs(observed - o.Chance) < 5 * sigma + 1e-4,
					string.format("%s observed %.5f expected %.5f", o.Rarity, observed, o.Chance)
				)
			end
		end)
	end)
end
