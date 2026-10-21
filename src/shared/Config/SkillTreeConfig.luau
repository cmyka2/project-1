--!strict
-- Skill tree: six branches plus cross-branch nodes. Nodes are bought with
-- Gems. Every effect is a modifier key aggregated by Util/Modifiers, so the
-- same key from skills, ascension, rebirths and boosts is summed once.

export type NodeEffect = { Key: string, PerLevel: number }

export type SkillNodeDef = {
	Id: string,
	Name: string,
	Description: string, -- "{v}" is replaced with the current total value in the UI
	Branch: string,
	BaseCost: number,
	CostGrowth: number, -- cost of level n (0-based) = BaseCost * CostGrowth ^ n
	MaxLevel: number,
	Prerequisites: { string },
	RequiredRebirths: number,
	Effects: { NodeEffect },
	Icon: string,
	Position: Vector2, -- grid units on the skill canvas
	Repeatable: boolean,
}

export type BranchDef = { Id: string, DisplayName: string, Color: Color3, Glyph: string }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Branches: { [string]: BranchDef } = {
	Luck = { Id = "Luck", DisplayName = "Luck", Color = rgb(90, 230, 120), Glyph = "🍀" },
	Economy = { Id = "Economy", DisplayName = "Economy", Color = rgb(255, 210, 60), Glyph = "💰" },
	Utility = { Id = "Utility", DisplayName = "Utility", Color = rgb(120, 200, 255), Glyph = "🧰" },
	Mobility = { Id = "Mobility", DisplayName = "Mobility", Color = rgb(170, 255, 230), Glyph = "👟" },
	Defense = { Id = "Defense", DisplayName = "Health & Defense", Color = rgb(120, 140, 255), Glyph = "🛡" },
	Damage = { Id = "Damage", DisplayName = "Damage", Color = rgb(255, 90, 90), Glyph = "⚔" },
	Cross = { Id = "Cross", DisplayName = "Cross-Branch", Color = rgb(230, 150, 255), Glyph = "✳" },
}

local BranchOrder = { "Luck", "Economy", "Utility", "Mobility", "Defense", "Damage" }

local Nodes: { [string]: SkillNodeDef } = {}
local NodeOrder: { string } = {}

local function N(
	id: string,
	name: string,
	description: string,
	branch: string,
	position: Vector2,
	baseCost: number,
	maxLevel: number,
	effects: { NodeEffect },
	prereqs: { string }?,
	requiredRebirths: number?,
	icon: string?
)
	assert(Nodes[id] == nil, "duplicate skill node " .. id)
	Nodes[id] = {
		Id = id,
		Name = name,
		Description = description,
		Branch = branch,
		BaseCost = baseCost,
		CostGrowth = 1.55,
		MaxLevel = maxLevel,
		Prerequisites = prereqs or {},
		RequiredRebirths = requiredRebirths or 0,
		Effects = effects,
		Icon = icon or Branches[branch].Glyph,
		Position = position,
		Repeatable = maxLevel > 1,
	}
	table.insert(NodeOrder, id)
end

local function fx(key: string, perLevel: number): { NodeEffect }
	return { { Key = key, PerLevel = perLevel } }
end

local V = Vector2.new

-- Luck (column 1)
N("luck_1", "Lucky Paws", "+{v} roll luck", "Luck", V(1, 1), 5, 5, fx("Luck", 0.05))
N(
	"luck_2",
	"Rare Instinct",
	"+{v} luck on Volcano dice and above",
	"Luck",
	V(1, 2),
	12,
	5,
	fx("HighTierLuck", 0.05),
	{ "luck_1" }
)
N(
	"luck_3",
	"Thrifty Roller",
	"-{v} dice cost",
	"Luck",
	V(0.4, 2.5),
	10,
	5,
	fx("RollCostReduction", 0.03),
	{ "luck_1" }
)
N(
	"luck_4",
	"Collector's Eye",
	"+{v} codex milestone rewards",
	"Luck",
	V(1, 3),
	20,
	3,
	fx("DiscoveryRewardBonus", 0.1),
	{ "luck_2" }
)
N(
	"luck_5",
	"Potion Master",
	"+{v} potion effectiveness",
	"Luck",
	V(0.4, 3.5),
	18,
	3,
	fx("BoostEffectiveness", 0.1),
	{ "luck_3" }
)
N(
	"luck_6",
	"Fortune's Favor",
	"+{v} roll luck",
	"Luck",
	V(1, 4.5),
	60,
	3,
	fx("Luck", 0.1),
	{ "luck_4", "luck_5" },
	3
)

-- Economy (column 3)
N("eco_1", "Golden Touch", "+{v} passive income", "Economy", V(3, 1), 5, 5, fx("Income", 0.06))
N(
	"eco_2",
	"Master Trainer",
	"+{v} monster upgrade effectiveness",
	"Economy",
	V(3, 2),
	14,
	5,
	fx("UpgradeEffectiveness", 0.06),
	{ "eco_1" }
)
N("eco_3", "Haggler", "+{v} sell value", "Economy", V(3.6, 2.5), 8, 3, fx("SellValue", 0.1), { "eco_1" })
N(
	"eco_4",
	"Bounty Hunter",
	"+{v} battle coins",
	"Economy",
	V(3, 3),
	15,
	5,
	fx("BattleCoins", 0.1),
	{ "eco_2" }
)
N(
	"eco_5",
	"Night Shift",
	"+{v} offline efficiency",
	"Economy",
	V(3.6, 3.5),
	18,
	5,
	fx("OfflineEfficiency", 0.05),
	{ "eco_3" }
)
N(
	"eco_6",
	"Long Rest",
	"+{v} hours offline cap",
	"Economy",
	V(3, 4.5),
	30,
	4,
	fx("OfflineCapHours", 1),
	{ "eco_5" },
	1
)

-- Utility (column 5)
N("util_1", "Bigger Bag", "+{v} monster storage", "Utility", V(5, 1), 4, 10, fx("InventoryCapacity", 10))
N(
	"util_2",
	"Quick Hands",
	"-{v} crafting time",
	"Utility",
	V(5, 2),
	10,
	5,
	fx("CraftSpeed", 0.08),
	{ "util_1" }
)
N(
	"util_3",
	"Treasure Sense",
	"+{v} chance of an extra chest reward",
	"Utility",
	V(5.6, 2.5),
	12,
	5,
	fx("ChestBonusRollChance", 0.04),
	{ "util_1" }
)
N(
	"util_4",
	"Tactician",
	"+{v} saved battle loadouts",
	"Utility",
	V(5, 3),
	20,
	2,
	fx("LoadoutSlots", 1),
	{ "util_2" }
)
N(
	"util_5",
	"Quest Seeker",
	"+{v} quest rewards",
	"Utility",
	V(5.6, 3.5),
	16,
	5,
	fx("QuestRewards", 0.08),
	{ "util_3" }
)
N(
	"util_6",
	"Armory",
	"+{v} equipment storage",
	"Utility",
	V(5, 4.5),
	10,
	5,
	fx("EquipmentCapacity", 20),
	{ "util_4" }
)
N(
	"util_7",
	"Workshop Expansion",
	"+{v} crafting queue slots",
	"Utility",
	V(4.4, 4),
	35,
	2,
	fx("CraftQueue", 1),
	{ "util_2" },
	1
)

-- Mobility (column 7)
N("mob_1", "Fleet Foot", "+{v} walk speed", "Mobility", V(7, 1), 3, 5, fx("WalkSpeed", 0.04))
N("mob_2", "Spring Step", "+{v} jump power", "Mobility", V(7, 2), 6, 4, fx("JumpPower", 0.05), { "mob_1" })
N(
	"mob_3",
	"Seasoned Traveler",
	"-{v} region travel cooldown",
	"Mobility",
	V(7.6, 2.5),
	8,
	5,
	fx("TravelCooldownReduction", 0.1),
	{ "mob_1" }
)
N("mob_4", "Trailblazer", "+{v} walk speed", "Mobility", V(7, 3), 15, 3, fx("WalkSpeed", 0.05), { "mob_2" })
N(
	"mob_5",
	"Stardust Trail",
	"Unlocks a sparkling movement trail",
	"Mobility",
	V(7.6, 3.5),
	25,
	1,
	fx("MovementTrail", 1),
	{ "mob_3" }
)
N(
	"mob_6",
	"Windwalker",
	"+{v} jump power",
	"Mobility",
	V(7, 4.5),
	30,
	2,
	fx("JumpPower", 0.08),
	{ "mob_4" },
	2
)

-- Health & Defense (column 9)
N("def_1", "Thick Hide", "+{v} monster health", "Defense", V(9, 1), 5, 5, fx("Health", 0.06))
N("def_2", "Iron Scales", "+{v} monster defense", "Defense", V(9, 2), 10, 5, fx("Defense", 0.05), { "def_1" })
N(
	"def_3",
	"Guardian Aura",
	"-{v} damage taken",
	"Defense",
	V(9.6, 2.5),
	14,
	5,
	fx("DamageReduction", 0.02),
	{ "def_1" }
)
N("def_4", "Field Medic", "+{v} healing", "Defense", V(9, 3), 14, 4, fx("Healing", 0.08), { "def_2" })
N(
	"def_5",
	"Steadfast",
	"+{v} status resistance",
	"Defense",
	V(9.6, 3.5),
	16,
	4,
	fx("StatusResist", 0.05),
	{ "def_3" }
)
N(
	"def_6",
	"Unbreakable",
	"+{v} monster health",
	"Defense",
	V(9, 4.5),
	60,
	3,
	fx("Health", 0.1),
	{ "def_4", "def_5" },
	3
)

-- Damage (column 11)
N("dmg_1", "Sharpened Claws", "+{v} monster attack", "Damage", V(11, 1), 5, 5, fx("Attack", 0.05))
N(
	"dmg_2",
	"Keen Eye",
	"+{v} critical chance",
	"Damage",
	V(11, 2),
	10,
	5,
	fx("CritChance", 0.015),
	{ "dmg_1" }
)
N(
	"dmg_3",
	"Brutal Crits",
	"+{v} critical damage",
	"Damage",
	V(10.4, 2.5),
	12,
	5,
	fx("CritDamage", 0.08),
	{ "dmg_1" }
)
N(
	"dmg_4",
	"Elemental Mastery",
	"+{v} elemental damage",
	"Damage",
	V(11, 3),
	16,
	4,
	fx("ElementDamage", 0.05),
	{ "dmg_2" }
)
N(
	"dmg_5",
	"Ultimate Power",
	"+{v} ultimate damage",
	"Damage",
	V(10.4, 3.5),
	18,
	4,
	fx("UltimateDamage", 0.08),
	{ "dmg_3" }
)
N(
	"dmg_6",
	"Apex Predator",
	"+{v} monster attack",
	"Damage",
	V(11, 4.5),
	60,
	3,
	fx("Attack", 0.08),
	{ "dmg_4", "dmg_5" },
	3
)

-- Cross-branch nodes (require investment in two branches)
N("x_luck_eco", "Gambler's Fortune", "+{v} luck and cheaper dice", "Cross", V(2, 3.2), 40, 3, {
	{ Key = "Luck", PerLevel = 0.04 },
	{ Key = "RollCostReduction", PerLevel = 0.02 },
}, { "luck_3", "eco_1" }, 1)
N("x_eco_util", "Industrialist", "+{v} income and faster crafting", "Cross", V(4, 3.2), 40, 3, {
	{ Key = "Income", PerLevel = 0.05 },
	{ Key = "CraftSpeed", PerLevel = 0.05 },
}, { "eco_2", "util_2" }, 1)
N("x_luck_util", "Archivist", "+{v} codex rewards and storage", "Cross", V(3, 5.6), 55, 3, {
	{ Key = "DiscoveryRewardBonus", PerLevel = 0.1 },
	{ Key = "InventoryCapacity", PerLevel = 15 },
}, { "luck_4", "util_1" }, 2)
N("x_dmg_def", "Battle Hardened", "+{v} attack and health", "Cross", V(10, 3.2), 40, 3, {
	{ Key = "Attack", PerLevel = 0.05 },
	{ Key = "Health", PerLevel = 0.05 },
}, { "dmg_1", "def_1" }, 1)

local SkillTreeConfig = {
	Branches = Branches,
	BranchOrder = BranchOrder,
	Nodes = Nodes,
	NodeOrder = NodeOrder,
	Currency = "Gems",
	-- Refund policy: a full respec refunds every gem spent, for a flat fee.
	RespecCostGems = 25,
	RespecCooldownSeconds = 3600,
}

function SkillTreeConfig.costOf(node: SkillNodeDef, currentLevel: number): number
	return math.floor(node.BaseCost * node.CostGrowth ^ currentLevel + 0.5)
end

return table.freeze(SkillTreeConfig)
