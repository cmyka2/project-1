--!strict
-- Monster definitions. MonsterId is the stable key used everywhere (saves,
-- quests, recipes, models). Display names and ModelKeys can change freely.
--
-- Default stats/income are derived from the region scale and an archetype so
-- the table stays readable; any monster can override BaseStats or
-- BaseIncomePerSecond explicitly via the `opts` column.

local RegionConfig = require(script.Parent.RegionConfig)
local CombatConfig = require(script.Parent.CombatConfig)

export type BaseStats = CombatConfig.ArchetypeStats

export type EvolutionRequirements = {
	Level: number,
	Coins: number,
	Materials: { [string]: number },
	Duplicates: number, -- extra copies of the same MonsterId consumed
}

export type MonsterDef = {
	MonsterId: string,
	DisplayName: string,
	Rarity: string,
	Region: string,
	Element: string,
	Archetype: string,
	ModelKey: string,
	IconKey: string,
	AnimationKeys: { Idle: string, Attack: string, Cast: string, Hit: string, Ultimate: string },
	BaseIncomePerSecond: number,
	BaseStats: BaseStats,
	RollWeight: number, -- relative weight among monsters of the same rarity in a dice pool
	Abilities: { string }, -- [1] basic, then specials, last = ultimate
	CanPlaceInBase: boolean,
	EvolvesTo: string?,
	EvolutionRequirements: EvolutionRequirements?,
	EvolutionOnly: boolean, -- obtainable only by evolving
	FusionOnly: boolean, -- obtainable only via a special fusion recipe
	EventId: string?, -- obtainable only from that event's dice
	Description: string,
}

type Opts = {
	IncomeFactor: number?,
	StatFactor: number?,
	RollWeight: number?,
	BaseIncomePerSecond: number?,
	BaseStats: BaseStats?,
	EvolvesTo: string?,
	Evolution: EvolutionRequirements?,
	EvolutionOnly: boolean?,
	FusionOnly: boolean?,
	EventId: string?,
	Description: string?,
	ModelKey: string?,
}

local ARCHETYPE_INCOME: { [string]: number } = {
	Tank = 0.9,
	Bruiser = 1,
	Striker = 1,
	Speedster = 1.05,
	Support = 1.15,
}

local Monsters: { [string]: MonsterDef } = {}
local Order: { string } = {}

local function pascal(id: string): string
	local parts = string.split(id, "_")
	for i, part in parts do
		parts[i] = string.upper(string.sub(part, 1, 1)) .. string.sub(part, 2)
	end
	return table.concat(parts)
end

local function scaledStats(archetype: string, regionId: string, factor: number): BaseStats
	local base = CombatConfig.Archetypes[archetype]
	assert(base, "unknown archetype " .. archetype)
	local region = RegionConfig.Regions[regionId]
	assert(region, "unknown region " .. regionId)
	local s = region.StatScale * factor
	return {
		MaxHealth = math.floor(base.MaxHealth * s + 0.5),
		Attack = math.floor(base.Attack * s + 0.5),
		Defense = math.floor(base.Defense * s + 0.5),
		Speed = math.floor(base.Speed * (1 + (region.Index - 1) * 0.04) * factor + 0.5),
		CritChance = base.CritChance,
		CritDamage = base.CritDamage,
		Accuracy = base.Accuracy,
		Evasion = base.Evasion,
		StatusResist = base.StatusResist,
	}
end

local function M(
	id: string,
	name: string,
	rarity: string,
	region: string,
	element: string,
	archetype: string,
	abilities: { string },
	opts: Opts?
)
	assert(Monsters[id] == nil, "duplicate monster " .. id)
	local o: Opts = opts or {}
	local regionDef = RegionConfig.Regions[region]
	assert(regionDef, "unknown region " .. region)
	local modelKey = o.ModelKey or pascal(id)
	local income = o.BaseIncomePerSecond
		or regionDef.IncomeScale * (ARCHETYPE_INCOME[archetype] or 1) * (o.IncomeFactor or 1)
	Monsters[id] = {
		MonsterId = id,
		DisplayName = name,
		Rarity = rarity,
		Region = region,
		Element = element,
		Archetype = archetype,
		ModelKey = modelKey,
		IconKey = modelKey,
		AnimationKeys = {
			Idle = modelKey .. "_Idle",
			Attack = modelKey .. "_Attack",
			Cast = modelKey .. "_Cast",
			Hit = modelKey .. "_Hit",
			Ultimate = modelKey .. "_Ultimate",
		},
		BaseIncomePerSecond = income,
		BaseStats = o.BaseStats or scaledStats(archetype, region, o.StatFactor or 1),
		RollWeight = o.RollWeight or 1,
		Abilities = abilities,
		CanPlaceInBase = true,
		EvolvesTo = o.EvolvesTo,
		EvolutionRequirements = o.Evolution,
		EvolutionOnly = o.EvolutionOnly == true,
		FusionOnly = o.FusionOnly == true,
		EventId = o.EventId,
		Description = o.Description or "",
	}
	table.insert(Order, id)
end

-- Grassland ------------------------------------------------------------------
M(
	"sprout_bunny",
	"Sprout Bunny",
	"Common",
	"Grassland",
	"Nature",
	"Speedster",
	{ "quick_jab", "vine_lash", "gaia_wrath" },
	{
		EvolvesTo = "bloom_hare",
		Evolution = { Level = 10, Coins = 1500, Materials = { grassland_essence = 6 }, Duplicates = 0 },
		Description = "Hops through meadows nibbling on clover sprouts.",
	}
)
M(
	"pebble_pup",
	"Pebble Pup",
	"Common",
	"Grassland",
	"Earth",
	"Tank",
	{ "heavy_slam", "stone_skin", "earthquake" },
	{
		Description = "Its fur is made of tiny smooth stones.",
	}
)
M(
	"puddle_slime",
	"Puddle Slime",
	"Uncommon",
	"Grassland",
	"Water",
	"Support",
	{ "strike", "bubble_shield", "tsunami" },
	{
		Description = "Wobbles happily after every rainstorm.",
	}
)
M(
	"breeze_finch",
	"Breeze Finch",
	"Uncommon",
	"Grassland",
	"Wind",
	"Speedster",
	{ "quick_jab", "gale_slash", "cyclone" },
	{
		Description = "Rides warm breezes from flower to flower.",
	}
)
M(
	"meadow_ram",
	"Meadow Ram",
	"Rare",
	"Grassland",
	"Earth",
	"Bruiser",
	{ "heavy_slam", "rock_smash", "earthquake" },
	{
		Description = "Headbutts boulders for fun.",
	}
)
M(
	"sunpetal_fox",
	"Sunpetal Fox",
	"Epic",
	"Grassland",
	"Light",
	"Striker",
	{ "quick_jab", "radiant_beam", "judgment" },
	{
		Description = "Its tails glow like sunflowers at dawn.",
	}
)
M(
	"clover_king",
	"Clover King",
	"Legendary",
	"Grassland",
	"Nature",
	"Support",
	{ "strike", "regrowth", "rally", "gaia_wrath" },
	{
		Description = "A regal beast said to bring luck to whoever finds it.",
	}
)
M(
	"bloom_hare",
	"Bloom Hare",
	"Uncommon",
	"Grassland",
	"Nature",
	"Speedster",
	{ "quick_jab", "vine_lash", "regrowth", "gaia_wrath" },
	{
		EvolutionOnly = true,
		StatFactor = 1.1,
		IncomeFactor = 1.2,
		Description = "The evolved Sprout Bunny, crowned with blossoms.",
	}
)

-- Forest ---------------------------------------------------------------------
M(
	"acorn_imp",
	"Acorn Imp",
	"Common",
	"Forest",
	"Nature",
	"Striker",
	{ "quick_jab", "vine_lash", "gaia_wrath" },
	{
		Description = "A mischievous imp that pelts travelers with acorns.",
	}
)
M("glow_moth", "Glow Moth", "Uncommon", "Forest", "Light", "Support", { "strike", "mend", "judgment" }, {
	Description = "Lights the forest floor at night.",
})
M(
	"thornback_boar",
	"Thornback Boar",
	"Uncommon",
	"Forest",
	"Earth",
	"Bruiser",
	{ "heavy_slam", "rock_smash", "earthquake" },
	{
		Description = "Charges anything that moves, thorns first.",
	}
)
M(
	"moss_golem",
	"Moss Golem",
	"Rare",
	"Forest",
	"Nature",
	"Tank",
	{ "heavy_slam", "stone_skin", "regrowth", "gaia_wrath" },
	{
		EvolvesTo = "ancient_moss_colossus",
		Evolution = {
			Level = 15,
			Coins = 40000,
			Materials = { forest_essence = 12, grassland_essence = 10 },
			Duplicates = 1,
		},
		Description = "A gentle giant overgrown with centuries of moss.",
	}
)
M(
	"spore_shaman",
	"Spore Shaman",
	"Epic",
	"Forest",
	"Nature",
	"Support",
	{ "strike", "spore_cloud", "regrowth", "gaia_wrath" },
	{
		Description = "Brews medicine and poison from the same mushrooms.",
	}
)
M(
	"elder_treant",
	"Elder Treant",
	"Legendary",
	"Forest",
	"Nature",
	"Tank",
	{ "heavy_slam", "fortify", "regrowth", "gaia_wrath" },
	{
		Description = "The oldest tree in the forest. It remembers everything.",
	}
)
M(
	"verdant_wyrm",
	"Verdant Wyrm",
	"Mythic",
	"Forest",
	"Nature",
	"Striker",
	{ "quick_jab", "vine_lash", "spore_cloud", "gaia_wrath" },
	{
		Description = "A serpent of living vines coiled around the world tree.",
	}
)
M(
	"ancient_moss_colossus",
	"Ancient Moss Colossus",
	"Epic",
	"Forest",
	"Nature",
	"Tank",
	{ "heavy_slam", "stone_skin", "fortify", "gaia_wrath" },
	{
		EvolutionOnly = true,
		StatFactor = 1.15,
		IncomeFactor = 1.25,
		Description = "Moss Golem after a thousand years of patience.",
	}
)

-- Desert ---------------------------------------------------------------------
M(
	"sand_skink",
	"Sand Skink",
	"Common",
	"Desert",
	"Earth",
	"Speedster",
	{ "quick_jab", "rock_smash", "earthquake" },
	{
		Description = "Swims through sand as easily as water.",
	}
)
M(
	"dune_scorpion",
	"Dune Scorpion",
	"Uncommon",
	"Desert",
	"Earth",
	"Striker",
	{ "quick_jab", "rock_smash", "curse", "earthquake" },
	{
		EvolvesTo = "emperor_scorpion",
		Evolution = { Level = 15, Coins = 250000, Materials = { desert_shard = 15 }, Duplicates = 1 },
		Description = "Its tail glints like polished bronze.",
	}
)
M(
	"cactus_brute",
	"Cactus Brute",
	"Rare",
	"Desert",
	"Nature",
	"Bruiser",
	{ "heavy_slam", "vine_lash", "gaia_wrath" },
	{
		Description = "Hugs are not recommended.",
	}
)
M(
	"mirage_jackal",
	"Mirage Jackal",
	"Epic",
	"Desert",
	"Wind",
	"Speedster",
	{ "quick_jab", "gale_slash", "tailwind", "cyclone" },
	{
		Description = "Is it really there? Nobody is quite sure.",
	}
)
M(
	"sunscale_basilisk",
	"Sunscale Basilisk",
	"Legendary",
	"Desert",
	"Fire",
	"Striker",
	{ "quick_jab", "ember_bite", "flame_wave", "inferno" },
	{
		Description = "Basks in the midday sun until its scales ignite.",
	}
)
M(
	"pharaoh_sphinx",
	"Pharaoh Sphinx",
	"Mythic",
	"Desert",
	"Light",
	"Tank",
	{ "heavy_slam", "radiant_beam", "blessing", "judgment" },
	{
		Description = "Guardian of the buried pyramids. Answers riddles with lasers.",
	}
)
M(
	"emperor_scorpion",
	"Emperor Scorpion",
	"Rare",
	"Desert",
	"Earth",
	"Striker",
	{ "quick_jab", "rock_smash", "curse", "earthquake" },
	{
		EvolutionOnly = true,
		StatFactor = 1.15,
		IncomeFactor = 1.25,
		Description = "Rules the dunes with a golden stinger.",
	}
)

-- Mountain -------------------------------------------------------------------
M(
	"frost_marmot",
	"Frost Marmot",
	"Uncommon",
	"Mountain",
	"Water",
	"Speedster",
	{ "quick_jab", "frost_breath", "tsunami" },
	{
		Description = "Whistles to warn the mountain of intruders.",
	}
)
M(
	"crag_goat",
	"Crag Goat",
	"Uncommon",
	"Mountain",
	"Earth",
	"Bruiser",
	{ "heavy_slam", "rock_smash", "earthquake" },
	{
		Description = "Climbs sheer cliffs without breaking a sweat.",
	}
)
M(
	"yeti_cub",
	"Yeti Cub",
	"Rare",
	"Mountain",
	"Water",
	"Tank",
	{ "heavy_slam", "frost_breath", "bubble_shield", "tsunami" },
	{
		EvolvesTo = "yeti_monarch",
		Evolution = {
			Level = 20,
			Coins = 2000000,
			Materials = { mountain_ore = 20, desert_shard = 10 },
			Duplicates = 1,
		},
		Description = "Fluffy, adorable, and stronger than a bulldozer.",
	}
)
M(
	"storm_eagle",
	"Storm Eagle",
	"Epic",
	"Mountain",
	"Wind",
	"Striker",
	{ "quick_jab", "gale_slash", "feather_storm", "cyclone" },
	{
		Description = "Its wings crackle with static before a storm.",
	}
)
M(
	"glacier_titan",
	"Glacier Titan",
	"Legendary",
	"Mountain",
	"Water",
	"Tank",
	{ "heavy_slam", "frost_breath", "fortify", "tsunami" },
	{
		Description = "A walking glacier that carves valleys as it moves.",
	}
)
M(
	"thunder_roc",
	"Thunder Roc",
	"Mythic",
	"Mountain",
	"Wind",
	"Speedster",
	{ "quick_jab", "gale_slash", "tailwind", "cyclone" },
	{
		Description = "Its cry is the thunder you hear in the peaks.",
	}
)
M(
	"avalanche_colossus",
	"Avalanche Colossus",
	"Divine",
	"Mountain",
	"Earth",
	"Tank",
	{ "heavy_slam", "rock_smash", "fortify", "earthquake" },
	{
		Description = "When it wakes, whole mountainsides follow.",
	}
)
M(
	"yeti_monarch",
	"Yeti Monarch",
	"Epic",
	"Mountain",
	"Water",
	"Tank",
	{ "heavy_slam", "frost_breath", "fortify", "tsunami" },
	{
		EvolutionOnly = true,
		StatFactor = 1.15,
		IncomeFactor = 1.25,
		Description = "The undisputed ruler of the frozen peaks.",
	}
)

-- Volcano --------------------------------------------------------------------
M(
	"magma_slug",
	"Magma Slug",
	"Rare",
	"Volcano",
	"Fire",
	"Tank",
	{ "heavy_slam", "ember_bite", "stone_skin", "inferno" },
	{
		EvolvesTo = "magma_leviathan",
		Evolution = {
			Level = 20,
			Coins = 15000000,
			Materials = { volcanic_core = 20, mountain_ore = 12 },
			Duplicates = 1,
		},
		Description = "Leaves a trail of cooling obsidian wherever it goes.",
	}
)
M(
	"cinder_hound",
	"Cinder Hound",
	"Rare",
	"Volcano",
	"Fire",
	"Speedster",
	{ "quick_jab", "ember_bite", "inferno" },
	{
		Description = "Fetches lava rocks. Please do not throw them back.",
	}
)
M(
	"obsidian_golem",
	"Obsidian Golem",
	"Epic",
	"Volcano",
	"Earth",
	"Tank",
	{ "heavy_slam", "stone_skin", "fortify", "earthquake" },
	{
		Description = "Volcanic glass forged into an unbreakable guardian.",
	}
)
M(
	"lava_drake",
	"Lava Drake",
	"Legendary",
	"Volcano",
	"Fire",
	"Striker",
	{ "quick_jab", "ember_bite", "flame_wave", "inferno" },
	{
		Description = "A young dragon that bathes in molten rock.",
	}
)
M(
	"phoenix_hatchling",
	"Phoenix Hatchling",
	"Mythic",
	"Volcano",
	"Fire",
	"Support",
	{ "strike", "kindle", "mend", "inferno" },
	{
		EvolvesTo = "eternal_phoenix",
		Evolution = {
			Level = 30,
			Coins = 120000000,
			Materials = { volcanic_core = 40, heavenly_dust = 10 },
			Duplicates = 2,
		},
		Description = "Reborn from its own ashes every hundred years.",
	}
)
M(
	"inferno_behemoth",
	"Inferno Behemoth",
	"Divine",
	"Volcano",
	"Fire",
	"Bruiser",
	{ "heavy_slam", "flame_wave", "kindle", "inferno" },
	{
		Description = "The heart of the volcano given a body.",
	}
)
M(
	"magma_leviathan",
	"Magma Leviathan",
	"Epic",
	"Volcano",
	"Fire",
	"Tank",
	{ "heavy_slam", "flame_wave", "stone_skin", "inferno" },
	{
		EvolutionOnly = true,
		StatFactor = 1.15,
		IncomeFactor = 1.25,
		Description = "Swims through rivers of lava like a whale through the sea.",
	}
)
M(
	"eternal_phoenix",
	"Eternal Phoenix",
	"Divine",
	"Volcano",
	"Fire",
	"Support",
	{ "strike", "kindle", "blessing", "inferno" },
	{
		EvolutionOnly = true,
		StatFactor = 1.15,
		IncomeFactor = 1.25,
		Description = "A phoenix that has stopped dying altogether.",
	}
)

-- Cave -----------------------------------------------------------------------
M(
	"crystal_bat",
	"Crystal Bat",
	"Rare",
	"Cave",
	"Dark",
	"Speedster",
	{ "quick_jab", "soul_drain", "void_eclipse" },
	{
		EvolvesTo = "crystal_vampire",
		Evolution = {
			Level = 25,
			Coins = 90000000,
			Materials = { cave_crystal = 25, volcanic_core = 12 },
			Duplicates = 1,
		},
		Description = "Echolocates with chimes of crystal.",
	}
)
M("geode_crab", "Geode Crab", "Rare", "Cave", "Earth", "Tank", { "heavy_slam", "stone_skin", "earthquake" }, {
	Description = "Its shell hides a sparkling amethyst interior.",
})
M(
	"gloom_spider",
	"Gloom Spider",
	"Epic",
	"Cave",
	"Dark",
	"Striker",
	{ "quick_jab", "shadow_claw", "curse", "void_eclipse" },
	{
		Description = "Weaves webs from threads of pure shadow.",
	}
)
M(
	"amethyst_serpent",
	"Amethyst Serpent",
	"Legendary",
	"Cave",
	"Earth",
	"Support",
	{ "strike", "fortify", "mend", "earthquake" },
	{
		Description = "Gemstones grow along its spine like scales.",
	}
)
M(
	"shadow_lurker",
	"Shadow Lurker",
	"Mythic",
	"Cave",
	"Dark",
	"Striker",
	{ "quick_jab", "shadow_claw", "soul_drain", "void_eclipse" },
	{
		Description = "You only see its eyes. Then nothing at all.",
	}
)
M(
	"prism_dragon",
	"Prism Dragon",
	"Divine",
	"Cave",
	"Light",
	"Bruiser",
	{ "heavy_slam", "radiant_beam", "rally", "judgment" },
	{
		Description = "Splits light into blinding rainbows.",
	}
)
M(
	"void_crystal_wyrm",
	"Void Crystal Wyrm",
	"Celestial",
	"Cave",
	"Dark",
	"Striker",
	{ "quick_jab", "shadow_claw", "curse", "void_eclipse" },
	{
		Description = "A crystal so dark it swallows light.",
	}
)
M(
	"crystal_vampire",
	"Crystal Vampire",
	"Epic",
	"Cave",
	"Dark",
	"Speedster",
	{ "quick_jab", "soul_drain", "shadow_claw", "void_eclipse" },
	{
		EvolutionOnly = true,
		StatFactor = 1.15,
		IncomeFactor = 1.25,
		Description = "Drinks starlight reflected in cave crystals.",
	}
)

-- Heaven ---------------------------------------------------------------------
M(
	"cloud_lamb",
	"Cloud Lamb",
	"Epic",
	"Heaven",
	"Light",
	"Support",
	{ "strike", "mend", "blessing", "judgment" },
	{
		Description = "Literally made of cloud. Extremely huggable.",
	}
)
M(
	"halo_sprite",
	"Halo Sprite",
	"Epic",
	"Heaven",
	"Light",
	"Speedster",
	{ "quick_jab", "radiant_beam", "judgment" },
	{
		Description = "Darts between the clouds trailing golden light.",
	}
)
M(
	"seraph_lion",
	"Seraph Lion",
	"Legendary",
	"Heaven",
	"Light",
	"Bruiser",
	{ "heavy_slam", "radiant_beam", "rally", "judgment" },
	{
		Description = "Six wings, one mighty roar.",
	}
)
M(
	"aurora_pegasus",
	"Aurora Pegasus",
	"Mythic",
	"Heaven",
	"Wind",
	"Speedster",
	{ "quick_jab", "gale_slash", "tailwind", "cyclone" },
	{
		Description = "Gallops across the aurora at dawn.",
	}
)
M(
	"archangel_guardian",
	"Archangel Guardian",
	"Divine",
	"Heaven",
	"Light",
	"Tank",
	{ "heavy_slam", "fortify", "blessing", "judgment" },
	{
		Description = "Sworn protector of the heavenly gates.",
	}
)
M(
	"celestial_kirin",
	"Celestial Kirin",
	"Celestial",
	"Heaven",
	"Light",
	"Striker",
	{ "quick_jab", "radiant_beam", "blessing", "judgment" },
	{
		Description = "Appears only to the truly worthy.",
	}
)

-- Cosmic ---------------------------------------------------------------------
M(
	"comet_pup",
	"Comet Pup",
	"Epic",
	"Cosmic",
	"Cosmic",
	"Speedster",
	{ "quick_jab", "star_shard", "supernova" },
	{
		EvolvesTo = "meteor_wolf",
		Evolution = {
			Level = 30,
			Coins = 3000000000,
			Materials = { cosmic_fragment = 30, heavenly_dust = 20 },
			Duplicates = 1,
		},
		Description = "Chases its own glowing tail through the stars.",
	}
)
M(
	"nebula_jelly",
	"Nebula Jelly",
	"Legendary",
	"Cosmic",
	"Cosmic",
	"Support",
	{ "strike", "gravity_well", "mend", "supernova" },
	{
		Description = "Drifts through space painting nebulae as it goes.",
	}
)
M(
	"star_golem",
	"Star Golem",
	"Mythic",
	"Cosmic",
	"Cosmic",
	"Tank",
	{ "heavy_slam", "star_shard", "fortify", "supernova" },
	{
		Description = "Built from the core of a collapsed star.",
	}
)
M(
	"void_leviathan",
	"Void Leviathan",
	"Divine",
	"Cosmic",
	"Dark",
	"Bruiser",
	{ "heavy_slam", "soul_drain", "curse", "void_eclipse" },
	{
		Description = "Swallows asteroids whole.",
	}
)
M(
	"galaxy_serpent",
	"Galaxy Serpent",
	"Celestial",
	"Cosmic",
	"Cosmic",
	"Striker",
	{ "quick_jab", "star_shard", "gravity_well", "supernova" },
	{
		Description = "Its body contains an entire spiral galaxy.",
	}
)
M(
	"supernova_titan",
	"Supernova Titan",
	"Cosmic",
	"Cosmic",
	"Cosmic",
	"Tank",
	{ "heavy_slam", "gravity_well", "fortify", "supernova" },
	{
		Description = "A titan forever on the brink of exploding.",
	}
)
M(
	"meteor_wolf",
	"Meteor Wolf",
	"Legendary",
	"Cosmic",
	"Cosmic",
	"Speedster",
	{ "quick_jab", "star_shard", "tailwind", "supernova" },
	{
		EvolutionOnly = true,
		StatFactor = 1.15,
		IncomeFactor = 1.25,
		Description = "Leaves craters wherever it lands.",
	}
)

-- Glitch ---------------------------------------------------------------------
M(
	"pixel_slime",
	"Pixel Slime",
	"Legendary",
	"Glitch",
	"Glitch",
	"Support",
	{ "strike", "corrupt", "mend", "system_crash" },
	{
		Description = "Rendered in glorious 8-bit.",
	}
)
M(
	"error_hound",
	"Error Hound",
	"Mythic",
	"Glitch",
	"Glitch",
	"Speedster",
	{ "quick_jab", "bit_crush", "system_crash" },
	{
		Description = "Barks in error codes.",
	}
)
M(
	"null_knight",
	"Null Knight",
	"Divine",
	"Glitch",
	"Glitch",
	"Tank",
	{ "heavy_slam", "corrupt", "fortify", "system_crash" },
	{
		Description = "Its armor references an object that does not exist.",
	}
)
M(
	"corrupted_seraph",
	"Corrupted Seraph",
	"Celestial",
	"Glitch",
	"Glitch",
	"Striker",
	{ "quick_jab", "bit_crush", "curse", "system_crash" },
	{
		Description = "An angel whose code was overwritten.",
	}
)
M(
	"syntax_dragon",
	"Syntax Dragon",
	"Cosmic",
	"Glitch",
	"Glitch",
	"Bruiser",
	{ "heavy_slam", "bit_crush", "corrupt", "system_crash" },
	{
		Description = "Breathes unterminated strings.",
	}
)
M(
	"overlord_404",
	"404 Overlord",
	"Glitched",
	"Glitch",
	"Glitch",
	"Striker",
	{ "quick_jab", "bit_crush", "corrupt", "system_crash" },
	{
		ModelKey = "Overlord404",
		Description = "Monster not found. Yet here it is.",
	}
)

-- Fusion-only ----------------------------------------------------------------
M(
	"chimera_of_seasons",
	"Chimera of Seasons",
	"Mythic",
	"Forest",
	"Nature",
	"Bruiser",
	{ "heavy_slam", "vine_lash", "flame_wave", "gaia_wrath" },
	{
		FusionOnly = true,
		StatFactor = 1.25,
		IncomeFactor = 1.3,
		Description = "Fused from the kings of meadow and forest.",
	}
)
M(
	"tempest_hydra",
	"Tempest Hydra",
	"Divine",
	"Mountain",
	"Water",
	"Striker",
	{ "quick_jab", "tidal_slam", "feather_storm", "tsunami" },
	{
		FusionOnly = true,
		StatFactor = 1.25,
		IncomeFactor = 1.3,
		Description = "Three heads, three storms.",
	}
)
M(
	"eclipse_dragon",
	"Eclipse Dragon",
	"Celestial",
	"Cave",
	"Dark",
	"Bruiser",
	{ "heavy_slam", "shadow_claw", "radiant_beam", "void_eclipse" },
	{
		FusionOnly = true,
		StatFactor = 1.25,
		IncomeFactor = 1.3,
		Description = "Born where light and shadow overlap.",
	}
)

-- Event: Glitchy Halloween ---------------------------------------------------
M(
	"pumpkin_imp",
	"Pumpkin Imp",
	"Rare",
	"Forest",
	"Fire",
	"Striker",
	{ "quick_jab", "ember_bite", "inferno" },
	{
		EventId = "halloween_2026",
		Description = "Carved itself. Lit itself. Very proud of both.",
	}
)
M(
	"wraith_cat",
	"Wraith Cat",
	"Legendary",
	"Forest",
	"Dark",
	"Speedster",
	{ "quick_jab", "shadow_claw", "void_eclipse" },
	{
		EventId = "halloween_2026",
		Description = "Nine lives, all of them spooky.",
	}
)
M(
	"lantern_king",
	"Hollow Lantern King",
	"Mythic",
	"Forest",
	"Dark",
	"Support",
	{ "strike", "curse", "mend", "void_eclipse" },
	{
		EventId = "halloween_2026",
		Description = "Guides lost souls home with its eternal flame.",
	}
)

local MonsterConfig = {
	Monsters = Monsters,
	Order = Order, -- codex display order
}

function MonsterConfig.get(id: string): MonsterDef?
	return Monsters[id]
end

-- Monsters a dice pool may contain: belongs to the region and is not
-- evolution-only, fusion-only, or event-only.
function MonsterConfig.isRollable(def: MonsterDef): boolean
	return not def.EvolutionOnly and not def.FusionOnly and def.EventId == nil
end

return table.freeze(MonsterConfig)
