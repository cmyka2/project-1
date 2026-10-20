-- Battle balance: monster combat stats, elements, status effects, regions/stages/enemies, rewards.
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

-- Status effects. Timing: effects tick at the start of the affected unit's own turn (dot/hot), then count down.
-- Stacking: re-applying refreshes the duration (no stacks). self = lands on the caster instead of the target.
-- skip = the unit loses its next turn; afterwards it is immune to skip effects for CONTROL_IMMUNE turns
-- (bosses BOSS_CONTROL_IMMUNE), so freeze/stun can never chain-lock. cleanse = removes the caster's harmful effects.
B.Status = {
	burn = { name = "Burn", icon = "🔥", dur = 2, dot = 0.08 },
	poison = { name = "Poison", icon = "☠️", dur = 3, dot = 0.05 },
	freeze = { name = "Freeze", icon = "🧊", dur = 1, skip = true },
	stun = { name = "Stun", icon = "💫", dur = 1, skip = true },
	weaken = { name = "Weaken", icon = "🥀", dur = 2, dealt = 0.75 }, -- deals 25% less
	expose = { name = "Expose", icon = "🎯", dur = 2, armor = 0.5 }, -- defense halved
	shield = { name = "Shield", icon = "🛡️", dur = 2, absorb = 0.25, self = true }, -- absorbs 25% of max HP
	regen = { name = "Regen", icon = "💚", dur = 3, hot = 0.07, self = true, cleanse = true },
}
B.SkillStatus = {
	Fire = "burn", Nature = "poison", Water = "freeze", Lightning = "stun",
	Shadow = "weaken", Cosmic = "expose", Earth = "shield", Light = "regen",
}
B.CONTROL_IMMUNE, B.BOSS_CONTROL_IMMUNE = 2, 4

function B.monsterStats(def, variant)
	local t = Config.Tier[def.rarity] - 1
	local m = B.VariantMult[variant] or 1
	return {
		name = (variant ~= "Normal" and variant .. " " or "") .. def.name, element = def.element,
		hp = math.floor(100 * 1.6 ^ t * m), dmg = math.floor(20 * 1.6 ^ t * m), def = 10 + 6 * t, spd = 10 + 2 * t,
	}
end

local function e(name, element, hp, dmg, def, spd, boss)
	return { name = name, element = element, hp = hp, dmg = dmg, def = def, spd = spd, boss = boss }
end
-- a region's first stage needs the previous region's last stage cleared, plus owning requiresDie.
-- mats = crafting materials per win; firstClearGear = guaranteed gear rarity on the first clear.
B.Regions = {
	{
		id = "grassland", name = "Grassland", icon = "🌿",
		stages = {
			{ id = "grass1", name = "Meadow Skirmish", cash = 500, mats = { forest_essence = 1 },
				enemies = { e("Wild Slime", "Nature", 80, 12, 5, 8), e("Wild Slime", "Nature", 80, 12, 5, 8) } },
			{ id = "grass2", name = "Goblin Ambush", cash = 1500, mats = { forest_essence = 2 },
				enemies = { e("Moss Goblin", "Nature", 140, 18, 10, 11), e("Moss Goblin", "Nature", 140, 18, 10, 11), e("Thorn Sprite", "Earth", 90, 24, 6, 14) } },
			{ id = "grass3", name = "BOSS: Overgrown Brute", cash = 5000, boss = true, firstClearGear = "Rare", mats = { forest_essence = 4 },
				enemies = { e("Overgrown Brute", "Earth", 900, 35, 25, 9, true), e("Thorn Sprite", "Earth", 90, 24, 6, 14) } },
		},
	},
	{
		id = "forest", name = "Forest", icon = "🌲", requiresDie = "forest",
		stages = {
			{ id = "forest1", name = "Rootbound Path", cash = 20000, mats = { forest_essence = 3 },
				enemies = { e("Bark Hound", "Nature", 600, 60, 30, 13), e("Bark Hound", "Nature", 600, 60, 30, 13), e("Ember Wisp", "Fire", 350, 80, 15, 18) } },
			{ id = "forest2", name = "Hollow Grove", cash = 50000, mats = { forest_essence = 3, desert_relic = 1 },
				enemies = { e("Grove Warden", "Earth", 1400, 70, 50, 10), e("Spore Witch", "Shadow", 700, 95, 20, 16), e("Ember Wisp", "Fire", 350, 80, 15, 18) } },
			{ id = "forest3", name = "BOSS: Elder Root", cash = 150000, boss = true, firstClearGear = "Epic", mats = { desert_relic = 3 },
				enemies = { e("Elder Root", "Nature", 6000, 110, 70, 8, true), e("Spore Witch", "Shadow", 700, 95, 20, 16) } },
		},
	},
}
B.StageById, B.PrevStage, B.RegionOf = {}, {}, {}
local prevLast
for _, r in B.Regions do
	for i, s in r.stages do
		B.StageById[s.id] = s
		B.RegionOf[s.id] = r
		B.PrevStage[s.id] = i > 1 and r.stages[i - 1].id or prevLast
	end
	prevLast = r.stages[#r.stages].id
end
return B
