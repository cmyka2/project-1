--!strict
-- Economy tunables: currencies, starting values, selling, monster upgrades,
-- income ticking and offline earnings. Formulas live in Util/EconomyMath and
-- are documented in docs/FORMULAS.md.

export type CurrencyDef = {
	Id: string,
	DisplayName: string,
	Glyph: string,
	Color: Color3,
	Purpose: string,
	Paid: boolean, -- can it be bought with Robux (directly or indirectly)?
}

export type BaseCosmeticDef = {
	Id: string,
	DisplayName: string,
	Category: "Floor" | "Platform" | "Lighting" | "Sign" | "Decoration",
	Cost: number,
	CostCurrency: "Coins" | "Gems",
	RequiredRebirths: number,
	Color: Color3,
	Material: Enum.Material,
	Description: string,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Currencies: { [string]: CurrencyDef } = {
	Coins = {
		Id = "Coins",
		DisplayName = "Coins",
		Glyph = "💰",
		Color = rgb(255, 214, 60),
		Purpose = "Main currency: dice, upgrades, regions, crafting, rebirth.",
		Paid = false,
	},
	Gems = {
		Id = "Gems",
		DisplayName = "Gems",
		Glyph = "💎",
		Color = rgb(90, 220, 255),
		Purpose = "Skill tree nodes, premium chests and cosmetics. Earned from quests, achievements, bosses, daily rewards and the arena.",
		Paid = true,
	},
	AscensionPoints = {
		Id = "AscensionPoints",
		DisplayName = "Ascension Points",
		Glyph = "🌟",
		Color = rgb(255, 160, 255),
		Purpose = "Permanent Ascension tree. Earned only by rebirthing and milestones.",
		Paid = false,
	},
	EventTokens = {
		Id = "EventTokens",
		DisplayName = "Event Tokens",
		Glyph = "🎟",
		Color = rgb(255, 140, 40),
		Purpose = "Event chests during live events. Earned from event quests.",
		Paid = false,
	},
}

local BaseCosmetics: { [string]: BaseCosmeticDef } = {
	floor_marble = {
		Id = "floor_marble",
		DisplayName = "Marble Floors",
		Category = "Floor",
		Cost = 5000,
		CostCurrency = "Coins",
		RequiredRebirths = 0,
		Color = rgb(235, 235, 240),
		Material = Enum.Material.Marble,
		Description = "Polished marble for every floor of your base.",
	},
	floor_wood = {
		Id = "floor_wood",
		DisplayName = "Oak Planks",
		Category = "Floor",
		Cost = 1500,
		CostCurrency = "Coins",
		RequiredRebirths = 0,
		Color = rgb(160, 110, 70),
		Material = Enum.Material.WoodPlanks,
		Description = "Cozy wooden floors.",
	},
	floor_neon = {
		Id = "floor_neon",
		DisplayName = "Neon Grid",
		Category = "Floor",
		Cost = 250,
		CostCurrency = "Gems",
		RequiredRebirths = 3,
		Color = rgb(60, 255, 200),
		Material = Enum.Material.Neon,
		Description = "A glowing synthwave floor.",
	},
	platform_gold = {
		Id = "platform_gold",
		DisplayName = "Golden Pedestals",
		Category = "Platform",
		Cost = 25000,
		CostCurrency = "Coins",
		RequiredRebirths = 0,
		Color = rgb(255, 200, 60),
		Material = Enum.Material.Metal,
		Description = "Display your monsters on golden pedestals.",
	},
	platform_crystal = {
		Id = "platform_crystal",
		DisplayName = "Crystal Pedestals",
		Category = "Platform",
		Cost = 150,
		CostCurrency = "Gems",
		RequiredRebirths = 2,
		Color = rgb(150, 220, 255),
		Material = Enum.Material.Glass,
		Description = "Shimmering crystal display platforms.",
	},
	lighting_lanterns = {
		Id = "lighting_lanterns",
		DisplayName = "Paper Lanterns",
		Category = "Lighting",
		Cost = 8000,
		CostCurrency = "Coins",
		RequiredRebirths = 0,
		Color = rgb(255, 170, 90),
		Material = Enum.Material.Neon,
		Description = "Warm lanterns around your base.",
	},
	sign_royal = {
		Id = "sign_royal",
		DisplayName = "Royal Banner",
		Category = "Sign",
		Cost = 60,
		CostCurrency = "Gems",
		RequiredRebirths = 1,
		Color = rgb(160, 60, 220),
		Material = Enum.Material.Fabric,
		Description = "A purple banner over your base sign.",
	},
	deco_fountain = {
		Id = "deco_fountain",
		DisplayName = "Mini Fountain",
		Category = "Decoration",
		Cost = 40000,
		CostCurrency = "Coins",
		RequiredRebirths = 1,
		Color = rgb(120, 190, 255),
		Material = Enum.Material.Slate,
		Description = "A small fountain at your entrance.",
	},
}

local EconomyConfig = {
	Currencies = Currencies,
	CurrencyOrder = { "Coins", "Gems", "AscensionPoints", "EventTokens" },
	BaseCosmetics = BaseCosmetics,

	StartingCoins = 100,
	StartingGems = 10,
	MaxCurrency = 1e30, -- hard ceiling to keep numbers finite and display-safe

	-- Selling: value = DiceCost * SellBaseFraction * Rarity.SellMultiplier / DiceFloorSellMultiplier
	--   * (1 + stars*SellPerStar) * (1 + SellValue) + UpgradeRefund
	-- DiceCost is the cost of the monster's region dice (its event dice for event monsters);
	-- DiceFloorSellMultiplier is the SellMultiplier of the most common rarity on that dice.
	-- UpgradeRefund = SellUpgradeRefund * (cost of the monster's upgrades at UpgradeCostReductionCap)
	-- Keep SellBaseFraction low: rolling then selling must never be profitable, even at the luck
	-- hard cap with maximum sell bonus and dice discount (enforced by tests/unit/Economy.spec).
	SellBaseFraction = 0.12,
	SellUpgradeRefund = 0.5,
	UpgradeCostReductionCap = 0.5, -- also the Modifiers cap for UpgradeCostReduction
	SellPerStar = 0.5,

	-- Monster upgrades: cost = BaseIncome * Rarity.IncomeMultiplier * UpgradeCostSeconds * UpgradeCostGrowth ^ level
	UpgradeCostSeconds = 240,
	UpgradeCostGrowth = 1.4,
	UpgradeIncomeBonusPerLevel = 0.25, -- income multiplier = 1 + level * this
	UpgradeStatBonusPerLevel = 0.04, -- combat multiplier = 1 + level * this

	-- Star fusion bonuses (FusionService): each star adds
	StarIncomeBonus = 0.3,
	StarStatBonus = 0.15,
	MaxStars = 5,

	-- Monster level effect on income (levels come from battle XP)
	LevelIncomeBonusPerLevel = 0.02,

	-- Income ticking
	IncomeTickSeconds = 1,

	-- Offline earnings (granted on join, computed from timestamps)
	OfflineBaseCapHours = 2,
	OfflineMaxCapHours = 12, -- absolute ceiling after all bonuses
	OfflineBaseEfficiency = 0.5, -- fraction of the online rate
	OfflineMaxEfficiency = 1,
	OfflineMinSeconds = 60, -- shorter absences grant nothing (avoids rejoin spam)

	-- Inventory
	BaseMonsterCapacity = 60,
	MaxMonsterCapacity = 500,
	BaseEquipmentCapacity = 60,
	MaxEquipmentCapacity = 300,
}

return table.freeze(EconomyConfig)
