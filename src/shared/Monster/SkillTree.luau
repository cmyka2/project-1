-- Evolution Tree (bought with cash) and Ascension Tree (bought with Ascension Points from rebirths).
-- Six branches radiate from Start along the six hex directions (flat-top axial q/r); cross-branch nodes sit in
-- the wedges between the branches they combine. Owned = { [nodeId] = rank }.
-- effects = { effect = value per rank }; Tree.stat sums them and is the only place bonuses are read from,
-- so each node applies exactly once per rank.
local Tree = {}

Tree.Branches = {
	{ id = "luck", name = "Luck", icon = "🍀", dir = { 0, -1 }, color = Color3.fromRGB(80, 210, 90) },
	{ id = "economy", name = "Economy", icon = "💵", dir = { 1, -1 }, color = Color3.fromRGB(240, 200, 60) },
	{ id = "utility", name = "Utility", icon = "🎒", dir = { 1, 0 }, color = Color3.fromRGB(80, 180, 240) },
	{ id = "defense", name = "Health & Defense", icon = "❤️", dir = { 0, 1 }, color = Color3.fromRGB(240, 90, 110) },
	{ id = "damage", name = "Damage", icon = "🗡️", dir = { -1, 1 }, color = Color3.fromRGB(240, 120, 50) },
	{ id = "mobility", name = "Mobility", icon = "👟", dir = { -1, 0 }, color = Color3.fromRGB(180, 110, 240) },
	{ id = "cross", name = "Cross-branch", icon = "✨", color = Color3.fromRGB(255, 255, 255) },
}
Tree.BranchById = {}
for _, b in Tree.Branches do Tree.BranchById[b.id] = b end

-- what each effect does (value is per rank); every one is read by a live system
Tree.Effects = {
	income = { fmt = "+%d%% income", pct = true }, luck = { fmt = "+%d%% luck", pct = true },
	double = { fmt = "%d%% chance of a bonus roll", pct = true }, discovery = { fmt = "new discoveries pay %ds of income" },
	rollspeed = { fmt = "-%d%% roll cooldown", pct = true }, walkspeed = { fmt = "+%d walk speed" },
	dash = { fmt = "+%d stud dash (Q / dash button)" }, dashcd = { fmt = "-%d%% dash cooldown", pct = true },
	jump = { fmt = "+%d jump power" }, autoroll = { fmt = "auto-roll while standing at the Summon station" },
	travel = { fmt = "fast travel to shops and your base" },
	upgradecost = { fmt = "-%d%% monster upgrade cost", pct = true }, offline = { fmt = "+%dh offline earnings cap" },
	fusecost = { fmt = "-%d%% fusion cost", pct = true }, chestcost = { fmt = "-%d%% chest price", pct = true },
	sell = { fmt = "+%d%% sell value", pct = true }, storage = { fmt = "+%d backpack space" },
	fusecopies = { fmt = "fusion needs %d fewer copies" }, presets = { fmt = "+%d battle team preset" },
	chestluck = { fmt = "+%d%% chest luck", pct = true }, relic = { fmt = "unlocks the relic gear slot" },
	research = { fmt = "+%d%% battle materials", pct = true },
	damage = { fmt = "+%d%% monster damage", pct = true }, crit = { fmt = "+%d%% critical chance", pct = true },
	elemental = { fmt = "+%d%% strong-element damage", pct = true }, energy = { fmt = "+%d%% energy gain", pct = true },
	boss = { fmt = "+%d%% damage to bosses", pct = true }, skillamp = { fmt = "+%d%% skill damage", pct = true },
	ultamp = { fmt = "+%d%% ultimate damage", pct = true },
	health = { fmt = "+%d%% monster HP", pct = true }, defense = { fmt = "+%d%% defense", pct = true },
	regen = { fmt = "heal %d%% HP each turn", pct = true }, laststand = { fmt = "once per battle, survive a lethal hit" },
	protect = { fmt = "-%d%% damage taken", pct = true }, resist = { fmt = "-%d%% damage from strong elements", pct = true },
	guard = { fmt = "Defend blocks %d%% more", pct = true }, startcash = { fmt = "start each rebirth with $%d" },
}

-- n(id, name, branch, k = step from Start, cost of rank 1, max rank, effects, requires?, rebirth?)
local function n(id, name, branch, k, cost, max, effects, requires, rebirth)
	return { id = id, name = name, branch = branch, k = k, cost = cost, max = max, effects = effects, requires = requires, rebirth = rebirth }
end
local ARMS = {
	luck = {
		n("lucky_charm", "Lucky Charm", "luck", 1, 250, 5, { luck = 0.05 }),
		n("rare_hunter", "Rare Hunter", "luck", 2, 5000, 5, { luck = 0.08 }),
		n("legendary_focus", "Legendary Focus", "luck", 3, 100e3, 5, { luck = 0.12 }),
		n("mythic_resonance", "Mythic Resonance", "luck", 4, 5e6, 3, { luck = 0.2 }),
		n("double_fortune", "Double Fortune", "luck", 5, 100e6, 5, { double = 0.05 }),
		n("discovery_streak", "Discovery Streak", "luck", 6, 2e9, 3, { discovery = 60 }),
		n("cosmic_fortune", "Cosmic Fortune", "luck", 7, 100e9, 3, { luck = 0.5 }, nil, 3),
	},
	economy = {
		n("coin_collector", "Coin Collector", "economy", 1, 100, 5, { income = 0.1 }),
		n("efficient_training", "Efficient Training", "economy", 2, 3000, 5, { upgradecost = 0.05 }),
		n("golden_pedestals", "Golden Pedestals", "economy", 3, 75e3, 5, { income = 0.2 }),
		n("idle_earnings", "Idle Earnings", "economy", 4, 2e6, 4, { offline = 1 }),
		n("fusion_efficiency", "Fusion Efficiency", "economy", 5, 50e6, 5, { fusecost = 0.1 }),
		n("treasure_research", "Treasure Research", "economy", 6, 1e9, 5, { chestcost = 0.05 }),
		n("empire_builder", "Empire Builder", "economy", 7, 50e9, 5, { income = 0.5 }, nil, 3),
	},
	utility = {
		n("bigger_backpack", "Bigger Backpack", "utility", 1, 300, 4, { storage = 25 }),
		n("faster_rolling", "Faster Rolling", "utility", 2, 10e3, 5, { rollspeed = 0.08 }),
		n("quick_fusion", "Quick Fusion", "utility", 3, 500e3, 1, { fusecopies = 1 }),
		n("extra_team_preset", "Extra Team Preset", "utility", 4, 5e6, 2, { presets = 1 }),
		n("better_chest_finder", "Better Chest Finder", "utility", 5, 200e6, 5, { chestluck = 0.15 }),
		n("equipment_slots", "Equipment Slots", "utility", 6, 5e9, 1, { relic = 1 }),
		n("research_lab", "Research Lab", "utility", 7, 100e9, 4, { research = 0.25, sell = 0.1 }),
	},
	defense = {
		n("thick_hide", "Thick Hide", "defense", 1, 400, 5, { health = 0.1 }),
		n("iron_guard", "Iron Guard", "defense", 2, 8000, 5, { defense = 0.1 }),
		n("regeneration", "Regeneration", "defense", 3, 200e3, 3, { regen = 0.02 }),
		n("last_stand", "Last Stand", "defense", 4, 10e6, 1, { laststand = 1 }),
		n("team_protection", "Team Protection", "defense", 5, 300e6, 4, { protect = 0.05 }),
		n("elemental_resistance", "Elemental Resistance", "defense", 6, 8e9, 3, { resist = 0.1 }),
		n("guardians_resolve", "Guardian's Resolve", "defense", 7, 200e9, 3, { guard = 0.1, health = 0.2 }),
	},
	damage = {
		n("sharpened_claws", "Sharpened Claws", "damage", 1, 400, 5, { damage = 0.1 }),
		n("critical_strike", "Critical Strike", "damage", 2, 8000, 5, { crit = 0.03 }),
		n("elemental_mastery", "Elemental Mastery", "damage", 3, 200e3, 4, { elemental = 0.05 }),
		n("combo_master", "Combo Master", "damage", 4, 10e6, 5, { energy = 0.1 }),
		n("boss_hunter", "Boss Hunter", "damage", 5, 300e6, 5, { boss = 0.1 }),
		n("skill_amplification", "Skill Amplification", "damage", 6, 8e9, 5, { skillamp = 0.1 }),
		n("ultimate_awakening", "Ultimate Awakening", "damage", 7, 200e9, 3, { ultamp = 0.15 }),
	},
	mobility = {
		n("quick_feet", "Quick Feet", "mobility", 1, 200, 5, { walkspeed = 2 }),
		n("longer_dash", "Longer Dash", "mobility", 2, 5000, 4, { dash = 6 }),
		n("reduced_cooldown", "Reduced Cooldown", "mobility", 3, 100e3, 5, { dashcd = 0.1 }),
		n("jump_boost", "Jump Boost", "mobility", 4, 2e6, 4, { jump = 8 }),
		n("auto_pickup", "Auto Pickup", "mobility", 5, 50e6, 1, { autoroll = 1 }),
		n("portal_mastery", "Portal Mastery", "mobility", 6, 1e9, 1, { travel = 1 }),
		n("phantom_sprint", "Phantom Sprint", "mobility", 7, 50e9, 3, { walkspeed = 6 }, nil, 3),
	},
}
-- cross nodes: pos = axial position in the wedge between their branches
local function x(id, name, pos, cost, max, effects, requires, rebirth)
	local node = n(id, name, "cross", 0, cost, max, effects, requires, rebirth)
	node.q, node.r = pos[1], pos[2]
	return node
end
local CROSS = {
	x("fortune_engine", "Fortune Engine", { 2, -4 }, 1e9, 3, { luck = 0.15, income = 0.25 }, { "legendary_focus", "golden_pedestals" }),
	x("master_collector", "Master Collector", { 4, -2 }, 1e9, 3, { storage = 50, sell = 0.25 }, { "golden_pedestals", "quick_fusion" }),
	x("war_beast", "War Beast", { -2, 4 }, 1e9, 3, { damage = 0.2, health = 0.2 }, { "elemental_mastery", "regeneration" }),
	x("explorers_instinct", "Explorer's Instinct", { -2, -2 }, 500e6, 3, { luck = 0.1, walkspeed = 3 }, { "legendary_focus", "reduced_cooldown" }),
	x("divine_ascension", "Divine Ascension", { 3, 3 }, 10e12, 1, { income = 1, luck = 0.25, damage = 0.5, health = 0.5 },
		{ "double_fortune", "fusion_efficiency", "better_chest_finder", "team_protection", "boss_hunter", "auto_pickup" }, 6),
}

Tree.Nodes = { { id = "start", name = "Start", branch = "cross", q = 0, r = 0, cost = 0, max = 1, effects = {} } }
for _, b in Tree.Branches do
	for i, node in ARMS[b.id] or {} do
		node.q, node.r = b.dir[1] * node.k, b.dir[2] * node.k
		node.requires = node.requires or { i == 1 and "start" or ARMS[b.id][i - 1].id }
		table.insert(Tree.Nodes, node)
	end
end
for _, node in CROSS do table.insert(Tree.Nodes, node) end
Tree.ById = {}
for _, node in Tree.Nodes do
	node.icon = node.icon or Tree.BranchById[node.branch].icon
	node.growth = node.growth or 3
	Tree.ById[node.id] = node
end

-- Ascension Tree: permanent upgrades paid with Ascension Points; rank r+1 costs cost x (r + 1) AP
Tree.Ascension = {
	{ id = "eternal_wealth", name = "Eternal Wealth", icon = "👑", cost = 1, max = 10, effects = { income = 0.25 } },
	{ id = "fated_luck", name = "Fated Luck", icon = "🌟", cost = 2, max = 10, effects = { luck = 0.05 } },
	{ id = "head_start", name = "Head Start", icon = "🚀", cost = 2, max = 5, effects = { startcash = 50000 } },
	{ id = "timeless_rest", name = "Timeless Rest", icon = "🌙", cost = 3, max = 4, effects = { offline = 2 } },
	{ id = "ascended_arms", name = "Ascended Arms", icon = "⚔️", cost = 3, max = 5, effects = { damage = 0.15, health = 0.15 } },
	{ id = "deep_pockets", name = "Deep Pockets", icon = "🎒", cost = 2, max = 4, effects = { storage = 50 } },
}
Tree.AscById = {}
for _, node in Tree.Ascension do Tree.AscById[node.id] = node end

-- price of the next rank given the current rank
function Tree.cost(node, rank: number): number
	if Tree.AscById[node.id] == node then return node.cost * (rank + 1) end
	return math.floor(node.cost * node.growth ^ rank)
end
-- why a node can't be bought right now (nil = buyable apart from price)
function Tree.blocked(node, owned, rebirths: number): string?
	local rank = owned[node.id] or 0
	if rank >= node.max then return "Maxed" end
	for _, req in node.requires or {} do
		if (owned[req] or 0) < 1 then return "Needs " .. Tree.ById[req].name end
	end
	if node.rebirth and rebirths < node.rebirth then return "Needs Rebirth " .. node.rebirth end
	return nil
end

function Tree.describe(node, rank: number?)
	if node.id == "start" then return "The root of your Evolution Tree." end
	local parts = {}
	for effect, v in node.effects do
		local e = Tree.Effects[effect]
		local value = e.pct and math.floor(v * 100 + 0.5) or v
		table.insert(parts, e.fmt:find("%%d") and e.fmt:format(value) or e.fmt)
	end
	table.sort(parts)
	return table.concat(parts, ", ") .. (node.max > 1 and " per rank" or "") .. (rank and ("  (rank " .. rank .. "/" .. node.max .. ")") or "")
end

-- sum of an effect over owned ranks; byId defaults to the Evolution Tree
function Tree.stat(owned, effect: string, byId: { [string]: any }?): number
	byId = byId or Tree.ById
	local s = 0
	for id, rank in owned do
		local node = byId[id]
		local v = node and node.effects[effect]
		if v and typeof(rank) == "number" then s += v * math.min(rank, node.max) end
	end
	return s
end
return Tree
