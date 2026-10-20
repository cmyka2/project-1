-- Rebirth rules. Each rebirth: meet the requirement, cash resets, +1 base slot (floors at 6 and 12),
-- permanent income/luck bonus and Ascension Points. Everything not listed in Resets is kept.
local Rebirth = {}
Rebirth.Resets = { "Cash" }
Rebirth.Keeps = { "Monsters & levels", "Index", "Placed monsters", "Gear", "Dice", "Upgrade tree", "Materials" }
Rebirth.INCOME_BONUS = 0.10 -- +10% income per rebirth (its own bracket, see Formulas)
Rebirth.LUCK_BONUS = 0.02 -- +2% luck per rebirth, added to skill luck before diminishing returns

-- cost curve, tuned with tools/headless/pacing.luau: a greedy active player's first rebirth lands around
-- 10-15 minutes, floor 2 (rebirth 6) after roughly an hour and a half, and cycles stay meaningful instead of chaining.
-- Steep x6 per rebirth early (dice make income jump), gentler x2.5 after rebirth 6 so floor 3 stays reachable.
Rebirth.BASE_COST, Rebirth.EARLY_GROWTH, Rebirth.LATE_GROWTH, Rebirth.BEND = 500000, 6, 2.5, 6
function Rebirth.cost(rebirths: number)
	local early = math.min(rebirths, Rebirth.BEND)
	return math.floor(Rebirth.BASE_COST * Rebirth.EARLY_GROWTH ^ early * Rebirth.LATE_GROWTH ^ (rebirths - early))
end
-- stage = battle stage that must be cleared first (nil = none)
-- count monsters of at least tier minTier must be owned (kept, not consumed), like Steal a Brainrot's rebirths:
-- 2 Rares for the first rebirth, then the bar climbs one rarity every 2 rebirths (MonsterConfig.Rarities tiers)
function Rebirth.requirement(rebirths: number)
	return { cost = Rebirth.cost(rebirths), stage = rebirths >= 3 and "grass3" or nil,
		minTier = math.min(12, 3 + rebirths // 2), count = 2 }
end
-- AP for reaching rebirth n: 1, plus 5 on each floor milestone
function Rebirth.points(n: number)
	return n % 6 == 0 and 6 or 1
end

-- the whole reset, applied to the data table in one non-yielding step. Returns AP awarded.
function Rebirth.apply(d)
	d.Cash = 0
	d.Rebirths += 1
	local ap = Rebirth.points(d.Rebirths)
	d.AscensionPoints = (d.AscensionPoints or 0) + ap
	return ap
end
return Rebirth
