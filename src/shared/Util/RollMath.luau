--!strict
-- Pure roll math (no Roblox services): luck transform, rarity odds and
-- weighted selection. Randomness is injected so tests can use a seeded rng.
--
-- Probability model (two-stage, documented in docs/FORMULAS.md):
--   w'_r  = w_r * L ^ e_r         (e_r = RarityConfig LuckExponent, L = effective luck)
--   P(r)  = w'_r / sum(w')        over rarities that have >= 1 eligible monster
--   P(m|r) = RollWeight_m / sum(RollWeight of eligible monsters of rarity r)

local DiceConfig = require(script.Parent.Parent.Config.DiceConfig)
local MonsterConfig = require(script.Parent.Parent.Config.MonsterConfig)
local RarityConfig = require(script.Parent.Parent.Config.RarityConfig)

export type Odds = { Rarity: string, Chance: number }
export type WeightedEntry<T> = { Value: T, Weight: number }

local RollMath = {}

local function isPositiveFinite(x: number): boolean
	return x == x and x > 0 and x < math.huge
end

-- Soft-capped luck. Linear up to SoftCapStart, diminishing afterwards.
function RollMath.effectiveLuck(raw: number): number
	local cfg = DiceConfig.Luck
	if raw ~= raw or raw <= 0 then
		return 1
	end
	local value = raw
	if raw > cfg.SoftCapStart then
		value = cfg.SoftCapStart + (raw - cfg.SoftCapStart) ^ cfg.SoftCapExponent
	end
	return math.clamp(value, 1, cfg.HardCap)
end

-- Monsters of a dice pool grouped by rarity, skipping unknown ids and
-- non-positive weights.
function RollMath.poolByRarity(pool: { string }): { [string]: { WeightedEntry<string> } }
	local grouped: { [string]: { WeightedEntry<string> } } = {}
	for _, monsterId in pool do
		local def = MonsterConfig.Monsters[monsterId]
		if def and isPositiveFinite(def.RollWeight) and RarityConfig.Rarities[def.Rarity] then
			local list = grouped[def.Rarity]
			if not list then
				list = {}
				grouped[def.Rarity] = list
			end
			table.insert(list, { Value = monsterId, Weight = def.RollWeight })
		end
	end
	return grouped
end

-- Final rarity probabilities for a dice at a given effective luck, sorted by tier.
function RollMath.rarityOdds(rarityWeights: { [string]: number }, pool: { string }, luck: number): { Odds }
	local grouped = RollMath.poolByRarity(pool)
	local weights: { [string]: number } = {}
	local total = 0
	for rarity, weight in rarityWeights do
		local def = RarityConfig.Rarities[rarity]
		if def and grouped[rarity] and isPositiveFinite(weight) then
			local w = weight * luck ^ def.LuckExponent
			if isPositiveFinite(w) then
				weights[rarity] = w
				total += w
			end
		end
	end
	local odds: { Odds } = {}
	if total <= 0 then
		return odds
	end
	for rarity, w in weights do
		table.insert(odds, { Rarity = rarity, Chance = w / total })
	end
	table.sort(odds, function(a, b)
		return RarityConfig.tierOf(a.Rarity) < RarityConfig.tierOf(b.Rarity)
	end)
	return odds
end

-- Picks one value proportionally to weight. `rng` returns a float in [0, 1).
-- Returns nil only when no entry has a positive finite weight.
function RollMath.pickWeighted<T>(entries: { WeightedEntry<T> }, rng: () -> number): T?
	local total = 0
	for _, entry in entries do
		if isPositiveFinite(entry.Weight) then
			total += entry.Weight
		end
	end
	if total <= 0 then
		return nil
	end
	local target = math.clamp(rng(), 0, 0.9999999999) * total
	local last: T? = nil
	for _, entry in entries do
		if isPositiveFinite(entry.Weight) then
			last = entry.Value
			target -= entry.Weight
			if target < 0 then
				return entry.Value
			end
		end
	end
	return last -- floating point safety: fall through to the last valid entry
end

-- Full two-stage roll. Returns (monsterId, rarity) or nil if the pool is empty.
function RollMath.roll(
	rarityWeights: { [string]: number },
	pool: { string },
	luck: number,
	rng: () -> number
): (string?, string?)
	local odds = RollMath.rarityOdds(rarityWeights, pool, luck)
	if #odds == 0 then
		return nil, nil
	end
	local entries: { WeightedEntry<string> } = {}
	for _, o in odds do
		table.insert(entries, { Value = o.Rarity, Weight = o.Chance })
	end
	local rarity = RollMath.pickWeighted(entries, rng)
	if not rarity then
		return nil, nil
	end
	local grouped = RollMath.poolByRarity(pool)
	local monsterId = RollMath.pickWeighted(grouped[rarity], rng)
	return monsterId, rarity
end

return RollMath
