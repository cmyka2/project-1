-- Battle balance: monster combat stats, elements, regions/stages/enemies, rewards.
local Config = require(script.Parent.MonsterConfig)
local B = {}

B.Strong = { -- attacker element -> defender elements it beats (x1.25); the reverse matchup is x0.8
	Nature = { Earth = true }, Earth = { Lightning = true }, Fire = { Nature = true }, Water = { Fire = true },
	Lightning = { Water = true }, Light = { Shadow = true }, Shadow = { Light = true },
}
B.STRONG_MULT, B.WEAK_MULT = 1.25, 0.8
B.SkillName = {
	Nature = "Vine Lash", Earth = "Rock Slam", Water = "Tidal Bite", Fire = "Flame Burst",
	Lightning = "Thunder Strike", Light = "Radiant Beam", Shadow = "Shadow Claw", Cosmic = "Star Fall",
}
B.VariantMult = { Normal = 1, Huge = 1.5, Monstrous = 2.5 }

function B.monsterStats(def, variant)
	local t = Config.Tier[def.rarity] - 1
	local m = B.VariantMult[variant] or 1
	return {
		name = (variant ~= "Normal" and variant .. " " or "") .. def.name, element = def.element,
		hp = math.floor(100 * 1.6 ^ t * m), dmg = math.floor(20 * 1.6 ^ t * m), def = 10 + 6 * t, spd = 10 + 2 * t,
	}
end

local function e(name, element, hp, dmg, def, spd) return { name = name, element = element, hp = hp, dmg = dmg, def = def, spd = spd } end
B.Regions = {
	{
		id = "grassland", name = "Grassland",
		stages = {
			{ id = "grass1", name = "Meadow Skirmish", cash = 500,
				enemies = { e("Wild Slime", "Nature", 80, 12, 5, 8), e("Wild Slime", "Nature", 80, 12, 5, 8) } },
			{ id = "grass2", name = "Goblin Ambush", cash = 1500,
				enemies = { e("Moss Goblin", "Nature", 140, 18, 10, 11), e("Moss Goblin", "Nature", 140, 18, 10, 11), e("Thorn Sprite", "Earth", 90, 24, 6, 14) } },
			{ id = "grass3", name = "BOSS: Overgrown Brute", cash = 5000, boss = true, firstClearGear = "Rare",
				enemies = { e("Overgrown Brute", "Earth", 900, 35, 25, 9), e("Thorn Sprite", "Earth", 90, 24, 6, 14) } },
		},
	},
}
B.StageById, B.PrevStage = {}, {}
for _, r in B.Regions do
	for i, s in r.stages do
		B.StageById[s.id] = s
		B.PrevStage[s.id] = r.stages[i - 1] and r.stages[i - 1].id
	end
end
return B
