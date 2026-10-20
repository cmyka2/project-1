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
	mark = { name = "Mark", icon = "📍", dur = 2, taken = 1.2 }, -- takes 20% more; applied to every foe by ultimates
}
B.SkillStatus = {
	Fire = "burn", Nature = "poison", Water = "freeze", Lightning = "stun",
	Shadow = "weaken", Cosmic = "expose", Earth = "shield", Light = "regen",
}
B.CONTROL_IMMUNE, B.BOSS_CONTROL_IMMUNE = 2, 4

-- roles (from MonsterConfig.RoleByElement): stat multipliers plus one role trait used by BattleEngine on skills
-- heal = heals the most-hurt ally (fraction of its max HP), energy = gives every ally energy,
-- extend = +turns on statuses it applies, crit = extra critical chance
B.Roles = {
	Attacker = { hp = 0.9, dmg = 1.2 },
	Tank = { hp = 1.35, dmg = 0.85, def = 10 },
	Healer = { hp = 1, dmg = 0.9, heal = 0.15 },
	Support = { hp = 1.05, dmg = 0.95, energy = 20 },
	Controller = { hp = 1, dmg = 1, extend = 1 },
	Specialist = { hp = 0.95, dmg = 1.05, crit = 0.05 },
}

function B.monsterStats(def, variant)
	local t = Config.Tier[def.rarity] - 1
	local m = B.VariantMult[variant] or 1
	local role = Config.RoleByElement[def.element] or "Attacker"
	local r = B.Roles[role]
	return {
		name = (variant ~= "Normal" and variant .. " " or "") .. def.name, element = def.element, role = role,
		hp = math.floor(100 * 1.6 ^ t * m * r.hp), dmg = math.floor(20 * 1.6 ^ t * m * r.dmg), def = 10 + 6 * t + (r.def or 0), spd = 10 + 2 * t,
	}
end

local function e(name, element, hp, dmg, def, spd, boss)
	return { name = name, element = element, hp = hp, dmg = dmg, def = def, spd = spd, boss = boss }
end
-- enemy ids for AssetRegistry (Enemies / Bosses): the name in snake_case, e.g. "Overgrown Brute" -> overgrown_brute
function B.enemyId(name: string): string
	return (name:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
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
-- regions 3-9 follow one template, scaled by S per region past Forest (placeholder balance)
local S = 2.5
local LATER = {
	{ "desert", "Desert", "🏜️", "desert_relic", "Epic", { "Dust Scarab", "Earth" }, { "Sand Djinn", "Fire" }, { "Pharaoh of Dust", "Earth" } },
	{ "mountain", "Mountain", "🏔️", "mountain_shard", "Legendary", { "Ice Ram", "Water" }, { "Crag Golem", "Earth" }, { "Frost King", "Water" } },
	{ "volcano", "Volcano", "🌋", "ember_shard", "Legendary", { "Lava Hound", "Fire" }, { "Ash Wyrm", "Fire" }, { "Infernos, the World Eater", "Fire" } },
	{ "cave", "Cave", "🕳️", "crystal_fragment", "Mythic", { "Crystal Bat", "Shadow" }, { "Deep Lurker", "Earth" }, { "The Buried Ancient", "Earth" } },
	{ "heaven", "Heaven", "☁️", "divine_dust", "Mythic", { "Cloud Sprite", "Light" }, { "Halo Knight", "Light" }, { "The Fallen Luminary", "Light" } },
	{ "cosmic", "Cosmic", "🌌", "cosmic_core", "Mythic", { "Star Mote", "Cosmic" }, { "Nebula Eater", "Cosmic" }, { "The Star Devourer", "Cosmic" } },
	{ "glitch", "Glitch", "👾", "cosmic_core", "Mythic", { "Corrupt Byte", "Shadow" }, { "Stack Overflow", "Cosmic" }, { "The Null Sovereign", "Cosmic" } },
}
for i, r in LATER do
	local k = S ^ i
	local function mob(m, hp, dmg, def, spd, boss) return e(m[1], m[2], math.floor(hp * k), math.floor(dmg * k), math.floor(def * (1 + i * 0.6)), spd + i, boss) end
	local mat = r[4]
	table.insert(B.Regions, {
		id = r[1], name = r[2], icon = r[3], requiresDie = r[1],
		stages = {
			{ id = r[1] .. "1", name = r[2] .. " Outskirts", cash = math.floor(20000 * 8 ^ i), mats = { [mat] = 3 },
				enemies = { mob(r[6], 600, 60, 30, 13), mob(r[6], 600, 60, 30, 13), mob(r[7], 400, 85, 15, 18) } },
			{ id = r[1] .. "2", name = r[2] .. " Depths", cash = math.floor(50000 * 8 ^ i), mats = { [mat] = 4 },
				enemies = { mob(r[7], 1400, 75, 50, 11), mob(r[6], 800, 95, 20, 16), mob(r[7], 400, 85, 15, 18) } },
			{ id = r[1] .. "3", name = "BOSS: " .. r[8][1], cash = math.floor(150000 * 8 ^ i), boss = true, firstClearGear = r[5], mats = { [mat] = 6 },
				enemies = { mob(r[8], 6000, 115, 70, 8, true), mob(r[7], 800, 95, 20, 16) } },
		},
	})
end
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
