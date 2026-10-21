--!strict
-- Monster income, costs, combat stats and leveling (pure). The server uses
-- these results authoritatively; the client uses the same code for display.
-- Formulas are documented in docs/FORMULAS.md.

local MonsterConfig = require(script.Parent.Parent.Config.MonsterConfig)
local RarityConfig = require(script.Parent.Parent.Config.RarityConfig)
local RegionConfig = require(script.Parent.Parent.Config.RegionConfig)
local DiceConfig = require(script.Parent.Parent.Config.DiceConfig)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local CombatConfig = require(script.Parent.Parent.Config.CombatConfig)
local EnemyConfig = require(script.Parent.Parent.Config.EnemyConfig)
local EquipMath = require(script.Parent.EquipMath)
local Types = require(script.Parent.Parent.Types)

export type CombatStats = {
	MaxHealth: number,
	Attack: number,
	Defense: number,
	Speed: number,
	CritChance: number,
	CritDamage: number,
	Accuracy: number,
	Evasion: number,
	StatusResist: number,
	ElementDamage: number, -- bonus fraction on own-element damage
	ElementResist: number, -- fraction of incoming damage reduced
	Healing: number, -- bonus fraction on healing done
	DamageReduction: number,
	UltimateDamage: number,
}

type Mods = { [string]: number }

local StatMath = {}

local function finite(x: number, fallback: number): number
	if x ~= x or x == math.huge or x == -math.huge then
		return fallback
	end
	return x
end

-- Income -----------------------------------------------------------------------

function StatMath.levelIncomeMultiplier(level: number): number
	return 1 + math.max(0, level - 1) * EconomyConfig.LevelIncomeBonusPerLevel
end

function StatMath.upgradeIncomeMultiplier(upgrade: number, mods: Mods): number
	return 1 + upgrade * EconomyConfig.UpgradeIncomeBonusPerLevel * (1 + (mods.UpgradeEffectiveness or 0))
end

function StatMath.starIncomeMultiplier(stars: number): number
	return 1 + stars * EconomyConfig.StarIncomeBonus
end

-- Coins/sec of one monster BEFORE the global multiplier (skills, rebirth, events).
--   BaseIncome * RarityIncome * Level * Upgrade * Stars * (1 + equipment IncomePct)
function StatMath.monsterIncome(inst: Types.MonsterInstance, equipmentIncomePct: number, mods: Mods): number
	local def = MonsterConfig.Monsters[inst.MonsterId]
	if not def or not def.CanPlaceInBase then
		return 0
	end
	local rarity = RarityConfig.Rarities[def.Rarity]
	local income = def.BaseIncomePerSecond
		* rarity.IncomeMultiplier
		* StatMath.levelIncomeMultiplier(inst.Level)
		* StatMath.upgradeIncomeMultiplier(inst.Upgrade, mods)
		* StatMath.starIncomeMultiplier(inst.Stars)
		* (1 + math.max(0, equipmentIncomePct))
	return finite(income, 0)
end

-- Total coins/sec for a profile: sum over placed monsters, times the global multiplier once.
-- Returns (total, perMonster).
function StatMath.totalIncome(
	profile: Types.Profile,
	mods: Mods,
	globalMultiplier: number
): (number, { [string]: number })
	local perMonster: { [string]: number } = {}
	local sum = 0
	local seen: { [string]: boolean } = {}
	-- index equipment by wearer once instead of scanning per monster
	local worn: { [string]: { Types.EquipmentInstance } } = {}
	for _, item in profile.Inventory.Equipment do
		local wearer = item.EquippedTo
		if wearer then
			local list = worn[wearer]
			if not list then
				list = {}
				worn[wearer] = list
			end
			table.insert(list, item)
		end
	end
	for _, instanceId in profile.Base.PlacedMonsters do
		local inst = profile.Inventory.Monsters[instanceId]
		if inst and not seen[instanceId] then
			seen[instanceId] = true
			local items = worn[instanceId]
			local equipIncome = if items then EquipMath.monsterBonuses(items).IncomePct else 0
			local income = StatMath.monsterIncome(inst, equipIncome, mods) * globalMultiplier
			perMonster[instanceId] = income
			sum += income
		end
	end
	return math.min(finite(sum, 0), EconomyConfig.MaxCurrency), perMonster
end

-- Costs & values -------------------------------------------------------------

function StatMath.maxUpgrade(inst: Types.MonsterInstance): number
	local def = MonsterConfig.Monsters[inst.MonsterId]
	if not def then
		return 0
	end
	return RarityConfig.Rarities[def.Rarity].MaxUpgradeLevel
end

--   BaseIncome * RarityIncome * UpgradeCostSeconds * Growth ^ upgrade * (1 - UpgradeCostReduction)
function StatMath.upgradeCost(inst: Types.MonsterInstance, mods: Mods): number
	local def = MonsterConfig.Monsters[inst.MonsterId]
	if not def then
		return math.huge
	end
	local rarity = RarityConfig.Rarities[def.Rarity]
	local cost = def.BaseIncomePerSecond
		* rarity.IncomeMultiplier
		* EconomyConfig.UpgradeCostSeconds
		* EconomyConfig.UpgradeCostGrowth ^ inst.Upgrade
		* (1 - (mods.UpgradeCostReduction or 0))
	return math.max(1, math.floor(finite(cost, math.huge) + 0.5))
end

function StatMath.regionDiceCost(regionId: string): number
	local region = RegionConfig.Regions[regionId]
	local dice = region and DiceConfig.Dice[region.DiceId]
	return if dice then dice.Cost else 25
end

-- The dice a monster's sale is priced against: the event dice for event
-- monsters, otherwise its region's dice.
local sellDiceCache: { [string]: DiceConfig.DiceDef } = {}
local function sellDice(def: MonsterConfig.MonsterDef): DiceConfig.DiceDef?
	local key = def.EventId or def.Region
	local cached = sellDiceCache[key]
	if cached then
		return cached
	end
	local found: DiceConfig.DiceDef? = nil
	if def.EventId then
		for _, dice in DiceConfig.Dice do
			if dice.EventId == def.EventId then
				found = dice
				break
			end
		end
	else
		local region = RegionConfig.Regions[def.Region]
		found = region and DiceConfig.Dice[region.DiceId]
	end
	if found then
		sellDiceCache[key] = found
	end
	return found
end

-- SellMultiplier of the most common rarity on a dice. Sell values are relative
-- to it, so the commonest result of every dice sells for SellBaseFraction of
-- that dice's cost no matter which rarity tier the dice starts at.
local floorSellCache: { [string]: number } = {}
local function floorSellMultiplier(dice: DiceConfig.DiceDef): number
	local cached = floorSellCache[dice.Id]
	if cached then
		return cached
	end
	local floorMult, bestTier = 1, math.huge
	for rarityId, weight in dice.RarityWeights do
		local rarity = RarityConfig.Rarities[rarityId]
		if rarity and weight > 0 and rarity.Tier < bestTier then
			bestTier = rarity.Tier
			floorMult = rarity.SellMultiplier
		end
	end
	floorSellCache[dice.Id] = floorMult
	return floorMult
end

-- Coins refunded on sale for a monster's upgrades: a fraction of what those
-- upgrades cost at the maximum cost reduction, so it is never more than the
-- player actually paid, whatever their current modifiers are.
function StatMath.upgradeRefund(inst: Types.MonsterInstance): number
	local cheapest = { UpgradeCostReduction = EconomyConfig.UpgradeCostReductionCap }
	local total = 0
	for level = 0, inst.Upgrade - 1 do
		local probe = table.clone(inst)
		probe.Upgrade = level
		total += StatMath.upgradeCost(probe, cheapest)
	end
	return total * EconomyConfig.SellUpgradeRefund
end

--   DiceCost * SellBaseFraction * RaritySell / DiceFloorSell
--     * (1 + stars*SellPerStar) * (1 + SellValue) + UpgradeRefund
-- (DiceCost: the monster's region dice, or its event dice for event monsters)
function StatMath.sellValue(inst: Types.MonsterInstance, mods: Mods): number
	local def = MonsterConfig.Monsters[inst.MonsterId]
	if not def then
		return 0
	end
	local rarity = RarityConfig.Rarities[def.Rarity]
	local dice = sellDice(def)
	local value = (if dice then dice.Cost else 25)
		* EconomyConfig.SellBaseFraction
		* rarity.SellMultiplier
		/ (if dice then floorSellMultiplier(dice) else 1)
		* (1 + inst.Stars * EconomyConfig.SellPerStar)
		* (1 + (mods.SellValue or 0))
	value += StatMath.upgradeRefund(inst)
	return math.max(1, math.floor(finite(value, 0) + 0.5))
end

-- Leveling ----------------------------------------------------------------------

-- XP needed to go from `level` to `level + 1`.
function StatMath.xpToNext(level: number): number
	return math.floor(CombatConfig.XpCurveBase * level ^ CombatConfig.XpCurveExponent)
end

-- Applies XP; returns (newLevel, newXp, levelsGained).
function StatMath.applyXp(level: number, xp: number, gained: number): (number, number, number)
	local maxLevel = CombatConfig.MaxMonsterLevel
	local lvl, cur = level, xp + math.max(0, gained)
	local start = level
	while lvl < maxLevel do
		local need = StatMath.xpToNext(lvl)
		if cur < need then
			break
		end
		cur -= need
		lvl += 1
	end
	if lvl >= maxLevel then
		cur = 0
	end
	return lvl, cur, lvl - start
end

-- Combat stats -------------------------------------------------------------------

local function emptyExtras(): CombatStats
	return {
		MaxHealth = 1,
		Attack = 1,
		Defense = 0,
		Speed = 1,
		CritChance = 0,
		CritDamage = 1.5,
		Accuracy = 1,
		Evasion = 0,
		StatusResist = 0,
		ElementDamage = 0,
		ElementResist = 0,
		Healing = 0,
		DamageReduction = 0,
		UltimateDamage = 0,
	}
end

-- Final stats of a player's monster:
--   stat = Base * RarityStat * (1 + 0.06*(level-1)) * (1 + 0.04*upgrade) * (1 + 0.15*stars)
--          * (1 + equipment%) * (1 + skill/ascension%)
function StatMath.monsterStats(
	inst: Types.MonsterInstance,
	equipment: { Types.EquipmentInstance },
	mods: Mods
): CombatStats
	local def = MonsterConfig.Monsters[inst.MonsterId]
	if not def then
		return emptyExtras()
	end
	local rarity = RarityConfig.Rarities[def.Rarity]
	local growth = 1 + math.max(0, inst.Level - 1) * CombatConfig.StatGrowthPerLevel
	local upgrade = 1 + inst.Upgrade * EconomyConfig.UpgradeStatBonusPerLevel
	local stars = 1 + inst.Stars * EconomyConfig.StarStatBonus
	local core = rarity.StatMultiplier * growth * upgrade * stars
	local eq = EquipMath.monsterBonuses(equipment)
	local base = def.BaseStats
	return {
		MaxHealth = math.max(
			1,
			math.floor(base.MaxHealth * core * (1 + eq.HealthPct) * (1 + (mods.Health or 0)))
		),
		Attack = math.max(1, math.floor(base.Attack * core * (1 + eq.AttackPct) * (1 + (mods.Attack or 0)))),
		Defense = math.max(
			0,
			math.floor(base.Defense * core * (1 + eq.DefensePct) * (1 + (mods.Defense or 0)))
		),
		Speed = math.max(1, base.Speed * (1 + inst.Level * 0.005) * (1 + eq.SpeedPct)),
		CritChance = math.min(
			CombatConfig.MaxCritChance,
			base.CritChance + eq.CritChance + (mods.CritChance or 0)
		),
		CritDamage = base.CritDamage + eq.CritDamage + (mods.CritDamage or 0),
		Accuracy = base.Accuracy,
		Evasion = base.Evasion,
		StatusResist = math.min(CombatConfig.MaxStatusResist, base.StatusResist + (mods.StatusResist or 0)),
		ElementDamage = eq.ElementDamagePct + (mods.ElementDamage or 0),
		ElementResist = math.min(0.5, eq.ElementResistPct),
		Healing = eq.HealingPct + (mods.Healing or 0),
		DamageReduction = math.min(CombatConfig.MaxDamageReduction, mods.DamageReduction or 0),
		UltimateDamage = mods.UltimateDamage or 0,
	}
end

function StatMath.enemyStats(enemy: EnemyConfig.EnemyDef, level: number): CombatStats
	local base = CombatConfig.Archetypes[enemy.Archetype]
	local region = RegionConfig.Regions[enemy.Region]
	local scale = (if region then region.StatScale else 1) * enemy.PowerFactor
	local growth = 1 + math.max(0, level - 1) * CombatConfig.StatGrowthPerLevel
	local regionIndex = if region then region.Index else 1
	return {
		MaxHealth = math.max(1, math.floor(base.MaxHealth * scale * growth * enemy.HealthFactor)),
		Attack = math.max(1, math.floor(base.Attack * scale * growth)),
		Defense = math.max(0, math.floor(base.Defense * scale * growth)),
		Speed = base.Speed * (1 + (regionIndex - 1) * 0.04) * (1 + level * 0.005),
		CritChance = base.CritChance,
		CritDamage = base.CritDamage,
		Accuracy = base.Accuracy,
		Evasion = base.Evasion,
		StatusResist = base.StatusResist + (if enemy.IsBoss then 0.25 else 0),
		ElementDamage = 0,
		ElementResist = 0,
		Healing = 0,
		DamageReduction = 0,
		UltimateDamage = 0,
	}
end

-- Single power number for UI comparisons and recommended-power checks.
function StatMath.power(stats: CombatStats): number
	local w = CombatConfig.PowerWeights
	local p = stats.MaxHealth * w.MaxHealth
		+ stats.Attack * w.Attack
		+ stats.Defense * w.Defense
		+ stats.Speed * w.Speed
	p *= 1 + stats.CritChance * (stats.CritDamage - 1)
	return math.floor(finite(p, 0))
end

function StatMath.monsterPower(profile: Types.Profile, inst: Types.MonsterInstance, mods: Mods): number
	return StatMath.power(StatMath.monsterStats(inst, EquipMath.itemsOn(profile, inst.Id), mods))
end

function StatMath.teamPower(profile: Types.Profile, mods: Mods): number
	local total = 0
	for _, id in profile.Battle.Team do
		local inst = profile.Inventory.Monsters[id]
		if inst then
			total += StatMath.monsterPower(profile, inst, mods)
		end
	end
	return total
end

function StatMath.encounterPower(encounter: EnemyConfig.EncounterDef): number
	local total = 0
	for _, entry in encounter.Enemies do
		local enemy = EnemyConfig.Enemies[entry.Enemy]
		if enemy then
			total += StatMath.power(StatMath.enemyStats(enemy, entry.Level))
		end
	end
	return total
end

return StatMath
