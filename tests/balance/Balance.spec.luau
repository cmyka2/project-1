-- Economy pacing simulation. Plays a greedy "active" player (always online,
-- auto-rolls, reinvests whenever an investment pays for itself before the next
-- goal) and a "casual" player (1 hour online per day, offline earnings for
-- the rest) through every region unlock and the first rebirths, using only
-- the shared config and math modules the game itself uses.
--
-- Guardrails are asserted on every run. With BALANCE_WRITE=1 the full report
-- is written to docs/BALANCE.md:
--   BALANCE_WRITE=1 lune run tests/run tests/balance/Balance.spec.luau
--
-- Simplifications (all make the estimate conservative unless noted): no skill
-- tree, ascension, equipment, potions, events, stars, monster levels or battle
-- rewards; the boss of each region is assumed beatable when the player can
-- afford the next region (combat pacing is reported separately below).
return function(ctx)
	local T, Loader = ctx.Test, ctx.Loader
	local describe, it, expect = T.describe, T.it, T.expect
	local fs = require("@lune/fs")
	local process = require("@lune/process")

	local DiceConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DiceConfig")
	local RarityConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RarityConfig")
	local MonsterConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonsterConfig")
	local RegionConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RegionConfig")
	local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local EnemyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EnemyConfig")
	local StatMath = Loader.requirePath("ReplicatedStorage.Shared.Util.StatMath")
	local RollMath = Loader.requirePath("ReplicatedStorage.Shared.Util.RollMath")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Util.BaseLayout")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Random = ctx.Mock.Random

	local MAX_REBIRTH = 12
	local MAX_HOURS = 3000

	local function monster(id, upgrade)
		return {
			Id = "sim",
			MonsterId = id,
			Level = 1,
			Xp = 0,
			Upgrade = upgrade or 0,
			Stars = 0,
			Locked = false,
			Favorite = false,
			Source = "Sim",
			Acquired = 0,
		}
	end

	local function hours(seconds)
		if seconds < 3600 then
			return string.format("%.0f min", seconds / 60)
		end
		return string.format("%.1f h", seconds / 3600)
	end

	-- Every possible outcome of a dice at a luck value: { MonsterId, P, Income }.
	local distributionCache = {}
	local function distribution(dice, luck)
		local key = dice.Id .. "@" .. luck
		if distributionCache[key] then
			return distributionCache[key]
		end
		local grouped = RollMath.poolByRarity(dice.Pool)
		local out = {}
		for _, o in RollMath.rarityOdds(dice.RarityWeights, dice.Pool, luck) do
			local entries = grouped[o.Rarity]
			local sumW = 0
			for _, e in entries do
				sumW += e.Weight
			end
			for _, e in entries do
				table.insert(out, {
					MonsterId = e.Value,
					P = o.Chance * e.Weight / sumW,
					Income = StatMath.monsterIncome(monster(e.Value), 0, {}),
				})
			end
		end
		distributionCache[key] = out
		return out
	end

	local function availableDice(state)
		local list = {}
		for _, id in DiceConfig.Order do
			local dice = DiceConfig.Dice[id]
			if
				dice.CostCurrency == "Coins"
				and state.unlocked[dice.RequiredRegion]
				and state.rebirths >= dice.RequiredRebirths
			then
				table.insert(list, dice)
			end
		end
		return list
	end

	local function luckFor(state, dice)
		local additive =
			math.min(RebirthConfig.LuckBonusPerRebirth * state.rebirths, RebirthConfig.LuckBonusCap)
		return RollMath.effectiveLuck(dice.BaseLuck * (1 + additive))
	end

	local function multiplier(state)
		return 1 + RebirthConfig.IncomeBonusPerRebirth * state.rebirths
	end

	local function placedIncome(state, entry)
		return StatMath.monsterIncome(monster(entry.MonsterId, entry.Upgrade), 0, {}) * multiplier(state)
	end

	local function rate(state)
		local total = 0
		for _, entry in state.base do
			total += placedIncome(state, entry)
		end
		return total
	end

	local function worstIndex(state)
		local worst, index = math.huge, nil
		for i, entry in state.base do
			local v = placedIncome(state, entry)
			if v < worst then
				worst, index = v, i
			end
		end
		return index, worst
	end

	local function slots(state)
		return BaseLayout.totalSlots(state.rebirths)
	end

	local function rollsPerSecond(state)
		if state.totalRolls < DiceConfig.AutoRoll.RequiredTotalRolls then
			return 1 / 0.8 -- manual rolling, including the reveal
		end
		local batch = 1
		for _, option in DiceConfig.MultiRoll do
			if
				state.totalRolls >= option.RequiredTotalRolls
				and state.rebirths >= option.RequiredRebirths
			then
				batch = math.max(batch, option.Count)
			end
		end
		return math.min(batch, DiceConfig.AutoRoll.MaxBatch) / DiceConfig.AutoRoll.IntervalSeconds
	end

	-- Expected coins/sec gained from one roll of `dice` (placing it if it beats the worst).
	local function rollGain(state, dice)
		local dist = distribution(dice, luckFor(state, dice))
		local full = #state.base >= slots(state)
		local _, worst = worstIndex(state)
		local gain = 0
		for _, o in dist do
			local v = o.Income * multiplier(state)
			if full then
				gain += o.P * math.max(0, v - worst)
			else
				gain += o.P * v
			end
		end
		return gain
	end

	local function sellOf(monsterId)
		return StatMath.sellValue(monster(monsterId), {})
	end

	local function doRoll(state, dice, rng)
		local monsterId = RollMath.roll(dice.RarityWeights, dice.Pool, luckFor(state, dice), rng)
		state.coins -= dice.Cost
		state.totalRolls += 1
		state.rollBudget -= 1
		state.spentOnRolls += dice.Cost
		local rarity = MonsterConfig.Monsters[monsterId].Rarity
		state.rarityCounts[rarity] = (state.rarityCounts[rarity] or 0) + 1
		local entry = { MonsterId = monsterId, Upgrade = 0 }
		if #state.base < slots(state) then
			table.insert(state.base, entry)
			return
		end
		local index, worst = worstIndex(state)
		if placedIncome(state, entry) > worst then
			local old = state.base[index]
			state.coins += StatMath.sellValue(monster(old.MonsterId, old.Upgrade), {})
			state.base[index] = entry
		else
			state.coins += sellOf(monsterId)
		end
	end

	local function bestUpgrade(state)
		local best, bestRatio, bestCost = nil, 0, 0
		for _, entry in state.base do
			local def = MonsterConfig.Monsters[entry.MonsterId]
			if entry.Upgrade < RarityConfig.Rarities[def.Rarity].MaxUpgradeLevel then
				local cost = StatMath.upgradeCost(monster(entry.MonsterId, entry.Upgrade), {})
				local gain = (
					StatMath.monsterIncome(monster(entry.MonsterId, entry.Upgrade + 1), 0, {})
					- StatMath.monsterIncome(monster(entry.MonsterId, entry.Upgrade), 0, {})
				) * multiplier(state)
				local ratio = gain / cost
				if ratio > bestRatio then
					best, bestRatio, bestCost = entry, ratio, cost
				end
			end
		end
		return best, bestRatio, bestCost
	end

	-- The next goal: unlocking the next region or rebirthing, whichever is allowed and cheaper.
	local function nextGoal(state)
		local goals = {}
		local nextRegion = RegionConfig.Order[state.regionIndex + 1]
		if nextRegion then
			local region = RegionConfig.Regions[nextRegion]
			if state.rebirths >= region.RequiredRebirths then
				table.insert(goals, { Kind = "Region", Id = nextRegion, Cost = region.UnlockCost })
			end
		end
		if state.rebirths < MAX_REBIRTH and state.unlocked[RebirthConfig.requiredRegion(state.rebirths)] then
			table.insert(goals, { Kind = "Rebirth", Cost = RebirthConfig.cost(state.rebirths) })
		end
		table.sort(goals, function(a, b)
			return a.Cost < b.Cost
		end)
		return goals[1]
	end

	local function simulate(profile, seed)
		local rng = Random.new(seed)
		local nextFloat = function()
			return rng:NextNumber()
		end
		local state = {
			coins = EconomyConfig.StartingCoins,
			rebirths = 0,
			regionIndex = 1,
			unlocked = { [RegionConfig.Order[1]] = true },
			base = {},
			totalRolls = 0,
			rollBudget = 0,
			spentOnRolls = 0,
			rarityCounts = {},
		}
		local t = 0 -- seconds of simulated wall-clock time
		local online = 0 -- seconds played
		local milestones = {}
		local function mark(name)
			table.insert(milestones, {
				Name = name,
				Time = t,
				Online = online,
				Rate = rate(state),
				Rolls = state.totalRolls,
				Slots = slots(state),
			})
		end
		local dayOnline = 0
		while online < MAX_HOURS * 3600 do
			-- casual players log off after an hour and come back the next day
			if profile == "Casual" and dayOnline >= 3600 then
				local away = 86400 - dayOnline
				local counted = math.min(away, EconomyConfig.OfflineBaseCapHours * 3600)
				state.coins += rate(state) * counted * EconomyConfig.OfflineBaseEfficiency
				t += away
				dayOnline = 0
			end
			local goal = nextGoal(state)
			if not goal then
				break
			end
			if state.coins >= goal.Cost then
				state.coins -= goal.Cost
				if goal.Kind == "Region" then
					state.regionIndex += 1
					state.unlocked[goal.Id] = true
					mark("Unlock " .. goal.Id)
				else
					state.coins = 0
					for _, entry in state.base do
						entry.Upgrade = 0
					end
					state.rebirths += 1
					mark("Rebirth " .. state.rebirths)
				end
				continue
			end
			-- invest while it pays back before the goal would be reached anyway
			local r = rate(state)
			local timeToGoal = if r > 0 then (goal.Cost - state.coins) / r else math.huge
			local acted = true
			local guard = 0
			while acted and guard < 500 do
				acted = false
				guard += 1
				local bestDice, bestDiceRatio = nil, 0
				if state.rollBudget >= 1 then
					for _, dice in availableDice(state) do
						if dice.Cost <= state.coins then
							local ratio = rollGain(state, dice) / dice.Cost
							if ratio > bestDiceRatio then
								bestDice, bestDiceRatio = dice, ratio
							end
						end
					end
				end
				local upgrade, upgradeRatio, upgradeCost = bestUpgrade(state)
				if upgrade and upgradeCost > state.coins then
					upgrade = nil
				end
				local ratio = math.max(bestDiceRatio, if upgrade then upgradeRatio else 0)
				if ratio > 0 and 1 / ratio < timeToGoal then
					if upgrade and upgradeRatio >= bestDiceRatio then
						state.coins -= upgradeCost
						upgrade.Upgrade += 1
					else
						doRoll(state, bestDice, nextFloat)
					end
					acted = true
				end
			end
			-- advance time: short steps while active investing is possible, longer when saving
			local dt = 5
			r = rate(state)
			if r > 0 then
				local cheapest = goal.Cost
				for _, dice in availableDice(state) do
					cheapest = math.min(cheapest, dice.Cost)
				end
				local _, _, upgradeCost = bestUpgrade(state)
				if upgradeCost > 0 then
					cheapest = math.min(cheapest, upgradeCost)
				end
				dt = math.clamp((cheapest - state.coins) / r, 5, 900)
			end
			if profile == "Casual" then
				dt = math.min(dt, 3600 - dayOnline)
			end
			state.coins += r * dt
			state.rollBudget = math.min(state.rollBudget + rollsPerSecond(state) * dt, 400)
			if r == 0 and state.coins < DiceConfig.Dice.grassland_dice.Cost then
				-- broke with an empty base can only happen with bad config; free roll covers it
				state.coins += DiceConfig.Dice.grassland_dice.Cost
			end
			t += dt
			online += dt
			dayOnline += dt
			if state.rebirths >= MAX_REBIRTH and state.regionIndex >= #RegionConfig.Order then
				break
			end
		end
		return milestones, state
	end

	local active, activeState = simulate("Active", 20261021)
	local casual = simulate("Casual", 20261021)

	local function find(list, name)
		for _, m in list do
			if m.Name == name then
				return m
			end
		end
		return nil
	end

	describe("pacing guardrails", function()
		it("every region is reachable", function()
			for i = 2, #RegionConfig.Order do
				local id = RegionConfig.Order[i]
				assert(
					find(active, "Unlock " .. id),
					id .. " was never reached in " .. MAX_HOURS .. " h of active play"
				)
			end
		end)

		it("onboarding is quick: Forest within 15 minutes, Desert within an hour", function()
			expect(find(active, "Unlock Forest").Online < 15 * 60).toBe(true)
			expect(find(active, "Unlock Desert").Online < 3600).toBe(true)
		end)

		it("the first rebirth takes between 30 minutes and 4 hours of active play", function()
			local first = find(active, "Rebirth 1")
			expect(first ~= nil).toBe(true)
			expect(first.Online > 30 * 60 and first.Online < 4 * 3600).toBe(true)
		end)

		it(
			"no single milestone is a wall (each takes < 6x the longest before it, after the first hour)",
			function()
				local longest = 0
				local previous = 0
				for _, m in active do
					local gap = m.Online - previous
					if previous > 3600 and longest > 0 then
						assert(
							gap < longest * 6,
							string.format(
								"%s took %s after the previous milestone (longest earlier gap %s)",
								m.Name,
								hours(gap),
								hours(longest)
							)
						)
					end
					longest = math.max(longest, gap)
					previous = m.Online
				end
			end
		)

		it("recommended region power matches the region's boss encounter (±35%)", function()
			for _, id in RegionConfig.Order do
				local region = RegionConfig.Regions[id]
				local boss = EnemyConfig.Encounters[region.BossEncounterId]
				local power = StatMath.encounterPower(boss)
				local ratio = region.RecommendedPower / power
				assert(
					ratio > 0.65 and ratio < 1.35,
					string.format(
						"%s RecommendedPower %d vs boss power %d",
						id,
						region.RecommendedPower,
						power
					)
				)
			end
		end)
	end)

	if process.env.BALANCE_WRITE ~= "1" then
		return
	end

	-- Report ------------------------------------------------------------------------
	local lines = {}
	local function w(s)
		table.insert(lines, s or "")
	end
	w("# Balance report")
	w()
	w("Generated by `tests/balance/Balance.spec.luau` from the live config. Regenerate after tuning:")
	w()
	w("```")
	w("BALANCE_WRITE=1 lune run tests/run tests/balance/Balance.spec.luau")
	w("```")
	w()
	w(
		"These are model estimates, not playtest data. The simulated player uses no skills, ascension, equipment, potions,"
	)
	w(
		"events, stars, monster levels or battle rewards, so real players should progress faster. Treat the numbers as"
	)
	w("the pacing *shape* and re-check them against analytics after launch.")
	w()
	w("## Progression pacing")
	w()
	w(
		"| Milestone | Active player (online time) | Casual player (calendar days, 1 h/day) | Income at milestone | Total rolls | Base slots |"
	)
	w("|---|---|---|---|---|---|")
	for _, m in active do
		local c = find(casual, m.Name)
		w(
			string.format(
				"| %s | %s | %s | %s/s | %s | %d |",
				m.Name,
				hours(m.Online),
				if c then string.format("%.1f", c.Time / 86400) else "—",
				Format.number(m.Rate),
				Format.number(m.Rolls),
				m.Slots
			)
		)
	end
	w()
	-- the same active player with different RNG seeds: how much luck moves the curve
	local spread = {}
	for seed = 1, 5 do
		local runs = simulate("Active", seed * 7919)
		for _, m in runs do
			local entry = spread[m.Name] or { Min = math.huge, Max = 0 }
			entry.Min = math.min(entry.Min, m.Online)
			entry.Max = math.max(entry.Max, m.Online)
			spread[m.Name] = entry
		end
	end
	w("RNG spread for the active player over 5 other seeds:")
	w()
	w("| Milestone | Fastest | Slowest |")
	w("|---|---|---|")
	for _, m in active do
		local entry = spread[m.Name]
		if entry then
			w(string.format("| %s | %s | %s |", m.Name, hours(entry.Min), hours(entry.Max)))
		end
	end
	w()
	w("Rolls by rarity over the active run (luck from rebirth bonuses only):")
	w()
	w("| Rarity | Rolled |")
	w("|---|---|")
	for _, id in RarityConfig.Order do
		w(string.format("| %s | %s |", id, Format.number(activeState.rarityCounts[id] or 0)))
	end
	w()
	w("## Dice")
	w()
	w(
		"Expected value of one roll at base luck. *Payback* is how long the average result takes to earn back the dice cost"
	)
	w(
		"when placed (before multipliers). *Sell EV* is the average sell value as a share of the cost, at base luck and at"
	)
	w(
		"the luck hard cap; it must stay below 100% so rolling-and-selling can never print money (enforced by `Economy.spec`)."
	)
	w()
	w(
		"| Dice | Cost | Base luck | Avg income of result | Payback | Sell EV (base / hard cap) | 1 in N for Legendary+ | 1 in N for Mythic+ |"
	)
	w("|---|---|---|---|---|---|---|---|")
	for _, id in DiceConfig.Order do
		local dice = DiceConfig.Dice[id]
		local dist = distribution(dice, dice.BaseLuck)
		local avg, sell, legendary, mythic = 0, 0, 0, 0
		for _, o in dist do
			avg += o.P * o.Income
			sell += o.P * sellOf(o.MonsterId)
			local tier = RarityConfig.tierOf(MonsterConfig.Monsters[o.MonsterId].Rarity)
			if tier >= RarityConfig.tierOf("Legendary") then
				legendary += o.P
			end
			if tier >= RarityConfig.tierOf("Mythic") then
				mythic += o.P
			end
		end
		local capSell = 0
		for _, o in distribution(dice, DiceConfig.Luck.HardCap) do
			capSell += o.P * sellOf(o.MonsterId)
		end
		w(
			string.format(
				"| %s | %s %s | %.2f | %s/s | %s | %.0f%% / %.0f%% | %s | %s |",
				dice.DisplayName,
				Format.number(dice.Cost),
				dice.CostCurrency,
				dice.BaseLuck,
				Format.number(avg),
				hours(dice.Cost / math.max(avg, 1e-9)),
				100 * sell / dice.Cost,
				100 * capSell / dice.Cost,
				if legendary > 0 then Format.number(math.floor(1 / legendary + 0.5)) else "—",
				if mythic > 0 then Format.number(math.floor(1 / mythic + 0.5)) else "—"
			)
		)
	end
	w()
	w("## Rebirth costs")
	w()
	w("| Rebirth | Cost | Requires region | Slots after | Floors after |")
	w("|---|---|---|---|---|")
	for n = 0, 14 do
		w(
			string.format(
				"| %d → %d | %s | %s | %d | %d |",
				n,
				n + 1,
				Format.number(RebirthConfig.cost(n)),
				RebirthConfig.requiredRegion(n),
				BaseLayout.totalSlots(n + 1),
				BaseLayout.floorCount(n + 1)
			)
		)
	end
	w()
	w("## Combat difficulty")
	w()
	w(
		"Encounter power is the sum of `StatMath.power` over the enemies. `RecommendedPower` (RegionConfig) is the hint"
	)
	w(
		"shown to players and is kept within ±35% of the boss (asserted). *Team of 3* is three of the region's most common"
	)
	w("monsters at the given level with no upgrades or equipment.")
	w()
	w(
		"| Region | Recommended | Encounter 1 | Encounter 2 | Encounter 3 | Boss | Team of 3 at Lv 1 | Lv 10 | Lv 25 | Lv 40 |"
	)
	w("|---|---|---|---|---|---|---|---|---|---|")
	for _, id in RegionConfig.Order do
		local region = RegionConfig.Regions[id]
		local row = { region.DisplayName, Format.number(region.RecommendedPower) }
		for _, enc in EnemyConfig.encountersForRegion(id) do
			table.insert(row, Format.number(StatMath.encounterPower(enc)))
		end
		local dice = DiceConfig.Dice[region.DiceId]
		local common, bestP = nil, -1
		for _, o in distribution(dice, dice.BaseLuck) do
			if o.P > bestP then
				common, bestP = o.MonsterId, o.P
			end
		end
		for _, level in { 1, 10, 25, 40 } do
			local inst = monster(common)
			inst.Level = level
			table.insert(row, Format.number(3 * StatMath.power(StatMath.monsterStats(inst, {}, {}))))
		end
		w("| " .. table.concat(row, " | ") .. " |")
	end
	w()
	w("## Offline earnings")
	w()
	w(
		string.format(
			"Offline income = online rate (permanent multipliers only) × min(time away, %d h base cap, up to %d h with upgrades) × %d%% efficiency (up to %d%%). Absences under %d s pay nothing.",
			EconomyConfig.OfflineBaseCapHours,
			EconomyConfig.OfflineMaxCapHours,
			math.floor(EconomyConfig.OfflineBaseEfficiency * 100),
			math.floor(EconomyConfig.OfflineMaxEfficiency * 100),
			EconomyConfig.OfflineMinSeconds
		)
	)
	w()
	fs.writeFile(ctx.Root .. "/docs/BALANCE.md", table.concat(lines, "\n"))
	print("  wrote docs/BALANCE.md")
end
