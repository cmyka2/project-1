-- Pure progression math shared by server (authoritative) and client (previews only).
local F = {}

-- BASE SLOTS AND FLOORS
-- total slots = 5 + rebirths (capped by MAX_SLOTS); floors = min(3, 1 + floor(rebirths / 6)).
-- Slot i unlocks at rebirth max(0, i - 5) and sits on the floor that rebirth count unlocks:
-- floor 1 = slots 1-10 (the 5 starters + rebirths 1-5), floor 2 = slots 11-16 (rebirths 6-11),
-- floor 3 = slot 17 onward (rebirth 12+; later slots keep landing on the top floor).
F.BASE_SLOTS, F.MAX_SLOTS, F.MAX_FLOORS, F.REBIRTHS_PER_FLOOR = 5, 40, 3, 6
function F.slots(rebirths: number): number
	return math.min(F.MAX_SLOTS, F.BASE_SLOTS + rebirths)
end
function F.floors(rebirths: number): number
	return math.min(F.MAX_FLOORS, 1 + rebirths // F.REBIRTHS_PER_FLOOR)
end
function F.slotRebirth(i: number): number
	return math.max(0, i - F.BASE_SLOTS)
end
function F.slotFloor(i: number): number
	return F.floors(F.slotRebirth(i))
end

-- MONSTER LEVELS AND FUSION
-- income = base x levelMult x fusionMult x (1 + skill) x (1 + gear) x (1 + rebirth): each bonus source
-- is additive inside its own bracket and the brackets multiply, so no source is applied twice.
F.MAX_LEVEL, F.MAX_FUSION, F.FUSE_COPIES = 50, 5, 3
function F.levelMult(lvl: number): number return 1 + 0.25 * (lvl - 1) end
function F.fusionMult(fr: number): number return 1 + 0.5 * fr end
function F.combatMult(lvl: number, fr: number): number return (1 + 0.05 * (lvl - 1)) * (1 + 0.2 * fr) end
-- cost to go from lvl to lvl + 1; base = the monster's base income
function F.upgradeCost(base: number, lvl: number): number
	return math.floor(base * 25 * 1.2 ^ (lvl - 1))
end
function F.fuseCost(base: number, fr: number): number
	return math.floor(base * 100 * (fr + 1))
end
function F.sellValue(base: number, lvl: number, sellBonus: number): number
	return math.floor(base * 20 * F.levelMult(lvl) * (1 + sellBonus))
end

-- OFFLINE EARNINGS: server timestamps only; elapsed is clamped to [0, cap] (default 8h, skills/ascension extend it)
F.OFFLINE_CAP = 8 * 3600
function F.offline(elapsed: number, incomePerSec: number, cap: number?): (number, number)
	if typeof(elapsed) ~= "number" or elapsed ~= elapsed then return 0, 0 end
	local secs = math.clamp(math.floor(elapsed), 0, cap or F.OFFLINE_CAP)
	return math.floor(secs * math.max(0, incomePerSec)), secs
end

return F
