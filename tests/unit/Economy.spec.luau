-- Income, upgrade costs, sell values, modifier aggregation (no double
-- counting), luck composition and offline earnings.
return function(ctx)
	local T, Loader = ctx.Test, ctx.Loader
	local describe, it, expect = T.describe, T.it, T.expect
	local StatMath = Loader.requirePath("ReplicatedStorage.Shared.Util.StatMath")
	local Modifiers = Loader.requirePath("ReplicatedStorage.Shared.Util.Modifiers")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local MonsterConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonsterConfig")
	local RarityConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RarityConfig")
	local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
	local DiceConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DiceConfig")
	local SkillTreeConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SkillTreeConfig")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local DataSchema = Loader.requirePath("ServerScriptService.Server.Modules.DataSchema")
	local OfflineIncome = Loader.requirePath("ServerScriptService.Server.Modules.OfflineIncome")
	local NOW = 1792549555 + 2 * 86400

	local function monster(id, overrides)
		local inst = {
			Id = "m1",
			MonsterId = id,
			Level = 1,
			Xp = 0,
			Upgrade = 0,
			Stars = 0,
			Locked = false,
			Favorite = false,
			Source = "Test",
			Acquired = 0,
		}
		for k, v in overrides or {} do
			inst[k] = v
		end
		return inst
	end

	describe("StatMath income", function()
		it("BaseIncome * rarity * level * upgrade * stars * equipment", function()
			local def = MonsterConfig.Monsters.moss_golem
			local rarity = RarityConfig.Rarities[def.Rarity]
			local base = StatMath.monsterIncome(monster("moss_golem"), 0, {})
			expect(base).toBeNear(def.BaseIncomePerSecond * rarity.IncomeMultiplier, 1e-9)
			local upgraded =
				StatMath.monsterIncome(monster("moss_golem", { Upgrade = 4, Level = 11, Stars = 2 }), 0.1, {})
			local expected = def.BaseIncomePerSecond
				* rarity.IncomeMultiplier
				* (1 + 10 * 0.02)
				* (1 + 4 * 0.25)
				* (1 + 2 * 0.3)
				* 1.1
			expect(upgraded).toBeNear(expected, 1e-9)
		end)

		it("applies the global multiplier exactly once to the sum", function()
			local p = DataSchema.default(NOW)
			p.Inventory.Monsters.m1 = monster("moss_golem")
			p.Inventory.Monsters.m2 = monster("sprout_bunny", { Id = "m2" })
			p.Base.PlacedMonsters["1"] = "m1"
			p.Base.PlacedMonsters["2"] = "m2"
			local raw = StatMath.monsterIncome(p.Inventory.Monsters.m1, 0, {})
				+ StatMath.monsterIncome(p.Inventory.Monsters.m2, 0, {})
			local total, per = StatMath.totalIncome(p, {}, 3)
			expect(total).toBeNear(raw * 3, 1e-9)
			expect(per.m1 + per.m2).toBeNear(total, 1e-9)
		end)

		it("does not count a monster placed in two slots twice", function()
			local p = DataSchema.default(NOW)
			p.Inventory.Monsters.m1 = monster("moss_golem")
			p.Base.PlacedMonsters["1"] = "m1"
			p.Base.PlacedMonsters["2"] = "m1"
			local single = StatMath.monsterIncome(p.Inventory.Monsters.m1, 0, {})
			expect(StatMath.totalIncome(p, {}, 1)).toBeNear(single, 1e-9)
		end)
	end)

	describe("costs and values", function()
		it("upgrade cost grows geometrically and respects reductions", function()
			local a = StatMath.upgradeCost(monster("moss_golem", { Upgrade = 0 }), {})
			local b = StatMath.upgradeCost(monster("moss_golem", { Upgrade = 1 }), {})
			expect(b / a).toBeNear(EconomyConfig.UpgradeCostGrowth, 0.02)
			local cheaper = StatMath.upgradeCost(monster("moss_golem"), { UpgradeCostReduction = 0.25 })
			expect(cheaper < a).toBe(true)
		end)

		-- Worst case for a roll-then-sell loop: luck at the hard cap, every sell
		-- bonus (skills, ascension, game passes) maxed, and the dice discount at its cap.
		local function maxedBonus(key)
			local total = 0
			for _, nodes in { SkillTreeConfig.Nodes, RebirthConfig.AscensionNodes } do
				for _, node in nodes do
					for _, effect in node.Effects do
						if effect.Key == key then
							total += effect.PerLevel * node.MaxLevel
						end
					end
				end
			end
			for _, pass in MonetizationConfig.Passes do
				total += pass.Modifiers[key] or 0
			end
			return Modifiers.cap(key, total)
		end

		it("rolling then selling is never profitable, even with maxed luck and bonuses", function()
			local RollMath = Loader.requirePath("ReplicatedStorage.Shared.Util.RollMath")
			local sellMods = { SellValue = maxedBonus("SellValue") }
			for id, dice in DiceConfig.Dice do
				local grouped = RollMath.poolByRarity(dice.Pool)
				for _, luck in { 1, DiceConfig.Luck.HardCap } do
					local ev = 0
					for _, o in RollMath.rarityOdds(dice.RarityWeights, dice.Pool, luck) do
						local entries = grouped[o.Rarity]
						local sumW, avg = 0, 0
						for _, e in entries do
							sumW += e.Weight
						end
						for _, e in entries do
							avg += StatMath.sellValue(monster(e.Value), sellMods) * e.Weight / sumW
						end
						ev += o.Chance * avg
					end
					local cost = Modifiers.rollCost(
						dice,
						{ RollCostReduction = Modifiers.cap("RollCostReduction", 1) }
					)
					assert(
						ev < cost * 0.9,
						string.format(
							"%s at luck %g: expected sell value %.1f vs cost %d",
							id,
							luck,
							ev,
							cost
						)
					)
				end
			end
		end)

		it("upgrading then selling never returns more than the upgrade cost", function()
			local mods = {
				UpgradeCostReduction = Modifiers.cap("UpgradeCostReduction", 1),
				SellValue = maxedBonus("SellValue"),
			}
			for id, def in MonsterConfig.Monsters do
				local maxUpgrade = RarityConfig.Rarities[def.Rarity].MaxUpgradeLevel
				for level = 0, maxUpgrade - 1 do
					local before = StatMath.sellValue(monster(id, { Upgrade = level }), mods)
					local after = StatMath.sellValue(monster(id, { Upgrade = level + 1 }), mods)
					local cost = StatMath.upgradeCost(monster(id, { Upgrade = level }), mods)
					assert(
						after - before < cost,
						string.format(
							"%s upgrade %d: sell gain %d >= cost %d",
							id,
							level,
							after - before,
							cost
						)
					)
				end
			end
		end)
	end)

	describe("fusion economy", function()
		it("rarity fusion never turns inputs into more sell value than they cost", function()
			local CraftingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CraftingConfig")
			local RegionConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RegionConfig")
			local cfg = CraftingConfig.RarityFusion
			for regionId in RegionConfig.Regions do
				local byTier = {}
				for id, def in MonsterConfig.Monsters do
					if def.Region == regionId and MonsterConfig.isRollable(def) then
						local tier = RarityConfig.tierOf(def.Rarity)
						byTier[tier] = byTier[tier] or {}
						table.insert(byTier[tier], StatMath.sellValue(monster(id), {}))
					end
				end
				for tier, values in byTier do
					local nextValues = byTier[tier + 1]
					if nextValues then
						local minInput, maxOutput = math.huge, 0
						for _, v in values do
							minInput = math.min(minInput, v)
						end
						for _, v in nextValues do
							maxOutput = math.max(maxOutput, v)
						end
						local coins = StatMath.regionDiceCost(regionId)
							* cfg.CoinsDiceCostMultiplier
							* tier
							* 0.5
						assert(
							cfg.InputCount * minInput + coins > maxOutput,
							string.format(
								"%s tier %d: %d inputs worth %d + %d coins -> output worth %d",
								regionId,
								tier,
								cfg.InputCount,
								minInput,
								coins,
								maxOutput
							)
						)
					end
				end
			end
		end)
	end)

	describe("Modifiers", function()
		it("sums skills, ascension, rebirths and caps reductions", function()
			local p = DataSchema.default(NOW)
			p.Skills.Nodes.eco_1 = 5 -- +30% income
			p.Progression.AscensionUpgrades.asc_wealth = 2 -- +20% income
			p.Progression.RebirthCount = 2 -- +70% income
			p.Skills.Nodes.luck_3 = 5
			p.Skills.Nodes.x_luck_eco = 3
			local mods = Modifiers.compute(p, NOW)
			expect(mods.Income).toBeNear(0.3 + 0.2 + 2 * RebirthConfig.IncomeBonusPerRebirth, 1e-9)
			expect(Modifiers.incomeMultiplier(mods, false)).toBeNear(1 + mods.Income, 1e-9)
			expect(mods.RollCostReduction <= 0.5).toBe(true)
		end)

		it("potion and event multipliers apply online but not offline", function()
			local p = DataSchema.default(NOW)
			p.Boosts.income_potion = NOW + 600
			local mods = Modifiers.compute(p, NOW)
			expect(mods.BoostIncomeMult).toBe(2)
			local event = mods.EventIncomeMult or 1
			expect(Modifiers.incomeMultiplier(mods, true)).toBeNear(
				2 * event * Modifiers.incomeMultiplier(mods, false),
				1e-9
			)
			local expired = Modifiers.compute(p, NOW + 601)
			expect(expired.BoostIncomeMult).toBe(1)
		end)

		it("composes luck: base * (1 + additive) * boosts * events, soft-capped", function()
			local p = DataSchema.default(NOW)
			p.Skills.Nodes.luck_1 = 5 -- +25%
			p.Boosts.luck_potion = NOW + 100
			local mods = Modifiers.compute(p, NOW)
			local dice = DiceConfig.Dice.forest_dice
			local raw, effective = Modifiers.luckFor(dice, mods)
			expect(raw).toBeNear(dice.BaseLuck * 1.25 * 1.5, 1e-9)
			expect(effective).toBeNear(raw, 1e-9)
		end)

		it("high-tier luck only affects Volcano dice and above", function()
			local p = DataSchema.default(NOW)
			p.Skills.Nodes.luck_2 = 5
			local mods = Modifiers.compute(p, NOW)
			local lowRaw = Modifiers.luckFor(DiceConfig.Dice.forest_dice, mods)
			local highRaw = Modifiers.luckFor(DiceConfig.Dice.volcano_dice, mods)
			expect(lowRaw).toBeNear(DiceConfig.Dice.forest_dice.BaseLuck, 1e-9)
			expect(highRaw > DiceConfig.Dice.volcano_dice.BaseLuck).toBe(true)
		end)
	end)

	describe("OfflineIncome", function()
		local function profileWithIncome()
			local p = DataSchema.default(NOW)
			p.Inventory.Monsters.m1 = monster("moss_golem")
			p.Base.PlacedMonsters["1"] = "m1"
			return p
		end

		it("grants rate * capped time * efficiency", function()
			local p = profileWithIncome()
			p.Timestamps.LastSeen = NOW - 3600
			local r = OfflineIncome.compute(p, NOW)
			expect(r.CountedSeconds).toBe(3600)
			expect(r.Efficiency).toBe(EconomyConfig.OfflineBaseEfficiency)
			expect(r.Coins).toBe(math.floor(r.RatePerSecond * 3600 * r.Efficiency))
		end)

		it("caps long absences", function()
			local p = profileWithIncome()
			p.Timestamps.LastSeen = NOW - 7 * 86400
			local r = OfflineIncome.compute(p, NOW)
			expect(r.CountedSeconds).toBe(EconomyConfig.OfflineBaseCapHours * 3600)
		end)

		it("ignores tiny absences and negative elapsed time", function()
			local p = profileWithIncome()
			p.Timestamps.LastSeen = NOW - 10
			expect(OfflineIncome.compute(p, NOW).Coins).toBe(0)
			p.Timestamps.LastSeen = NOW + 500
			expect(OfflineIncome.compute(p, NOW).Coins).toBe(0)
		end)

		it("excludes temporary boosts from the offline rate", function()
			local p = profileWithIncome()
			p.Timestamps.LastSeen = NOW - 3600
			local plain = OfflineIncome.compute(p, NOW).Coins
			p.Boosts.income_potion = NOW + 600
			expect(OfflineIncome.compute(p, NOW).Coins).toBe(plain)
		end)
	end)
end
