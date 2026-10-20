-- The 9 dice, in progression order. Buying one requires owning the previous die.
-- luck multiplies Rare+ odds; maxTier is the rarest tier (index into MonsterConfig.Rarities) this die can roll.
local C = Color3.fromRGB
local Dice = {}
local function d(id, name, cost, luck, maxTier, color)
	return { id = id, name = name, cost = cost, luck = luck, maxTier = maxTier, color = color }
end
Dice.List = {
	d("grassland", "Grassland Die", 0, 1, 5, C(90, 220, 90)),
	d("forest", "Forest Die", 5000, 1.5, 6, C(40, 140, 60)),
	d("desert", "Desert Die", 75000, 2.5, 7, C(240, 200, 70)),
	d("mountain", "Mountain Die", 1e6, 4, 8, C(150, 150, 160)),
	d("volcano", "Volcano Die", 25e6, 6, 9, C(230, 60, 40)),
	d("cave", "Cave Die", 750e6, 10, 10, C(60, 70, 90)),
	d("heaven", "Heaven Die", 20e9, 16, 11, C(250, 250, 255)),
	d("cosmic", "Cosmic Die", 2e12, 25, 12, C(120, 60, 200)),
	d("glitch", "Glitch Die", 500e12, 40, 12, C(0, 255, 120)),
}
Dice.ById, Dice.Index = {}, {}
for i, die in Dice.List do Dice.ById[die.id] = die Dice.Index[die.id] = i end
return Dice
