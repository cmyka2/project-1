--!strict
-- Pure turn-based battle engine (no Roblox services; randomness injected).
-- CombatService owns battle instances and calls into this module; the client
-- only ever sees snapshots and event logs.
--
-- Round structure: at the start of each round every living unit is ordered
-- by effective Speed (ties: player side first, then lower slot). Each unit's
-- turn: cooldowns tick, damage/heal-over-time ticks, skip-turn statuses are
-- consumed, status durations tick, then the unit acts. Player units wait for
-- input; enemies act via AI. The battle ends when one side has no living
-- units or the round limit is exceeded (counts as a defeat).
--
-- Damage (see docs/FORMULAS.md):
--   dmg = Power * Atk * Atk/(Atk + Def*DefenseWeight) * Element * OwnElementBonus
--         * Crit * UltimateBonus * DamageTaken * (1-DamageReduction)*(1-ElementResist) * Variance
--   clamped to [MinDamage, MaxDamage] (exactly 0 only for configured immunities).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local EnemyConfig = require(Config:WaitForChild("EnemyConfig"))
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local StatMath = require(Shared:WaitForChild("Util"):WaitForChild("StatMath"))

type CombatStats = StatMath.CombatStats

export type StatusInstance = {
	Id: string,
	Duration: number,
	Stacks: number,
	Amount: number, -- shield absorb remaining (Shield only)
}

export type Unit = {
	Id: string,
	Side: "Player" | "Enemy",
	Slot: number,
	Name: string,
	MonsterId: string?,
	EnemyId: string?,
	InstanceId: string?,
	Element: string,
	ModelKey: string,
	Archetype: string,
	Rarity: string?,
	Level: number,
	Stats: CombatStats,
	Hp: number,
	Energy: number,
	Alive: boolean,
	Abilities: { string },
	Cooldowns: { [string]: number },
	Statuses: { StatusInstance },
	IsBoss: boolean,
	Phases: { EnemyConfig.BossPhase },
	PhasesTriggered: { [number]: boolean },
	AiProfile: string,
	Telegraph: boolean,
	Charging: string?,
	Controlled: boolean, -- true = waits for player input
}

export type BattleEvent = { [string]: any }

export type Battle = {
	Id: string,
	Round: number,
	State: "Running" | "PlayerTurn" | "Victory" | "Defeat",
	Units: { Unit },
	Queue: { string },
	Active: string?,
	Log: { BattleEvent },
	EventCursor: number,
	ItemsUsed: number,
	Rng: () -> number,
	EndReason: string?,
	SummonCounter: number,
}

export type Action = {
	Kind: "Ability" | "Defend" | "Item",
	AbilityId: string?,
	TargetId: string?,
	ItemId: string?,
}

local BattleEngine = {}

-- Construction -------------------------------------------------------------------

export type UnitSpec = {
	Name: string,
	MonsterId: string?,
	EnemyId: string?,
	InstanceId: string?,
	Element: string,
	ModelKey: string,
	Archetype: string,
	Rarity: string?,
	Level: number,
	Stats: CombatStats,
	Abilities: { string },
	IsBoss: boolean?,
	Phases: { EnemyConfig.BossPhase }?,
	AiProfile: string?,
	Telegraph: boolean?,
	Controlled: boolean,
}

local function makeUnit(spec: UnitSpec, side: "Player" | "Enemy", slot: number, id: string): Unit
	return {
		Id = id,
		Side = side,
		Slot = slot,
		Name = spec.Name,
		MonsterId = spec.MonsterId,
		EnemyId = spec.EnemyId,
		InstanceId = spec.InstanceId,
		Element = spec.Element,
		ModelKey = spec.ModelKey,
		Archetype = spec.Archetype,
		Rarity = spec.Rarity,
		Level = spec.Level,
		Stats = spec.Stats,
		Hp = spec.Stats.MaxHealth,
		Energy = 0,
		Alive = true,
		Abilities = table.clone(spec.Abilities),
		Cooldowns = {},
		Statuses = {},
		IsBoss = spec.IsBoss == true,
		Phases = spec.Phases or {},
		PhasesTriggered = {},
		AiProfile = spec.AiProfile or "Balanced",
		Telegraph = spec.Telegraph == true,
		Charging = nil,
		Controlled = spec.Controlled,
	}
end

function BattleEngine.enemySpec(enemyId: string, level: number): UnitSpec?
	local def = EnemyConfig.Enemies[enemyId]
	if not def then
		return nil
	end
	return {
		Name = def.DisplayName,
		EnemyId = enemyId,
		Element = def.Element,
		ModelKey = def.ModelKey,
		Archetype = def.Archetype,
		Level = level,
		Stats = StatMath.enemyStats(def, level),
		Abilities = def.Abilities,
		IsBoss = def.IsBoss,
		Phases = def.Phases,
		AiProfile = def.AiProfile :: string,
		Telegraph = def.TelegraphUltimate,
		Controlled = false,
	}
end

local function log(battle: Battle, event: BattleEvent)
	table.insert(battle.Log, event)
end

function BattleEngine.new(id: string, players: { UnitSpec }, enemies: { UnitSpec }, rng: () -> number): Battle
	local battle: Battle = {
		Id = id,
		Round = 0,
		State = "Running",
		Units = {},
		Queue = {},
		Active = nil,
		Log = {},
		EventCursor = 0,
		ItemsUsed = 0,
		Rng = rng,
		EndReason = nil,
		SummonCounter = 0,
	}
	for i, spec in players do
		table.insert(battle.Units, makeUnit(spec, "Player", i, "p" .. i))
	end
	for i, spec in enemies do
		table.insert(battle.Units, makeUnit(spec, "Enemy", i, "e" .. i))
	end
	log(battle, { Type = "Start" })
	return battle
end

-- Queries --------------------------------------------------------------------------

function BattleEngine.unit(battle: Battle, id: string): Unit?
	for _, u in battle.Units do
		if u.Id == id then
			return u
		end
	end
	return nil
end

function BattleEngine.living(battle: Battle, side: "Player" | "Enemy"): { Unit }
	local out = {}
	for _, u in battle.Units do
		if u.Alive and u.Side == side then
			table.insert(out, u)
		end
	end
	return out
end

local function opponents(unit: Unit): "Player" | "Enemy"
	return if unit.Side == "Player" then "Enemy" else "Player"
end

local function statusDef(id: string): CombatConfig.StatusDef?
	return CombatConfig.StatusEffects[id]
end

local function findStatus(unit: Unit, id: string): StatusInstance?
	for _, s in unit.Statuses do
		if s.Id == id then
			return s
		end
	end
	return nil
end

function BattleEngine.statModifier(unit: Unit, stat: string): number
	local total = 0
	for _, s in unit.Statuses do
		local def = statusDef(s.Id)
		if def and def.Kind == "StatModifier" and def.Stat == stat then
			total += def.Magnitude * s.Stacks
		end
	end
	return math.clamp(total, -0.75, 2)
end

local function kindTotal(unit: Unit, kind: string): number
	local total = 0
	for _, s in unit.Statuses do
		local def = statusDef(s.Id)
		if def and def.Kind == kind then
			total += def.Magnitude * s.Stacks
		end
	end
	return total
end

function BattleEngine.speed(unit: Unit): number
	return unit.Stats.Speed * (1 + BattleEngine.statModifier(unit, "Speed"))
end

function BattleEngine.isAvailable(unit: Unit, abilityId: string): boolean
	if not table.find(unit.Abilities, abilityId) then
		return false
	end
	local ability = AbilityConfig.Abilities[abilityId]
	if not ability then
		return false
	end
	if ability.Kind == "Ultimate" then
		return unit.Energy >= ability.EnergyCost
	end
	return (unit.Cooldowns[abilityId] or 0) <= 0
end

-- Status effects ----------------------------------------------------------------------

function BattleEngine.applyStatus(
	battle: Battle,
	source: Unit?,
	target: Unit,
	statusId: string,
	chance: number,
	duration: number?,
	amount: number?
): boolean
	local def = statusDef(statusId)
	if not def or not target.Alive then
		return false
	end
	local effective = chance
	if def.Debuff and source and source.Side ~= target.Side then
		effective *= 1 - math.clamp(target.Stats.StatusResist, 0, CombatConfig.MaxStatusResist)
	end
	if effective < 1 and battle.Rng() >= effective then
		if def.Debuff then
			log(battle, { Type = "Resist", Target = target.Id, Status = statusId })
		end
		return false
	end
	local existing = findStatus(target, statusId)
	local dur = duration or def.DefaultDuration
	if existing then
		if def.Stacking == "Ignore" then
			return false
		elseif def.Stacking == "Stack" then
			existing.Stacks = math.min(def.MaxStacks, existing.Stacks + 1)
			existing.Duration = math.max(existing.Duration, dur)
		else
			existing.Duration = math.max(existing.Duration, dur)
		end
		if amount then
			existing.Amount = math.max(existing.Amount, amount)
		end
	else
		table.insert(target.Statuses, { Id = statusId, Duration = dur, Stacks = 1, Amount = amount or 0 })
	end
	log(battle, { Type = "Status", Target = target.Id, Status = statusId, Duration = dur })
	return true
end

local function removeStatus(unit: Unit, statusId: string)
	for i = #unit.Statuses, 1, -1 do
		if unit.Statuses[i].Id == statusId then
			table.remove(unit.Statuses, i)
		end
	end
end

local function cleanse(battle: Battle, unit: Unit)
	local removed = false
	for i = #unit.Statuses, 1, -1 do
		local def = statusDef(unit.Statuses[i].Id)
		if def and def.Debuff then
			table.remove(unit.Statuses, i)
			removed = true
		end
	end
	if removed then
		log(battle, { Type = "Cleanse", Target = unit.Id })
	end
end

-- Damage & healing ---------------------------------------------------------------------

local function defeat(battle: Battle, unit: Unit)
	if not unit.Alive then
		return
	end
	unit.Alive = false
	unit.Hp = 0
	unit.Statuses = {}
	unit.Charging = nil
	log(battle, { Type = "Defeated", Unit = unit.Id })
end

local function heal(battle: Battle, caster: Unit?, target: Unit, amount: number): number
	if not target.Alive or amount <= 0 then
		return 0
	end
	local modifier = 1 + kindTotal(target, "HealingModifier")
	local value = math.floor(amount * math.max(0, modifier))
	local missing = target.Stats.MaxHealth - target.Hp
	value = math.clamp(value, 0, missing)
	target.Hp += value
	log(
		battle,
		{ Type = "Heal", Source = if caster then caster.Id else nil, Target = target.Id, Amount = value }
	)
	return value
end

local function triggerPhases(battle: Battle, unit: Unit)
	if not unit.IsBoss or not unit.Alive then
		return
	end
	local fraction = unit.Hp / unit.Stats.MaxHealth
	for index, phase in unit.Phases do
		if not unit.PhasesTriggered[index] and fraction <= phase.HealthBelow then
			unit.PhasesTriggered[index] = true
			log(battle, { Type = "Phase", Unit = unit.Id, Message = string.format(phase.Message, unit.Name) })
			for _, statusId in phase.Statuses do
				BattleEngine.applyStatus(battle, unit, unit, statusId, 1, 99)
			end
			if phase.ShieldPercent then
				BattleEngine.applyStatus(
					battle,
					unit,
					unit,
					"Shield",
					1,
					3,
					math.floor(unit.Stats.MaxHealth * phase.ShieldPercent)
				)
			end
			if phase.UnlockAbility and not table.find(unit.Abilities, phase.UnlockAbility) then
				table.insert(unit.Abilities, phase.UnlockAbility)
			end
			if phase.Summon and #BattleEngine.living(battle, "Enemy") < CombatConfig.MaxEnemies then
				local spec = BattleEngine.enemySpec(phase.Summon, unit.Level)
				if spec then
					battle.SummonCounter += 1
					local summoned =
						makeUnit(spec, "Enemy", 10 + battle.SummonCounter, "s" .. battle.SummonCounter)
					table.insert(battle.Units, summoned)
					log(
						battle,
						{ Type = "Summon", Unit = summoned.Id, Name = summoned.Name, Source = unit.Id }
					)
				end
			end
		end
	end
end

-- Deals already-computed damage, absorbing with shields first.
local function dealDamage(
	battle: Battle,
	source: Unit?,
	target: Unit,
	amount: number,
	info: BattleEvent
): number
	if not target.Alive then
		return 0
	end
	local remaining = amount
	local shield = findStatus(target, "Shield")
	local absorbed = 0
	if shield and shield.Amount > 0 then
		absorbed = math.min(shield.Amount, remaining)
		shield.Amount -= absorbed
		remaining -= absorbed
		if shield.Amount <= 0 then
			removeStatus(target, "Shield")
		end
	end
	target.Hp = math.max(0, target.Hp - remaining)
	info.Type = info.Type or "Damage"
	info.Source = if source then source.Id else nil
	info.Target = target.Id
	info.Amount = remaining
	info.Absorbed = absorbed
	log(battle, info)
	if remaining > 0 then
		target.Energy = math.min(CombatConfig.MaxEnergy, target.Energy + CombatConfig.EnergyOnDamaged)
	end
	if target.Hp <= 0 then
		defeat(battle, target)
	else
		triggerPhases(battle, target)
	end
	return remaining
end

-- The damage formula. Returns (damage, crit, effectiveness).
function BattleEngine.computeDamage(
	battle: Battle,
	attacker: Unit,
	target: Unit,
	ability: AbilityConfig.AbilityDef
): (number, boolean, number)
	local element = ability.Element or attacker.Element
	local effectiveness = CombatConfig.effectiveness(element, target.Element)
	if effectiveness <= 0 then
		return 0, false, 0 -- explicit immunity only
	end
	local atk = math.max(1, attacker.Stats.Attack * (1 + BattleEngine.statModifier(attacker, "Attack")))
	local def = math.max(0, target.Stats.Defense * (1 + BattleEngine.statModifier(target, "Defense")))
	def *= 1 - math.clamp(ability.DefensePierce or 0, 0, 1)
	local defenseFactor = atk / (atk + def * CombatConfig.DefenseWeight)
	local ownElement = if element == attacker.Element then 1 + attacker.Stats.ElementDamage else 1
	local critChance =
		math.clamp(attacker.Stats.CritChance + (ability.CritBonus or 0), 0, CombatConfig.MaxCritChance)
	local crit = battle.Rng() < critChance
	local critFactor = if crit then math.max(1, attacker.Stats.CritDamage) else 1
	local ultimate = if ability.Kind == "Ultimate" then 1 + attacker.Stats.UltimateDamage else 1
	local taken = math.max(0.25, 1 + kindTotal(target, "DamageTakenModifier"))
	local reduction = (1 - math.clamp(target.Stats.DamageReduction, 0, CombatConfig.MaxDamageReduction))
		* (1 - math.clamp(target.Stats.ElementResist, 0, 0.5))
	local vmin = ability.VarianceMin or CombatConfig.VarianceMin
	local vmax = ability.VarianceMax or CombatConfig.VarianceMax
	local variance = vmin + (vmax - vmin) * battle.Rng()
	local raw = ability.Power
		* atk
		* defenseFactor
		* effectiveness
		* ownElement
		* critFactor
		* ultimate
		* taken
		* reduction
		* variance
	if raw ~= raw then
		raw = CombatConfig.MinDamage
	end
	local damage = math.clamp(math.floor(raw), CombatConfig.MinDamage, CombatConfig.MaxDamage)
	return damage, crit, effectiveness
end

local function hitChance(attacker: Unit, target: Unit, ability: AbilityConfig.AbilityDef): number
	local accuracy = ability.Accuracy
		* attacker.Stats.Accuracy
		* (1 + BattleEngine.statModifier(attacker, "Accuracy"))
	local evasion = target.Stats.Evasion * (1 + BattleEngine.statModifier(target, "Evasion"))
	return math.clamp(accuracy - evasion, CombatConfig.MinHitChance, CombatConfig.MaxHitChance)
end

-- Targeting ------------------------------------------------------------------------------

function BattleEngine.validTargets(battle: Battle, caster: Unit, ability: AbilityConfig.AbilityDef): { Unit }
	local t = ability.Target
	if t == "SingleEnemy" or t == "AllEnemies" or t == "RandomEnemies" then
		return BattleEngine.living(battle, opponents(caster))
	elseif t == "Self" then
		return { caster }
	end
	return BattleEngine.living(battle, caster.Side)
end

local function resolveTargets(
	battle: Battle,
	caster: Unit,
	ability: AbilityConfig.AbilityDef,
	targetId: string?
): { Unit }?
	local t = ability.Target
	local pool = BattleEngine.validTargets(battle, caster, ability)
	if #pool == 0 then
		return nil
	end
	if t == "AllEnemies" or t == "AllAllies" then
		return pool
	elseif t == "Self" then
		return { caster }
	elseif t == "LowestAlly" then
		local best = pool[1]
		for _, u in pool do
			if u.Hp / u.Stats.MaxHealth < best.Hp / best.Stats.MaxHealth then
				best = u
			end
		end
		return { best }
	elseif t == "RandomEnemies" then
		local out = {}
		for _ = 1, ability.Hits or 1 do
			table.insert(out, pool[math.clamp(math.floor(battle.Rng() * #pool) + 1, 1, #pool)])
		end
		return out
	end
	-- SingleEnemy / SingleAlly need an explicit, valid target
	if not targetId then
		return nil
	end
	for _, u in pool do
		if u.Id == targetId then
			return { u }
		end
	end
	return nil
end

-- Executing actions ------------------------------------------------------------------------

local function useAbility(battle: Battle, caster: Unit, ability: AbilityConfig.AbilityDef, targets: { Unit })
	log(battle, {
		Type = "Ability",
		Source = caster.Id,
		Ability = ability.Id,
		Targets = (function()
			local ids = {}
			for _, t in targets do
				table.insert(ids, t.Id)
			end
			return ids
		end)(),
	})
	if ability.Kind == "Ultimate" then
		caster.Energy = 0
	elseif ability.Kind == "Special" then
		caster.Cooldowns[ability.Id] = ability.Cooldown
		caster.Energy = math.min(CombatConfig.MaxEnergy, caster.Energy + CombatConfig.SpecialEnergyGain)
	else
		caster.Energy = math.min(CombatConfig.MaxEnergy, caster.Energy + CombatConfig.BasicEnergyGain)
	end
	local isOffensive = ability.Target == "SingleEnemy"
		or ability.Target == "AllEnemies"
		or ability.Target == "RandomEnemies"
	for _, target in targets do
		if target.Alive then
			if ability.Power > 0 and isOffensive then
				if battle.Rng() > hitChance(caster, target, ability) then
					log(
						battle,
						{ Type = "Miss", Source = caster.Id, Target = target.Id, Ability = ability.Id }
					)
				else
					local damage, crit, effectiveness =
						BattleEngine.computeDamage(battle, caster, target, ability)
					local dealt = dealDamage(
						battle,
						caster,
						target,
						damage,
						{ Ability = ability.Id, Crit = crit, Effectiveness = effectiveness }
					)
					if ability.Lifesteal and dealt > 0 and caster.Alive then
						heal(battle, caster, caster, dealt * ability.Lifesteal)
					end
					if target.Alive and ability.Statuses then
						for _, application in ability.Statuses do
							local recipient = application.Recipient or "Target"
							if recipient == "Target" then
								BattleEngine.applyStatus(
									battle,
									caster,
									target,
									application.Status,
									application.Chance,
									application.Duration
								)
							end
						end
					end
				end
			else
				if ability.HealPower then
					heal(
						battle,
						caster,
						target,
						ability.HealPower * caster.Stats.Attack * (1 + caster.Stats.Healing)
					)
				end
				if ability.ShieldPercent then
					BattleEngine.applyStatus(
						battle,
						caster,
						target,
						"Shield",
						1,
						nil,
						math.floor(caster.Stats.MaxHealth * ability.ShieldPercent)
					)
				end
				if ability.Cleanse then
					cleanse(battle, target)
				end
				if ability.Statuses then
					for _, application in ability.Statuses do
						if (application.Recipient or "Target") == "Target" then
							BattleEngine.applyStatus(
								battle,
								caster,
								target,
								application.Status,
								application.Chance,
								application.Duration
							)
						end
					end
				end
			end
		end
	end
	-- self / team riders on offensive abilities
	if ability.Statuses then
		for _, application in ability.Statuses do
			if application.Recipient == "Self" then
				BattleEngine.applyStatus(
					battle,
					caster,
					caster,
					application.Status,
					application.Chance,
					application.Duration
				)
			elseif application.Recipient == "AllAllies" then
				for _, ally in BattleEngine.living(battle, caster.Side) do
					BattleEngine.applyStatus(
						battle,
						caster,
						ally,
						application.Status,
						application.Chance,
						application.Duration
					)
				end
			end
		end
	end
end

local function checkEnd(battle: Battle): boolean
	if battle.State == "Victory" or battle.State == "Defeat" then
		return true
	end
	if #BattleEngine.living(battle, "Enemy") == 0 then
		battle.State = "Victory"
		battle.Active = nil
		log(battle, { Type = "Result", Victory = true })
		return true
	end
	if #BattleEngine.living(battle, "Player") == 0 then
		battle.State = "Defeat"
		battle.Active = nil
		battle.EndReason = "Your team was defeated."
		log(battle, { Type = "Result", Victory = false })
		return true
	end
	return false
end

-- Enemy AI ----------------------------------------------------------------------------------

local function pickRandom<T>(battle: Battle, list: { T }): T
	return list[math.clamp(math.floor(battle.Rng() * #list) + 1, 1, #list)]
end

local function bestDamageTarget(battle: Battle, caster: Unit, ability: AbilityConfig.AbilityDef): Unit?
	local pool = BattleEngine.living(battle, opponents(caster))
	local best: Unit? = nil
	local bestScore = -math.huge
	local element = ability.Element or caster.Element
	for _, u in pool do
		local score = CombatConfig.effectiveness(element, u.Element) * 2 + (1 - u.Hp / u.Stats.MaxHealth)
		if score > bestScore then
			bestScore = score
			best = u
		end
	end
	return best
end

function BattleEngine.chooseAiAction(battle: Battle, unit: Unit): Action
	local smart = unit.AiProfile == "Smart"
		or (unit.AiProfile == "Balanced" and battle.Rng() < EnemyConfig.BalancedOptimalChance)
	local available = {}
	for _, id in unit.Abilities do
		if BattleEngine.isAvailable(unit, id) then
			table.insert(available, id)
		end
	end
	if #available == 0 then
		return { Kind = "Defend" }
	end
	if not smart then
		local id = pickRandom(battle, available)
		local ability = AbilityConfig.Abilities[id]
		local targets = BattleEngine.validTargets(battle, unit, ability)
		return {
			Kind = "Ability",
			AbilityId = id,
			TargetId = if #targets > 0 then pickRandom(battle, targets).Id else nil,
		}
	end
	local allies = BattleEngine.living(battle, unit.Side)
	-- 1. heal / shield a hurt ally
	local hurt: Unit? = nil
	for _, ally in allies do
		if
			ally.Hp / ally.Stats.MaxHealth < EnemyConfig.AiHealThreshold
			and (hurt == nil or ally.Hp < (hurt :: Unit).Hp)
		then
			hurt = ally
		end
	end
	if hurt then
		for _, id in available do
			local ability = AbilityConfig.Abilities[id]
			if ability.HealPower or ability.ShieldPercent then
				return { Kind = "Ability", AbilityId = id, TargetId = (hurt :: Unit).Id }
			end
		end
	end
	-- 2. ultimate
	for _, id in available do
		local ability = AbilityConfig.Abilities[id]
		if ability.Kind == "Ultimate" then
			local target = bestDamageTarget(battle, unit, ability)
			return { Kind = "Ability", AbilityId = id, TargetId = if target then target.Id else nil }
		end
	end
	-- 3. buffs the team does not have yet
	for _, id in available do
		local ability = AbilityConfig.Abilities[id]
		if ability.Power == 0 and not ability.HealPower and ability.Statuses and #ability.Statuses > 0 then
			local statusId = ability.Statuses[1].Status
			if not findStatus(unit, statusId) and battle.Rng() < 0.6 then
				return { Kind = "Ability", AbilityId = id, TargetId = unit.Id }
			end
		end
	end
	-- 4. strongest damaging special, else basic
	local bestId: string? = nil
	local bestPower = -1
	for _, id in available do
		local ability = AbilityConfig.Abilities[id]
		if ability.Power > 0 and ability.Power * (ability.Hits or 1) > bestPower then
			bestPower = ability.Power * (ability.Hits or 1)
			bestId = id
		end
	end
	if bestId then
		local ability = AbilityConfig.Abilities[bestId]
		local target = bestDamageTarget(battle, unit, ability)
		return { Kind = "Ability", AbilityId = bestId, TargetId = if target then target.Id else nil }
	end
	return { Kind = "Defend" }
end

-- Turn processing ---------------------------------------------------------------------------

local function execute(battle: Battle, unit: Unit, action: Action): (boolean, string?)
	if action.Kind == "Defend" then
		BattleEngine.applyStatus(battle, unit, unit, "Defending", 1, 1)
		unit.Energy = math.min(CombatConfig.MaxEnergy, unit.Energy + CombatConfig.DefendEnergyGain)
		log(battle, { Type = "Defend", Source = unit.Id })
		return true, nil
	elseif action.Kind == "Item" then
		local item = action.ItemId and CraftingConfig.Consumables[action.ItemId]
		if not item or item.Kind ~= "BattleHeal" then
			return false, "That item can't be used in battle."
		end
		if battle.ItemsUsed >= CombatConfig.MaxItemUsesPerBattle then
			return false, "No more items this battle."
		end
		local targets: { Unit } = {}
		if item.HealAll then
			targets = BattleEngine.living(battle, unit.Side)
		else
			local target = action.TargetId and BattleEngine.unit(battle, action.TargetId)
			if not target or not target.Alive or target.Side ~= unit.Side then
				return false, "Pick an ally to heal."
			end
			targets = { target }
		end
		battle.ItemsUsed += 1
		log(battle, { Type = "Item", Source = unit.Id, Item = item.Id })
		for _, t in targets do
			heal(battle, unit, t, t.Stats.MaxHealth * (item.HealPercent or 0))
		end
		return true, nil
	end
	local abilityId = action.AbilityId
	local ability = abilityId and AbilityConfig.Abilities[abilityId]
	if not abilityId or not ability then
		return false, "Unknown ability."
	end
	if not BattleEngine.isAvailable(unit, abilityId) then
		return false, "That ability isn't ready."
	end
	local targets = resolveTargets(battle, unit, ability, action.TargetId)
	if not targets then
		return false, "Pick a valid target."
	end
	useAbility(battle, unit, ability, targets)
	return true, nil
end

local function startRound(battle: Battle)
	battle.Round += 1
	local living = {}
	for _, u in battle.Units do
		if u.Alive then
			table.insert(living, u)
		end
	end
	table.sort(living, function(a: Unit, b: Unit)
		local sa, sb = BattleEngine.speed(a), BattleEngine.speed(b)
		if sa ~= sb then
			return sa > sb
		end
		if a.Side ~= b.Side then
			return a.Side == "Player"
		end
		return a.Slot < b.Slot
	end)
	battle.Queue = {}
	for _, u in living do
		table.insert(battle.Queue, u.Id)
	end
	log(battle, { Type = "Round", Round = battle.Round, Order = table.clone(battle.Queue) })
end

-- Start-of-turn processing. Returns false if the unit cannot act this turn.
local function beginTurn(battle: Battle, unit: Unit): boolean
	for id, cd in unit.Cooldowns do
		unit.Cooldowns[id] = math.max(0, cd - 1)
	end
	-- damage / heal over time
	for _, s in table.clone(unit.Statuses) do
		local def = statusDef(s.Id)
		if def and def.Timing == "TurnStart" and unit.Alive then
			if def.Kind == "DamageOverTime" then
				local amount = math.max(1, math.floor(unit.Stats.MaxHealth * def.Magnitude * s.Stacks))
				dealDamage(battle, nil, unit, amount, { Type = "Tick", Status = s.Id })
			elseif def.Kind == "HealOverTime" then
				heal(battle, nil, unit, unit.Stats.MaxHealth * def.Magnitude * s.Stacks)
			end
		end
	end
	if not unit.Alive then
		return false
	end
	local skip = false
	for _, s in unit.Statuses do
		local def = statusDef(s.Id)
		if def and def.Kind == "SkipTurn" then
			skip = true
			log(battle, { Type = "Skip", Unit = unit.Id, Status = s.Id })
			break
		end
	end
	-- durations tick down at the start of the owner's turn
	for i = #unit.Statuses, 1, -1 do
		local s = unit.Statuses[i]
		s.Duration -= 1
		if s.Duration <= 0 then
			table.remove(unit.Statuses, i)
			log(battle, { Type = "Expire", Target = unit.Id, Status = s.Id })
		end
	end
	return not skip
end

-- Runs turns until the battle needs player input or ends.
function BattleEngine.advance(battle: Battle)
	local guard = 0
	while battle.State == "Running" do
		guard += 1
		if guard > 1000 then
			battle.State = "Defeat"
			battle.EndReason = "The battle stalled."
			log(battle, { Type = "Result", Victory = false })
			return
		end
		if checkEnd(battle) then
			return
		end
		if #battle.Queue == 0 then
			if battle.Round >= CombatConfig.MaxRounds then
				battle.State = "Defeat"
				battle.EndReason = "Time ran out."
				log(battle, { Type = "Result", Victory = false, Reason = "Timeout" })
				return
			end
			startRound(battle)
		end
		local unitId = table.remove(battle.Queue, 1) :: string
		local unit = BattleEngine.unit(battle, unitId)
		if unit and unit.Alive then
			log(battle, { Type = "Turn", Unit = unit.Id })
			local canAct = beginTurn(battle, unit)
			if checkEnd(battle) then
				return
			end
			if canAct and unit.Alive then
				if unit.Controlled then
					battle.State = "PlayerTurn"
					battle.Active = unit.Id
					return
				end
				-- telegraphed boss ultimates: charge one turn, release the next
				if unit.Charging then
					local id = unit.Charging
					unit.Charging = nil
					local ability = AbilityConfig.Abilities[id]
					local targets = ability and resolveTargets(battle, unit, ability, nil)
					if ability and targets then
						useAbility(battle, unit, ability, targets)
					end
				else
					local action = BattleEngine.chooseAiAction(battle, unit)
					local ability = action.AbilityId and AbilityConfig.Abilities[action.AbilityId]
					if unit.Telegraph and ability and ability.Kind == "Ultimate" then
						unit.Charging = ability.Id
						unit.Energy = 0
						log(battle, { Type = "Charging", Unit = unit.Id, Ability = ability.Id })
					else
						local ok = execute(battle, unit, action)
						if not ok then
							execute(battle, unit, { Kind = "Defend" })
						end
					end
				end
			end
		end
	end
end

-- Applies the player's chosen action for the active unit, then continues.
function BattleEngine.playerAction(battle: Battle, unitId: string, action: Action): (boolean, string?)
	if battle.State ~= "PlayerTurn" then
		return false, "It's not your turn."
	end
	if battle.Active ~= unitId then
		return false, "That monster isn't acting right now."
	end
	local unit = BattleEngine.unit(battle, unitId)
	if not unit or not unit.Alive or unit.Side ~= "Player" then
		return false, "Invalid monster."
	end
	local ok, err = execute(battle, unit, action)
	if not ok then
		return false, err
	end
	battle.State = "Running"
	battle.Active = nil
	BattleEngine.advance(battle)
	return true, nil
end

-- Default action used when the player times out: basic attack on the weakest enemy.
function BattleEngine.defaultAction(battle: Battle, unit: Unit): Action
	local basic = unit.Abilities[1]
	local enemies = BattleEngine.living(battle, opponents(unit))
	table.sort(enemies, function(a, b)
		return a.Hp < b.Hp
	end)
	return { Kind = "Ability", AbilityId = basic, TargetId = if enemies[1] then enemies[1].Id else nil }
end

function BattleEngine.forfeit(battle: Battle)
	if battle.State == "Victory" or battle.State == "Defeat" then
		return
	end
	battle.State = "Defeat"
	battle.Active = nil
	battle.EndReason = "You fled the battle."
	log(battle, { Type = "Result", Victory = false, Reason = "Forfeit" })
end

-- Client-facing view of the battle (no rng, no internal references).
function BattleEngine.snapshot(battle: Battle): { [string]: any }
	local units = {}
	for _, u in battle.Units do
		local abilities = {}
		if u.Side == "Player" then
			for _, id in u.Abilities do
				table.insert(
					abilities,
					{ Id = id, Ready = BattleEngine.isAvailable(u, id), Cooldown = u.Cooldowns[id] or 0 }
				)
			end
		end
		local statuses = {}
		for _, s in u.Statuses do
			table.insert(statuses, { Id = s.Id, Duration = s.Duration, Stacks = s.Stacks, Amount = s.Amount })
		end
		table.insert(units, {
			Id = u.Id,
			Side = u.Side,
			Slot = u.Slot,
			Name = u.Name,
			MonsterId = u.MonsterId,
			EnemyId = u.EnemyId,
			Element = u.Element,
			ModelKey = u.ModelKey,
			Archetype = u.Archetype,
			Rarity = u.Rarity,
			Level = u.Level,
			Hp = u.Hp,
			MaxHp = u.Stats.MaxHealth,
			Energy = u.Energy,
			Alive = u.Alive,
			IsBoss = u.IsBoss,
			Charging = u.Charging,
			Abilities = abilities,
			Statuses = statuses,
			Speed = math.floor(BattleEngine.speed(u) * 10) / 10,
		})
	end
	return {
		Id = battle.Id,
		Round = battle.Round,
		State = battle.State,
		Active = battle.Active,
		Queue = table.clone(battle.Queue),
		Units = units,
		ItemsUsed = battle.ItemsUsed,
		MaxItems = CombatConfig.MaxItemUsesPerBattle,
		EndReason = battle.EndReason,
	}
end

-- Events added since the previous call.
function BattleEngine.takeEvents(battle: Battle): { BattleEvent }
	local out = {}
	for i = battle.EventCursor + 1, #battle.Log do
		table.insert(out, battle.Log[i])
	end
	battle.EventCursor = #battle.Log
	return out
end

return BattleEngine
