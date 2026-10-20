-- How luck sources combine, and how luck reshapes rarity weights.
-- raw luck = die luck x (1 + skill luck + rebirth luck)
-- base luck = raw up to SOFT_CAP, then logarithmic (diminishing returns) - this keeps permanent stacking controlled.
-- Multipliers (gamepasses, potions, server luck, events, Golden/Rainbow/Lucky rolls) apply AFTER that, so an
-- advertised "2x luck" really doubles luck; the result never exceeds HARD_CAP.
-- A tier's weight is multiplied by luck ^ TierPower[tier]: Common/Uncommon are untouched, rarer tiers gain more.
-- The weights are then normalized, so odds always sum to 100% (see MonsterConfig.pool).
local L = {}
L.SOFT_CAP, L.HARD_CAP = 25, 1e5
L.TierPower = { 0, 0, 0.25, 0.5, 0.75 } -- tiers past the list use 1

function L.effective(raw: number): number
	if typeof(raw) ~= "number" or raw ~= raw or raw < 1 then return 1 end
	if raw <= L.SOFT_CAP then return raw end
	return math.min(L.HARD_CAP, L.SOFT_CAP * (1 + math.log(raw / L.SOFT_CAP)))
end

function L.combine(dieLuck: number, additive: number, mult: number?): number
	return math.min(L.HARD_CAP, L.effective(dieLuck * (1 + math.max(0, additive))) * math.max(1, mult or 1))
end

function L.tierMult(luck: number, tier: number): number
	return luck ^ (L.TierPower[tier] or 1)
end

return L
