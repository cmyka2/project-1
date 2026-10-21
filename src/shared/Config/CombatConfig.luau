--!strict
-- Turn-based combat rules: elements, the effectiveness matrix, status
-- effects, archetype base stats and every constant used by the damage
-- formula (see docs/FORMULAS.md for the full derivation).

export type ElementDef = {
	Id: string,
	DisplayName: string,
	Color: Color3,
	Glyph: string,
}

export type StatKind = "Attack" | "Defense" | "Speed" | "Accuracy" | "Evasion" | "CritChance"

export type StatusDef = {
	Id: string,
	DisplayName: string,
	Glyph: string,
	Color: Color3,
	Debuff: boolean,
	Kind: "DamageOverTime"
		| "HealOverTime"
		| "SkipTurn"
		| "StatModifier"
		| "Shield"
		| "HealingModifier"
		| "DamageTakenModifier",
	Stat: StatKind?, -- for StatModifier
	Magnitude: number, -- meaning depends on Kind (fraction of max HP, stat fraction, etc.)
	DefaultDuration: number, -- in the affected unit's turns
	Stacking: "Refresh" | "Stack" | "Ignore",
	MaxStacks: number,
	Timing: "TurnStart" | "Passive",
}

export type ArchetypeStats = {
	MaxHealth: number,
	Attack: number,
	Defense: number,
	Speed: number,
	CritChance: number,
	CritDamage: number,
	Accuracy: number,
	Evasion: number,
	StatusResist: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Elements: { [string]: ElementDef } = {
	Nature = { Id = "Nature", DisplayName = "Nature", Color = rgb(96, 200, 90), Glyph = "🌿" },
	Fire = { Id = "Fire", DisplayName = "Fire", Color = rgb(255, 110, 50), Glyph = "🔥" },
	Water = { Id = "Water", DisplayName = "Water", Color = rgb(60, 150, 255), Glyph = "💧" },
	Earth = { Id = "Earth", DisplayName = "Earth", Color = rgb(170, 120, 70), Glyph = "🪨" },
	Wind = { Id = "Wind", DisplayName = "Wind", Color = rgb(170, 240, 220), Glyph = "🌪" },
	Light = { Id = "Light", DisplayName = "Light", Color = rgb(255, 236, 140), Glyph = "✨" },
	Dark = { Id = "Dark", DisplayName = "Dark", Color = rgb(120, 70, 160), Glyph = "🌑" },
	Cosmic = { Id = "Cosmic", DisplayName = "Cosmic", Color = rgb(150, 110, 255), Glyph = "🪐" },
	Glitch = { Id = "Glitch", DisplayName = "Glitch", Color = rgb(60, 255, 140), Glyph = "👾" },
}

local ElementOrder: { string } =
	{ "Nature", "Fire", "Water", "Earth", "Wind", "Light", "Dark", "Cosmic", "Glitch" }

-- Effectiveness[attacker][defender]. Missing entries are neutral (1.0).
-- Each of the five basic elements is strong against two and weak against two.
local SUPER = 1.5
local RESIST = 0.67
local Effectiveness: { [string]: { [string]: number } } = {
	Fire = { Nature = SUPER, Wind = SUPER, Water = RESIST, Earth = RESIST, Fire = RESIST },
	Water = { Fire = SUPER, Earth = SUPER, Nature = RESIST, Wind = RESIST, Water = RESIST },
	Nature = { Water = SUPER, Earth = SUPER, Fire = RESIST, Wind = RESIST, Nature = RESIST },
	Earth = { Fire = SUPER, Wind = SUPER, Water = RESIST, Nature = RESIST },
	Wind = { Nature = SUPER, Water = SUPER, Earth = RESIST, Fire = RESIST },
	Light = { Dark = SUPER, Glitch = SUPER, Light = RESIST },
	Dark = { Light = SUPER, Dark = RESIST },
	Cosmic = { Light = SUPER, Dark = SUPER, Cosmic = RESIST, Glitch = RESIST },
	Glitch = { Cosmic = SUPER, Glitch = RESIST },
}

local StatusEffects: { [string]: StatusDef } = {
	Burn = {
		Id = "Burn",
		DisplayName = "Burn",
		Glyph = "🔥",
		Color = rgb(255, 120, 40),
		Debuff = true,
		Kind = "DamageOverTime",
		Magnitude = 0.06,
		DefaultDuration = 3,
		Stacking = "Refresh",
		MaxStacks = 1,
		Timing = "TurnStart",
	},
	Poison = {
		Id = "Poison",
		DisplayName = "Poison",
		Glyph = "☠",
		Color = rgb(150, 60, 200),
		Debuff = true,
		Kind = "DamageOverTime",
		Magnitude = 0.04,
		DefaultDuration = 3,
		Stacking = "Stack",
		MaxStacks = 3,
		Timing = "TurnStart",
	},
	Freeze = {
		Id = "Freeze",
		DisplayName = "Freeze",
		Glyph = "❄",
		Color = rgb(150, 220, 255),
		Debuff = true,
		Kind = "SkipTurn",
		Magnitude = 0,
		DefaultDuration = 1,
		Stacking = "Ignore",
		MaxStacks = 1,
		Timing = "TurnStart",
	},
	Stun = {
		Id = "Stun",
		DisplayName = "Stun",
		Glyph = "💫",
		Color = rgb(255, 230, 90),
		Debuff = true,
		Kind = "SkipTurn",
		Magnitude = 0,
		DefaultDuration = 1,
		Stacking = "Ignore",
		MaxStacks = 1,
		Timing = "TurnStart",
	},
	Slow = {
		Id = "Slow",
		DisplayName = "Slow",
		Glyph = "🐌",
		Color = rgb(120, 160, 200),
		Debuff = true,
		Kind = "StatModifier",
		Stat = "Speed",
		Magnitude = -0.3,
		DefaultDuration = 2,
		Stacking = "Refresh",
		MaxStacks = 1,
		Timing = "Passive",
	},
	SpeedUp = {
		Id = "SpeedUp",
		DisplayName = "Haste",
		Glyph = "⏩",
		Color = rgb(140, 255, 220),
		Debuff = false,
		Kind = "StatModifier",
		Stat = "Speed",
		Magnitude = 0.3,
		DefaultDuration = 2,
		Stacking = "Refresh",
		MaxStacks = 1,
		Timing = "Passive",
	},
	AttackUp = {
		Id = "AttackUp",
		DisplayName = "Attack Up",
		Glyph = "⚔",
		Color = rgb(255, 90, 90),
		Debuff = false,
		Kind = "StatModifier",
		Stat = "Attack",
		Magnitude = 0.3,
		DefaultDuration = 3,
		Stacking = "Refresh",
		MaxStacks = 1,
		Timing = "Passive",
	},
	AttackDown = {
		Id = "AttackDown",
		DisplayName = "Attack Down",
		Glyph = "⤵",
		Color = rgb(160, 90, 90),
		Debuff = true,
		Kind = "StatModifier",
		Stat = "Attack",
		Magnitude = -0.25,
		DefaultDuration = 2,
		Stacking = "Refresh",
		MaxStacks = 1,
		Timing = "Passive",
	},
	DefenseUp = {
		Id = "DefenseUp",
		DisplayName = "Defense Up",
		Glyph = "🛡",
		Color = rgb(90, 160, 255),
		Debuff = false,
		Kind = "StatModifier",
		Stat = "Defense",
		Magnitude = 0.35,
		DefaultDuration = 3,
		Stacking = "Refresh",
		MaxStacks = 1,
		Timing = "Passive",
	},
	DefenseDown = {
		Id = "DefenseDown",
		DisplayName = "Defense Down",
		Glyph = "💔",
		Color = rgb(120, 110, 160),
		Debuff = true,
		Kind = "StatModifier",
		Stat = "Defense",
		Magnitude = -0.3,
		DefaultDuration = 2,
		Stacking = "Refresh",
		MaxStacks = 1,
		Timing = "Passive",
	},
	Shield = {
		Id = "Shield",
		DisplayName = "Shield",
		Glyph = "🔰",
		Color = rgb(120, 220, 255),
		Debuff = false,
		Kind = "Shield",
		Magnitude = 0, -- the absorb amount is stored on the applied instance
		DefaultDuration = 3,
		Stacking = "Refresh",
		MaxStacks = 1,
		Timing = "Passive",
	},
	Regeneration = {
		Id = "Regeneration",
		DisplayName = "Regeneration",
		Glyph = "💚",
		Color = rgb(110, 255, 140),
		Debuff = false,
		Kind = "HealOverTime",
		Magnitude = 0.06,
		DefaultDuration = 3,
		Stacking = "Refresh",
		MaxStacks = 1,
		Timing = "TurnStart",
	},
	HealingReduction = {
		Id = "HealingReduction",
		DisplayName = "Grievous Wounds",
		Glyph = "🩸",
		Color = rgb(200, 40, 60),
		Debuff = true,
		Kind = "HealingModifier",
		Magnitude = -0.5,
		DefaultDuration = 3,
		Stacking = "Refresh",
		MaxStacks = 1,
		Timing = "Passive",
	},
	Defending = {
		Id = "Defending",
		DisplayName = "Guarding",
		Glyph = "✋",
		Color = rgb(200, 200, 255),
		Debuff = false,
		Kind = "DamageTakenModifier",
		Magnitude = -0.5,
		DefaultDuration = 1,
		Stacking = "Refresh",
		MaxStacks = 1,
		Timing = "Passive",
	},
}

local Archetypes: { [string]: ArchetypeStats } = {
	Tank = {
		MaxHealth = 140,
		Attack = 14,
		Defense = 15,
		Speed = 8,
		CritChance = 0.05,
		CritDamage = 1.5,
		Accuracy = 0.95,
		Evasion = 0.02,
		StatusResist = 0.15,
	},
	Bruiser = {
		MaxHealth = 115,
		Attack = 18,
		Defense = 10,
		Speed = 10,
		CritChance = 0.08,
		CritDamage = 1.5,
		Accuracy = 0.95,
		Evasion = 0.03,
		StatusResist = 0.05,
	},
	Striker = {
		MaxHealth = 90,
		Attack = 22,
		Defense = 7,
		Speed = 13,
		CritChance = 0.15,
		CritDamage = 1.6,
		Accuracy = 0.97,
		Evasion = 0.04,
		StatusResist = 0,
	},
	Speedster = {
		MaxHealth = 80,
		Attack = 18,
		Defense = 6,
		Speed = 17,
		CritChance = 0.12,
		CritDamage = 1.5,
		Accuracy = 0.98,
		Evasion = 0.09,
		StatusResist = 0,
	},
	Support = {
		MaxHealth = 100,
		Attack = 15,
		Defense = 9,
		Speed = 11,
		CritChance = 0.06,
		CritDamage = 1.5,
		Accuracy = 0.95,
		Evasion = 0.04,
		StatusResist = 0.1,
	},
}

local CombatConfig = {
	Elements = Elements,
	ElementOrder = ElementOrder,
	Effectiveness = Effectiveness,
	StatusEffects = StatusEffects,
	Archetypes = Archetypes,

	TeamSize = 3,
	MaxEnemies = 3,
	MaxRounds = 40, -- battle is a loss for the player if it lasts longer (prevents stalemates)

	-- Damage formula constants (see docs/FORMULAS.md)
	DefenseWeight = 1, -- DefenseFactor = Atk / (Atk + Def * DefenseWeight)
	VarianceMin = 0.92,
	VarianceMax = 1.08,
	MinDamage = 1,
	MaxDamage = 1e15,
	MinHitChance = 0.05,
	MaxHitChance = 1,
	MaxCritChance = 0.75,
	MaxStatusResist = 0.8,
	MaxDamageReduction = 0.75,

	-- Energy / ultimate meter
	MaxEnergy = 100,
	EnergyOnDamaged = 8,
	DefendEnergyGain = 20,
	BasicEnergyGain = 30,
	SpecialEnergyGain = 15,

	-- Consumables usable in battle (ids from CraftingConfig.Consumables)
	MaxItemUsesPerBattle = 2,

	-- Power rating shown in UI and used for recommended-power comparisons.
	PowerWeights = {
		MaxHealth = 0.2,
		Attack = 2.2,
		Defense = 1.6,
		Speed = 0.8,
	},

	-- Turn timeout: if the player does not act, a basic attack is chosen for them.
	TurnTimeoutSeconds = 45,
	-- After the battle ends the server keeps the result this long for the UI.
	ResultLingerSeconds = 30,

	-- Monster leveling
	MaxMonsterLevel = 60,
	XpCurveBase = 40,
	XpCurveExponent = 1.6,
	StatGrowthPerLevel = 0.06, -- +6% combat stats per level above 1

	-- Arena (asynchronous PvP: fight an AI-controlled copy of another player's team)
	ArenaStartingRating = 1000,
	ArenaKFactor = 32,
	ArenaMinRating = 0,
	ArenaRewardCoinsSeconds = 90, -- reward = winner income/sec * this (bounded below)
	ArenaRewardGems = 3,
	ArenaCooldownSeconds = 20,
}

function CombatConfig.effectiveness(attacker: string, defender: string): number
	local row = Effectiveness[attacker]
	if not row then
		return 1
	end
	local value = row[defender]
	return if value then value else 1
end

return table.freeze(CombatConfig)
