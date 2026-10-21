--!strict
-- Battle abilities. Every monster and enemy references abilities by Id.
-- Kinds:
--   Basic    - always available, no cooldown, grants energy
--   Special  - cooldown in the caster's turns, grants a little energy
--   Ultimate - requires a full energy meter (CombatConfig.MaxEnergy), consumes it
-- Target rules decide who the effects land on; the engine validates targets.

export type AbilityTarget =
	"SingleEnemy"
	| "AllEnemies"
	| "RandomEnemies"
	| "Self"
	| "SingleAlly"
	| "AllAllies"
	| "LowestAlly"

export type StatusApplication = {
	Status: string,
	Chance: number, -- 0..1, reduced by target StatusResist for debuffs
	Duration: number?, -- defaults to the status' DefaultDuration
	Recipient: ("Target" | "Self" | "AllAllies")?, -- defaults to "Target"
}

export type AbilityDef = {
	Id: string,
	Name: string,
	Description: string,
	Kind: "Basic" | "Special" | "Ultimate",
	Target: AbilityTarget,
	Element: string?, -- nil = caster's element
	Power: number, -- damage multiplier (0 = no damage)
	Hits: number?, -- for RandomEnemies / multi-hit
	Accuracy: number, -- multiplied with caster accuracy
	Cooldown: number,
	EnergyCost: number,
	CritBonus: number?,
	DefensePierce: number?, -- fraction of target defense ignored
	Lifesteal: number?, -- fraction of damage dealt returned as healing
	HealPower: number?, -- heal = HealPower * caster Attack
	ShieldPercent: number?, -- shield = ShieldPercent * caster MaxHealth
	Cleanse: boolean?, -- removes debuffs from targets
	VarianceMin: number?,
	VarianceMax: number?,
	Statuses: { StatusApplication }?,
	AnimationKey: string,
	SoundKey: string,
	EffectKey: string,
}

local A: { [string]: AbilityDef } = {}

local function add(def: AbilityDef)
	assert(A[def.Id] == nil, "duplicate ability " .. def.Id)
	A[def.Id] = def
end

-- Basic attacks ------------------------------------------------------------
add({
	Id = "strike",
	Name = "Strike",
	Description = "A reliable attack using the monster's own element.",
	Kind = "Basic",
	Target = "SingleEnemy",
	Power = 1,
	Accuracy = 1,
	Cooldown = 0,
	EnergyCost = 0,
	AnimationKey = "Attack",
	SoundKey = "HitBasic",
	EffectKey = "Slash",
})
add({
	Id = "quick_jab",
	Name = "Quick Jab",
	Description = "A fast, precise hit with a higher critical chance.",
	Kind = "Basic",
	Target = "SingleEnemy",
	Power = 0.85,
	Accuracy = 1.05,
	Cooldown = 0,
	EnergyCost = 0,
	CritBonus = 0.1,
	AnimationKey = "Attack",
	SoundKey = "HitBasic",
	EffectKey = "Slash",
})
add({
	Id = "heavy_slam",
	Name = "Heavy Slam",
	Description = "A slow but crushing blow.",
	Kind = "Basic",
	Target = "SingleEnemy",
	Power = 1.2,
	Accuracy = 0.9,
	Cooldown = 0,
	EnergyCost = 0,
	AnimationKey = "Attack",
	SoundKey = "HitHeavy",
	EffectKey = "Impact",
})

-- Nature ---------------------------------------------------------------------
add({
	Id = "vine_lash",
	Name = "Vine Lash",
	Description = "Whips a foe with thorned vines, slowing it.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Nature",
	Power = 1.4,
	Accuracy = 1,
	Cooldown = 2,
	EnergyCost = 0,
	Statuses = { { Status = "Slow", Chance = 0.6 } },
	AnimationKey = "Cast",
	SoundKey = "Nature",
	EffectKey = "Vines",
})
add({
	Id = "spore_cloud",
	Name = "Spore Cloud",
	Description = "Releases toxic spores that poison all enemies.",
	Kind = "Special",
	Target = "AllEnemies",
	Element = "Nature",
	Power = 0.55,
	Accuracy = 0.95,
	Cooldown = 3,
	EnergyCost = 0,
	Statuses = { { Status = "Poison", Chance = 0.7 } },
	AnimationKey = "Cast",
	SoundKey = "Nature",
	EffectKey = "Spores",
})
add({
	Id = "regrowth",
	Name = "Regrowth",
	Description = "Heals the weakest ally and grants Regeneration.",
	Kind = "Special",
	Target = "LowestAlly",
	Element = "Nature",
	Power = 0,
	Accuracy = 1,
	Cooldown = 3,
	EnergyCost = 0,
	HealPower = 2.2,
	Statuses = { { Status = "Regeneration", Chance = 1 } },
	AnimationKey = "Cast",
	SoundKey = "Heal",
	EffectKey = "Heal",
})
add({
	Id = "gaia_wrath",
	Name = "Gaia's Wrath",
	Description = "The earth itself erupts with roots, striking every enemy.",
	Kind = "Ultimate",
	Target = "AllEnemies",
	Element = "Nature",
	Power = 2.1,
	Accuracy = 1,
	Cooldown = 0,
	EnergyCost = 100,
	Statuses = { { Status = "Poison", Chance = 0.5 } },
	AnimationKey = "Ultimate",
	SoundKey = "Ultimate",
	EffectKey = "Roots",
})

-- Fire -----------------------------------------------------------------------
add({
	Id = "ember_bite",
	Name = "Ember Bite",
	Description = "A searing bite that may Burn.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Fire",
	Power = 1.35,
	Accuracy = 1,
	Cooldown = 2,
	EnergyCost = 0,
	Statuses = { { Status = "Burn", Chance = 0.5 } },
	AnimationKey = "Attack",
	SoundKey = "Fire",
	EffectKey = "Flame",
})
add({
	Id = "flame_wave",
	Name = "Flame Wave",
	Description = "A wave of fire washes over all enemies.",
	Kind = "Special",
	Target = "AllEnemies",
	Element = "Fire",
	Power = 0.8,
	Accuracy = 0.95,
	Cooldown = 3,
	EnergyCost = 0,
	Statuses = { { Status = "Burn", Chance = 0.3 } },
	AnimationKey = "Cast",
	SoundKey = "Fire",
	EffectKey = "FlameWave",
})
add({
	Id = "kindle",
	Name = "Kindle",
	Description = "Stokes inner fire: grants Attack Up to the whole team.",
	Kind = "Special",
	Target = "AllAllies",
	Element = "Fire",
	Power = 0,
	Accuracy = 1,
	Cooldown = 4,
	EnergyCost = 0,
	Statuses = { { Status = "AttackUp", Chance = 1 } },
	AnimationKey = "Cast",
	SoundKey = "Buff",
	EffectKey = "Buff",
})
add({
	Id = "inferno",
	Name = "Inferno",
	Description = "Engulfs a single enemy in a pillar of flame.",
	Kind = "Ultimate",
	Target = "SingleEnemy",
	Element = "Fire",
	Power = 3.2,
	Accuracy = 1,
	Cooldown = 0,
	EnergyCost = 100,
	Statuses = { { Status = "Burn", Chance = 1 } },
	AnimationKey = "Ultimate",
	SoundKey = "Ultimate",
	EffectKey = "Inferno",
})

-- Water ----------------------------------------------------------------------
add({
	Id = "tidal_slam",
	Name = "Tidal Slam",
	Description = "Crashes into a foe like a breaking wave.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Water",
	Power = 1.5,
	Accuracy = 1,
	Cooldown = 2,
	EnergyCost = 0,
	AnimationKey = "Attack",
	SoundKey = "Water",
	EffectKey = "Splash",
})
add({
	Id = "bubble_shield",
	Name = "Bubble Shield",
	Description = "Wraps the weakest ally in a protective bubble.",
	Kind = "Special",
	Target = "LowestAlly",
	Element = "Water",
	Power = 0,
	Accuracy = 1,
	Cooldown = 3,
	EnergyCost = 0,
	ShieldPercent = 0.25,
	AnimationKey = "Cast",
	SoundKey = "Shield",
	EffectKey = "Bubble",
})
add({
	Id = "frost_breath",
	Name = "Frost Breath",
	Description = "Icy breath that may Freeze the target solid.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Water",
	Power = 1.1,
	Accuracy = 0.95,
	Cooldown = 4,
	EnergyCost = 0,
	Statuses = { { Status = "Freeze", Chance = 0.35 } },
	AnimationKey = "Cast",
	SoundKey = "Ice",
	EffectKey = "Frost",
})
add({
	Id = "tsunami",
	Name = "Tsunami",
	Description = "A colossal wave hits all enemies and slows them.",
	Kind = "Ultimate",
	Target = "AllEnemies",
	Element = "Water",
	Power = 2,
	Accuracy = 1,
	Cooldown = 0,
	EnergyCost = 100,
	Statuses = { { Status = "Slow", Chance = 0.8 } },
	AnimationKey = "Ultimate",
	SoundKey = "Ultimate",
	EffectKey = "Tsunami",
})

-- Earth ----------------------------------------------------------------------
add({
	Id = "rock_smash",
	Name = "Rock Smash",
	Description = "A boulder-breaking blow that may Stun.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Earth",
	Power = 1.55,
	Accuracy = 0.92,
	Cooldown = 2,
	EnergyCost = 0,
	Statuses = { { Status = "Stun", Chance = 0.25 } },
	AnimationKey = "Attack",
	SoundKey = "HitHeavy",
	EffectKey = "Rocks",
})
add({
	Id = "stone_skin",
	Name = "Stone Skin",
	Description = "Hardens the body, gaining Defense Up and a shield.",
	Kind = "Special",
	Target = "Self",
	Element = "Earth",
	Power = 0,
	Accuracy = 1,
	Cooldown = 3,
	EnergyCost = 0,
	ShieldPercent = 0.15,
	Statuses = { { Status = "DefenseUp", Chance = 1 } },
	AnimationKey = "Cast",
	SoundKey = "Buff",
	EffectKey = "Stone",
})
add({
	Id = "fortify",
	Name = "Fortify",
	Description = "Rallies the team behind a wall of stone: team Defense Up.",
	Kind = "Special",
	Target = "AllAllies",
	Element = "Earth",
	Power = 0,
	Accuracy = 1,
	Cooldown = 4,
	EnergyCost = 0,
	Statuses = { { Status = "DefenseUp", Chance = 1 } },
	AnimationKey = "Cast",
	SoundKey = "Buff",
	EffectKey = "Buff",
})
add({
	Id = "earthquake",
	Name = "Earthquake",
	Description = "Shatters the ground under every enemy, lowering their Defense.",
	Kind = "Ultimate",
	Target = "AllEnemies",
	Element = "Earth",
	Power = 2,
	Accuracy = 1,
	Cooldown = 0,
	EnergyCost = 100,
	Statuses = { { Status = "DefenseDown", Chance = 0.8 } },
	AnimationKey = "Ultimate",
	SoundKey = "Ultimate",
	EffectKey = "Quake",
})

-- Wind -----------------------------------------------------------------------
add({
	Id = "gale_slash",
	Name = "Gale Slash",
	Description = "A razor wind with a high critical chance.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Wind",
	Power = 1.3,
	Accuracy = 1.05,
	Cooldown = 2,
	EnergyCost = 0,
	CritBonus = 0.25,
	AnimationKey = "Attack",
	SoundKey = "Wind",
	EffectKey = "WindSlash",
})
add({
	Id = "tailwind",
	Name = "Tailwind",
	Description = "A favorable wind grants the team Haste.",
	Kind = "Special",
	Target = "AllAllies",
	Element = "Wind",
	Power = 0,
	Accuracy = 1,
	Cooldown = 4,
	EnergyCost = 0,
	Statuses = { { Status = "SpeedUp", Chance = 1 } },
	AnimationKey = "Cast",
	SoundKey = "Buff",
	EffectKey = "Wind",
})
add({
	Id = "feather_storm",
	Name = "Feather Storm",
	Description = "Fires a flurry of feathers at random enemies.",
	Kind = "Special",
	Target = "RandomEnemies",
	Element = "Wind",
	Power = 0.55,
	Hits = 4,
	Accuracy = 0.95,
	Cooldown = 3,
	EnergyCost = 0,
	AnimationKey = "Cast",
	SoundKey = "Wind",
	EffectKey = "Feathers",
})
add({
	Id = "cyclone",
	Name = "Cyclone",
	Description = "A roaring cyclone batters all enemies and may Stun them.",
	Kind = "Ultimate",
	Target = "AllEnemies",
	Element = "Wind",
	Power = 1.9,
	Accuracy = 1,
	Cooldown = 0,
	EnergyCost = 100,
	Statuses = { { Status = "Stun", Chance = 0.25 } },
	AnimationKey = "Ultimate",
	SoundKey = "Ultimate",
	EffectKey = "Cyclone",
})

-- Light ----------------------------------------------------------------------
add({
	Id = "radiant_beam",
	Name = "Radiant Beam",
	Description = "A focused beam of holy light.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Light",
	Power = 1.5,
	Accuracy = 1.05,
	Cooldown = 2,
	EnergyCost = 0,
	AnimationKey = "Cast",
	SoundKey = "Light",
	EffectKey = "Beam",
})
add({
	Id = "blessing",
	Name = "Blessing",
	Description = "Heals every ally and removes their debuffs.",
	Kind = "Special",
	Target = "AllAllies",
	Element = "Light",
	Power = 0,
	Accuracy = 1,
	Cooldown = 4,
	EnergyCost = 0,
	HealPower = 1.1,
	Cleanse = true,
	AnimationKey = "Cast",
	SoundKey = "Heal",
	EffectKey = "Heal",
})
add({
	Id = "judgment",
	Name = "Judgment",
	Description = "Calls down a column of light on one enemy, piercing defense.",
	Kind = "Ultimate",
	Target = "SingleEnemy",
	Element = "Light",
	Power = 3,
	Accuracy = 1,
	Cooldown = 0,
	EnergyCost = 100,
	DefensePierce = 0.4,
	AnimationKey = "Ultimate",
	SoundKey = "Ultimate",
	EffectKey = "Judgment",
})

-- Dark -----------------------------------------------------------------------
add({
	Id = "shadow_claw",
	Name = "Shadow Claw",
	Description = "Rends a foe from the shadows, lowering its Attack.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Dark",
	Power = 1.4,
	Accuracy = 1,
	Cooldown = 2,
	EnergyCost = 0,
	Statuses = { { Status = "AttackDown", Chance = 0.5 } },
	AnimationKey = "Attack",
	SoundKey = "Dark",
	EffectKey = "Shadow",
})
add({
	Id = "curse",
	Name = "Curse",
	Description = "Lowers a foe's Defense and inflicts Grievous Wounds.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Dark",
	Power = 0.6,
	Accuracy = 1,
	Cooldown = 3,
	EnergyCost = 0,
	Statuses = { { Status = "DefenseDown", Chance = 0.9 }, { Status = "HealingReduction", Chance = 0.9 } },
	AnimationKey = "Cast",
	SoundKey = "Dark",
	EffectKey = "Curse",
})
add({
	Id = "soul_drain",
	Name = "Soul Drain",
	Description = "Drains life from a foe, healing the caster.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Dark",
	Power = 1.2,
	Accuracy = 1,
	Cooldown = 3,
	EnergyCost = 0,
	Lifesteal = 0.5,
	AnimationKey = "Cast",
	SoundKey = "Dark",
	EffectKey = "Drain",
})
add({
	Id = "void_eclipse",
	Name = "Void Eclipse",
	Description = "Darkness swallows all enemies; the caster drinks their life.",
	Kind = "Ultimate",
	Target = "AllEnemies",
	Element = "Dark",
	Power = 2.2,
	Accuracy = 1,
	Cooldown = 0,
	EnergyCost = 100,
	Lifesteal = 0.2,
	AnimationKey = "Ultimate",
	SoundKey = "Ultimate",
	EffectKey = "Eclipse",
})

-- Cosmic ---------------------------------------------------------------------
add({
	Id = "star_shard",
	Name = "Star Shard",
	Description = "Hurls a shard of a dying star that ignores some defense.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Cosmic",
	Power = 1.5,
	Accuracy = 1,
	Cooldown = 2,
	EnergyCost = 0,
	DefensePierce = 0.3,
	AnimationKey = "Cast",
	SoundKey = "Cosmic",
	EffectKey = "Star",
})
add({
	Id = "gravity_well",
	Name = "Gravity Well",
	Description = "Crushes all enemies, slowing them and lowering Defense.",
	Kind = "Special",
	Target = "AllEnemies",
	Element = "Cosmic",
	Power = 0.7,
	Accuracy = 0.95,
	Cooldown = 4,
	EnergyCost = 0,
	Statuses = { { Status = "Slow", Chance = 0.6 }, { Status = "DefenseDown", Chance = 0.4 } },
	AnimationKey = "Cast",
	SoundKey = "Cosmic",
	EffectKey = "Gravity",
})
add({
	Id = "supernova",
	Name = "Supernova",
	Description = "Explodes with the light of a thousand suns.",
	Kind = "Ultimate",
	Target = "AllEnemies",
	Element = "Cosmic",
	Power = 2.6,
	Accuracy = 1,
	Cooldown = 0,
	EnergyCost = 100,
	AnimationKey = "Ultimate",
	SoundKey = "Ultimate",
	EffectKey = "Supernova",
})

-- Glitch ---------------------------------------------------------------------
add({
	Id = "bit_crush",
	Name = "Bit Crush",
	Description = "Corrupted data hits for wildly unpredictable damage.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Glitch",
	Power = 1.5,
	Accuracy = 1,
	Cooldown = 2,
	EnergyCost = 0,
	VarianceMin = 0.4,
	VarianceMax = 2.4,
	AnimationKey = "Attack",
	SoundKey = "Glitch",
	EffectKey = "Glitch",
})
add({
	Id = "corrupt",
	Name = "Corrupt",
	Description = "Injects malware: Poison and Attack Down.",
	Kind = "Special",
	Target = "SingleEnemy",
	Element = "Glitch",
	Power = 0.8,
	Accuracy = 1,
	Cooldown = 3,
	EnergyCost = 0,
	Statuses = { { Status = "Poison", Chance = 0.8 }, { Status = "AttackDown", Chance = 0.6 } },
	AnimationKey = "Cast",
	SoundKey = "Glitch",
	EffectKey = "Glitch",
})
add({
	Id = "system_crash",
	Name = "System Crash",
	Description = "Crashes reality for every enemy, possibly Stunning them.",
	Kind = "Ultimate",
	Target = "AllEnemies",
	Element = "Glitch",
	Power = 2.4,
	Accuracy = 1,
	Cooldown = 0,
	EnergyCost = 100,
	Statuses = { { Status = "Stun", Chance = 0.3 } },
	AnimationKey = "Ultimate",
	SoundKey = "Ultimate",
	EffectKey = "Crash",
})

-- Shared support abilities -----------------------------------------------------
add({
	Id = "rally",
	Name = "Rally Cry",
	Description = "A battle cry that grants the team Attack Up.",
	Kind = "Special",
	Target = "AllAllies",
	Power = 0,
	Accuracy = 1,
	Cooldown = 4,
	EnergyCost = 0,
	Statuses = { { Status = "AttackUp", Chance = 1 } },
	AnimationKey = "Cast",
	SoundKey = "Buff",
	EffectKey = "Buff",
})
add({
	Id = "mend",
	Name = "Mend",
	Description = "Heals the weakest ally.",
	Kind = "Special",
	Target = "LowestAlly",
	Power = 0,
	Accuracy = 1,
	Cooldown = 2,
	EnergyCost = 0,
	HealPower = 2.6,
	AnimationKey = "Cast",
	SoundKey = "Heal",
	EffectKey = "Heal",
})

-- Boss-only abilities ---------------------------------------------------------
add({
	Id = "boss_cataclysm",
	Name = "Cataclysm",
	Description = "A telegraphed devastating blow against the whole team.",
	Kind = "Ultimate",
	Target = "AllEnemies",
	Power = 2.4,
	Accuracy = 1,
	Cooldown = 0,
	EnergyCost = 100,
	AnimationKey = "Ultimate",
	SoundKey = "BossUltimate",
	EffectKey = "Cataclysm",
})
add({
	Id = "boss_enrage",
	Name = "Enrage",
	Description = "The boss works itself into a frenzy.",
	Kind = "Special",
	Target = "Self",
	Power = 0,
	Accuracy = 1,
	Cooldown = 5,
	EnergyCost = 0,
	Statuses = {
		{ Status = "AttackUp", Chance = 1, Duration = 4 },
		{ Status = "SpeedUp", Chance = 1, Duration = 4 },
	},
	AnimationKey = "Cast",
	SoundKey = "Roar",
	EffectKey = "Enrage",
})

local AbilityConfig = {
	Abilities = A,
}

function AbilityConfig.get(id: string): AbilityDef?
	return A[id]
end

return table.freeze(AbilityConfig)
