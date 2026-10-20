-- All monsters, rarities and variants. Add a monster = add one row; RNG, Index and models pick it up.
local Weighted = require(script.Parent.Weighted)
local Luck = require(script.Parent.LuckConfig)
local Config = {}

local C = Color3.fromRGB
Config.Rarities = { -- oneIn = relative weight 1/oneIn; real odds are normalized into Config.Odds
	{ id = "Common", color = C(200, 200, 200), oneIn = 2 },
	{ id = "Uncommon", color = C(90, 220, 90), oneIn = 4 },
	{ id = "Rare", color = C(70, 150, 255), oneIn = 12 },
	{ id = "Epic", color = C(170, 80, 255), oneIn = 50 },
	{ id = "Legendary", color = C(255, 170, 40), oneIn = 250 },
	{ id = "Mythic", color = C(255, 60, 90), oneIn = 1000 },
	{ id = "Divine", color = C(255, 240, 150), oneIn = 5000 },
	{ id = "Celestial", color = C(120, 230, 255), oneIn = 25000 },
	{ id = "Transcendent", color = C(255, 120, 255), oneIn = 100000 },
	{ id = "Eternal", color = C(255, 255, 255), oneIn = 500000 },
	{ id = "Secret", color = C(120, 120, 135), oneIn = 2500000 },
	{ id = "Glitched", color = C(0, 255, 120), oneIn = 10000000 },
}

Config.Variants = { -- rolled independently of the monster
	{ id = "Normal", oneIn = 1, scale = 1, color = C(200, 200, 200) },
	{ id = "Huge", oneIn = 50, scale = 2, color = C(255, 200, 40) },
	{ id = "Monstrous", oneIn = 500, scale = 3, color = C(230, 30, 40) },
}

-- $/s per owned monster (placeholder balance)
Config.Income = {
	Common = 1, Uncommon = 3, Rare = 10, Epic = 40, Legendary = 150, Mythic = 1000, Divine = 5000,
	Celestial = 25000, Transcendent = 120000, Eternal = 600000, Secret = 3000000, Glitched = 15000000,
}
Config.VariantIncome = { Normal = 1, Huge = 10, Monstrous = 50 }

-- dice = optional list of die ids that can roll it (world-exclusive monsters)
local function m(id, name, rarity, element, shape, dice) return { id = id, name = name, rarity = rarity, element = element, shape = shape, dice = dice } end
Config.Monsters = {
	m("moss_goblin", "Moss Goblin", "Common", "Nature", "biped"),
	m("meadow_slime", "Meadow Slime", "Common", "Nature", "blob"),
	m("rockling", "Rockling", "Common", "Earth", "beast"),
	m("puddle_pup", "Puddle Pup", "Uncommon", "Water", "beast"),
	m("ember_imp", "Ember Imp", "Uncommon", "Fire", "biped"),
	m("spark_bug", "Spark Bug", "Uncommon", "Lightning", "blob"),
	m("thornback", "Thornback", "Rare", "Nature", "beast"),
	m("dune_crawler", "Dune Crawler", "Rare", "Earth", "beast"),
	m("gloom_bat", "Gloom Bat", "Rare", "Shadow", "blob"),
	m("frostfang", "Frostfang", "Epic", "Water", "beast"),
	m("magma_brute", "Magma Brute", "Epic", "Fire", "biped"),
	m("storm_drake", "Storm Drake", "Epic", "Lightning", "beast"),
	m("elder_treant", "Elder Treant", "Legendary", "Nature", "biped"),
	m("sandstorm_sphinx", "Sandstorm Sphinx", "Legendary", "Earth", "beast"),
	m("tidal_serpent", "Tidal Serpent", "Legendary", "Water", "beast"),
	m("solarius", "Solarius", "Mythic", "Light", "biped"),
	m("void_stalker", "Void Stalker", "Mythic", "Shadow", "beast"),
	m("inferno_titan", "Inferno Titan", "Mythic", "Fire", "biped"),
	m("seraph_guardian", "Seraph Guardian", "Divine", "Light", "biped"),
	m("aurora_whale", "Aurora Whale", "Divine", "Water", "blob"),
	m("thunder_god", "Thunder God", "Divine", "Lightning", "biped"),
	m("star_weaver", "Star Weaver", "Celestial", "Cosmic", "blob"),
	m("moon_howler", "Moon Howler", "Celestial", "Shadow", "beast"),
	m("comet_rider", "Comet Rider", "Celestial", "Cosmic", "biped"),
	m("astral_hydra", "Astral Hydra", "Transcendent", "Cosmic", "beast"),
	m("prism_phoenix", "Prism Phoenix", "Transcendent", "Light", "beast"),
	m("eclipse_lord", "Eclipse Lord", "Transcendent", "Shadow", "biped"),
	m("time_keeper", "Time Keeper", "Eternal", "Cosmic", "biped"),
	m("world_turtle", "World Turtle", "Eternal", "Earth", "beast"),
	m("first_flame", "First Flame", "Eternal", "Fire", "blob"),
	m("the_watcher", "The Watcher", "Secret", "Shadow", "blob"),
	m("mimic_king", "Mimic King", "Secret", "Shadow", "biped"),
	m("hollow_echo", "Hollow Echo", "Secret", "Cosmic", "beast"),
	m("null_0", "NULL-0", "Glitched", "Cosmic", "biped", { "glitch" }),
	m("err0r_beast", "ERR0R Beast", "Glitched", "Cosmic", "beast", { "glitch" }),
	m("missing_texture", "Missing Texture", "Glitched", "Cosmic", "blob", { "glitch" }),
}

-- combat role follows the element (BattleConfig.Roles holds what each role changes)
Config.RoleByElement = {
	Fire = "Attacker", Lightning = "Attacker", Earth = "Tank", Light = "Healer",
	Water = "Controller", Nature = "Support", Shadow = "Specialist", Cosmic = "Specialist",
}
Config.Lore = {
	moss_goblin = "Hides in hedges and steals shiny pebbles.", meadow_slime = "Bounces after anyone who smells of flowers.",
	rockling = "A pebble that refused to stay still.", puddle_pup = "Shakes off a small rainstorm when it's happy.",
	ember_imp = "Its giggle sounds like crackling kindling.", spark_bug = "Charges up by rubbing its wings on wool.",
	thornback = "Every thorn is a trophy from a fight it won.", dune_crawler = "Swims through sand like it's water.",
	gloom_bat = "Only flies on moonless nights.", frostfang = "Its bite freezes rivers solid.",
	magma_brute = "Leaves glowing footprints for days.", storm_drake = "Rides thunderheads across the sky.",
	elder_treant = "Older than the island itself.", sandstorm_sphinx = "Asks one riddle. Nobody has answered it.",
	tidal_serpent = "Its coils are the reason the tides turn.", solarius = "A sliver of the sun that came down to look around.",
	void_stalker = "You never see it. You only notice the missing stars.", inferno_titan = "Volcanoes are its footsteps.",
	seraph_guardian = "Keeps watch over every gate in the clouds.", aurora_whale = "Sings the northern lights into being.",
	thunder_god = "Every storm is it clearing its throat.", star_weaver = "Knits constellations out of loose light.",
	moon_howler = "The moon answers when it calls.", comet_rider = "Never in the same sky twice.",
	astral_hydra = "Each head dreams of a different galaxy.", prism_phoenix = "Reborn in a new color every time.",
	eclipse_lord = "Where it stands, noon becomes midnight.", time_keeper = "Winds the clock the universe runs on.",
	world_turtle = "Carries a sleeping continent on its shell.", first_flame = "The spark everything else was lit from.",
	the_watcher = "It has always been here. It is looking at you.", mimic_king = "Was that chest always there?",
	hollow_echo = "Repeats things nobody has said yet.", null_0 = "ERROR: description not found.",
	err0r_beast = "Crashes into reality at random intervals.", missing_texture = "The pink and black is not a pattern. It's a warning.",
}

Config.ById, Config.RarityById, Config.VariantById, Config.Tier, Config.Pools, Config.Odds = {}, {}, {}, {}, {}, {}
for i, r in Config.Rarities do Config.RarityById[r.id] = r Config.Tier[r.id] = i end
for _, v in Config.Variants do Config.VariantById[v.id] = v end
for _, d in Config.Monsters do
	assert(Config.RarityById[d.rarity], "unknown rarity " .. d.rarity)
	Config.ById[d.id] = d
	Config.Pools[d.rarity] = Config.Pools[d.rarity] or {}
	table.insert(Config.Pools[d.rarity], d)
end

local function eligible(def, maxTier: number, dieId: string?)
	if Config.Tier[def.rarity] > maxTier then return false end
	if def.dice and not table.find(def.dice, dieId) then return false end -- die-exclusive monsters
	return true
end

-- the roll pool: { { def, weight } } in roster order. Each rarity's weight (1/oneIn, reshaped by luck) is
-- split evenly across its eligible monsters, so a rarity's odds don't depend on how many monsters it has.
-- Ineligible monsters (above the die's tier cap, or exclusive to another die) never enter the pool.
function Config.pool(luck: number?, maxTier: number?, dieId: string?)
	luck = math.max(1, luck or 1)
	maxTier = math.max(1, maxTier or #Config.Rarities)
	local count = {}
	for _, def in Config.Monsters do
		if eligible(def, maxTier, dieId) then count[def.rarity] = (count[def.rarity] or 0) + 1 end
	end
	local out = {}
	for _, def in Config.Monsters do
		if eligible(def, maxTier, dieId) then
			local rar, tier = Config.RarityById[def.rarity], Config.Tier[def.rarity]
			table.insert(out, { def, (1 / rar.oneIn) * Luck.tierMult(luck, tier) / count[def.rarity] })
		end
	end
	return out
end

-- real odds per rarity for this luck/die, summing to 1 (what the UI shows)
function Config.oddsFor(luck: number?, maxTier: number?, dieId: string?)
	local pool = Config.pool(luck, maxTier, dieId)
	local p, out = Weighted.odds(pool), {}
	for i, e in pool do out[e[1].rarity] = (out[e[1].rarity] or 0) + p[i] end
	return out
end
Config.Odds = Config.oddsFor(1)

-- server-only in practice; rng is injectable so tests can seed it. nil when the pool is empty.
function Config.roll(rng: Random, luck: number?, maxTier: number?, dieId: string?)
	local def = Weighted.pick(Config.pool(luck, maxTier, dieId), rng)
	if not def then return nil end
	local v, acc, variant = rng:NextNumber(), 0, "Normal"
	for k = #Config.Variants, 2, -1 do
		acc += 1 / Config.Variants[k].oneIn
		if v < acc then variant = Config.Variants[k].id break end
	end
	return def, variant
end

return Config
