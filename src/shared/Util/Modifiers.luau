--!strict
-- Single aggregation point for every gameplay modifier (pure).
--
-- Additive keys (e.g. "Luck", "Income", "Attack") are summed across skill
-- nodes, ascension nodes, rebirth bonuses, owned game passes and equipment
-- luck. Time-limited multipliers (potions, events) are kept separate in the
-- *Mult keys so offline income can exclude them. Because every system reads
-- this one table, no bonus is ever applied twice.

local SkillTreeConfig = require(script.Parent.Parent.Config.SkillTreeConfig)
local RebirthConfig = require(script.Parent.Parent.Config.RebirthConfig)
local MonetizationConfig = require(script.Parent.Parent.Config.MonetizationConfig)
local CraftingConfig = require(script.Parent.Parent.Config.CraftingConfig)
local EquipmentConfig = require(script.Parent.Parent.Config.EquipmentConfig)
local EventConfig = require(script.Parent.Parent.Config.EventConfig)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local DiceConfig = require(script.Parent.Parent.Config.DiceConfig)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local EquipMath = require(script.Parent.EquipMath)
local EventSchedule = require(script.Parent.EventSchedule)
local RollMath = require(script.Parent.RollMath)
local Types = require(script.Parent.Parent.Types)

export type Mods = { [string]: number }

local Modifiers = {}

-- Upper bounds for keys that would otherwise break the economy.
local CAPS: { [string]: number } = {
	RollCostReduction = 0.3,
	UpgradeCostReduction = EconomyConfig.UpgradeCostReductionCap,
	ServiceCostReduction = 0.5,
	CraftSpeed = 0.75,
	TravelCooldownReduction = 0.8,
	RebirthKeepCoins = 0.25,
	ChestBonusRollChance = 0.5,
	DamageReduction = 0.5,
	StatusResist = 0.6,
	CritChance = 0.5,
	EquipmentLuck = EquipmentConfig.LuckCap,
}

local MULT_KEYS = {
	"BoostLuckMult",
	"BoostIncomeMult",
	"BoostBattleCoinsMult",
	"EventLuckMult",
	"EventIncomeMult",
	"EventBattleCoinsMult",
}

local function add(mods: Mods, key: string, value: number)
	if value == value and value ~= math.huge and value ~= -math.huge then
		mods[key] = (mods[key] or 0) + value
	end
end

function Modifiers.get(mods: Mods, key: string): number
	return mods[key] or 0
end

-- Clamps a value to the economy cap for `key` (unchanged if the key has none).
function Modifiers.cap(key: string, value: number): number
	local cap = CAPS[key]
	return if cap and value > cap then cap else value
end

function Modifiers.compute(profile: Types.Profile, now: number): Mods
	local mods: Mods = {}
	for _, key in MULT_KEYS do
		mods[key] = 1
	end

	-- Skill tree
	for nodeId, level in profile.Skills.Nodes do
		local node = SkillTreeConfig.Nodes[nodeId]
		if node and level > 0 then
			local lvl = math.min(level, node.MaxLevel)
			for _, effect in node.Effects do
				add(mods, effect.Key, effect.PerLevel * lvl)
			end
		end
	end

	-- Ascension tree
	for nodeId, level in profile.Progression.AscensionUpgrades do
		local node = RebirthConfig.AscensionNodes[nodeId]
		if node and level > 0 then
			local lvl = math.min(level, node.MaxLevel)
			for _, effect in node.Effects do
				add(mods, effect.Key, effect.PerLevel * lvl)
			end
		end
	end

	-- Rebirths
	local rebirths = profile.Progression.RebirthCount
	add(mods, "Income", RebirthConfig.IncomeBonusPerRebirth * rebirths)
	add(mods, "Luck", math.min(RebirthConfig.LuckBonusPerRebirth * rebirths, RebirthConfig.LuckBonusCap))

	-- Game passes (ownership verified server-side before being stored)
	for _, pass in MonetizationConfig.Passes do
		if profile.Purchases.GamePasses[pass.Key] then
			for key, value in pass.Modifiers do
				add(mods, key, value)
			end
		end
	end

	-- Equipment luck: items worn by members of the active battle team
	local team: { [string]: boolean } = {}
	for _, id in profile.Battle.Team do
		team[id] = true
	end
	for _, item in profile.Inventory.Equipment do
		if item.EquippedTo and team[item.EquippedTo] then
			local bonuses = EquipMath.itemBonuses(item)
			add(mods, "EquipmentLuck", bonuses.LuckPct)
		end
	end

	-- Caps
	for key in CAPS do
		if mods[key] then
			mods[key] = Modifiers.cap(key, mods[key])
		end
	end

	-- Potions (online-only multipliers). The strongest active boost per stat applies.
	local boostEffectiveness = 1 + (mods.BoostEffectiveness or 0)
	local best: { [string]: number } = {}
	for consumableId, expiresAt in profile.Boosts do
		local def = CraftingConfig.Consumables[consumableId]
		local boost = def and def.Boost
		if boost and expiresAt > now then
			local m = 1 + (boost.Multiplier - 1) * boostEffectiveness
			if m > (best[boost.Stat] or 1) then
				best[boost.Stat] = m
			end
		end
	end
	mods.BoostLuckMult = best.Luck or 1
	mods.BoostIncomeMult = best.Income or 1
	mods.BoostBattleCoinsMult = best.BattleCoins or 1

	-- Live events (server time)
	for _, eventId in EventSchedule.activeIds(now) do
		local event = EventConfig.Events[eventId]
		mods.EventLuckMult *= event.LuckMultiplier
		mods.EventIncomeMult *= event.IncomeMultiplier
		mods.EventBattleCoinsMult *= event.BattleCoinMultiplier
	end

	return mods
end

-- Luck for a dice. Returns (raw, effective-after-soft-cap).
--   raw = BaseLuck * (1 + Luck + EquipmentLuck + HighTierLuck?) * BoostLuckMult * EventLuckMult
function Modifiers.luckFor(dice: DiceConfig.DiceDef, mods: Mods): (number, number)
	local additive = (mods.Luck or 0) + (mods.EquipmentLuck or 0)
	if dice.Order >= DiceConfig.Luck.HighTierFromOrder then
		additive += mods.HighTierLuck or 0
	end
	local raw = dice.BaseLuck * (1 + additive) * (mods.BoostLuckMult or 1) * (mods.EventLuckMult or 1)
	return raw, RollMath.effectiveLuck(raw)
end

function Modifiers.rollCost(dice: DiceConfig.DiceDef, mods: Mods): number
	return math.max(1, math.floor(dice.Cost * (1 - (mods.RollCostReduction or 0)) + 0.5))
end

-- Global income multiplier applied once to the sum of monster incomes.
function Modifiers.incomeMultiplier(mods: Mods, includeTemporary: boolean): number
	local m = 1 + (mods.Income or 0)
	if includeTemporary then
		m *= (mods.BoostIncomeMult or 1) * (mods.EventIncomeMult or 1)
	end
	return m
end

function Modifiers.battleCoinMultiplier(mods: Mods): number
	return (1 + (mods.BattleCoins or 0)) * (mods.BoostBattleCoinsMult or 1) * (mods.EventBattleCoinsMult or 1)
end

function Modifiers.monsterCapacity(mods: Mods): number
	return math.min(
		EconomyConfig.MaxMonsterCapacity,
		EconomyConfig.BaseMonsterCapacity + math.floor(mods.InventoryCapacity or 0)
	)
end

function Modifiers.equipmentCapacity(mods: Mods): number
	return math.min(
		EconomyConfig.MaxEquipmentCapacity,
		EconomyConfig.BaseEquipmentCapacity + math.floor(mods.EquipmentCapacity or 0)
	)
end

function Modifiers.offlineCapSeconds(mods: Mods): number
	local hours = math.min(
		EconomyConfig.OfflineMaxCapHours,
		EconomyConfig.OfflineBaseCapHours + (mods.OfflineCapHours or 0)
	)
	return hours * 3600
end

function Modifiers.offlineEfficiency(mods: Mods): number
	return math.min(
		EconomyConfig.OfflineMaxEfficiency,
		EconomyConfig.OfflineBaseEfficiency + (mods.OfflineEfficiency or 0)
	)
end

function Modifiers.craftQueueSize(mods: Mods): number
	return math.min(
		CraftingConfig.MaxQueueSize,
		CraftingConfig.BaseQueueSize + math.floor(mods.CraftQueue or 0)
	)
end

function Modifiers.craftSeconds(baseSeconds: number, mods: Mods): number
	return math.max(
		CraftingConfig.MinCraftSeconds,
		math.floor(baseSeconds * (1 - (mods.CraftSpeed or 0)) + 0.5)
	)
end

function Modifiers.loadoutSlots(mods: Mods): number
	return 1 + math.floor(mods.LoadoutSlots or 0)
end

function Modifiers.walkSpeed(mods: Mods): number
	return GameConfig.Movement.BaseWalkSpeed * (1 + (mods.WalkSpeed or 0))
end

function Modifiers.sprintSpeed(mods: Mods): number
	return Modifiers.walkSpeed(mods) * GameConfig.Movement.SprintMultiplier
end

function Modifiers.jumpPower(mods: Mods): number
	return GameConfig.Movement.BaseJumpPower * (1 + (mods.JumpPower or 0))
end

function Modifiers.travelCooldown(mods: Mods): number
	return GameConfig.Travel.CooldownSeconds * (1 - (mods.TravelCooldownReduction or 0))
end

function Modifiers.serviceCost(baseCoins: number, mods: Mods): number
	return math.floor(baseCoins * (1 - (mods.ServiceCostReduction or 0)) + 0.5)
end

return Modifiers
