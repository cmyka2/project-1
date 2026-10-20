-- Per-monster modifiers from the roll-and-earn games (Spin a Soccer Card / Anime Card Farm mutations, Grow a Garden /
-- Plants vs Brainrots weather mutations, Anime Dice traits). Both live on the monster instance and stack with
-- level, fusion, variant, gear and skills (each is its own multiplier bracket).
--   mutation (inst.mu): rolled once with the monster. Natural ones are rare everywhere; biome ones only roll
--     while that biome is active. Multiplies income.
--   trait (inst.tr): rerolled at will for TRAIT_COST Gems. Multiplies income and/or combat.
local Weighted = require(script.Parent.Weighted)
local C = Color3.fromRGB
local T = {}

T.Mutations = {
	-- natural: oneIn per roll, checked rarest first
	{ id = "rainbow", name = "Rainbow", mult = 4, oneIn = 1500, color = C(255, 120, 255) },
	{ id = "diamond", name = "Diamond", mult = 2, oneIn = 250, color = C(120, 230, 255) },
	{ id = "golden", name = "Golden", mult = 1.5, oneIn = 50, color = C(255, 210, 60) },
	-- biome: chance per roll while that biome (ProgressConfig.Biomes) is active
	{ id = "wet", name = "Wet", mult = 1.5, biome = "rainy", chance = 0.15, color = C(110, 170, 255) },
	{ id = "scorched", name = "Scorched", mult = 2, biome = "heatwave", chance = 0.15, color = C(255, 120, 60) },
	{ id = "shocked", name = "Shocked", mult = 2.5, biome = "thunderstorm", chance = 0.12, color = C(255, 240, 90) },
	{ id = "blooming", name = "Blooming", mult = 1.5, biome = "bloom", chance = 0.15, color = C(255, 160, 200) },
	{ id = "sandy", name = "Sandy", mult = 1.5, biome = "sandstorm", chance = 0.15, color = C(230, 200, 130) },
	{ id = "auroral", name = "Auroral", mult = 3, biome = "aurora", chance = 0.12, color = C(170, 255, 220) },
	{ id = "bloodrot", name = "Bloodrot", mult = 3, biome = "blood_moon", chance = 0.12, color = C(200, 30, 50) },
	{ id = "starfallen", name = "Starfallen", mult = 5, biome = "starfall", chance = 0.1, color = C(190, 160, 255) },
}
T.MutationById = {}
for _, m in T.Mutations do T.MutationById[m.id] = m end

-- the mutation for a fresh roll (nil = none); biomeId = the active biome or nil
function T.rollMutation(rng: Random, biomeId: string?): string?
	if biomeId then
		for _, m in T.Mutations do
			if m.biome == biomeId and rng:NextNumber() < m.chance then return m.id end
		end
	end
	for _, m in T.Mutations do
		if m.oneIn and rng:NextNumber() < 1 / m.oneIn then return m.id end
	end
	return nil
end

-- traits: weight = relative reroll odds; income / combat = multipliers (1 = none)
T.TRAIT_COST = 1 -- Gems per reroll
T.Traits = {
	{ id = "money1", name = "Money I", weight = 300, income = 1.1, combat = 1, color = C(150, 230, 150) },
	{ id = "money2", name = "Money II", weight = 150, income = 1.25, combat = 1, color = C(110, 230, 110) },
	{ id = "money3", name = "Money III", weight = 50, income = 1.6, combat = 1, color = C(60, 230, 80) },
	{ id = "power1", name = "Power I", weight = 300, income = 1, combat = 1.1, color = C(230, 150, 150) },
	{ id = "power2", name = "Power II", weight = 150, income = 1, combat = 1.25, color = C(230, 110, 110) },
	{ id = "power3", name = "Power III", weight = 50, income = 1, combat = 1.6, color = C(240, 60, 60) },
	{ id = "samurai", name = "Samurai", weight = 12, income = 2, combat = 2, color = C(255, 170, 60) },
	{ id = "shogun", name = "Shogun", weight = 4, income = 3, combat = 3, color = C(255, 120, 40) },
	{ id = "monarch", name = "Monarch", weight = 1, income = 5, combat = 5, color = C(200, 80, 255) },
	{ id = "transcendent", name = "Transcendent", weight = 0.1, income = 10, combat = 10, color = C(120, 255, 255) },
}
T.TraitById = {}
local traitPool = {}
for _, t in T.Traits do
	T.TraitById[t.id] = t
	table.insert(traitPool, { t.id, t.weight })
end
function T.rollTrait(rng: Random): string
	return Weighted.pick(traitPool, rng)
end
-- real reroll odds (shown in the Backpack before spending Gems)
function T.traitOdds()
	local p, out = Weighted.odds(traitPool), {}
	for i, e in traitPool do out[e[1]] = p[i] end
	return out
end

function T.incomeMult(inst): number
	local m = inst.mu and T.MutationById[inst.mu]
	local t = inst.tr and T.TraitById[inst.tr]
	return (m and m.mult or 1) * (t and t.income or 1)
end
function T.combatMult(inst): number
	local t = inst.tr and T.TraitById[inst.tr]
	return t and t.combat or 1
end
return T
