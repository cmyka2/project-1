--!strict
-- Materials, consumables, crafting recipes and fusion recipes.

export type MaterialDef = {
	Id: string,
	DisplayName: string,
	Region: string,
	Glyph: string,
	Color: Color3,
}

export type BoostDef = {
	Stat: "Luck" | "Income" | "BattleCoins",
	Multiplier: number, -- applied multiplicatively while active (online only)
	DurationSeconds: number,
	MaxStackSeconds: number, -- re-using extends duration up to this cap
}

export type ConsumableDef = {
	Id: string,
	DisplayName: string,
	Glyph: string,
	Description: string,
	Kind: "Boost" | "BattleHeal",
	Boost: BoostDef?,
	HealPercent: number?, -- BattleHeal: fraction of max health
	HealAll: boolean?,
}

export type Ingredient = { Kind: "Material" | "Coins" | "Gems" | "Consumable", Id: string, Amount: number }

export type RecipeDef = {
	Id: string,
	DisplayName: string,
	Category: "Equipment" | "Potion" | "Material",
	Output: { Kind: "Equipment" | "Consumable" | "Material", Id: string, Amount: number },
	Ingredients: { Ingredient },
	CraftSeconds: number,
	RequiredRegion: string,
}

export type SpecialFusionDef = {
	Id: string,
	DisplayName: string,
	Inputs: { string }, -- MonsterIds, one instance each
	Coins: number,
	Materials: { [string]: number },
	Result: string, -- MonsterId
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Materials: { [string]: MaterialDef } = {
	grassland_essence = {
		Id = "grassland_essence",
		DisplayName = "Grassland Essence",
		Region = "Grassland",
		Glyph = "🌱",
		Color = rgb(120, 210, 100),
	},
	forest_essence = {
		Id = "forest_essence",
		DisplayName = "Forest Essence",
		Region = "Forest",
		Glyph = "🍃",
		Color = rgb(60, 150, 70),
	},
	desert_shard = {
		Id = "desert_shard",
		DisplayName = "Desert Shard",
		Region = "Desert",
		Glyph = "🔶",
		Color = rgb(235, 190, 110),
	},
	mountain_ore = {
		Id = "mountain_ore",
		DisplayName = "Mountain Ore",
		Region = "Mountain",
		Glyph = "🪨",
		Color = rgb(170, 190, 210),
	},
	volcanic_core = {
		Id = "volcanic_core",
		DisplayName = "Volcanic Core",
		Region = "Volcano",
		Glyph = "🌋",
		Color = rgb(255, 110, 40),
	},
	cave_crystal = {
		Id = "cave_crystal",
		DisplayName = "Cave Crystal",
		Region = "Cave",
		Glyph = "💠",
		Color = rgb(140, 230, 255),
	},
	heavenly_dust = {
		Id = "heavenly_dust",
		DisplayName = "Heavenly Dust",
		Region = "Heaven",
		Glyph = "✨",
		Color = rgb(255, 240, 180),
	},
	cosmic_fragment = {
		Id = "cosmic_fragment",
		DisplayName = "Cosmic Fragment",
		Region = "Cosmic",
		Glyph = "🌠",
		Color = rgb(150, 110, 255),
	},
	glitch_data = {
		Id = "glitch_data",
		DisplayName = "Glitch Data",
		Region = "Glitch",
		Glyph = "💾",
		Color = rgb(60, 255, 140),
	},
}

local MaterialOrder = {
	"grassland_essence",
	"forest_essence",
	"desert_shard",
	"mountain_ore",
	"volcanic_core",
	"cave_crystal",
	"heavenly_dust",
	"cosmic_fragment",
	"glitch_data",
}

local Consumables: { [string]: ConsumableDef } = {
	luck_potion = {
		Id = "luck_potion",
		DisplayName = "Luck Potion",
		Glyph = "🧪",
		Description = "x1.5 roll luck for 10 minutes (online).",
		Kind = "Boost",
		Boost = { Stat = "Luck", Multiplier = 1.5, DurationSeconds = 600, MaxStackSeconds = 3600 },
	},
	super_luck_potion = {
		Id = "super_luck_potion",
		DisplayName = "Super Luck Potion",
		Glyph = "⚗",
		Description = "x2 roll luck for 10 minutes (online). Does not stack with Luck Potion; the stronger applies.",
		Kind = "Boost",
		Boost = { Stat = "Luck", Multiplier = 2, DurationSeconds = 600, MaxStackSeconds = 3600 },
	},
	income_potion = {
		Id = "income_potion",
		DisplayName = "Income Potion",
		Glyph = "🍯",
		Description = "x2 passive income for 10 minutes (online only).",
		Kind = "Boost",
		Boost = { Stat = "Income", Multiplier = 2, DurationSeconds = 600, MaxStackSeconds = 3600 },
	},
	battle_tonic = {
		Id = "battle_tonic",
		DisplayName = "Battle Tonic",
		Glyph = "🧃",
		Description = "In battle: heals one ally for 35% of max health.",
		Kind = "BattleHeal",
		HealPercent = 0.35,
		HealAll = false,
	},
	grand_elixir = {
		Id = "grand_elixir",
		DisplayName = "Grand Elixir",
		Glyph = "🏺",
		Description = "In battle: heals the whole team for 25% of max health.",
		Kind = "BattleHeal",
		HealPercent = 0.25,
		HealAll = true,
	},
}

local Recipes: { [string]: RecipeDef } = {}
local RecipeOrder: { string } = {}

local function R(def: RecipeDef)
	assert(Recipes[def.Id] == nil, "duplicate recipe " .. def.Id)
	Recipes[def.Id] = def
	table.insert(RecipeOrder, def.Id)
end

local function mat(id: string, amount: number): Ingredient
	return { Kind = "Material", Id = id, Amount = amount }
end

local function coins(amount: number): Ingredient
	return { Kind = "Coins", Id = "Coins", Amount = amount }
end

-- Potions & battle items
R({
	Id = "craft_battle_tonic",
	DisplayName = "Battle Tonic",
	Category = "Potion",
	Output = { Kind = "Consumable", Id = "battle_tonic", Amount = 1 },
	Ingredients = { mat("grassland_essence", 3), coins(300) },
	CraftSeconds = 10,
	RequiredRegion = "Grassland",
})
R({
	Id = "craft_luck_potion",
	DisplayName = "Luck Potion",
	Category = "Potion",
	Output = { Kind = "Consumable", Id = "luck_potion", Amount = 1 },
	Ingredients = { mat("grassland_essence", 5), mat("forest_essence", 3), coins(2000) },
	CraftSeconds = 30,
	RequiredRegion = "Forest",
})
R({
	Id = "craft_income_potion",
	DisplayName = "Income Potion",
	Category = "Potion",
	Output = { Kind = "Consumable", Id = "income_potion", Amount = 1 },
	Ingredients = { mat("desert_shard", 6), mat("forest_essence", 4), coins(8000) },
	CraftSeconds = 45,
	RequiredRegion = "Desert",
})
R({
	Id = "craft_grand_elixir",
	DisplayName = "Grand Elixir",
	Category = "Potion",
	Output = { Kind = "Consumable", Id = "grand_elixir", Amount = 1 },
	Ingredients = { mat("mountain_ore", 4), mat("desert_shard", 4), coins(30000) },
	CraftSeconds = 40,
	RequiredRegion = "Mountain",
})
R({
	Id = "craft_super_luck_potion",
	DisplayName = "Super Luck Potion",
	Category = "Potion",
	Output = { Kind = "Consumable", Id = "super_luck_potion", Amount = 1 },
	Ingredients = { mat("volcanic_core", 5), mat("mountain_ore", 5), coins(400000) },
	CraftSeconds = 90,
	RequiredRegion = "Volcano",
})

-- Material refinement (lets players convert surplus upward)
R({
	Id = "refine_forest",
	DisplayName = "Refine Forest Essence",
	Category = "Material",
	Output = { Kind = "Material", Id = "forest_essence", Amount = 1 },
	Ingredients = { mat("grassland_essence", 4), coins(500) },
	CraftSeconds = 5,
	RequiredRegion = "Forest",
})
R({
	Id = "refine_desert",
	DisplayName = "Refine Desert Shard",
	Category = "Material",
	Output = { Kind = "Material", Id = "desert_shard", Amount = 1 },
	Ingredients = { mat("forest_essence", 4), coins(3000) },
	CraftSeconds = 5,
	RequiredRegion = "Desert",
})
R({
	Id = "refine_mountain",
	DisplayName = "Refine Mountain Ore",
	Category = "Material",
	Output = { Kind = "Material", Id = "mountain_ore", Amount = 1 },
	Ingredients = { mat("desert_shard", 4), coins(20000) },
	CraftSeconds = 5,
	RequiredRegion = "Mountain",
})

-- Equipment
type EquipRecipeRow = { Id: string, Name: string, Ingredients: { Ingredient }, Seconds: number, Region: string }
local function eq(
	id: string,
	name: string,
	ingredients: { Ingredient },
	seconds: number,
	region: string
): EquipRecipeRow
	return { Id = id, Name = name, Ingredients = ingredients, Seconds = seconds, Region = region }
end
local equipmentRecipes: { EquipRecipeRow } = {
	eq("wooden_claws", "Wooden Claws", { mat("grassland_essence", 4), coins(400) }, 15, "Grassland"),
	eq("leaf_vest", "Leaf Vest", { mat("grassland_essence", 4), coins(400) }, 15, "Grassland"),
	eq("swift_feather", "Swift Feather", { mat("grassland_essence", 6), coins(900) }, 20, "Grassland"),
	eq(
		"lucky_clover_pin",
		"Lucky Clover Pin",
		{ mat("grassland_essence", 10), mat("forest_essence", 4), coins(5000) },
		40,
		"Forest"
	),
	eq("forest_fang", "Forest Fang", { mat("forest_essence", 6), coins(4000) }, 30, "Forest"),
	eq("bark_plate", "Bark Plate", { mat("forest_essence", 6), coins(4000) }, 30, "Forest"),
	eq("healing_charm", "Healing Charm", { mat("forest_essence", 10), coins(12000) }, 45, "Forest"),
	eq(
		"four_leaf_relic",
		"Four-Leaf Relic",
		{ mat("forest_essence", 14), mat("grassland_essence", 14), coins(25000) },
		60,
		"Forest"
	),
	eq("sunsteel_blade", "Sunsteel Blade", { mat("desert_shard", 8), coins(30000) }, 45, "Desert"),
	eq("sandstone_mail", "Sandstone Mail", { mat("desert_shard", 8), coins(30000) }, 45, "Desert"),
	eq("golden_idol", "Golden Idol", { mat("desert_shard", 12), coins(60000) }, 60, "Desert"),
	eq(
		"crit_monocle",
		"Critical Monocle",
		{ mat("desert_shard", 14), mat("forest_essence", 8), coins(90000) },
		60,
		"Desert"
	),
	eq("frostbite_edge", "Frostbite Edge", { mat("mountain_ore", 10), coins(250000) }, 60, "Mountain"),
	eq("glacier_plate", "Glacier Plate", { mat("mountain_ore", 10), coins(250000) }, 60, "Mountain"),
	eq(
		"elemental_amulet",
		"Elemental Amulet",
		{ mat("mountain_ore", 16), mat("desert_shard", 10), coins(600000) },
		90,
		"Mountain"
	),
	eq("magma_maul", "Magma Maul", { mat("volcanic_core", 12), coins(1800000) }, 90, "Volcano"),
	eq("obsidian_aegis", "Obsidian Aegis", { mat("volcanic_core", 12), coins(1800000) }, 90, "Volcano"),
	eq("void_scythe", "Void Scythe", { mat("cave_crystal", 14), coins(12000000) }, 120, "Cave"),
	eq("crystal_carapace", "Crystal Carapace", { mat("cave_crystal", 14), coins(12000000) }, 120, "Cave"),
	eq(
		"fortune_orb",
		"Fortune Orb",
		{ mat("cave_crystal", 20), mat("volcanic_core", 12), coins(25000000) },
		150,
		"Cave"
	),
	eq("seraph_lance", "Seraph Lance", { mat("heavenly_dust", 16), coins(90000000) }, 150, "Heaven"),
	eq("halo_armor", "Halo Armor", { mat("heavenly_dust", 16), coins(90000000) }, 150, "Heaven"),
	eq(
		"starforged_glaive",
		"Starforged Glaive",
		{ mat("cosmic_fragment", 18), coins(650000000) },
		180,
		"Cosmic"
	),
	eq("nebula_shroud", "Nebula Shroud", { mat("cosmic_fragment", 18), coins(650000000) }, 180, "Cosmic"),
	eq(
		"cosmic_hourglass",
		"Cosmic Hourglass",
		{ mat("cosmic_fragment", 24), mat("heavenly_dust", 16), coins(1500000000) },
		240,
		"Cosmic"
	),
	eq("null_pointer", "Null Pointer", { mat("glitch_data", 20), coins(5000000000) }, 240, "Glitch"),
	eq("firewall_armor", "Firewall Armor", { mat("glitch_data", 20), coins(5000000000) }, 240, "Glitch"),
}
for _, row in equipmentRecipes do
	R({
		Id = "craft_" .. row.Id,
		DisplayName = row.Name,
		Category = "Equipment",
		Output = { Kind = "Equipment", Id = row.Id, Amount = 1 },
		Ingredients = row.Ingredients,
		CraftSeconds = row.Seconds,
		RequiredRegion = row.Region,
	})
end

local SpecialFusions: { [string]: SpecialFusionDef } = {
	chimera_of_seasons = {
		Id = "chimera_of_seasons",
		DisplayName = "Chimera of Seasons",
		Inputs = { "clover_king", "elder_treant", "spore_shaman" },
		Coins = 60000,
		Materials = { forest_essence = 25, grassland_essence = 25 },
		Result = "chimera_of_seasons",
	},
	tempest_hydra = {
		Id = "tempest_hydra",
		DisplayName = "Tempest Hydra",
		Inputs = { "glacier_titan", "storm_eagle", "yeti_cub" },
		Coins = 9000000,
		Materials = { mountain_ore = 40, desert_shard = 30 },
		Result = "tempest_hydra",
	},
	eclipse_dragon = {
		Id = "eclipse_dragon",
		DisplayName = "Eclipse Dragon",
		Inputs = { "shadow_lurker", "prism_dragon", "gloom_spider" },
		Coins = 500000000,
		Materials = { cave_crystal = 60, heavenly_dust = 20 },
		Result = "eclipse_dragon",
	},
}

local CraftingConfig = {
	Materials = Materials,
	MaterialOrder = MaterialOrder,
	Consumables = Consumables,
	Recipes = Recipes,
	RecipeOrder = RecipeOrder,
	SpecialFusions = SpecialFusions,

	BaseQueueSize = 2,
	MaxQueueSize = 6,
	MaxCraftCount = 10, -- per request
	MinCraftSeconds = 1,

	-- Star fusion: merge duplicates (same MonsterId) into a target to raise its stars.
	-- Deterministic: no failure chance.
	StarFusion = {
		DuplicatesPerStar = { 1, 1, 2, 2, 3 }, -- copies consumed to reach star 1..5
		CoinsPerStarMultiplier = 2, -- coins = target sell value * this * nextStar
	},
	-- Rarity fusion: N monsters of one rarity from one region -> 1 random monster
	-- of the next rarity from that region's dice pool (odds shown in the UI).
	-- The result rarity is guaranteed; nothing is lost on failure because there is no failure.
	RarityFusion = {
		InputCount = 4,
		CoinsDiceCostMultiplier = 4, -- coins = region dice cost * this * input tier
		MaterialPerTier = 2, -- region material = input tier * this
		BonusMaterialChance = 0.25, -- optional bonus outcome: extra region materials
		BonusMaterialAmount = 3,
	},
}

return table.freeze(CraftingConfig)
