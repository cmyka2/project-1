--!strict
-- Dice definitions. A roll is two-stage (documented in docs/FORMULAS.md):
--   1. pick a rarity using the dice's RarityWeights after the luck transform
--      (rarities with no eligible monster in the pool are dropped first);
--   2. pick a monster of that rarity from the pool by MonsterDef.RollWeight.

local MonsterConfig = require(script.Parent.MonsterConfig)
local RegionConfig = require(script.Parent.RegionConfig)

export type DiceDef = {
	Id: string,
	DisplayName: string,
	Order: number,
	Cost: number,
	CostCurrency: "Coins" | "Gems" | "EventTokens",
	RequiredRegion: string, -- region that must be unlocked
	RequiredRebirths: number,
	BaseLuck: number,
	RarityWeights: { [string]: number },
	Pool: { string }, -- MonsterIds; filled from the region below unless given explicitly
	Color: Color3,
	Glyph: string,
	RollAnimation: "Tumble" | "Spin" | "Cosmic" | "Glitch",
	SoundKey: string,
	AutoRollEligible: boolean,
	EventId: string?, -- only rollable while that event is active
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function regionPool(regionId: string): { string }
	local pool = {}
	for _, id in MonsterConfig.Order do
		local def = MonsterConfig.Monsters[id]
		if def.Region == regionId and MonsterConfig.isRollable(def) then
			table.insert(pool, id)
		end
	end
	return pool
end

local function eventPool(eventId: string): { string }
	local pool = {}
	for _, id in MonsterConfig.Order do
		local def = MonsterConfig.Monsters[id]
		if def.EventId == eventId then
			table.insert(pool, id)
		end
	end
	return pool
end

local Dice: { [string]: DiceDef } = {}
local Order: { string } = {}

local function D(def: DiceDef)
	assert(Dice[def.Id] == nil, "duplicate dice " .. def.Id)
	assert(RegionConfig.Regions[def.RequiredRegion], "dice region missing " .. def.RequiredRegion)
	Dice[def.Id] = def
	table.insert(Order, def.Id)
end

D({
	Id = "grassland_dice",
	DisplayName = "Grassland Dice",
	Order = 1,
	Cost = 25,
	CostCurrency = "Coins",
	RequiredRegion = "Grassland",
	RequiredRebirths = 0,
	BaseLuck = 1,
	RarityWeights = { Common = 600, Uncommon = 300, Rare = 80, Epic = 18, Legendary = 2 },
	Pool = regionPool("Grassland"),
	Color = rgb(120, 210, 100),
	Glyph = "🎲",
	RollAnimation = "Tumble",
	SoundKey = "RollBasic",
	AutoRollEligible = true,
})
D({
	Id = "forest_dice",
	DisplayName = "Forest Dice",
	Order = 2,
	Cost = 250,
	CostCurrency = "Coins",
	RequiredRegion = "Forest",
	RequiredRebirths = 0,
	BaseLuck = 1.1,
	RarityWeights = { Common = 560, Uncommon = 300, Rare = 110, Epic = 26, Legendary = 3.6, Mythic = 0.4 },
	Pool = regionPool("Forest"),
	Color = rgb(60, 150, 70),
	Glyph = "🎲",
	RollAnimation = "Tumble",
	SoundKey = "RollBasic",
	AutoRollEligible = true,
})
D({
	Id = "desert_dice",
	DisplayName = "Desert Dice",
	Order = 3,
	Cost = 2500,
	CostCurrency = "Coins",
	RequiredRegion = "Desert",
	RequiredRebirths = 0,
	BaseLuck = 1.2,
	RarityWeights = { Common = 520, Uncommon = 310, Rare = 130, Epic = 34, Legendary = 5.4, Mythic = 0.6 },
	Pool = regionPool("Desert"),
	Color = rgb(235, 190, 110),
	Glyph = "🎲",
	RollAnimation = "Tumble",
	SoundKey = "RollBasic",
	AutoRollEligible = true,
})
D({
	Id = "mountain_dice",
	DisplayName = "Mountain Dice",
	Order = 4,
	Cost = 22000,
	CostCurrency = "Coins",
	RequiredRegion = "Mountain",
	RequiredRebirths = 0,
	BaseLuck = 1.3,
	RarityWeights = { Uncommon = 600, Rare = 280, Epic = 95, Legendary = 20, Mythic = 4.5, Divine = 0.5 },
	Pool = regionPool("Mountain"),
	Color = rgb(190, 215, 240),
	Glyph = "🎲",
	RollAnimation = "Spin",
	SoundKey = "RollAdvanced",
	AutoRollEligible = true,
})
D({
	Id = "volcano_dice",
	DisplayName = "Volcano Dice",
	Order = 5,
	Cost = 175000,
	CostCurrency = "Coins",
	RequiredRegion = "Volcano",
	RequiredRebirths = 1,
	BaseLuck = 1.4,
	RarityWeights = { Rare = 700, Epic = 220, Legendary = 62, Mythic = 15, Divine = 3 },
	Pool = regionPool("Volcano"),
	Color = rgb(255, 110, 40),
	Glyph = "🎲",
	RollAnimation = "Spin",
	SoundKey = "RollAdvanced",
	AutoRollEligible = true,
})
D({
	Id = "cave_dice",
	DisplayName = "Cave Dice",
	Order = 6,
	Cost = 900000,
	CostCurrency = "Coins",
	RequiredRegion = "Cave",
	RequiredRebirths = 2,
	BaseLuck = 1.5,
	RarityWeights = { Rare = 640, Epic = 250, Legendary = 80, Mythic = 22, Divine = 6.5, Celestial = 1.5 },
	Pool = regionPool("Cave"),
	Color = rgb(150, 120, 255),
	Glyph = "🎲",
	RollAnimation = "Spin",
	SoundKey = "RollAdvanced",
	AutoRollEligible = true,
})
D({
	Id = "heaven_dice",
	DisplayName = "Heaven Dice",
	Order = 7,
	Cost = 6000000,
	CostCurrency = "Coins",
	RequiredRegion = "Heaven",
	RequiredRebirths = 4,
	BaseLuck = 1.65,
	RarityWeights = { Epic = 720, Legendary = 200, Mythic = 60, Divine = 16, Celestial = 4 },
	Pool = regionPool("Heaven"),
	Color = rgb(255, 240, 180),
	Glyph = "🎲",
	RollAnimation = "Cosmic",
	SoundKey = "RollAdvanced",
	AutoRollEligible = true,
})
D({
	Id = "cosmic_dice",
	DisplayName = "Cosmic Dice",
	Order = 8,
	Cost = 30000000,
	CostCurrency = "Coins",
	RequiredRegion = "Cosmic",
	RequiredRebirths = 6,
	BaseLuck = 1.8,
	RarityWeights = { Epic = 650, Legendary = 240, Mythic = 80, Divine = 22, Celestial = 6.5, Cosmic = 1.5 },
	Pool = regionPool("Cosmic"),
	Color = rgb(140, 100, 255),
	Glyph = "🎲",
	RollAnimation = "Cosmic",
	SoundKey = "RollCosmic",
	AutoRollEligible = true,
})
D({
	Id = "glitch_dice",
	DisplayName = "Glitch Dice",
	Order = 9,
	Cost = 200000000,
	CostCurrency = "Coins",
	RequiredRegion = "Glitch",
	RequiredRebirths = 9,
	BaseLuck = 2,
	RarityWeights = {
		Legendary = 700,
		Mythic = 220,
		Divine = 60,
		Celestial = 15,
		Cosmic = 4.4,
		Glitched = 0.6,
	},
	Pool = regionPool("Glitch"),
	Color = rgb(60, 255, 140),
	Glyph = "🎲",
	RollAnimation = "Glitch",
	SoundKey = "RollGlitch",
	AutoRollEligible = true,
})
D({
	Id = "spooky_dice",
	DisplayName = "Spooky Dice",
	Order = 10,
	Cost = 400,
	CostCurrency = "Coins",
	RequiredRegion = "Grassland",
	RequiredRebirths = 0,
	BaseLuck = 1,
	RarityWeights = { Rare = 900, Legendary = 90, Mythic = 10 },
	Pool = eventPool("halloween_2026"),
	Color = rgb(255, 140, 30),
	Glyph = "🎃",
	RollAnimation = "Spin",
	SoundKey = "RollAdvanced",
	AutoRollEligible = true,
	EventId = "halloween_2026",
})

local DiceConfig = {
	Dice = Dice,
	Order = Order,
	StartingDice = "grassland_dice",
	-- Multi-roll options and how each one unlocks (checked server-side).
	MultiRoll = {
		{ Count = 1, RequiredTotalRolls = 0, RequiredRebirths = 0 },
		{ Count = 3, RequiredTotalRolls = 15, RequiredRebirths = 0 },
		{ Count = 5, RequiredTotalRolls = 60, RequiredRebirths = 0 },
		{ Count = 10, RequiredTotalRolls = 200, RequiredRebirths = 1 },
	},
	AutoRoll = {
		RequiredTotalRolls = 40,
		IntervalSeconds = 1.6, -- server-paced, independent of client animations
		MaxBatch = 10,
	},
	RollCooldownSeconds = 0.35, -- minimum time between manual roll requests
	FreeRollCooldownSeconds = 600,
	-- Luck soft cap (see Util/RollMath.effectiveLuck): linear up to SoftCapStart,
	-- then grows as (excess ^ SoftCapExponent), never beyond HardCap.
	Luck = {
		SoftCapStart = 4,
		SoftCapExponent = 0.6,
		HardCap = 20,
		HighTierFromOrder = 5, -- "HighTierLuck" modifiers apply to dice with Order >= this
	},
}

function DiceConfig.get(id: string): DiceDef?
	return Dice[id]
end

return table.freeze(DiceConfig)
