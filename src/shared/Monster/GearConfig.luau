-- Chests, the gear they drop, crafting materials and recipes. Each monster holds one weapon, one armor and one accessory.
-- income: bonus to the wearer's income; the same value boosts combat: weapon -> damage, armor -> HP, accessory -> speed.
local Weighted = require(script.Parent.Weighted)
local C = Color3.fromRGB
local Gear = {}

Gear.Types = {
	{ id = "weapon", name = "Sword", icon = "🗡️" },
	{ id = "armor", name = "Armor", icon = "🛡️" },
	{ id = "accessory", name = "Amulet", icon = "📿" },
}
Gear.Rarities = {
	{ id = "Common", color = C(220, 220, 220), income = 0.05 },
	{ id = "Uncommon", color = C(80, 200, 90), income = 0.10 },
	{ id = "Rare", color = C(60, 130, 240), income = 0.20 },
	{ id = "Epic", color = C(160, 80, 230), income = 0.40 },
	{ id = "Legendary", color = C(255, 150, 30), income = 0.80 },
	{ id = "Mythic", color = C(230, 50, 50), income = 1.50 },
}
-- die = the die you must own to buy this chest; weights = relative drop weights per gear rarity
local function chest(id, name, cost, die, color, weights)
	return { id = id, name = name, cost = cost, die = die, color = color, weights = weights }
end
Gear.Chests = {
	chest("wooden", "Wooden Chest", 2500, "grassland", C(150, 100, 55), { Common = 70, Uncommon = 25, Rare = 5 }),
	chest("forest", "Forest Chest", 40000, "forest", C(40, 140, 60), { Common = 50, Uncommon = 35, Rare = 12, Epic = 3 }),
	chest("desert", "Desert Chest", 600000, "desert", C(240, 200, 70), { Common = 30, Uncommon = 40, Rare = 22, Epic = 7, Legendary = 1 }),
	chest("mountain", "Mountain Chest", 12e6, "mountain", C(150, 150, 160), { Uncommon = 40, Rare = 35, Epic = 18, Legendary = 6, Mythic = 1 }),
	chest("volcano", "Volcano Chest", 300e6, "volcano", C(230, 60, 40), { Uncommon = 25, Rare = 40, Epic = 25, Legendary = 8, Mythic = 2 }),
	chest("crystal", "Crystal Chest", 8e9, "cave", C(160, 90, 255), { Rare = 40, Epic = 35, Legendary = 20, Mythic = 5 }),
	chest("divine", "Divine Chest", 250e9, "heaven", C(255, 240, 170), { Rare = 20, Epic = 40, Legendary = 30, Mythic = 10 }),
	chest("cosmic", "Cosmic Chest", 10e12, "cosmic", C(110, 50, 200), { Epic = 35, Legendary = 45, Mythic = 20 }),
}
Gear.TypeById, Gear.RarityById, Gear.ChestById = {}, {}, {}
for _, t in Gear.Types do Gear.TypeById[t.id] = t end
for _, r in Gear.Rarities do Gear.RarityById[r.id] = r end
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
}
Gear.MaterialById, Gear.RecipeById = {}, {}
for _, m in Gear.Materials do Gear.MaterialById[m.id] = m end
for _, r in Gear.Recipes do Gear.RecipeById[r.id] = r end

local function entries(c)
	local out = {}
	for _, rar in Gear.Rarities do if c.weights[rar.id] then table.insert(out, { rar.id, c.weights[rar.id] }) end end
	return out
end
-- real drop odds for a chest, summing to 1
function Gear.odds(c)
	local list, out = entries(c), {}
	local p = Weighted.odds(list) or {}
	for i, e in list do if p[i] > 0 then out[e[1]] = p[i] end end
	return out
end
function Gear.roll(c, rng: Random)
	return Weighted.pick(entries(c), rng), Gear.Types[rng:NextInteger(1, #Gear.Types)].id
end
function Gear.name(g)
	return g.r .. " " .. Gear.TypeById[g.t].name
end
return Gear
