-- All monsters, rarities and variants. Add a monster = add one row; RNG, Index and models pick it up.
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

local function m(id, name, rarity, element, shape) return { id = id, name = name, rarity = rarity, element = element, shape = shape } end
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
	m("null_0", "NULL-0", "Glitched", "Cosmic", "biped"),
	m("err0r_beast", "ERR0R Beast", "Glitched", "Cosmic", "beast"),
	m("missing_texture", "Missing Texture", "Glitched", "Cosmic", "blob"),
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
local total = 0
for _, r in Config.Rarities do if Config.Pools[r.id] then total += 1 / r.oneIn end end
for _, r in Config.Rarities do Config.Odds[r.id] = Config.Pools[r.id] and (1 / r.oneIn) / total or 0 end

-- luck >= 1 boosts Rare and above; tiers above maxTier are excluded; weights renormalize to sum 1
local function weights(luck: number?, maxTier: number?)
	luck = math.max(1, luck or 1)
	maxTier = math.max(1, maxTier or #Config.Rarities)
	local w, sum = {}, 0
	for _, rar in Config.Rarities do
		if Config.Pools[rar.id] and Config.Tier[rar.id] <= maxTier then
			w[rar.id] = (1 / rar.oneIn) * (Config.Tier[rar.id] >= 3 and luck or 1)
			sum += w[rar.id]
		end
	end
	return w, sum
end

function Config.oddsFor(luck: number?, maxTier: number?)
	local w, sum = weights(luck, maxTier)
	local out = {}
	for id, x in w do out[id] = x / sum end
	return out
end

-- server-only in practice; rng is injectable so tests can seed it
function Config.roll(rng: Random, luck: number?, maxTier: number?)
	local w, sum = weights(luck, maxTier)
	local r, pool = rng:NextNumber() * sum, nil
	for _, rar in Config.Rarities do
		if w[rar.id] then
			pool = Config.Pools[rar.id]
			r -= w[rar.id]
			if r <= 0 then break end
		end
	end
	local def = pool[rng:NextInteger(1, #pool)]
	local v, acc, variant = rng:NextNumber(), 0, "Normal"
	for k = #Config.Variants, 2, -1 do
		acc += 1 / Config.Variants[k].oneIn
		if v < acc then variant = Config.Variants[k].id break end
	end
	return def, variant
end

return Config
