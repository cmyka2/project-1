--!strict
-- Equipment items. A monster has one slot per category. Bonuses are
-- fractional (0.1 = +10%). Combat bonuses only affect battles; IncomePct only
-- affects the idle income of the monster wearing it; LuckPct only counts while
-- the wearer is in the active battle team (capped by LuckCap).

export type EquipStats = {
	AttackPct: number?,
	HealthPct: number?,
	DefensePct: number?,
	SpeedPct: number?,
	CritChance: number?,
	CritDamage: number?,
	ElementDamagePct: number?, -- bonus to damage of the wearer's element
	ElementResistPct: number?, -- reduction of incoming damage
	HealingPct: number?,
	IncomePct: number?,
	LuckPct: number?,
}

export type EquipmentDef = {
	Id: string,
	DisplayName: string,
	Category: "Weapon" | "Armor" | "Accessory" | "Relic",
	Rarity: string,
	Region: string, -- governs upgrade materials
	Glyph: string,
	IconKey: string,
	Description: string,
	Stats: EquipStats,
	CompatibleElements: { string }?, -- nil = any monster
	SetId: string?,
	RequiredLevel: number, -- monster level needed to equip
	Source: string,
}

export type SetBonus = {
	Id: string,
	DisplayName: string,
	Tiers: { { Pieces: number, Stats: EquipStats, Description: string } },
}

local Items: { [string]: EquipmentDef } = {}
local Order: { string } = {}

local function I(def: EquipmentDef)
	assert(Items[def.Id] == nil, "duplicate equipment " .. def.Id)
	Items[def.Id] = def
	table.insert(Order, def.Id)
end

-- Weapons ----------------------------------------------------------------------
I({
	Id = "wooden_claws",
	DisplayName = "Wooden Claws",
	Category = "Weapon",
	Rarity = "Common",
	Region = "Grassland",
	Glyph = "🗡",
	IconKey = "WoodenClaws",
	Description = "Carved from a fallen branch.",
	Stats = { AttackPct = 0.08 },
	RequiredLevel = 1,
	Source = "Crafting, Basic Chest",
})
I({
	Id = "forest_fang",
	DisplayName = "Forest Fang",
	Category = "Weapon",
	Rarity = "Uncommon",
	Region = "Forest",
	Glyph = "🗡",
	IconKey = "ForestFang",
	Description = "A wolf's fang wrapped in vines.",
	Stats = { AttackPct = 0.12, CritChance = 0.02 },
	RequiredLevel = 3,
	Source = "Crafting, Rare Chest",
})
I({
	Id = "sunsteel_blade",
	DisplayName = "Sunsteel Blade",
	Category = "Weapon",
	Rarity = "Rare",
	Region = "Desert",
	Glyph = "⚔",
	IconKey = "SunsteelBlade",
	Description = "Forged in desert heat.",
	Stats = { AttackPct = 0.18, CritDamage = 0.1 },
	RequiredLevel = 6,
	Source = "Crafting, Region Chest",
})
I({
	Id = "frostbite_edge",
	DisplayName = "Frostbite Edge",
	Category = "Weapon",
	Rarity = "Epic",
	Region = "Mountain",
	Glyph = "⚔",
	IconKey = "FrostbiteEdge",
	Description = "Never melts.",
	Stats = { AttackPct = 0.24, CritChance = 0.05 },
	RequiredLevel = 10,
	Source = "Crafting, Epic Chest",
})
I({
	Id = "magma_maul",
	DisplayName = "Magma Maul",
	Category = "Weapon",
	Rarity = "Legendary",
	Region = "Volcano",
	Glyph = "🔨",
	IconKey = "MagmaMaul",
	Description = "Still glowing from the forge.",
	Stats = { AttackPct = 0.32, ElementDamagePct = 0.1 },
	SetId = "ember",
	RequiredLevel = 15,
	Source = "Crafting, Boss Chest",
})
I({
	Id = "void_scythe",
	DisplayName = "Void Scythe",
	Category = "Weapon",
	Rarity = "Mythic",
	Region = "Cave",
	Glyph = "⚔",
	IconKey = "VoidScythe",
	Description = "Cuts through light itself.",
	Stats = { AttackPct = 0.42, CritChance = 0.08 },
	RequiredLevel = 20,
	Source = "Crafting, Legendary Chest",
})
I({
	Id = "seraph_lance",
	DisplayName = "Seraph Lance",
	Category = "Weapon",
	Rarity = "Divine",
	Region = "Heaven",
	Glyph = "🔱",
	IconKey = "SeraphLance",
	Description = "Carried by heaven's champions.",
	Stats = { AttackPct = 0.55, CritDamage = 0.2 },
	RequiredLevel = 26,
	Source = "Crafting",
})
I({
	Id = "starforged_glaive",
	DisplayName = "Starforged Glaive",
	Category = "Weapon",
	Rarity = "Celestial",
	Region = "Cosmic",
	Glyph = "🔱",
	IconKey = "StarforgedGlaive",
	Description = "Its edge is a sliver of starlight.",
	Stats = { AttackPct = 0.7, CritChance = 0.1 },
	RequiredLevel = 32,
	Source = "Crafting",
})
I({
	Id = "null_pointer",
	DisplayName = "Null Pointer",
	Category = "Weapon",
	Rarity = "Cosmic",
	Region = "Glitch",
	Glyph = "⚡",
	IconKey = "NullPointer",
	Description = "Points at nothing. Hits everything.",
	Stats = { AttackPct = 0.9, CritChance = 0.1, CritDamage = 0.3 },
	RequiredLevel = 40,
	Source = "Crafting",
})

-- Armor -----------------------------------------------------------------------
I({
	Id = "leaf_vest",
	DisplayName = "Leaf Vest",
	Category = "Armor",
	Rarity = "Common",
	Region = "Grassland",
	Glyph = "🦺",
	IconKey = "LeafVest",
	Description = "Better than nothing.",
	Stats = { HealthPct = 0.1 },
	RequiredLevel = 1,
	Source = "Crafting, Basic Chest",
})
I({
	Id = "bark_plate",
	DisplayName = "Bark Plate",
	Category = "Armor",
	Rarity = "Uncommon",
	Region = "Forest",
	Glyph = "🛡",
	IconKey = "BarkPlate",
	Description = "Tough treant bark.",
	Stats = { HealthPct = 0.12, DefensePct = 0.06 },
	RequiredLevel = 3,
	Source = "Crafting, Rare Chest",
})
I({
	Id = "sandstone_mail",
	DisplayName = "Sandstone Mail",
	Category = "Armor",
	Rarity = "Rare",
	Region = "Desert",
	Glyph = "🛡",
	IconKey = "SandstoneMail",
	Description = "Heavy but dependable.",
	Stats = { HealthPct = 0.16, DefensePct = 0.1 },
	RequiredLevel = 6,
	Source = "Crafting, Region Chest",
})
I({
	Id = "glacier_plate",
	DisplayName = "Glacier Plate",
	Category = "Armor",
	Rarity = "Epic",
	Region = "Mountain",
	Glyph = "🛡",
	IconKey = "GlacierPlate",
	Description = "Cut from ancient ice.",
	Stats = { HealthPct = 0.2, DefensePct = 0.14, ElementResistPct = 0.05 },
	RequiredLevel = 10,
	Source = "Crafting, Epic Chest",
})
I({
	Id = "obsidian_aegis",
	DisplayName = "Obsidian Aegis",
	Category = "Armor",
	Rarity = "Legendary",
	Region = "Volcano",
	Glyph = "🛡",
	IconKey = "ObsidianAegis",
	Description = "Volcanic glass, polished to a mirror.",
	Stats = { HealthPct = 0.26, DefensePct = 0.2 },
	SetId = "ember",
	RequiredLevel = 15,
	Source = "Crafting, Boss Chest",
})
I({
	Id = "crystal_carapace",
	DisplayName = "Crystal Carapace",
	Category = "Armor",
	Rarity = "Mythic",
	Region = "Cave",
	Glyph = "🛡",
	IconKey = "CrystalCarapace",
	Description = "Refracts incoming blows.",
	Stats = { HealthPct = 0.32, DefensePct = 0.26, ElementResistPct = 0.08 },
	RequiredLevel = 20,
	Source = "Crafting, Legendary Chest",
})
I({
	Id = "halo_armor",
	DisplayName = "Halo Armor",
	Category = "Armor",
	Rarity = "Divine",
	Region = "Heaven",
	Glyph = "🛡",
	IconKey = "HaloArmor",
	Description = "Glows with protective light.",
	Stats = { HealthPct = 0.4, DefensePct = 0.3, HealingPct = 0.1 },
	RequiredLevel = 26,
	Source = "Crafting",
})
I({
	Id = "nebula_shroud",
	DisplayName = "Nebula Shroud",
	Category = "Armor",
	Rarity = "Celestial",
	Region = "Cosmic",
	Glyph = "🛡",
	IconKey = "NebulaShroud",
	Description = "Woven from interstellar dust.",
	Stats = { HealthPct = 0.5, DefensePct = 0.36, ElementResistPct = 0.1 },
	RequiredLevel = 32,
	Source = "Crafting",
})
I({
	Id = "firewall_armor",
	DisplayName = "Firewall Armor",
	Category = "Armor",
	Rarity = "Cosmic",
	Region = "Glitch",
	Glyph = "🛡",
	IconKey = "FirewallArmor",
	Description = "Blocks all unauthorized damage.",
	Stats = { HealthPct = 0.62, DefensePct = 0.45, ElementResistPct = 0.12 },
	RequiredLevel = 40,
	Source = "Crafting",
})

-- Accessories -----------------------------------------------------------------
I({
	Id = "swift_feather",
	DisplayName = "Swift Feather",
	Category = "Accessory",
	Rarity = "Uncommon",
	Region = "Grassland",
	Glyph = "🪶",
	IconKey = "SwiftFeather",
	Description = "Light as a breeze.",
	Stats = { SpeedPct = 0.08 },
	RequiredLevel = 1,
	Source = "Crafting, Basic Chest",
})
I({
	Id = "crit_monocle",
	DisplayName = "Critical Monocle",
	Category = "Accessory",
	Rarity = "Epic",
	Region = "Desert",
	Glyph = "🧐",
	IconKey = "CritMonocle",
	Description = "Spots every weak point.",
	Stats = { CritChance = 0.06, CritDamage = 0.15 },
	RequiredLevel = 8,
	Source = "Crafting, Epic Chest",
})
I({
	Id = "healing_charm",
	DisplayName = "Healing Charm",
	Category = "Accessory",
	Rarity = "Epic",
	Region = "Forest",
	Glyph = "💚",
	IconKey = "HealingCharm",
	Description = "Warm to the touch.",
	Stats = { HealingPct = 0.2, HealthPct = 0.05 },
	RequiredLevel = 5,
	Source = "Crafting, Rare Chest",
})
I({
	Id = "elemental_amulet",
	DisplayName = "Elemental Amulet",
	Category = "Accessory",
	Rarity = "Legendary",
	Region = "Mountain",
	Glyph = "📿",
	IconKey = "ElementalAmulet",
	Description = "Amplifies the wearer's element.",
	Stats = { ElementDamagePct = 0.15, ElementResistPct = 0.1 },
	RequiredLevel = 12,
	Source = "Crafting, Legendary Chest",
})
I({
	Id = "ember_ring",
	DisplayName = "Ember Ring",
	Category = "Accessory",
	Rarity = "Legendary",
	Region = "Volcano",
	Glyph = "💍",
	IconKey = "EmberRing",
	Description = "Fire-aligned monsters only.",
	Stats = { AttackPct = 0.1, ElementDamagePct = 0.12 },
	CompatibleElements = { "Fire" },
	SetId = "ember",
	RequiredLevel = 15,
	Source = "Boss Chest",
})
I({
	Id = "lucky_clover_pin",
	DisplayName = "Lucky Clover Pin",
	Category = "Accessory",
	Rarity = "Rare",
	Region = "Grassland",
	Glyph = "🍀",
	IconKey = "LuckyCloverPin",
	Description = "Slightly improves roll luck while worn by a team member.",
	Stats = { LuckPct = 0.04 },
	RequiredLevel = 1,
	Source = "Crafting, Rare Chest",
})

-- Relics ----------------------------------------------------------------------
I({
	Id = "golden_idol",
	DisplayName = "Golden Idol",
	Category = "Relic",
	Rarity = "Rare",
	Region = "Desert",
	Glyph = "🗿",
	IconKey = "GoldenIdol",
	Description = "+income for the monster wearing it (idle only).",
	Stats = { IncomePct = 0.1 },
	RequiredLevel = 1,
	Source = "Crafting, Region Chest",
})
I({
	Id = "four_leaf_relic",
	DisplayName = "Four-Leaf Relic",
	Category = "Relic",
	Rarity = "Epic",
	Region = "Forest",
	Glyph = "🍀",
	IconKey = "FourLeafRelic",
	Description = "Improves roll luck while worn by a team member.",
	Stats = { LuckPct = 0.06 },
	RequiredLevel = 1,
	Source = "Crafting, Epic Chest",
})
I({
	Id = "midas_crown",
	DisplayName = "Midas Crown",
	Category = "Relic",
	Rarity = "Legendary",
	Region = "Volcano",
	Glyph = "👑",
	IconKey = "MidasCrown",
	Description = "Everything it touches earns more gold.",
	Stats = { IncomePct = 0.25 },
	RequiredLevel = 1,
	Source = "Legendary Chest, Boss Chest",
})
I({
	Id = "fortune_orb",
	DisplayName = "Fortune Orb",
	Category = "Relic",
	Rarity = "Mythic",
	Region = "Cave",
	Glyph = "🔮",
	IconKey = "FortuneOrb",
	Description = "Luck and gold, swirling together.",
	Stats = { LuckPct = 0.12, IncomePct = 0.1 },
	RequiredLevel = 1,
	Source = "Crafting, Legendary Chest",
})
I({
	Id = "cosmic_hourglass",
	DisplayName = "Cosmic Hourglass",
	Category = "Relic",
	Rarity = "Divine",
	Region = "Cosmic",
	Glyph = "⏳",
	IconKey = "CosmicHourglass",
	Description = "Bends time so the coins flow faster.",
	Stats = { IncomePct = 0.4 },
	RequiredLevel = 1,
	Source = "Crafting",
})

local Sets: { [string]: SetBonus } = {
	ember = {
		Id = "ember",
		DisplayName = "Ember Set",
		Tiers = {
			{ Pieces = 2, Stats = { ElementDamagePct = 0.1 }, Description = "2 pieces: +10% element damage" },
			{ Pieces = 3, Stats = { AttackPct = 0.15 }, Description = "3 pieces: +15% attack" },
		},
	},
}

local EquipmentConfig = {
	Items = Items,
	Order = Order,
	Sets = Sets,
	Categories = { "Weapon", "Armor", "Accessory", "Relic" },
	CategoryGlyphs = { Weapon = "⚔", Armor = "🛡", Accessory = "💍", Relic = "🔮" },
	LuckCap = 0.5, -- maximum total LuckPct from equipment

	-- Upgrades: each level adds UpgradeStatPerLevel of the item's base stats.
	-- cost = UpgradeBaseCoins[rarity] * UpgradeCoinGrowth ^ level, plus
	-- (level + 1) * UpgradeMaterialPerLevel of the item's region material.
	MaxLevelBase = 4, -- max level = MaxLevelBase + rarity tier
	UpgradeStatPerLevel = 0.12,
	UpgradeCoinGrowth = 1.6,
	UpgradeMaterialPerLevel = 2,
	UpgradeBaseCoins = {
		Common = 300,
		Uncommon = 1200,
		Rare = 6000,
		Epic = 40000,
		Legendary = 250000,
		Mythic = 1800000,
		Divine = 12000000,
		Celestial = 90000000,
		Cosmic = 700000000,
		Glitched = 5000000000,
	} :: { [string]: number },
	-- Salvaging returns materials of the item's region.
	SalvageMaterials = {
		Common = 1,
		Uncommon = 2,
		Rare = 4,
		Epic = 7,
		Legendary = 12,
		Mythic = 20,
		Divine = 32,
		Celestial = 50,
		Cosmic = 80,
		Glitched = 120,
	} :: { [string]: number },
}

function EquipmentConfig.get(id: string): EquipmentDef?
	return Items[id]
end

return table.freeze(EquipmentConfig)
