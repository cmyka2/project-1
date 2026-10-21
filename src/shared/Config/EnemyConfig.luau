--!strict
-- Enemies and battle encounters. Enemy stats = archetype * region StatScale *
-- PowerFactor * level growth (HealthFactor scales max health only).
-- Encounters list their enemies with levels and their rewards.

local RegionConfig = require(script.Parent.RegionConfig)

export type BossPhase = {
	HealthBelow: number, -- fraction of max health that triggers the phase (once)
	Message: string,
	Statuses: { string }, -- applied to the boss
	ShieldPercent: number?, -- shield = this * boss max health
	Summon: string?, -- EnemyId summoned into a free enemy slot
	UnlockAbility: string?,
}

export type EnemyDef = {
	Id: string,
	DisplayName: string,
	Region: string,
	Element: string,
	Archetype: string,
	ModelKey: string,
	Abilities: { string },
	PowerFactor: number,
	HealthFactor: number,
	IsBoss: boolean,
	AiProfile: "Random" | "Balanced" | "Smart",
	TelegraphUltimate: boolean,
	Phases: { BossPhase },
}

export type Drop = {
	Kind: "Material" | "Chest" | "Consumable" | "Equipment",
	Id: string,
	Chance: number,
	Min: number,
	Max: number,
}

export type EncounterDef = {
	Id: string,
	Region: string,
	DisplayName: string,
	Order: number,
	IsBoss: boolean,
	Enemies: { { Enemy: string, Level: number } },
	RewardCoins: number,
	RewardGems: number,
	RewardXp: number,
	FirstClearGems: number,
	Drops: { Drop },
	CooldownSeconds: number,
}

local Enemies: { [string]: EnemyDef } = {}
local Encounters: { [string]: EncounterDef } = {}
local EncounterOrder: { string } = {}

local function pascal(id: string): string
	local parts = string.split(id, "_")
	for i, part in parts do
		parts[i] = string.upper(string.sub(part, 1, 1)) .. string.sub(part, 2)
	end
	return table.concat(parts)
end

type EnemyOpts = {
	HealthFactor: number?,
	IsBoss: boolean?,
	AiProfile: ("Random" | "Balanced" | "Smart")?,
	Phases: { BossPhase }?,
}

local function E(
	id: string,
	name: string,
	region: string,
	element: string,
	archetype: string,
	abilities: { string },
	powerFactor: number,
	opts: EnemyOpts?
)
	assert(Enemies[id] == nil, "duplicate enemy " .. id)
	local o: EnemyOpts = opts or {}
	Enemies[id] = {
		Id = id,
		DisplayName = name,
		Region = region,
		Element = element,
		Archetype = archetype,
		ModelKey = pascal(id),
		Abilities = abilities,
		PowerFactor = powerFactor,
		HealthFactor = o.HealthFactor or 1,
		IsBoss = o.IsBoss == true,
		AiProfile = o.AiProfile or "Balanced",
		TelegraphUltimate = o.IsBoss == true,
		Phases = o.Phases or {},
	}
end

local function bossPhases(minion: string): { BossPhase }
	return {
		{
			HealthBelow = 0.6,
			Message = "%s roars and calls for help!",
			Statuses = { "AttackUp" },
			Summon = minion,
		},
		{
			HealthBelow = 0.3,
			Message = "%s is enraged! Its hide hardens!",
			Statuses = { "AttackUp", "DefenseUp" },
			ShieldPercent = 0.15,
			UnlockAbility = "boss_cataclysm",
		},
	}
end

-- Region rosters: three regulars and a boss each --------------------------------
type Roster = {
	Region: string,
	Regulars: { { id: string, name: string, element: string, archetype: string, abilities: { string } } },
	Boss: { id: string, name: string, element: string, archetype: string, abilities: { string } },
}

local Rosters: { Roster } = {
	{
		Region = "Grassland",
		Regulars = {
			{
				id = "wild_hopper",
				name = "Wild Hopper",
				element = "Nature",
				archetype = "Speedster",
				abilities = { "quick_jab", "vine_lash" },
			},
			{
				id = "mud_toad",
				name = "Mud Toad",
				element = "Water",
				archetype = "Tank",
				abilities = { "heavy_slam", "bubble_shield" },
			},
			{
				id = "thistle_wasp",
				name = "Thistle Wasp",
				element = "Wind",
				archetype = "Striker",
				abilities = { "quick_jab", "gale_slash" },
			},
		},
		Boss = {
			id = "bramble_king_boar",
			name = "Bramble King Boar",
			element = "Earth",
			archetype = "Bruiser",
			abilities = { "heavy_slam", "rock_smash", "boss_enrage", "earthquake" },
		},
	},
	{
		Region = "Forest",
		Regulars = {
			{
				id = "rotwood_stump",
				name = "Rotwood Stump",
				element = "Nature",
				archetype = "Tank",
				abilities = { "heavy_slam", "stone_skin" },
			},
			{
				id = "venom_shroom",
				name = "Venom Shroom",
				element = "Nature",
				archetype = "Support",
				abilities = { "strike", "spore_cloud", "mend" },
			},
			{
				id = "night_owl",
				name = "Night Owl",
				element = "Dark",
				archetype = "Speedster",
				abilities = { "quick_jab", "shadow_claw" },
			},
		},
		Boss = {
			id = "hollow_treant",
			name = "Hollow Treant",
			element = "Nature",
			archetype = "Tank",
			abilities = { "heavy_slam", "spore_cloud", "regrowth", "gaia_wrath" },
		},
	},
	{
		Region = "Desert",
		Regulars = {
			{
				id = "sand_raider",
				name = "Sand Raider",
				element = "Earth",
				archetype = "Striker",
				abilities = { "quick_jab", "rock_smash" },
			},
			{
				id = "dust_devil",
				name = "Dust Devil",
				element = "Wind",
				archetype = "Speedster",
				abilities = { "quick_jab", "feather_storm" },
			},
			{
				id = "scarab_swarm",
				name = "Scarab Swarm",
				element = "Earth",
				archetype = "Bruiser",
				abilities = { "heavy_slam", "curse" },
			},
		},
		Boss = {
			id = "sand_wyrm_queen",
			name = "Sand Wyrm Queen",
			element = "Earth",
			archetype = "Bruiser",
			abilities = { "heavy_slam", "rock_smash", "boss_enrage", "earthquake" },
		},
	},
	{
		Region = "Mountain",
		Regulars = {
			{
				id = "ice_imp",
				name = "Ice Imp",
				element = "Water",
				archetype = "Speedster",
				abilities = { "quick_jab", "frost_breath" },
			},
			{
				id = "rock_troll",
				name = "Rock Troll",
				element = "Earth",
				archetype = "Tank",
				abilities = { "heavy_slam", "stone_skin", "rock_smash" },
			},
			{
				id = "harpy",
				name = "Harpy",
				element = "Wind",
				archetype = "Striker",
				abilities = { "quick_jab", "gale_slash" },
			},
		},
		Boss = {
			id = "frost_giant_jarl",
			name = "Frost Giant Jarl",
			element = "Water",
			archetype = "Tank",
			abilities = { "heavy_slam", "frost_breath", "fortify", "tsunami" },
		},
	},
	{
		Region = "Volcano",
		Regulars = {
			{
				id = "ash_sprite",
				name = "Ash Sprite",
				element = "Fire",
				archetype = "Speedster",
				abilities = { "quick_jab", "ember_bite" },
			},
			{
				id = "lava_golem",
				name = "Lava Golem",
				element = "Fire",
				archetype = "Tank",
				abilities = { "heavy_slam", "stone_skin", "flame_wave" },
			},
			{
				id = "fire_salamander",
				name = "Fire Salamander",
				element = "Fire",
				archetype = "Striker",
				abilities = { "quick_jab", "ember_bite", "kindle" },
			},
		},
		Boss = {
			id = "magma_tyrant",
			name = "Magma Tyrant",
			element = "Fire",
			archetype = "Bruiser",
			abilities = { "heavy_slam", "flame_wave", "boss_enrage", "inferno" },
		},
	},
	{
		Region = "Cave",
		Regulars = {
			{
				id = "cave_ghoul",
				name = "Cave Ghoul",
				element = "Dark",
				archetype = "Bruiser",
				abilities = { "heavy_slam", "soul_drain" },
			},
			{
				id = "crystal_mite",
				name = "Crystal Mite",
				element = "Earth",
				archetype = "Speedster",
				abilities = { "quick_jab", "rock_smash" },
			},
			{
				id = "echo_wraith",
				name = "Echo Wraith",
				element = "Dark",
				archetype = "Striker",
				abilities = { "quick_jab", "curse", "shadow_claw" },
			},
		},
		Boss = {
			id = "gemheart_hydra",
			name = "Gemheart Hydra",
			element = "Dark",
			archetype = "Tank",
			abilities = { "heavy_slam", "curse", "soul_drain", "void_eclipse" },
		},
	},
	{
		Region = "Heaven",
		Regulars = {
			{
				id = "fallen_cherub",
				name = "Fallen Cherub",
				element = "Light",
				archetype = "Speedster",
				abilities = { "quick_jab", "radiant_beam" },
			},
			{
				id = "storm_valkyrie",
				name = "Storm Valkyrie",
				element = "Wind",
				archetype = "Striker",
				abilities = { "quick_jab", "gale_slash", "tailwind" },
			},
			{
				id = "halo_sentinel",
				name = "Halo Sentinel",
				element = "Light",
				archetype = "Tank",
				abilities = { "heavy_slam", "blessing" },
			},
		},
		Boss = {
			id = "seraphim_judge",
			name = "Seraphim Judge",
			element = "Light",
			archetype = "Bruiser",
			abilities = { "heavy_slam", "radiant_beam", "blessing", "judgment" },
		},
	},
	{
		Region = "Cosmic",
		Regulars = {
			{
				id = "star_wisp",
				name = "Star Wisp",
				element = "Cosmic",
				archetype = "Speedster",
				abilities = { "quick_jab", "star_shard" },
			},
			{
				id = "meteor_brute",
				name = "Meteor Brute",
				element = "Cosmic",
				archetype = "Bruiser",
				abilities = { "heavy_slam", "gravity_well" },
			},
			{
				id = "void_drifter",
				name = "Void Drifter",
				element = "Dark",
				archetype = "Support",
				abilities = { "strike", "curse", "mend" },
			},
		},
		Boss = {
			id = "black_hole_devourer",
			name = "Black Hole Devourer",
			element = "Cosmic",
			archetype = "Tank",
			abilities = { "heavy_slam", "gravity_well", "boss_enrage", "supernova" },
		},
	},
	{
		Region = "Glitch",
		Regulars = {
			{
				id = "lag_spike",
				name = "Lag Spike",
				element = "Glitch",
				archetype = "Speedster",
				abilities = { "quick_jab", "bit_crush" },
			},
			{
				id = "corrupted_sprite",
				name = "Corrupted Sprite",
				element = "Glitch",
				archetype = "Striker",
				abilities = { "quick_jab", "corrupt" },
			},
			{
				id = "firewall_golem",
				name = "Firewall Golem",
				element = "Glitch",
				archetype = "Tank",
				abilities = { "heavy_slam", "fortify", "corrupt" },
			},
		},
		Boss = {
			id = "kernel_panic",
			name = "The Kernel Panic",
			element = "Glitch",
			archetype = "Bruiser",
			abilities = { "heavy_slam", "bit_crush", "boss_enrage", "system_crash" },
		},
	},
}

-- Reward tuning (per region, scaled by RegionConfig.IncomeScale)
local REWARD_COIN_SECONDS = { 150, 220, 320 } -- normal encounters 1..3
local BOSS_COIN_SECONDS = 1400
local NORMAL_LEVELS = { { 1, 2 }, { 3, 4, 3 }, { 5, 6, 6 } }
local BOSS_LEVEL = 8

local encounterIndex = 0
for _, roster in Rosters do
	local region = RegionConfig.Regions[roster.Region]
	assert(region, "roster region missing " .. roster.Region)
	for _, r in roster.Regulars do
		E(r.id, r.name, roster.Region, r.element, r.archetype, r.abilities, 1.05)
	end
	local firstRegular = roster.Regulars[1].id
	E(
		roster.Boss.id,
		roster.Boss.name,
		roster.Region,
		roster.Boss.element,
		roster.Boss.archetype,
		roster.Boss.abilities,
		1.25,
		{
			HealthFactor = 3.2,
			IsBoss = true,
			AiProfile = "Smart",
			Phases = bossPhases(firstRegular),
		}
	)

	local xpBase = math.floor(25 * region.Index ^ 1.35)
	local materialId = region.MaterialId
	local names = { "Skirmish", "Ambush", "Elite Pack" }
	for n = 1, 3 do
		encounterIndex += 1
		local enemies = {}
		for slot, level in NORMAL_LEVELS[n] do
			local regular = roster.Regulars[((slot + n - 2) % #roster.Regulars) + 1]
			table.insert(enemies, { Enemy = regular.id, Level = level })
		end
		local id = string.lower(roster.Region) .. "_" .. n
		Encounters[id] = {
			Id = id,
			Region = roster.Region,
			DisplayName = region.DisplayName .. " " .. names[n],
			Order = encounterIndex,
			IsBoss = false,
			Enemies = enemies,
			RewardCoins = math.floor(region.IncomeScale * REWARD_COIN_SECONDS[n]),
			RewardGems = if n == 3 then 1 else 0,
			RewardXp = xpBase * n,
			FirstClearGems = 3 + n,
			Drops = {
				{ Kind = "Material", Id = materialId, Chance = 0.55 + 0.15 * n, Min = 1, Max = n + 1 },
				{ Kind = "Chest", Id = "region_chest", Chance = 0.04 * n, Min = 1, Max = 1 },
				{ Kind = "Consumable", Id = "battle_tonic", Chance = 0.08, Min = 1, Max = 1 },
			},
			CooldownSeconds = 0,
		}
		table.insert(EncounterOrder, id)
	end

	encounterIndex += 1
	local bossId = string.lower(roster.Region) .. "_boss"
	assert(bossId == region.BossEncounterId, "boss encounter id mismatch for " .. roster.Region)
	Encounters[bossId] = {
		Id = bossId,
		Region = roster.Region,
		DisplayName = roster.Boss.name,
		Order = encounterIndex,
		IsBoss = true,
		Enemies = {
			{ Enemy = roster.Regulars[2].id, Level = BOSS_LEVEL - 2 },
			{ Enemy = roster.Boss.id, Level = BOSS_LEVEL },
		},
		RewardCoins = math.floor(region.IncomeScale * BOSS_COIN_SECONDS),
		RewardGems = 8 + region.Index * 2,
		RewardXp = xpBase * 6,
		FirstClearGems = 25 + region.Index * 5,
		Drops = {
			{ Kind = "Material", Id = materialId, Chance = 1, Min = 3, Max = 6 },
			{ Kind = "Chest", Id = "boss_chest", Chance = 1, Min = 1, Max = 1 },
			{ Kind = "Consumable", Id = "battle_tonic", Chance = 0.3, Min = 1, Max = 2 },
		},
		CooldownSeconds = 60,
	}
	table.insert(EncounterOrder, bossId)
end

local EnemyConfig = {
	Enemies = Enemies,
	Encounters = Encounters,
	EncounterOrder = EncounterOrder,
	-- AI tuning: chance that a "Balanced" AI picks its best-scored action
	-- instead of a random valid one ("Smart" always does, "Random" never).
	BalancedOptimalChance = 0.7,
	AiHealThreshold = 0.4, -- heal allies below this health fraction
}

function EnemyConfig.encountersForRegion(regionId: string): { EncounterDef }
	local list = {}
	for _, id in EncounterOrder do
		local enc = Encounters[id]
		if enc.Region == regionId then
			table.insert(list, enc)
		end
	end
	return list
end

return table.freeze(EnemyConfig)
