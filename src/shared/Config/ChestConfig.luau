--!strict
-- Chest definitions. Rewards are a weighted pool; the UI shows the exact
-- percentages computed from these weights. "Scaled" amounts (and the cost
-- when ScaleCost is set) are multiplied by the IncomeScale of the player's
-- highest unlocked region so chests stay relevant all game. A reward Id of
-- "@region" means "the material of the player's highest unlocked region".

export type ChestReward = {
	Kind: "Coins" | "Gems" | "Material" | "Equipment" | "Consumable" | "Monster",
	Id: string, -- currency/material/item/consumable/monster id or "@region"
	Min: number,
	Max: number,
	Weight: number,
	Scaled: boolean?,
}

export type ChestDef = {
	Id: string,
	DisplayName: string,
	Glyph: string,
	Color: Color3,
	Cost: number?, -- nil = cannot be bought, only earned
	CostCurrency: ("Coins" | "Gems" | "EventTokens")?,
	ScaleCost: boolean,
	Rolls: number, -- rewards drawn per chest
	Rewards: { ChestReward },
	EventId: string?,
	Description: string,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Chests: { [string]: ChestDef } = {
	basic_chest = {
		Id = "basic_chest",
		DisplayName = "Basic Chest",
		Glyph = "📦",
		Color = rgb(190, 150, 100),
		Cost = 400,
		CostCurrency = "Coins",
		ScaleCost = true,
		Rolls = 1,
		Description = "Coins, materials and common gear.",
		Rewards = {
			{ Kind = "Coins", Id = "Coins", Min = 250, Max = 700, Weight = 55, Scaled = true },
			{ Kind = "Material", Id = "@region", Min = 1, Max = 3, Weight = 30 },
			{ Kind = "Equipment", Id = "wooden_claws", Min = 1, Max = 1, Weight = 4 },
			{ Kind = "Equipment", Id = "leaf_vest", Min = 1, Max = 1, Weight = 4 },
			{ Kind = "Equipment", Id = "swift_feather", Min = 1, Max = 1, Weight = 3 },
			{ Kind = "Consumable", Id = "battle_tonic", Min = 1, Max = 2, Weight = 3 },
			{ Kind = "Consumable", Id = "luck_potion", Min = 1, Max = 1, Weight = 1 },
		},
	},
	rare_chest = {
		Id = "rare_chest",
		DisplayName = "Rare Chest",
		Glyph = "🎁",
		Color = rgb(80, 150, 255),
		Cost = 3000,
		CostCurrency = "Coins",
		ScaleCost = true,
		Rolls = 2,
		Description = "Better gear and more materials.",
		Rewards = {
			{ Kind = "Coins", Id = "Coins", Min = 1500, Max = 3500, Weight = 35, Scaled = true },
			{ Kind = "Material", Id = "@region", Min = 3, Max = 6, Weight = 30 },
			{ Kind = "Equipment", Id = "forest_fang", Min = 1, Max = 1, Weight = 6 },
			{ Kind = "Equipment", Id = "bark_plate", Min = 1, Max = 1, Weight = 6 },
			{ Kind = "Equipment", Id = "healing_charm", Min = 1, Max = 1, Weight = 4 },
			{ Kind = "Equipment", Id = "lucky_clover_pin", Min = 1, Max = 1, Weight = 4 },
			{ Kind = "Consumable", Id = "luck_potion", Min = 1, Max = 1, Weight = 8 },
			{ Kind = "Consumable", Id = "income_potion", Min = 1, Max = 1, Weight = 5 },
			{ Kind = "Gems", Id = "Gems", Min = 2, Max = 6, Weight = 2 },
		},
	},
	epic_chest = {
		Id = "epic_chest",
		DisplayName = "Epic Chest",
		Glyph = "💜",
		Color = rgb(170, 90, 255),
		Cost = 40,
		CostCurrency = "Gems",
		ScaleCost = false,
		Rolls = 2,
		Description = "Epic gear, potions and plenty of materials.",
		Rewards = {
			{ Kind = "Material", Id = "@region", Min = 6, Max = 12, Weight = 30 },
			{ Kind = "Equipment", Id = "frostbite_edge", Min = 1, Max = 1, Weight = 8 },
			{ Kind = "Equipment", Id = "glacier_plate", Min = 1, Max = 1, Weight = 8 },
			{ Kind = "Equipment", Id = "crit_monocle", Min = 1, Max = 1, Weight = 7 },
			{ Kind = "Equipment", Id = "four_leaf_relic", Min = 1, Max = 1, Weight = 5 },
			{ Kind = "Consumable", Id = "luck_potion", Min = 1, Max = 2, Weight = 15 },
			{ Kind = "Consumable", Id = "income_potion", Min = 1, Max = 2, Weight = 12 },
			{ Kind = "Coins", Id = "Coins", Min = 8000, Max = 20000, Weight = 15, Scaled = true },
		},
	},
	legendary_chest = {
		Id = "legendary_chest",
		DisplayName = "Legendary Chest",
		Glyph = "👑",
		Color = rgb(255, 190, 40),
		Cost = 120,
		CostCurrency = "Gems",
		ScaleCost = false,
		Rolls = 3,
		Description = "Legendary and Mythic gear with a chance at a monster.",
		Rewards = {
			{ Kind = "Material", Id = "@region", Min = 10, Max = 20, Weight = 26 },
			{ Kind = "Equipment", Id = "elemental_amulet", Min = 1, Max = 1, Weight = 7 },
			{ Kind = "Equipment", Id = "midas_crown", Min = 1, Max = 1, Weight = 6 },
			{ Kind = "Equipment", Id = "void_scythe", Min = 1, Max = 1, Weight = 4 },
			{ Kind = "Equipment", Id = "crystal_carapace", Min = 1, Max = 1, Weight = 4 },
			{ Kind = "Equipment", Id = "fortune_orb", Min = 1, Max = 1, Weight = 3 },
			{ Kind = "Consumable", Id = "super_luck_potion", Min = 1, Max = 1, Weight = 12 },
			{ Kind = "Consumable", Id = "income_potion", Min = 2, Max = 3, Weight = 14 },
			{ Kind = "Monster", Id = "clover_king", Min = 1, Max = 1, Weight = 4 },
			{ Kind = "Coins", Id = "Coins", Min = 30000, Max = 60000, Weight = 20, Scaled = true },
		},
	},
	region_chest = {
		Id = "region_chest",
		DisplayName = "Region Chest",
		Glyph = "🧰",
		Color = rgb(120, 200, 140),
		Cost = nil,
		CostCurrency = nil,
		ScaleCost = false,
		Rolls = 2,
		Description = "Dropped by battles. Materials and regional gear.",
		Rewards = {
			{ Kind = "Material", Id = "@region", Min = 3, Max = 8, Weight = 45 },
			{ Kind = "Coins", Id = "Coins", Min = 800, Max = 2000, Weight = 30, Scaled = true },
			{ Kind = "Equipment", Id = "sunsteel_blade", Min = 1, Max = 1, Weight = 5 },
			{ Kind = "Equipment", Id = "sandstone_mail", Min = 1, Max = 1, Weight = 5 },
			{ Kind = "Equipment", Id = "golden_idol", Min = 1, Max = 1, Weight = 5 },
			{ Kind = "Consumable", Id = "battle_tonic", Min = 1, Max = 2, Weight = 10 },
		},
	},
	boss_chest = {
		Id = "boss_chest",
		DisplayName = "Boss Chest",
		Glyph = "💀",
		Color = rgb(220, 60, 60),
		Cost = nil,
		CostCurrency = nil,
		ScaleCost = false,
		Rolls = 3,
		Description = "Dropped by bosses. Big rewards and boss gear.",
		Rewards = {
			{ Kind = "Material", Id = "@region", Min = 6, Max = 12, Weight = 35 },
			{ Kind = "Gems", Id = "Gems", Min = 5, Max = 15, Weight = 20 },
			{ Kind = "Coins", Id = "Coins", Min = 5000, Max = 12000, Weight = 20, Scaled = true },
			{ Kind = "Equipment", Id = "magma_maul", Min = 1, Max = 1, Weight = 4 },
			{ Kind = "Equipment", Id = "obsidian_aegis", Min = 1, Max = 1, Weight = 4 },
			{ Kind = "Equipment", Id = "ember_ring", Min = 1, Max = 1, Weight = 3 },
			{ Kind = "Equipment", Id = "midas_crown", Min = 1, Max = 1, Weight = 2 },
			{ Kind = "Consumable", Id = "grand_elixir", Min = 1, Max = 2, Weight = 12 },
		},
	},
	event_chest = {
		Id = "event_chest",
		DisplayName = "Spooky Chest",
		Glyph = "🎃",
		Color = rgb(255, 140, 30),
		Cost = 10,
		CostCurrency = "EventTokens",
		ScaleCost = false,
		Rolls = 2,
		EventId = "halloween_2026",
		Description = "Halloween event chest: spooky monsters and potions.",
		Rewards = {
			{ Kind = "Monster", Id = "pumpkin_imp", Min = 1, Max = 1, Weight = 20 },
			{ Kind = "Monster", Id = "wraith_cat", Min = 1, Max = 1, Weight = 4 },
			{ Kind = "Monster", Id = "lantern_king", Min = 1, Max = 1, Weight = 1 },
			{ Kind = "Consumable", Id = "luck_potion", Min = 1, Max = 2, Weight = 25 },
			{ Kind = "Gems", Id = "Gems", Min = 5, Max = 12, Weight = 20 },
			{ Kind = "Material", Id = "@region", Min = 4, Max = 10, Weight = 30 },
		},
	},
}

local ChestConfig = {
	Chests = Chests,
	ShopOrder = { "basic_chest", "rare_chest", "epic_chest", "legendary_chest", "event_chest" },
	MaxOpenPerRequest = 10,
}

return table.freeze(ChestConfig)
