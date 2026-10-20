-- Chests, the gear they drop, crafting materials and recipes. Each monster holds one weapon, one armor and one accessory.
-- income: bonus to the wearer's income; the same power boosts combat: weapon -> damage, armor -> HP, accessory -> speed.
-- Relics (4th slot, unlocked by the Equipment Slots node) add their power to income and all three combat stats.
-- Every gear instance has a level (1-MAX_LEVEL, +10% power each) and may roll one secondary stat.
local Weighted = require(script.Parent.Weighted)
local C = Color3.fromRGB
local Gear = {}

Gear.Types = {
	{ id = "weapon", name = "Sword", icon = "🗡️" },
	{ id = "armor", name = "Armor", icon = "🛡️" },
	{ id = "accessory", name = "Amulet", icon = "📿" },
	{ id = "relic", name = "Relic", icon = "🔮", relic = true },
}
Gear.MAX_LEVEL = 10
-- secondary stats: value range at Common, scaled up by rarity index
Gear.Secondary = {
	{ id = "income", name = "Income", min = 0.02, max = 0.06 },
	{ id = "crit", name = "Crit", min = 0.01, max = 0.03 },
	{ id = "energy", name = "Energy", min = 0.04, max = 0.1 },
}
Gear.SECONDARY_CHANCE = 0.5
Gear.Rarities = {
	{ id = "Common", color = C(220, 220, 220), income = 0.05 },
	{ id = "Uncommon", color = C(80, 200, 90), income = 0.10 },
	{ id = "Rare", color = C(60, 130, 240), income = 0.20 },
	{ id = "Epic", color = C(160, 80, 230), income = 0.40 },
	{ id = "Legendary", color = C(255, 150, 30), income = 0.80 },
	{ id = "Mythic", color = C(230, 50, 50), income = 1.50 },
}
-- die = the die you must own to buy this chest; weights = relative drop weights per gear rarity
-- relics = this chest can drop relics
local function chest(id, name, cost, die, color, weights, relics)
	return { id = id, name = name, cost = cost, die = die, color = color, weights = weights, relics = relics }
end
Gear.Chests = {
	chest("wooden", "Wooden Chest", 2500, "grassland", C(150, 100, 55), { Common = 70, Uncommon = 25, Rare = 5 }),
	chest("forest", "Forest Chest", 40000, "forest", C(40, 140, 60), { Common = 50, Uncommon = 35, Rare = 12, Epic = 3 }),
	chest("desert", "Desert Chest", 600000, "desert", C(240, 200, 70), { Common = 30, Uncommon = 40, Rare = 22, Epic = 7, Legendary = 1 }),
	chest("mountain", "Mountain Chest", 12e6, "mountain", C(150, 150, 160), { Uncommon = 40, Rare = 35, Epic = 18, Legendary = 6, Mythic = 1 }),
	chest("volcano", "Volcano Chest", 300e6, "volcano", C(230, 60, 40), { Uncommon = 25, Rare = 40, Epic = 25, Legendary = 8, Mythic = 2 }),
	chest("crystal", "Crystal Chest", 8e9, "cave", C(160, 90, 255), { Rare = 40, Epic = 35, Legendary = 20, Mythic = 5 }),
	chest("divine", "Divine Chest", 250e9, "heaven", C(255, 240, 170), { Rare = 20, Epic = 40, Legendary = 30, Mythic = 10 }, true),
	chest("cosmic", "Cosmic Chest", 10e12, "cosmic", C(110, 50, 200), { Epic = 35, Legendary = 45, Mythic = 20 }, true),
}
Gear.TypeById, Gear.RarityById, Gear.ChestById, Gear.RarityIndex = {}, {}, {}, {}
for _, t in Gear.Types do Gear.TypeById[t.id] = t end
for i, r in Gear.Rarities do Gear.RarityById[r.id] = r Gear.RarityIndex[r.id] = i end
for _, c in Gear.Chests do Gear.ChestById[c.id] = c end

-- regional materials (battle drops) and data-driven recipes: pay cash + materials, get gear of that rarity (random type)
Gear.Materials = {
	{ id = "forest_essence", name = "Forest Essence", icon = "🌿" },
	{ id = "desert_relic", name = "Desert Relic", icon = "🏺" },
	{ id = "mountain_shard", name = "Mountain Shard", icon = "🪨" },
	{ id = "ember_shard", name = "Ember Shard", icon = "🔥" },
	{ id = "crystal_fragment", name = "Crystal Fragment", icon = "💎" },
	{ id = "divine_dust", name = "Divine Dust", icon = "✨" },
	{ id = "cosmic_core", name = "Cosmic Core", icon = "🌌" },
}
Gear.Recipes = {
	{ id = "rare_gear", name = "Forge Rare Gear", rarity = "Rare", cash = 10000, mats = { forest_essence = 5 } },
	{ id = "epic_gear", name = "Forge Epic Gear", rarity = "Epic", cash = 250000, mats = { forest_essence = 15, desert_relic = 5 } },
	{ id = "legendary_gear", name = "Forge Legendary Gear", rarity = "Legendary", cash = 25e6, mats = { desert_relic = 20, mountain_shard = 10 } },
	{ id = "mythic_gear", name = "Forge Mythic Gear", rarity = "Mythic", cash = 5e9, mats = { ember_shard = 20, crystal_fragment = 10 } },
	{ id = "forge_relic", name = "Forge a Relic", rarity = "Legendary", gtype = "relic", cash = 50e9, mats = { divine_dust = 15, cosmic_core = 5 } },
	-- event recipes: only craftable while that event (ProgressConfig.Events) is active
	{ id = "hallow_relic", name = "Hallowed Relic (event)", rarity = "Epic", gtype = "relic", event = "halloween_hunt", cash = 1e6, mats = { forest_essence = 20 } },
}
Gear.MaterialById, Gear.RecipeById = {}, {}
for _, m in Gear.Materials do Gear.MaterialById[m.id] = m end
for _, r in Gear.Recipes do Gear.RecipeById[r.id] = r end

-- chest luck reshapes weights toward rarer drops: weight x (1 + luck)^(rarity index - 1), then renormalized
local function entries(c, luck: number?)
	local out = {}
	for i, rar in Gear.Rarities do
		if c.weights[rar.id] then table.insert(out, { rar.id, c.weights[rar.id] * (1 + math.max(0, luck or 0)) ^ (i - 1) }) end
	end
	return out
end
-- real drop odds for a chest, summing to 1
function Gear.odds(c, luck: number?)
	local list, out = entries(c, luck), {}
	local p = Weighted.odds(list) or {}
	for i, e in list do if p[i] > 0 then out[e[1]] = p[i] end end
	return out
end
-- a random gear type; relics only from chests that drop them
function Gear.randomType(rng: Random, relics: boolean?)
	local pool = {}
	for _, t in Gear.Types do if relics or not t.relic then table.insert(pool, t.id) end end
	return pool[rng:NextInteger(1, #pool)]
end
function Gear.roll(c, rng: Random, luck: number?)
	return Weighted.pick(entries(c, luck), rng), Gear.randomType(rng, c.relics)
end
-- optional secondary stat for a new gear piece: { stat, v } or nil
function Gear.rollSecondary(rarity: string, rng: Random)
	if rng:NextNumber() >= Gear.SECONDARY_CHANCE then return nil end
	local s = Gear.Secondary[rng:NextInteger(1, #Gear.Secondary)]
	local scale = 1 + 0.5 * (Gear.RarityIndex[rarity] - 1)
	return { stat = s.id, v = math.floor((s.min + (s.max - s.min) * rng:NextNumber()) * scale * 1000) / 1000 }
end
-- main power of a gear instance (rarity power x level)
function Gear.power(g): number
	return Gear.RarityById[g.r].income * (1 + 0.1 * ((g.lvl or 1) - 1))
end
function Gear.upgradeCost(g): number
	return math.floor(1000 * 4 ^ (Gear.RarityIndex[g.r] - 1) * 1.5 ^ ((g.lvl or 1) - 1))
end
function Gear.name(g)
	return g.r .. " " .. Gear.TypeById[g.t].name .. ((g.lvl or 1) > 1 and (" +" .. g.lvl - 1) or "")
end
function Gear.secondaryText(g)
	if not g.sec then return "" end
	for _, s in Gear.Secondary do if s.id == g.sec.stat then return "+" .. math.floor(g.sec.v * 1000 + 0.5) / 10 .. "% " .. s.name end end
	return ""
end
return Gear
