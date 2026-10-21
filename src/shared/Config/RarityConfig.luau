--!strict
-- Rarity tiers. Every rarity rule in the game (colors, multipliers, luck
-- exponents, announcement thresholds) is read from here; UI and server code
-- never hardcode rarity behavior.

export type RarityDef = {
	Id: string,
	DisplayName: string,
	Tier: number, -- 1 = Common ... 10 = Glitched; used for ordering and comparisons
	Color: Color3,
	AccentColor: Color3,
	Glyph: string, -- placeholder icon until an image asset is registered in AssetConfig
	IncomeMultiplier: number,
	StatMultiplier: number,
	SellMultiplier: number,
	-- Luck transform exponent: finalWeight = baseWeight * effectiveLuck ^ LuckExponent.
	-- 0 means luck never changes this tier's raw weight (it still shrinks after normalization).
	LuckExponent: number,
	MaxUpgradeLevel: number,
	RevealDuration: number, -- seconds of the reveal animation (skippable)
	RevealEffect: "None" | "Glow" | "Burst" | "Beam" | "Supernova",
	Announce: "None" | "Server" | "ServerLoud",
	IsRareDiscovery: boolean, -- recorded in Discovery.RareDiscoveries
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Order: { string } = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Divine",
	"Celestial",
	"Cosmic",
	"Glitched",
}

local Rarities: { [string]: RarityDef } = {
	Common = {
		Id = "Common",
		DisplayName = "Common",
		Tier = 1,
		Color = rgb(176, 184, 196),
		AccentColor = rgb(120, 128, 140),
		Glyph = "●",
		IncomeMultiplier = 1,
		StatMultiplier = 1,
		SellMultiplier = 1,
		LuckExponent = 0,
		MaxUpgradeLevel = 15,
		RevealDuration = 1.2,
		RevealEffect = "None",
		Announce = "None",
		IsRareDiscovery = false,
	},
	Uncommon = {
		Id = "Uncommon",
		DisplayName = "Uncommon",
		Tier = 2,
		Color = rgb(96, 214, 112),
		AccentColor = rgb(40, 150, 64),
		Glyph = "◆",
		IncomeMultiplier = 1.6,
		StatMultiplier = 1.15,
		SellMultiplier = 1.8,
		LuckExponent = 0.25,
		MaxUpgradeLevel = 18,
		RevealDuration = 1.3,
		RevealEffect = "None",
		Announce = "None",
		IsRareDiscovery = false,
	},
	Rare = {
		Id = "Rare",
		DisplayName = "Rare",
		Tier = 3,
		Color = rgb(72, 156, 255),
		AccentColor = rgb(30, 92, 200),
		Glyph = "★",
		IncomeMultiplier = 2.6,
		StatMultiplier = 1.35,
		SellMultiplier = 3.5,
		LuckExponent = 0.5,
		MaxUpgradeLevel = 20,
		RevealDuration = 1.5,
		RevealEffect = "Glow",
		Announce = "None",
		IsRareDiscovery = false,
	},
	Epic = {
		Id = "Epic",
		DisplayName = "Epic",
		Tier = 4,
		Color = rgb(178, 92, 255),
		AccentColor = rgb(112, 40, 200),
		Glyph = "✦",
		IncomeMultiplier = 4.5,
		StatMultiplier = 1.6,
		SellMultiplier = 7,
		LuckExponent = 0.75,
		MaxUpgradeLevel = 22,
		RevealDuration = 1.8,
		RevealEffect = "Glow",
		Announce = "None",
		IsRareDiscovery = false,
	},
	Legendary = {
		Id = "Legendary",
		DisplayName = "Legendary",
		Tier = 5,
		Color = rgb(255, 184, 38),
		AccentColor = rgb(214, 120, 0),
		Glyph = "✪",
		IncomeMultiplier = 8,
		StatMultiplier = 1.9,
		SellMultiplier = 15,
		LuckExponent = 1,
		MaxUpgradeLevel = 25,
		RevealDuration = 2.2,
		RevealEffect = "Burst",
		Announce = "None",
		IsRareDiscovery = true,
	},
	Mythic = {
		Id = "Mythic",
		DisplayName = "Mythic",
		Tier = 6,
		Color = rgb(255, 72, 120),
		AccentColor = rgb(190, 20, 70),
		Glyph = "❖",
		IncomeMultiplier = 15,
		StatMultiplier = 2.3,
		SellMultiplier = 32,
		LuckExponent = 1,
		MaxUpgradeLevel = 25,
		RevealDuration = 2.6,
		RevealEffect = "Burst",
		Announce = "Server",
		IsRareDiscovery = true,
	},
	Divine = {
		Id = "Divine",
		DisplayName = "Divine",
		Tier = 7,
		Color = rgb(255, 244, 160),
		AccentColor = rgb(230, 190, 60),
		Glyph = "☀",
		IncomeMultiplier = 28,
		StatMultiplier = 2.8,
		SellMultiplier = 70,
		LuckExponent = 1,
		MaxUpgradeLevel = 30,
		RevealDuration = 3,
		RevealEffect = "Beam",
		Announce = "Server",
		IsRareDiscovery = true,
	},
	Celestial = {
		Id = "Celestial",
		DisplayName = "Celestial",
		Tier = 8,
		Color = rgb(120, 236, 255),
		AccentColor = rgb(40, 160, 220),
		Glyph = "☾",
		IncomeMultiplier = 55,
		StatMultiplier = 3.4,
		SellMultiplier = 150,
		LuckExponent = 1,
		MaxUpgradeLevel = 30,
		RevealDuration = 3.4,
		RevealEffect = "Beam",
		Announce = "ServerLoud",
		IsRareDiscovery = true,
	},
	Cosmic = {
		Id = "Cosmic",
		DisplayName = "Cosmic",
		Tier = 9,
		Color = rgb(122, 92, 255),
		AccentColor = rgb(255, 92, 220),
		Glyph = "✺",
		IncomeMultiplier = 110,
		StatMultiplier = 4.1,
		SellMultiplier = 330,
		LuckExponent = 1,
		MaxUpgradeLevel = 35,
		RevealDuration = 3.8,
		RevealEffect = "Supernova",
		Announce = "ServerLoud",
		IsRareDiscovery = true,
	},
	Glitched = {
		Id = "Glitched",
		DisplayName = "Glitched",
		Tier = 10,
		Color = rgb(60, 255, 140),
		AccentColor = rgb(255, 40, 90),
		Glyph = "▓",
		IncomeMultiplier = 250,
		StatMultiplier = 5,
		SellMultiplier = 800,
		LuckExponent = 1,
		MaxUpgradeLevel = 40,
		RevealDuration = 4.2,
		RevealEffect = "Supernova",
		Announce = "ServerLoud",
		IsRareDiscovery = true,
	},
}

local RarityConfig = {
	Order = Order,
	Rarities = Rarities,
}

function RarityConfig.get(id: string): RarityDef?
	return Rarities[id]
end

function RarityConfig.tierOf(id: string): number
	local def = Rarities[id]
	return if def then def.Tier else 0
end

return table.freeze(RarityConfig)
