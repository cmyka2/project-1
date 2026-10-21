--!strict
-- Rebirth requirements, rewards, reset rules, and the permanent Ascension tree.
--
-- Base slots and floors are a fixed core rule (see Util/BaseLayout):
--   total slots = 5 + rebirths, floors = min(3, 1 + floor(rebirths / 6)).

export type AscensionNodeDef = {
	Id: string,
	Name: string,
	Description: string,
	BaseCost: number,
	CostPerLevel: number, -- cost of level n (0-based) = BaseCost + CostPerLevel * n
	MaxLevel: number,
	Prerequisites: { string },
	Effects: { { Key: string, PerLevel: number } },
	Icon: string,
	Position: Vector2,
}

local AscensionNodes: { [string]: AscensionNodeDef } = {}
local AscensionOrder: { string } = {}

local function A(def: AscensionNodeDef)
	assert(AscensionNodes[def.Id] == nil, "duplicate ascension node " .. def.Id)
	AscensionNodes[def.Id] = def
	table.insert(AscensionOrder, def.Id)
end

local V = Vector2.new

A({
	Id = "asc_wealth",
	Name = "Eternal Wealth",
	Description = "+{v} passive income",
	BaseCost = 1,
	CostPerLevel = 1,
	MaxLevel = 10,
	Prerequisites = {},
	Effects = { { Key = "Income", PerLevel = 0.1 } },
	Icon = "💰",
	Position = V(2, 1),
})
A({
	Id = "asc_luck",
	Name = "Eternal Luck",
	Description = "+{v} roll luck",
	BaseCost = 1,
	CostPerLevel = 1,
	MaxLevel = 10,
	Prerequisites = {},
	Effects = { { Key = "Luck", PerLevel = 0.05 } },
	Icon = "🍀",
	Position = V(4, 1),
})
A({
	Id = "asc_might",
	Name = "Eternal Might",
	Description = "+{v} monster attack",
	BaseCost = 1,
	CostPerLevel = 1,
	MaxLevel = 10,
	Prerequisites = {},
	Effects = { { Key = "Attack", PerLevel = 0.05 } },
	Icon = "⚔",
	Position = V(6, 1),
})
A({
	Id = "asc_vigor",
	Name = "Eternal Vigor",
	Description = "+{v} monster health and defense",
	BaseCost = 1,
	CostPerLevel = 1,
	MaxLevel = 10,
	Prerequisites = {},
	Effects = { { Key = "Health", PerLevel = 0.05 }, { Key = "Defense", PerLevel = 0.03 } },
	Icon = "🛡",
	Position = V(8, 1),
})
A({
	Id = "asc_quickroll",
	Name = "Quick Roller",
	Description = "Unlocks auto-roll immediately",
	BaseCost = 1,
	CostPerLevel = 0,
	MaxLevel = 1,
	Prerequisites = { "asc_luck" },
	Effects = { { Key = "AutoRollUnlock", PerLevel = 1 } },
	Icon = "🔁",
	Position = V(4, 2),
})
A({
	Id = "asc_dice",
	Name = "Dice Savant",
	Description = "+{v} luck on Volcano dice and above",
	BaseCost = 2,
	CostPerLevel = 1,
	MaxLevel = 5,
	Prerequisites = { "asc_luck" },
	Effects = { { Key = "HighTierLuck", PerLevel = 0.08 } },
	Icon = "🎲",
	Position = V(5, 2.6),
})
A({
	Id = "asc_nest_egg",
	Name = "Nest Egg",
	Description = "Keep {v} of your coins when you rebirth",
	BaseCost = 2,
	CostPerLevel = 2,
	MaxLevel = 5,
	Prerequisites = { "asc_wealth" },
	Effects = { { Key = "RebirthKeepCoins", PerLevel = 0.02 } },
	Icon = "🥚",
	Position = V(1.4, 2.4),
})
A({
	Id = "asc_dreamer",
	Name = "Dreamer",
	Description = "+{v} hours offline cap",
	BaseCost = 2,
	CostPerLevel = 1,
	MaxLevel = 4,
	Prerequisites = { "asc_wealth" },
	Effects = { { Key = "OfflineCapHours", PerLevel = 1 }, { Key = "OfflineEfficiency", PerLevel = 0.05 } },
	Icon = "🌙",
	Position = V(2.6, 2.4),
})
A({
	Id = "asc_vault",
	Name = "Vault",
	Description = "+{v} monster storage",
	BaseCost = 1,
	CostPerLevel = 1,
	MaxLevel = 6,
	Prerequisites = { "asc_wealth" },
	Effects = { { Key = "InventoryCapacity", PerLevel = 25 } },
	Icon = "🏦",
	Position = V(2, 3.4),
})
A({
	Id = "asc_momentum",
	Name = "Momentum",
	Description = "-{v} monster upgrade costs",
	BaseCost = 2,
	CostPerLevel = 1,
	MaxLevel = 5,
	Prerequisites = { "asc_wealth" },
	Effects = { { Key = "UpgradeCostReduction", PerLevel = 0.05 } },
	Icon = "📈",
	Position = V(3, 3.4),
})
A({
	Id = "asc_veteran",
	Name = "Veteran",
	Description = "+{v} monster battle XP",
	BaseCost = 1,
	CostPerLevel = 1,
	MaxLevel = 5,
	Prerequisites = { "asc_might" },
	Effects = { { Key = "XpGain", PerLevel = 0.1 } },
	Icon = "🎖",
	Position = V(6, 2.4),
})
A({
	Id = "asc_war_chest",
	Name = "War Chest",
	Description = "+{v} battle coins",
	BaseCost = 1,
	CostPerLevel = 1,
	MaxLevel = 5,
	Prerequisites = { "asc_vigor" },
	Effects = { { Key = "BattleCoins", PerLevel = 0.15 } },
	Icon = "🪙",
	Position = V(8, 2.4),
})

local RebirthConfig = {
	MaxRebirths = 30,
	-- Coin cost of rebirth n (n = current rebirth count): BaseCost * Growth ^ n
	BaseCost = 400000,
	Growth = 5.5,
	-- Region that must be unlocked before rebirth n -> n+1 (index = current count + 1,
	-- clamped to the last entry).
	RequiredRegionByRebirth = {
		"Desert",
		"Mountain",
		"Volcano",
		"Volcano",
		"Cave",
		"Cave",
		"Heaven",
		"Heaven",
		"Cosmic",
		"Cosmic",
		"Glitch",
	},
	-- Permanent rewards per completed rebirth (summed through Util/Modifiers)
	IncomeBonusPerRebirth = 0.35,
	LuckBonusPerRebirth = 0.02,
	LuckBonusCap = 0.4,
	AscensionPointsPerRebirth = 1,
	AscensionMilestoneEvery = 5, -- every Nth rebirth grants bonus points
	AscensionMilestoneBonus = 2,
	GemsPerRebirth = 5, -- gems granted = this * new rebirth count

	-- What a rebirth resets. Everything not listed here is kept.
	Reset = {
		Coins = true, -- set to 0, minus the RebirthKeepCoins modifier
		MonsterUpgrades = true, -- monster upgrade ranks back to 0 (levels, stars and XP are kept)
		Skills = false,
		Regions = false,
		Boosts = false,
		CraftingQueue = false,
	},
	-- Shown to the player before confirming, generated from Reset above.
	KeptDescription = {
		"Your entire monster collection, levels, stars and equipment",
		"Codex discoveries, achievements and quests",
		"Unlocked regions and defeated bosses",
		"Skill tree, Ascension tree and base cosmetics",
		"Materials, gems, chests and consumables",
		"Base slots and floors (rebirths only ever add slots)",
	},

	AscensionNodes = AscensionNodes,
	AscensionOrder = AscensionOrder,
}

function RebirthConfig.cost(currentRebirths: number): number
	return math.floor(RebirthConfig.BaseCost * RebirthConfig.Growth ^ currentRebirths + 0.5)
end

function RebirthConfig.requiredRegion(currentRebirths: number): string
	local list = RebirthConfig.RequiredRegionByRebirth
	local index = math.clamp(currentRebirths + 1, 1, #list)
	return list[index]
end

function RebirthConfig.ascensionCost(node: AscensionNodeDef, currentLevel: number): number
	return node.BaseCost + node.CostPerLevel * currentLevel
end

return table.freeze(RebirthConfig)
